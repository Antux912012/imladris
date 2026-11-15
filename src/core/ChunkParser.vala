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
        public bool echo { get; set; default = true; }
        public bool include { get; set; default = true; }
        public bool warning_enabled { get; set; default = true; }
        public bool error_enabled { get; set; default = false; }
        public string output_mode { owned get; set; default = "true"; }
        public string fig_cap { owned get; set; default = ""; }
        public bool unclosed_eof { get; set; default = false; }
        public bool is_executable { get; set; default = true; }

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
     * Scans .Rmd, .Qmd, and .ipynb buffers using Rust imladris-core CommonMark
     * fence scanner + YAML/attribute option parser.
     */
    public class ChunkParser : GLib.Object {

        public static Gee.ArrayList<CodeChunk> parse_all_fences (string buffer_text, string format_code = "qmd") {
            var list = new Gee.ArrayList<CodeChunk> ();
            string json_str = NativeCore.parse_chunks_json (buffer_text, format_code);
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_str, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                    return list;
                }
                var arr = root.get_array ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    var obj = arr.get_object_element (i);
                    int start_line = (int) obj.get_int_member ("fence_start_line");
                    int end_line = (int) obj.get_int_member ("fence_end_line");
                    string lang = obj.get_string_member ("language");
                    string code = obj.get_string_member ("code");
                    string hdr = obj.get_string_member ("raw_header");
                    bool eval_en = obj.get_boolean_member ("eval_enabled");
                    string lbl = obj.get_string_member ("label");

                    var ch = new CodeChunk (start_line, end_line, lang, code, hdr, eval_en, lbl);
                    ch.echo = obj.get_boolean_member ("echo");
                    ch.include = obj.get_boolean_member ("include");
                    ch.warning_enabled = obj.get_boolean_member ("warning");
                    ch.error_enabled = obj.get_boolean_member ("error");
                    ch.output_mode = obj.get_string_member ("output_mode");
                    ch.fig_cap = obj.get_string_member ("fig_cap");
                    ch.unclosed_eof = obj.get_boolean_member ("unclosed_eof");
                    ch.is_executable = obj.get_boolean_member ("is_executable");
                    list.add (ch);
                }
            } catch (GLib.Error e) {
                GLib.warning ("ChunkParser JSON decode error: %s", e.message);
            }
            return list;
        }

        public static Gee.ArrayList<CodeChunk> parse_chunks (string buffer_text) {
            var all = parse_all_fences (buffer_text, "qmd");
            var exec_only = new Gee.ArrayList<CodeChunk> ();
            foreach (var ch in all) {
                if (ch.is_executable) {
                    exec_only.add (ch);
                }
            }
            return exec_only;
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
