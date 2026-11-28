// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Qual;

namespace Imladris.UI.Qual {

    public class CodebookRowItem : GLib.Object {
        public string code_id { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public string color_hex { get; set; default = "#88C0D0"; }
        public int depth { get; set; default = 0; }
        public int groundedness { get; set; default = 0; }
        public int density { get; set; default = 0; }

        public CodebookRowItem (QualCodeDef def, int grounded, int dens) {
            this.code_id = def.id;
            this.label = def.label;
            this.color_hex = def.color != "" ? def.color : "#88C0D0";
            this.depth = def.depth;
            this.groundedness = grounded;
            this.density = dens;
        }
    }

    /**
     * Hierarchical Codebook Sidebar backed by virtualized Gtk.ListView + GLib.ListStore.
     * Displays Domain Profile selector, Nord color swatches, Groundedness/Density badges,
     * coder identity, and Blinded Dual-Coding mode toggle.
     */
    public class CodebookSidebar : Gtk.Box {
        private QualWorkspaceService service;
        private GLib.ListStore code_store;
        private Gtk.SingleSelection selection_model;
        private Gtk.ListView list_view;
        private Gtk.DropDown profile_dropdown;
        private Gtk.SearchEntry search_entry;
        private Gtk.Entry coder_entry;
        private Gtk.ToggleButton blinded_toggle;
        private bool syncing_ui = false;
        private ulong state_hid = 0;

        public signal void apply_code_requested (string code_id);
        public signal void filter_by_code_requested (string? code_id);

        public CodebookSidebar (QualWorkspaceService svc) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.service = svc;
            this.width_request = 240;
            this.vexpand = true;
            this.add_css_class ("qual-codebook-sidebar");

            build_ui ();
            refresh ();

            state_hid = service.state_changed.connect (() => {
                refresh ();
            });
        }

        public void cleanup () {
            if (state_hid != 0 && service != null) {
                service.disconnect (state_hid);
                state_hid = 0;
            }
        }

        public void set_service (QualWorkspaceService svc) {
            cleanup ();
            this.service = svc;
            state_hid = service.state_changed.connect (() => {
                refresh ();
            });
            refresh ();
        }

        private void build_ui () {
            var top_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 8,
                margin_start = 8,
                margin_end = 8
            };

            // Domain Profile Selector
            var prof_names = new string[service.profiles.size];
            uint active_idx = 0;
            for (int i = 0; i < service.profiles.size; i++) {
                prof_names[i] = service.profiles[i].name;
                if (service.active_profile != null && service.profiles[i].profile_id == service.active_profile.profile_id) {
                    active_idx = (uint) i;
                }
            }
            profile_dropdown = new Gtk.DropDown (new Gtk.StringList (prof_names), null) {
                selected = active_idx,
                tooltip_text = "Select Domain Profile (.imladris/profiles/*.yaml)"
            };
            profile_dropdown.notify["selected"].connect (() => {
                if (syncing_ui) return;
                uint idx = profile_dropdown.selected;
                if (idx < service.profiles.size) {
                    service.set_active_profile_by_id (service.profiles[(int) idx].profile_id);
                }
            });
            top_box.append (profile_dropdown);

            // Coder & Blinded Dual-Coding Row
            var coder_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            coder_entry = new Gtk.Entry () {
                text = service.current_coder,
                placeholder_text = "Coder ID...",
                hexpand = true,
                tooltip_text = "Active Coder Identity (ALCOA+ user_id)"
            };
            coder_entry.changed.connect (() => {
                string v = coder_entry.text.strip ();
                if (v != "") {
                    service.current_coder = v;
                    if (service.blinded_mode) {
                        service.state_changed ();
                    }
                }
            });

            blinded_toggle = new Gtk.ToggleButton.with_label ("Blinded") {
                active = service.blinded_mode,
                tooltip_text = "Blinded Dual-Coding: Hide spans where coder != current coder until adjudication"
            };
            blinded_toggle.toggled.connect (() => {
                if (syncing_ui) return;
                service.set_blinded_coding (blinded_toggle.active);
            });

            coder_row.append (coder_entry);
            coder_row.append (blinded_toggle);
            top_box.append (coder_row);

            search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Filter codes...",
                hexpand = true
            };
            search_entry.search_changed.connect (refresh);
            top_box.append (search_entry);

