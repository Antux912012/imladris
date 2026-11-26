// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris.Adapters {

    public class DocumentAdapter : GLib.Object {

        private static GLib.Regex? chunk_regex = null;
        private static GLib.Regex? plain_mermaid_regex = null;
        private static GLib.Regex? video_regex = null;
        private static GLib.Regex? img_regex = null;
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
        private static GLib.Regex? html_head_close_regex = null;
        private static GLib.Mutex regex_mutex;

        private static string make_nonce () {
            return GLib.Uuid.string_random ().replace ("-", "");
        }

        private static void ensure_regexes () throws GLib.RegexError {
            regex_mutex.lock ();
            try {
                if (chunk_regex == null) chunk_regex = new GLib.Regex ("```\\{([A-Za-z0-9_+-]+)([^\\}]*)\\}([\\s\\S]*?)```");
                if (plain_mermaid_regex == null) plain_mermaid_regex = new GLib.Regex ("```mermaid\\s*\\n([\\s\\S]*?)```");
                if (video_regex == null) video_regex = new GLib.Regex ("\\{\\{<\\s*video\\s+([^\\s>]+)[^>]*>\\}\\}");
                if (img_regex == null) img_regex = new GLib.Regex ("!\\[([^\\]]*)\\]\\(([^\\)]+)\\)");
                if (display_math_regex == null) display_math_regex = new GLib.Regex ("\\$\\$([\\s\\S]*?)\\$\\$");
                if (equation_env_regex == null) equation_env_regex = new GLib.Regex ("\\\\begin\\{equation\\}([\\s\\S]*?)\\\\end\\{equation\\}");
                if (latex_title_regex == null) latex_title_regex = new GLib.Regex ("\\\\title\\{([^\\}]*)\\}");
                if (latex_author_regex == null) latex_author_regex = new GLib.Regex ("\\\\author\\{([^\\}]*)\\}");
                if (latex_date_regex == null) latex_date_regex = new GLib.Regex ("\\\\date\\{([^\\}]*)\\}");
                if (latex_verb_regex == null) latex_verb_regex = new GLib.Regex ("\\\\begin\\{(verbatim|lstlisting)\\}([\\s\\S]*?)\\\\end\\{\\1\\}");
                if (latex_bracket_math_regex == null) latex_bracket_math_regex = new GLib.Regex ("\\\\\\[([\\s\\S]*?)\\\\\\]");
                if (latex_env_math_regex == null) latex_env_math_regex = new GLib.Regex ("\\\\begin\\{(equation|equation\\*|align|align\\*|gather|gather\\*)\\}([\\s\\S]*?)\\\\end\\{\\1\\}");
                if (latex_dd_math_regex == null) latex_dd_math_regex = new GLib.Regex ("\\$\\$([\\s\\S]*?)\\$\\$");
                if (latex_paren_math_regex == null) latex_paren_math_regex = new GLib.Regex ("\\\\\\(([\\s\\S]*?)\\\\\\)");
                if (latex_ce_regex == null) latex_ce_regex = new GLib.Regex ("\\\\ce\\{([^\\}]+)\\}");
                if (latex_inline_dollar_regex == null) latex_inline_dollar_regex = new GLib.Regex ("(?<!\\\\)\\$(?!\\s)([^\\$\\n]+?)(?<!\\s)\\$(?!\\d)");
                if (latex_maketitle_regex == null) latex_maketitle_regex = new GLib.Regex ("\\\\maketitle");
                if (latex_sec_regex == null) latex_sec_regex = new GLib.Regex ("\\\\section\\*?\\{([^\\}]*)\\}");
                if (latex_subsec_regex == null) latex_subsec_regex = new GLib.Regex ("\\\\subsection\\*?\\{([^\\}]*)\\}");
                if (latex_subsubsec_regex == null) latex_subsubsec_regex = new GLib.Regex ("\\\\subsubsection\\*?\\{([^\\}]*)\\}");
                if (latex_textbf_regex == null) latex_textbf_regex = new GLib.Regex ("\\\\textbf\\{([^\\}]*)\\}");
                if (latex_emph_regex == null) latex_emph_regex = new GLib.Regex ("\\\\(?:textit|emph)\\{([^\\}]*)\\}");
                if (latex_texttt_regex == null) latex_texttt_regex = new GLib.Regex ("\\\\texttt\\{([^\\}]*)\\}");
                if (latex_cite_regex == null) latex_cite_regex = new GLib.Regex ("\\\\cite\\{([^\\}]*)\\}");
                if (inline_code_regex == null) inline_code_regex = new GLib.Regex ("`([^`]+)`");
                if (inline_bold_regex == null) inline_bold_regex = new GLib.Regex ("\\*\\*([^\\*]+)\\*\\*");
                if (inline_italic_regex == null) inline_italic_regex = new GLib.Regex ("(?<!\\*)\\*([^\\*]+)\\*(?!\\*)");
                if (inline_strike_regex == null) inline_strike_regex = new GLib.Regex ("~~([^~]+)~~");
                if (inline_sub_regex == null) inline_sub_regex = new GLib.Regex ("(?<!~)~([^~\\s]+)~(?!~)");
                if (inline_sup_regex == null) inline_sup_regex = new GLib.Regex ("\\^([^\\^\\s]+)\\^");
                if (inline_link_regex == null) inline_link_regex = new GLib.Regex ("\\[([^\\]]+)\\]\\(([^\\)]+)\\)");
                if (inline_ce_regex == null) inline_ce_regex = new GLib.Regex ("\\\\ce\\{([^\\}]+)\\}");
                if (inline_math_regex == null) inline_math_regex = new GLib.Regex ("(?<!\\$)(?<!\\\\)\\$(?!\\s)([^\\$\\n]+?)(?<!\\s)\\$(?!\\d)(?!\\$)");
                if (ordered_list_regex == null) ordered_list_regex = new GLib.Regex ("^[0-9]+\\.\\s+(.+)$");
                if (html_protected_tag_regex == null) html_protected_tag_regex = new GLib.Regex ("<(style|script|pre|code)(\\s[^>]*)?>[\\s\\S]*?</\\1>", GLib.RegexCompileFlags.CASELESS);
                if (html_ce_regex == null) html_ce_regex = new GLib.Regex ("\\\\ce\\{([^\\}]+)\\}");
                if (html_inline_math_regex == null) html_inline_math_regex = new GLib.Regex ("(?<!\\\\)\\$(?!\\s)([^\\$\\n]+?)(?<!\\s)\\$(?!\\d)");
                if (html_head_close_regex == null) html_head_close_regex = new GLib.Regex ("</head>", GLib.RegexCompileFlags.CASELESS);
            } finally {
                regex_mutex.unlock ();
            }
        }

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
                    return @"<!-- IMLADRIS_IPYNB_PARSE_ERROR -->\n> **Error parsing Jupyter Notebook (.ipynb):** $(e.message)\n> Editing/saving raw JSON is disabled to prevent data corruption.\n\n```json\n$(raw_content)\n```\n";
                }
            }
            return raw_content;
        }

        public static string save_from_editor_buffer (string editor_text, Imladris.DocumentFormat format, string? existing_raw_file = null) {
            // Strip any Gtk.TextChildAnchor Unicode Object Replacement Characters (\uFFFC)
            string clean_text = editor_text.replace ("\uFFFC", "");
            if (format == Imladris.DocumentFormat.IPYNB) {
                if (clean_text.has_prefix ("<!-- IMLADRIS_IPYNB_PARSE_ERROR -->")) {
                    return existing_raw_file ?? clean_text;
                }
                try {
                    return Core.NotebookSerializer.markdown_to_ipynb (clean_text, "", existing_raw_file ?? "");
                } catch (GLib.Error e) {
                    GLib.warning ("Failed to serialize editor buffer to .ipynb JSON: %s", e.message);
                    return existing_raw_file ?? clean_text;
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
            if (format == Imladris.DocumentFormat.RTF) {
                return Core.RtfCodec.rtf_to_html (clean_text);
            }

            Core.FrontmatterData? meta;
            string body;
            Core.FrontmatterParser.split_frontmatter (clean_text, out meta, out body);

            var builder = new StringBuilder ();
            if (meta != null && !meta.is_empty ()) {
                builder.append (meta.to_html ());
            }

            string nonce = make_nonce ();
            var internal_blocks = new Gee.ArrayList<string> ();
            string processed_body = transform_code_chunks (body, nonce, internal_blocks);
            processed_body = transform_display_math (processed_body, nonce, internal_blocks);
            processed_body = transform_media_tags (processed_body, nonce, internal_blocks);

            string html_body = basic_markdown_to_html (processed_body, nonce, internal_blocks);
            builder.append (html_body);
            return builder.str;
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
                    ensure_regexes ();
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
            string tex_nonce = make_nonce ();
            string working = body;
            try {
                ensure_regexes ();
                working = latex_verb_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add ("<pre><code>" + GLib.Markup.escape_text (mi.fetch (2)) + "</code></pre>");
                    res.append_printf ("__IMLADRIS_TEX_PROT_%s_%d__", tex_nonce, idx);
                    return false;
                });

                working = latex_bracket_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), true));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%s_%d__", tex_nonce, idx);
                    return false;
                });
                working = latex_env_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (2).strip (), true));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%s_%d__", tex_nonce, idx);
                    return false;
                });
                working = latex_dd_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), true));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%s_%d__", tex_nonce, idx);
                    return false;
                });

                working = latex_paren_math_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), false));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%s_%d__", tex_nonce, idx);
                    return false;
                });
                working = latex_ce_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html ("\\ce{" + mi.fetch (1) + "}", false));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%s_%d__", tex_nonce, idx);
                    return false;
                });
                working = latex_inline_dollar_regex.replace_eval (working, -1, 0, 0, (mi, res) => {
                    int idx = prot.size;
                    prot.add (Core.MathChemEngine.render_latex_to_html (mi.fetch (1).strip (), false));
                    res.append_printf ("__IMLADRIS_TEX_PROT_%s_%d__", tex_nonce, idx);
                    return false;
                });
            } catch (GLib.RegexError e) {}

            working = GLib.Markup.escape_text (working);
            try {
                ensure_regexes ();
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
            string tex_prefix = @"__IMLADRIS_TEX_PROT_$(tex_nonce)_";
            foreach (var ln in lines) {
                string t = ln.strip ();
                if (t == "") {
                    body_out.append ("<br/>\n");
                } else if (t.has_prefix ("<h") || t.has_prefix (tex_prefix)) {
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
                final_body = final_body.replace (@"__IMLADRIS_TEX_PROT_$(tex_nonce)_$(i)__", prot[i]);
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
            string html_nonce = make_nonce ();
            string working = raw_html;

            try {
                ensure_regexes ();
                working = html_protected_tag_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    int idx = protected_blocks.size;
                    protected_blocks.add (match_info.fetch (0));
                    res.append_printf ("__IMLADRIS_HTML_PROT_%s_%d__", html_nonce, idx);
                    return false;
                });
            } catch (GLib.RegexError e) {}

            working = transform_display_math (working);

            try {
                ensure_regexes ();
                working = html_ce_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    res.append (Core.MathChemEngine.render_latex_to_html ("\\ce{" + match_info.fetch (1) + "}", false));
                    return false;
                });

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
                working = working.replace (@"__IMLADRIS_HTML_PROT_$(html_nonce)_$(i)__", protected_blocks[i]);
            }

            if (!working.contains (".math-display-card")) {
                string math_css = "<style id=\"imladris-math-css\">\n" + Core.MathChemEngine.get_math_chem_css () + "\n</style>\n";
                int head_close = -1;
                try {
                    ensure_regexes ();
                    GLib.MatchInfo hmi;
                    if (html_head_close_regex.match (working, 0, out hmi)) {
                        int end_pos;
                        hmi.fetch_pos (0, out head_close, out end_pos);
                    }
                } catch (GLib.RegexError e) {}
                if (head_close >= 0) {
                    working = working.substring (0, head_close) + math_css + working.substring (head_close);
                } else {
                    working = math_css + working;
                }
            }

            return working;
        }

        private static string emit_or_protect_block (string html, string? nonce, Gee.ArrayList<string>? internal_blocks) {
            if (nonce != null && internal_blocks != null) {
                int idx = internal_blocks.size;
                internal_blocks.add (html);
                return @"\n@@IMLBLK_$(nonce)_$(idx)@@\n";
            }
            return html;
        }

        private static string transform_display_math (string text, string? nonce = null, Gee.ArrayList<string>? internal_blocks = null) {
            string result = text;
            try {
                ensure_regexes ();
                result = display_math_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string expr = match_info.fetch (1).strip ();
                    res.append (emit_or_protect_block (Core.MathChemEngine.render_latex_to_html (expr, true), nonce, internal_blocks));
                    res.append ("\n");
                    return false;
                });

                result = equation_env_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string expr = match_info.fetch (1).strip ();
                    res.append (emit_or_protect_block (Core.MathChemEngine.render_latex_to_html (expr, true), nonce, internal_blocks));
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

        private static bool is_safe_link (string uri) {
            string value = uri.strip ().down ();
            return value.has_prefix ("https://") ||
                   value.has_prefix ("http://") ||
                   value.has_prefix ("mailto:") ||
                   value.has_prefix ("#") ||
                   (!value.has_prefix ("//") && !value.contains (":"));
        }

        private static string transform_media_tags (string text, string? nonce = null, Gee.ArrayList<string>? internal_blocks = null) {
            string result = text;
            try {
                ensure_regexes ();
                result = video_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string path = match_info.fetch (1);
                    if (is_safe_link (path)) {
                        string html = "<div class=\"media-video-container\"><video src=\"%s\" controls></video></div>".printf (
                            GLib.Markup.escape_text (path)
                        );
                        res.append (emit_or_protect_block (html, nonce, internal_blocks));
                    } else {
                        res.append (GLib.Markup.escape_text (match_info.fetch (0)));
                    }
                    return false;
                });
                result = img_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string alt = match_info.fetch (1);
                    string path = match_info.fetch (2);
                    if (is_safe_link (path)) {
                        var fig = new StringBuilder ();
                        fig.append_printf (
                            "<figure><img src=\"%s\" alt=\"%s\" style=\"max-width:100%%;height:auto\"/>",
                            GLib.Markup.escape_text (path),
                            GLib.Markup.escape_text (alt)
                        );
                        if (alt.strip () != "") {
                            fig.append_printf ("<figcaption>%s</figcaption>", GLib.Markup.escape_text (alt));
                        }
                        fig.append ("</figure>");
                        res.append (emit_or_protect_block (fig.str, nonce, internal_blocks));
                    } else {
                        res.append (GLib.Markup.escape_text (alt));
                    }
                    return false;
                });
            } catch (GLib.RegexError e) {
                GLib.warning ("Failed to convert Markdown media: %s", e.message);
            }
            return result;
        }

        private static string transform_code_chunks (string text, string? nonce = null, Gee.ArrayList<string>? internal_blocks = null) {
            string result = text;
            try {
                ensure_regexes ();
                result = chunk_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    string language = match_info.fetch (1).down ();
                    string options = match_info.fetch (2).strip ();
                    string code = match_info.fetch (3);
                    if (language == "mermaid") {
                        res.append (emit_or_protect_block (render_mermaid_svg_inline (code), nonce, internal_blocks));
                    } else {
                        var card = new StringBuilder ();
                        card.append ("<div class=\"code-chunk-card\">");
                        card.append_printf (
                            "<div class=\"code-chunk-header\"><span class=\"badge\">%s</span>%s</div>",
                            GLib.Markup.escape_text (language.up ()),
                            options != "" ? " <span class=\"chunk-opts\">" + GLib.Markup.escape_text (options) + "</span>" : ""
                        );
                        card.append_printf (
                            "<pre><code class=\"language-%s\">%s</code></pre></div>",
                            GLib.Markup.escape_text (language),
                            GLib.Markup.escape_text (code)
                        );
                        res.append (emit_or_protect_block (card.str, nonce, internal_blocks));
                    }
                    return false;
                });
                result = plain_mermaid_regex.replace_eval (result, -1, 0, 0, (match_info, res) => {
                    res.append (emit_or_protect_block (render_mermaid_svg_inline (match_info.fetch (1)), nonce, internal_blocks));
                    return false;
                });
            } catch (GLib.RegexError e) {
                GLib.warning ("Failed to convert fenced code: %s", e.message);
            }
            return result;
        }

        private static string format_inline_markdown (string line) {
            string working = line;
            string span_nonce = make_nonce ();
            var protected_spans = new Gee.ArrayList<string> ();
            try {
                ensure_regexes ();

                // 1. Protect inline code spans first so `$...$` or `\ce{...}` inside backticks are never mangled
                working = inline_code_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    int idx = protected_spans.size;
                    protected_spans.add ("<code>" + GLib.Markup.escape_text (match_info.fetch (1)) + "</code>");
                    res.append_printf ("@@IMLSPAN_%s_%d@@", span_nonce, idx);
                    return false;
                });

                // 2. Render raw \ce{...} and $...$ before Markup.escape_text so & and < are not corrupted
                working = inline_ce_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    int idx = protected_spans.size;
                    protected_spans.add (Core.MathChemEngine.render_latex_to_html ("\\ce{" + match_info.fetch (1) + "}", false));
                    res.append_printf ("@@IMLSPAN_%s_%d@@", span_nonce, idx);
                    return false;
                });
                working = inline_math_regex.replace_eval (working, -1, 0, 0, (match_info, res) => {
                    string expr = match_info.fetch (1);
                    if (expr.strip () == "") {
                        res.append (match_info.fetch (0));
                    } else {
                        int idx = protected_spans.size;
                        protected_spans.add (Core.MathChemEngine.render_latex_to_html (expr, false));
                        res.append_printf ("@@IMLSPAN_%s_%d@@", span_nonce, idx);
                    }
                    return false;
                });

                // 3. Escape remaining plain text and apply inline formatting
                string escaped = GLib.Markup.escape_text (working);
                escaped = inline_bold_regex.replace (escaped, -1, 0, "<strong>\\1</strong>");
                escaped = inline_italic_regex.replace (escaped, -1, 0, "<em>\\1</em>");
                escaped = inline_strike_regex.replace (escaped, -1, 0, "<del>\\1</del>");
                escaped = inline_sub_regex.replace (escaped, -1, 0, "<sub>\\1</sub>");
                escaped = inline_sup_regex.replace (escaped, -1, 0, "<sup>\\1</sup>");
                escaped = inline_link_regex.replace_eval (escaped, -1, 0, 0, (match_info, res) => {
                    string href = match_info.fetch (2);
                    if (is_safe_link (href)) {
                        // href is already HTML-escaped from step 3 above; do not double-escape
                        res.append_printf (
                            "<a href=\"%s\">%s</a>",
                            href,
                            match_info.fetch (1)
                        );
                    } else {
                        res.append (match_info.fetch (1));
                    }
                    return false;
                });

                // 4. Restore protected code/math/chem HTML spans
                for (int i = 0; i < protected_spans.size; i++) {
                    escaped = escaped.replace ("@@IMLSPAN_%s_%d@@".printf (span_nonce, i), protected_spans.get (i));
                }
                return escaped;
            } catch (GLib.RegexError e) {
                GLib.warning ("Failed to format inline Markdown: %s", e.message);
                return GLib.Markup.escape_text (line);
            }
        }

        private static string basic_markdown_to_html (string text, string nonce, Gee.ArrayList<string> internal_blocks) {
            var result = new StringBuilder ();
            bool in_ul = false;
            bool in_ol = false;
            bool in_table = false;
            bool in_pre = false;
            string blk_prefix = @"@@IMLBLK_$(nonce)_";

            foreach (string line in text.split ("\n")) {
                string trimmed = line.strip ();

                if (trimmed.has_prefix (blk_prefix) && trimmed.has_suffix ("@@")) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    if (in_table) {
                        result.append ("</tbody></table>\n");
                        in_table = false;
                    }
                    string idx_str = trimmed.substring (blk_prefix.length, trimmed.length - blk_prefix.length - 2);
                    int idx = int.parse (idx_str);
                    if (idx >= 0 && idx < internal_blocks.size) {
                        result.append (internal_blocks.get (idx)).append_c ('\n');
                    }
                    continue;
                }

                if (line.has_prefix ("```")) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    if (!in_pre) {
                        string lang = GLib.Markup.escape_text (line.substring (3).strip ());
                        result.append_printf ("<pre><code class=\"language-%s\">", lang != "" ? lang : "text");
                        in_pre = true;
                    } else {
                        result.append ("</code></pre>\n");
                        in_pre = false;
                    }
                    continue;
                }
                if (in_pre) {
                    result.append (GLib.Markup.escape_text (line) + "\n");
                    continue;
                }

                if (trimmed.has_prefix ("|") && trimmed.has_suffix ("|") && trimmed.length > 2) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    string[] cells = trimmed.substring (1, trimmed.length - 2).split ("|");
                    bool separator = true;
                    foreach (string cell in cells) {
                        if (cell.strip ().replace ("-", "").replace (":", "") != "") {
                            separator = false;
                            break;
                        }
                    }
                    if (!separator) {
                        if (!in_table) {
                            result.append ("<table><thead><tr>");
                            foreach (string cell in cells) {
                                result.append_printf ("<th>%s</th>", format_inline_markdown (cell.strip ()));
                            }
                            result.append ("</tr></thead><tbody>\n");
                            in_table = true;
                        } else {
                            result.append ("<tr>");
                            foreach (string cell in cells) {
                                result.append_printf ("<td>%s</td>", format_inline_markdown (cell.strip ()));
                            }
                            result.append ("</tr>\n");
                        }
                    }
                    continue;
                } else if (in_table) {
                    result.append ("</tbody></table>\n");
                    in_table = false;
                }

                if (trimmed == "") {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    result.append ("\n");
                } else if (trimmed.has_prefix ("#### ")) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    result.append_printf ("<h4>%s</h4>\n", format_inline_markdown (trimmed.substring (5)));
                } else if (trimmed.has_prefix ("### ")) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    result.append_printf ("<h3>%s</h3>\n", format_inline_markdown (trimmed.substring (4)));
                } else if (trimmed.has_prefix ("## ")) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    result.append_printf ("<h2>%s</h2>\n", format_inline_markdown (trimmed.substring (3)));
                } else if (trimmed.has_prefix ("# ")) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    result.append_printf ("<h1>%s</h1>\n", format_inline_markdown (trimmed.substring (2)));
                } else if (trimmed == "---" || trimmed == "***") {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    result.append ("<hr/>\n");
                } else if (trimmed.has_prefix ("> ")) {
                    close_markdown_lists (result, ref in_ul, ref in_ol);
                    result.append_printf ("<blockquote>%s</blockquote>\n", format_inline_markdown (trimmed.substring (2)));
                } else if (trimmed.has_prefix ("- ") || trimmed.has_prefix ("* ")) {
                    if (in_ol) { result.append ("</ol>\n"); in_ol = false; }
                    if (!in_ul) { result.append ("<ul>\n"); in_ul = true; }
                    result.append_printf ("<li>%s</li>\n", format_inline_markdown (trimmed.substring (2)));
                } else {
                    string list_item = "";
                    if (is_ordered_list_item (trimmed, out list_item)) {
                        if (in_ul) { result.append ("</ul>\n"); in_ul = false; }
                        if (!in_ol) { result.append ("<ol>\n"); in_ol = true; }
                        result.append_printf ("<li>%s</li>\n", format_inline_markdown (list_item));
                    } else {
                        close_markdown_lists (result, ref in_ul, ref in_ol);
                        result.append_printf ("<p>%s</p>\n", format_inline_markdown (line));
                    }
                }
            }

            close_markdown_lists (result, ref in_ul, ref in_ol);
            if (in_table) result.append ("</tbody></table>\n");
            if (in_pre) result.append ("</code></pre>\n");
            return result.str;
        }

        private static void close_markdown_lists (StringBuilder result, ref bool in_ul, ref bool in_ol) {
            if (in_ul) { result.append ("</ul>\n"); in_ul = false; }
            if (in_ol) { result.append ("</ol>\n"); in_ol = false; }
        }

        private static bool is_ordered_list_item (string line, out string item) {
            item = "";
            try {
                ensure_regexes ();
                GLib.MatchInfo match_info;
                if (ordered_list_regex.match (line, 0, out match_info)) {
                    item = match_info.fetch (1);
                    return true;
                }
            } catch (GLib.RegexError e) {
                GLib.warning ("Failed to parse ordered Markdown list: %s", e.message);
            }
            return false;
        }
    }
}
