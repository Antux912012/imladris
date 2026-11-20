/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gtk;
using GLib;

namespace Imladris.UI {

    /**
     * Zero-WebKit native preview widget supporting two user-selectable modes:
     *  - NATIVE_GTK_PANGO: Native GTK4 / Pango prose & code card renderer.
     *  - CAIRO_PDF_PAGES:  Paginated A4 Cairo/Pango page preview matching PDF export.
     */
    public class NativePreviewView : Gtk.Box {
        private Gtk.ScrolledWindow scroller;
        private Gtk.Box content_box;
        private double zoom_scale = 1.0;

        private enum BlockKind {
            TITLE,
            META,
            RULE,
            H1,
            H2,
            H3,
            H4,
            CODE,
            QUOTE,
            BULLET,
            PARAGRAPH
        }

        private class DocBlock {
            public BlockKind kind;
            public string text;
            public DocBlock (BlockKind kind, string text) {
                this.kind = kind;
                this.text = text;
            }
        }

        private class PageSlice {
            public Gee.ArrayList<PageDrawItem> items = new Gee.ArrayList<PageDrawItem> ();
        }

        private class PageDrawItem {
            public BlockKind kind;
            public string text;
            public double y;
            public double height;
            public PageDrawItem (BlockKind kind, string text, double y, double height) {
                this.kind = kind;
                this.text = text;
                this.y = y;
                this.height = height;
            }
        }

        public NativePreviewView () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0, hexpand: true, vexpand: true);

