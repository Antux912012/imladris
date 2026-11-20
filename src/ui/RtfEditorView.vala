/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: Apache-2.0
 */

using Gtk;
using GLib;

namespace Imladris.UI {

    /**
     * Apple TextEdit-style WYSIWYG Rich Text Format (.rtf) editor widget
     * with a compact formatting bar (font family, font size, B/I/U/S,
     * text & highlight colors, paragraph alignment, bullet list, and clear formatting).
     */
    public class RtfEditorView : Gtk.Box {

        private const string[] FONT_FAMILIES = {
            "Sans", "Serif", "Monospace", "Inter", "Cantarell",
            "Georgia", "Liberation Sans", "Liberation Serif", "Liberation Mono"
        };

        private const string[] FONT_SIZES = {
            "9", "10", "11", "12", "13", "14", "16", "18", "20", "24", "28", "36", "48"
        };

        public Gtk.TextView text_view { get; private set; }
        public Gtk.TextBuffer buffer { get; private set; }
        public Gtk.ScrolledWindow scroller { get; private set; }

        private Gtk.DropDown font_dropdown;
        private Gtk.DropDown size_dropdown;
        private Gtk.ToggleButton btn_bold;
        private Gtk.ToggleButton btn_italic;
        private Gtk.ToggleButton btn_underline;
        private Gtk.ToggleButton btn_strike;
        private Gtk.Button btn_fg_color;
        private Gtk.Button btn_bg_color;
        private Gdk.RGBA current_fg_rgba;
        private Gdk.RGBA current_bg_rgba;
        private Gtk.ToggleButton btn_align_left;
        private Gtk.ToggleButton btn_align_center;
        private Gtk.ToggleButton btn_align_right;
        private Gtk.ToggleButton btn_align_justify;

        private bool updating_toolbar = false;

        // Pending typing attributes when cursor has no selection (TextEdit behavior)
        private bool pending_attrs_active = false;
        private bool pending_bold = false;
        private bool pending_italic = false;
        private bool pending_underline = false;
        private bool pending_strike = false;
        private string pending_font = "Sans";
        private int pending_size_pt = 12;
        private string? pending_fg_hex = null;
        private string? pending_bg_hex = null;

        public signal void content_changed ();

        public RtfEditorView () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.hexpand = true;
            this.vexpand = true;

            buffer = new Gtk.TextBuffer (null);
            text_view = new Gtk.TextView.with_buffer (buffer) {
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                accepts_tab = true,
                top_margin = 36,
                bottom_margin = 36,
                left_margin = 48,
                right_margin = 48,
                hexpand = true,
                vexpand = true
            };
            text_view.add_css_class ("rtf-rich-text-view");

            build_format_bar ();

            scroller = new Gtk.ScrolledWindow () {
                child = text_view,
                hexpand = true,
                vexpand = true
            };
            this.append (scroller);

            setup_shortcuts ();
            setup_buffer_signals ();
            sync_toolbar_from_cursor ();
        }

