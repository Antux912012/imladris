// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

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
            for (int i = 0; i < lines.length; i++) {
                GLib.MatchInfo match_info;
                if (!declaration.match (lines[i], 0, out match_info)) {
                    continue;
                }

                string kind = match_info.fetch (1);
                string name = match_info.fetch (2);
                if (seen.contains (name)) {
                    continue;
                }
                seen.add (name);

                if ((kind == "const" || kind == "let" || kind == "var") && lines[i].contains ("=>")) {
                    kind = "function";
                }

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
            bool in_fence = false;

            builder.begin_array ();
            string[] lines = source.split ("\n");
            for (int i = 0; i < lines.length; i++) {
                string line = lines[i];
                string trimmed = line.strip ();
                if (in_fence) {
                    if (trimmed.has_prefix ("```") || trimmed.has_prefix ("~~~")) {
                        in_fence = false;
                    }
                    continue;
                }

                GLib.MatchInfo chunk_match;
                if (chunk_regex.match (line, 0, out chunk_match)) {
                    string language = chunk_match.fetch (1).down ();
                    string? raw_label = chunk_match.fetch (2);
                    string label = raw_label != null ? raw_label.strip () : "";
                    if (label != "" && !label.contains ("=")) {
                        append_outline_item (builder, 2, @"$label ($language)", i + 1, "chunk");
                    }
                    in_fence = true;
                    continue;
                }

                if (trimmed.has_prefix ("```") || trimmed.has_prefix ("~~~")) {
                    in_fence = true;
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
