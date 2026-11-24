// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Single Responsibility: Offline-first git-commit-style synchronization engine
 * between Imladris Desktop documents and self-hosted Imladris on Web instances.
 *
 * Features:
 * - Content-addressed local object store ($XDG_DATA_HOME/imladris/web-sync/objects/<sha256>.blob)
 * - Persistent per-document workspace links & pending offline commit queues (links.json)
 * - Automatic reconnect detection (GLib.NetworkMonitor + lightweight reachability check)
 * - Automatic git-style commit creation on reconnect (or manual commit anytime)
 * - Remote divergence conflict detection (never silently overwrites teammate edits)
 * - Strict Air-Gapped Mode governance compliance
 */

using GLib;
using Json;
using Imladris.Bridges.WebSync;

namespace Imladris.Services {

    public class WebSyncService : GLib.Object {
        private static WebSyncService? instance = null;

        private WebSyncClient client;
        private Gee.HashMap<string, WebDocumentLink> links;
        private Gee.HashSet<string> syncing_docs;
        private GLib.NetworkMonitor? net_monitor = null;
        private uint reconnect_timer_id = 0;
        private bool network_available = true;

        public signal void link_updated (string doc_key);
        public signal void toast_requested (string message);
        public signal void connectivity_changed (bool online);

        public static WebSyncService get_default () {
            if (instance == null) {
                instance = new WebSyncService ();
            }
            return instance;
        }

        public WebSyncService (WebSyncClient? custom_client = null) {
            this.client = custom_client ?? WebSyncClient.get_default ();
            this.links = new Gee.HashMap<string, WebDocumentLink> ();
            this.syncing_docs = new Gee.HashSet<string> ();

            load_links_from_disk ();
            setup_network_monitor ();
        }

        ~WebSyncService () {
            if (reconnect_timer_id != 0) {
                GLib.Source.remove (reconnect_timer_id);
                reconnect_timer_id = 0;
            }
        }

        public WebSyncClient get_client () {
            return client;
        }

        public bool is_network_available () {
            if (Core.SettingsManager.get_default ().airgapped_mode) {
                return false;
            }
            return network_available;
        }

        private string get_store_dir () {
            string dir = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "imladris", "web-sync");
            GLib.DirUtils.create_with_parents (dir, 0755);
            return dir;
        }

        private string get_objects_dir () {
            string dir = GLib.Path.build_filename (get_store_dir (), "objects");
            GLib.DirUtils.create_with_parents (dir, 0755);
            return dir;
        }

        private string get_links_path () {
            return GLib.Path.build_filename (get_store_dir (), "links.json");
        }

        public string store_object_blob (string content) throws GLib.Error {
            string hash = WebSyncUtils.sha256_hex (content);
            string blob_path = GLib.Path.build_filename (get_objects_dir (), @"$hash.blob");
            if (!GLib.FileUtils.test (blob_path, GLib.FileTest.EXISTS)) {
                GLib.FileUtils.set_contents (blob_path, content);
            }
            return hash;
        }

        public string? load_object_blob (string sha256) {
            if (sha256.length == 0) return null;
            string blob_path = GLib.Path.build_filename (get_objects_dir (), @"$sha256.blob");
            if (!GLib.FileUtils.test (blob_path, GLib.FileTest.EXISTS)) return null;
            try {
                string content;
                GLib.FileUtils.get_contents (blob_path, out content);
                return content;
            } catch (GLib.Error e) {
                return null;
            }
        }

        private void setup_network_monitor () {
            net_monitor = GLib.NetworkMonitor.get_default ();
            if (net_monitor != null) {
                network_available = net_monitor.get_network_available ();
                net_monitor.network_changed.connect ((avail) => {
                    bool was_offline = !network_available;
                    network_available = avail;
                    connectivity_changed (avail && !Core.SettingsManager.get_default ().airgapped_mode);
                    if (avail && was_offline) {
                        trigger_auto_reconnect_sync ();
                    }
                });
            }

            // Periodic background check only fires if there are queued offline commits
            reconnect_timer_id = GLib.Timeout.add_seconds (30, () => {
                if (has_any_auto_sync_pending () && !Core.SettingsManager.get_default ().airgapped_mode) {
                    trigger_auto_reconnect_sync ();
                }
                return GLib.Source.CONTINUE;
            });
        }

