// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Core {

    /**
     * Bidirectional Jupyter Notebook (.ipynb nbformat 4.5) serializer backed by
     * Rust imladris-core for lossless metadata, cell ID, attachment, and fence round-tripping.
     */
    public class NotebookSerializer : GLib.Object {

        public static string ipynb_to_markdown (string json_content) throws GLib.Error {
            if (json_content.strip ().length == 0) {
                return "";
            }
            string res_json = NativeCore.ipynb_to_editor_json (json_content);
            var parser = new Json.Parser ();
            parser.load_from_data (res_json, -1);
            var root = parser.get_root ();
            if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                var obj = root.get_object ();
                if (obj.has_member ("editor")) {
                    return obj.get_string_member ("editor");
                }
            }
            return "";
        }

        public static string detect_notebook_language (string markdown_content) {
            var chunks = ChunkParser.parse_chunks (markdown_content);
            foreach (var ch in chunks) {
                string l = ch.language.strip ().down ();
                if (l == "r" || l == "ir") return "r";
                if (l == "julia") return "julia";
                if (l == "python" || l == "py") return "python";
            }
            return "python";
        }

        public static string markdown_to_ipynb (
            string markdown_content,
            string existing_ipynb_or_lang = "",
            string outputs_map_json = "{}"
        ) throws GLib.Error {
            string existing_json = "";
            string trimmed_arg = existing_ipynb_or_lang.strip ();
            if (trimmed_arg.has_prefix ("{")) {
                existing_json = trimmed_arg;
            } else {
                string lang = trimmed_arg.down ();
                if (lang == "" || lang == "python3" || lang == "py") {
                    lang = detect_notebook_language (markdown_content);
                }
                string kname = (lang == "r") ? "ir" : (lang == "julia" ? "julia-1.0" : "python3");
                string kdisp = (lang == "r") ? "R" : (lang == "julia" ? "Julia" : "Python 3");
                var b = new Json.Builder ();
                b.begin_object ();
                b.set_member_name ("cells"); b.begin_array (); b.end_array ();
                b.set_member_name ("metadata"); b.begin_object ();
                b.set_member_name ("kernelspec"); b.begin_object ();
                b.set_member_name ("display_name"); b.add_string_value (kdisp);
                b.set_member_name ("language"); b.add_string_value (lang);
                b.set_member_name ("name"); b.add_string_value (kname);
                b.end_object ();
                b.set_member_name ("language_info"); b.begin_object ();
                b.set_member_name ("name"); b.add_string_value (lang);
                b.end_object ();
                b.end_object ();
                b.set_member_name ("nbformat"); b.add_int_value (4);
                b.set_member_name ("nbformat_minor"); b.add_int_value (5);
                b.end_object ();
                var gen = new Json.Generator ();
                gen.set_root (b.get_root ());
                existing_json = gen.to_data (null);
            }

            string res_json = NativeCore.editor_to_ipynb_json (markdown_content, existing_json, outputs_map_json);
            var parser = new Json.Parser ();
            parser.load_from_data (res_json, -1);
            var root = parser.get_root ();
            if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                var obj = root.get_object ();
                if (obj.has_member ("ipynb")) {
                    return obj.get_string_member ("ipynb");
                }
            }
            return "{}";
        }

        public static string get_default_ipynb_markdown_template (string default_lang = "python") {
            string lang = (default_lang.down () == "r") ? "r" : "python";
            string kernel_name = (lang == "r") ? "ir" : "python3";
            string display_name = (lang == "r") ? "R" : "Python 3 (ipykernel)";
            var sb = new StringBuilder ();

            sb.append ("---\n");
            sb.append ("title: \"Untitled Notebook\"\n");
            sb.append ("jupyter:\n");
            sb.append ("  kernelspec:\n");
            sb.append_printf ("    display_name: \"%s\"\n", display_name);
            sb.append_printf ("    language: %s\n", lang);
            sb.append_printf ("    name: %s\n", kernel_name);
            sb.append ("---\n\n");

            sb.append ("# Jupyter Notebook\n\n");
            sb.append ("Interactive computational cells with reproducible execution.\n\n");

            if (lang == "r") {
                sb.append ("```{r}\n");
                sb.append ("# R Notebook Setup\n");
                sb.append ("library(datasets)\n");
                sb.append ("summary(cars)\n");
                sb.append ("```\n");
            } else {
                sb.append ("```{python}\n");
                sb.append ("# Python Notebook Setup\n");
                sb.append ("import numpy as np\n");
                sb.append ("import pandas as pd\n\n");
                sb.append ("print(\"Jupyter Notebook kernel session initialized.\")\n");
                sb.append ("```\n");
            }

            return sb.str;
        }
    }
}
