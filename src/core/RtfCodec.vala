/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: Apache-2.0
 */

using GLib;

namespace Imladris.Core {

    /**
     * Standards-compliant RTF 1.x parser, serializer, and HTML converter
     * powering Apple TextEdit-style WYSIWYG .rtf editing in Imladris.
     */
    public class RtfCodec : GLib.Object {

        private class RtfState : GLib.Object {
            public bool bold = false;
            public bool italic = false;
            public bool underline = false;
            public bool strike = false;
            public int font_idx = 0;
            public int font_size_hp = 24; // half-points (24 = 12pt, Apple TextEdit default)
            public int fg_color = 0;      // 0 = default
            public int bg_color = 0;      // 0 = none
            public string align = "left"; // left, center, right, justify
            public int uc_skip = 1;
            public bool skip_group = false;
            public string group_dest = "";

            public RtfState copy () {
                var s = new RtfState ();
                s.bold = this.bold;
                s.italic = this.italic;
                s.underline = this.underline;
                s.strike = this.strike;
                s.font_idx = this.font_idx;
                s.font_size_hp = this.font_size_hp;
                s.fg_color = this.fg_color;
                s.bg_color = this.bg_color;
                s.align = this.align;
                s.uc_skip = this.uc_skip;
                s.skip_group = this.skip_group;
                s.group_dest = "";
                return s;
            }
        }

        private class RtfSpan : GLib.Object {
            public string text;
            public bool bold;
            public bool italic;
            public bool underline;
            public bool strike;
            public string font_family;
            public int font_size_pt;
            public string? fg_hex;
            public string? bg_hex;
            public string align;

            public RtfSpan (string text, RtfState st, Gee.HashMap<int, string> fonttbl, Gee.ArrayList<string?> colortbl) {
                this.text = text;
                this.bold = st.bold;
                this.italic = st.italic;
                this.underline = st.underline;
                this.strike = st.strike;
                this.font_family = fonttbl.has_key (st.font_idx) ? fonttbl.get (st.font_idx) : "Sans";
                this.font_size_pt = (st.font_size_hp > 0) ? (st.font_size_hp / 2) : 12;
                if (this.font_size_pt < 6) this.font_size_pt = 12;
                this.fg_hex = (st.fg_color > 0 && st.fg_color < colortbl.size) ? colortbl.get (st.fg_color) : null;
                this.bg_hex = (st.bg_color > 0 && st.bg_color < colortbl.size) ? colortbl.get (st.bg_color) : null;
                this.align = st.align;
            }
        }

        private static bool is_ignored_destination (string name) {
            switch (name) {
                case "fonttbl":
                case "colortbl":
                case "stylesheet":
                case "info":
                case "header":
                case "footer":
                case "headerl":
                case "headerr":
                case "headerf":
                case "footerl":
                case "footerr":
                case "footerf":
                case "pict":
                case "object":
                case "fldinst":
                case "listtable":
                case "listoverridetable":
                case "revtbl":
                case "rsidtbl":
                case "generator":
                case "themedata":
                case "colorschememapping":
                case "latentstyles":
                case "datastore":
                case "xmlnstbl":
                    return true;
                default:
                    return false;
            }
        }

        private static string decode_cp1252_byte (int b) {
            if (b >= 0x20 && b <= 0x7E) {
                return ((char) b).to_string ();
            }
            // Windows-1252 0x80..0x9F mapping
            switch (b) {
                case 0x80: return "€";
                case 0x82: return "‚";
                case 0x83: return "ƒ";
                case 0x84: return "„";
                case 0x85: return "…";
                case 0x86: return "†";
                case 0x87: return "‡";
                case 0x88: return "ˆ";
                case 0x89: return "‰";
                case 0x8A: return "Š";
                case 0x8B: return "‹";
                case 0x8C: return "Œ";
                case 0x8E: return "Ž";
                case 0x91: return "‘";
                case 0x92: return "’";
                case 0x93: return "“";
                case 0x94: return "”";
                case 0x95: return "•";
                case 0x96: return "–";
                case 0x97: return "—";
                case 0x98: return "˜";
                case 0x99: return "™";
                case 0x9A: return "š";
                case 0x9B: return "›";
                case 0x9C: return "œ";
                case 0x9E: return "ž";
                case 0x9F: return "Ÿ";
                default:
                    if (b >= 0xA0 && b <= 0xFF) {
                        return ((unichar) b).to_string ();
                    }
                    return "";
            }
        }

