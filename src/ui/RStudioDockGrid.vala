// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using Imladris.Core.Layout;

namespace Imladris.UI {

    public class DockQuadrant : Gtk.Box {

        public QuadrantId quad_id { get; private set; }
        public signal void popout_tab_requested (PanelId pid);
        public signal void focus_popped_tab_requested (PanelId pid);
        public signal void redock_tab_requested (PanelId pid);
        private unowned RStudioDockLayoutState dock_state;
        private unowned PersistentPanelRegistry registry;

        private Gtk.Box header_box;
        private Gtk.Box tab_list_box;
        private Gtk.Button popout_quick_btn;
        private Gtk.Popover options_popover;
        private Gtk.Box options_pop_box;
        private Gtk.Overlay body_overlay;
        private Gtk.Box viewport_box;
        private Gtk.Box drop_overlay_indicator;
        private Gtk.Label drop_overlay_label;

        public DockQuadrant (QuadrantId id, RStudioDockLayoutState state, PersistentPanelRegistry reg) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.quad_id = id;
            this.dock_state = state;
            this.registry = reg;
            this.hexpand = true;
            this.vexpand = true;
            this.add_css_class ("rstudio-quadrant");

            // 1. QuadrantHeader (36px height)
            header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_start = 4,
                margin_end = 4,
                margin_top = 2,
                margin_bottom = 2
            };
            header_box.add_css_class ("rstudio-quadrant-header");

