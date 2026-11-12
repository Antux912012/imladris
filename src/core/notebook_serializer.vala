// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Converts bidirectionally between Jupyter Notebook JSON (.ipynb) and Markdown.
 *
 * Architectural Position:
 * Core serialization engine in Imladris.Core.
 * Downstream consumers: Imladris.Adapters.DocumentAdapter, Imladris.Window, and test suites.
 * Upstream dependencies: Json-GLib 1.0, GLib.Object.
 *
 * Concurrency Constraints:
 * Pure static transformation routines. Re-entrant and thread-safe.
 */

using GLib;
using Json;

namespace Imladris.Core {

    /**
     * Domain model representing an in-memory notebook cell.
     */
    public class NotebookCell : GLib.Object {
        public string cell_type { get; set; default = "code"; }
        public string language { get; set; default = "python"; }
        public string source { get; set; default = ""; }
        public string cell_id { get; set; default = ""; }
        public int execution_count { get; set; default = -1; }
        public Gee.ArrayList<string> tags { get; private set; }

        public NotebookCell (string cell_type, string source, string language = "python", string cell_id = "") {
            this.cell_type = cell_type;
            this.source = source;
            this.language = language;
            this.cell_id = cell_id != "" ? cell_id : NotebookSerializer.generate_cell_id ();
            this.execution_count = -1;
            this.tags = new Gee.ArrayList<string> ();
        }
    }

    /**
     * Bidirectional converter implementing 1:1 parity with Jupyter Notebook (nbformat v4.5).
     */
    public class NotebookSerializer : GLib.Object {

        /**
         * Generates an 8-character unique alphanumeric identifier for nbformat 4.5 cells.
         *
         * @return Random 8-character alphanumeric identifier.
         */
        public static string generate_cell_id () {
            uint32 r1 = GLib.Random.next_int ();
            uint32 r2 = GLib.Random.next_int ();
            return "%04x%04x".printf ((uint) (r1 & 0xFFFF), (uint) (r2 & 0xFFFF));
        }