        private static int hex_val (char c) {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
            if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
            return -1;
        }

        private static void parse_fonttbl (string group_raw, Gee.HashMap<int, string> fonttbl) {
            // Matches {\f0\fswiss... Font Name;} or \f0... Font Name;
            try {
                var rx = new GLib.Regex ("\\\\f(\\d+)[^;{}]*?\\s+([^;{}]+);");
                GLib.MatchInfo mi;
                if (rx.match (group_raw, 0, out mi)) {
                    do {
                        int idx = int.parse (mi.fetch (1));
                        string fname = mi.fetch (2).strip ();
                        // Strip trailing RTF sub-commands if any
                        if (fname.has_suffix ("\\*")) fname = fname.substring (0, fname.length - 2).strip ();
                        if (fname.length > 0) {
                            fonttbl.set (idx, fname);
                        }
                    } while (mi.next ());
                }
            } catch (GLib.RegexError e) {}
        }

        private static void parse_colortbl (string group_raw, Gee.ArrayList<string?> colortbl) {
            colortbl.clear ();
            // Strip outer {\colortbl and trailing }
            int start = group_raw.index_of ("\\colortbl");
            string body = (start >= 0) ? group_raw.substring (start + 9) : group_raw;
            if (body.has_suffix ("}")) body = body.substring (0, body.length - 1);

            string[] entries = body.split (";");
            for (int i = 0; i < entries.length; i++) {
                string entry = entries[i].strip ();
                if (entry.length == 0) {
                    colortbl.add (null);
                    continue;
                }
                int r = 0, g = 0, b = 0;
                bool has_rgb = false;
                try {
                    var rx_r = new GLib.Regex ("\\\\red(\\d+)");
                    var rx_g = new GLib.Regex ("\\\\green(\\d+)");
                    var rx_b = new GLib.Regex ("\\\\blue(\\d+)");
                    GLib.MatchInfo mi;
                    if (rx_r.match (entry, 0, out mi)) { r = int.parse (mi.fetch (1)).clamp (0, 255); has_rgb = true; }
                    if (rx_g.match (entry, 0, out mi)) { g = int.parse (mi.fetch (1)).clamp (0, 255); has_rgb = true; }
                    if (rx_b.match (entry, 0, out mi)) { b = int.parse (mi.fetch (1)).clamp (0, 255); has_rgb = true; }
                } catch (GLib.RegexError e) {}
                colortbl.add (has_rgb ? "#%02x%02x%02x".printf (r, g, b) : null);
            }
        }

        private static int find_matching_brace (string s, int open_pos) {
            int depth = 0;
            int len = s.length;
            for (int i = open_pos; i < len; i++) {
                char c = s[i];
                if (c == '\\' && i + 1 < len) {
                    i++;
                    continue;
                }
                if (c == '{') depth++;
                else if (c == '}') {
                    depth--;
                    if (depth == 0) return i;
                }
            }
            return len - 1;
        }