            tab_list_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) {
                hexpand = true
            };
            var tab_scroller = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.NEVER,
                hexpand = true,
                child = tab_list_box
            };
            header_box.append (tab_scroller);

            // Streamlined Quadrant Controls: Pop Out + Maximize + Dynamic Move/Swap Menu
            var controls_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);

            popout_quick_btn = new Gtk.Button.from_icon_name ("window-new-symbolic") {
                tooltip_text = "Pop Out Active Panel to Independent Window (Multi-Screen)"
            };
            popout_quick_btn.add_css_class ("flat");
            popout_quick_btn.add_css_class ("dock-control-btn");
            popout_quick_btn.clicked.connect (() => {
                var qc = dock_state.quadrants.get (quad_id);
                if (qc != null && qc.active_tab != null) {
                    popout_tab_requested (qc.active_tab);
                }
            });
            controls_box.append (popout_quick_btn);

            var max_btn = new Gtk.Button.from_icon_name ("window-maximize-symbolic") {
                tooltip_text = "Maximize / Restore Pane"
            };
            max_btn.add_css_class ("flat");
            max_btn.add_css_class ("dock-control-btn");
            max_btn.clicked.connect (() => {
                dock_state.toggle_maximize (quad_id);
            });
            controls_box.append (max_btn);

            var move_btn = new Gtk.MenuButton () {
                icon_name = "view-more-symbolic",
                tooltip_text = "Pane Options (Move, Swap Quadrant, Minimize, Pop Out)"
            };
            move_btn.add_css_class ("flat");
            move_btn.add_css_class ("dock-control-btn");

            options_popover = new Gtk.Popover ();
            options_pop_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6
            };
            options_popover.set_child (options_pop_box);
            options_popover.map.connect (() => {
                rebuild_options_menu ();
            });
            move_btn.set_popover (options_popover);
            controls_box.append (move_btn);

            header_box.append (controls_box);
            this.append (header_box);

            // 2. QuadrantViewport + DragDropOverlay
            body_overlay = new Gtk.Overlay () {
                hexpand = true,
                vexpand = true
            };

            viewport_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            body_overlay.set_child (viewport_box);

            drop_overlay_indicator = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                hexpand = true,
                vexpand = true,
                halign = Gtk.Align.FILL,
                valign = Gtk.Align.FILL,
                visible = false,
                can_target = false
            };
            drop_overlay_indicator.add_css_class ("dock-drop-overlay");
            drop_overlay_label = new Gtk.Label ("Drop Panel Here") {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER,
                vexpand = true,
                css_classes = { "heading" }
            };
            drop_overlay_indicator.append (drop_overlay_label);
            body_overlay.add_overlay (drop_overlay_indicator);

            this.append (body_overlay);

            // 3. Setup Drop-Target Hit Detection on Quadrant
            setup_quadrant_drop_target ();
        }

        private void rebuild_options_menu () {
            Gtk.Widget? child = options_pop_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                options_pop_box.remove (child);
                child = next;
            }

            var min_item = new Gtk.Button.with_label ("Minimize / Restore Pane") { halign = Gtk.Align.START };
            min_item.add_css_class ("flat");
            min_item.clicked.connect (() => {
                options_popover.popdown ();
                dock_state.toggle_minimize (quad_id);
            });
            options_pop_box.append (min_item);

            options_pop_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            options_pop_box.append (new Gtk.Label ("Move active tab to:") {
                css_classes = { "dim-label", "caption" },
                xalign = 0
            });

            var active_quads = QuadrantId.active_for_topology (dock_state.topology);
            foreach (var target_qid in active_quads) {
                if (target_qid == quad_id) continue;
                var dest_q = target_qid;
                var b = new Gtk.Button.with_label (dest_q.to_display_name ()) { halign = Gtk.Align.START };
                b.add_css_class ("flat");
                b.clicked.connect (() => {
                    options_popover.popdown ();
                    var qc = dock_state.quadrants.get (quad_id);
                    if (qc != null && qc.active_tab != null) {
                        dock_state.move_tab (quad_id, dest_q, qc.active_tab);
                    }
                });
                options_pop_box.append (b);
            }

            options_pop_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            options_pop_box.append (new Gtk.Label ("Swap entire quadrant with:") {
                css_classes = { "dim-label", "caption" },
                xalign = 0
            });

            foreach (var target_qid in active_quads) {
                if (target_qid == quad_id) continue;
                var swap_q = target_qid;
                var sb = new Gtk.Button.with_label (swap_q.to_display_name ()) { halign = Gtk.Align.START };
                sb.add_css_class ("flat");
                sb.clicked.connect (() => {
                    options_popover.popdown ();
                    dock_state.swap_quadrants (quad_id, swap_q);
                });
                options_pop_box.append (sb);
            }
        }

        private void show_tab_context_menu (Gtk.Widget anchor, PanelId pid) {
            var pop = new Gtk.Popover ();
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6
            };

            bool is_popped = dock_state.popped_out_panels.contains (pid);
            if (is_popped) {
                var focus_btn = new Gtk.Button.with_label ("Focus Independent Window") { halign = Gtk.Align.START };
                focus_btn.add_css_class ("flat");
                focus_btn.clicked.connect (() => {
                    pop.popdown ();
                    focus_popped_tab_requested (pid);
                });
                vbox.append (focus_btn);

                var redock_btn = new Gtk.Button.with_label ("Re-dock into Main Window") { halign = Gtk.Align.START };
                redock_btn.add_css_class ("flat");
                redock_btn.clicked.connect (() => {
                    pop.popdown ();
                    redock_tab_requested (pid);
                });
                vbox.append (redock_btn);
            } else {
                var popout_btn = new Gtk.Button.with_label ("Pop Out to Independent Window") { halign = Gtk.Align.START };
                popout_btn.add_css_class ("flat");
                popout_btn.clicked.connect (() => {
                    pop.popdown ();
                    popout_tab_requested (pid);
                });
                vbox.append (popout_btn);
            }

            vbox.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            vbox.append (new Gtk.Label (@"Move $(pid.to_title ()) to:") {
                css_classes = { "dim-label", "caption" },
                xalign = 0
            });

            foreach (var target_qid in QuadrantId.active_for_topology (dock_state.topology)) {
                if (target_qid == quad_id) continue;
                var dest_q = target_qid;
                var b = new Gtk.Button.with_label (dest_q.to_display_name ()) { halign = Gtk.Align.START };
                b.add_css_class ("flat");
                b.clicked.connect (() => {
                    pop.popdown ();
                    if (is_popped) {
                        redock_tab_requested (pid);
                    }
                    dock_state.move_tab (quad_id, dest_q, pid);
                });
                vbox.append (b);
            }

            pop.set_child (vbox);
            pop.set_parent (anchor);
            pop.closed.connect (() => {
                pop.unparent ();
            });
            pop.popup ();
        }

        private void setup_quadrant_drop_target () {
            var drop_target = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);

            drop_target.motion.connect ((x, y) => {
                drop_overlay_indicator.visible = true;
                if (y < 36.0) {
                    int idx = (int) (x / 95.0);
                    drop_overlay_label.label = @"Insert into $(quad_id.to_display_name ()) (Tab #$(idx + 1))";
                    header_box.add_css_class ("dock-header-drop-active");
                } else {
                    drop_overlay_label.label = @"Dock in $(quad_id.to_display_name ())";
                    header_box.remove_css_class ("dock-header-drop-active");
                }
                return Gdk.DragAction.MOVE;
            });

            drop_target.leave.connect (() => {
                drop_overlay_indicator.visible = false;
                header_box.remove_css_class ("dock-header-drop-active");
            });

            drop_target.drop.connect ((val, x, y) => {
                drop_overlay_indicator.visible = false;
                header_box.remove_css_class ("dock-header-drop-active");

                string payload = val.get_string ();
                // Payload format: "SOURCE_QUAD_ID:PANEL_ID:SOURCE_INDEX"
                string[] parts = payload.split (":");
                if (parts.length < 3) return false;

                QuadrantId src_quad = QuadrantId.from_id_string (parts[0]);
                PanelId? panel_id = PanelId.from_id_string (parts[1]);
                int src_idx = int.parse (parts[2]);

                if (panel_id == null) return false;

                if (y < 36.0) {
                    int dest_idx = (int) (x / 95.0);
                    if (src_quad == this.quad_id) {
                        dock_state.reorder_tab (this.quad_id, src_idx, dest_idx);
                    } else {
                        dock_state.move_tab (src_quad, this.quad_id, panel_id, dest_idx);
                    }
                } else {
                    dock_state.move_tab (src_quad, this.quad_id, panel_id, -1);
                }
                return true;
            });

            this.add_controller (drop_target);
        }

        public void sync_from_state () {
            var qconfig = dock_state.quadrants.get (quad_id);
            if (qconfig == null) return;

            // Rebuild DraggableTabList
            Gtk.Widget? child = tab_list_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                tab_list_box.remove (child);
                child = next;
            }

            for (int i = 0; i < qconfig.tabs.size; i++) {
                PanelId pid = qconfig.tabs.get (i);
                int tab_index = i;
                bool is_popped = dock_state.popped_out_panels.contains (pid);
                bool is_active = (qconfig.active_tab == pid && !is_popped);

                var tab_btn = new Gtk.Button () {
                    tooltip_text = is_popped
                        ? @"$(pid.to_title ()) is popped out in an independent window — click to focus, right-click to re-dock"
                        : @"Drag to move across quadrants or outside window to pop out; right-click for options"
                };
                tab_btn.add_css_class ("dock-tab-btn");
                if (is_active) {
                    tab_btn.add_css_class ("dock-tab-active");
                }
                if (is_popped) {
                    tab_btn.add_css_class ("dock-tab-popped-out");
                }

                var tbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
                tbox.append (new Gtk.Image.from_icon_name (pid.to_icon_name ()));
                tbox.append (new Gtk.Label (pid.to_title ()));
                if (is_popped) {
                    var ext_ico = new Gtk.Image.from_icon_name ("window-new-symbolic") {
                        pixel_size = 12
                    };
                    tbox.append (ext_ico);
                }
                tab_btn.set_child (tbox);

                tab_btn.clicked.connect (() => {
                    if (dock_state.popped_out_panels.contains (pid)) {
                        focus_popped_tab_requested (pid);
                    } else {
                        dock_state.activate_tab (quad_id, pid);
                    }
                });

                // Right-click context menu on tab
                var right_click = new Gtk.GestureClick () {
                    button = Gdk.BUTTON_SECONDARY
                };
                unowned Gtk.Button tab_btn_ref = tab_btn;
                right_click.pressed.connect ((n_press, rx, ry) => {
                    show_tab_context_menu (tab_btn_ref, pid);
                });
                tab_btn.add_controller (right_click);

                // Attach DragSource to each <DockTab/> (supports cross-quadrant move & drag-out popout)
                var drag_source = new Gtk.DragSource () {
                    actions = Gdk.DragAction.MOVE
                };
                string drag_payload = @"$(quad_id.to_id_string ()):$(pid.to_id_string ()):$tab_index";
                drag_source.prepare.connect ((x, y) => {
                    GLib.Value v = GLib.Value (typeof (string));
                    v.set_string (drag_payload);
                    return new Gdk.ContentProvider.for_value (v);
                });
                drag_source.drag_begin.connect ((drag) => {
                    var paintable = new Gtk.WidgetPaintable (tab_btn_ref);
                    drag_source.set_icon (paintable, 12, 12);
                });
                drag_source.drag_cancel.connect ((drag, reason) => {
                    // Dragged outside all dock drop zones -> pop out to independent window unless layout is locked
                    if (reason == Gdk.DragCancelReason.NO_TARGET &&
                        !dock_state.user_locked_mode &&
                        !dock_state.popped_out_panels.contains (pid)) {
                        popout_tab_requested (pid);
                        return true;
                    }
                    return false;
                });
                tab_btn.add_controller (drag_source);

                // Attach Intra-Quadrant Tab DropTarget for direct tab-on-tab reordering
                var tab_drop = new Gtk.DropTarget (typeof (string), Gdk.DragAction.MOVE);
                tab_drop.drop.connect ((val, x, y) => {
                    string p_str = val.get_string ();
                    string[] p_parts = p_str.split (":");
                    if (p_parts.length < 3) return false;
                    QuadrantId s_quad = QuadrantId.from_id_string (p_parts[0]);
                    PanelId? s_panel = PanelId.from_id_string (p_parts[1]);
                    int s_idx = int.parse (p_parts[2]);
                    if (s_panel == null) return false;

                    if (s_quad == this.quad_id) {
                        dock_state.reorder_tab (this.quad_id, s_idx, tab_index);
                    } else {
                        dock_state.move_tab (s_quad, this.quad_id, s_panel, tab_index);
                    }
                    return true;
                });
                tab_btn.add_controller (tab_drop);

                tab_list_box.append (tab_btn);
            }

            // Check minimized, empty, or popped-out state
            popout_quick_btn.sensitive = (qconfig.active_tab != null && !dock_state.popped_out_panels.contains (qconfig.active_tab));
            if (qconfig.size_state == QuadrantSizeState.MINIMIZED || qconfig.tabs.size == 0 || qconfig.active_tab == null || dock_state.popped_out_panels.contains (qconfig.active_tab)) {
                Gtk.Widget? vp_child = viewport_box.get_first_child ();
                while (vp_child != null) {
                    var next = vp_child.get_next_sibling ();
                    viewport_box.remove (vp_child);
                    vp_child = next;
                }
                body_overlay.visible = false;
                this.vexpand = false;
            } else {
                var target_panel = registry.get_panel (qconfig.active_tab);
                Gtk.Widget? vp_child = viewport_box.get_first_child ();
                bool already_mounted = (target_panel != null && vp_child == target_panel && target_panel.get_next_sibling () == null);
                if (!already_mounted) {
                    while (vp_child != null) {
                        var next = vp_child.get_next_sibling ();
                        viewport_box.remove (vp_child);
                        vp_child = next;
                    }
                    registry.mount_panel (qconfig.active_tab, viewport_box);
                } else {
                    target_panel.visible = true;
                }
                body_overlay.visible = true;
                this.vexpand = true;
            }
        }
    }

    public class RStudioDockGrid : Gtk.Box {

        public RStudioDockLayoutState dock_state { get; private set; }
        public WorkspaceDockManager dock_manager { get; private set; }
        private unowned PersistentPanelRegistry registry;
        private unowned Window? parent_window;

        private Gtk.Overlay root_overlay;
        private Gtk.Paned main_hpaned;
        private Gtk.Paned right_hpaned;
        private Gtk.Paned left_vpaned;
        private Gtk.Paned center_vpaned;
        private Gtk.Paned right_vpaned;

        private Gee.HashMap<QuadrantId, DockQuadrant> quadrant_widgets;
        private Gtk.Box center_crosshair;
        private Gtk.Box right_crosshair;

        private double drag_start_col_px = 0;
        private double drag_start_left_px = 0;
        private double drag_start_right_px = 0;
        private double drag_start_rcol_px = 0;
        private double drag_start_center_px = 0;
        private bool syncing_ratios = false;
        private uint splitter_save_id = 0;
        private uint initial_ratios_idle_id = 0;

        public override void dispose () {
            if (splitter_save_id != 0) {
                GLib.Source.remove (splitter_save_id);
                splitter_save_id = 0;
            }
            if (initial_ratios_idle_id != 0) {
                GLib.Source.remove (initial_ratios_idle_id);
                initial_ratios_idle_id = 0;
            }
            base.dispose ();
        }

        public RStudioDockGrid (RStudioDockLayoutState state, PersistentPanelRegistry reg, Window? win = null) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.dock_state = state;
            this.registry = reg;
            this.parent_window = win;
            this.dock_manager = new WorkspaceDockManager (state, reg, win);
            this.hexpand = true;
            this.vexpand = true;
            this.add_css_class ("rstudio-dock-grid");

            root_overlay = new Gtk.Overlay () {
                hexpand = true,
                vexpand = true
            };
            this.append (root_overlay);

            quadrant_widgets = new Gee.HashMap<QuadrantId, DockQuadrant> ();
            foreach (var qid in QuadrantId.all ()) {
                var qw = new DockQuadrant (qid, dock_state, registry);
                qw.popout_tab_requested.connect ((pid) => {
                    dock_manager.undock_panel (pid);
                });
                qw.focus_popped_tab_requested.connect ((pid) => {
                    dock_manager.focus_undocked_panel (pid);
                });
                qw.redock_tab_requested.connect ((pid) => {
                    dock_manager.redock_panel (pid);
                });
                quadrant_widgets.set (qid, qw);
            }

            // Build 2x2 / 3x2 Resizable Split Grid (Left | Center | Right)
            left_vpaned = new Gtk.Paned (Gtk.Orientation.VERTICAL) {
                start_child = quadrant_widgets.get (QuadrantId.Q1_TOP_LEFT),
                end_child = quadrant_widgets.get (QuadrantId.Q2_BOTTOM_LEFT),
                resize_start_child = true,
                resize_end_child = true,
                shrink_start_child = true,
                shrink_end_child = true,
                wide_handle = true,
                hexpand = true,
                vexpand = true
            };

            center_vpaned = new Gtk.Paned (Gtk.Orientation.VERTICAL) {
                start_child = quadrant_widgets.get (QuadrantId.Q5_TOP_CENTER),
                end_child = quadrant_widgets.get (QuadrantId.Q6_BOTTOM_CENTER),
                resize_start_child = true,
                resize_end_child = true,
                shrink_start_child = true,
                shrink_end_child = true,
                wide_handle = true,
                hexpand = true,
                vexpand = true,
                visible = false
            };

            right_vpaned = new Gtk.Paned (Gtk.Orientation.VERTICAL) {
                start_child = quadrant_widgets.get (QuadrantId.Q3_TOP_RIGHT),
                end_child = quadrant_widgets.get (QuadrantId.Q4_BOTTOM_RIGHT),
                resize_start_child = true,
                resize_end_child = true,
                shrink_start_child = true,
                shrink_end_child = true,
                wide_handle = true,
                hexpand = true,
                vexpand = true
            };

            right_hpaned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = center_vpaned,
                end_child = right_vpaned,
                resize_start_child = true,
                resize_end_child = true,
                shrink_start_child = true,
                shrink_end_child = true,
                wide_handle = true,
                hexpand = true,
                vexpand = true
            };

            main_hpaned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = left_vpaned,
                end_child = right_hpaned,
                resize_start_child = true,
                resize_end_child = true,
                shrink_start_child = true,
                shrink_end_child = true,
                wide_handle = true,
                hexpand = true,
                vexpand = true
            };

            root_overlay.set_child (main_hpaned);

            // Primary 4-Way Intersection Crosshair Handle (Left / Center or Left / Right)
            center_crosshair = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                width_request = 14,
                height_request = 14,
                halign = Gtk.Align.START,
                valign = Gtk.Align.START,
                tooltip_text = "Drag 4-Way Splitter Intersection (60 FPS Simultaneous Resize)"
            };
            center_crosshair.add_css_class ("dock-center-crosshair");
            center_crosshair.set_cursor_from_name ("move");

            // Secondary 4-Way Intersection Crosshair Handle (Center / Right in 6-Quadrant Ultrawide Mode)
            right_crosshair = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                width_request = 14,
                height_request = 14,
                halign = Gtk.Align.START,
                valign = Gtk.Align.START,
                visible = false,
                tooltip_text = "Drag Center/Right 4-Way Splitter Intersection (6-Quadrant Ultrawide)"
            };
            right_crosshair.add_css_class ("dock-center-crosshair");
            right_crosshair.set_cursor_from_name ("move");

            GLib.SourceFunc schedule_ratio_save = () => {
                if (splitter_save_id != 0) {
                    GLib.Source.remove (splitter_save_id);
                }
                splitter_save_id = GLib.Timeout.add (250, () => {
                    splitter_save_id = 0;
                    dock_state.save_to_disk ();
                    return GLib.Source.REMOVE;
                });
                return GLib.Source.REMOVE;
            };

            main_hpaned.notify["position"].connect (() => {
                if (syncing_ratios) return;
                int total_w = main_hpaned.get_width ();
                if (total_w >= 200) {
                    double col = SplitterRatios.clamp_ratio (main_hpaned.position / (double) total_w);
                    dock_state.ratios.main_vertical = col;
                    update_crosshair_position ();
                    schedule_ratio_save ();
                }
            });

            right_hpaned.notify["position"].connect (() => {
                if (syncing_ratios || dock_state.topology != LayoutTopology.QUAD_6_ULTRAWIDE) return;
                int rw = right_hpaned.get_width ();
                if (rw >= 200) {
                    double cv = SplitterRatios.clamp_ratio (right_hpaned.position / (double) rw);
                    dock_state.ratios.center_vertical = cv;
                    update_crosshair_position ();
                    schedule_ratio_save ();
                }
            });

            left_vpaned.notify["position"].connect (() => {
                if (syncing_ratios) return;
                int total_h = left_vpaned.get_height ();
                if (total_h >= 200) {
                    double lh = SplitterRatios.clamp_ratio (left_vpaned.position / (double) total_h);
                    dock_state.ratios.left_horizontal = lh;
                    update_crosshair_position ();
                    schedule_ratio_save ();
                }
            });

            center_vpaned.notify["position"].connect (() => {
                if (syncing_ratios || dock_state.topology != LayoutTopology.QUAD_6_ULTRAWIDE) return;
                int total_h = center_vpaned.get_height ();
                if (total_h >= 200) {
                    double ch = SplitterRatios.clamp_ratio (center_vpaned.position / (double) total_h);
                    dock_state.ratios.center_horizontal = ch;
                    update_crosshair_position ();
                    schedule_ratio_save ();
                }
            });

            right_vpaned.notify["position"].connect (() => {
                if (syncing_ratios) return;
                int total_h = right_vpaned.get_height ();
                if (total_h >= 200) {
                    double rh = SplitterRatios.clamp_ratio (right_vpaned.position / (double) total_h);
                    dock_state.ratios.right_horizontal = rh;
                    update_crosshair_position ();
                    schedule_ratio_save ();
                }
            });

            var drag_gesture = new Gtk.GestureDrag ();
            drag_gesture.drag_begin.connect ((start_x, start_y) => {
                drag_start_col_px = main_hpaned.position;
                drag_start_left_px = left_vpaned.position;
                drag_start_center_px = center_vpaned.position;
                drag_start_right_px = right_vpaned.position;
            });

            drag_gesture.drag_update.connect ((offset_x, offset_y) => {
                int total_w = main_hpaned.get_width ();
                int total_h = main_hpaned.get_height ();
                if (total_w < 200 || total_h < 200) return;

                syncing_ratios = true;
                double new_col_ratio = SplitterRatios.clamp_ratio ((drag_start_col_px + offset_x) / (double) total_w);
                double new_left_ratio = SplitterRatios.clamp_ratio ((drag_start_left_px + offset_y) / (double) total_h);

                main_hpaned.position = (int) (new_col_ratio * total_w);
                left_vpaned.position = (int) (new_left_ratio * total_h);
                dock_state.ratios.main_vertical = new_col_ratio;
                dock_state.ratios.left_horizontal = new_left_ratio;

                if (dock_state.topology == LayoutTopology.QUAD_6_ULTRAWIDE) {
                    double new_center_ratio = SplitterRatios.clamp_ratio ((drag_start_center_px + offset_y) / (double) total_h);
                    center_vpaned.position = (int) (new_center_ratio * total_h);
                    dock_state.ratios.center_horizontal = new_center_ratio;
                } else {
                    double new_right_ratio = SplitterRatios.clamp_ratio ((drag_start_right_px + offset_y) / (double) total_h);
                    right_vpaned.position = (int) (new_right_ratio * total_h);
                    dock_state.ratios.right_horizontal = new_right_ratio;
                }

                syncing_ratios = false;
                update_crosshair_position ();
            });

            drag_gesture.drag_end.connect ((offset_x, offset_y) => {
                update_crosshair_position ();
                dock_state.save_to_disk ();
            });
            center_crosshair.add_controller (drag_gesture);
            root_overlay.add_overlay (center_crosshair);

            var right_drag_gesture = new Gtk.GestureDrag ();
            right_drag_gesture.drag_begin.connect ((start_x, start_y) => {
                drag_start_rcol_px = right_hpaned.position;
                drag_start_center_px = center_vpaned.position;
                drag_start_right_px = right_vpaned.position;
            });
            right_drag_gesture.drag_update.connect ((offset_x, offset_y) => {
                int rw = right_hpaned.get_width ();
                int total_h = right_hpaned.get_height ();
                if (rw < 200 || total_h < 200) return;

                syncing_ratios = true;
                double new_cv = SplitterRatios.clamp_ratio ((drag_start_rcol_px + offset_x) / (double) rw);
                double new_ch = SplitterRatios.clamp_ratio ((drag_start_center_px + offset_y) / (double) total_h);
                double new_rh = SplitterRatios.clamp_ratio ((drag_start_right_px + offset_y) / (double) total_h);

                right_hpaned.position = (int) (new_cv * rw);
                center_vpaned.position = (int) (new_ch * total_h);
                right_vpaned.position = (int) (new_rh * total_h);

                dock_state.ratios.center_vertical = new_cv;
                dock_state.ratios.center_horizontal = new_ch;
                dock_state.ratios.right_horizontal = new_rh;
                syncing_ratios = false;
                update_crosshair_position ();
            });
            right_drag_gesture.drag_end.connect ((offset_x, offset_y) => {
                update_crosshair_position ();
                dock_state.save_to_disk ();
            });
            right_crosshair.add_controller (right_drag_gesture);
            root_overlay.add_overlay (right_crosshair);

            // Connect state changes
            dock_state.state_updated.connect (() => {
                refresh_dock_layout ();
            });

            // Apply initial ratios once widget is allocated
            initial_ratios_idle_id = GLib.Idle.add (() => {
                initial_ratios_idle_id = 0;
                apply_splitter_ratios ();
                return GLib.Source.REMOVE;
            });
        }

        private void apply_vpaned_ratio (Gtk.Paned vpaned, QuadrantId top_id, QuadrantId bot_id, double ratio, int total_h) {
            var q_top = dock_state.quadrants.get (top_id);
            var q_bot = dock_state.quadrants.get (bot_id);
            if (q_bot != null && (q_bot.size_state == QuadrantSizeState.MINIMIZED || q_bot.tabs.size == 0 || q_bot.active_tab == null)) {
                vpaned.position = total_h - 38;
            } else if (q_top != null && (q_top.size_state == QuadrantSizeState.MINIMIZED || q_top.tabs.size == 0 || q_top.active_tab == null)) {
                vpaned.position = 38;
            } else {
                vpaned.position = (int) (ratio * total_h);
            }
        }

        public void apply_splitter_ratios () {
            int total_w = main_hpaned.get_width ();
            int total_h = main_hpaned.get_height ();
            if (total_w < 200) total_w = (dock_state.topology == LayoutTopology.QUAD_6_ULTRAWIDE) ? 2400 : 1280;
            if (total_h < 200) total_h = 720;

            syncing_ratios = true;
            main_hpaned.position = (int) (dock_state.ratios.main_vertical * total_w);

            if (dock_state.topology == LayoutTopology.QUAD_6_ULTRAWIDE) {
                int right_w = right_hpaned.get_width ();
                if (right_w < 200) right_w = total_w - main_hpaned.position;
                right_hpaned.position = (int) (dock_state.ratios.center_vertical * right_w);
                apply_vpaned_ratio (center_vpaned, QuadrantId.Q5_TOP_CENTER, QuadrantId.Q6_BOTTOM_CENTER, dock_state.ratios.center_horizontal, total_h);
            } else {
                right_hpaned.position = 0;
            }

            apply_vpaned_ratio (left_vpaned, QuadrantId.Q1_TOP_LEFT, QuadrantId.Q2_BOTTOM_LEFT, dock_state.ratios.left_horizontal, total_h);
            apply_vpaned_ratio (right_vpaned, QuadrantId.Q3_TOP_RIGHT, QuadrantId.Q4_BOTTOM_RIGHT, dock_state.ratios.right_horizontal, total_h);

            syncing_ratios = false;
            update_crosshair_position ();
        }

        private void update_crosshair_position () {
            if (center_crosshair != null && center_crosshair.visible) {
                int x = main_hpaned.position - 7;
                int right_pos = (dock_state.topology == LayoutTopology.QUAD_6_ULTRAWIDE)
                    ? center_vpaned.position
                    : right_vpaned.position;
                int y = ((left_vpaned.position + right_pos) / 2) - 7;
                center_crosshair.margin_start = x > 0 ? x : 0;
                center_crosshair.margin_top = y > 0 ? y : 0;
            }
            if (right_crosshair != null && right_crosshair.visible) {
                int x2 = main_hpaned.position + right_hpaned.position - 7;
                int y2 = ((center_vpaned.position + right_vpaned.position) / 2) - 7;
                right_crosshair.margin_start = x2 > 0 ? x2 : 0;
                right_crosshair.margin_top = y2 > 0 ? y2 : 0;
            }
        }

        public void refresh_dock_layout () {
            // Check if a single quadrant is maximized
            if (dock_state.maximized_quadrant != null) {
                QuadrantId max_id = dock_state.maximized_quadrant;
                bool is_left = (max_id == QuadrantId.Q1_TOP_LEFT || max_id == QuadrantId.Q2_BOTTOM_LEFT);
                bool is_center = (max_id == QuadrantId.Q5_TOP_CENTER || max_id == QuadrantId.Q6_BOTTOM_CENTER);
                bool is_right = (max_id == QuadrantId.Q3_TOP_RIGHT || max_id == QuadrantId.Q4_BOTTOM_RIGHT);

                left_vpaned.visible = is_left;
                right_hpaned.visible = is_center || is_right;
                center_vpaned.visible = is_center;
                right_vpaned.visible = is_right;
                center_crosshair.visible = false;
                right_crosshair.visible = false;

                foreach (var qid in QuadrantId.all ()) {
                    var qw = quadrant_widgets.get (qid);
                    if (qw != null) {
                        qw.visible = (qid == max_id);
                        if (qid == max_id) {
                            qw.sync_from_state ();
                        }
                    }
                }
                return;
            }

            // Normal Workbench view (check topology)
            left_vpaned.visible = true;
            right_hpaned.visible = true;
            right_vpaned.visible = true;

            if (dock_state.topology == LayoutTopology.QUAD_6_ULTRAWIDE) {
                center_vpaned.visible = true;
                center_crosshair.visible = true;
                right_crosshair.visible = true;
                foreach (var qid in QuadrantId.all ()) {
                    var qw = quadrant_widgets.get (qid);
                    if (qw != null) {
                        qw.visible = true;
                        qw.sync_from_state ();
                    }
                }
            } else if (dock_state.topology == LayoutTopology.LEFT_TALL_3) {
                center_vpaned.visible = false;
                center_crosshair.visible = false;
                right_crosshair.visible = false;
                foreach (var qid in QuadrantId.all ()) {
                    var qw = quadrant_widgets.get (qid);
                    if (qw != null) {
                        bool show = (qid == QuadrantId.Q1_TOP_LEFT || qid == QuadrantId.Q3_TOP_RIGHT || qid == QuadrantId.Q4_BOTTOM_RIGHT);
                        qw.visible = show;
                        if (show) qw.sync_from_state ();
                    }
                }
            } else if (dock_state.topology == LayoutTopology.RIGHT_TALL_3) {
                center_vpaned.visible = false;
                center_crosshair.visible = false;
                right_crosshair.visible = false;
                foreach (var qid in QuadrantId.all ()) {
                    var qw = quadrant_widgets.get (qid);
                    if (qw != null) {
                        bool show = (qid == QuadrantId.Q1_TOP_LEFT || qid == QuadrantId.Q2_BOTTOM_LEFT || qid == QuadrantId.Q4_BOTTOM_RIGHT);
                        qw.visible = show;
                        if (show) qw.sync_from_state ();
                    }
                }
            } else {
                center_vpaned.visible = false;
                center_crosshair.visible = true;
                right_crosshair.visible = false;
                foreach (var qid in QuadrantId.all ()) {
                    var qw = quadrant_widgets.get (qid);
                    if (qw != null) {
                        bool show = (qid != QuadrantId.Q5_TOP_CENTER && qid != QuadrantId.Q6_BOTTOM_CENTER);
                        qw.visible = show;
                        if (show) qw.sync_from_state ();
                    }
                }
            }

            apply_splitter_ratios ();
        }
    }
}