        private bool has_any_auto_sync_pending () {
            foreach (var link in links.values) {
                if (link.auto_commit_on_reconnect && !link.has_conflict && link.pending_commits.size > 0) {
                    return true;
                }
            }
            return false;
        }

        public void trigger_auto_reconnect_sync () {
            if (Core.SettingsManager.get_default ().airgapped_mode) return;
            if (!client.is_authenticated) return;

            sync_all_pending_async.begin ((obj, res) => {
                sync_all_pending_async.end (res);
            });
        }

        public WebDocumentLink? get_link (string doc_key) {
            return links.get (doc_key);
        }

        public Gee.Collection<WebDocumentLink> list_links () {
            return links.values;
        }

        public WebSyncStatus get_status_for_doc (string doc_key) {
            if (Core.SettingsManager.get_default ().airgapped_mode) {
                return links.has_key (doc_key) ? WebSyncStatus.AIRGAPPED : WebSyncStatus.UNLINKED;
            }
            var link = links.get (doc_key);
            if (link == null) return WebSyncStatus.UNLINKED;
            if (syncing_docs.contains (doc_key)) return WebSyncStatus.SYNCING;
            if (link.has_conflict) return WebSyncStatus.CONFLICT;
            if (link.pending_commits.size > 0) return WebSyncStatus.PENDING_OFFLINE;
            if (!network_available) return WebSyncStatus.OFFLINE;
            if (link.last_error.length > 0) return WebSyncStatus.ERROR;
            return WebSyncStatus.SYNCED;
        }

        /**
         * Registers or updates a link directly (used by share flow and unit tests).
         */
        public WebDocumentLink register_link (
            string doc_key,
            string instance_url,
            string workspace_id,
            string workspace_name,
            string workspace_slug,
            string remote_rel_path,
            string initial_content,
            bool auto_commit = true
        ) throws GLib.Error {
            string sha = store_object_blob (initial_content);
            var link = new WebDocumentLink ();
            link.doc_key = doc_key;
            link.instance_url = instance_url;
            link.workspace_id = workspace_id;
            link.workspace_name = workspace_name;
            link.workspace_slug = workspace_slug;
            link.remote_rel_path = remote_rel_path;
            link.last_synced_sha256 = sha;
            link.last_synced_at = GLib.get_real_time () / 1000;
            link.auto_commit_on_reconnect = auto_commit;
            link.has_conflict = false;
            link.last_error = "";

            links.set (doc_key, link);
            save_links_to_disk ();
            link_updated (doc_key);
            return link;
        }

        public void unlink_document (string doc_key) {
            if (links.unset (doc_key)) {
                save_links_to_disk ();
                link_updated (doc_key);
            }
        }

        public void set_auto_commit (string doc_key, bool enabled) {
            var link = links.get (doc_key);
            if (link == null) return;
            link.auto_commit_on_reconnect = enabled;
            save_links_to_disk ();
            link_updated (doc_key);
        }

        /**
         * Shares a local document onto an Imladris on Web workspace and records
         * the initial git-style revision checkpoint.
         */
        public async WebDocumentLink share_document_async (
            string doc_key,
            string workspace_id,
            string workspace_name,
            string workspace_slug,
            string remote_rel_path,
            string content,
            string? initial_message = null,
            bool auto_commit = true
        ) throws GLib.Error {
            syncing_docs.add (doc_key);
            link_updated (doc_key);
            try {
                string msg = (initial_message != null && initial_message.strip ().length > 0)
                    ? initial_message.strip ()
                    : @"Initial share of $(GLib.Path.get_basename (remote_rel_path)) from Imladris Desktop";

                yield client.push_file_async (workspace_id, remote_rel_path, content);
                var rev = yield client.create_revision_async (workspace_id, remote_rel_path, msg);

                var link = register_link (
                    doc_key,
                    client.instance_url,
                    workspace_id,
                    workspace_name,
                    workspace_slug,
                    remote_rel_path,
                    content,
                    auto_commit
                );
                link.last_remote_revision_id = rev.id;
                save_links_to_disk ();
                syncing_docs.remove (doc_key);
                link_updated (doc_key);
                toast_requested (@"Shared '$(remote_rel_path)' to $(workspace_name) ($(rev.short_hash ()))");
                return link;
            } catch (GLib.Error e) {
                syncing_docs.remove (doc_key);
                link_updated (doc_key);
                throw e;
            }
        }

