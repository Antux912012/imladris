// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Bridges.WebSync {

    public errordomain WebSyncError {
        AIRGAPPED_BLOCKED,
        OFFLINE,
        UNAUTHORIZED,
        FORBIDDEN,
        NOT_FOUND,
        CONFLICT,
        SERVER_ERROR,
        NETWORK_ERROR,
        INVALID_DATA
    }

    public enum WebSyncStatus {
        UNLINKED,
        SYNCED,
        PENDING_OFFLINE,
        SYNCING,
        CONFLICT,
        OFFLINE,
        AIRGAPPED,
        ERROR;

        public string to_badge_label (int pending_count = 0) {
            switch (this) {
                case SYNCED: return "Web: Synced";
                case PENDING_OFFLINE:
                    return pending_count == 1
                        ? "Web: 1 Offline Commit"
                        : @"Web: $pending_count Offline Commits";
                case SYNCING: return "Web: Syncing…";
                case CONFLICT: return "Web: Conflict";
                case OFFLINE: return "Web: Offline";
                case AIRGAPPED: return "Web: Air-Gapped";
                case ERROR: return "Web: Sync Error";
                case UNLINKED:
                default: return "Imladris Web";
            }
        }

        public string to_css_class () {
            switch (this) {
                case SYNCED: return "synced";
                case PENDING_OFFLINE:
                case SYNCING: return "pending";
                case CONFLICT:
                case ERROR: return "conflict";
                case OFFLINE:
                case AIRGAPPED:
                case UNLINKED:
                default: return "offline";
            }
        }
    }

    public class WebUser : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string email { get; construct set; default = ""; }
        public string display_name { get; construct set; default = ""; }
        public string avatar_color { get; construct set; default = "#3584e4"; }

        public WebUser (string id, string email, string display_name, string avatar_color = "#3584e4") {
            Object (id: id, email: email, display_name: display_name, avatar_color: avatar_color);
        }
    }

    public class WebWorkspace : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string slug { get; construct set; default = ""; }
        public string name { get; construct set; default = ""; }
        public string role { get; construct set; default = "OWNER"; }
        public string kernel_mode { get; construct set; default = "SHARED"; }

        public WebWorkspace (string id, string slug, string name, string role = "OWNER", string kernel_mode = "SHARED") {
            Object (id: id, slug: slug, name: name, role: role, kernel_mode: kernel_mode);
        }
    }

    public class WebRevision : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string rel_path { get; construct set; default = ""; }
        public string sha256_hash { get; construct set; default = ""; }
        public string message { get; construct set; default = ""; }
        public bool is_checkpoint { get; construct set; default = true; }
        public string updated_by_name { get; construct set; default = ""; }
        public int64 updated_at { get; construct set; default = 0; }

        public WebRevision (
            string id,
            string rel_path,
            string sha256_hash,
            string message,
            bool is_checkpoint,
            string updated_by_name,
            int64 updated_at
        ) {
            Object (
                id: id,
                rel_path: rel_path,
                sha256_hash: sha256_hash,
                message: message,
                is_checkpoint: is_checkpoint,
                updated_by_name: updated_by_name,
                updated_at: updated_at
            );
        }

        public string short_hash () {
            return sha256_hash.length >= 8 ? sha256_hash.substring (0, 8) : sha256_hash;
        }
    }

    public class WebOfflineCommit : GLib.Object {
        public string id { get; set; default = ""; }
        public string message { get; set; default = ""; }
        public string sha256 { get; set; default = ""; }
        public string parent_sha256 { get; set; default = ""; }
        public string author { get; set; default = ""; }
        public int64 created_at { get; set; default = 0; }
        public bool is_auto { get; set; default = false; }
        public int lines_added { get; set; default = 0; }
        public int lines_removed { get; set; default = 0; }

        public WebOfflineCommit (
            string id,
            string message,
            string sha256,
            string parent_sha256,
            string author,
            int64 created_at,
            bool is_auto = false,
            int lines_added = 0,
            int lines_removed = 0
        ) {
            this.id = id;
            this.message = message;
            this.sha256 = sha256;
            this.parent_sha256 = parent_sha256;
            this.author = author;
            this.created_at = created_at;
            this.is_auto = is_auto;
            this.lines_added = lines_added;
            this.lines_removed = lines_removed;
        }

        public string short_hash () {
            return sha256.length >= 8 ? sha256.substring (0, 8) : sha256;
        }
    }

    public class WebDocumentLink : GLib.Object {
        public string doc_key { get; set; default = ""; }
        public string instance_url { get; set; default = ""; }
        public string workspace_id { get; set; default = ""; }
        public string workspace_name { get; set; default = ""; }
        public string workspace_slug { get; set; default = ""; }
        public string remote_rel_path { get; set; default = ""; }
        public string last_synced_sha256 { get; set; default = ""; }
        public string last_remote_revision_id { get; set; default = ""; }
        public int64 last_synced_at { get; set; default = 0; }
        public bool auto_commit_on_reconnect { get; set; default = true; }
        public bool has_conflict { get; set; default = false; }
        public string last_error { get; set; default = ""; }
        public Gee.ArrayList<WebOfflineCommit> pending_commits { get; owned set; }

        public WebDocumentLink () {
            pending_commits = new Gee.ArrayList<WebOfflineCommit> ();
        }

        public string get_latest_local_sha256 () {
            if (pending_commits.size > 0) {
                return pending_commits.get (pending_commits.size - 1).sha256;
            }
            return last_synced_sha256;
        }

        public string get_web_workspace_url () {
            string base_u = instance_url.strip ();
            while (base_u.has_suffix ("/")) {
                base_u = base_u.substring (0, base_u.length - 1);
            }
            return @"$base_u/workspaces/$workspace_id";
        }
    }

    public struct DiffSummary {
        public int added;
        public int removed;
        public bool changed;
    }

    public class WebSyncUtils : GLib.Object {

        public static string sha256_hex (string text) {
            return GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA256, text, -1);
        }

        public static DiffSummary compute_diff_summary (string old_text, string new_text) {
            if (old_text == new_text) {
                return DiffSummary () { added = 0, removed = 0, changed = false };
            }
            string[] old_lines = old_text.length > 0 ? old_text.split ("\n") : new string[0];
            string[] new_lines = new_text.length > 0 ? new_text.split ("\n") : new string[0];

            var old_counts = new GLib.HashTable<string, int> (GLib.str_hash, GLib.str_equal);
            foreach (string l in old_lines) {
                old_counts.insert (l, old_counts.lookup (l) + 1);
            }

            var new_counts = new GLib.HashTable<string, int> (GLib.str_hash, GLib.str_equal);
            foreach (string l in new_lines) {
                new_counts.insert (l, new_counts.lookup (l) + 1);
            }

            int added = 0;
            foreach (string l in new_counts.get_keys ()) {
                int nc = new_counts.lookup (l);
                int oc = old_counts.lookup (l);
                if (nc > oc) added += (nc - oc);
            }

            int removed = 0;
            foreach (string l in old_counts.get_keys ()) {
                int oc = old_counts.lookup (l);
                int nc = new_counts.lookup (l);
                if (oc > nc) removed += (oc - nc);
            }

            return DiffSummary () { added = added, removed = removed, changed = true };
        }

        public static string format_auto_commit_message (string filename, DiffSummary diff, bool offline) {
            string base_name = GLib.Path.get_basename (filename);
            string prefix = offline ? "offline(auto)" : "sync(auto)";
            if (!diff.changed) {
                return @"$prefix: checkpoint $base_name";
            }
            return @"$prefix: update $base_name (+$(diff.added)/-$(diff.removed) lines)";
        }

        public static string format_timestamp (int64 epoch_ms) {
            if (epoch_ms <= 0) return "Never";
            var dt = new GLib.DateTime.from_unix_local (epoch_ms / 1000);
            return dt.format ("%Y-%m-%d %H:%M");
        }
    }
}