        /**
         * Converts a Jupyter Notebook (.ipynb) JSON string into editable Markdown text.
         *
         * @param json_content Raw JSON string from .ipynb file.
         * @return Formatted Markdown text with code chunk delimiters.
         * @throws GLib.Error on malformed JSON payload.
         */
        public static string ipynb_to_markdown (string json_content) throws GLib.Error {
            if (json_content.strip ().length == 0) {
                return "";
            }

            var parser = new Json.Parser ();
            parser.load_from_data (json_content);

            var root_node = parser.get_root ();
            if (root_node == null || root_node.get_node_type () != Json.NodeType.OBJECT) {
                return "";
            }

            var root = root_node.get_object ();
            if (!root.has_member ("cells")) {
                return "";
            }

            string default_lang = "python";
            string kernel_name = "python3";
            string display_name = "Python 3";

            if (root.has_member ("metadata")) {
                var meta = root.get_object_member ("metadata");
                if (meta.has_member ("kernelspec")) {
                    var ks = meta.get_object_member ("kernelspec");
                    if (ks.has_member ("language")) {
                        default_lang = ks.get_string_member ("language").down ();
                    }
                    if (ks.has_member ("name")) {
                        kernel_name = ks.get_string_member ("name");
                    }
                    if (ks.has_member ("display_name")) {
                        display_name = ks.get_string_member ("display_name");
                    }
                } else if (meta.has_member ("language_info")) {
                    var li = meta.get_object_member ("language_info");
                    if (li.has_member ("name")) {
                        default_lang = li.get_string_member ("name").down ();
                    }
                }
            }

            // Normalize language identifier
            if (default_lang == "r" || default_lang == "ir") {
                default_lang = "r";
            } else if (default_lang == "julia") {
                default_lang = "julia";
            } else {
                default_lang = "python";
            }

            var cells = root.get_array_member ("cells");
            var builder = new StringBuilder ();

            // Emit YAML Frontmatter anchor for kernelspec metadata
            builder.append ("---\n");
            builder.append_printf ("jupyter:\n");
            builder.append_printf ("  kernelspec:\n");
            builder.append_printf ("    display_name: \"%s\"\n", display_name);
            builder.append_printf ("    language: \"%s\"\n", default_lang);
            builder.append_printf ("    name: \"%s\"\n", kernel_name);
            builder.append ("---\n\n");

            for (uint i = 0; i < cells.get_length (); i++) {
                var cell = cells.get_object_element (i);
                string cell_type = cell.has_member ("cell_type") ? cell.get_string_member ("cell_type") : "markdown";

                // Parse cell source buffer
                var cell_text = new StringBuilder ();
                if (cell.has_member ("source")) {
                    var source_node = cell.get_member ("source");
                    if (source_node.get_node_type () == Json.NodeType.ARRAY) {
                        var source_arr = source_node.get_array ();
                        for (uint j = 0; j < source_arr.get_length (); j++) {
                            cell_text.append (source_arr.get_string_element (j));
                        }
                    } else if (source_node.get_node_type () == Json.NodeType.VALUE) {
                        cell_text.append (source_node.get_string ());
                    }
                }

                string text = cell_text.str;

                // Extract cell id if present
                string cell_id = "";
                if (cell.has_member ("id")) {
                    cell_id = cell.get_string_member ("id");
                }

                // Extract custom cell language or fallback to notebook default
                string cell_lang = default_lang;
                if (cell.has_member ("metadata")) {
                    var c_meta = cell.get_object_member ("metadata");
                    if (c_meta.has_member ("language")) {
                        cell_lang = c_meta.get_string_member ("language");
                    }
                }

                // Extract execution count if present
                int exec_count = -1;
                if (cell.has_member ("execution_count") && !cell.get_null_member ("execution_count")) {
                    exec_count = (int) cell.get_int_member ("execution_count");
                }

                // Extract tags if present
                var tag_list = new Gee.ArrayList<string> ();
                if (cell.has_member ("metadata")) {
                    var c_meta = cell.get_object_member ("metadata");
                    if (c_meta.has_member ("tags")) {
                        var t_arr = c_meta.get_array_member ("tags");
                        for (uint t = 0; t < t_arr.get_length (); t++) {
                            tag_list.add (t_arr.get_string_element (t));
                        }
                    }
                }

                if (cell_type == "markdown") {
                    builder.append (text);
                    if (!text.has_suffix ("\n")) {
                        builder.append ("\n");
                    }
                    builder.append ("\n");
                } else if (cell_type == "code") {
                    builder.append_printf ("```{%s}\n", cell_lang);

                    if (cell_id.length > 0) {
                        builder.append_printf ("#| cell_id: %s\n", cell_id);
                    }

                    if (exec_count >= 0) {
                        builder.append_printf ("#| execution_count: %d\n", exec_count);
                    }

                    if (tag_list.size > 0) {
                        builder.append ("#| tags: [");
                        for (int t = 0; t < tag_list.size; t++) {
                            builder.append_printf ("\"%s\"", tag_list.get (t));
                            if (t < tag_list.size - 1) builder.append (", ");
                        }
                        builder.append ("]\n");
                    }

                    builder.append (text);
                    if (!text.has_suffix ("\n")) {
                        builder.append ("\n");
                    }
                    builder.append ("```\n\n");
                } else if (cell_type == "raw") {
                    builder.append ("```{raw}\n");
                    builder.append (text);
                    if (!text.has_suffix ("\n")) {
                        builder.append ("\n");
                    }
                    builder.append ("```\n\n");
                }
            }

            return builder.str;
        }

        /**
         * Scans Markdown document to detect dominant programming language.
         *
         * @param markdown_content Document text buffer.
         * @return Language string (python, r, julia, bash).
         */
        public static string detect_notebook_language (string markdown_content) {
            string lower = markdown_content.down ();

            if (lower.contains ("```{r") || lower.contains ("```{ r")) {
                return "r";
            }
            if (lower.contains ("```{julia") || lower.contains ("```{ julia")) {
                return "julia";
            }
            if (lower.contains ("```{bash") || lower.contains ("```{sh")) {
                return "bash";
            }
            return "python";
        }

