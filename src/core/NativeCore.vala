/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;

namespace Imladris.Core {

    /**
     * Memory-safe Vala wrapper around the Rust imladris_core static library.
     * Every raw C string returned by Rust is copied into a managed Vala string
     * and freed immediately via imladris_free_string().
     */
    public class NativeCore : GLib.Object {

        private static string take_and_free (char* raw_ptr) {
            if (raw_ptr == null) return "{}";
            string copy = (string) raw_ptr;
            RustFFI.free_string (raw_ptr);
            return copy;
        }

        public static string parse_frontmatter_json (string source) {
            return take_and_free (RustFFI.parse_frontmatter_json_raw (source));
        }

        public static string parse_chunks_json (string source, string format_code = "qmd") {
            return take_and_free (RustFFI.parse_chunks_json_raw (source, format_code));
        }

        public static string extract_outline_json (string source, string format_code = "qmd") {
            return take_and_free (RustFFI.extract_outline_json_raw (source, format_code));
        }

        public static string render_markdown_html (string body, string options_json = "{}") {
            return take_and_free (RustFFI.render_markdown_html_raw (body, options_json));
        }

        public static string ipynb_to_editor_json (string ipynb_json) {
            return take_and_free (RustFFI.ipynb_to_editor_json_raw (ipynb_json));
        }

        public static string editor_to_ipynb_json (string editor_text, string existing_ipynb = "", string outputs_map_json = "{}") {
            return take_and_free (RustFFI.editor_to_ipynb_json_raw (editor_text, existing_ipynb, outputs_map_json));
        }

        public static string parse_latex_log_json (string log_text) {
            return take_and_free (RustFFI.parse_latex_log_json_raw (log_text));
        }

        public static string analyze_typescript_symbols_json (string ts_source) {
            return take_and_free (RustFFI.analyze_typescript_symbols_json_raw (ts_source));
        }
    }
}
