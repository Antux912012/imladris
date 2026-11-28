// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Json;
using Soup;
using Imladris.Qual;

namespace Imladris.Bridges.Qual {

    /**
     * Phase 5.1: Yavanna Multi-Namespace Entity Resolver for Qualitative Spans.
     * Resolves UniProt, Ensembl, Gene Ontology (GO), SEC CIK, and Ticker identifiers
     * into canonical CURIEs stored in spans.entity_id.
     */
    public class YavannaQualResolver : GLib.Object {

        public static string normalize_entity_id (string raw_input, string resolver_hint = "") {
            string s = raw_input.strip ();
            if (s == "") return "";

            string up = s.up ();
            string hint = resolver_hint.down ();

            // Already canonical CURIE?
            if (up.has_prefix ("UNIPROTKB:")) return "UniProtKB:" + s.substring (10).strip ().up ();
            if (up.has_prefix ("UNIPROT:")) return "UniProtKB:" + s.substring (8).strip ().up ();
            if (up.has_prefix ("ENSEMBL:")) return "Ensembl:" + s.substring (8).strip ().up ();
            if (up.has_prefix ("GO:")) {
                string digits = s.substring (3).strip ();
                return "GO:" + pad_digits (digits, 7);
            }
            if (up.has_prefix ("CIK:") || up.has_prefix ("SEC-CIK:")) {
                string digits = up.has_prefix ("SEC-CIK:") ? s.substring (8).strip () : s.substring (4).strip ();
                return "SEC-CIK:" + pad_digits (digits, 10);
            }
            if (up.has_prefix ("TICKER:")) {
                return "TICKER:" + s.substring (7).strip ().up ();
            }
            if (s.has_prefix ("$") && s.length > 1) {
                return "TICKER:" + s.substring (1).strip ().up ();
            }

            // Pattern-based recognition
            if (up.has_prefix ("ENSG") || up.has_prefix ("ENSMUSG") || up.has_prefix ("ENST")) {
                return "Ensembl:" + up;
            }
            if (is_all_digits (s) && s.length >= 6 && s.length <= 10 && hint.contains ("sec")) {
                return "SEC-CIK:" + pad_digits (s, 10);
            }

            // Resolver hint routing
            if (hint.contains ("uniprot")) {
                return "UniProtKB:" + up;
            }
            if (hint.contains ("ensembl")) {
                return "Ensembl:" + s;
            }
            if (hint.contains ("go")) {
                return is_all_digits (s) ? ("GO:" + pad_digits (s, 7)) : ("GO:" + up);
            }
            if (hint.contains ("sec") || hint.contains ("ticker") || hint.contains ("finance")) {
                if (is_all_digits (s)) return "SEC-CIK:" + pad_digits (s, 10);
                return "TICKER:" + up;
            }
            return s;
        }

        public static async string resolve_cloud_or_normalize_async (
            string raw_query,
            string resolver_hint = "",
            Soup.Session? custom_session = null
        ) {
            string fallback = normalize_entity_id (raw_query, resolver_hint);
            string q = raw_query.strip ();
            if (q == "" || q.contains (":")) return fallback;

            var sess = custom_session ?? new Soup.Session () { timeout = 5, user_agent = "Imladris-Yavanna-Qual/1.0" };
            string hint = resolver_hint.down ();

            try {
                if (hint.contains ("uniprot")) {
                    string url = @"https://rest.uniprot.org/uniprotkb/search?query=$(GLib.Uri.escape_string (q, null, false))&size=1";
                    var msg = new Soup.Message ("GET", url);
                    msg.request_headers.append ("Accept", "application/json");
                    var bytes = yield sess.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
                    if (msg.status_code == 200 && bytes != null && bytes.get_size () > 0) {
                        var sb = new GLib.StringBuilder.sized (bytes.get_size () + 1);
                        sb.append_len ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
                        var p = new Json.Parser ();
                        p.load_from_data (sb.str, -1);
                        var obj = p.get_root ().get_object ();
                        if (obj.has_member ("results") && obj.get_array_member ("results").get_length () > 0) {
                            var r0 = obj.get_array_member ("results").get_object_element (0);
                            if (r0.has_member ("primaryAccession")) {
                                return "UniProtKB:" + r0.get_string_member ("primaryAccession");
                            }
                        }
                    }
                } else if (hint.contains ("ensembl")) {
                    string url = @"https://rest.ensembl.org/lookup/symbol/homo_sapiens/$(GLib.Uri.escape_string (q, null, false))?content-type=application/json";
                    var msg = new Soup.Message ("GET", url);
                    var bytes = yield sess.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
                    if (msg.status_code == 200 && bytes != null && bytes.get_size () > 0) {
                        var sb = new GLib.StringBuilder.sized (bytes.get_size () + 1);
                        sb.append_len ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
                        var p = new Json.Parser ();
                        p.load_from_data (sb.str, -1);
                        var obj = p.get_root ().get_object ();
                        if (obj.has_member ("id")) {
                            return "Ensembl:" + obj.get_string_member ("id");
                        }
                    }
                }
            } catch (GLib.Error e) {}

            return fallback;
        }