        /**
         * Converts Markdown text into fully compliant Jupyter Notebook (.ipynb) JSON.
         *
         * @param markdown_content Document text with code chunks.
         * @param explicit_default_lang Fallback language string.
         * @return Complete JSON string conforming to nbformat 4.5.
         * @throws GLib.Error on construction failure.
         */
        public static string markdown_to_ipynb (
            string markdown_content,
            string explicit_default_lang = "python"
        ) throws GLib.Error {
            string default_lang = explicit_default_lang.strip ().down ();
            if (default_lang == "" || default_lang == "python3" || default_lang == "py") {
                default_lang = detect_notebook_language (markdown_content);
            }

            var builder = new Json.Builder ();
            builder.begin_object ();

            builder.set_member_name ("cells");
            builder.begin_array ();

            string[] lines = markdown_content.split ("\n");
            bool in_code_chunk = false;
            string current_chunk_lang = default_lang;
            int current_exec_count = -1;
            var current_tags = new Gee.ArrayList<string> ();
            string current_cell_id = "";
            var current_source = new StringBuilder ();
            bool in_yaml_frontmatter = false;
            int yaml_marker_count = 0;

            for (int i = 0; i < lines.length; i++) {
                string line = lines[i];
                string trimmed = line.strip ();

                // Filter out Quarto / Jupyter YAML Frontmatter markers
                if (i == 0 && trimmed == "---") {
                    in_yaml_frontmatter = true;
                    yaml_marker_count++;
                    continue;
                }
                if (in_yaml_frontmatter) {
                    if (trimmed == "---") {
                        in_yaml_frontmatter = false;
                        yaml_marker_count++;
                        continue;
                    }
                    if (trimmed.has_prefix ("language:")) {
                        string lang_val = trimmed.substring (9).replace ("\"", "").replace ("'", "").strip ().down ();
                        if (lang_val == "r" || lang_val == "python" || lang_val == "julia") {
                            default_lang = lang_val;
                            current_chunk_lang = default_lang;
                        }
                    }
                    continue;
                }

                if (!in_code_chunk && trimmed.has_prefix ("```")) {
                    if (current_source.len > 0) {
                        string md_text = current_source.str.strip ();
                        if (md_text.length > 0) {
                            add_cell_to_builder (builder, "markdown", current_source.str, -1, null);
                        }
                        current_source.truncate ();
                    }

                    in_code_chunk = true;
                    current_exec_count = -1;
                    current_tags.clear ();
                    current_cell_id = "";

                    string raw_tag = trimmed.substring (3).strip ();
                    current_chunk_lang = parse_chunk_language (raw_tag, default_lang);
                } else if (in_code_chunk && trimmed == "```") {
                    in_code_chunk = false;
                    string cell_type = (current_chunk_lang == "raw") ? "raw" : "code";
                    add_cell_to_builder (builder, cell_type, current_source.str, current_exec_count, current_tags, current_cell_id, current_chunk_lang);
                    current_source.truncate ();
                    current_tags.clear ();
                    current_exec_count = -1;
                    current_cell_id = "";
                } else if (in_code_chunk) {
                    // Inspect Quarto chunk comments for metadata
                    if (trimmed.has_prefix ("#| cell_id:") || trimmed.has_prefix ("#| id:")) {
                        int colon_idx = trimmed.index_of (":");
                        current_cell_id = trimmed.substring (colon_idx + 1).strip ();
                    } else if (trimmed.has_prefix ("#| execution_count:")) {
                        int colon_idx = trimmed.index_of (":");
                        current_exec_count = int.parse (trimmed.substring (colon_idx + 1).strip ());
                    } else if (trimmed.has_prefix ("#| tags:")) {
                        parse_tags_comment (trimmed, current_tags);
                    } else {
                        current_source.append (line);
                        current_source.append ("\n");
                    }
                } else {
                    current_source.append (line);
                    current_source.append ("\n");
                }
            }

            if (current_source.len > 0) {
                if (in_code_chunk) {
                    string cell_type = (current_chunk_lang == "raw") ? "raw" : "code";
                    add_cell_to_builder (builder, cell_type, current_source.str, current_exec_count, current_tags, current_cell_id, current_chunk_lang);
                } else {
                    string rem = current_source.str.strip ();
                    if (rem.length > 0) {
                        add_cell_to_builder (builder, "markdown", current_source.str, -1, null, null, null);
                    }
                }
            }

            builder.end_array (); // end cells

            // metadata
            builder.set_member_name ("metadata");
            builder.begin_object ();

            builder.set_member_name ("kernelspec");
            builder.begin_object ();

            if (default_lang == "r") {
                builder.set_member_name ("display_name");
                builder.add_string_value ("R");
                builder.set_member_name ("language");
                builder.add_string_value ("R");
                builder.set_member_name ("name");
                builder.add_string_value ("ir");
            } else if (default_lang == "julia") {
                builder.set_member_name ("display_name");
                builder.add_string_value ("Julia");
                builder.set_member_name ("language");
                builder.add_string_value ("julia");
                builder.set_member_name ("name");
                builder.add_string_value ("julia");
            } else {
                builder.set_member_name ("display_name");
                builder.add_string_value ("Python 3");
                builder.set_member_name ("language");
                builder.add_string_value ("python");
                builder.set_member_name ("name");
                builder.add_string_value ("python3");
            }
            builder.end_object ();

            builder.set_member_name ("language_info");
            builder.begin_object ();
            builder.set_member_name ("name");
            builder.add_string_value (default_lang);
            builder.set_member_name ("file_extension");
            builder.add_string_value (default_lang == "r" ? ".r" : (default_lang == "julia" ? ".jl" : ".py"));
            builder.set_member_name ("mimetype");
            builder.add_string_value (default_lang == "r" ? "text/x-r-source" : "text/x-python");
            builder.end_object ();

            builder.end_object (); // end metadata

            // nbformat 4.5 standard
            builder.set_member_name ("nbformat");
            builder.add_int_value (4);
            builder.set_member_name ("nbformat_minor");
            builder.add_int_value (5);

            builder.end_object (); // end root

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            generator.pretty = true;
            generator.indent = 2;
            return generator.to_data (null);
        }

