// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Qual {

    /**
     * Workspace-scoped coordinator managing .imladris-qual.db, active Domain Profile,
     * Blinded Dual-Coding state, and Pivot Matrix / Quarto Table / CSV-TSV exports.
     */
    public class EvidenceMatrixRow : GLib.Object {
        public string entity_label { get; set; default = ""; }
        public string code_id { get; set; default = ""; }
        public string code_label { get; set; default = ""; }
        public int span_count { get; set; default = 0; }
        public string coders_summary { get; set; default = ""; }
        public string top_confidence { get; set; default = ""; }
        public string sdv_summary { get; set; default = ""; }
        public string sample_excerpt { get; set; default = ""; }
        public string first_file_path { get; set; default = ""; }
        public int first_line { get; set; default = 1; }
        public string first_span_id { get; set; default = ""; }
    }

    public class QualWorkspaceService : GLib.Object {
        private static Gee.HashMap<string, QualWorkspaceService>? instances = null;

        public string workspace_dir { get; private set; }
        public QualDatabase db { get; private set; }
        public Gee.ArrayList<QualDomainProfile> profiles { get; private set; }
        public QualDomainProfile active_profile { get; private set; }
        public string current_coder { get; set; default = ""; }
        public bool blinded_mode { get; set; default = false; }
        public Gee.HashSet<string> selected_graph_nodes { get; private set; }

        public signal void state_changed ();
        public signal void selection_filter_changed ();

        public static QualWorkspaceService for_workspace (string raw_workspace_dir) {
            if (instances == null) {
                instances = new Gee.HashMap<string, QualWorkspaceService> ();
            }
            string key = raw_workspace_dir.strip ();
            if (key == "" || key == "default") {
                key = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "imladris", "default-qual-workspace");
            }
            var existing = instances.get (key);
            if (existing != null) return existing;

            var svc = new QualWorkspaceService (key);
            instances.set (key, svc);
            return svc;
        }

        public QualWorkspaceService (string dir) {
            this.workspace_dir = dir;
            this.selected_graph_nodes = new Gee.HashSet<string> ();
            string user = GLib.Environment.get_user_name ();
            this.current_coder = (user != null && user.strip () != "") ? user.strip () : "researcher";

            try {
                this.db = new QualDatabase (dir);
            } catch (QualDbError e) {
                string fallback = GLib.Path.build_filename (GLib.Environment.get_tmp_dir (), "imladris-qual-fallback");
                try {
                    this.db = new QualDatabase (fallback);
                } catch (QualDbError e2) {
                    GLib.warning ("QualDatabase fallback failed: %s", e2.message);
                }
            }

            this.profiles = ProfileLoader.load_all_profiles (dir);
            if (this.profiles.size > 0) {
                this.active_profile = this.profiles[0];
                foreach (var p in this.profiles) {
                    if (p.profile_id.has_prefix ("protein")) {
                        this.active_profile = p;
                        break;
                    }
                }
            } else {
                this.active_profile = ProfileLoader.parse_yaml (ProfileLoader.default_protein_yaml ());
                this.profiles.add (this.active_profile);
            }

            if (this.db != null) {
                this.db.database_changed.connect (() => {
                    state_changed ();
                });
            }
        }

        public void set_active_profile_by_id (string profile_id) {
            foreach (var p in profiles) {
                if (p.profile_id == profile_id) {
                    active_profile = p;
                    state_changed ();
                    return;
                }
            }
        }

        public void set_blinded_coding (bool enabled) {
            if (blinded_mode != enabled) {
                blinded_mode = enabled;
                state_changed ();
            }
        }

        public void set_graph_node_filter (Gee.Collection<string>? node_ids) {
            selected_graph_nodes.clear ();
            if (node_ids != null) {
                foreach (string nid in node_ids) {
                    if (nid.strip () != "") selected_graph_nodes.add (nid.strip ());
                }
            }
            selection_filter_changed ();
            state_changed ();
        }

        public Gee.ArrayList<QualSpan> get_visible_spans (
            string? filter_coder = null,
            string? filter_confidence = null,
            string? filter_code_id = null
        ) {
            if (db == null) return new Gee.ArrayList<QualSpan> ();
            string? effective_coder = filter_coder;
            if (blinded_mode) {
                effective_coder = current_coder;
            }
            var raw = db.list_spans (null, effective_coder, filter_code_id, filter_confidence);
            if (selected_graph_nodes.size == 0) {
                return raw;
            }
            var filtered = new Gee.ArrayList<QualSpan> ();
            foreach (var sp in raw) {
                bool match = selected_graph_nodes.contains (sp.code_id)
                    || selected_graph_nodes.contains ("code:" + sp.code_id)
                    || (sp.entity_id != null && (selected_graph_nodes.contains (sp.entity_id) || selected_graph_nodes.contains ("entity:" + sp.entity_id)))
                    || (sp.file_path != "" && (selected_graph_nodes.contains (sp.file_path) || selected_graph_nodes.contains (GLib.Path.get_basename (sp.file_path))));
                if (match) filtered.add (sp);
            }
            return filtered;
        }

        public Gee.ArrayList<EvidenceMatrixRow> build_matrix_rows (
            string? filter_coder = null,
            string? filter_confidence = null,
            string? filter_sdv = null,
            Gee.HashMap<string, string>? open_doc_buffers = null
        ) {
            var spans = get_visible_spans (filter_coder, filter_confidence, null);
            var grouped = new Gee.HashMap<string, Gee.ArrayList<QualSpan>> ();
            var group_keys = new Gee.ArrayList<string> ();

            foreach (var sp in spans) {
                string ent = (sp.entity_id != null && sp.entity_id != "") ? sp.entity_id : "(Document Context)";
                string key = ent + "\t" + sp.code_id;
                var bucket = grouped.get (key);
                if (bucket == null) {
                    bucket = new Gee.ArrayList<QualSpan> ();
                    grouped.set (key, bucket);
                    group_keys.add (key);
                }
                bucket.add (sp);
            }
            group_keys.sort ();

            var file_cache = new Gee.HashMap<string, string> ();
            var rows = new Gee.ArrayList<EvidenceMatrixRow> ();

            foreach (string key in group_keys) {
                var bucket = grouped.get (key);
                if (bucket == null || bucket.size == 0) continue;

                var first = bucket[0];
                string ent = (first.entity_id != null && first.entity_id != "") ? first.entity_id : "(Document Context)";
                var code_def = active_profile != null ? active_profile.find_code (first.code_id) : null;
                string c_label = code_def != null ? code_def.label : first.code_id;

                var coders = new Gee.HashSet<string> ();
                int verified_cnt = 0;
                int mismatch_cnt = 0;
                string best_conf = "";

                foreach (var sp in bucket) {
                    if (sp.coder_id != "") coders.add (sp.coder_id);
                    if (sp.confidence == "high") best_conf = "high";
                    else if (sp.confidence == "moderate" && best_conf != "high") best_conf = "moderate";
                    else if (sp.confidence != null && best_conf == "") best_conf = sp.confidence;

                    string? doc_body = null;
                    if (open_doc_buffers != null && open_doc_buffers.has_key (sp.file_path)) {
                        doc_body = open_doc_buffers.get (sp.file_path);
                    } else if (sp.file_path != "" && file_cache.has_key (sp.file_path)) {
                        doc_body = file_cache.get (sp.file_path);
                    } else if (sp.file_path != "" && GLib.FileUtils.test (sp.file_path, GLib.FileTest.EXISTS)) {
                        try {
                            string loaded;
                            GLib.FileUtils.get_contents (sp.file_path, out loaded);
                            file_cache.set (sp.file_path, loaded);
                            doc_body = loaded;
                        } catch (GLib.Error e) {}
                    }

                    if (doc_body != null) {
                        var st = QualSpanParser.verify_span_sdv (sp, doc_body);
                        if (st == SdvStatus.VERIFIED) verified_cnt++;
                        else if (st == SdvStatus.MODIFIED) mismatch_cnt++;
                    }
                }

                string sdv_str = "Unverified";
                if (mismatch_cnt > 0) {
                    sdv_str = "Hash Mismatch";
                } else if (verified_cnt == bucket.size) {
                    sdv_str = "Verified";
                } else if (verified_cnt > 0) {
                    sdv_str = @"Partial ($(verified_cnt)/$(bucket.size))";
                }

                if (filter_sdv != null && filter_sdv != "" && filter_sdv != "All") {
                    if (filter_sdv == "Verified" && sdv_str != "Verified") continue;
                    if (filter_sdv == "Hash Mismatch" && sdv_str != "Hash Mismatch") continue;
                    if (filter_sdv == "Unverified" && sdv_str != "Unverified") continue;
                }

                var coder_list = new Gee.ArrayList<string> ();
                foreach (string c in coders) coder_list.add (c);
                coder_list.sort ();

                string snip = first.excerpt.replace ("\n", " ").strip ();
                if (snip.length > 96) snip = snip.substring (0, 93) + "...";

                var row = new EvidenceMatrixRow ();
                row.entity_label = ent;
                row.code_id = first.code_id;
                row.code_label = c_label;
                row.span_count = bucket.size;
                row.coders_summary = string.joinv (", ", coder_list.to_array ());
                row.top_confidence = best_conf != "" ? best_conf : "—";
                row.sdv_summary = sdv_str;
                row.sample_excerpt = snip;
                row.first_file_path = first.file_path;
                row.first_line = first.line_start;
                row.first_span_id = first.span_id;
                rows.add (row);
            }
            return rows;
        }

        public static string format_as_quarto_table (Gee.ArrayList<EvidenceMatrixRow> rows, string caption = "Qualitative Evidence Matrix (Entities × Codes)") {
            var sb = new GLib.StringBuilder ();
            sb.append ("\n| Entity | Code | Spans | Coders | Confidence | SDV Status | Representative Excerpt |\n");
            sb.append ("| :--- | :--- | ---: | :--- | :--- | :--- | :--- |\n");
            foreach (var r in rows) {
                sb.append_printf (
                    "| %s | `%s` (%s) | %d | %s | %s | %s | %s |\n",
                    escape_md_cell (r.entity_label),
                    escape_md_cell (r.code_id),
                    escape_md_cell (r.code_label),
                    r.span_count,
                    escape_md_cell (r.coders_summary),
                    escape_md_cell (r.top_confidence),
                    escape_md_cell (r.sdv_summary),
                    escape_md_cell (r.sample_excerpt)
                );
            }
            sb.append_printf ("\n: %s {#tbl-qual-evidence-matrix}\n\n", caption);
            return sb.str;
        }

        public static string format_as_delimited (Gee.ArrayList<EvidenceMatrixRow> rows, char sep = ',') {
            var sb = new GLib.StringBuilder ();
            string s = sep.to_string ();
            sb.append ("entity" + s + "code_id" + s + "code_label" + s + "span_count" + s + "coders" + s + "confidence" + s + "sdv_status" + s + "sample_excerpt\n");
            foreach (var r in rows) {
                sb.append (quote_delim (r.entity_label, sep)).append (s);
                sb.append (quote_delim (r.code_id, sep)).append (s);
                sb.append (quote_delim (r.code_label, sep)).append (s);
                sb.append (r.span_count.to_string ()).append (s);
                sb.append (quote_delim (r.coders_summary, sep)).append (s);
                sb.append (quote_delim (r.top_confidence, sep)).append (s);
                sb.append (quote_delim (r.sdv_summary, sep)).append (s);
                sb.append (quote_delim (r.sample_excerpt, sep)).append_c ('\n');
            }
            return sb.str;
        }

        private static string escape_md_cell (string s) {
            return s.replace ("|", "\\|").replace ("\n", " ").replace ("\r", " ");
        }

        private static string quote_delim (string val, char sep) {
            if (sep == '\t') {
                return val.replace ("\t", " ").replace ("\n", " ").replace ("\r", " ");
            }
            if (val.contains (",") || val.contains ("\"") || val.contains ("\n")) {
                return "\"" + val.replace ("\"", "\"\"") + "\"";
            }
            return val;
        }
    }
}