        /**
         * Queues a local offline git-style commit into the content-addressed object store.
         * Deduplicates if the latest local commit already has the identical SHA-256.
         */
        public WebOfflineCommit? queue_offline_commit (
            string doc_key,
            string content,
            string? custom_message = null,
            bool is_auto = false
        ) throws GLib.Error {
            var link = links.get (doc_key);
            if (link == null) {
                throw new WebSyncError.NOT_FOUND ("Document is not linked to an Imladris on Web workspace.");
            }

            string new_sha = store_object_blob (content);
            string parent_sha = link.get_latest_local_sha256 ();
            if (new_sha == parent_sha) {
                return null; // Nothing changed since last commit/sync
            }

            string? prev_content = load_object_blob (parent_sha);
            var diff = WebSyncUtils.compute_diff_summary (prev_content ?? "", content);

            string msg = (custom_message != null && custom_message.strip ().length > 0)
                ? custom_message.strip ()
                : WebSyncUtils.format_auto_commit_message (link.remote_rel_path, diff, true);

            string author = (client.current_user != null && client.current_user.display_name.length > 0)
                ? client.current_user.display_name
                : GLib.Environment.get_user_name ();

            var commit = new WebOfflineCommit (
                GLib.Uuid.string_random (),
                msg,
                new_sha,
                parent_sha,
                author,
                GLib.get_real_time () / 1000,
                is_auto,
                diff.added,
                diff.removed
            );
            link.pending_commits.add (commit);
            link.last_error = "";
            save_links_to_disk ();
            link_updated (doc_key);
            return commit;
        }

        /**
         * Commits document changes in git style:
         * - If online & authenticated, pushes immediately (after replaying any queued offline commits).
         * - If offline or unreachable, stores a local offline commit to push automatically on reconnect or manually later.
         */
        public async bool commit_document_async (
            string doc_key,
            string content,
            string? custom_message = null,
            bool is_auto = false,
            bool force_overwrite = false
        ) throws GLib.Error {
            var link = links.get (doc_key);
            if (link == null) {
                throw new WebSyncError.NOT_FOUND ("Document is not linked to an Imladris on Web workspace.");
            }

            var queued = queue_offline_commit (doc_key, content, custom_message, is_auto);
            if (queued == null && link.pending_commits.size == 0) {
                toast_requested ("No changes to commit (already up to date)");
                return true;
            }

            if (Core.SettingsManager.get_default ().airgapped_mode || !network_available || !client.is_authenticated) {
                if (queued != null) {
                    toast_requested (@"Committed offline [$(queued.short_hash ())] — will sync when online");
                }
                return false;
            }

            return yield sync_pending_commits_async (doc_key, null, force_overwrite);
        }

