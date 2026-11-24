// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Imladris.Bridges.WebSync;
using Imladris.Services;

namespace Imladris.Tests {

    public class WebSyncTests : GLib.Object {

        public static void register_tests () {
            Test.add_func ("/web_sync/sha256_and_diff_summary", test_sha256_and_diff_summary);
            Test.add_func ("/web_sync/offline_commit_queue_and_persistence", test_offline_commit_queue_and_persistence);
            Test.add_func ("/web_sync/deduplicate_identical_commits", test_deduplicate_identical_commits);
            Test.add_func ("/web_sync/airgapped_mode_governance", test_airgapped_mode_governance);
        }

        private static void test_sha256_and_diff_summary () {
            string h1 = WebSyncUtils.sha256_hex ("# Title\nline 1\n");
            string h2 = WebSyncUtils.sha256_hex ("# Title\nline 1\n");
            string h3 = WebSyncUtils.sha256_hex ("# Title\nline 1\nline 2\n");
            assert (h1 == h2);
            assert (h1 != h3);
            assert (h1.length == 64);

            var same = WebSyncUtils.compute_diff_summary ("a\nb", "a\nb");
            assert (!same.changed);
            assert (same.added == 0 && same.removed == 0);

            var diff = WebSyncUtils.compute_diff_summary ("a\nb\nc", "a\nx\nc\nd");
            assert (diff.changed);
            assert (diff.added == 2);
            assert (diff.removed == 1);

            string auto_msg = WebSyncUtils.format_auto_commit_message ("/tmp/study/report.qmd", diff, true);
            assert (auto_msg.contains ("offline(auto)"));
            assert (auto_msg.contains ("report.qmd"));
            assert (auto_msg.contains ("+2/-1"));
        }

        private static void test_offline_commit_queue_and_persistence () {
            var svc = new WebSyncService (new WebSyncClient ());
            string doc_key = "/tmp/imladris-test/analysis.qmd";
            string v0 = "---\ntitle: Study\n---\n\nInitial version.\n";

            try {
                var link = svc.register_link (
                    doc_key,
                    "http://localhost:8787",
                    "ws-123",
                    "Biostats Lab",
                    "biostats-lab-abc",
                    "analysis.qmd",
                    v0,
                    true
                );
                assert (link.workspace_id == "ws-123");
                assert (link.pending_commits.size == 0);
                assert (svc.get_status_for_doc (doc_key) == WebSyncStatus.SYNCED ||
                        svc.get_status_for_doc (doc_key) == WebSyncStatus.OFFLINE);

                // Work offline: commit v1 manually
                string v1 = v0 + "\n## Methods\nLogistic regression.\n";
                var c1 = svc.queue_offline_commit (doc_key, v1, "feat(methods): add logistic regression section", false);
                assert (c1 != null);
                assert (c1.parent_sha256 == link.last_synced_sha256);
                assert (!c1.is_auto);
                assert (c1.message == "feat(methods): add logistic regression section");
                assert (svc.load_object_blob (c1.sha256) == v1);

                // Work offline: commit v2 automatically
                string v2 = v1 + "\n## Results\np < 0.001\n";
                var c2 = svc.queue_offline_commit (doc_key, v2, null, true);
                assert (c2 != null);
                assert (c2.parent_sha256 == c1.sha256);
                assert (c2.is_auto);
                assert (svc.load_object_blob (c2.sha256) == v2);
                assert (svc.get_status_for_doc (doc_key) == WebSyncStatus.PENDING_OFFLINE);

                // Reload service from disk and verify queue & blobs survived restart
                var svc2 = new WebSyncService (new WebSyncClient ());
                var loaded = svc2.get_link (doc_key);
                assert (loaded != null);
                assert (loaded.workspace_name == "Biostats Lab");
                assert (loaded.pending_commits.size == 2);
                assert (loaded.pending_commits.get (0).message == "feat(methods): add logistic regression section");
                assert (loaded.pending_commits.get (1).parent_sha256 == c1.sha256);
                assert (svc2.load_object_blob (loaded.pending_commits.get (1).sha256) == v2);

                svc2.unlink_document (doc_key);
                assert (svc2.get_link (doc_key) == null);
            } catch (GLib.Error e) {
                assert_not_reached ();
            }
        }

        private static void test_deduplicate_identical_commits () {
            var svc = new WebSyncService (new WebSyncClient ());
            string doc_key = "/tmp/imladris-test/dedup.qmd";
            string v0 = "Hello world\n";
            try {
                svc.register_link (doc_key, "http://localhost:8787", "ws-1", "Lab", "lab", "dedup.qmd", v0, true);
                // Identical content should NOT create a duplicate commit
                var noop = svc.queue_offline_commit (doc_key, v0, "noop", false);
                assert (noop == null);

                var c1 = svc.queue_offline_commit (doc_key, v0 + "edit 1\n", "edit 1", false);
                assert (c1 != null);
                var noop2 = svc.queue_offline_commit (doc_key, v0 + "edit 1\n", "duplicate save", true);
                assert (noop2 == null);
                assert (svc.get_link (doc_key).pending_commits.size == 1);
            } catch (GLib.Error e) {
                assert_not_reached ();
            }
        }

        private static void test_airgapped_mode_governance () {
            var sm = Core.SettingsManager.get_default ();
            bool prev = sm.airgapped_mode;
            sm.airgapped_mode = true;

            var svc = new WebSyncService (new WebSyncClient ());
            string doc_key = "/tmp/imladris-test/airgap.qmd";
            try {
                svc.register_link (doc_key, "http://localhost:8787", "ws-ag", "Secure Lab", "secure", "airgap.qmd", "v0", true);
                assert (!svc.is_network_available ());
                assert (svc.get_status_for_doc (doc_key) == WebSyncStatus.AIRGAPPED);
            } catch (GLib.Error e) {
                assert_not_reached ();
            } finally {
                sm.airgapped_mode = prev;
            }
        }
    }

    public static int main (string[] args) {
        string tmp_xdg = "";
        try {
            tmp_xdg = GLib.DirUtils.make_tmp ("imladris-websync-test-XXXXXX");
            GLib.Environment.set_variable ("XDG_CONFIG_HOME", GLib.Path.build_filename (tmp_xdg, "config"), true);
            GLib.Environment.set_variable ("XDG_DATA_HOME", GLib.Path.build_filename (tmp_xdg, "data"), true);
            GLib.Environment.set_variable ("XDG_CACHE_HOME", GLib.Path.build_filename (tmp_xdg, "cache"), true);
        } catch (GLib.Error e) {
            warning ("Temp dir setup failed: %s", e.message);
        }

        Test.init (ref args);
        WebSyncTests.register_tests ();
        int rc = Test.run ();

        if (tmp_xdg != "") {
            Core.PlatformUtils.delete_directory_recursive (GLib.File.new_for_path (tmp_xdg));
        }
        return rc;
    }
}
