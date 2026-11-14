// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Adapters {

    public class DocumentAdapter : GLib.Object {

        private static GLib.Regex? chunk_regex = null;
        private static GLib.Regex? display_math_regex = null;
        private static GLib.Regex? equation_env_regex = null;

        public static Imladris.DocumentFormat detect_format (string? filename) {
            if (filename == null || filename == "") return Imladris.DocumentFormat.MD;
            return Imladris.DocumentFormat.from_filename (filename);
        }

        public static string load_to_editor_buffer (string raw_content, Imladris.DocumentFormat format) {
            if (format == Imladris.DocumentFormat.IPYNB) {
                try {
                    return Core.NotebookSerializer.ipynb_to_markdown (raw_content);
                } catch (GLib.Error e) {
                    GLib.warning ("Failed to deserialize .ipynb JSON: %s", e.message);
                    return raw_content;
                }
            }
            return raw_content;
        }

        public static string save_from_editor_buffer (string editor_text, Imladris.DocumentFormat format, string? existing_raw_file = null) {
            // Strip any Gtk.TextChildAnchor Unicode Object Replacement Characters (\uFFFC)
            string clean_text = editor_text.replace ("\uFFFC", "");
            if (format == Imladris.DocumentFormat.IPYNB) {
                try {
                    return Core.NotebookSerializer.markdown_to_ipynb (clean_text, existing_raw_file ?? "python");
                } catch (GLib.Error e) {
                    GLib.warning ("Failed to serialize editor buffer to .ipynb JSON: %s", e.message);
                    return clean_text;
                }
            }
            return clean_text;
        }

        public static string render_html (string editor_text, Imladris.DocumentFormat format) {
            Core.FrontmatterData? meta;
            string body;
            Core.FrontmatterParser.split_frontmatter (editor_text, out meta, out body);

            var builder = new StringBuilder ();
            if (meta != null && !meta.is_empty ()) {
                builder.append (meta.to_html ());
            }

            // Convert Code chunk annotations ```{r} or ```{python} to styled blocks
            string processed_body = transform_code_chunks (body);
            processed_body = transform_display_math (processed_body);
            processed_body = transform_media_tags (processed_body);
            builder.append (basic_markdown_to_html (processed_body));

            return builder.str;
        }

        private static GLib.Regex? html_protected_tag_regex = null;
        private static GLib.Regex? html_inline_math_regex = null;

        /**
         * Renders LaTeX math ($...$, $$...$$, \begin{equation}...\end{equation}) inside
         * raw HTML documents while preserving <style>, <script>, <pre>, and <code> blocks,
         * and injects MathChemEngine CSS when needed.
         */
        public static string render_html_with_latex (string raw_html) {
            if (!raw_html.contains ("$") && !raw_html.contains ("\\begin{equation}")) {
                return raw_html;
            }

            var protected_blocks = new Gee.ArrayList<string> ();
            string working = raw_html;

            try {
                if (html_protected_tag_regex == null) {
                    html_protected_tag_regex = new GLib.Regex ("<(style|script|pre|code)(\\s[^>]*)?>[\\s\\S]*?</\\1>", GLib.RegexCompileFlags.CASELESS);
                }
                working = html_protected_tag_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    int idx = protected_blocks.size;
                    protected_blocks.add (match_info.fetch (0));
                    res.append_printf ("__IMLADRIS_HTML_PROT_%d__", idx);
                    return false;
                });
            } catch (GLib.RegexError e) {}

            working = transform_display_math (working);

            try {
                if (html_inline_math_regex == null) {
                    html_inline_math_regex = new GLib.Regex ("(?<!\\\\)\\$([^\\$\\n]+?)\\$");
                }
                working = html_inline_math_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    string expr = match_info.fetch (1).strip ();
                    if (expr.length == 0) {
                        res.append (match_info.fetch (0));
                    } else {
                        res.append (Core.MathChemEngine.render_latex_to_html (expr, false));
                    }
                    return false;
                });
            } catch (GLib.RegexError e) {}

            for (int i = 0; i < protected_blocks.size; i++) {
                working = working.replace (@"__IMLADRIS_HTML_PROT_$(i)__", protected_blocks[i]);
            }

            if (!working.contains (".math-display-card")) {
                string math_css = "<style id=\"imladris-math-css\">\n" + Core.MathChemEngine.get_math_chem_css () + "\n</style>\n";
                int head_close = working.down ().index_of ("</head>");
                if (head_close >= 0) {
                    working = working.substring (0, head_close) + math_css + working.substring (head_close);
                } else {
                    working = math_css + working;
                }
            }

            return working;
        }

        private static string transform_display_math (string text) {
            string result = text;
            try {
                if (display_math_regex == null) {
                    display_math_regex = new GLib.Regex ("\\$\\$([\\s\\S]*?)\\$\\$");
                }
                result = display_math_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string expr = match_info.fetch (1).strip ();
                    res.append (Core.MathChemEngine.render_latex_to_html (expr, true));
                    res.append ("\n");
                    return false;
                });

                if (equation_env_regex == null) {
                    equation_env_regex = new GLib.Regex ("\\\\begin\\{equation\\}([\\s\\S]*?)\\\\end\\{equation\\}");
                }
                result = equation_env_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string expr = match_info.fetch (1).strip ();
                    res.append (Core.MathChemEngine.render_latex_to_html (expr, true));
                    res.append ("\n");
                    return false;
                });
            } catch (GLib.RegexError e) {}
            return result;
        }

        private static GLib.Regex? img_regex = null;
        private static GLib.Regex? video_regex = null;

        private static string transform_media_tags (string text) {
            string result = text;
            try {
                // Quarto video shortcodes: {{< video path >}}
                if (video_regex == null) {
                    video_regex = new GLib.Regex ("\\{\\{<\\s*video\\s+([^\\s>]+)[^>]*>\\}\\}");
                }
                result = video_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string vpath = match_info.fetch (1);
                    res.append_printf ("<div class=\"media-video-container\" style=\"margin: 16px 0; text-align: center;\"><video src=\"%s\" controls style=\"max-width: 100%%; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);\"></video></div>", GLib.Markup.escape_text (vpath));
                    return false;
                });

                // Markdown images: ![caption](path)
                if (img_regex == null) {
                    img_regex = new GLib.Regex ("!\\[([^\\]]*)\\]\\(([^\\)]+)\\)");
                }
                result = img_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string alt = match_info.fetch (1);
                    string ipath = match_info.fetch (2);
                    res.append_printf ("<figure style=\"margin: 16px 0; text-align: center;\"><img src=\"%s\" alt=\"%s\" style=\"max-width: 100%%; height: auto; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);\"/>", GLib.Markup.escape_text (ipath), GLib.Markup.escape_text (alt));
                    if (alt.strip ().length > 0) {
                        res.append_printf ("<figcaption style=\"font-size: 0.9em; color: #64748b; margin-top: 6px;\">%s</figcaption>", GLib.Markup.escape_text (alt));
                    }
                    res.append ("</figure>");
                    return false;
                });
            } catch (GLib.RegexError e) {}
            return result;
        }

        private static GLib.Regex? plain_mermaid_regex = null;

        private static string render_mermaid_svg_inline (string code) {
            Core.MermaidDiagramKind kind;
            Core.MermaidFlowDirection dir;
            Gee.ArrayList<Core.MermaidNode> nodes;
            Gee.ArrayList<Core.MermaidEdge> edges;
            Core.MermaidFlowEngine.parse_mermaid_code (code, out kind, out dir, out nodes, out edges);
            if (nodes.size == 0) {
                return "<pre><code class=\"language-mermaid\">" + GLib.Markup.escape_text (code) + "</code></pre>";
            }
            Core.MermaidFlowEngine.auto_layout (kind, dir, nodes, edges);
            string svg = Core.MermaidFlowEngine.export_to_svg (nodes, edges);
            int svg_start = svg.index_of ("<svg");
            if (svg_start > 0) {
                svg = svg.substring (svg_start);
            }
            return "<div class=\"mermaid-diagram-card\" style=\"margin: 1em 0; overflow-x: auto;\">" + svg + "</div>\n";
        }

        private static string transform_code_chunks (string text) {
            string step1 = text;
            try {
                if (chunk_regex == null) {
                    chunk_regex = new GLib.Regex ("```\\{([a-zA-Z0-9_-]+)([^\\}]*)\\}([\\s\\S]*?)```");
                }
                step1 = chunk_regex.replace_eval (step1, -1, 0, 0, (match_info, result) => {
                    string lang = match_info.fetch (1);
                    string opts = match_info.fetch (2).strip ();
                    string code = match_info.fetch (3);

                    if (lang.down () == "mermaid") {
                        result.append (render_mermaid_svg_inline (code));
                        return false;
                    }

                    result.append ("<div class=\"code-chunk-card\">\n");
                    result.append_printf ("  <div class=\"code-chunk-header\"><span class=\"badge\">%s</span>", GLib.Markup.escape_text (lang.up ()));
                    if (opts != "") {
                        result.append_printf (" <span class=\"chunk-opts\">%s</span>", GLib.Markup.escape_text (opts));
                    }
                    result.append ("</div>\n");
                    result.append_printf ("  <pre><code class=\"language-%s\">%s</code></pre>\n", lang, GLib.Markup.escape_text (code));
                    result.append ("</div>\n");
                    return false;
                });
                if (plain_mermaid_regex == null) {
                    plain_mermaid_regex = new GLib.Regex ("```mermaid\\s*\\n([\\s\\S]*?)```");
                }
                step1 = plain_mermaid_regex.replace_eval (step1, -1, 0, 0, (match_info, result) => {
                    string code = match_info.fetch (1);
                    result.append (render_mermaid_svg_inline (code));
                    return false;
                });
            } catch (GLib.RegexError e) {
                return text;
            }
            return step1;
        }

        private static GLib.Regex? inline_code_regex = null;
        private static GLib.Regex? inline_bold_regex = null;
        private static GLib.Regex? inline_italic_regex = null;
        private static GLib.Regex? inline_strike_regex = null;
        private static GLib.Regex? inline_sub_regex = null;
        private static GLib.Regex? inline_sup_regex = null;
        private static GLib.Regex? inline_link_regex = null;
        private static GLib.Regex? inline_math_regex = null;
        private static GLib.Regex? inline_ce_regex = null;
        private static GLib.Regex? ordered_list_regex = null;

        private static string format_inline_markdown (string line) {
            string escaped = GLib.Markup.escape_text (line);
            try {
                if (inline_code_regex == null) inline_code_regex = new GLib.Regex ("`([^`]+)`");
                if (inline_bold_regex == null) inline_bold_regex = new GLib.Regex ("\\*\\*([^\\*]+)\\*\\*");
                if (inline_italic_regex == null) inline_italic_regex = new GLib.Regex ("(?<!\\*)\\*([^\\*]+)\\*(?!\\*)");
                if (inline_strike_regex == null) inline_strike_regex = new GLib.Regex ("~~([^~]+)~~");
                if (inline_sub_regex == null) inline_sub_regex = new GLib.Regex ("(?<!~)~([^~\\s]+)~(?!~)");
                if (inline_sup_regex == null) inline_sup_regex = new GLib.Regex ("\\^([^\\^\\s]+)\\^");
                if (inline_link_regex == null) inline_link_regex = new GLib.Regex ("\\[([^\\]]+)\\]\\(([^\\)]+)\\)");
                if (inline_ce_regex == null) inline_ce_regex = new GLib.Regex ("\\\\ce\\{([^\\}]+)\\}");
                if (inline_math_regex == null) inline_math_regex = new GLib.Regex ("(?<!\\$)\\$([^\\$\\n]+)\\$(?!\\$)");

                // Render inline \ce{...} and $...$ math/chemistry expressions first
                escaped = inline_ce_regex.replace_eval (escaped, -1, 0, 0, (match_info, res) => {
                    string expr = "\\ce{" + match_info.fetch (1) + "}";
                    res.append (Core.MathChemEngine.render_latex_to_html (expr, false));
                    return false;
                });
                escaped = inline_math_regex.replace_eval (escaped, -1, 0, 0, (match_info, res) => {
                    string expr = match_info.fetch (1);
                    res.append (Core.MathChemEngine.render_latex_to_html (expr, false));
                    return false;
                });

                escaped = inline_code_regex.replace (escaped, -1, 0, "<code>\\1</code>");
                escaped = inline_bold_regex.replace (escaped, -1, 0, "<strong>\\1</strong>");
                escaped = inline_italic_regex.replace (escaped, -1, 0, "<em>\\1</em>");
                escaped = inline_strike_regex.replace (escaped, -1, 0, "<del>\\1</del>");
                escaped = inline_sub_regex.replace (escaped, -1, 0, "<sub>\\1</sub>");
                escaped = inline_sup_regex.replace (escaped, -1, 0, "<sup>\\1</sup>");
                escaped = inline_link_regex.replace (escaped, -1, 0, "<a href=\"\\2\">\\1</a>");
            } catch (GLib.RegexError e) {}
            return escaped;
        }

        private static string basic_markdown_to_html (string text) {
            var lines = text.split ("\n");
            var res = new StringBuilder ();
            bool in_pre = false;
            bool in_html_pre = false;
            bool in_callout = false;
            bool in_ul = false;
            bool in_ol = false;
            bool in_table = false;

            foreach (var line in lines) {
                string trimmed_line = line.strip ();
                if (in_html_pre) {
                    res.append (line);
                    res.append ("\n");
                    if (line.contains ("</pre>")) {
                        in_html_pre = false;
                    }
                    continue;
                }

                if (trimmed_line.has_prefix ("<div") || trimmed_line.has_prefix ("</div") ||
                    trimmed_line.has_prefix ("<pre") || trimmed_line.has_prefix ("</pre") ||
                    trimmed_line.has_prefix ("<header") || trimmed_line.has_prefix ("</header") ||
                    trimmed_line.has_prefix ("<figure") || trimmed_line.has_prefix ("</figure") ||
                    trimmed_line.has_prefix ("<video") || trimmed_line.has_prefix ("</video") ||
                    trimmed_line.has_prefix ("<figcaption") || trimmed_line.has_prefix ("</figcaption") ||
                    trimmed_line.has_prefix ("<img")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    if (in_table) { res.append ("</tbody></table>\n"); in_table = false; }
                    res.append (line);
                    res.append ("\n");
                    if (line.contains ("<pre") && !line.contains ("</pre>")) {
                        in_html_pre = true;
                    }
                    continue;
                }

                // Quarto fenced callout blocks: ::: {.callout-note} ... :::
                if (trimmed_line.has_prefix (":::")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    if (in_table) { res.append ("</tbody></table>\n"); in_table = false; }
                    if (!in_callout && trimmed_line.length > 3) {
                        string lower = trimmed_line.down ();
                        string accent = "#3584e4";
                        string label = "Note";
                        if (lower.contains ("callout-warning")) { accent = "#e5a50a"; label = "Warning"; }
                        else if (lower.contains ("callout-tip")) { accent = "#26a269"; label = "Tip"; }
                        else if (lower.contains ("callout-important")) { accent = "#c01c28"; label = "Important"; }
                        else if (lower.contains ("callout-caution")) { accent = "#e66100"; label = "Caution"; }
                        else if (lower.contains ("panel-tabset")) { accent = "#6366f1"; label = "Tabset"; }
                        res.append_printf ("<div style=\"border-left: 4px solid %s; background: rgba(148,163,184,0.08); border-radius: 6px; padding: 10px 14px; margin: 12px 0;\">\n<div style=\"font-weight: 700; font-size: 12px; text-transform: uppercase; color: %s; margin-bottom: 4px;\">%s</div>\n", accent, accent, label);
                        in_callout = true;
                    } else if (in_callout) {
                        res.append ("</div>\n");
                        in_callout = false;
                    }
                    continue;
                }

                if (line.has_prefix ("```")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    if (in_table) { res.append ("</tbody></table>\n"); in_table = false; }
                    if (!in_pre) {
                        string lang = line.substring (3).strip ();
                        res.append_printf ("<pre><code class=\"language-%s\">", lang != "" ? lang : "text");
                        in_pre = true;
                    } else {
                        res.append ("</code></pre>\n");
                        in_pre = false;
                    }
                    continue;
                }

                if (in_pre) {
                    res.append (GLib.Markup.escape_text (line));
                    res.append ("\n");
                    continue;
                }

                // Markdown table rows: | col1 | col2 |
                if (trimmed_line.has_prefix ("|") && trimmed_line.has_suffix ("|") && trimmed_line.length > 2) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }

                    string inner_row = trimmed_line.substring (1, trimmed_line.length - 2);
                    string[] cells = inner_row.split ("|");

                    // Check if separator row (e.g. |---|---|)
                    bool is_sep = true;
                    foreach (var cell in cells) {
                        string c = cell.strip ().replace ("-", "").replace (":", "");
                        if (c.length > 0) {
                            is_sep = false;
                            break;
                        }
                    }
                    if (is_sep) {
                        continue;
                    }

                    if (!in_table) {
                        res.append ("<table style=\"border-collapse: collapse; width: 100%; margin: 12px 0;\">\n<thead><tr>");
                        foreach (var cell in cells) {
                            res.append_printf ("<th style=\"border: 1px solid #cbd5e1; padding: 6px 10px; text-align: left;\">%s</th>",
                                format_inline_markdown (cell.strip ()));
                        }
                        res.append ("</tr></thead>\n<tbody>\n");
                        in_table = true;
                    } else {
                        res.append ("<tr>");
                        foreach (var cell in cells) {
                            res.append_printf ("<td style=\"border: 1px solid #cbd5e1; padding: 6px 10px;\">%s</td>",
                                format_inline_markdown (cell.strip ()));
                        }
                        res.append ("</tr>\n");
                    }
                    continue;
                } else if (in_table) {
                    res.append ("</tbody></table>\n");
                    in_table = false;
                }

                if (line.has_prefix ("#### ")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    res.append_printf ("<h4>%s</h4>\n", format_inline_markdown (line.substring (5)));
                } else if (line.has_prefix ("### ")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    res.append_printf ("<h3>%s</h3>\n", format_inline_markdown (line.substring (4)));
                } else if (line.has_prefix ("## ")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    res.append_printf ("<h2>%s</h2>\n", format_inline_markdown (line.substring (3)));
                } else if (line.has_prefix ("# ")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    res.append_printf ("<h1>%s</h1>\n", format_inline_markdown (line.substring (2)));
                } else if (trimmed_line == "---" || trimmed_line == "***") {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    res.append ("<hr/>\n");
                } else if (line.has_prefix ("> ")) {
                    if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    res.append_printf ("<blockquote style=\"border-left: 4px solid #6366f1; margin: 10px 0; padding: 4px 14px; color: #64748b;\">%s</blockquote>\n",
                        format_inline_markdown (line.substring (2)));
                } else if (line.has_prefix ("- ") || line.has_prefix ("* ")) {
                    if (in_ol) { res.append ("</ol>\n"); in_ol = false; }
                    if (!in_ul) {
                        res.append ("<ul>\n");
                        in_ul = true;
                    }
                    res.append_printf ("  <li>%s</li>\n", format_inline_markdown (line.substring (2)));
                } else {
                    string ordered_item_text = "";
                    if (is_ordered_list_item (trimmed_line, out ordered_item_text)) {
                        if (in_ul) { res.append ("</ul>\n"); in_ul = false; }
                        if (!in_ol) {
                            res.append ("<ol>\n");
                            in_ol = true;
                        }
                        res.append_printf ("  <li>%s</li>\n", format_inline_markdown (ordered_item_text));
                    } else {
                        if (in_ul) {
                            res.append ("</ul>\n");
                            in_ul = false;
                        }
                        if (in_ol) {
                            res.append ("</ol>\n");
                            in_ol = false;
                        }
                        if (trimmed_line == "") {
                            res.append ("\n");
                        } else {
                            res.append_printf ("<p>%s</p>\n", format_inline_markdown (line));
                        }
                    }
                }
            }

            if (in_ul) res.append ("</ul>\n");
            if (in_ol) res.append ("</ol>\n");
            if (in_table) res.append ("</tbody></table>\n");
            if (in_pre) res.append ("</code></pre>\n");
            if (in_callout) res.append ("</div>\n");

            return res.str;
        }

        private static bool is_ordered_list_item (string trimmed_line, out string item_content) {
            item_content = "";
            try {
                if (ordered_list_regex == null) {
                    ordered_list_regex = new GLib.Regex ("^[0-9]+\\.\\s+(.+)$");
                }
                GLib.MatchInfo mi;
                if (ordered_list_regex.match (trimmed_line, 0, out mi)) {
                    item_content = mi.fetch (1);
                    return true;
                }
            } catch (GLib.RegexError e) {}
            return false;
        }
    }
}
