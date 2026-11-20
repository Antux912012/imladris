// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

#ifndef IMLADRIS_TOOLCHAIN_NATIVE_H
#define IMLADRIS_TOOLCHAIN_NATIVE_H

#include <glib.h>

G_BEGIN_DECLS

const char *imladris_toolchain_get_arch (void);

gint64 imladris_toolchain_get_dir_usage (const char *path,
                                         gboolean    deduplicate_hardlinks);

gint64 imladris_toolchain_get_free_space (const char *path);

char *imladris_toolchain_detect_pkg_version (const char *env_prefix,
                                             const char *pkg_name);

GStrv imladris_toolchain_list_python_envs (const char *mamba_root);

G_END_DECLS

#endif /* IMLADRIS_TOOLCHAIN_NATIVE_H */
