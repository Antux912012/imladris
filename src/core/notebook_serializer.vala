// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

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

        private static string extract_source_node (Json.Node? node) {
            if (node == null) return "";
            if (node.get_node_type () == Json.NodeType.ARRAY) {
                var sb = new StringBuilder ();
                var arr = node.get_array ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    sb.append (arr.get_string_element (i));
                }
                return sb.str;
            } else if (node.get_node_type () == Json.NodeType.VALUE) {
                return node.get_string () ?? "";
            }
            return "";
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

            if (root.has_member ("metadata") && !root.get_null_member ("metadata")) {
                var meta_node = root.get_member ("metadata");
                if (meta_node.get_node_type () == Json.NodeType.OBJECT) {
                    var meta = meta_node.get_object ();
                    if (meta.has_member ("kernelspec") && !meta.get_null_member ("kernelspec") &&
                        meta.get_member ("kernelspec").get_node_type () == Json.NodeType.OBJECT) {
                        var ks = meta.get_object_member ("kernelspec");
                        if (ks.has_member ("language") && !ks.get_null_member ("language")) {
                            default_lang = (ks.get_string_member ("language") ?? "python").down ();
                        }
                        if (ks.has_member ("name") && !ks.get_null_member ("name")) {
                            kernel_name = ks.get_string_member ("name") ?? "python3";
                        }
                        if (ks.has_member ("display_name") && !ks.get_null_member ("display_name")) {
                            display_name = ks.get_string_member ("display_name") ?? "Python 3";
                        }
                    } else if (meta.has_member ("language_info") && !meta.get_null_member ("language_info") &&
                               meta.get_member ("language_info").get_node_type () == Json.NodeType.OBJECT) {
                        var li = meta.get_object_member ("language_info");
                        if (li.has_member ("name") && !li.get_null_member ("name")) {
                            default_lang = (li.get_string_member ("name") ?? "python").down ();
                        }
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

            if (!root.has_member ("cells") || root.get_null_member ("cells") ||
                root.get_member ("cells").get_node_type () != Json.NodeType.ARRAY) {
                throw new IOError.INVALID_DATA ("Invalid .ipynb file: missing or non-array 'cells' field.");
            }
            var cells = root.get_array_member ("cells");
            var builder = new StringBuilder ();

            string safe_display = display_name.replace ("\\", "\\\\").replace ("\"", "\\\"");
            string safe_kernel = kernel_name.replace ("\\", "\\\\").replace ("\"", "\\\"");

            // Emit YAML Frontmatter anchor for kernelspec metadata
            builder.append ("---\n");
            builder.append_printf ("jupyter:\n");
            builder.append_printf ("  kernelspec:\n");
            builder.append_printf ("    display_name: \"%s\"\n", safe_display);
            builder.append_printf ("    language: \"%s\"\n", default_lang);
            builder.append_printf ("    name: \"%s\"\n", safe_kernel);
            builder.append ("---\n\n");

            for (uint i = 0; i < cells.get_length (); i++) {
                var cell_node = cells.get_element (i);
                if (cell_node == null || cell_node.get_node_type () != Json.NodeType.OBJECT) continue;
                var cell = cell_node.get_object ();
                string cell_type = (cell.has_member ("cell_type") && !cell.get_null_member ("cell_type"))
                    ? (cell.get_string_member ("cell_type") ?? "markdown") : "markdown";

                // Parse cell source buffer safely
                var cell_text = new StringBuilder ();
                if (cell.has_member ("source") && !cell.get_null_member ("source")) {
                    var source_node = cell.get_member ("source");
                    if (source_node.get_node_type () == Json.NodeType.ARRAY) {
                        var source_arr = source_node.get_array ();
                        for (uint j = 0; j < source_arr.get_length (); j++) {
                            var s_el = source_arr.get_element (j);
                            if (s_el != null && s_el.get_node_type () == Json.NodeType.VALUE) {
                                cell_text.append (s_el.get_string () ?? "");
                            }
                        }
                    } else if (source_node.get_node_type () == Json.NodeType.VALUE) {
                        cell_text.append (source_node.get_string () ?? "");
                    }
                }

                string text = cell_text.str;

                // Extract cell id if present
                string cell_id = "";
                if (cell.has_member ("id") && !cell.get_null_member ("id")) {
                    cell_id = cell.get_string_member ("id") ?? "";
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

                builder.append_printf ("<!-- imladris:cell type=%s id=%s -->\n", cell_type, cell_id);

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

                    string output_preview = "";
                    if (cell.has_member ("outputs") && !cell.get_null_member ("outputs")) {
                        var out_node = cell.get_member ("outputs");
                        if (out_node.get_node_type () == Json.NodeType.ARRAY) {
                            var out_arr = out_node.get_array ();
                            if (out_arr.get_length () > 0) {
                                var preview_sb = new StringBuilder ();
                                for (uint oi = 0; oi < out_arr.get_length (); oi++) {
                                    var o_el = out_arr.get_element (oi);
                                    if (o_el.get_node_type () != Json.NodeType.OBJECT) continue;
                                    var o_obj = o_el.get_object ();
                                    if (o_obj.has_member ("text") && !o_obj.get_null_member ("text")) {
                                        string txt = extract_source_node (o_obj.get_member ("text")).strip ();
                                        if (txt.length > 0) preview_sb.append (txt).append ("\n");
                                    } else if (o_obj.has_member ("data") && !o_obj.get_null_member ("data")) {
                                        var d_node = o_obj.get_member ("data");
                                        if (d_node.get_node_type () == Json.NodeType.OBJECT) {
                                            var d_obj = d_node.get_object ();
                                            if (d_obj.has_member ("text/plain") && !d_obj.get_null_member ("text/plain")) {
                                                string txt = extract_source_node (d_obj.get_member ("text/plain")).strip ();
                                                if (txt.length > 0) preview_sb.append (txt).append ("\n");
                                            }
                                            if (d_obj.has_member ("image/png") && !d_obj.get_null_member ("image/png")) {
                                                string png_b64 = extract_source_node (d_obj.get_member ("image/png")).replace ("\n", "").strip ();
                                                if (png_b64.length > 0) preview_sb.append ("[Image PNG output preserved]\n");
                                            }
                                            if (d_obj.has_member ("text/html") && !d_obj.get_null_member ("text/html") && !d_obj.has_member ("text/plain")) {
                                                string html_txt = extract_source_node (d_obj.get_member ("text/html")).strip ();
                                                if (html_txt.length > 0) preview_sb.append (html_txt).append ("\n");
                                            }
                                        }
                                    } else if (o_obj.has_member ("ename") && !o_obj.get_null_member ("ename")) {
                                        string ename = o_obj.get_string_member ("ename") ?? "Error";
                                        string evalue = (o_obj.has_member ("evalue") && !o_obj.get_null_member ("evalue"))
                                            ? (o_obj.get_string_member ("evalue") ?? "") : "";
                                        preview_sb.append_printf ("%s: %s\n", ename, evalue);
                                    }
                                }
                                output_preview = preview_sb.str.strip ();
                            }
                        }
                    }

                    builder.append (text);
                    if (!text.has_suffix ("\n")) {
                        builder.append ("\n");
                    }
                    builder.append ("```\n\n");
                    if (output_preview.length > 0) {
                        builder.append ("::: {.ipynb-output}\n");
                        foreach (string oline in output_preview.split ("\n")) {
                            builder.append_printf ("> %s\n", oline);
                        }
                        builder.append (":::\n\n");
                    }
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
         * @param existing_ipynb_json Original notebook JSON whose cell state should be preserved.
         * @return Complete JSON string conforming to nbformat 4.5.
         * @throws GLib.Error on construction failure.
         */
        public static string markdown_to_ipynb (
            string markdown_content,
            string explicit_default_lang = "",
            string existing_ipynb_json = ""
        ) throws GLib.Error {
            string default_lang = explicit_default_lang.strip ().down ();
            bool has_explicit_language = default_lang != "" && default_lang != "python3" && default_lang != "py";
            Json.Object? existing_root = null;
            var existing_cells = new Gee.HashMap<string, Json.Object> ();
            if (existing_ipynb_json.strip () != "") {
                var existing_parser = new Json.Parser ();
                existing_parser.load_from_data (existing_ipynb_json, -1);
                var existing_node = existing_parser.get_root ();
                if (existing_node != null && existing_node.get_node_type () == Json.NodeType.OBJECT) {
                    existing_root = existing_node.get_object ();
                    if (existing_root.has_member ("cells")) {
                        var old_cells = existing_root.get_array_member ("cells");
                        for (uint i = 0; i < old_cells.get_length (); i++) {
                            var old_cell = old_cells.get_object_element (i);
                            if (old_cell.has_member ("id")) {
                                existing_cells.set (old_cell.get_string_member ("id"), old_cell);
                            }
                        }
                    }
                    if (!has_explicit_language && existing_root.has_member ("metadata")) {
                        var metadata = existing_root.get_object_member ("metadata");
                        if (metadata.has_member ("kernelspec")) {
                            var kernelspec = metadata.get_object_member ("kernelspec");
                            if (kernelspec.has_member ("language")) {
                                default_lang = kernelspec.get_string_member ("language").down ();
                            }
                        }
                    }
                }
            }
            if (!has_explicit_language && (default_lang == "" || default_lang == "python3" || default_lang == "py")) {
                default_lang = detect_notebook_language (markdown_content);
            }
            if (default_lang == "ir") default_lang = "r";
            if (default_lang == "python3" || default_lang == "py" || default_lang == "") default_lang = "python";

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
            string current_outputs_b64 = "";
            string marker_cell_id = "";
            string marker_cell_type = "";
            bool in_ipynb_output_block = false;
            var current_source = new StringBuilder ();
            bool in_yaml_frontmatter = false;
            bool has_closed_yaml = false;
            if (lines.length > 1 && lines[0].strip () == "---") {
                int scan_limit = int.min (lines.length, 250);
                for (int j = 1; j < scan_limit; j++) {
                    if (lines[j].strip () == "---") {
                        has_closed_yaml = true;
                        break;
                    }
                }
            }

            for (int i = 0; i < lines.length; i++) {
                string line = lines[i];
                string trimmed = line.strip ();

                // Filter out Quarto / Jupyter YAML Frontmatter markers
                if (i == 0 && trimmed == "---" && has_closed_yaml) {
                    in_yaml_frontmatter = true;
                    continue;
                }
                if (in_yaml_frontmatter) {
                    if (trimmed == "---") {
                        in_yaml_frontmatter = false;
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

                if (!in_code_chunk) {
                    if (trimmed.has_prefix ("<!-- imladris:cell ")) {
                        if (current_source.str.strip () != "") {
                            add_cell_to_builder (
                                builder,
                                "markdown",
                                current_source.str,
                                -1,
                                null,
                                current_cell_id,
                                null,
                                null,
                                find_existing_cell (existing_cells, current_cell_id)
                            );
                            current_source.truncate ();
                        }
                        marker_cell_type = marker_attribute (trimmed, "type");
                        marker_cell_id = marker_attribute (trimmed, "id");
                        current_cell_id = marker_cell_id;
                        continue;
                    }
                    if (trimmed == "::: {.ipynb-output}") {
                        in_ipynb_output_block = true;
                        continue;
                    }
                    if (in_ipynb_output_block) {
                        if (trimmed == ":::") {
                            in_ipynb_output_block = false;
                        }
                        continue;
                    }
                }

                if (!in_code_chunk && trimmed.has_prefix ("```")) {
                    if (current_source.len > 0) {
                        string md_text = current_source.str.strip ();
                        if (md_text.length > 0) {
                            add_cell_to_builder (
                                builder,
                                "markdown",
                                current_source.str,
                                -1,
                                null,
                                current_cell_id,
                                null,
                                null,
                                find_existing_cell (existing_cells, current_cell_id)
                            );
                        }
                        current_source.truncate ();
                    }

                    in_code_chunk = true;
                    current_exec_count = -1;
                    current_tags.clear ();
                    current_outputs_b64 = "";

                    string raw_tag = trimmed.substring (3).strip ();
                    current_chunk_lang = parse_chunk_language (raw_tag, default_lang);
                    if (marker_cell_type == "raw") {
                        current_chunk_lang = "raw";
                    }
                    marker_cell_type = "";
                    marker_cell_id = "";
                } else if (in_code_chunk && trimmed == "```") {
                    in_code_chunk = false;
                    string cell_type = (current_chunk_lang == "raw") ? "raw" : "code";
                    add_cell_to_builder (
                        builder,
                        cell_type,
                        current_source.str,
                        current_exec_count,
                        current_tags,
                        current_cell_id,
                        current_chunk_lang,
                        current_outputs_b64,
                        find_existing_cell (existing_cells, current_cell_id)
                    );
                    current_source.truncate ();
                    current_tags.clear ();
                    current_exec_count = -1;
                    current_cell_id = "";
                    current_outputs_b64 = "";
                } else if (in_code_chunk) {
                    // Inspect Quarto chunk comments for metadata
                    if (trimmed.has_prefix ("#| cell_id:") || trimmed.has_prefix ("#| id:")) {
                        int colon_idx = trimmed.index_of (":");
                        current_cell_id = trimmed.substring (colon_idx + 1).strip ();
                    } else if (trimmed.has_prefix ("#| execution_count:")) {
                        int colon_idx = trimmed.index_of (":");
                        current_exec_count = int.parse (trimmed.substring (colon_idx + 1).strip ());
                    } else if (trimmed.has_prefix ("#| outputs_b64:")) {
                        int colon_idx = trimmed.index_of (":");
                        current_outputs_b64 = trimmed.substring (colon_idx + 1).strip ();
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
                    add_cell_to_builder (
                        builder,
                        cell_type,
                        current_source.str,
                        current_exec_count,
                        current_tags,
                        current_cell_id,
                        current_chunk_lang,
                        current_outputs_b64,
                        find_existing_cell (existing_cells, current_cell_id)
                    );
                } else {
                    string rem = current_source.str.strip ();
                    if (rem.length > 0) {
                        add_cell_to_builder (
                            builder,
                            "markdown",
                            current_source.str,
                            -1,
                            null,
                            current_cell_id,
                            null,
                            null,
                            find_existing_cell (existing_cells, current_cell_id)
                        );
                    }
                }
            }

            builder.end_array (); // end cells

            // metadata
            builder.set_member_name ("metadata");
            if (existing_root != null && existing_root.has_member ("metadata")) {
                builder.add_value (existing_root.get_member ("metadata").copy ());
            } else {
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
            }

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

        private static string marker_attribute (string marker, string name) {
            string prefix = name + "=";
            int start = marker.index_of (prefix);
            if (start < 0) return "";
            start += prefix.length;
            int end = marker.index_of (" ", start);
            if (end < 0) end = marker.index_of ("-->", start);
            if (end < 0) end = marker.length;
            return marker.substring (start, end - start).strip ().replace ("\"", "");
        }

        private static Json.Object? find_existing_cell (
            Gee.HashMap<string, Json.Object> existing_cells,
            string cell_id
        ) {
            if (cell_id.strip () == "") return null;
            return existing_cells.get (cell_id);
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
            string? chunk_lang = null,
            string? outputs_b64 = null,
            Json.Object? existing_cell = null
        ) {
            builder.begin_object ();

            builder.set_member_name ("cell_type");
            builder.add_string_value (cell_type);

            builder.set_member_name ("id");
            string final_id = (cell_id != null && cell_id.strip ().length > 0)
                ? cell_id.strip ()
                : ((existing_cell != null && existing_cell.has_member ("id"))
                    ? existing_cell.get_string_member ("id")
                    : generate_cell_id ());
            builder.add_string_value (final_id);

            builder.set_member_name ("metadata");
            if (existing_cell != null && existing_cell.has_member ("metadata")) {
                builder.add_value (existing_cell.get_member ("metadata").copy ());
            } else {
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
            }

            if (cell_type == "code") {
                builder.set_member_name ("execution_count");
                if (execution_count >= 0) {
                    builder.add_int_value (execution_count);
                } else if (existing_cell != null && existing_cell.has_member ("execution_count") &&
                           !existing_cell.get_null_member ("execution_count")) {
                    builder.add_value (existing_cell.get_member ("execution_count").copy ());
                } else {
                    builder.add_null_value ();
                }

                builder.set_member_name ("outputs");
                bool restored_outputs = false;
                if (outputs_b64 != null && outputs_b64.length > 0) {
                    try {
                        uint8[] decoded = GLib.Base64.decode (outputs_b64);
                        string out_json = Core.PlatformUtils.data_to_string (decoded);
                        var p = new Json.Parser ();
                        p.load_from_data (out_json, -1);
                        var r = p.get_root ();
                        if (r != null && r.get_node_type () == Json.NodeType.ARRAY) {
                            builder.add_value (r.copy ());
                            restored_outputs = true;
                        }
                    } catch (GLib.Error e) {}
                }
                if (!restored_outputs && existing_cell != null && existing_cell.has_member ("outputs")) {
                    var existing_outputs = existing_cell.get_member ("outputs");
                    if (existing_outputs.get_node_type () == Json.NodeType.ARRAY) {
                        builder.add_value (existing_outputs.copy ());
                        restored_outputs = true;
                    }
                }
                if (!restored_outputs) {
                    builder.begin_array ();
                    builder.end_array ();
                }
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
