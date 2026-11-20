// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris.Core {

    public class CodeChunk : GLib.Object {
        public int start_line { get; set; }
        public int end_line { get; set; }
        public string language { owned get; set; }
        public string code { owned get; set; }
        public string header { owned get; set; }
        public bool eval_enabled { get; set; default = true; }
        public string chunk_label { owned get; set; default = ""; }
        public bool echo { get; set; default = true; }
        public bool include { get; set; default = true; }
        public bool warning_enabled { get; set; default = true; }
        public bool error_enabled { get; set; default = false; }
        public string output_mode { owned get; set; default = "true"; }
        public string fig_cap { owned get; set; default = ""; }
        public bool unclosed_eof { get; set; default = false; }
        public bool is_executable { get; set; default = true; }

        public CodeChunk (
            int start_line,
            int end_line,
            string language,
            string code,
            string header = "",
            bool eval_enabled = true,
            string chunk_label = ""
        ) {
            this.start_line = start_line;
            this.end_line = end_line;
            this.language = language;
            this.code = code;
            this.header = header;
            this.eval_enabled = eval_enabled;
            this.chunk_label = chunk_label;
            this.is_executable = ChunkParser.is_executable_language (language);
        }
    }

    public class ChunkParser : GLib.Object {

        public static Gee.ArrayList<CodeChunk> parse_all_fences (
            string buffer_text,
            string format_code = "qmd"
        ) {
            var chunks = new Gee.ArrayList<CodeChunk> ();
            string[] lines = buffer_text.split ("\n");
            bool inside_chunk = false;
            char fence_char = '`';
            int fence_length = 0;
            int start_line = -1;
            string header = "";
            string language = "";
            string chunk_label = "";
            var code = new GLib.StringBuilder ();
            CodeChunk? current = null;

            for (int i = 0; i < lines.length; i++) {
                string raw = lines[i];
                string trimmed = raw.strip ();

                if (!inside_chunk) {
                    int prefix_length = 0;
                    while (prefix_length < raw.length &&
                           (raw[prefix_length] == ' ' || raw[prefix_length] == '\t')) {
                        prefix_length++;
                    }
                    if (prefix_length > 3 || prefix_length >= raw.length) {
                        continue;
                    }

                    char candidate_fence = raw[prefix_length];
                    if (candidate_fence != '`' && candidate_fence != '~') {
                        continue;
                    }
                    int run_length = 0;
                    while (prefix_length + run_length < raw.length &&
                           raw[prefix_length + run_length] == candidate_fence) {
                        run_length++;
                    }
                    if (run_length < 3) {
                        continue;
                    }

                    string info = raw.substring (prefix_length + run_length).strip ();
                    if (candidate_fence == '`' && info.contains ("`")) {
                        continue;
                    }
                    parse_fence_info (info, out language, out chunk_label);
                    if (language == "") {
                        language = "text";
                    }

                    fence_char = candidate_fence;
                    fence_length = run_length;
                    start_line = i;
                    header = raw.strip ();
                    code.truncate (0);
                    current = new CodeChunk (start_line, -1, language, "", header, true, chunk_label);
                    parse_header_options (info, current);
                    inside_chunk = true;
                    continue;
                }

                if (is_closing_fence (raw, fence_char, fence_length) && current != null) {
                    current.end_line = i;
                    current.code = code.str;
                    chunks.add (current);
                    current = null;
                    inside_chunk = false;
                    continue;
                }

                if (current != null && trimmed.has_prefix ("#|")) {
                    parse_option (current, trimmed.substring (2).strip ());
                    continue;
                }
                code.append (raw);
                code.append_c ('\n');
            }

            if (inside_chunk && current != null) {
                current.end_line = lines.length - 1;
                current.code = code.str;
                current.unclosed_eof = true;
                chunks.add (current);
            }

            return chunks;
        }

        public static Gee.ArrayList<CodeChunk> parse_chunks (string buffer_text) {
            var executable = new Gee.ArrayList<CodeChunk> ();
            foreach (var chunk in parse_all_fences (buffer_text)) {
                if (chunk.is_executable) {
                    executable.add (chunk);
                }
            }
            return executable;
        }

        public static CodeChunk? find_chunk_at_line (string buffer_text, int line_num) {
            foreach (var chunk in parse_chunks (buffer_text)) {
                if (line_num >= chunk.start_line && line_num <= chunk.end_line) {
                    return chunk;
                }
            }
            return null;
        }

        private static bool is_closing_fence (string raw, char fence_char, int minimum_length) {
            string trimmed = raw.strip ();
            int run_length = 0;
            while (run_length < trimmed.length && trimmed[run_length] == fence_char) {
                run_length++;
            }
            return run_length >= minimum_length && trimmed.substring (run_length).strip () == "";
        }

        public static bool is_executable_language (string language) {
            switch (language.down ()) {
            case "r":
            case "python":
            case "julia":
            case "bash":
            case "sh":
            case "sql":
            case "typescript":
            case "ts":
            case "javascript":
            case "js":
                return true;
            default:
                return false;
            }
        }

        private static void parse_fence_info (string info, out string language, out string label) {
            string clean = info.strip ();
            if (clean.has_prefix ("{")) {
                int close = clean.index_of ("}");
                clean = close > 0 ? clean.substring (1, close - 1) : clean.substring (1);
            }

            language = "";
            label = "";
            string[] parts = clean.split (",");
            if (parts.length == 0) {
                return;
            }

            string[] first_words = parts[0].strip ().split (" ");
            foreach (string word in first_words) {
                string token = word.strip ();
                if (token == "") continue;
                if (language == "") {
                    language = normalize_language (token);
                } else if (label == "" && !token.contains ("=")) {
                    label = token;
                }
            }
            for (int i = 1; i < parts.length && label == ""; i++) {
                string token = parts[i].strip ();
                if (token.has_prefix ("label=")) {
                    label = token.substring (6).replace ("\"", "").replace ("'", "").strip ();
                } else if (!token.contains ("=")) {
                    label = token;
                }
            }
        }

        private static string normalize_language (string language) {
            string normalized = language.down ();
            if (normalized == "py" || normalized == "python3") return "python";
            if (normalized == "shell" || normalized == "zsh") return "bash";
            if (normalized == "ts") return "typescript";
            if (normalized == "js") return "javascript";
            return normalized;
        }

        private static void parse_option (CodeChunk chunk, string option) {
            string[] pair = option.split (":", 2);
            if (pair.length == 2) {
                apply_option (chunk, pair[0].strip (), pair[1].strip ());
                return;
            }
            pair = option.split ("=", 2);
            if (pair.length == 2) {
                apply_option (chunk, pair[0].strip (), pair[1].strip ());
            }
        }

        private static void parse_header_options (string info, CodeChunk chunk) {
            string clean = info.strip ();
            if (clean.has_prefix ("{")) {
                int close = clean.index_of ("}");
                clean = close > 0 ? clean.substring (1, close - 1) : clean.substring (1);
            }

            string[] parts = clean.split (",");
            for (int i = 0; i < parts.length; i++) {
                string[] words = parts[i].strip ().split (" ");
                for (int j = 0; j < words.length; j++) {
                    string token = words[j].strip ();
                    if (token == "") continue;
                    if (i == 0 && j == 0) continue;
                    if (i == 0 && j == 1 && !token.contains ("=")) continue;
                    string[] pair = token.split ("=", 2);
                    if (pair.length == 2) {
                        apply_option (chunk, pair[0].strip (), pair[1].strip ());
                    }
                }
            }
        }

        private static void apply_option (CodeChunk chunk, string key, string value) {
            string normalized_key = key.down ();
            string normalized_value = value.down ().replace ("\"", "").replace ("'", "");
            bool enabled = normalized_value != "false" &&
                           normalized_value != "f" &&
                           normalized_value != "no" &&
                           normalized_value != "0";
            switch (normalized_key) {
            case "eval":
                chunk.eval_enabled = enabled;
                break;
            case "echo":
                chunk.echo = enabled;
                break;
            case "include":
                chunk.include = enabled;
                break;
            case "warning":
                chunk.warning_enabled = enabled;
                break;
            case "error":
                chunk.error_enabled = enabled;
                break;
            case "output":
                chunk.output_mode = value.strip ().replace ("\"", "").replace ("'", "");
                break;
            case "fig-cap":
                chunk.fig_cap = value.strip ().replace ("\"", "").replace ("'", "");
                break;
            case "label":
                chunk.chunk_label = value.strip ().replace ("\"", "").replace ("'", "");
                break;
            }
        }
    }
}