            this.append (top_box);
            this.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            // Virtualized Gtk.ListView for Hierarchical Codes
            code_store = new GLib.ListStore (typeof (CodebookRowItem));
            selection_model = new Gtk.SingleSelection (code_store) {
                autoselect = false,
                can_unselect = true
            };

            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((obj) => {
                var list_item = (Gtk.ListItem) obj;
                var row_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                    margin_top = 4,
                    margin_bottom = 4,
                    margin_start = 6,
                    margin_end = 6
                };

                var swatch = new Gtk.DrawingArea () {
                    content_width = 10,
                    content_height = 10,
                    valign = Gtk.Align.CENTER
                };
                var lbl = new Gtk.Label ("") {
                    xalign = 0,
                    hexpand = true,
                    ellipsize = Pango.EllipsizeMode.END
                };
                var count_lbl = new Gtk.Label ("0") {
                    css_classes = { "caption", "numeric", "dim-label" },
                    valign = Gtk.Align.CENTER
                };
                var apply_btn = new Gtk.Button.from_icon_name ("list-add-symbolic") {
                    tooltip_text = "Apply code to active editor selection",
                    valign = Gtk.Align.CENTER
                };
                apply_btn.add_css_class ("flat");
                apply_btn.add_css_class ("dock-control-btn");

                row_box.append (swatch);
                row_box.append (lbl);
                row_box.append (count_lbl);
                row_box.append (apply_btn);
                list_item.set_child (row_box);
            });

            factory.bind.connect ((obj) => {
                var list_item = (Gtk.ListItem) obj;
                var item = list_item.get_item () as CodebookRowItem;
                var row_box = list_item.get_child () as Gtk.Box;
                if (item == null || row_box == null) return;

                row_box.margin_start = 6 + (item.depth * 14);
                var swatch = row_box.get_first_child () as Gtk.DrawingArea;
                var lbl = swatch.get_next_sibling () as Gtk.Label;
                var count_lbl = lbl.get_next_sibling () as Gtk.Label;
                var apply_btn = count_lbl.get_next_sibling () as Gtk.Button;

                string hex = item.color_hex;
                swatch.set_draw_func ((area, cr, w, h) => {
                    Gdk.RGBA rgba = Gdk.RGBA ();
                    if (!rgba.parse (hex)) rgba.parse ("#88C0D0");
                    cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, 1.0);
                    cr.arc (w / 2.0, h / 2.0, double.min (w, h) / 2.0, 0, 2 * GLib.Math.PI);
                    cr.fill ();
                });
                swatch.queue_draw ();

                lbl.label = item.label;
                lbl.tooltip_text = @"$(item.code_id) — Groundedness: $(item.groundedness), Density: $(item.density)";
                count_lbl.label = @"$(item.groundedness)";

                ulong prev_hid = apply_btn.get_data<ulong> ("qual-click-hid");
                if (prev_hid != 0) {
                    apply_btn.disconnect (prev_hid);
                }
                string cid = item.code_id;
                ulong hid = apply_btn.clicked.connect (() => {
                    apply_code_requested (cid);
                });
                apply_btn.set_data<ulong> ("qual-click-hid", hid);
            });

            list_view = new Gtk.ListView (selection_model, factory) {
                single_click_activate = false,
                vexpand = true,
                hexpand = true
            };
            list_view.activate.connect ((pos) => {
                var item = code_store.get_item (pos) as CodebookRowItem;
                if (item != null) {
                    apply_code_requested (item.code_id);
                }
            });
            selection_model.notify["selected-item"].connect (() => {
                var item = selection_model.selected_item as CodebookRowItem;
                filter_by_code_requested (item != null ? item.code_id : null);
            });

            var scroller = new Gtk.ScrolledWindow () {
                child = list_view,
                vexpand = true,
                hexpand = true,
                hscrollbar_policy = Gtk.PolicyType.NEVER
            };
            this.append (scroller);
        }

        public void refresh () {
            syncing_ui = true;
            blinded_toggle.active = service.blinded_mode;
            if (coder_entry != null && coder_entry.text != service.current_coder) {
                coder_entry.text = service.current_coder;
            }
            if (profile_dropdown != null && service.active_profile != null) {
                for (int i = 0; i < service.profiles.size; i++) {
                    if (service.profiles[i].profile_id == service.active_profile.profile_id) {
                        profile_dropdown.selected = (uint) i;
                        break;
                    }
                }
            }
            syncing_ui = false;

            code_store.remove_all ();
            if (service.active_profile == null || service.db == null) return;

            string? vis_coder = service.blinded_mode ? service.current_coder : null;
            var grounded = service.db.get_groundedness_counts (vis_coder);
            var density = service.db.get_density_counts ();
            string q = search_entry != null ? search_entry.text.strip ().down () : "";

            foreach (var cdef in service.active_profile.flatten_codes ()) {
                if (q != "" && !cdef.label.down ().contains (q) && !cdef.id.down ().contains (q)) {
                    continue;
                }
                int g = grounded.has_key (cdef.id) ? grounded.get (cdef.id) : 0;
                int d = density.has_key (cdef.id) ? density.get (cdef.id) : 0;
                code_store.append (new CodebookRowItem (cdef, g, d));
            }
        }
    }
}