        private static bool is_all_digits (string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++) {
                if (!s[i].isdigit ()) return false;
            }
            return true;
        }

        private static string pad_digits (string d, int width) {
            if (d.length >= width) return d;
            return string.nfill (width - d.length, '0') + d;
        }
    }

    /**
     * Phase 5.2: Elrond AI Human-in-the-Loop Qualitative Coding Bridge.
     * Builds grammar-constrained JSON prompts, parses structured LLM coding suggestions,
     * queues them strictly in Pending Review state, and commits to spans + audit_log ONLY
     * upon explicit human adjudication.
     */
    public class ElrondQualCodingBridge : GLib.Object {

        public static string build_grammar_json_schema () {
            return """{
  "type": "object",
  "required": ["suggestions"],
  "properties": {
    "suggestions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["line_start", "line_end", "excerpt", "code_id", "confidence", "valence", "rationale"],
        "properties": {
          "line_start": { "type": "integer", "minimum": 1 },
          "line_end": { "type": "integer", "minimum": 1 },
          "excerpt": { "type": "string", "minLength": 1 },
          "code_id": { "type": "string", "minLength": 1 },
          "entity_id": { "type": "string" },
          "confidence": { "type": "string", "enum": ["low", "moderate", "high"] },
          "valence": { "type": "string" },
          "rationale": { "type": "string", "minLength": 1 }
        }
      }
    }
  }
}""";
        }

        public static string build_system_prompt (QualDomainProfile profile) {
            var code_sb = new GLib.StringBuilder ();
            foreach (var c in profile.flatten_codes ()) {
                code_sb.append_printf ("- \"%s\": %s\n", c.id, c.label);
            }
            return """You are Elrond Qualitative Biostatistician AI inside Imladris.
Analyze the scientific manuscript and return ONLY a single valid JSON object conforming strictly to this schema:
%s

Allowed Domain Profile ("%s", domain="%s") codes:
%s
Do NOT wrap the JSON in conversational prose. Every suggestion enters human-in-the-loop Pending Review.""".printf (
                build_grammar_json_schema (),
                profile.name,
                profile.domain_slug,
                code_sb.str
            );
        }

        public static Gee.ArrayList<QualAiSuggestion> parse_and_queue_suggestions (
            QualWorkspaceService svc,
            string raw_ai_json,
            string file_path
        ) throws GLib.Error {
            string cleaned = extract_json_object (raw_ai_json);
            var parser = new Json.Parser ();
            parser.load_from_data (cleaned, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new GLib.IOError.INVALID_DATA ("Elrond qualitative output is not a JSON object.");
            }
            var obj = root.get_object ();
            if (!obj.has_member ("suggestions") || obj.get_member ("suggestions").get_node_type () != Json.NodeType.ARRAY) {
                throw new GLib.IOError.INVALID_DATA ("Elrond qualitative JSON missing 'suggestions' array.");
            }

            var queued = new Gee.ArrayList<QualAiSuggestion> ();
            var arr = obj.get_array_member ("suggestions");
            string domain = svc.active_profile != null ? svc.active_profile.domain_slug : "protein";
            string resolver = svc.active_profile != null ? svc.active_profile.entity_resolver : "";

            for (uint i = 0; i < arr.get_length (); i++) {
                var item = arr.get_object_element (i);
                string excerpt = item.has_member ("excerpt") ? item.get_string_member ("excerpt").strip () : "";
                string cid = item.has_member ("code_id") ? item.get_string_member ("code_id").strip () : "";
                if (excerpt == "" || cid == "") continue;

                var sug = new QualAiSuggestion ();
                sug.file_path = file_path;
                sug.line_start = item.has_member ("line_start") ? int.max (1, (int) item.get_int_member ("line_start")) : 1;
                sug.line_end = item.has_member ("line_end") ? int.max (sug.line_start, (int) item.get_int_member ("line_end")) : sug.line_start;
                sug.excerpt = excerpt;
                sug.domain = domain;
                sug.suggested_code_id = cid;
                if (item.has_member ("entity_id") && !item.get_null_member ("entity_id")) {
                    string raw_ent = item.get_string_member ("entity_id").strip ();
                    sug.entity_id = raw_ent != "" ? YavannaQualResolver.normalize_entity_id (raw_ent, resolver) : null;
                }
                if (item.has_member ("confidence")) sug.confidence = item.get_string_member ("confidence");
                if (item.has_member ("valence")) sug.valence = item.get_string_member ("valence");
                if (item.has_member ("rationale")) sug.rationale = item.get_string_member ("rationale");

                // Strictly enters Pending Review; never writes to spans without human approval!
                svc.db.queue_ai_suggestion (sug, "elrond-ai");
                queued.add (sug);
            }
            return queued;
        }

        /**
         * Adjudicates a Pending Review AI suggestion. If approved, injects the {.qual ...}
         * Pandoc span into doc_text (when the excerpt is present on the line/document) and
         * writes the verified span + ALCOA+ audit entries.
         */
        public static string adjudicate_into_document (
            QualWorkspaceService svc,
            string suggestion_id,
            bool approve,
            string human_reviewer_id,
            string doc_text,
            string rationale = "Human adjudication",
            out QualSpan? committed_span = null
        ) throws QualDbError {
            committed_span = null;
            QualAiSuggestion? target = null;
            foreach (var s in svc.db.list_ai_suggestions ("Pending Review")) {
                if (s.suggestion_id == suggestion_id) {
                    target = s;
                    break;
                }
            }
            if (target == null) {
                return doc_text;
            }

            if (!approve) {
                svc.db.adjudicate_ai_suggestion (suggestion_id, false, human_reviewer_id, doc_text, rationale, null);
                return doc_text;
            }

            var span = new QualSpan ();
            span.span_id = QualSpan.generate_short_id ();
            span.file_path = target.file_path;
            span.line_start = target.line_start;
            span.line_end = target.line_end;
            span.excerpt = target.excerpt;
            span.domain = target.domain;
            span.code_id = target.suggested_code_id;
            span.entity_id = target.entity_id;
            span.coder_id = human_reviewer_id;
            span.confidence = target.confidence;
            span.valence = target.valence;

            string updated = doc_text;
            int idx = QualSpanParser.find_unannotated_excerpt_offset (doc_text, target.excerpt, target.line_start, target.line_end);
            if (idx >= 0) {
                updated = QualSpanParser.apply_span_at_offsets (
                    doc_text,
                    idx,
                    idx + target.excerpt.length,
                    span
                );
            } else {
                string slice = QualSpanParser.extract_lines_slice (doc_text, span.line_start, span.line_end);
                span.source_sha256 = QualSpanParser.compute_sha256 (slice != "" ? slice : span.excerpt);
            }

            committed_span = svc.db.adjudicate_ai_suggestion (
                suggestion_id,
                true,
                human_reviewer_id,
                updated,
                rationale,
                span
            );
            return updated;
        }

        private static string extract_json_object (string raw) {
            int s = raw.index_of_char ('{');
            int e = raw.last_index_of_char ('}');
            if (s >= 0 && e > s) {
                return raw.substring (s, e - s + 1);
            }
            return raw.strip ();
        }
    }

    /**
     * Phase 5.3: Arekyer / Code Chunk Bridge (.qual-hook.json).
     * Maps quantitative thresholds from R, Python, or Galaxy outputs (e.g. padj < 0.05 & log2FC > 1.5)
     * into qualitative spans and network evidence with full ALCOA+ provenance.
     */
    public class ArekyerQualHookBridge : GLib.Object {

        public static int ingest_hook_json (
            QualWorkspaceService svc,
            string hook_json,
            string default_file_path = "",
            string actor_id = "arekyer-hook"
        ) throws GLib.Error {
            var parser = new Json.Parser ();
            parser.load_from_data (hook_json, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new GLib.IOError.INVALID_DATA (".qual-hook.json root must be a JSON object.");
            }
            var obj = root.get_object ();
            string source_label = obj.has_member ("source") ? obj.get_string_member ("source") : "Quantitative Chunk";
            string domain = obj.has_member ("domain")
                ? obj.get_string_member ("domain")
                : (svc.active_profile != null ? svc.active_profile.domain_slug : "gene-expr");
            string rule_desc = obj.has_member ("rules_applied") ? obj.get_string_member ("rules_applied") : "Threshold hook";
            string resolver = svc.active_profile != null ? svc.active_profile.entity_resolver : domain;

            if (!obj.has_member ("annotations") || obj.get_member ("annotations").get_node_type () != Json.NodeType.ARRAY) {
                return 0;
            }

            var arr = obj.get_array_member ("annotations");
            int count = 0;
            for (uint i = 0; i < arr.get_length (); i++) {
                var a = arr.get_object_element (i);
                string cid = a.has_member ("code_id") ? a.get_string_member ("code_id").strip () : "";
                if (cid == "") continue;

                var sp = new QualSpan ();
                sp.span_id = a.has_member ("span_id") ? a.get_string_member ("span_id") : QualSpan.generate_short_id ();
                sp.file_path = a.has_member ("file_path") ? a.get_string_member ("file_path") : default_file_path;
                sp.line_start = a.has_member ("line_start") ? int.max (1, (int) a.get_int_member ("line_start")) : 1;
                sp.line_end = a.has_member ("line_end") ? int.max (sp.line_start, (int) a.get_int_member ("line_end")) : sp.line_start;
                sp.domain = domain;
                sp.code_id = cid;
                sp.coder_id = actor_id;
                sp.valence = a.has_member ("valence") ? a.get_string_member ("valence") : "";
                sp.confidence = a.has_member ("confidence") ? a.get_string_member ("confidence") : "high";
                if (a.has_member ("entity_id") && !a.get_null_member ("entity_id")) {
                    sp.entity_id = YavannaQualResolver.normalize_entity_id (a.get_string_member ("entity_id"), resolver);
                }
                sp.excerpt = a.has_member ("excerpt") ? a.get_string_member ("excerpt") : @"$source_label ($rule_desc)";
                string resolved_path = sp.file_path;
                if (resolved_path != "" && !GLib.Path.is_absolute (resolved_path) && svc.workspace_dir != "") {
                    resolved_path = GLib.Path.build_filename (svc.workspace_dir, resolved_path);
                }
                if (resolved_path != "" && GLib.FileUtils.test (resolved_path, GLib.FileTest.EXISTS)) {
                    sp.file_path = resolved_path;
                    try {
                        string doc_txt;
                        GLib.FileUtils.get_contents (resolved_path, out doc_txt);
                        string slice = QualSpanParser.extract_lines_slice (doc_txt, sp.line_start, sp.line_end);
                        sp.source_sha256 = QualSpanParser.compute_sha256 (slice != "" ? slice : sp.excerpt);
                    } catch (GLib.Error fe) {
                        sp.source_sha256 = QualSpanParser.compute_sha256 (sp.excerpt);
                    }
                } else {
                    sp.source_sha256 = QualSpanParser.compute_sha256 (sp.excerpt);
                }

                svc.db.upsert_span (sp, actor_id, @"Arekyer hook ($source_label): $rule_desc");
                count++;
            }
            return count;
        }

        public static int ingest_hook_file (
            QualWorkspaceService svc,
            string hook_file_path,
            string default_doc_path = "",
            string actor_id = "arekyer-hook"
        ) throws GLib.Error {
            string contents;
            GLib.FileUtils.get_contents (hook_file_path, out contents);
            return ingest_hook_json (svc, contents, default_doc_path, actor_id);
        }

        public static string generate_r_hook_snippet (string df_name = "deseq2_res") {
            return """```{r arekyer-qual-hook}
# Emit .qual-hook.json mapping quantitative DESeq2 thresholds to qualitative tags
sig_hits <- subset(%s, !is.na(padj) & padj < 0.05 & abs(log2FoldChange) > 1.5)
ann <- lapply(seq_len(nrow(sig_hits)), function(i) {
  r <- sig_hits[i, ]
  list(
    entity_id = paste0("Ensembl:", r$gene_id),
    code_id = ifelse(r$log2FoldChange > 0, "deg-up", "deg-down"),
    valence = ifelse(r$log2FoldChange > 0, "upregulated", "downregulated"),
    confidence = "high",
    excerpt = sprintf("%%s log2FC=%%.2f, padj=%%.3g", r$gene_id, r$log2FoldChange, r$padj)
  )
})
jsonlite::write_json(list(
  source = "R / DESeq2 Chunk",
  domain = "gene-expr",
  rules_applied = "padj < 0.05 & |log2FC| > 1.5",
  annotations = ann
), ".qual-hook.json", auto_unbox = TRUE, pretty = TRUE)
```
""".printf (df_name);
        }
    }
}