        private static Gee.ArrayList<RtfSpan> parse_rtf_spans (string rtf_text) {
            var spans = new Gee.ArrayList<RtfSpan> ();
            var fonttbl = new Gee.HashMap<int, string> ();
            var colortbl = new Gee.ArrayList<string?> ();
            colortbl.add (null); // index 0 = auto/default

            string trimmed = rtf_text.strip ();
            if (!trimmed.has_prefix ("{\\rtf")) {
                var st = new RtfState ();
                spans.add (new RtfSpan (rtf_text, st, fonttbl, colortbl));
                return spans;
            }

            var stack = new Gee.ArrayList<RtfState> ();
            var state = new RtfState ();
            var buf = new GLib.StringBuilder ();
            int skip_chars = 0;
            int len = rtf_text.length;
            int i = 0;

            while (i < len) {
                char c = rtf_text[i];

                if (c == '{') {
                    if (buf.len > 0 && !state.skip_group) {
                        spans.add (new RtfSpan (buf.str, state, fonttbl, colortbl));
                        buf.truncate (0);
                    }
                    stack.add (state.copy ());
                    // Check if this group is \* or \fonttbl or \colortbl
                    if (i + 1 < len && rtf_text[i + 1] == '\\') {
                        if (i + 2 < len && rtf_text[i + 2] == '*') {
                            state.skip_group = true;
                        } else if (rtf_text.substring (i + 1).has_prefix ("\\fonttbl")) {
                            int end_b = find_matching_brace (rtf_text, i);
                            parse_fonttbl (rtf_text.substring (i, end_b - i + 1), fonttbl);
                            if (stack.size > 0) {
                                state = stack.remove_at (stack.size - 1);
                            }
                            i = end_b + 1;
                            continue;
                        } else if (rtf_text.substring (i + 1).has_prefix ("\\colortbl")) {
                            int end_b = find_matching_brace (rtf_text, i);
                            parse_colortbl (rtf_text.substring (i, end_b - i + 1), colortbl);
                            if (stack.size > 0) {
                                state = stack.remove_at (stack.size - 1);
                            }
                            i = end_b + 1;
                            continue;
                        }
                    }
                    i++;
                    continue;
                }

                if (c == '}') {
                    if (buf.len > 0 && !state.skip_group) {
                        spans.add (new RtfSpan (buf.str, state, fonttbl, colortbl));
                        buf.truncate (0);
                    }
                    if (stack.size > 0) {
                        state = stack.remove_at (stack.size - 1);
                    }
                    i++;
                    continue;
                }

                if (c == '\r' || c == '\n') {
                    i++;
                    continue;
                }

                if (c == '\\') {
                    i++;
                    if (i >= len) break;
                    char esc = rtf_text[i];

                    // Control symbols
                    if (esc == '\\' || esc == '{' || esc == '}') {
                        if (!state.skip_group) {
                            if (skip_chars > 0) skip_chars--;
                            else buf.append_c (esc);
                        }
                        i++;
                        continue;
                    }
                    if (esc == '~') {
                        if (!state.skip_group) buf.append ("\u00A0");
                        i++;
                        continue;
                    }
                    if (esc == '_') {
                        if (!state.skip_group) buf.append ("-");
                        i++;
                        continue;
                    }
                    if (esc == '-' || esc == '*') {
                        i++;
                        continue;
                    }
                    if (esc == '\n' || esc == '\r') {
                        if (!state.skip_group) buf.append_c ('\n');
                        i++;
                        continue;
                    }
                    if (esc == '\'') {
                        if (i + 2 < len) {
                            int hi = hex_val (rtf_text[i + 1]);
                            int lo = hex_val (rtf_text[i + 2]);
                            if (hi >= 0 && lo >= 0) {
                                if (!state.skip_group) {
                                    if (skip_chars > 0) skip_chars--;
                                    else buf.append (decode_cp1252_byte ((hi << 4) | lo));
                                }
                                i += 3;
                                continue;
                            }
                        }
                        i++;
                        continue;
                    }

                    // Control word: [a-zA-Z]+(-?[0-9]+)?[ ]?
                    int word_start = i;
                    while (i < len && ((rtf_text[i] >= 'a' && rtf_text[i] <= 'z') || (rtf_text[i] >= 'A' && rtf_text[i] <= 'Z'))) {
                        i++;
                    }
                    string word = rtf_text.substring (word_start, i - word_start);
                    bool has_param = false;
                    int param = 0;
                    if (i < len && (rtf_text[i] == '-' || (rtf_text[i] >= '0' && rtf_text[i] <= '9'))) {
                        has_param = true;
                        int num_start = i;
                        if (rtf_text[i] == '-') i++;
                        while (i < len && rtf_text[i] >= '0' && rtf_text[i] <= '9') {
                            i++;
                        }
                        param = int.parse (rtf_text.substring (num_start, i - num_start));
                    }
                    // Single trailing space is delimiter, not text
                    if (i < len && rtf_text[i] == ' ') {
                        i++;
                    }

                    if (is_ignored_destination (word)) {
                        state.skip_group = true;
                        continue;
                    }
                    if (state.skip_group) continue;

                    // Flush buffered text before state-changing control words
                    bool state_changing = (
                        word == "b" || word == "i" || word == "ul" || word == "ulnone" || word == "ul0" ||
                        word == "strike" || word == "f" || word == "fs" || word == "cf" || word == "cb" ||
                        word == "highlight" || word == "pard" || word == "plain" ||
                        word == "ql" || word == "qc" || word == "qr" || word == "qj"
                    );
                    if (state_changing && buf.len > 0) {
                        spans.add (new RtfSpan (buf.str, state, fonttbl, colortbl));
                        buf.truncate (0);
                    }

                    switch (word) {
                        case "par":
                        case "line":
                            buf.append_c ('\n');
                            break;
                        case "tab":
                            buf.append_c ('\t');
                            break;
                        case "bullet":
                            buf.append ("•");
                            break;
                        case "endash":
                            buf.append ("–");
                            break;
                        case "emdash":
                            buf.append ("—");
                            break;
                        case "lquote":
                            buf.append ("‘");
                            break;
                        case "rquote":
                            buf.append ("’");
                            break;
                        case "ldblquote":
                            buf.append ("“");
                            break;
                        case "rdblquote":
                            buf.append ("”");
                            break;
                        case "uc":
                            state.uc_skip = has_param ? param.clamp (0, 8) : 1;
                            break;
                        case "u":
                            if (has_param) {
                                int code = (param < 0) ? (65536 + param) : param;
                                if (code > 0) {
                                    buf.append (((unichar) code).to_string ());
                                }
                                skip_chars = state.uc_skip;
                            }
                            break;
                        case "b":
                            state.bold = !has_param || param != 0;
                            break;
                        case "i":
                            state.italic = !has_param || param != 0;
                            break;
                        case "ul":
                            state.underline = !has_param || param != 0;
                            break;
                        case "ulnone":
                        case "ul0":
                            state.underline = false;
                            break;
                        case "strike":
                            state.strike = !has_param || param != 0;
                            break;
                        case "f":
                            if (has_param) state.font_idx = param;
                            break;
                        case "fs":
                            if (has_param && param > 0) state.font_size_hp = param;
                            break;
                        case "cf":
                            if (has_param) state.fg_color = param;
                            break;
                        case "cb":
                        case "highlight":
                            if (has_param) state.bg_color = param;
                            break;
                        case "ql":
                            state.align = "left";
                            break;
                        case "qc":
                            state.align = "center";
                            break;
                        case "qr":
                            state.align = "right";
                            break;
                        case "qj":
                            state.align = "justify";
                            break;
                        case "pard":
                            state.align = "left";
                            break;
                        case "plain":
                            state.bold = false;
                            state.italic = false;
                            state.underline = false;
                            state.strike = false;
                            state.fg_color = 0;
                            state.bg_color = 0;
                            state.font_size_hp = 24;
                            break;
                        default:
                            break;
                    }
                    continue;
                }

                // Normal character
                if (!state.skip_group) {
                    if (skip_chars > 0) {
                        skip_chars--;
                        i++;
                        continue;
                    }
                    unichar uc = rtf_text.get_char (i);
                    if (uc != 0) {
                        buf.append_unichar (uc);
                        i = rtf_text.index_of_nth_char (0) >= 0 ? i + uc.to_string ().length : i + 1;
                    } else {
                        buf.append_c (c);
                        i++;
                    }
                } else {
                    i++;
                }
            }

            if (buf.len > 0 && !state.skip_group) {
                spans.add (new RtfSpan (buf.str, state, fonttbl, colortbl));
            }
            // Strip a single trailing newline if RTF ended with \par}
            if (spans.size > 0) {
                var last = spans.get (spans.size - 1);
                if (last.text.has_suffix ("\n") && last.text.length == 1) {
                    spans.remove_at (spans.size - 1);
                } else if (last.text.has_suffix ("\n")) {
                    last.text = last.text.substring (0, last.text.length - 1);
                }
            }
            return spans;
        }

