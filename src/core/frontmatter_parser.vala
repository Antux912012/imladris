// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Core {

    public class FrontmatterData : GLib.Object {
        public string? title { owned get; set; default = null; }
        public string? author { owned get; set; default = null; }
        public string? date { owned get; set; default = null; }
        public string? bibliography { owned get; set; default = null; }
        public string? format_type { owned get; set; default = null; }
        public string? output { owned get; set; default = null; }
        public string? abstract_text { owned get; set; default = null; }

        public bool is_empty () {
            return title == null && author == null && date == null &&
                   bibliography == null && format_type == null &&
                   output == null && abstract_text == null;
        }

        public string to_html () {
            if (is_empty ()) {
                return "";
            }

            var builder = new StringBuilder ();
            builder.append ("<header class=\"document-frontmatter-card\">\n");

            if (title != null && title.strip () != "") {
                builder.append_printf ("  <h1 class=\"frontmatter-title\">%s</h1>\n", GLib.Markup.escape_text (title));
            }

            builder.append ("  <div class=\"frontmatter-meta-grid\">\n");

            if (author != null && author.strip () != "") {
                builder.append_printf (
                    "    <div class=\"frontmatter-meta-item\"><span class=\"frontmatter-label\">Author</span><span class=\"frontmatter-value\">%s</span></div>\n",
                    GLib.Markup.escape_text (author)
                );
            }

            if (date != null && date.strip () != "") {
                builder.append_printf (
                    "    <div class=\"frontmatter-meta-item\"><span class=\"frontmatter-label\">Date</span><span class=\"frontmatter-value\">%s</span></div>\n",
                    GLib.Markup.escape_text (date)
                );
            }

            if (bibliography != null && bibliography.strip () != "") {
                builder.append_printf (
                    "    <div class=\"frontmatter-meta-item\"><span class=\"frontmatter-label\">Bibliography</span><span class=\"frontmatter-value\"><code>%s</code></span></div>\n",
                    GLib.Markup.escape_text (bibliography)
                );
            }

            string? fmt = format_type ?? output;
            if (fmt != null && fmt.strip () != "") {
                builder.append_printf (
                    "    <div class=\"frontmatter-meta-item\"><span class=\"frontmatter-label\">Format</span><span class=\"frontmatter-badge\">%s</span></div>\n",
                    GLib.Markup.escape_text (fmt)
                );
            }

            builder.append ("  </div>\n");

            if (abstract_text != null && abstract_text.strip () != "") {
                builder.append_printf (
                    "  <div class=\"frontmatter-abstract\"><strong>Abstract:</strong> %s</div>\n",
                    GLib.Markup.escape_text (abstract_text)
                );
            }

            builder.append ("</header>\n");
            return builder.str;
        }
    }

    public class FrontmatterParser : GLib.Object {

        public static void split_frontmatter (string content, out FrontmatterData? data, out string markdown_body) {
            data = null;
            markdown_body = content;

            string json_str = NativeCore.parse_frontmatter_json (content);
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_str, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return;
                }
                var obj = root.get_object ();
                if (!obj.get_boolean_member ("has_frontmatter")) {
                    return;
                }
                markdown_body = obj.get_string_member ("body");
                var meta = new FrontmatterData ();
                string t = obj.get_string_member ("title");
                if (t != "") meta.title = t;
                string a = obj.get_string_member ("author");
                if (a != "") meta.author = a;
                string d = obj.get_string_member ("date");
                if (d != "") meta.date = d;
                string b = obj.get_string_member ("bibliography");
                if (b != "") meta.bibliography = b;
                string fmt = obj.get_string_member ("format_summary");
                if (fmt != "") {
                    meta.format_type = fmt;
                    meta.output = fmt;
                }
                if (obj.has_member ("yaml") && obj.get_member ("yaml").get_node_type () == Json.NodeType.OBJECT) {
                    var yobj = obj.get_object_member ("yaml");
                    if (yobj.has_member ("abstract") && yobj.get_member ("abstract").get_node_type () == Json.NodeType.VALUE) {
                        meta.abstract_text = yobj.get_string_member ("abstract");
                    }
                }
                data = meta;
            } catch (GLib.Error e) {
                GLib.warning ("FrontmatterParser JSON decode error: %s", e.message);
            }
        }
    }
}