        private void build_format_bar () {
            var bar_scroller = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.NEVER,
                hexpand = true
            };

            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 10,
                margin_end = 10
            };
            bar.add_css_class ("toolbar");

            font_dropdown = new Gtk.DropDown.from_strings (FONT_FAMILIES) {
                tooltip_text = "Font Family",
                selected = 0
            };
            font_dropdown.notify["selected"].connect (() => {
                if (updating_toolbar) return;
                uint idx = font_dropdown.selected;
                if (idx < FONT_FAMILIES.length) {
                    apply_font_family (FONT_FAMILIES[idx]);
                }
            });
            bar.append (font_dropdown);

            size_dropdown = new Gtk.DropDown.from_strings (FONT_SIZES) {
                tooltip_text = "Font Size (pt)",
                selected = 3 // 12pt default
            };
            size_dropdown.notify["selected"].connect (() => {
                if (updating_toolbar) return;
                uint idx = size_dropdown.selected;
                if (idx < FONT_SIZES.length) {
                    apply_font_size (int.parse (FONT_SIZES[idx]));
                }
            });
            bar.append (size_dropdown);

            bar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

            btn_bold = make_toggle ("format-text-bold-symbolic", "Bold (Ctrl+B)");
            btn_bold.toggled.connect (() => {
                if (!updating_toolbar) toggle_style_tag ("rtf-bold", btn_bold.active);
            });
            bar.append (btn_bold);

            btn_italic = make_toggle ("format-text-italic-symbolic", "Italic (Ctrl+I)");
            btn_italic.toggled.connect (() => {
                if (!updating_toolbar) toggle_style_tag ("rtf-italic", btn_italic.active);
            });
            bar.append (btn_italic);

            btn_underline = make_toggle ("format-text-underline-symbolic", "Underline (Ctrl+U)");
            btn_underline.toggled.connect (() => {
                if (!updating_toolbar) toggle_style_tag ("rtf-underline", btn_underline.active);
            });
            bar.append (btn_underline);

            btn_strike = make_toggle ("format-text-strikethrough-symbolic", "Strikethrough");
            btn_strike.toggled.connect (() => {
                if (!updating_toolbar) toggle_style_tag ("rtf-strike", btn_strike.active);
            });
            bar.append (btn_strike);

            bar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

            current_fg_rgba = Gdk.RGBA ();
            current_fg_rgba.parse ("#1e242b");
            btn_fg_color = new Gtk.Button.from_icon_name ("format-text-rich-symbolic") {
                tooltip_text = "Text Color"
            };
            btn_fg_color.add_css_class ("flat");
            btn_fg_color.clicked.connect (() => {
                var fg_dlg = new Gtk.ColorDialog () { title = "Text Color", with_alpha = false };
                fg_dlg.choose_rgba.begin (this.get_root () as Gtk.Window, current_fg_rgba, null, (obj, res) => {
                    try {
                        current_fg_rgba = fg_dlg.choose_rgba.end (res);
                        apply_color_tag ("rtf-fg:", rgba_to_hex (current_fg_rgba));
                    } catch (GLib.Error e) {}
                });
            });
            bar.append (btn_fg_color);

            current_bg_rgba = Gdk.RGBA ();
            current_bg_rgba.parse ("#fef08a");
            btn_bg_color = new Gtk.Button.from_icon_name ("color-select-symbolic") {
                tooltip_text = "Highlight Color"
            };
            btn_bg_color.add_css_class ("flat");
            btn_bg_color.clicked.connect (() => {
                var bg_dlg = new Gtk.ColorDialog () { title = "Highlight Color", with_alpha = false };
                bg_dlg.choose_rgba.begin (this.get_root () as Gtk.Window, current_bg_rgba, null, (obj, res) => {
                    try {
                        current_bg_rgba = bg_dlg.choose_rgba.end (res);
                        apply_color_tag ("rtf-bg:", rgba_to_hex (current_bg_rgba));
                    } catch (GLib.Error e) {}
                });
            });
            bar.append (btn_bg_color);

            bar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

            btn_align_left = make_toggle ("format-justify-left-symbolic", "Align Left");
            btn_align_left.active = true;
            btn_align_left.toggled.connect (() => {
                if (!updating_toolbar && btn_align_left.active) apply_alignment ("left");
            });
            bar.append (btn_align_left);

            btn_align_center = make_toggle ("format-justify-center-symbolic", "Align Center");
            btn_align_center.group = btn_align_left;
            btn_align_center.toggled.connect (() => {
                if (!updating_toolbar && btn_align_center.active) apply_alignment ("center");
            });
            bar.append (btn_align_center);

            btn_align_right = make_toggle ("format-justify-right-symbolic", "Align Right");
            btn_align_right.group = btn_align_left;
            btn_align_right.toggled.connect (() => {
                if (!updating_toolbar && btn_align_right.active) apply_alignment ("right");
            });
            bar.append (btn_align_right);

            btn_align_justify = make_toggle ("format-justify-fill-symbolic", "Justify");
            btn_align_justify.group = btn_align_left;
            btn_align_justify.toggled.connect (() => {
                if (!updating_toolbar && btn_align_justify.active) apply_alignment ("justify");
            });
            bar.append (btn_align_justify);

            bar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

            var btn_bullet = new Gtk.Button.from_icon_name ("view-list-bullet-symbolic") {
                tooltip_text = "Toggle Bullet List"
            };
            btn_bullet.add_css_class ("flat");
            btn_bullet.clicked.connect (toggle_bullet_on_current_lines);
            bar.append (btn_bullet);

            var btn_clear = new Gtk.Button.from_icon_name ("edit-clear-symbolic") {
                tooltip_text = "Clear Formatting"
            };
            btn_clear.add_css_class ("flat");
            btn_clear.clicked.connect (clear_formatting);
            bar.append (btn_clear);

            bar_scroller.set_child (bar);
            this.append (bar_scroller);
            this.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
        }

        private Gtk.ToggleButton make_toggle (string icon_name, string tooltip) {
            var btn = new Gtk.ToggleButton () {
                icon_name = icon_name,
                tooltip_text = tooltip
            };
            btn.add_css_class ("flat");
            return btn;
        }

        private void setup_shortcuts () {
            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    (state & Gdk.ModifierType.SHIFT_MASK) == 0 &&
                    (state & Gdk.ModifierType.ALT_MASK) == 0) {
                    if (keyval == Gdk.Key.b || keyval == Gdk.Key.B) {
                        btn_bold.active = !btn_bold.active;
                        return true;
                    }
                    if (keyval == Gdk.Key.i || keyval == Gdk.Key.I) {
                        btn_italic.active = !btn_italic.active;
                        return true;
                    }
                    if (keyval == Gdk.Key.u || keyval == Gdk.Key.U) {
                        btn_underline.active = !btn_underline.active;
                        return true;
                    }
                }
                return false;
            });
            text_view.add_controller (key_ctrl);
        }

        private void setup_buffer_signals () {
            buffer.insert_text.connect_after ((ref location, text, len) => {
                if (pending_attrs_active && text.length > 0) {
                    int end_off = location.get_offset ();
                    int char_len = text.char_count ();
                    int start_off = (end_off - char_len).clamp (0, end_off);
                    Gtk.TextIter s_it, e_it;
                    buffer.get_iter_at_offset (out s_it, start_off);
                    buffer.get_iter_at_offset (out e_it, end_off);
                    apply_pending_to_range (s_it, e_it);
                }
            });

            buffer.changed.connect (() => {
                content_changed ();
            });

            buffer.notify["cursor-position"].connect (() => {
                pending_attrs_active = false;
                sync_toolbar_from_cursor ();
            });
        }

        private Gtk.TextTag ensure_tag (string name) {
            var existing = buffer.tag_table.lookup (name);
            if (existing != null) return existing;

            var tag = new Gtk.TextTag (name);
            if (name == "rtf-bold") tag.weight = Pango.Weight.BOLD;
            else if (name == "rtf-italic") tag.style = Pango.Style.ITALIC;
            else if (name == "rtf-underline") tag.underline = Pango.Underline.SINGLE;
            else if (name == "rtf-strike") tag.strikethrough = true;
            else if (name.has_prefix ("rtf-fs:")) {
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

        private void remove_prefixed_tags (string prefix, Gtk.TextIter start, Gtk.TextIter end) {
            var to_remove = new Gee.ArrayList<Gtk.TextTag> ();
            buffer.tag_table.@foreach ((tag) => {
                if (tag.name != null && tag.name.has_prefix (prefix)) {
                    to_remove.add (tag);
                }
            });
            foreach (var t in to_remove) {
                buffer.remove_tag (t, start, end);
            }
        }

        private void capture_pending_from_toolbar () {
            pending_attrs_active = true;
            pending_bold = btn_bold.active;
            pending_italic = btn_italic.active;
            pending_underline = btn_underline.active;
            pending_strike = btn_strike.active;
            uint f_idx = font_dropdown.selected;
            pending_font = (f_idx < FONT_FAMILIES.length) ? FONT_FAMILIES[f_idx] : "Sans";
            uint s_idx = size_dropdown.selected;
            pending_size_pt = (s_idx < FONT_SIZES.length) ? int.parse (FONT_SIZES[s_idx]) : 12;
        }

        private void apply_pending_to_range (Gtk.TextIter s_it, Gtk.TextIter e_it) {
            if (pending_bold) buffer.apply_tag (ensure_tag ("rtf-bold"), s_it, e_it);
            else buffer.remove_tag (ensure_tag ("rtf-bold"), s_it, e_it);

            if (pending_italic) buffer.apply_tag (ensure_tag ("rtf-italic"), s_it, e_it);
            else buffer.remove_tag (ensure_tag ("rtf-italic"), s_it, e_it);

            if (pending_underline) buffer.apply_tag (ensure_tag ("rtf-underline"), s_it, e_it);
            else buffer.remove_tag (ensure_tag ("rtf-underline"), s_it, e_it);

            if (pending_strike) buffer.apply_tag (ensure_tag ("rtf-strike"), s_it, e_it);
            else buffer.remove_tag (ensure_tag ("rtf-strike"), s_it, e_it);

            remove_prefixed_tags ("rtf-ff:", s_it, e_it);
            if (pending_font != "Sans") buffer.apply_tag (ensure_tag (@"rtf-ff:$(pending_font)"), s_it, e_it);

            remove_prefixed_tags ("rtf-fs:", s_it, e_it);
            if (pending_size_pt != 12) buffer.apply_tag (ensure_tag (@"rtf-fs:$(pending_size_pt)"), s_it, e_it);

            if (pending_fg_hex != null) {
                remove_prefixed_tags ("rtf-fg:", s_it, e_it);
                buffer.apply_tag (ensure_tag (@"rtf-fg:$(pending_fg_hex)"), s_it, e_it);
            }
            if (pending_bg_hex != null) {
                remove_prefixed_tags ("rtf-bg:", s_it, e_it);
                buffer.apply_tag (ensure_tag (@"rtf-bg:$(pending_bg_hex)"), s_it, e_it);
            }
        }

        public void toggle_named_style (string style_name) {
            if (style_name == "bold") btn_bold.active = !btn_bold.active;
            else if (style_name == "italic") btn_italic.active = !btn_italic.active;
            else if (style_name == "underline") btn_underline.active = !btn_underline.active;
            else if (style_name == "strike" || style_name == "strikethrough") btn_strike.active = !btn_strike.active;
        }

        private void toggle_style_tag (string tag_name, bool active) {
            Gtk.TextIter s, e;
            if (buffer.get_selection_bounds (out s, out e)) {
                buffer.begin_user_action ();
                var tag = ensure_tag (tag_name);
                if (active) buffer.apply_tag (tag, s, e);
                else buffer.remove_tag (tag, s, e);
                buffer.end_user_action ();
                content_changed ();
            } else {
                capture_pending_from_toolbar ();
            }
        }

        private void apply_font_family (string family) {
            Gtk.TextIter s, e;
            if (buffer.get_selection_bounds (out s, out e)) {
                buffer.begin_user_action ();
                remove_prefixed_tags ("rtf-ff:", s, e);
                if (family != "Sans") {
                    buffer.apply_tag (ensure_tag (@"rtf-ff:$(family)"), s, e);
                }
                buffer.end_user_action ();
                content_changed ();
            } else {
                capture_pending_from_toolbar ();
            }
        }

        private void apply_font_size (int pt) {
            Gtk.TextIter s, e;
            if (buffer.get_selection_bounds (out s, out e)) {
                buffer.begin_user_action ();
                remove_prefixed_tags ("rtf-fs:", s, e);
                if (pt != 12) {
                    buffer.apply_tag (ensure_tag (@"rtf-fs:$(pt)"), s, e);
                }
                buffer.end_user_action ();
                content_changed ();
            } else {
                capture_pending_from_toolbar ();
            }
        }

        private void apply_color_tag (string prefix, string hex) {
            Gtk.TextIter s, e;
            if (buffer.get_selection_bounds (out s, out e)) {
                buffer.begin_user_action ();
                remove_prefixed_tags (prefix, s, e);
                buffer.apply_tag (ensure_tag (prefix + hex), s, e);
                buffer.end_user_action ();
                content_changed ();
            } else {
                capture_pending_from_toolbar ();
                if (prefix == "rtf-fg:") pending_fg_hex = hex;
                else if (prefix == "rtf-bg:") pending_bg_hex = hex;
            }
        }

        private void apply_alignment (string align) {
            Gtk.TextIter s, e;
            if (!buffer.get_selection_bounds (out s, out e)) {
                buffer.get_iter_at_mark (out s, buffer.get_insert ());
                e = s;
            }
            s.set_line_offset (0);
            if (!e.ends_line ()) e.forward_to_line_end ();
            if (!e.is_end ()) e.forward_char (); // include newline so paragraph tag sticks

            buffer.begin_user_action ();
            remove_prefixed_tags ("rtf-align:", s, e);
            if (align != "left") {
                buffer.apply_tag (ensure_tag (@"rtf-align:$(align)"), s, e);
            }
            buffer.end_user_action ();
            content_changed ();
        }

        private void toggle_bullet_on_current_lines () {
            Gtk.TextIter s, e;
            if (!buffer.get_selection_bounds (out s, out e)) {
                buffer.get_iter_at_mark (out s, buffer.get_insert ());
                e = s;
            }
            int start_line = s.get_line ();
            int end_line = e.get_line ();

            buffer.begin_user_action ();
            for (int ln = start_line; ln <= end_line; ln++) {
                Gtk.TextIter line_start;
                buffer.get_iter_at_line (out line_start, ln);
                Gtk.TextIter line_end = line_start;
                if (!line_end.ends_line ()) line_end.forward_to_line_end ();
                string line_txt = buffer.get_text (line_start, line_end, false);
                if (line_txt.has_prefix ("• ")) {
                    Gtk.TextIter del_end = line_start;
                    del_end.forward_chars (2);
                    buffer.delete (ref line_start, ref del_end);
                } else {
                    buffer.insert (ref line_start, "• ", -1);
                }
            }
            buffer.end_user_action ();
        }

        private void clear_formatting () {
            Gtk.TextIter s, e;
            if (buffer.get_selection_bounds (out s, out e)) {
                buffer.begin_user_action ();
                buffer.remove_all_tags (s, e);
                buffer.end_user_action ();
                sync_toolbar_from_cursor ();
                content_changed ();
            } else {
                pending_attrs_active = false;
                pending_fg_hex = null;
                pending_bg_hex = null;
                sync_toolbar_from_cursor ();
            }
        }

        private void sync_toolbar_from_cursor () {
            updating_toolbar = true;
            Gtk.TextIter it;
            Gtk.TextIter s, e;
            if (buffer.get_selection_bounds (out s, out e)) {
                it = s;
            } else {
                buffer.get_iter_at_mark (out it, buffer.get_insert ());
                if (it.get_offset () > 0 && (it.is_end () || it.ends_line ())) {
                    it.backward_char ();
                }
            }

            bool is_bold = false, is_italic = false, is_under = false, is_strike = false;
            string font = "Sans";
            int fs = 12;
            string align = "left";

            foreach (var tag in it.get_tags ()) {
                string? name = tag.name;
                if (name == null) continue;
                if (name == "rtf-bold") is_bold = true;
                else if (name == "rtf-italic") is_italic = true;
                else if (name == "rtf-underline") is_under = true;
                else if (name == "rtf-strike") is_strike = true;
                else if (name.has_prefix ("rtf-ff:")) font = name.substring (7);
                else if (name.has_prefix ("rtf-fs:")) fs = int.parse (name.substring (7));
                else if (name.has_prefix ("rtf-align:")) align = name.substring (10);
            }

            btn_bold.active = is_bold;
            btn_italic.active = is_italic;
            btn_underline.active = is_under;
            btn_strike.active = is_strike;

            uint f_sel = 0;
            for (uint i = 0; i < FONT_FAMILIES.length; i++) {
                if (FONT_FAMILIES[i].down () == font.down ()) { f_sel = i; break; }
            }
            font_dropdown.selected = f_sel;

            uint s_sel = 3; // 12pt
            string fs_str = fs.to_string ();
            for (uint i = 0; i < FONT_SIZES.length; i++) {
                if (FONT_SIZES[i] == fs_str) { s_sel = i; break; }
            }
            size_dropdown.selected = s_sel;

            if (align == "center") btn_align_center.active = true;
            else if (align == "right") btn_align_right.active = true;
            else if (align == "justify") btn_align_justify.active = true;
            else btn_align_left.active = true;

            updating_toolbar = false;
        }

        private static string rgba_to_hex (Gdk.RGBA c) {
            int r = ((int) Math.round (c.red * 255.0)).clamp (0, 255);
            int g = ((int) Math.round (c.green * 255.0)).clamp (0, 255);
            int b = ((int) Math.round (c.blue * 255.0)).clamp (0, 255);
            return "#%02x%02x%02x".printf (r, g, b);
        }

        public void load_rtf (string rtf_text) {
            Core.RtfCodec.load_rtf_into_buffer (rtf_text, buffer);
            sync_toolbar_from_cursor ();
        }

        public string serialize_rtf () {
            return Core.RtfCodec.serialize_buffer_to_rtf (buffer);
        }

        public string get_plain_text () {
            Gtk.TextIter s, e;
            buffer.get_bounds (out s, out e);
            return buffer.get_text (s, e, false);
        }
    }
}