        private static Gtk.TextTag ensure_tag (Gtk.TextBuffer buffer, string name) {
            var existing = buffer.tag_table.lookup (name);
            if (existing != null) return existing;

            var tag = new Gtk.TextTag (name);
            if (name == "rtf-bold") {
                tag.weight = Pango.Weight.BOLD;
            } else if (name == "rtf-italic") {
                tag.style = Pango.Style.ITALIC;
            } else if (name == "rtf-underline") {
                tag.underline = Pango.Underline.SINGLE;
            } else if (name == "rtf-strike") {
                tag.strikethrough = true;
            } else if (name.has_prefix ("rtf-fs:")) {
                int pt = int.parse (name.substring (7));
                if (pt >= 6 && pt <= 144) tag.size_points = (double) pt;
            } else if (name.has_prefix ("rtf-ff:")) {
                tag.family = name.substring (7);
            } else if (name.has_prefix ("rtf-fg:")) {
                tag.foreground = name.substring (7);
            } else if (name.has_prefix ("rtf-bg:")) {
                tag.background = name.substring (7);
            } else if (name == "rtf-align:center") {
                tag.justification = Gtk.Justification.CENTER;
            } else if (name == "rtf-align:right") {
                tag.justification = Gtk.Justification.RIGHT;
            } else if (name == "rtf-align:justify") {
                tag.justification = Gtk.Justification.FILL;
            } else if (name == "rtf-align:left") {
                tag.justification = Gtk.Justification.LEFT;
            }
            buffer.tag_table.add (tag);
            return tag;
        }