        /**
         * Replays queued offline commits sequentially against Imladris on Web.
         * If current_live_content is provided and auto_commit_on_reconnect is enabled,
         * also auto-commits any uncommitted local changes before pushing.
         */
        public async bool sync_pending_commits_async (
            string doc_key,
            string? current_live_content = null,
            bool force_overwrite = false
        ) throws GLib.Error {
            var link = links.get (doc_key);
            if (link == null) return false;
            if (syncing_docs.contains (doc_key)) return false;

            if (Core.SettingsManager.get_default ().airgapped_mode) {
                throw new WebSyncError.AIRGAPPED_BLOCKED ("Air-Gapped Mode blocks web synchronization.");
            }

            // If live content has uncommitted offline edits and auto-commit is enabled, queue an auto commit
            if (current_live_content != null && link.auto_commit_on_reconnect) {
                queue_offline_commit (doc_key, current_live_content, null, true);
            }

            if (link.pending_commits.size == 0) {
                return true;
            }

            syncing_docs.add (doc_key);
            link.last_error = "";
            link_updated (doc_key);

            try {
                // Ensure client targets the link's configured instance URL
                if (link.instance_url.length > 0 && client.instance_url != link.instance_url) {
                    client.instance_url = link.instance_url;
                }

                // 1. Conflict safety check: verify remote hasn't diverged since last_synced_sha256
                if (!force_overwrite && link.last_synced_sha256.length > 0) {
                    try {
                        string remote_content = yield client.pull_file_async (link.workspace_id, link.remote_rel_path);
                        string remote_sha = WebSyncUtils.sha256_hex (remote_content);
                        if (remote_sha != link.last_synced_sha256) {
                            link.has_conflict = true;
                            link.last_error = "Remote document changed on Imladris on Web while you were offline.";
                            save_links_to_disk ();
                            syncing_docs.remove (doc_key);
                            link_updated (doc_key);
                            toast_requested (@"Sync conflict on $(link.remote_rel_path) — review in Imladris Web panel");
                            return false;
                        }
                    } catch (WebSyncError.NOT_FOUND nf) {
                        // File does not yet exist remotely; safe to push
                    }
                }

                // 2. Replay each queued commit in chronological order
                int pushed_count = 0;
                while (link.pending_commits.size > 0) {
                    var commit = link.pending_commits.get (0);
                    string? blob_text = load_object_blob (commit.sha256);
                    if (blob_text == null) {
                        link.pending_commits.remove_at (0);
                        continue;
                    }

                    yield client.push_file_async (link.workspace_id, link.remote_rel_path, blob_text);
                    var rev = yield client.create_revision_async (link.workspace_id, link.remote_rel_path, commit.message);

                    link.last_synced_sha256 = commit.sha256;
                    link.last_remote_revision_id = rev.id;
                    link.last_synced_at = rev.updated_at;
                    link.has_conflict = false;
                    link.last_error = "";
                    link.pending_commits.remove_at (0);
                    save_links_to_disk ();
                    pushed_count++;
                }

                syncing_docs.remove (doc_key);
                link_updated (doc_key);
                if (pushed_count > 0) {
                    string noun = pushed_count == 1 ? "commit" : "commits";
                    toast_requested (@"Synced $pushed_count $noun to $(link.workspace_name) on Imladris Web");
                }
                return true;
            } catch (WebSyncError.OFFLINE off_err) {
                link.last_error = "";
                syncing_docs.remove (doc_key);
                link_updated (doc_key);
                return false;
            } catch (GLib.Error e) {
                link.last_error = e.message;
                save_links_to_disk ();
                syncing_docs.remove (doc_key);
                link_updated (doc_key);
                throw e;
            }
        }

        public async void sync_all_pending_async () {
            if (Core.SettingsManager.get_default ().airgapped_mode) return;
            bool healthy = yield client.probe_health_async ();
            if (!healthy) return;

            var keys = new Gee.ArrayList<string> ();
            foreach (var entry in links.entries) {
                if (entry.value.auto_commit_on_reconnect && !entry.value.has_conflict && entry.value.pending_commits.size > 0) {
                    keys.add (entry.key);
                }
            }
            foreach (string key in keys) {
                try {
                    // If the document is on disk, read latest file text for auto-commit reconciliation
                    string? disk_text = null;
                    if (GLib.Path.is_absolute (key) && GLib.FileUtils.test (key, GLib.FileTest.EXISTS)) {
                        try {
                            GLib.FileUtils.get_contents (key, out disk_text);
                        } catch (GLib.Error e) {}
                    }
                    yield sync_pending_commits_async (key, disk_text, false);
                } catch (GLib.Error e) {
                    GLib.debug ("Auto-reconnect sync skipped for %s: %s", key, e.message);
                }
            }
        }

