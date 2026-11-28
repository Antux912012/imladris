// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Json;

namespace Imladris.Qual {

    public enum SdvStatus {
        VERIFIED,
        MODIFIED,
        UNVERIFIED;

        public string to_label () {
            switch (this) {
                case VERIFIED: return "Verified";
                case MODIFIED: return "Hash Mismatch";
                default: return "Unverified";
            }
        }
    }

    public class QualSpan : GLib.Object {
        public string span_id { get; set; default = ""; }
        public string file_path { get; set; default = ""; }
        public int line_start { get; set; default = 1; }
        public int line_end { get; set; default = 1; }
        public int byte_start { get; set; default = 0; }
        public int byte_end { get; set; default = 0; }
        public string source_sha256 { get; set; default = ""; }
        public string excerpt { get; set; default = ""; }
        public string domain { get; set; default = "general"; }
        public string code_id { get; set; default = ""; }
        public string valence { get; set; default = ""; }
        public string? entity_id { get; set; default = null; }
        public string coder_id { get; set; default = ""; }
        public string? confidence { get; set; default = null; }
        public string? citation_key { get; set; default = null; }
        public string? source_uri { get; set; default = null; }
        public string created_utc { get; set; default = ""; }
        public Gee.HashMap<string, string> extra_attrs { get; owned set; }

        public QualSpan () {
            extra_attrs = new Gee.HashMap<string, string> ();
            created_utc = now_iso8601_utc ();
        }

        public static string now_iso8601_utc () {
            return new GLib.DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ");
        }

        public static string generate_short_id () {
            string raw = GLib.Uuid.string_random ().replace ("-", "");
            return "q-" + raw.substring (0, 8);
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("span_id"); b.add_string_value (span_id);
            b.set_member_name ("file_path"); b.add_string_value (file_path);
            b.set_member_name ("line_start"); b.add_int_value (line_start);
            b.set_member_name ("line_end"); b.add_int_value (line_end);
            b.set_member_name ("byte_start"); b.add_int_value (byte_start);
            b.set_member_name ("byte_end"); b.add_int_value (byte_end);
            b.set_member_name ("source_sha256"); b.add_string_value (source_sha256);
            b.set_member_name ("excerpt"); b.add_string_value (excerpt);
            b.set_member_name ("domain"); b.add_string_value (domain);
            b.set_member_name ("code_id"); b.add_string_value (code_id);
            b.set_member_name ("valence"); b.add_string_value (valence);
            b.set_member_name ("entity_id");
            if (entity_id != null) b.add_string_value (entity_id); else b.add_null_value ();
            b.set_member_name ("coder_id"); b.add_string_value (coder_id);
            b.set_member_name ("confidence");
            if (confidence != null) b.add_string_value (confidence); else b.add_null_value ();
            b.set_member_name ("citation_key");
            if (citation_key != null) b.add_string_value (citation_key); else b.add_null_value ();
            b.set_member_name ("source_uri");
            if (source_uri != null) b.add_string_value (source_uri); else b.add_null_value ();
            b.set_member_name ("created_utc"); b.add_string_value (created_utc);
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }
    }

    public class QualMemo : GLib.Object {
        public string memo_id { get; set; default = ""; }
        public string target_id { get; set; default = ""; }
        public string author_id { get; set; default = ""; }
        public string body { get; set; default = ""; }
        public string created_utc { get; set; default = ""; }

        public QualMemo () {
            memo_id = "m-" + GLib.Uuid.string_random ().replace ("-", "").substring (0, 8);
            created_utc = QualSpan.now_iso8601_utc ();
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("memo_id"); b.add_string_value (memo_id);
            b.set_member_name ("target_id"); b.add_string_value (target_id);
            b.set_member_name ("author_id"); b.add_string_value (author_id);
            b.set_member_name ("body"); b.add_string_value (body);
            b.set_member_name ("created_utc"); b.add_string_value (created_utc);
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }
    }

    public class QualNetworkEdge : GLib.Object {
        public string edge_id { get; set; default = ""; }
        public string source_node { get; set; default = ""; }
        public string target_node { get; set; default = ""; }
        public string relation_type { get; set; default = "co_occurs"; }
        public double weight { get; set; default = 1.0; }
        public string? evidence_span_id { get; set; default = null; }

        public QualNetworkEdge () {
            edge_id = "e-" + GLib.Uuid.string_random ().replace ("-", "").substring (0, 8);
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("edge_id"); b.add_string_value (edge_id);
            b.set_member_name ("source_node"); b.add_string_value (source_node);
            b.set_member_name ("target_node"); b.add_string_value (target_node);
            b.set_member_name ("relation_type"); b.add_string_value (relation_type);
            b.set_member_name ("weight"); b.add_double_value (weight);
            b.set_member_name ("evidence_span_id");
            if (evidence_span_id != null) b.add_string_value (evidence_span_id); else b.add_null_value ();
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }
    }

    public class QualAuditEntry : GLib.Object {
        public int64 log_id { get; set; default = 0; }
        public string timestamp_utc { get; set; default = ""; }
        public string user_id { get; set; default = ""; }
        public string action { get; set; default = ""; }
        public string target_table { get; set; default = ""; }
        public string target_id { get; set; default = ""; }
        public string? previous_json { get; set; default = null; }
        public string? new_json { get; set; default = null; }
        public string? rationale { get; set; default = null; }
    }

