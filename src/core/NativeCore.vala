// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Core {

    public class NativeCore : GLib.Object {

        private static GLib.Regex? ts_decl_regex = null;
        private static GLib.Regex? outline_heading_regex = null;
        private static GLib.Regex? outline_chunk_regex = null;
        private static GLib.Regex? latex_error_line_regex = null;

        private static GLib.Regex compile_required_regex (string pattern) {
            try {
                return new GLib.Regex (pattern);
            } catch (GLib.RegexError e) {
                GLib.error ("Invalid built-in regular expression: %s", e.message);
            }
        }

        private static string serialize_json (Json.Builder builder) {
            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            return generator.to_data (null);
        }

        public static string analyze_typescript_symbols_json (string source) {
            var builder = new Json.Builder ();
            var seen = new Gee.HashSet<string> ();
            if (ts_decl_regex == null) {
                ts_decl_regex = compile_required_regex (
                    "^\\s*(?:export\\s+)?(?:default\\s+)?(?:declare\\s+)?(?:async\\s+)?(function|class|interface|type|enum|const|let|var)\\s+([A-Za-z_$][A-Za-z0-9_$]*)"
                );
            }
            var declaration = ts_decl_regex;

            builder.begin_array ();
            string[] lines = source.split ("\n");
            bool in_block_comment = false;
            for (int i = 0; i < lines.length; i++) {
                string trimmed_l = lines[i].strip ();
                if (in_block_comment) {
                    if (trimmed_l.contains ("*/")) in_block_comment = false;
                    continue;
                }
                if (trimmed_l.has_prefix ("/*")) {
                    if (!trimmed_l.contains ("*/")) in_block_comment = true;
                    continue;
                }
                if (trimmed_l.has_prefix ("//")) continue;

                GLib.MatchInfo match_info;
                if (!declaration.match (lines[i], 0, out match_info)) {
                    continue;
                }

                string kind = match_info.fetch (1);
                string name = match_info.fetch (2);
                string code_part = lines[i];
                int c_idx = code_part.index_of ("//");
                if (c_idx >= 0) code_part = code_part.substring (0, c_idx);
                if ((kind == "const" || kind == "let" || kind == "var") && code_part.contains ("=>")) {
                    kind = "function";
                }
                string key = @"$kind:$name";
                if (seen.contains (key)) {
                    continue;
                }
                seen.add (key);

                builder.begin_object ();
                builder.set_member_name ("name");
                builder.add_string_value (name);
                builder.set_member_name ("kind");
                builder.add_string_value (kind);
                builder.set_member_name ("line");
                builder.add_int_value (i + 1);
                builder.end_object ();
            }
            builder.end_array ();
            return serialize_json (builder);
        }

        public static string extract_outline_json (string source, string format_code = "qmd") {
            var builder = new Json.Builder ();
            if (outline_heading_regex == null) {
                outline_heading_regex = compile_required_regex ("^\\s*(#{1,6})\\s+(.+?)\\s*#*\\s*$");
            }
            if (outline_chunk_regex == null) {
                outline_chunk_regex = compile_required_regex ("^\\s*```\\s*\\{([A-Za-z0-9_+-]+)(?:\\s+([^,}]+))?");
            }
            var heading_regex = outline_heading_regex;
            var chunk_regex = outline_chunk_regex;
            string fmt = format_code.down ().strip ();
            bool in_fence = false;
            string pending_chunk_lang = "";
            int pending_chunk_line = 0;
            bool pending_chunk_emitted = false;

            builder.begin_array ();
            string[] lines = source.split ("\n");
            for (int i = 0; i < lines.length; i++) {
                string line = lines[i];
                string trimmed = line.strip ();
                if (in_fence) {
                    if (trimmed.has_prefix ("```") || trimmed.has_prefix ("~~~")) {
                        in_fence = false;
                        pending_chunk_lang = "";
                        pending_chunk_emitted = false;
                    } else if (!pending_chunk_emitted && trimmed.has_prefix ("#|") && trimmed.contains ("label:")) {
                        int lbl_idx = trimmed.index_of ("label:") + 6;
                        string lbl = trimmed.substring (lbl_idx).strip ();
                        if (lbl.length > 0) {
                            append_outline_item (builder, 2, @"$lbl ($pending_chunk_lang)", pending_chunk_line, "chunk");
                            pending_chunk_emitted = true;
                        }
                    }
                    continue;
                }

                GLib.MatchInfo chunk_match;
                if (chunk_regex.match (line, 0, out chunk_match)) {
                    string language = chunk_match.fetch (1).down ();
                    string? raw_label = chunk_match.fetch (2);
                    string label = raw_label != null ? raw_label.strip () : "";
                    pending_chunk_lang = language;
                    pending_chunk_line = i + 1;
                    pending_chunk_emitted = false;
                    if (label != "" && !label.contains ("=")) {
                        append_outline_item (builder, 2, @"$label ($language)", i + 1, "chunk");
                        pending_chunk_emitted = true;
                    }
                    in_fence = true;
                    continue;
                }

                if (trimmed.has_prefix ("```") || trimmed.has_prefix ("~~~")) {
                    in_fence = true;
                    continue;
                }

                if (fmt == "tex" || fmt == "latex") {
                    if (trimmed.has_prefix ("\\section{") || trimmed.has_prefix ("\\subsection{") || trimmed.has_prefix ("\\subsubsection{")) {
                        int lvl = trimmed.has_prefix ("\\subsubsection") ? 3 : (trimmed.has_prefix ("\\subsection") ? 2 : 1);
                        int ob = trimmed.index_of_char ('{');
                        int cb = trimmed.last_index_of_char ('}');
                        if (ob >= 0 && cb > ob) {
                            append_outline_item (builder, lvl, trimmed.substring (ob + 1, cb - ob - 1).strip (), i + 1, "heading");
                        }
                    }
                    continue;
                }

                GLib.MatchInfo heading_match;
                if (heading_regex.match (line, 0, out heading_match)) {
                    append_outline_item (
                        builder,
                        heading_match.fetch (1).length,
                        heading_match.fetch (2).strip (),
                        i + 1,
                        "heading"
                    );
                }
            }
            builder.end_array ();
            return serialize_json (builder);
        }

        private static void append_outline_item (
            Json.Builder builder,
            int level,
            string title,
            int line,
            string kind
        ) {
            builder.begin_object ();
            builder.set_member_name ("level");
            builder.add_int_value (level);
            builder.set_member_name ("title");
            builder.add_string_value (title);
            builder.set_member_name ("line");
            builder.add_int_value (line);
            builder.set_member_name ("kind");
            builder.add_string_value (kind);
            builder.end_object ();
        }

        public static string parse_latex_log_json (string log_text) {
            var builder = new Json.Builder ();
            if (latex_error_line_regex == null) {
                latex_error_line_regex = compile_required_regex ("^l\\.(\\d+)\\s*(.*)$");
            }
            var error_line = latex_error_line_regex;
            string? pending_error = null;
            int pending_line = 1;

            builder.begin_array ();
            foreach (string line in log_text.split ("\n")) {
                string trimmed = line.strip ();
                if (trimmed.has_prefix ("!")) {
                    if (pending_error != null) {
                        append_latex_diagnostic (builder, pending_error, pending_line, "error");
                    }
                    pending_error = trimmed.substring (1).strip ();
                    pending_line = 1;
                    continue;
                }

                if (pending_error != null) {
                    GLib.MatchInfo match_info;
                    if (error_line.match (trimmed, 0, out match_info)) {
                        pending_line = int.parse (match_info.fetch (1));
                        string detail = match_info.fetch (2).strip ();
                        if (detail != "") {
                            pending_error = pending_error + " " + detail;
                        }
                        append_latex_diagnostic (builder, pending_error, pending_line, "error");
                        pending_error = null;
                    }
                }
            }
            if (pending_error != null) {
                append_latex_diagnostic (builder, pending_error, pending_line, "error");
            }
            builder.end_array ();
            return serialize_json (builder);
        }

        private static void append_latex_diagnostic (
            Json.Builder builder,
            string message,
            int line,
            string severity
        ) {
            builder.begin_object ();
            builder.set_member_name ("file");
            builder.add_string_value ("");
            builder.set_member_name ("line");
            builder.add_int_value (line);
            builder.set_member_name ("severity");
            builder.add_string_value (severity);
            builder.set_member_name ("message");
            builder.add_string_value (message);
            builder.end_object ();
        }
    }
}