        /**
         * Parses RTF 1.x text into a Gtk.TextBuffer with rich-text Gtk.TextTags.
         */
        public static void load_rtf_into_buffer (string rtf_text, Gtk.TextBuffer buffer) {
            buffer.set_text ("", 0);
            var spans = parse_rtf_spans (rtf_text);

            Gtk.TextIter iter;
            buffer.get_start_iter (out iter);

            foreach (var sp in spans) {
                if (sp.text.length == 0) continue;
                int start_offset = iter.get_offset ();
                buffer.insert (ref iter, sp.text, -1);

                Gtk.TextIter start_it, end_it;
                buffer.get_iter_at_offset (out start_it, start_offset);
                buffer.get_iter_at_offset (out end_it, iter.get_offset ());

                if (sp.bold) buffer.apply_tag (ensure_tag (buffer, "rtf-bold"), start_it, end_it);
                if (sp.italic) buffer.apply_tag (ensure_tag (buffer, "rtf-italic"), start_it, end_it);
                if (sp.underline) buffer.apply_tag (ensure_tag (buffer, "rtf-underline"), start_it, end_it);
                if (sp.strike) buffer.apply_tag (ensure_tag (buffer, "rtf-strike"), start_it, end_it);
                if (sp.font_size_pt > 0 && sp.font_size_pt != 12) {
                    buffer.apply_tag (ensure_tag (buffer, @"rtf-fs:$(sp.font_size_pt)"), start_it, end_it);
                }
                if (sp.font_family.length > 0 && sp.font_family != "Sans") {
                    buffer.apply_tag (ensure_tag (buffer, @"rtf-ff:$(sp.font_family)"), start_it, end_it);
                }
                if (sp.fg_hex != null) {
                    buffer.apply_tag (ensure_tag (buffer, @"rtf-fg:$(sp.fg_hex)"), start_it, end_it);
                }
                if (sp.bg_hex != null) {
                    buffer.apply_tag (ensure_tag (buffer, @"rtf-bg:$(sp.bg_hex)"), start_it, end_it);
                }
                if (sp.align != "left") {
                    buffer.apply_tag (ensure_tag (buffer, @"rtf-align:$(sp.align)"), start_it, end_it);
                }
            }
            buffer.set_modified (false);
        }

        private static int register_font (string family, Gee.ArrayList<string> fonts, Gee.HashMap<string, int> font_map) {
            if (font_map.has_key (family)) return font_map.get (family);
            int idx = fonts.size;
            fonts.add (family);
            font_map.set (family, idx);
            return idx;
        }

        private static int register_color (string hex, Gee.ArrayList<string> colors, Gee.HashMap<string, int> color_map) {
            string norm = hex.down ();
            if (color_map.has_key (norm)) return color_map.get (norm);
            int idx = colors.size + 1; // 1-based in RTF colortbl (0 = auto)
            colors.add (norm);
            color_map.set (norm, idx);
            return idx;
        }

        private static string hex_to_rtf_rgb (string hex) {
            string h = hex.has_prefix ("#") ? hex.substring (1) : hex;
            if (h.length >= 6) {
                int r = (hex_val (h[0]) << 4) | hex_val (h[1]);
                int g = (hex_val (h[2]) << 4) | hex_val (h[3]);
                int b = (hex_val (h[4]) << 4) | hex_val (h[5]);
                return "\\red%d\\green%d\\blue%d;".printf (r.clamp (0, 255), g.clamp (0, 255), b.clamp (0, 255));
            }
            return "\\red0\\green0\\blue0;";
        }