        /**
         * Parses clean language identifier from code chunk tag header.
         */
        private static string parse_chunk_language (string raw_tag, string default_lang) {
            string tag = raw_tag.strip ();

            if (tag.has_prefix ("{") && tag.has_suffix ("}")) {
                tag = tag.slice (1, tag.length - 1).strip ();
            } else if (tag.has_prefix ("{")) {
                int cb = tag.index_of ("}");
                if (cb > 0) tag = tag.slice (1, cb).strip ();
            }

            int space_idx = tag.index_of (" ");
            if (space_idx > 0) {
                tag = tag.substring (0, space_idx).strip ();
            }
            int comma_idx = tag.index_of (",");
            if (comma_idx > 0) {
                tag = tag.substring (0, comma_idx).strip ();
            }

            string clean = tag.down ();
            if (clean == "python" || clean == "py" || clean == "python3") {
                return "python";
            }
            if (clean == "r") {
                return "r";
            }
            if (clean == "julia" || clean == "jl") {
                return "julia";
            }
            if (clean == "raw") {
                return "raw";
            }
            return clean.length > 0 ? clean : default_lang;
        }

        /**
         * Parses comma-separated cell tags from Quarto metadata comment.
         */
        private static void parse_tags_comment (string tag_line, Gee.ArrayList<string> target_list) {
            int bracket_start = tag_line.index_of ("[");
            int bracket_end = tag_line.index_of ("]");
            if (bracket_start > 0 && bracket_end > bracket_start) {
                string inner = tag_line.substring (bracket_start + 1, bracket_end - bracket_start - 1);
                string[] parts = inner.split (",");
                foreach (string p in parts) {
                    string clean = p.replace ("\"", "").replace ("'", "").strip ();
                    if (clean.length > 0) {
                        target_list.add (clean);
                    }
                }
            }
        }

        /**
         * Writes a serialized cell object conforming to nbformat 4.5.
         */
        private static void add_cell_to_builder (
            Json.Builder builder,
            string cell_type,
            string source_text,
            int execution_count,
            Gee.ArrayList<string>? tags,
            string? cell_id = null,
            string? chunk_lang = null
        ) {
            builder.begin_object ();

            builder.set_member_name ("cell_type");
            builder.add_string_value (cell_type);

            builder.set_member_name ("id");
            string final_id = (cell_id != null && cell_id.strip ().length > 0) ? cell_id.strip () : generate_cell_id ();
            builder.add_string_value (final_id);

            builder.set_member_name ("metadata");
            builder.begin_object ();
            if (chunk_lang != null && chunk_lang.strip ().length > 0) {
                builder.set_member_name ("language");
                builder.add_string_value (chunk_lang.strip ());
            }
            if (tags != null && tags.size > 0) {
                builder.set_member_name ("tags");
                builder.begin_array ();
                for (int t = 0; t < tags.size; t++) {
                    builder.add_string_value (tags.get (t));
                }
                builder.end_array ();
            }
            builder.end_object ();

            if (cell_type == "code") {
                builder.set_member_name ("execution_count");
                if (execution_count >= 0) {
                    builder.add_int_value (execution_count);
                } else {
                    builder.add_null_value ();
                }

                builder.set_member_name ("outputs");
                builder.begin_array ();
                builder.end_array ();
            }

            builder.set_member_name ("source");
            builder.begin_array ();
            string[] cell_lines = source_text.split ("\n");
            for (int k = 0; k < cell_lines.length; k++) {
                string l = cell_lines[k];
                if (k < cell_lines.length - 1) {
                    builder.add_string_value (l + "\n");
                } else if (l.length > 0) {
                    builder.add_string_value (l);
                }
            }
            builder.end_array ();

            builder.end_object ();
        }

        /**
         * Returns starter Markdown template for a new Jupyter Notebook.
         *
         * @param default_lang Primary notebook language (python or r).
         * @return Valid Markdown content ready for notebook editing.
         */
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
