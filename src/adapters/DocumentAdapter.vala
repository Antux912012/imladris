// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Adapters {

    public class DocumentAdapter : GLib.Object {

        private static GLib.Regex? display_math_regex = null;
        private static GLib.Regex? equation_env_regex = null;
        private static GLib.Regex? latex_title_regex = null;
        private static GLib.Regex? latex_author_regex = null;
        private static GLib.Regex? latex_date_regex = null;
        private static GLib.Regex? latex_verb_regex = null;
        private static GLib.Regex? latex_bracket_math_regex = null;
        private static GLib.Regex? latex_env_math_regex = null;
        private static GLib.Regex? latex_dd_math_regex = null;
        private static GLib.Regex? latex_paren_math_regex = null;
        private static GLib.Regex? latex_ce_regex = null;
        private static GLib.Regex? latex_inline_dollar_regex = null;
        private static GLib.Regex? latex_maketitle_regex = null;
        private static GLib.Regex? latex_sec_regex = null;
        private static GLib.Regex? latex_subsec_regex = null;
        private static GLib.Regex? latex_subsubsec_regex = null;
        private static GLib.Regex? latex_textbf_regex = null;
        private static GLib.Regex? latex_emph_regex = null;
        private static GLib.Regex? latex_texttt_regex = null;
        private static GLib.Regex? latex_cite_regex = null;

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
                    return Core.NotebookSerializer.markdown_to_ipynb (clean_text, existing_raw_file ?? "");
                } catch (GLib.Error e) {
                    GLib.warning ("Failed to serialize editor buffer to .ipynb JSON: %s", e.message);
                    return clean_text;
                }
            }
            return clean_text;
        }

        public static string render_html (string editor_text, Imladris.DocumentFormat format) {
            string clean_text = editor_text.replace ("\uFFFC", "");
            if (format == Imladris.DocumentFormat.HTML) {
                return render_html_with_latex (clean_text);
            }
            if (format == Imladris.DocumentFormat.TEX) {
                return render_latex_document_html (clean_text);
            }
            if (format == Imladris.DocumentFormat.TS) {
                return render_typescript_document_html (clean_text);
            }

            Core.FrontmatterData? meta;
            string body;
            Core.FrontmatterParser.split_frontmatter (clean_text, out meta, out body);

            var builder = new StringBuilder ();
            if (meta != null && !meta.is_empty ()) {
                builder.append (meta.to_html ());
            }

            string rust_json = Core.NativeCore.render_markdown_html (body, "{}");
            string rust_html = "";
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (rust_json, -1);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("html")) {
                        rust_html = obj.get_string_member ("html");
                    }
                }
            } catch (GLib.Error e) {
                GLib.warning ("Failed to decode Rust markdown HTML JSON: %s", e.message);
            }
            string hydrated = hydrate_rust_placeholders (rust_html);
            builder.append (hydrated);

            return builder.str;
        }

        private static string unescape_html_attr (string attr) {
            return attr
                .replace ("&quot;", "\"")
                .replace ("&#39;", "'")
                .replace ("&lt;", "<")
                .replace ("&gt;", ">")
                .replace ("&amp;", "&");
        }

        private static GLib.Regex? rust_math_display_regex = null;
        private static GLib.Regex? rust_math_inline_regex = null;
        private static GLib.Regex? rust_mermaid_regex = null;

        private static string hydrate_rust_placeholders (string html) {
            string working = html;
            try {
                if (rust_math_display_regex == null) {
                    rust_math_display_regex = new GLib.Regex ("<div class=\"imladris-math-display\" data-tex=\"([^\"]*)\"></div>");
                }
                working = rust_math_display_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    string tex = unescape_html_attr (match_info.fetch (1));
                    res.append (Core.MathChemEngine.render_latex_to_html (tex, true));
                    return false;
                });

                if (rust_math_inline_regex == null) {
                    rust_math_inline_regex = new GLib.Regex ("<span class=\"imladris-math-inline\" data-tex=\"([^\"]*)\"></span>");
                }
                working = rust_math_inline_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    string tex = unescape_html_attr (match_info.fetch (1));
                    res.append (Core.MathChemEngine.render_latex_to_html (tex, false));
                    return false;
                });

                if (rust_mermaid_regex == null) {
                    rust_mermaid_regex = new GLib.Regex ("<div class=\"imladris-mermaid-block\" data-mermaid=\"([^\"]*)\"></div>");
                }
                working = rust_mermaid_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    string code = unescape_html_attr (match_info.fetch (1));
                    res.append (render_mermaid_svg_inline (code));
                    return false;
                });
            } catch (GLib.RegexError e) {
                GLib.warning ("Failed to hydrate placeholders: %s", e.message);
            }
            return working;
        }

        private static string render_latex_document_html (string source) {
            var builder = new StringBuilder ();
            string body = source;
            int doc_start = source.index_of ("\\begin{document}");
            if (doc_start >= 0) {
                string preamble = source.substring (0, doc_start);
                body = source.substring (doc_start + "\\begin{document}".length);
                int doc_end = body.last_index_of ("\\end{document}");
                if (doc_end >= 0) {
                    body = body.substring (0, doc_end);
                }

                string title = "";
                string author = "";
                string date = "";
                try {
                    if (latex_title_regex == null) latex_title_regex = new GLib.Regex ("\\\\title\\{([^\\}]*)\\}");
                    if (latex_author_regex == null) latex_author_regex = new GLib.Regex ("\\\\author\\{([^\\}]*)\\}");
                    if (latex_date_regex == null) latex_date_regex = new GLib.Regex ("\\\\date\\{([^\\}]*)\\}");
                    GLib.MatchInfo mi;
                    if (latex_title_regex.match (preamble, 0, out mi) || latex_title_regex.match (body, 0, out mi)) {
                        title = mi.fetch (1).strip ();
                    }
                    if (latex_author_regex.match (preamble, 0, out mi) || latex_author_regex.match (body, 0, out mi)) {
                        author = mi.fetch (1).strip ();
                    }
                    if (latex_date_regex.match (preamble, 0, out mi) || latex_date_regex.match (body, 0, out mi)) {
                        date = mi.fetch (1).strip ();
                    }
                } catch (GLib.RegexError e) {}

                if (title != "" || author != "" || date != "") {
                    builder.append ("<div class=\"document-frontmatter-card\">");
                    if (title != "") {
                        builder.append_printf ("<h1 class=\"frontmatter-title\">%s</h1>", GLib.Markup.escape_text (title));
                    }
                    builder.append ("<div class=\"frontmatter-meta-grid\">");
                    if (author != "") {
                        builder.append_printf ("<div><span class=\"frontmatter-label\">Author</span>%s</div>", GLib.Markup.escape_text (author));
                    }
                    if (date != "") {
                        builder.append_printf ("<div><span class=\"frontmatter-label\">Date</span>%s</div>", GLib.Markup.escape_text (date));
                    }
                    builder.append ("</div></div>\n");
                }
            }

            var prot = new Gee.ArrayList<string> ();
            string working = body;
            try {
                if (latex_verb_regex == null) latex_verb_regex = new GLib.Regex ("\\\\begin\\{(verbatim|lstlisting)\\}([\\s\\S]*?)\\\\end\\{\\1\\}");
                working = latex_verb_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add ("<pre><code>" + GLib.Markup.escape_text (mi.fetch (2)) + "</code></pre>");
                    res.append_printf ("__IMLADRIS_TEX_PROT_%d__", idx);
                    return false;
                });

                if (latex_bracket_math_regex == null) latex_bracket_math_regex = new GLib.Regex ("\\\\\\[([\\s\\S]*?)\\\\\\]");
                working = latex_bracket_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), true));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%d__", idx);
                    return false;
                });
                if (latex_env_math_regex == null) latex_env_math_regex = new GLib.Regex ("\\\\begin\\{(equation|equation\\*|align|align\\*|gather|gather\\*)\\}([\\s\\S]*?)\\\\end\\{\\1\\}");
                working = latex_env_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (2).strip (), true));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%d__", idx);
                    return false;
                });
                if (latex_dd_math_regex == null) latex_dd_math_regex = new GLib.Regex ("\\$\\$([\\s\\S]*?)\\$\\$");
                working = latex_dd_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), true));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%d__", idx);
                    return false;
                });

                if (latex_paren_math_regex == null) latex_paren_math_regex = new GLib.Regex ("\\\\\\(([\\s\\S]*?)\\\\\\)");
                working = latex_paren_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), false));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%d__", idx);
                    return false;
                });
                if (latex_ce_regex == null) latex_ce_regex = new GLib.Regex ("\\\\ce\\{([^\\}]+)\\}");
                working = latex_ce_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html ("\\ce{" + mi.fetch (1) + "}", false));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%d__", idx);
                    return false;
                });
                if (latex_inline_dollar_regex == null) latex_inline_dollar_regex = new GLib.Regex ("(?<!\\\\)\\$(?!\\s)([^\\$\\n]+?)(?<!\\s)\\$(?!\\d)");
                working = latex_inline_dollar_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), false));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%d__", idx);
                    return false;
                });
            } catch (GLib.RegexError e) {}

            working = GLib.Markup.escape_text (working);
            try {
                if (latex_maketitle_regex == null) latex_maketitle_regex = new GLib.Regex ("\\\\maketitle");
                if (latex_sec_regex == null) latex_sec_regex = new GLib.Regex ("\\\\section\\*?\\{([^\\}]*)\\}");
                if (latex_subsec_regex == null) latex_subsec_regex = new GLib.Regex ("\\\\subsection\\*?\\{([^\\}]*)\\}");
                if (latex_subsubsec_regex == null) latex_subsubsec_regex = new GLib.Regex ("\\\\subsubsection\\*?\\{([^\\}]*)\\}");
                if (latex_textbf_regex == null) latex_textbf_regex = new GLib.Regex ("\\\\textbf\\{([^\\}]*)\\}");
                if (latex_emph_regex == null) latex_emph_regex = new GLib.Regex ("\\\\(?:textit|emph)\\{([^\\}]*)\\}");
                if (latex_texttt_regex == null) latex_texttt_regex = new GLib.Regex ("\\\\texttt\\{([^\\}]*)\\}");
                if (latex_cite_regex == null) latex_cite_regex = new GLib.Regex ("\\\\cite\\{([^\\}]*)\\}");
                working = latex_maketitle_regex.replace (working, -1, 0, "");
                working = latex_sec_regex.replace (working, -1, 0, "<h2>\\1</h2>");
                working = latex_subsec_regex.replace (working, -1, 0, "<h3>\\1</h3>");
                working = latex_subsubsec_regex.replace (working, -1, 0, "<h4>\\1</h4>");
                working = latex_textbf_regex.replace (working, -1, 0, "<strong>\\1</strong>");
                working = latex_emph_regex.replace (working, -1, 0, "<em>\\1</em>");
                working = latex_texttt_regex.replace (working, -1, 0, "<code>\\1</code>");
                working = latex_cite_regex.replace (working, -1, 0, "<span class=\"frontmatter-badge\">[\\1]</span>");
            } catch (GLib.RegexError e) {}

            var lines = working.split ("\n");
            var body_out = new StringBuilder ();
            foreach (var ln in lines) {
                string t = ln.strip ();
                if (t == "") {
                    body_out.append ("<br/>\n");
                } else if (t.has_prefix ("<h") || t.has_prefix ("__IMLADRIS_TEX_PROT_")) {
                    body_out.append (t);
                    body_out.append ("\n");
                } else {
                    body_out.append ("<p>");
                    body_out.append (t);
                    body_out.append ("</p>\n");
                }
            }

            string final_body = body_out.str;
            for (int i = 0; i < prot.size; i++) {
                final_body = final_body.replace (@"__IMLADRIS_TEX_PROT_$(i)__", prot[i]);
            }
            builder.append (final_body);
            return builder.str;
        }

        private static string render_typescript_document_html (string source) {
            var builder = new StringBuilder ();
            string symbols_json = Core.NativeCore.analyze_typescript_symbols_json (source);
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (symbols_json, -1);
                var arr = parser.get_root ().get_array ();
                if (arr != null && arr.get_length () > 0) {
                    builder.append ("<div class=\"document-frontmatter-card\">");
                    builder.append ("<h2 class=\"frontmatter-title\">TypeScript Module Symbols</h2>");
                    builder.append ("<div class=\"frontmatter-meta-grid\">");
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var obj = arr.get_object_element (i);
                        string kind = obj.has_member ("kind") ? obj.get_string_member ("kind") : "symbol";
                        string name = obj.has_member ("name") ? obj.get_string_member ("name") : "";
                        int64 line = obj.has_member ("line") ? obj.get_int_member ("line") : 1;
                        builder.append_printf (
                            "<div><span class=\"frontmatter-badge\">%s</span> <code>%s</code> <span style=\"opacity:0.7;\">:%lld</span></div>",
                            GLib.Markup.escape_text (kind),
                            GLib.Markup.escape_text (name),
                            line
                        );
                    }
                    builder.append ("</div></div>\n");
                }
            } catch (GLib.Error e) {}

            builder.append ("<div class=\"code-chunk-card\">\n");
            builder.append ("  <div class=\"code-chunk-header\"><span class=\"badge\">TYPESCRIPT</span></div>\n");
            builder.append_printf ("  <pre><code class=\"language-typescript\">%s</code></pre>\n", GLib.Markup.escape_text (source));
            builder.append ("</div>\n");
            return builder.str;
        }

        private static GLib.Regex? html_protected_tag_regex = null;
        private static GLib.Regex? html_inline_math_regex = null;
        private static GLib.Regex? html_ce_regex = null;

        /**
         * Renders LaTeX math ($...$, $$...$$, \begin{equation}...\end{equation}, \ce{...}) inside
         * raw HTML documents while preserving <style>, <script>, <pre>, and <code> blocks,
         * and injects MathChemEngine CSS when needed.
         */
        public static string render_html_with_latex (string raw_html) {
            if (!raw_html.contains ("$") && !raw_html.contains ("\\begin{equation}") && !raw_html.contains ("\\ce{")) {
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
                if (html_ce_regex == null) {
                    html_ce_regex = new GLib.Regex ("\\\\ce\\{([^\\}]+)\\}");
                }
                working = html_ce_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    res.append (Core.MathChemEngine.render_latex_to_html ("\\ce{" + match_info.fetch (1) + "}", false));
                    return false;
                });

                if (html_inline_math_regex == null) {
                    // Pandoc currency guard: no space after opening $, no space before closing $, no digit after closing $
                    html_inline_math_regex = new GLib.Regex ("(?<!\\\\)\\$(?!\\s)([^\\$\\n]+?)(?<!\\s)\\$(?!\\d)");
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
            string svg = Core.MermaidFlowEngine.export_to_svg (nodes, edges, kind);
            int svg_start = svg.index_of ("<svg");
            if (svg_start > 0) {
                svg = svg.substring (svg_start);
            }
            return "<div class=\"mermaid-diagram-card\" style=\"margin: 1em 0; overflow-x: auto;\">" + svg + "</div>\n";
        }
    }
}
