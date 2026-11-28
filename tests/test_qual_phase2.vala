// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Imladris.Qual;

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/qual/phase2/matrix_1200_spans_and_blinded_coding", () => {
        try {
            string tmp_dir = GLib.DirUtils.make_tmp ("imladris-qual-p2-XXXXXX");
            string doc_path = GLib.Path.build_filename (tmp_dir, "proteomics_1200.qmd");
            var sb = new GLib.StringBuilder ("# High-Throughput Proteomics Qualitative Cohort\n\n");
            string[] entities = { "UniProtKB:P04637", "UniProtKB:P38398", "UniProtKB:P00533", "UniProtKB:Q9Y6K9", "UniProtKB:P42336" };
            string[] codes = { "loc-nuclear", "loc-cytosolic", "ptm-dysregulation", "ptm-hyperphos", "ppi-complex" };

            for (int i = 0; i < 1200; i++) {
                string coder = (i % 2 == 0) ? "coder_alpha" : "coder_beta";
                string ent = entities[i % entities.length];
                string cid = codes[(i / 2) % codes.length];
                string conf = (i % 3 == 0) ? "high" : "moderate";
                sb.append_printf (
                    "Sample %d shows [observation %d]{.qual id=\"q-perf-%04d\" domain=\"protein\" code=\"%s\" entity=\"%s\" coder=\"%s\" confidence=\"%s\"} in assay.\n",
                    i, i, i, cid, ent, coder, conf
                );
            }
            string doc_text = sb.str;
            GLib.FileUtils.set_contents (doc_path, doc_text);

            int64 t0 = GLib.get_monotonic_time ();
            var svc = new QualWorkspaceService (tmp_dir);
            svc.current_coder = "coder_alpha";
            svc.db.sync_document_spans (doc_path, doc_text, "coder_alpha", "Bulk 1200 span index");
            int64 index_ms = (GLib.get_monotonic_time () - t0) / 1000;

            var open_map = new Gee.HashMap<string, string> ();
            open_map.set (doc_path, doc_text);

            int64 t1 = GLib.get_monotonic_time ();
            var unblinded_rows = svc.build_matrix_rows (null, null, "Verified", open_map);
            int64 pivot_ms = (GLib.get_monotonic_time () - t1) / 1000;

            assert (unblinded_rows.size > 0);
            int total_unblinded = 0;
            foreach (var r in unblinded_rows) {
                total_unblinded += r.span_count;
                assert (r.sdv_summary == "Verified");
            }
            assert (total_unblinded == 1200);
            // Indexing 1200 spans in single WAL transaction + pivoting must be fast (< 2000ms)
            assert (index_ms < 2000);
            assert (pivot_ms < 500);

            // Blinded Coding Toggle hides coder_beta (600 spans) leaving exactly 600 spans for coder_alpha
            svc.set_blinded_coding (true);
            var blinded_rows = svc.build_matrix_rows (null, null, null, open_map);
            int total_blinded = 0;
            foreach (var r in blinded_rows) {
                total_blinded += r.span_count;
                assert (!r.coders_summary.contains ("coder_beta"));
            }
            assert (total_blinded == 600);

            // Quarto Table & CSV/TSV export checks
            string quarto_tbl = QualWorkspaceService.format_as_quarto_table (blinded_rows);
            assert (quarto_tbl.contains ("{#tbl-qual-evidence-matrix}"));
            assert (quarto_tbl.contains ("UniProtKB:P04637"));

            string csv = QualWorkspaceService.format_as_delimited (blinded_rows, ',');
            assert (csv.has_prefix ("entity,code_id,code_label,span_count,coders,confidence,sdv_status,sample_excerpt\n"));
            string tsv = QualWorkspaceService.format_as_delimited (blinded_rows, '\t');
            assert (tsv.has_prefix ("entity\tcode_id\t"));
        } catch (GLib.Error e) {
            error ("Phase 2 test error: %s", e.message);
        }
    });

    return Test.run ();
}