        private static void append_rtf_escaped_char (GLib.StringBuilder sb, unichar c) {
            if (c == '\\') {
                sb.append ("\\\\");
            } else if (c == '{') {
                sb.append ("\\{");
            } else if (c == '}') {
                sb.append ("\\}");
            } else if (c == '\t') {
                sb.append ("\\tab ");
            } else if (c == '\n') {
                sb.append ("\\par\n");
            } else if (c >= 0x20 && c <= 0x7E) {
                sb.append_unichar (c);
            } else {
                int code = (int) c;
                if (code > 32767) code -= 65536;
                sb.append_printf ("\\u%d?", code);
            }
        }

        /**
         * Serializes a Gtk.TextBuffer with rich-text Gtk.TextTags into standards-compliant RTF 1.x.
         */
        public static string serialize_buffer_to_rtf (Gtk.TextBuffer buffer) {
            var fonts = new Gee.ArrayList<string> ();
            var font_map = new Gee.HashMap<string, int> ();
            register_font ("Sans", fonts, font_map);

            var colors = new Gee.ArrayList<string> ();
            var color_map = new Gee.HashMap<string, int> ();

            var body = new GLib.StringBuilder ();
            Gtk.TextIter it;
            buffer.get_start_iter (out it);

            bool prev_bold = false;
            bool prev_italic = false;
            bool prev_under = false;
            bool prev_strike = false;
            int prev_font = 0;
            int prev_fs = 24;
            int prev_fg = 0;
            int prev_bg = 0;
            string prev_align = "left";
            bool at_line_start = true;

            while (!it.is_end ()) {
                unichar c = it.get_char ();

                bool cur_bold = false;
                bool cur_italic = false;
                bool cur_under = false;
                bool cur_strike = false;
                int cur_font = 0;
                int cur_fs = 24;
                int cur_fg = 0;
                int cur_bg = 0;
                string cur_align = "left";

                var tags = it.get_tags ();
                foreach (var tag in tags) {
                    string? name = tag.name;
                    if (name == null) continue;
                    if (name == "rtf-bold") cur_bold = true;
                    else if (name == "rtf-italic") cur_italic = true;
                    else if (name == "rtf-underline") cur_under = true;
                    else if (name == "rtf-strike") cur_strike = true;
                    else if (name.has_prefix ("rtf-fs:")) {
                        int pt = int.parse (name.substring (7));
                        if (pt >= 6) cur_fs = pt * 2;
                    } else if (name.has_prefix ("rtf-ff:")) {
                        cur_font = register_font (name.substring (7), fonts, font_map);
                    } else if (name.has_prefix ("rtf-fg:")) {
                        cur_fg = register_color (name.substring (7), colors, color_map);
                    } else if (name.has_prefix ("rtf-bg:")) {
                        cur_bg = register_color (name.substring (7), colors, color_map);
                    } else if (name.has_prefix ("rtf-align:")) {
                        cur_align = name.substring (10);
                    }
                }

                if (at_line_start) {
                    if (cur_align != prev_align) {
                        string al_cmd = cur_align == "center" ? "\\qc" : (cur_align == "right" ? "\\qr" : (cur_align == "justify" ? "\\qj" : "\\ql"));
                        body.append ("\\pard").append (al_cmd).append ("\\sa120\\sl276\\slmult1 ");
                        prev_align = cur_align;
                    }
                    at_line_start = false;
                }

                if (c == '\n') {
                    body.append ("\\par\n");
                    at_line_start = true;
                    it.forward_char ();
                    continue;
                }

                var ctrl = new GLib.StringBuilder ();
                if (cur_font != prev_font) { ctrl.append_printf ("\\f%d", cur_font); prev_font = cur_font; }
                if (cur_fs != prev_fs) { ctrl.append_printf ("\\fs%d", cur_fs); prev_fs = cur_fs; }
                if (cur_bold != prev_bold) { ctrl.append (cur_bold ? "\\b" : "\\b0"); prev_bold = cur_bold; }
                if (cur_italic != prev_italic) { ctrl.append (cur_italic ? "\\i" : "\\i0"); prev_italic = cur_italic; }
                if (cur_under != prev_under) { ctrl.append (cur_under ? "\\ul" : "\\ulnone"); prev_under = cur_under; }
                if (cur_strike != prev_strike) { ctrl.append (cur_strike ? "\\strike" : "\\strike0"); prev_strike = cur_strike; }
                if (cur_fg != prev_fg) { ctrl.append_printf ("\\cf%d", cur_fg); prev_fg = cur_fg; }
                if (cur_bg != prev_bg) { ctrl.append_printf ("\\highlight%d", cur_bg); prev_bg = cur_bg; }

                if (ctrl.len > 0) {
                    body.append (ctrl.str).append_c (' ');
                }
                append_rtf_escaped_char (body, c);
                it.forward_char ();
            }

            var out_rtf = new GLib.StringBuilder ();
            out_rtf.append ("{\\rtf1\\ansi\\ansicpg1252\\deff0\\nouicompat\n");
            out_rtf.append ("{\\fonttbl");
            for (int fi = 0; fi < fonts.size; fi++) {
                out_rtf.append_printf ("{\\f%d\\fnil\\fcharset0 %s;}", fi, fonts.get (fi));
            }
            out_rtf.append ("}\n");

            if (colors.size > 0) {
                out_rtf.append ("{\\colortbl ;");
                foreach (var hex in colors) {
                    out_rtf.append (hex_to_rtf_rgb (hex));
                }
                out_rtf.append ("}\n");
            }

            out_rtf.append ("\\viewkind4\\uc1\\pard\\ql\\sa120\\sl276\\slmult1\\f0\\fs24\n");
            out_rtf.append (body.str);
            out_rtf.append ("\n}\n");
            return out_rtf.str;
        }