        /**
         * Hook invoked whenever a document is saved via Ctrl+S.
         * When linked to Imladris on Web with auto-commit enabled:
         * - Offline: records a local git-style offline commit cleanly in the queue.
         * - Online: pushes an auto-commit checkpoint asynchronously.
         */
        public void on_document_saved (string doc_key, string content) {
            var link = links.get (doc_key);
            if (link == null || !link.auto_commit_on_reconnect) return;

            string current_sha = WebSyncUtils.sha256_hex (content);
            if (current_sha == link.get_latest_local_sha256 ()) return;

            commit_document_async.begin (doc_key, content, null, true, false, (obj, res) => {
                try {
                    commit_document_async.end (res);
                } catch (GLib.Error e) {
                    GLib.debug ("WebSyncService save hook error for %s: %s", doc_key, e.message);
                }
            });
        }

        public async string pull_remote_document_async (string doc_key) throws GLib.Error {
            var link = links.get (doc_key);
            if (link == null) {
                throw new WebSyncError.NOT_FOUND ("Document is not linked to Imladris on Web.");
            }
            if (link.instance_url.length > 0 && client.instance_url != link.instance_url) {
                client.instance_url = link.instance_url;
            }
            string remote_content = yield client.pull_file_async (link.workspace_id, link.remote_rel_path);
            string sha = store_object_blob (remote_content);
            link.last_synced_sha256 = sha;
            link.last_synced_at = GLib.get_real_time () / 1000;
            link.has_conflict = false;
            link.last_error = "";
            link.pending_commits.clear ();
            save_links_to_disk ();
            link_updated (doc_key);
            toast_requested (@"Pulled latest '$(link.remote_rel_path)' from Imladris Web");
            return remote_content;
        }

        public void save_links_to_disk () {
            try {
                var b = new Json.Builder ();
                b.begin_object ();
                b.set_member_name ("version");
                b.add_int_value (1);
                b.set_member_name ("links");
                b.begin_array ();
                foreach (var link in links.values) {
                    b.begin_object ();
                    b.set_member_name ("docKey");
                    b.add_string_value (link.doc_key);
                    b.set_member_name ("instanceUrl");
                    b.add_string_value (link.instance_url);
                    b.set_member_name ("workspaceId");
                    b.add_string_value (link.workspace_id);
                    b.set_member_name ("workspaceName");
                    b.add_string_value (link.workspace_name);
                    b.set_member_name ("workspaceSlug");
                    b.add_string_value (link.workspace_slug);
                    b.set_member_name ("remoteRelPath");
                    b.add_string_value (link.remote_rel_path);
                    b.set_member_name ("lastSyncedSha256");
                    b.add_string_value (link.last_synced_sha256);
                    b.set_member_name ("lastRemoteRevisionId");
                    b.add_string_value (link.last_remote_revision_id);
                    b.set_member_name ("lastSyncedAt");
                    b.add_int_value (link.last_synced_at);
                    b.set_member_name ("autoCommitOnReconnect");
                    b.add_boolean_value (link.auto_commit_on_reconnect);
                    b.set_member_name ("hasConflict");
                    b.add_boolean_value (link.has_conflict);
                    b.set_member_name ("lastError");
                    b.add_string_value (link.last_error);

                    b.set_member_name ("pendingCommits");
                    b.begin_array ();
                    foreach (var c in link.pending_commits) {
                        b.begin_object ();
                        b.set_member_name ("id");
                        b.add_string_value (c.id);
                        b.set_member_name ("message");
                        b.add_string_value (c.message);
                        b.set_member_name ("sha256");
                        b.add_string_value (c.sha256);
                        b.set_member_name ("parentSha256");
                        b.add_string_value (c.parent_sha256);
                        b.set_member_name ("author");
                        b.add_string_value (c.author);
                        b.set_member_name ("createdAt");
                        b.add_int_value (c.created_at);
                        b.set_member_name ("isAuto");
                        b.add_boolean_value (c.is_auto);
                        b.set_member_name ("linesAdded");
                        b.add_int_value (c.lines_added);
                        b.set_member_name ("linesRemoved");
                        b.add_int_value (c.lines_removed);
                        b.end_object ();
                    }
                    b.end_array ();
                    b.end_object ();
                }
                b.end_array ();
                b.end_object ();

                var gen = new Json.Generator ();
                gen.set_root (b.get_root ());
                gen.pretty = true;
                GLib.FileUtils.set_contents (get_links_path (), gen.to_data (null));
            } catch (GLib.Error e) {
                warning ("WebSyncService: failed to save links: %s", e.message);
            }
        }

