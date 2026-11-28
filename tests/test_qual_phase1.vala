// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Imladris.Qual;

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/qual/phase1/lossless_span_roundtrip", () => {
        string qmd = """---
title: "TP53 Proteomics Cohort"
format: html
---

# Results

Observed that [TP53 exhibits nuclear accumulation without transcriptional activation]{.qual id="q-8f3a" domain="protein" code="ptm-dysregulation" valence="negative" coder="antonio" confidence="high" ref="@doe2025"} in treated cells.

```{r}
# Code chunk with [bracket]{.qual id="ignored"} must NOT be parsed
x <- c(1, 2, 3)
```

Inline example `[raw]{.qual id="ignored2"}` also stays untouched, while [nested [@smith2024] citation inside span]{.qual id="q-991b" domain="protein" code="loc-nuclear" entity="UniProtKB:P04637" coder="reviewer2" confidence="moderate"} parses cleanly.
""";

        var spans = QualSpanParser.parse_document (qmd, "study.qmd");
        assert (spans.size == 2);

        var s0 = spans[0];
        assert (s0.span_id == "q-8f3a");
        assert (s0.domain == "protein");
        assert (s0.code_id == "ptm-dysregulation");
        assert (s0.valence == "negative");
        assert (s0.coder_id == "antonio");
        assert (s0.confidence == "high");
        assert (s0.citation_key == "@doe2025");
        assert (s0.line_start == 8);
        assert (s0.source_sha256.length == 64);
        assert (QualSpanParser.verify_span_sdv (s0, qmd) == SdvStatus.VERIFIED);

        var s1 = spans[1];
        assert (s1.span_id == "q-991b");
        assert (s1.entity_id == "UniProtKB:P04637");
        assert (s1.excerpt == "nested [@smith2024] citation inside span");

        // Verify 100% lossless round-trip serialization
        string rebuilt = QualSpanParser.update_or_remove_span_by_id (qmd, "q-8f3a", s0);
        assert (rebuilt == qmd);

        // Verify blinded stripping hides reviewer2 while keeping antonio + code chunks intact
        string blinded = QualSpanParser.strip_qual_spans (qmd, "antonio");
        assert (blinded.contains ("{.qual id=\"q-8f3a\""));
        assert (!blinded.contains ("{.qual id=\"q-991b\""));
        assert (blinded.contains ("nested [@smith2024] citation inside span"));
        assert (blinded.contains ("# Code chunk with [bracket]{.qual id=\"ignored\"}"));

        // Verify SDV detects tampering on line 8
        string tampered = qmd.replace ("treated cells", "untreated controls");
        assert (QualSpanParser.verify_span_sdv (s0, tampered) == SdvStatus.MODIFIED);
    });

    Test.add_func ("/qual/phase1/sqlite_wal_and_100pct_audit_immutability", () => {
        try {
            string tmp_dir = GLib.DirUtils.make_tmp ("imladris-qual-test-XXXXXX");
            var db = new QualDatabase (tmp_dir);
            assert (db.get_journal_mode ().down () == "wal");

            // 1. Span Create + Update + Delete
            var sp = new QualSpan ();
            sp.span_id = "q-test01";
            sp.file_path = "cohort.qmd";
            sp.line_start = 12;
            sp.line_end = 12;
            sp.source_sha256 = QualSpanParser.compute_sha256 ("BRCA1 nuclear foci");
            sp.excerpt = "BRCA1 nuclear foci";
            sp.domain = "protein";
            sp.code_id = "loc-nuclear";
            sp.entity_id = "UniProtKB:P38398";
            sp.coder_id = "antonio";
            sp.confidence = "high";
            db.upsert_span (sp, "antonio", "Initial coding pass");

            sp.confidence = "moderate";
            db.upsert_span (sp, "antonio", "Refined confidence after replicate review");

            // 2. Memo Create + Delete
            var memo = new QualMemo ();
            memo.target_id = sp.span_id;
            memo.author_id = "antonio";
            memo.body = "Confirmed by immunofluorescence panel B.";
            db.upsert_memo (memo, "antonio", "Attach IF memo");
            db.delete_memo (memo.memo_id, "antonio", "Superseded memo");

            // 3. Network Edge Create + Delete
            var edge = new QualNetworkEdge ();
            edge.source_node = "UniProtKB:P38398";
            edge.target_node = "loc-nuclear";
            edge.relation_type = "supports";
            edge.weight = 2.5;
            edge.evidence_span_id = sp.span_id;
            db.upsert_edge (edge, "antonio", "Link entity to code");
            db.delete_edge (edge.edge_id, "antonio", "Prune test edge");

            // 4. CRA Query Create + Answer
            var rq = new QualReviewQuery ();
            rq.span_id = sp.span_id;
            rq.raised_by = "cra_lead";
            rq.status = "Open";
            rq.message = "Verify Western blot lane annotation.";
            db.upsert_review_query (rq, "cra_lead", "SDV audit check");
            rq.status = "Closed";
            rq.resolution_note = "Verified against raw gel image SHA-256.";
            db.upsert_review_query (rq, "antonio", "Resolved CRA query");

            // 5. Delete span
            db.delete_span (sp.span_id, "antonio", "Cleanup test span");

            // Verify 100% audit coverage (9 distinct operations)
            var logs = db.list_audit_log (50);
            assert (logs.size == 9);
            assert (logs[0].action == "DELETE_SPAN");
            assert (logs[0].previous_json != null && logs[0].previous_json.contains ("q-test01"));

            // Verify ALCOA+ Immutability: UPDATE and DELETE on audit_log MUST fail!
            bool update_blocked = false;
            try {
                db.attempt_raw_sql_for_audit_test ("UPDATE audit_log SET user_id = 'mallory' WHERE log_id = 1;");
            } catch (QualDbError e) {
                update_blocked = (e is QualDbError.IMMUTABILITY_VIOLATION);
            }
            assert (update_blocked);

            bool delete_blocked = false;
            try {
                db.attempt_raw_sql_for_audit_test ("DELETE FROM audit_log WHERE log_id = 1;");
            } catch (QualDbError e) {
                delete_blocked = (e is QualDbError.IMMUTABILITY_VIOLATION);
            }
            assert (delete_blocked);
        } catch (GLib.Error e) {
            error ("Unexpected DB error: %s", e.message);
        }
    });

    Test.add_func ("/qual/phase1/domain_profile_loader", () => {
        string tmp_dir = "";
        try { tmp_dir = GLib.DirUtils.make_tmp ("imladris-profiles-XXXXXX"); } catch (GLib.FileError e) { error (e.message); }
        ProfileLoader.ensure_default_profiles_in_dir (tmp_dir);

        var protein = ProfileLoader.load_from_file (GLib.Path.build_filename (tmp_dir, "protein-qual.yaml"));
        assert (protein != null);
        assert (protein.profile_id == "protein-qual-v1");
        assert (protein.entity_resolver == "yavanna:uniprot");
        assert (protein.scales.has_key ("confidence"));
        assert (protein.scales.get ("confidence").size == 3);
        assert (protein.find_code ("loc-nuclear") != null);
        assert (protein.find_code ("ptm-dysregulation") != null);
        assert (protein.find_code ("ptm-dysregulation").color == "#BF616A");

        var gene = ProfileLoader.load_from_file (GLib.Path.build_filename (tmp_dir, "gene-expr-qual.yaml"));
        assert (gene != null && gene.entity_resolver == "yavanna:ensembl");

        var fin = ProfileLoader.load_from_file (GLib.Path.build_filename (tmp_dir, "finance-qual.yaml"));
        assert (fin != null && fin.find_code ("risk-liquidity") != null);
    });

    return Test.run ();
}