        /**
         * Extracts plain readable text from an RTF 1.x document.
         */
        public static string rtf_to_plain_text (string rtf_text) {
            var spans = parse_rtf_spans (rtf_text);
            var sb = new GLib.StringBuilder ();
            foreach (var sp in spans) {
                sb.append (sp.text);
            }
            return sb.str;
        }

        /**
         * Converts RTF 1.x text into clean styled HTML for WebKitGTK 6.0 live preview.
         */
        public static string rtf_to_html (string rtf_text) {
            var spans = parse_rtf_spans (rtf_text);
            var sb = new GLib.StringBuilder ();
            var para_buf = new GLib.StringBuilder ();
            string para_align = "left";

            foreach (var sp in spans) {
                string[] lines = sp.text.split ("\n");
                for (int li = 0; li < lines.length; li++) {
                    if (para_buf.len == 0) {
                        para_align = sp.align;
                    }
                    string seg = lines[li];
                    if (seg.length > 0) {
                        var style = new GLib.StringBuilder ();
                        if (sp.font_family != "Sans") {
                            style.append_printf ("font-family: '%s', sans-serif; ", GLib.Markup.escape_text (sp.font_family));
                        }
                        if (sp.font_size_pt != 12) {
                            style.append_printf ("font-size: %dpt; ", sp.font_size_pt);
                        }
                        if (sp.fg_hex != null) {
                            style.append_printf ("color: %s; ", sp.fg_hex);
                        }
                        if (sp.bg_hex != null) {
                            style.append_printf ("background-color: %s; ", sp.bg_hex);
                        }
                        string dec = "";
                        if (sp.underline && sp.strike) dec = "underline line-through";
                        else if (sp.underline) dec = "underline";
                        else if (sp.strike) dec = "line-through";
                        if (dec.length > 0) style.append_printf ("text-decoration: %s; ", dec);
                        if (sp.bold) style.append ("font-weight: 700; ");
                        if (sp.italic) style.append ("font-style: italic; ");

                        string escaped = GLib.Markup.escape_text (seg);
                        if (style.len > 0) {
                            para_buf.append_printf ("<span style=\"%s\">%s</span>", style.str.strip (), escaped);
                        } else {
                            para_buf.append (escaped);
                        }
                    }

                    if (li < lines.length - 1) {
                        string inner = para_buf.len > 0 ? para_buf.str : "&nbsp;";
                        sb.append_printf ("<p style=\"text-align:%s; margin: 0 0 0.65em 0;\">%s</p>\n", para_align, inner);
                        para_buf.truncate (0);
                    }
                }
            }
            if (para_buf.len > 0) {
                sb.append_printf ("<p style=\"text-align:%s; margin: 0 0 0.65em 0;\">%s</p>\n", para_align, para_buf.str);
            }
            return sb.str;
        }
    }
}
