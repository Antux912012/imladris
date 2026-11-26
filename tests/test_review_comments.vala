// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Imladris.Core;

namespace Imladris.Tests {

    public static void test_sidecar_path_resolution () {
        string proj_sidecar = ReviewCommentStore.resolve_sidecar_path (
            "/tmp/my_project/reports/analysis.qmd",
            "/tmp/my_project"
        );
        assert (proj_sidecar == "/tmp/my_project/.imladris/reviews/reports__analysis.qmd.comments.json");

        string standalone_sidecar = ReviewCommentStore.resolve_sidecar_path ("/tmp/standalone.qmd", null);
        assert (standalone_sidecar == "/tmp/.standalone.qmd.imladris-comments.json");
    }

    public static void test_json_roundtrip_and_merge () {
        var store_a = new ReviewCommentStore ();
        var anchor = new ReviewAnchor (10, 12, 0, 15, "fit <- lm(y ~ x, data = df)", "# Model", "summary(fit)");
        var t1 = new ReviewThread (anchor, "Statistics", "thread-1");
        t1.messages.add (new ReviewMessage ("Prof. Rossi", "Professor", "Check heteroskedasticity here.", "msg-1", "2026-11-26 10:00"));
        store_a.threads.add (t1);

        string json = store_a.serialize_json ();
        ReviewCommentStore parsed;
        try {
            parsed = ReviewCommentStore.deserialize_json (json);
        } catch (GLib.Error e) {
            assert_not_reached ();
        }

        assert (parsed.threads.size == 1);
        assert (parsed.threads[0].thread_id == "thread-1");
        assert (parsed.threads[0].anchor.start_line == 10);
        assert (parsed.threads[0].anchor.end_line == 12);
        assert (parsed.threads[0].messages.size == 1);
        assert (parsed.threads[0].messages[0].author == "Prof. Rossi");

        var store_b = new ReviewCommentStore ();
        var t1_reply = new ReviewThread (anchor, "Statistics", "thread-1");
        t1_reply.messages.add (new ReviewMessage ("Prof. Rossi", "Professor", "Check heteroskedasticity here.", "msg-1", "2026-11-26 10:00"));
        t1_reply.messages.add (new ReviewMessage ("Student", "Student", "Added HC3 robust SEs.", "msg-2", "2026-11-26 10:15"));
        t1_reply.status = "resolved";
        store_b.threads.add (t1_reply);

        int merged = parsed.merge_from (store_b);
        assert (merged == 1);
        assert (parsed.threads[0].messages.size == 2);
        assert (parsed.threads[0].is_resolved ());
    }

    public static void test_fuzzy_reanchoring_and_export () {
        var store = new ReviewCommentStore ();
        var t = new ReviewThread (
            new ReviewAnchor (2, 2, 0, 20, "alpha <- 0.05", "title: Test", "beta <- 0.80"),
            "Methodology",
            "t-reanchor"
        );
        t.messages.add (new ReviewMessage ("Reviewer 1", "Reviewer", "Justify alpha = 0.05."));
        store.threads.add (t);

        string shifted_doc = "line1\nline2\nline3\ntitle: Test\nalpha <- 0.05\nbeta <- 0.80\n";
        store.reanchor_against_text (shifted_doc);
        assert (!t.detached);
        assert (t.anchor.start_line == 5);
        assert (t.anchor.end_line == 5);

        string md = store.export_rebuttal_markdown ("Report");
        assert ("| L5 | Methodology | open |" in md);
        assert ("Justify alpha = 0.05." in md);

        store.reanchor_against_text ("completely different content\n");
        assert (t.detached);
    }

    public static int main (string[] args) {
        Test.init (ref args);
        Test.add_func ("/review_comments/sidecar_path_resolution", test_sidecar_path_resolution);
        Test.add_func ("/review_comments/json_roundtrip_and_merge", test_json_roundtrip_and_merge);
        Test.add_func ("/review_comments/fuzzy_reanchoring_and_export", test_fuzzy_reanchoring_and_export);
        return Test.run ();
    }
}