            content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10) {
                margin_top = 20,
                margin_bottom = 28,
                margin_start = 24,
                margin_end = 24,
                hexpand = true
            };

            scroller = new Gtk.ScrolledWindow () {
                child = content_box,
                hexpand = true,
                vexpand = true
            };
            this.append (scroller);
        }

        public void set_zoom_percent (int percent) {
            zoom_scale = (double) percent.clamp (50, 200) / 100.0;
        }

        public void render (string raw_source, DocumentFormat fmt, Core.PreviewBackend backend, string? source_file_path = null) {
            clear_content ();

            if (fmt == DocumentFormat.HTML && source_file_path != null && GLib.FileUtils.test (source_file_path, GLib.FileTest.EXISTS)) {
                append_browser_banner (source_file_path);
            }

            var blocks = parse_document_blocks (raw_source, fmt);
            if (blocks.size == 0) {
                var empty_lbl = new Gtk.Label ("Empty document") {
                    halign = Gtk.Align.CENTER,
                    valign = Gtk.Align.CENTER,
                    margin_top = 48
                };
                empty_lbl.add_css_class ("dim-label");
                content_box.append (empty_lbl);
                return;
            }

            if (backend == Core.PreviewBackend.CAIRO_PDF_PAGES) {
                render_cairo_pdf_pages (blocks);
            } else {
                render_native_gtk_pango (blocks);
            }
        }

        private void clear_content () {
            Gtk.Widget? child = content_box.get_first_child ();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling ();
                content_box.remove (child);
                child = next;
            }
        }

        private void append_browser_banner (string file_path) {
            var banner = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_bottom = 6
            };
            banner.add_css_class ("card");
            var lbl = new Gtk.Label ("Interactive HTML/JS preview is disabled in Native mode.") {
                hexpand = true,
                xalign = 0.0f,
                margin_start = 10,
                margin_top = 6,
                margin_bottom = 6,
                wrap = true
            };
            lbl.add_css_class ("dim-label");
            var open_btn = new Gtk.Button.with_label ("Open in Browser") {
                valign = Gtk.Align.CENTER,
                margin_end = 8
            };
            open_btn.add_css_class ("flat");
            open_btn.clicked.connect (() => {
                try {
                    string uri = GLib.Filename.to_uri (file_path);
                    GLib.AppInfo.launch_default_for_uri (uri, null);
                } catch (GLib.Error e) {
                    GLib.warning ("Failed to open in browser: %s", e.message);
                }
            });
            banner.append (lbl);
            banner.append (open_btn);
            content_box.append (banner);
        }

        private Gee.ArrayList<DocBlock> parse_document_blocks (string raw_source, DocumentFormat fmt) {
            string normalized = normalize_to_markdown (raw_source, fmt);
            Core.FrontmatterData? meta;
            string body;
            Core.FrontmatterParser.split_frontmatter (normalized, out meta, out body);

            var blocks = new Gee.ArrayList<DocBlock> ();
            if (meta != null && meta.title != null && meta.title.strip () != "") {
                blocks.add (new DocBlock (BlockKind.TITLE, meta.title.strip ()));
            }
            string author = (meta != null && meta.author != null) ? meta.author.strip () : "";
            string date = (meta != null && meta.date != null) ? meta.date.strip () : "";
            if (author != "" || date != "") {
                string meta_line = (author != "" && date != "") ? @"$author  •  $date" : (author != "" ? author : date);
                blocks.add (new DocBlock (BlockKind.META, meta_line));
            }
            if (meta != null && meta.title != null && meta.title.strip () != "") {
                blocks.add (new DocBlock (BlockKind.RULE, ""));
            }

            bool in_code = false;
            var code_buf = new GLib.StringBuilder ();
            foreach (string raw_line in body.split ("\n")) {
                string trimmed = raw_line.strip ();
                if (trimmed.has_prefix ("```")) {
                    if (in_code) {
                        blocks.add (new DocBlock (BlockKind.CODE, code_buf.str));
                        code_buf.truncate (0);
                        in_code = false;
                    } else {
                        in_code = true;
                    }
                    continue;
                }
                if (in_code) {
                    if (code_buf.len > 0) code_buf.append_c ('\n');
                    code_buf.append (raw_line);
                    continue;
                }
                if (trimmed == "") continue;

                if (trimmed == "---" || trimmed == "***") {
                    blocks.add (new DocBlock (BlockKind.RULE, ""));
                } else if (trimmed.has_prefix ("#### ")) {
                    blocks.add (new DocBlock (BlockKind.H4, trimmed.substring (5)));
                } else if (trimmed.has_prefix ("### ")) {
                    blocks.add (new DocBlock (BlockKind.H3, trimmed.substring (4)));
                } else if (trimmed.has_prefix ("## ")) {
                    blocks.add (new DocBlock (BlockKind.H2, trimmed.substring (3)));
                } else if (trimmed.has_prefix ("# ")) {
                    blocks.add (new DocBlock (BlockKind.H1, trimmed.substring (2)));
                } else if (trimmed.has_prefix ("> ")) {
                    blocks.add (new DocBlock (BlockKind.QUOTE, trimmed.substring (2)));
                } else if (trimmed.has_prefix ("- ") || trimmed.has_prefix ("* ")) {
                    blocks.add (new DocBlock (BlockKind.BULLET, trimmed.substring (2)));
                } else {
                    blocks.add (new DocBlock (BlockKind.PARAGRAPH, trimmed));
                }
            }
            if (in_code && code_buf.len > 0) {
                blocks.add (new DocBlock (BlockKind.CODE, code_buf.str));
            }
            return blocks;
        }

        private static GLib.Regex? cached_style_re = null;
        private static GLib.Regex? cached_script_re = null;
        private static GLib.Regex? cached_block_re = null;
        private static GLib.Regex? cached_tag_re = null;
        private static GLib.Regex? cached_bold_re = null;
        private static GLib.Regex? cached_italic_re = null;
        private static GLib.Regex? cached_code_re = null;

        private string normalize_to_markdown (string source_text, DocumentFormat fmt) {
            string trimmed = source_text.strip ();
            if (fmt == DocumentFormat.RTF || trimmed.has_prefix ("{\\rtf")) {
                return Core.RtfCodec.rtf_to_plain_text (source_text);
            }
            if (fmt == DocumentFormat.HTML || trimmed.down ().has_prefix ("<!doctype html") || trimmed.down ().has_prefix ("<html")) {
                string cleaned = source_text;
                try {
                    if (cached_style_re == null) cached_style_re = new GLib.Regex ("<style[^>]*>.*?</style>", GLib.RegexCompileFlags.CASELESS | GLib.RegexCompileFlags.DOTALL);
                    if (cached_script_re == null) cached_script_re = new GLib.Regex ("<script[^>]*>.*?</script>", GLib.RegexCompileFlags.CASELESS | GLib.RegexCompileFlags.DOTALL);
                    if (cached_block_re == null) cached_block_re = new GLib.Regex ("</?(p|div|br|li|h[1-6]|tr)[^>]*>", GLib.RegexCompileFlags.CASELESS);
                    if (cached_tag_re == null) cached_tag_re = new GLib.Regex ("<[^>]+>");
                    cleaned = cached_style_re.replace (cleaned, -1, 0, "");
                    cleaned = cached_script_re.replace (cleaned, -1, 0, "");
                    cleaned = cached_block_re.replace (cleaned, -1, 0, "\n");
                    cleaned = cached_tag_re.replace (cleaned, -1, 0, "");
                } catch (GLib.RegexError e) {}
                return cleaned
                    .replace ("&nbsp;", " ")
                    .replace ("&amp;", "&")
                    .replace ("&lt;", "<")
                    .replace ("&gt;", ">")
                    .replace ("&quot;", "\"")
                    .replace ("&#39;", "'")
                    .strip ();
            }
            if (fmt == DocumentFormat.TEX) {
                var sb = new GLib.StringBuilder ();
                bool in_body = !source_text.contains ("\\begin{document}");
                foreach (string raw_line in source_text.split ("\n")) {
                    string t = raw_line.strip ();
                    if (t.contains ("\\begin{document}")) {
                        in_body = true;
                        continue;
                    }
                    if (t.contains ("\\end{document}")) break;
                    if (!in_body) {
                        if (t.has_prefix ("\\title{") && t.has_suffix ("}")) {
                            sb.append_printf ("# %s\n\n", t.substring (7, t.length - 8));
                        }
                        continue;
                    }
                    if (t == "\\maketitle" || t == "\\tableofcontents") continue;
                    if (t.has_prefix ("\\section{") && t.has_suffix ("}")) {
                        sb.append_printf ("# %s\n", t.substring (9, t.length - 10));
                    } else if (t.has_prefix ("\\subsection{") && t.has_suffix ("}")) {
                        sb.append_printf ("## %s\n", t.substring (12, t.length - 13));
                    } else if (t.has_prefix ("\\subsubsection{") && t.has_suffix ("}")) {
                        sb.append_printf ("### %s\n", t.substring (15, t.length - 16));
                    } else if (t.has_prefix ("\\item ")) {
                        sb.append_printf ("- %s\n", t.substring (6));
                    } else if (t == "\\begin{itemize}" || t == "\\end{itemize}" || t == "\\begin{enumerate}" || t == "\\end{enumerate}") {
                        continue;
                    } else {
                        sb.append (raw_line).append ("\n");
                    }
                }
                return sb.str;
            }
            return source_text;
        }

        private string to_pango_inline (string text) {
            string escaped = GLib.Markup.escape_text (text);
            try {
                if (cached_code_re == null) cached_code_re = new GLib.Regex ("`([^`]+)`");
                if (cached_bold_re == null) cached_bold_re = new GLib.Regex ("\\*\\*([^*]+)\\*\\*");
                if (cached_italic_re == null) cached_italic_re = new GLib.Regex ("\\*([^*]+)\\*");

                // Protect inline code spans first so '*' inside `code` never crosses <b>/<i> tags
                var code_spans = new Gee.ArrayList<string> ();
                string protected_str = cached_code_re.replace_eval (escaped, -1, 0, 0, (mi, res) => {
                    string placeholder = @"\x01CODE$(code_spans.size)\x02";
                    code_spans.add ("<tt>" + mi.fetch (1) + "</tt>");
                    res.append (placeholder);
                    return false;
                });

                protected_str = cached_bold_re.replace (protected_str, -1, 0, "<b>\\1</b>");
                protected_str = cached_italic_re.replace (protected_str, -1, 0, "<i>\\1</i>");

                for (int i = 0; i < code_spans.size; i++) {
                    protected_str = protected_str.replace (@"\x01CODE$i\x02", code_spans.get (i));
                }
                if (Pango.parse_markup (protected_str, -1, 0, null, null, null)) {
                    return protected_str;
                }
            } catch (GLib.Error e) {}
            return escaped;
        }

        private void render_native_gtk_pango (Gee.ArrayList<DocBlock> blocks) {
            foreach (var blk in blocks) {
                switch (blk.kind) {
                    case BlockKind.RULE:
                        content_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) {
                            margin_top = 4,
                            margin_bottom = 4
                        });
                        break;
                    case BlockKind.CODE:
                        var frame = new Gtk.Frame (null) {
                            margin_top = 4,
                            margin_bottom = 4
                        };
                        var code_lbl = new Gtk.Label (blk.text) {
                            xalign = 0.0f,
                            wrap = true,
                            wrap_mode = Pango.WrapMode.WORD_CHAR,
                            selectable = true,
                            margin_top = 10,
                            margin_bottom = 10,
                            margin_start = 12,
                            margin_end = 12
                        };
                        code_lbl.add_css_class ("monospace");
                        frame.set_child (code_lbl);
                        content_box.append (frame);
                        break;
                    case BlockKind.QUOTE:
                        var quote_lbl = new Gtk.Label (null) {
                            xalign = 0.0f,
                            wrap = true,
                            wrap_mode = Pango.WrapMode.WORD_CHAR,
                            selectable = true,
                            margin_start = 16
                        };
                        quote_lbl.set_markup (@"<i>$(to_pango_inline (blk.text))</i>");
                        quote_lbl.add_css_class ("dim-label");
                        content_box.append (quote_lbl);
                        break;
                    case BlockKind.BULLET:
                        var bullet_lbl = new Gtk.Label (null) {
                            xalign = 0.0f,
                            wrap = true,
                            wrap_mode = Pango.WrapMode.WORD_CHAR,
                            selectable = true,
                            margin_start = 14
                        };
                        bullet_lbl.set_markup (@"•  $(to_pango_inline (blk.text))");
                        content_box.append (bullet_lbl);
                        break;
                    case BlockKind.TITLE:
                    case BlockKind.H1:
                    case BlockKind.H2:
                    case BlockKind.H3:
                    case BlockKind.H4:
                        string size = "x-large";
                        if (blk.kind == BlockKind.TITLE) size = "xx-large";
                        else if (blk.kind == BlockKind.H2) size = "large";
                        else if (blk.kind == BlockKind.H3 || blk.kind == BlockKind.H4) size = "medium";
                        var h_lbl = new Gtk.Label (null) {
                            xalign = 0.0f,
                            wrap = true,
                            wrap_mode = Pango.WrapMode.WORD_CHAR,
                            selectable = true,
                            margin_top = (blk.kind == BlockKind.TITLE) ? 0 : 8
                        };
                        h_lbl.set_markup (@"<span size=\"$size\" weight=\"bold\">$(GLib.Markup.escape_text (blk.text))</span>");
                        content_box.append (h_lbl);
                        break;
                    case BlockKind.META:
                        var meta_lbl = new Gtk.Label (null) {
                            xalign = 0.0f,
                            wrap = true,
                            selectable = true
                        };
                        meta_lbl.set_markup (@"<i>$(GLib.Markup.escape_text (blk.text))</i>");
                        meta_lbl.add_css_class ("dim-label");
                        content_box.append (meta_lbl);
                        break;
                    default:
                        var p_lbl = new Gtk.Label (null) {
                            xalign = 0.0f,
                            wrap = true,
                            wrap_mode = Pango.WrapMode.WORD_CHAR,
                            selectable = true
                        };
                        p_lbl.set_markup (to_pango_inline (blk.text));
                        content_box.append (p_lbl);
                        break;
                }
            }
        }

        private void render_cairo_pdf_pages (Gee.ArrayList<DocBlock> blocks) {
            double page_w = 595.0;
            double page_h = 842.0;
            double margin_x = 54.0;
            double margin_top = 54.0;
            double margin_bot = 54.0;
            double content_w = page_w - 2.0 * margin_x;

            var pages = paginate_blocks_for_cairo (blocks, page_h, margin_top, margin_bot, content_w);
            int total_pages = pages.size;

            for (int p_idx = 0; p_idx < total_pages; p_idx++) {
                var page_slice = pages.get (p_idx);
                int page_num = p_idx + 1;

                var frame = new Gtk.Frame (null) {
                    halign = Gtk.Align.CENTER,
                    margin_bottom = 16
                };

                var area = new Gtk.DrawingArea () {
                    content_width = (int) Math.round (page_w * zoom_scale),
                    content_height = (int) Math.round (page_h * zoom_scale)
                };

                area.set_draw_func ((da, cr, w, h) => {
                    double sx = (double) w / page_w;
                    double sy = (double) h / page_h;
                    cr.save ();
                    cr.scale (sx, sy);

                    // White A4 paper sheet
                    cr.set_source_rgb (1.0, 1.0, 1.0);
                    cr.rectangle (0, 0, page_w, page_h);
                    cr.fill ();

                    foreach (var item in page_slice.items) {
                        draw_cairo_item (cr, item, margin_x, content_w);
                    }

                    // Page footer
                    var footer_layout = Pango.cairo_create_layout (cr);
                    var fd = Pango.FontDescription.from_string ("Sans 8.5");
                    footer_layout.set_font_description (fd);
                    footer_layout.set_text (@"Page $page_num of $total_pages", -1);
                    int fw, fh;
                    footer_layout.get_pixel_size (out fw, out fh);
                    cr.set_source_rgb (0.45, 0.50, 0.58);
                    cr.move_to ((page_w - fw) / 2.0, page_h - 32.0);
                    Pango.cairo_show_layout (cr, footer_layout);

                    cr.restore ();
                });

                frame.set_child (area);
                content_box.append (frame);
            }
        }

        private Gee.ArrayList<PageSlice> paginate_blocks_for_cairo (
            Gee.ArrayList<DocBlock> blocks,
            double page_h,
            double margin_top,
            double margin_bot,
            double content_w
        ) {
            var pages = new Gee.ArrayList<PageSlice> ();
            var current_page = new PageSlice ();
            pages.add (current_page);

            var tmp_surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, 1, 1);
            var tmp_cr = new Cairo.Context (tmp_surface);

            double y = margin_top;
            double max_y = page_h - margin_bot;

            foreach (var blk in blocks) {
                double h = measure_cairo_block_height (tmp_cr, blk, content_w);
                if (y + h > max_y && current_page.items.size > 0) {
                    current_page = new PageSlice ();
                    pages.add (current_page);
                    y = margin_top;
                }
                current_page.items.add (new PageDrawItem (blk.kind, blk.text, y, h));
                y += h + 6.0;
            }
            return pages;
        }

        private string font_for_kind (BlockKind kind) {
            switch (kind) {
                case BlockKind.TITLE:  return "Sans Bold 20";
                case BlockKind.META:   return "Sans Italic 10";
                case BlockKind.H1:     return "Sans Bold 17";
                case BlockKind.H2:     return "Sans Bold 14";
                case BlockKind.H3:     return "Sans Bold 12";
                case BlockKind.H4:     return "Sans Bold 11";
                case BlockKind.CODE:   return "Monospace 9";
                case BlockKind.QUOTE:  return "Sans Italic 10.5";
                default:               return "Sans 10.5";
            }
        }

        private double measure_cairo_block_height (Cairo.Context cr, DocBlock blk, double content_w) {
            if (blk.kind == BlockKind.RULE) return 10.0;
            double indent = (blk.kind == BlockKind.QUOTE || blk.kind == BlockKind.BULLET) ? 14.0 : 0.0;
            double pad = (blk.kind == BlockKind.CODE) ? 14.0 : 0.0;
            double avail_w = content_w - indent - pad;

            var layout = Pango.cairo_create_layout (cr);
            layout.set_font_description (Pango.FontDescription.from_string (font_for_kind (blk.kind)));
            layout.set_width ((int) (avail_w * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            string display = (blk.kind == BlockKind.BULLET) ? @"•  $(blk.text)" : blk.text;
            layout.set_text (display, -1);

            int pw, ph;
            layout.get_pixel_size (out pw, out ph);
            return (double) ph + pad;
        }

        private void draw_cairo_item (Cairo.Context cr, PageDrawItem item, double margin_x, double content_w) {
            if (item.kind == BlockKind.RULE) {
                cr.save ();
                cr.set_source_rgb (0.82, 0.85, 0.90);
                cr.set_line_width (0.75);
                cr.move_to (margin_x, item.y + 5.0);
                cr.line_to (margin_x + content_w, item.y + 5.0);
                cr.stroke ();
                cr.restore ();
                return;
            }

            if (item.kind == BlockKind.CODE) {
                cr.save ();
                cr.set_source_rgb (0.96, 0.97, 0.98);
                cr.rectangle (margin_x, item.y, content_w, item.height);
                cr.fill_preserve ();
                cr.set_source_rgb (0.85, 0.88, 0.92);
                cr.set_line_width (0.75);
                cr.stroke ();
                cr.restore ();
            } else if (item.kind == BlockKind.QUOTE) {
                cr.save ();
                cr.set_source_rgb (0.22, 0.65, 0.92);
                cr.set_line_width (3.0);
                cr.move_to (margin_x + 4.0, item.y);
                cr.line_to (margin_x + 4.0, item.y + item.height);
                cr.stroke ();
                cr.restore ();
            }

            double indent = (item.kind == BlockKind.QUOTE || item.kind == BlockKind.BULLET) ? 14.0 : 0.0;
            double pad_x = (item.kind == BlockKind.CODE) ? 7.0 : 0.0;
            double pad_y = (item.kind == BlockKind.CODE) ? 7.0 : 0.0;

            var layout = Pango.cairo_create_layout (cr);
            layout.set_font_description (Pango.FontDescription.from_string (font_for_kind (item.kind)));
            layout.set_width ((int) ((content_w - indent - 2.0 * pad_x) * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            string display = (item.kind == BlockKind.BULLET) ? @"•  $(item.text)" : item.text;
            layout.set_text (display, -1);

            cr.save ();
            if (item.kind == BlockKind.META || item.kind == BlockKind.QUOTE) {
                cr.set_source_rgb (0.35, 0.41, 0.50);
            } else {
                cr.set_source_rgb (0.09, 0.12, 0.18);
            }
            cr.move_to (margin_x + indent + pad_x, item.y + pad_y);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }
    }
}
