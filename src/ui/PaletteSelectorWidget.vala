// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Imladris.Core;

namespace Imladris.UI {

    /**
     * Ptyxis-inspired 3-column color palette grid offering Rewaita color schemes.
     * Displays a collapsible grid ("Show All Palettes") with per-palette preview cards,
     * monospace text sample, and 6-color swatch strip.
     */
    public class PaletteSelectorWidget : Gtk.Box {

        private SettingsManager settings;
        private ulong palette_changed_hid = 0;
        private Gtk.FlowBox flow_box;
        private Gee.HashMap<string, Gtk.Button> card_buttons = new Gee.HashMap<string, Gtk.Button> ();
        private Gee.HashMap<string, Gtk.Image> check_badges = new Gee.HashMap<string, Gtk.Image> ();
        private Gee.ArrayList<Gtk.FlowBoxChild> extra_children = new Gee.ArrayList<Gtk.FlowBoxChild> ();
        private bool show_all = false;

        public signal void palette_selected (RewaitaPalette palette);

        public override void dispose () {
            if (palette_changed_hid != 0) {
                settings.disconnect (palette_changed_hid);
                palette_changed_hid = 0;
            }
            base.dispose ();
        }

        public PaletteSelectorWidget () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 8);
            this.settings = SettingsManager.get_default ();

            flow_box = new Gtk.FlowBox () {
                max_children_per_line = 3,
                min_children_per_line = 2,
                homogeneous = true,
                column_spacing = 10,
                row_spacing = 10,
                selection_mode = Gtk.SelectionMode.NONE
            };

            var catalog = ThemePalettes.get_catalog ();
            for (int i = 0; i < catalog.size; i++) {
                var pal = catalog[i];
                var btn = build_palette_card (pal);
                var child = new Gtk.FlowBoxChild () {
                    child = btn,
                    focusable = false
                };
                if (i >= 6) {
                    child.visible = false;
                    extra_children.add (child);
                }
                flow_box.append (child);
            }

            this.append (flow_box);
            update_selection (settings.color_palette);

            palette_changed_hid = settings.color_palette_changed.connect ((pid) => {
                update_selection (pid);
            });
        }

        public void set_show_all (bool expanded) {
            this.show_all = expanded;
            foreach (var c in extra_children) {
                c.visible = expanded;
            }
        }

        private Gtk.Button build_palette_card (RewaitaPalette pal) {
            var btn = new Gtk.Button ();
            btn.add_css_class ("flat");
            btn.add_css_class ("palette-card");
            btn.tooltip_text = pal.name;

            string card_css = """
                button.palette-card {
                    background-color: %s;
                    color: %s;
                    border: 1px solid alpha(%s, 0.22);
                    border-radius: 12px;
                    padding: 10px 12px;
                }
                button.palette-card:hover {
                    border-color: alpha(%s, 0.45);
                }
            """.printf (pal.view_bg, pal.window_fg, pal.window_fg, pal.window_fg);

            var card_prov = new Gtk.CssProvider ();
            card_prov.load_from_string (card_css);
            btn.get_style_context ().add_provider (card_prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 20);

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            // Header row: Palette title + active checkmark badge
            var hdr = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            var title_lbl = new Gtk.Label (pal.name) {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                css_classes = { "caption", "heading" }
            };
            var check_img = new Gtk.Image.from_icon_name ("object-select-symbolic") {
                pixel_size = 12,
                valign = Gtk.Align.CENTER,
                visible = false
            };
            check_img.add_css_class ("palette-check-badge");

            hdr.append (title_lbl);
            hdr.append (check_img);
            vbox.append (hdr);

            // Monospace preview snippet (Ptyxis style)
            var sample_lbl = new Gtk.Label ("The quick brown\nfox jumps over\nthe lazy dog") {
                xalign = 0,
                css_classes = { "monospace", "caption" }
            };
            vbox.append (sample_lbl);

            // 6-swatch ANSI/syntax color row
            var swatch_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
            foreach (string hex in pal.swatches) {
                var sw = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                    width_request = 18,
                    height_request = 14
                };
                sw.add_css_class ("palette-swatch");
                var sw_prov = new Gtk.CssProvider ();
                sw_prov.load_from_string (".palette-swatch { background-color: %s; border-radius: 4px; }".printf (hex));
                sw.get_style_context ().add_provider (sw_prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 20);
                swatch_row.append (sw);
            }
            vbox.append (swatch_row);

            btn.set_child (vbox);
            btn.set_data<string> ("palette-id", pal.id);
            card_buttons.set (pal.id, btn);
            check_badges.set (pal.id, check_img);

            unowned PaletteSelectorWidget self_ref = this;
            btn.clicked.connect ((b) => {
                string pid = b.get_data<string> ("palette-id");
                self_ref.settings.color_palette = pid;
                var chosen = ThemePalettes.find_by_id (pid);
                if (chosen != null) {
                    self_ref.palette_selected (chosen);
                }
            });

            return btn;
        }

        private void update_selection (string active_id) {
            foreach (var entry in card_buttons.entries) {
                bool is_active = (entry.key == active_id);
                if (is_active) {
                    entry.value.add_css_class ("is-selected");
                } else {
                    entry.value.remove_css_class ("is-selected");
                }
                var badge = check_badges.get (entry.key);
                if (badge != null) {
                    badge.visible = is_active;
                }
            }
        }
    }
}
