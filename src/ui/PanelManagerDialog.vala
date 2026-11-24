// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Core.Layout;

namespace Imladris.UI {

    /**
     * PanelManagerDialog
     * Native Libadwaita Panel & Multi-Screen Manager following GNOME & Pantheon HIG.
     * Uses Adw.PreferencesPage / Adw.PreferencesGroup / Adw.ActionRow primitives.
     */
    public class PanelManagerDialog : Adw.PreferencesDialog {

        private unowned RStudioDockLayoutState dock_state;
        private unowned WorkspaceDockManager dock_manager;
        private unowned Window? parent_window;

        private Adw.PreferencesGroup quadrants_group;
        private Adw.PreferencesGroup floating_group;
        private Adw.PreferencesGroup presets_group;
        private Gtk.ToggleButton btn_topo_4;
        private Gtk.ToggleButton btn_topo_6;
        private Gtk.ToggleButton btn_topo_lt3;
        private Gtk.ToggleButton btn_topo_rt3;
        private bool syncing_toggles = false;

        private Gee.ArrayList<Gtk.Widget> quadrant_rows = new Gee.ArrayList<Gtk.Widget> ();
        private Gee.ArrayList<Gtk.Widget> floating_rows = new Gee.ArrayList<Gtk.Widget> ();
        private Gee.ArrayList<Gtk.Widget> preset_rows = new Gee.ArrayList<Gtk.Widget> ();

        private ulong state_hid = 0;
        private ulong dock_hid = 0;

        public PanelManagerDialog (RStudioDockLayoutState state, WorkspaceDockManager mgr, Window? win) {
            Object (title: "Panels & Displays");
            this.dock_state = state;
            this.dock_manager = mgr;
            this.parent_window = win;
            this.content_width = 700;
            this.content_height = 620;

            setup_ui ();

            state_hid = dock_state.state_updated.connect (() => {
                refresh_view ();
            });
            dock_hid = dock_manager.panel_dock_changed.connect (() => {
                refresh_view ();
            });
            this.closed.connect (() => {
                if (state_hid != 0) {
                    dock_state.disconnect (state_hid);
                    state_hid = 0;
                }
                if (dock_hid != 0) {
                    dock_manager.disconnect (dock_hid);
                    dock_hid = 0;
                }
            });

            refresh_view ();
        }

        private void setup_ui () {
            var page = new Adw.PreferencesPage () {
                title = "Panels",
                icon_name = "view-grid-symbolic"
            };

            // 1. Display & Grid Topology Group
            var monitors = WorkspaceDockManager.get_connected_monitors ();
            MonitorSummary? uw = null;
            bool has_uw = WorkspaceDockManager.has_ultrawide_monitor (out uw);

            var topo_group = new Adw.PreferencesGroup () {
                title = "Workbench Layout",
                description = monitors.size > 0
                    ? @"$(monitors.size) display(s) connected. Drag tabs to move, or drag outside the window to pop out."
                    : "Drag tabs across quadrants, or drag outside the window to pop out onto another screen."
            };

            var topo_action_row = new Adw.ActionRow () {
                title = "Grid Topology",
                subtitle = "Choose 4-quadrant, 6-quadrant ultrawide (21:9 / 34:9), or 3-pane layout"
            };

            var topo_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                valign = Gtk.Align.CENTER
            };
            topo_box.add_css_class ("linked");

            btn_topo_4 = new Gtk.ToggleButton.with_label ("2×2 (4)");
            btn_topo_6 = new Gtk.ToggleButton.with_label ("3×2 (6)");
            btn_topo_lt3 = new Gtk.ToggleButton.with_label ("Left Tall");
            btn_topo_rt3 = new Gtk.ToggleButton.with_label ("Right Tall");

            btn_topo_6.set_group (btn_topo_4);
            btn_topo_lt3.set_group (btn_topo_4);
            btn_topo_rt3.set_group (btn_topo_4);

            btn_topo_4.toggled.connect (() => {
                if (!syncing_toggles && btn_topo_4.active) apply_topo (LayoutTopology.QUAD_4);
            });
            btn_topo_6.toggled.connect (() => {
                if (!syncing_toggles && btn_topo_6.active) apply_topo (LayoutTopology.QUAD_6_ULTRAWIDE);
            });
            btn_topo_lt3.toggled.connect (() => {
                if (!syncing_toggles && btn_topo_lt3.active) apply_topo (LayoutTopology.LEFT_TALL_3);
            });
            btn_topo_rt3.toggled.connect (() => {
                if (!syncing_toggles && btn_topo_rt3.active) apply_topo (LayoutTopology.RIGHT_TALL_3);
            });

            topo_box.append (btn_topo_4);
            topo_box.append (btn_topo_6);
            topo_box.append (btn_topo_lt3);
            topo_box.append (btn_topo_rt3);
            topo_action_row.add_suffix (topo_box);
            topo_group.add (topo_action_row);