        public void load_links_from_disk () {
            string path = get_links_path ();
            if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) return;
            try {
                string raw;
                GLib.FileUtils.get_contents (path, out raw);
                var parser = new Json.Parser ();
                parser.load_from_data (raw, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return;
                var obj = root.get_object ();
                if (!obj.has_member ("links")) return;
                var arr = obj.get_array_member ("links");
                links.clear ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    var lo = arr.get_object_element (i);
                    var link = new WebDocumentLink ();
                    link.doc_key = lo.has_member ("docKey") ? lo.get_string_member ("docKey") : "";
                    if (link.doc_key.length == 0) continue;
                    link.instance_url = lo.has_member ("instanceUrl") ? lo.get_string_member ("instanceUrl") : "";
                    link.workspace_id = lo.has_member ("workspaceId") ? lo.get_string_member ("workspaceId") : "";
                    link.workspace_name = lo.has_member ("workspaceName") ? lo.get_string_member ("workspaceName") : "";
                    link.workspace_slug = lo.has_member ("workspaceSlug") ? lo.get_string_member ("workspaceSlug") : "";
                    link.remote_rel_path = lo.has_member ("remoteRelPath") ? lo.get_string_member ("remoteRelPath") : "";
                    link.last_synced_sha256 = lo.has_member ("lastSyncedSha256") ? lo.get_string_member ("lastSyncedSha256") : "";
                    link.last_remote_revision_id = lo.has_member ("lastRemoteRevisionId") ? lo.get_string_member ("lastRemoteRevisionId") : "";
                    link.last_synced_at = lo.has_member ("lastSyncedAt") ? lo.get_int_member ("lastSyncedAt") : 0;
                    link.auto_commit_on_reconnect = lo.has_member ("autoCommitOnReconnect") ? lo.get_boolean_member ("autoCommitOnReconnect") : true;
                    link.has_conflict = lo.has_member ("hasConflict") ? lo.get_boolean_member ("hasConflict") : false;
                    link.last_error = lo.has_member ("lastError") ? lo.get_string_member ("lastError") : "";

                    if (lo.has_member ("pendingCommits")) {
                        var pc_arr = lo.get_array_member ("pendingCommits");
                        for (uint j = 0; j < pc_arr.get_length (); j++) {
                            var co = pc_arr.get_object_element (j);
                            link.pending_commits.add (new WebOfflineCommit (
                                co.has_member ("id") ? co.get_string_member ("id") : "",
                                co.has_member ("message") ? co.get_string_member ("message") : "",
                                co.has_member ("sha256") ? co.get_string_member ("sha256") : "",
                                co.has_member ("parentSha256") ? co.get_string_member ("parentSha256") : "",
                                co.has_member ("author") ? co.get_string_member ("author") : "",
                                co.has_member ("createdAt") ? co.get_int_member ("createdAt") : 0,
                                co.has_member ("isAuto") ? co.get_boolean_member ("isAuto") : false,
                                co.has_member ("linesAdded") ? (int) co.get_int_member ("linesAdded") : 0,
                                co.has_member ("linesRemoved") ? (int) co.get_int_member ("linesRemoved") : 0
                            ));
                        }
                    }
                    links.set (link.doc_key, link);
                }
            } catch (GLib.Error e) {
                warning ("WebSyncService: failed to load links: %s", e.message);
            }
        }
    }
}
