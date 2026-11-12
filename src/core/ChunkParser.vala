// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Core {

    public class CodeChunk : GLib.Object {
        public int start_line { get; set; }
        public int end_line { get; set; }
        public string language { owned get; set; }
        public string code { owned get; set; }
        public string header { owned get; set; }
        public bool eval_enabled { get; set; default = true; }
        public string chunk_label { owned get; set; default = ""; }

        public CodeChunk (int start_line, int end_line, string language, string code, string header = "", bool eval_enabled = true, string chunk_label = "") {
            this.start_line = start_line;
            this.end_line = end_line;
            this.language = language;
            this.code = code;
            this.header = header;
            this.eval_enabled = eval_enabled;
            this.chunk_label = chunk_label;
        }
    }

    /**
     * Pillar 11: Scans .Rmd, .Qmd, and .ipynb buffers for code chunk blocks.
     */
    public class ChunkParser : GLib.Object {

        public static Gee.ArrayList<CodeChunk> parse_chunks (string buffer_text) {
            var list = new Gee.ArrayList<CodeChunk> ();
            string[] lines = buffer_text.split ("\n");

            bool inside_chunk = false;
            int start_line = -1;
            string language = "r";
            string header = "";
            string chunk_label = "";
            bool eval_enabled = true;
            var code_sb = new GLib.StringBuilder ();

            for (int i = 0; i < lines.length; i++) {
                string trimmed = lines[i].strip ();

                if (!inside_chunk && trimmed.has_prefix ("```") && trimmed.length > 3) {
                    string tag = trimmed.substring (3).strip ();
                    if (tag.has_prefix ("{") && tag.has_suffix ("}")) {
                        tag = tag.substring (1, tag.length - 2).strip ();
                    } else if (tag.has_prefix ("{")) {
                        int close_brace = tag.index_of ("}");
                        if (close_brace > 1) {
                            tag = tag.substring (1, close_brace - 1).strip ();
                        }
                    }

                    string lower_header = tag.down ().replace (" ", "");
                    eval_enabled = !(lower_header.contains ("eval=false") || lower_header.contains ("eval=f"));

                    // Split engine identifier on earliest space, comma, semicolon, or tab
                    int split_idx = -1;
                    for (int c_idx = 0; c_idx < tag.length; c_idx++) {
                        char ch = tag[c_idx];
                        if (ch == ' ' || ch == ',' || ch == ';' || ch == '\t') {
                            split_idx = c_idx;
                            break;
                        }
                    }

                    chunk_label = "";
                    if (split_idx > 0) {
                        string rest = tag.substring (split_idx + 1).strip ();
                        if (rest.has_prefix (",")) {
                            rest = rest.substring (1).strip ();
                        }
                        int comma_idx = rest.index_of (",");
                        string candidate = (comma_idx >= 0) ? rest.substring (0, comma_idx).strip () : rest;
                        if (!candidate.contains ("=") && candidate.length > 0) {
                            chunk_label = candidate;
                        }
                        tag = tag.substring (0, split_idx);
                    }

                    string lang_clean = tag.down ().strip ();
                    if (lang_clean == "py" || lang_clean == "python3") {
                        lang_clean = "python";
                    } else if (lang_clean == "sh" || lang_clean == "shell" || lang_clean == "zsh") {
                        lang_clean = "bash";
                    }

                    if (lang_clean.length > 0) {
                        inside_chunk = true;
                        start_line = i;
                        header = trimmed;
                        code_sb.truncate (0);
                        language = lang_clean;
                        continue;
                    }
                }

                if (inside_chunk && trimmed == "```") {
                    inside_chunk = false;
                    list.add (new CodeChunk (
                        start_line,
                        i,
                        language,
                        code_sb.str.strip (),
                        header,
                        eval_enabled,
                        chunk_label
                    ));
                    continue;
                }

                if (inside_chunk) {
                    if (trimmed.has_prefix ("#|")) {
                        string opt_lower = trimmed.substring (2).strip ().down ().replace (" ", "");
                        if (opt_lower.has_prefix ("eval:false") || opt_lower.has_prefix ("eval:no") || opt_lower.has_prefix ("eval:f")) {
                            eval_enabled = false;
                        }
                    } else {
                        code_sb.append (lines[i] + "\n");
                    }
                }
            }

            return list;
        }

        public static CodeChunk? find_chunk_at_line (string buffer_text, int line_num) {
            var chunks = parse_chunks (buffer_text);
            foreach (var ch in chunks) {
                if (line_num >= ch.start_line && line_num <= ch.end_line) {
                    return ch;
                }
            }
            return null;
        }
    }
}