            if (has_uw && uw != null) {
                var uw_row = new Adw.ActionRow () {
                    title = @"Ultrawide Display Detected ($(uw.width)×$(uw.height))",
                    subtitle = "3×2 six-quadrant grid fits this aspect ratio"
                };
                var uw_btn = new Gtk.Button.with_label ("Switch to 6-Quad") {
                    valign = Gtk.Align.CENTER,
                    css_classes = { "suggested-action" }
                };
                uw_btn.clicked.connect (() => {
                    apply_topo (LayoutTopology.QUAD_6_ULTRAWIDE);
                });
                uw_row.add_suffix (uw_btn);
                topo_group.add (uw_row);
            }

            var actions_row = new Adw.ActionRow () {
                title = "Quick Reset",
                subtitle = "Re-dock all independent windows or restore default 4-quadrant placement"
            };
            var act_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            var btn_redock_all = new Gtk.Button.with_label ("Re-dock All");
            btn_redock_all.clicked.connect (() => {
                dock_manager.redock_all_panels ();
                if (parent_window != null) parent_window.show_toast ("Re-docked all floating panels");
            });
            var btn_reset = new Gtk.Button.with_label ("Reset Default");
            btn_reset.clicked.connect (() => {
                dock_manager.redock_all_panels ();
                dock_state.reset_to_default ();
                dock_state.save_to_disk ();
                if (parent_window != null) parent_window.show_toast ("Reset workbench layout to default");
            });
            act_box.append (btn_redock_all);
            act_box.append (btn_reset);
            actions_row.add_suffix (act_box);
            topo_group.add (actions_row);

            page.add (topo_group);

            // 2. Independent Floating Windows Group
            floating_group = new Adw.PreferencesGroup () {
                title = "Independent Windows",
                description = "Popped-out panels that can be placed on any monitor"
            };
            page.add (floating_group);

            // 3. Quadrant Placement Group (Adw.ExpanderRow per quadrant)
            quadrants_group = new Adw.PreferencesGroup () {
                title = "Quadrant Placement",
                description = "Move individual panels between quadrants or pop them out"
            };
            page.add (quadrants_group);

            // 4. Saved Presets Group
            presets_group = new Adw.PreferencesGroup () {
                title = "Saved Presets"
            };
            var save_entry_row = new Adw.EntryRow () {
                title = "New Preset Name",
                show_apply_button = true
            };
            save_entry_row.apply.connect (() => {
                string name = save_entry_row.text.strip ();
                if (name.length == 0) return;
                try {
                    LayoutSerializer.save_layout (name, dock_state);
                    save_entry_row.text = "";
                    refresh_presets ();
                    if (parent_window != null) parent_window.show_toast (@"Saved layout preset '$name'");
                } catch (GLib.Error e) {
                    if (parent_window != null) parent_window.show_toast (@"Failed to save preset: $(e.message)");
                }
            });
            presets_group.add (save_entry_row);
            page.add (presets_group);

            this.add (page);
        }

        private void apply_topo (LayoutTopology topo) {
            Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
            LayoutSerializer.apply_topology_preset (topo, dock_state);
            if (parent_window != null) {
                parent_window.show_toast (@"Applied $(topo.to_title ())");
            }
        }

        private void refresh_view () {
            syncing_toggles = true;
            switch (dock_state.topology) {
                case LayoutTopology.QUAD_6_ULTRAWIDE:
                    btn_topo_6.active = true;
                    break;
                case LayoutTopology.LEFT_TALL_3:
                    btn_topo_lt3.active = true;
                    break;
                case LayoutTopology.RIGHT_TALL_3:
                    btn_topo_rt3.active = true;
                    break;
                case LayoutTopology.QUAD_4:
                default:
                    btn_topo_4.active = true;
                    break;
            }
            syncing_toggles = false;

            refresh_floating_list ();
            refresh_quadrant_rows ();
            refresh_presets ();
        }

        private void refresh_floating_list () {
            foreach (var r in floating_rows) {
                floating_group.remove (r);
            }
            floating_rows.clear ();

            var undocked = dock_manager.list_undocked_panels ();
            floating_group.visible = (undocked.size > 0);

            foreach (var pid in undocked) {
                var panel = pid;
                var geom = dock_state.get_floating_geometry (panel);
                var row = new Adw.ActionRow () {
                    title = panel.to_title (),
                    subtitle = @"$(geom.width)×$(geom.height)"
                };
                row.add_prefix (new Gtk.Image.from_icon_name (panel.to_icon_name ()));

                var btn_focus = new Gtk.Button.with_label ("Focus") { valign = Gtk.Align.CENTER };
                btn_focus.add_css_class ("flat");
                btn_focus.clicked.connect (() => {
                    dock_manager.focus_undocked_panel (panel);
                });
                row.add_suffix (btn_focus);

                var btn_redock = new Gtk.Button.with_label ("Re-dock") { valign = Gtk.Align.CENTER };
                btn_redock.clicked.connect (() => {
                    dock_manager.redock_panel (panel);
                });
                row.add_suffix (btn_redock);

                floating_group.add (row);
                floating_rows.add (row);
            }
        }

