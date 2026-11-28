// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Imladris.Qual;
using Imladris.Bridges.Qual;

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/qual/phase5/end_to_end_ai_adjudication_yavanna_arekyer_irr_cytoscape", () => {
        try {
            string tmp_dir = GLib.DirUtils.make_tmp ("imladris-qual-p5-XXXXXX");
            var svc = new QualWorkspaceService (tmp_dir);
            svc.set_active_profile_by_id ("gene-expr-qual-v1");

            // 1. Yavanna multi-namespace normalization check
            assert (YavannaQualResolver.normalize_entity_id ("P04637", "yavanna:uniprot") == "UniProtKB:P04637");
            assert (YavannaQualResolver.normalize_entity_id ("ENSG00000141510", "yavanna:ensembl") == "Ensembl:ENSG00000141510");
            assert (YavannaQualResolver.normalize_entity_id ("6915", "yavanna:go") == "GO:0006915");
            assert (YavannaQualResolver.normalize_entity_id ("320193", "yavanna:sec-ticker") == "SEC-CIK:0000320193");
            assert (YavannaQualResolver.normalize_entity_id ("$NVDA", "yavanna:sec-ticker") == "TICKER:NVDA");

            // 2. Raw manuscript -> Elrond AI Coding Suggestion (must stay Pending Review!)
            string doc_path = GLib.Path.build_filename (tmp_dir, "rnaseq_cohort.qmd");
            string raw_doc = """# Transcriptomic Cohort

RNA-seq profiling showed that STAT1 exhibits marked interferon-driven upregulation in responder biopsies.
""";
            GLib.FileUtils.set_contents (doc_path, raw_doc);

            string mock_elrond_json = """{
              "suggestions": [
                {
                  "line_start": 3,
                  "line_end": 3,
                  "excerpt": "STAT1 exhibits marked interferon-driven upregulation",
                  "code_id": "deg-up",
                  "entity_id": "ENSG00000115415",
                  "confidence": "high",
                  "valence": "upregulated",
                  "rationale": "Log2FC > 2.1 in responder cohort"
                }
              ]
            }""";

            var queued = ElrondQualCodingBridge.parse_and_queue_suggestions (svc, mock_elrond_json, doc_path);
            assert (queued.size == 1);
            assert (svc.db.list_ai_suggestions ("Pending Review").size == 1);
            // Crucial Phase 5 Gate: AI suggestions MUST NOT write to spans before human approval!
            assert (svc.db.list_spans ().size == 0);

            // 3. Explicit Human Adjudication approves suggestion -> writes Pandoc {.qual} span + audit_log
            QualSpan? approved_span = null;
            string adjudicated_doc = ElrondQualCodingBridge.adjudicate_into_document (
                svc,
                queued[0].suggestion_id,
                true,
                "coder_human_1",
                raw_doc,
                "Approved after qPCR confirmation",
                out approved_span
            );
            assert (approved_span != null);
            assert (approved_span.entity_id == "Ensembl:ENSG00000115415");
            assert (adjudicated_doc.contains ("{.qual id=\""));
            assert (svc.db.list_ai_suggestions ("Pending Review").size == 0);
            assert (svc.db.list_spans ().size == 1);

            // 4. Independent second coder annotates same line for IRR report
            var second_coder_span = new QualSpan () {
                span_id = "q-coder2-01",
                file_path = doc_path,
                line_start = 3,
                line_end = 3,
                source_sha256 = approved_span.source_sha256,
                excerpt = approved_span.excerpt,
                domain = "gene-expr",
                code_id = "deg-up",
                entity_id = "Ensembl:ENSG00000115415",
                coder_id = "coder_human_2",
                confidence = "high"
            };
            svc.db.upsert_span (second_coder_span, "coder_human_2", "Independent blinded second coding");

            // 5. Arekyer .qual-hook.json quantitative-to-qualitative ingestion
            string hook_path = GLib.Path.build_filename (tmp_dir, ".qual-hook.json");
            string hook_payload = """{
              "source": "Galaxy DESeq2 History #19",
              "domain": "gene-expr",
              "rules_applied": "padj < 0.05 & log2FC > 1.5",
              "annotations": [
                {
                  "entity_id": "ENSG00000185338",
                  "code_id": "go-immune",
                  "valence": "upregulated",
                  "confidence": "high",
                  "excerpt": "SOCS1 negative-feedback induction (padj = 3.1e-6)",
                  "file_path": "rnaseq_cohort.qmd",
                  "line_start": 4
                }
              ]
            }""";
            GLib.FileUtils.set_contents (hook_path, hook_payload);
            int hooked = ArekyerQualHookBridge.ingest_hook_file (svc, hook_path, doc_path);
            assert (hooked == 1);

            // 6. IRR Report + Cytoscape CX2 Network Export
            IrrResult cohen, kripp;
            Gee.ArrayList<AdjudicationDiff> diffs;
            QualStatsEngine.analyze_workspace_irr (svc.db.list_spans (), out cohen, out kripp, out diffs);
            assert (cohen.n_units == 1);
            assert ((cohen.statistic - 1.0).abs () < 1e-9);

            var graph = NetworkBuilder.build_from_workspace (svc);
            string cx2 = Cx2Serializer.serialize (graph);
            assert (cx2.contains ("Ensembl:ENSG00000115415"));
            assert (cx2.contains ("Ensembl:ENSG00000185338"));
            assert (cx2.contains ("go-immune"));
        } catch (GLib.Error e) {
            error ("Phase 5 E2E test failed: %s", e.message);
        }
    });

    return Test.run ();
}