    public class QualReviewQuery : GLib.Object {
        public string query_id { get; set; default = ""; }
        public string span_id { get; set; default = ""; }
        public string raised_by { get; set; default = ""; }
        public string status { get; set; default = "Open"; }
        public string message { get; set; default = ""; }
        public string? resolution_note { get; set; default = null; }
        public string updated_utc { get; set; default = ""; }

        public QualReviewQuery () {
            query_id = "rq-" + GLib.Uuid.string_random ().replace ("-", "").substring (0, 8);
            updated_utc = QualSpan.now_iso8601_utc ();
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("query_id"); b.add_string_value (query_id);
            b.set_member_name ("span_id"); b.add_string_value (span_id);
            b.set_member_name ("raised_by"); b.add_string_value (raised_by);
            b.set_member_name ("status"); b.add_string_value (status);
            b.set_member_name ("message"); b.add_string_value (message);
            b.set_member_name ("resolution_note");
            if (resolution_note != null) b.add_string_value (resolution_note); else b.add_null_value ();
            b.set_member_name ("updated_utc"); b.add_string_value (updated_utc);
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }
    }

    public class QualAiSuggestion : GLib.Object {
        public string suggestion_id { get; set; default = ""; }
        public string file_path { get; set; default = ""; }
        public int line_start { get; set; default = 1; }
        public int line_end { get; set; default = 1; }
        public string excerpt { get; set; default = ""; }
        public string domain { get; set; default = "protein"; }
        public string suggested_code_id { get; set; default = ""; }
        public string? entity_id { get; set; default = null; }
        public string confidence { get; set; default = "moderate"; }
        public string valence { get; set; default = "neutral"; }
        public string rationale { get; set; default = ""; }
        public string status { get; set; default = "Pending Review"; }
        public string created_utc { get; set; default = ""; }

        public QualAiSuggestion () {
            suggestion_id = "ai-" + GLib.Uuid.string_random ().replace ("-", "").substring (0, 8);
            created_utc = QualSpan.now_iso8601_utc ();
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("suggestion_id"); b.add_string_value (suggestion_id);
            b.set_member_name ("file_path"); b.add_string_value (file_path);
            b.set_member_name ("line_start"); b.add_int_value (line_start);
            b.set_member_name ("line_end"); b.add_int_value (line_end);
            b.set_member_name ("excerpt"); b.add_string_value (excerpt);
            b.set_member_name ("domain"); b.add_string_value (domain);
            b.set_member_name ("suggested_code_id"); b.add_string_value (suggested_code_id);
            b.set_member_name ("entity_id");
            if (entity_id != null) b.add_string_value (entity_id); else b.add_null_value ();
            b.set_member_name ("confidence"); b.add_string_value (confidence);
            b.set_member_name ("valence"); b.add_string_value (valence);
            b.set_member_name ("rationale"); b.add_string_value (rationale);
            b.set_member_name ("status"); b.add_string_value (status);
            b.set_member_name ("created_utc"); b.add_string_value (created_utc);
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }
    }

    public class QualCodeDef : GLib.Object {
        public string id { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public string color { get; set; default = "#88C0D0"; }
        public string? parent_id { get; set; default = null; }
        public int depth { get; set; default = 0; }
        public Gee.ArrayList<QualCodeDef> children { get; owned set; }

        public QualCodeDef (string id, string label, string color = "#88C0D0", string? parent_id = null, int depth = 0) {
            this.id = id;
            this.label = label;
            this.color = color;
            this.parent_id = parent_id;
            this.depth = depth;
            this.children = new Gee.ArrayList<QualCodeDef> ();
        }
    }

    public class QualDomainProfile : GLib.Object {
        public string profile_id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string version { get; set; default = "1.0.0"; }
        public string domain_slug { get; set; default = "general"; }
        public string entity_resolver { get; set; default = ""; }
        public Gee.HashMap<string, Gee.ArrayList<string>> scales { get; owned set; }
        public Gee.ArrayList<QualCodeDef> codes { get; owned set; }

        public QualDomainProfile () {
            scales = new Gee.HashMap<string, Gee.ArrayList<string>> ();
            codes = new Gee.ArrayList<QualCodeDef> ();
        }

        public Gee.ArrayList<QualCodeDef> flatten_codes () {
            var list = new Gee.ArrayList<QualCodeDef> ();
            foreach (var c in codes) {
                collect_recursive (c, list, 0);
            }
            return list;
        }

        private void collect_recursive (QualCodeDef node, Gee.ArrayList<QualCodeDef> acc, int d) {
            node.depth = d;
            acc.add (node);
            foreach (var child in node.children) {
                if (child.color == "" || child.color == "#88C0D0") {
                    if (node.color != "") child.color = node.color;
                }
                collect_recursive (child, acc, d + 1);
            }
        }

        public QualCodeDef? find_code (string code_id) {
            foreach (var c in flatten_codes ()) {
                if (c.id == code_id) return c;
            }
            return null;
        }
    }
}