        private void refresh_quadrant_rows () {
            foreach (var r in quadrant_rows) {
                quadrants_group.remove (r);
            }
            quadrant_rows.clear ();

            var active_quads = QuadrantId.active_for_topology (dock_state.topology);
            foreach (var qid in active_quads) {
                var qc = dock_state.quadrants.get (qid);
                int count = qc != null ? qc.tabs.size : 0;

                var exp = new Adw.ExpanderRow () {
                    title = qid.to_display_name (),
                    subtitle = count == 1 ? "1 panel" : @"$count panels",
                    expanded = true
                };

                var swap_btn = new Gtk.MenuButton () {
                    icon_name = "view-refresh-symbolic",
                    tooltip_text = "Swap quadrant",
                    valign = Gtk.Align.CENTER
                };
                swap_btn.add_css_class ("flat");
                var swap_pop = new Gtk.Popover ();
                var swap_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                    margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6
                };
                swap_box.append (new Gtk.Label ("Swap with:") { css_classes = { "caption", "dim-label" }, xalign = 0 });
                foreach (var other in active_quads) {
                    if (other == qid) continue;
                    var oq = other;
                    var sb = new Gtk.Button.with_label (oq.to_display_name ()) { halign = Gtk.Align.START };
                    sb.add_css_class ("flat");
                    sb.clicked.connect (() => {
                        swap_pop.popdown ();
                        dock_state.swap_quadrants (qid, oq);
                    });
                    swap_box.append (sb);
                }
                swap_pop.set_child (swap_box);
                swap_btn.set_popover (swap_pop);
                exp.add_suffix (swap_btn);

                if (qc != null) {
                    foreach (var pid in qc.tabs) {
                        var panel = pid;
                        bool is_popped = dock_state.popped_out_panels.contains (panel);
                        var prow = new Adw.ActionRow () {
                            title = panel.to_title (),
                            subtitle = is_popped ? "Popped out" : ""
                        };
                        prow.add_prefix (new Gtk.Image.from_icon_name (panel.to_icon_name ()));

                        var move_btn = new Gtk.MenuButton () {
                            icon_name = "go-next-symbolic",
                            tooltip_text = "Move to quadrant",
                            valign = Gtk.Align.CENTER
                        };
                        move_btn.add_css_class ("flat");
                        var mpop = new Gtk.Popover ();
                        var mbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                            margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6
                        };
                        foreach (var dest in active_quads) {
                            if (dest == qid) continue;
                            var dq = dest;
                            var mb = new Gtk.Button.with_label (dq.to_display_name ()) { halign = Gtk.Align.START };
                            mb.add_css_class ("flat");
                            mb.clicked.connect (() => {
                                mpop.popdown ();
                                if (is_popped) {
                                    dock_manager.redock_panel_to (panel, dq);
                                } else {
                                    dock_state.move_tab (qid, dq, panel);
                                }
                            });
                            mbox.append (mb);
                        }
                        mpop.set_child (mbox);
                        move_btn.set_popover (mpop);
                        prow.add_suffix (move_btn);

                        var pop_btn = new Gtk.Button.from_icon_name (is_popped ? "view-restore-symbolic" : "window-new-symbolic") {
                            tooltip_text = is_popped ? "Re-dock" : "Pop out",
                            valign = Gtk.Align.CENTER
                        };
                        pop_btn.add_css_class ("flat");
                        pop_btn.clicked.connect (() => {
                            if (is_popped) {
                                dock_manager.redock_panel (panel);
                            } else {
                                dock_manager.undock_panel (panel);
                            }
                        });
                        prow.add_suffix (pop_btn);

                        exp.add_row (prow);
                    }
                }

                quadrants_group.add (exp);
                quadrant_rows.add (exp);
            }
        }

        private void refresh_presets () {
            foreach (var r in preset_rows) {
                presets_group.remove (r);
            }
            preset_rows.clear ();

            string[] saved = LayoutSerializer.list_saved_layouts ();
            foreach (string pname in saved) {
                string target_name = pname;
                var row = new Adw.ActionRow () {
                    title = target_name,
                    use_markup = false
                };
                row.add_prefix (new Gtk.Image.from_icon_name ("view-grid-symbolic"));

                var btn_load = new Gtk.Button.with_label ("Apply") { valign = Gtk.Align.CENTER };
                btn_load.clicked.connect (() => {
                    if (LayoutSerializer.load_layout (target_name, dock_state)) {
                        dock_manager.sync_windows_with_state ();
                        if (parent_window != null) parent_window.show_toast (@"Loaded layout preset '$target_name'");
                    }
                });
                row.add_suffix (btn_load);

                var btn_del = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = "Delete preset"
                };
                btn_del.add_css_class ("flat");
                btn_del.clicked.connect (() => {
                    LayoutSerializer.delete_layout (target_name);
                    refresh_presets ();
                });
                row.add_suffix (btn_del);

                presets_group.add (row);
                preset_rows.add (row);
            }
        }
    }
}
