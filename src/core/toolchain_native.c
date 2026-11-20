// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

#define _GNU_SOURCE
#include "toolchain_native.h"

#include <dirent.h>
#include <errno.h>
#include <fts.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/utsname.h>
#include <unistd.h>

typedef struct {
    dev_t dev;
    ino_t ino;
} ImladrisInodeKey;

static guint
inode_key_hash (gconstpointer v)
{
    const ImladrisInodeKey *k = (const ImladrisInodeKey *) v;
    guint64 mixed = ((guint64) k->dev << 32) ^ (guint64) k->ino;
    return g_int64_hash (&mixed);
}

static gboolean
inode_key_equal (gconstpointer a, gconstpointer b)
{
    const ImladrisInodeKey *ka = (const ImladrisInodeKey *) a;
    const ImladrisInodeKey *kb = (const ImladrisInodeKey *) b;
    return ka->dev == kb->dev && ka->ino == kb->ino;
}

const char *
imladris_toolchain_get_arch (void)
{
    static gsize init_guard = 0;
    static const char *cached = "linux-64";

    if (g_once_init_enter (&init_guard)) {
        struct utsname u;
        if (uname (&u) == 0) {
            if (g_strcmp0 (u.machine, "aarch64") == 0 ||
                g_strcmp0 (u.machine, "arm64") == 0) {
                cached = "linux-aarch64";
            }
        }
        g_once_init_leave (&init_guard, 1);
    }

    return cached;
}

gint64
imladris_toolchain_get_dir_usage (const char *path,
                                  gboolean    deduplicate_hardlinks)
{
    if (path == NULL || path[0] == '\0') {
        return 0;
    }

    struct stat root_st;
    if (lstat (path, &root_st) != 0 || !S_ISDIR (root_st.st_mode)) {
        return 0;
    }

    char *paths[2] = { (char *) path, NULL };
    FTS *tree = fts_open (paths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
    if (tree == NULL) {
        return 0;
    }

    GHashTable *seen_inodes = NULL;
    if (deduplicate_hardlinks) {
        seen_inodes = g_hash_table_new_full (inode_key_hash, inode_key_equal, g_free, NULL);
    }

    gint64 total = 0;
    FTSENT *ent;
    while ((ent = fts_read (tree)) != NULL) {
        if (ent->fts_info == FTS_F && ent->fts_statp != NULL) {
            if (seen_inodes != NULL && ent->fts_statp->st_nlink > 1) {
                ImladrisInodeKey probe = {
                    .dev = ent->fts_statp->st_dev,
                    .ino = ent->fts_statp->st_ino
                };
                if (g_hash_table_contains (seen_inodes, &probe)) {
                    continue;
                }
                ImladrisInodeKey *owned = g_new (ImladrisInodeKey, 1);
                *owned = probe;
                g_hash_table_add (seen_inodes, owned);
            }
            total += (gint64) ent->fts_statp->st_size;
        }
    }

    if (seen_inodes != NULL) {
        g_hash_table_unref (seen_inodes);
    }
    fts_close (tree);
    return total;
}

gint64
imladris_toolchain_get_free_space (const char *path)
{
    if (path == NULL || path[0] == '\0') {
        return -1;
    }

    g_autofree char *cur = g_strdup (path);
    while (access (cur, F_OK) != 0) {
        g_autofree char *parent = g_path_get_dirname (cur);
        if (g_strcmp0 (parent, cur) == 0) {
            return -1;
        }
        g_free (cur);
        cur = g_steal_pointer (&parent);
    }

    struct statvfs st;
    if (statvfs (cur, &st) != 0) {
        return -1;
    }

    return (gint64) st.f_bavail * (gint64) st.f_frsize;
}

static char *
extract_json_version_field (const char *json_buf, gsize len)
{
    if (json_buf == NULL || len == 0) {
        return NULL;
    }

    const char *p = g_strstr_len (json_buf, (gssize) len, "\"version\"");
    if (p == NULL) {
        return NULL;
    }
    p += 9; /* strlen("\"version\"") */

    const char *end = json_buf + len;
    while (p < end && (*p == ' ' || *p == '\t' || *p == ':')) {
        p++;
    }
    if (p >= end || *p != '"') {
        return NULL;
    }
    p++;

    const char *q = memchr (p, '"', (size_t) (end - p));
    if (q == NULL || q == p) {
        return NULL;
    }

    return g_strndup (p, (gsize) (q - p));
}

char *
imladris_toolchain_detect_pkg_version (const char *env_prefix,
                                       const char *pkg_name)
{
    if (env_prefix == NULL || pkg_name == NULL || pkg_name[0] == '\0') {
        return NULL;
    }

    g_autofree char *meta_dir = g_build_filename (env_prefix, "conda-meta", NULL);
    DIR *dir = opendir (meta_dir);
    if (dir == NULL) {
        return NULL;
    }

    gsize pkg_len = strlen (pkg_name);
    char *version = NULL;
    struct dirent *de;

    while ((de = readdir (dir)) != NULL) {
        const char *name = de->d_name;
        gsize name_len = strlen (name);

        if (name_len <= pkg_len + 6) { /* <pkg>-<digit>...json */
            continue;
        }
        if (strncmp (name, pkg_name, pkg_len) != 0 || name[pkg_len] != '-') {
            continue;
        }
        if (!g_ascii_isdigit (name[pkg_len + 1])) {
            continue;
        }
        if (strcmp (name + name_len - 5, ".json") != 0) {
            continue;
        }

        g_autofree char *meta_path = g_build_filename (meta_dir, name, NULL);
        g_autofree char *contents = NULL;
        gsize length = 0;
        if (g_file_get_contents (meta_path, &contents, &length, NULL)) {
            version = extract_json_version_field (contents, length);
            if (version != NULL) {
                break;
            }
        }
    }

    closedir (dir);
    return version;
}

GStrv
imladris_toolchain_list_python_envs (const char *mamba_root)
{
    GPtrArray *arr = g_ptr_array_new ();

    if (mamba_root != NULL && mamba_root[0] != '\0') {
        g_autofree char *envs_dir = g_build_filename (mamba_root, "envs", NULL);
        DIR *dir = opendir (envs_dir);
        if (dir != NULL) {
            struct dirent *de;
            while ((de = readdir (dir)) != NULL) {
                if (de->d_name[0] == '.') {
                    continue;
                }
                g_autofree char *env_path = g_build_filename (envs_dir, de->d_name, NULL);
                g_autofree char *py_bin = g_build_filename (env_path, "bin", "python3", NULL);
                if (access (py_bin, X_OK) == 0) {
                    g_ptr_array_add (arr, g_steal_pointer (&env_path));
                }
            }
            closedir (dir);
        }
    }

    g_ptr_array_add (arr, NULL);
    return (GStrv) g_ptr_array_free (arr, FALSE);
}
