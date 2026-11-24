// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Core.Layout;

namespace Imladris.UI {

    public class MonitorSummary : GLib.Object {
        public int index { get; construct set; }
        public string label { get; construct set; }
        public int width { get; construct set; }
        public int height { get; construct set; }
        public double aspect_ratio { get; construct set; }
        public bool is_ultrawide { get; construct set; }

        public MonitorSummary (int idx, string lbl, int w, int h) {
            double ratio = (h > 0) ? ((double) w / (double) h) : 1.77;
            Object (
                index: idx,
                label: lbl,
                width: w,
                height: h,
                aspect_ratio: ratio,
                is_ultrawide: ratio >= 2.05
            );
        }
    }

    /**
     * WorkspaceDockManager
     * Controls independent multi-screen detachable top-level windows, quadrant moves/swaps,
     * monitor assignment, and topology layout restructuring.
     */
    public class WorkspaceDockManager : GLib.Object {

        private unowned RStudioDockLayoutState dock_state;
        private unowned PersistentPanelRegistry registry;
        private unowned Window? main_window;

        private Gee.HashMap<PanelId, Adw.Window> undocked_windows;
        private Gee.HashMap<PanelId, ulong> theme_handlers;
        private bool closing_internally = false;

        public signal void panel_dock_changed ();

        public WorkspaceDockManager (RStudioDockLayoutState state, PersistentPanelRegistry reg, Window? win) {
            this.dock_state = state;
            this.registry = reg;
            this.main_window = win;
            this.undocked_windows = new Gee.HashMap<PanelId, Adw.Window> ();
            this.theme_handlers = new Gee.HashMap<PanelId, ulong> ();
        }

        /**
         * Enumerates connected displays via Gdk.Display.get_monitors() so users
         * with 2-3 screens or 21:9 / 34:9 ultrawides can inspect and target monitors.
         */
        public static Gee.ArrayList<MonitorSummary> get_connected_monitors () {
            var list = new Gee.ArrayList<MonitorSummary> ();
            var display = Gdk.Display.get_default ();
            if (display == null) return list;

            var monitors = display.get_monitors ();
            uint n = monitors.get_n_items ();
            for (uint i = 0; i < n; i++) {
                var mon = monitors.get_item (i) as Gdk.Monitor;
                if (mon == null) continue;
                var geom = mon.get_geometry ();
                string conn = mon.get_connector () ?? @"Screen $(i + 1)";
                string model = mon.get_model () ?? "";
                string ratio_tag = "";
                if (geom.height > 0) {
                    double r = (double) geom.width / (double) geom.height;
                    if (r >= 3.2) ratio_tag = " (32:9 / 34:9 Ultrawide)";
                    else if (r >= 2.05) ratio_tag = " (21:9 Ultrawide)";
                }
                string name = model.length > 0
                    ? @"Monitor $(i + 1): $model [$conn] $(geom.width)×$(geom.height)$ratio_tag"
                    : @"Monitor $(i + 1): $conn $(geom.width)×$(geom.height)$ratio_tag";
                list.add (new MonitorSummary ((int) i, name, geom.width, geom.height));
            }
            return list;
        }

        public static bool has_ultrawide_monitor (out MonitorSummary? ultrawide) {
            ultrawide = null;
            var mons = get_connected_monitors ();
            foreach (var m in mons) {
                if (m.is_ultrawide) {
                    ultrawide = m;
                    return true;
                }
            }
            return false;
        }

        private static void detach_widget (Gtk.Widget widget) {
            var parent = widget.get_parent ();
            if (parent == null) return;
            var pbox = parent as Gtk.Box;
            if (pbox != null) {
                pbox.remove (widget);
            } else if (parent is Adw.ToolbarView) {
                ((Adw.ToolbarView) parent).set_content (null);
            } else if (parent is Adw.Bin) {
                ((Adw.Bin) parent).set_child (null);
            } else {
                widget.unparent ();
            }
        }

        private void apply_window_theme (Adw.Window win) {
            var theme = Core.SettingsManager.get_default ().app_theme;
            if (theme == Core.AppTheme.EYE_FRIENDLY) {
                win.add_css_class ("eye-friendly");
            } else {
                win.remove_css_class ("eye-friendly");
            }
        }

        /**
         * Undocks a persistent panel into an independent top-level Adw.Window
         * (NOT transient_for the main window) so the OS window manager allows
         * freely moving, tiling, maximizing, or fullscreening it across 2 or 3 monitors.
         */
        public void undock_panel (PanelId pid) {
            if (undocked_windows.has_key (pid)) {
                var existing = undocked_windows.get (pid);
                existing.present ();
                return;
            }

            var widget = registry.get_panel_widget (pid);
            if (widget == null) return;

            detach_widget (widget);

            var geom = dock_state.get_floating_geometry (pid);
            var win = new Adw.Window () {
                title = @"$(pid.to_title ()) — Imladris",
                default_width = geom.width,
                default_height = geom.height,
                resizable = true
            };

            // Register with Gtk.Application as a first-class independent top-level window
            // (intentionally NOT calling set_transient_for so multi-monitor WM placement works freely).
            if (main_window != null && main_window.application != null) {
                win.application = main_window.application;
            }

            apply_window_theme (win);
            unowned Adw.Window win_ref = win;
            ulong th_id = Core.SettingsManager.get_default ().theme_changed.connect ((t) => {
                apply_window_theme (win_ref);
            });
            theme_handlers.set (pid, th_id);

            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar () {
                show_start_title_buttons = true,
                show_end_title_buttons = true
            };

            var title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                valign = Gtk.Align.CENTER
            };
            title_box.append (new Gtk.Image.from_icon_name (pid.to_icon_name ()) { pixel_size = 16 });
            title_box.append (new Gtk.Label (pid.to_title ()) { css_classes = { "heading" } });
            header.title_widget = title_box;

            // Monitor placement popover for 2-3 screen setups
            var monitors = get_connected_monitors ();
            if (monitors.size > 1) {
                var btn_screen = new Gtk.MenuButton () {
                    icon_name = "computer-symbolic",
                    tooltip_text = "Send to Display / Fullscreen on Monitor"
                };
                btn_screen.add_css_class ("flat");

                var mon_pop = new Gtk.Popover ();
                var mon_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                    margin_start = 8, margin_end = 8, margin_top = 8, margin_bottom = 8
                };
                mon_box.append (new Gtk.Label ("Multi-Screen Placement") {
                    css_classes = { "dim-label", "caption" },
                    xalign = 0
                });

                var display = Gdk.Display.get_default ();
                var gdk_mons = display != null ? display.get_monitors () : null;
                foreach (var ms in monitors) {
                    int m_idx = ms.index;
                    var b_mon = new Gtk.Button.with_label (@"Fullscreen on $(ms.label)") {
                        halign = Gtk.Align.START
                    };
                    b_mon.add_css_class ("flat");
                    b_mon.clicked.connect (() => {
                        mon_pop.popdown ();
                        if (gdk_mons != null && m_idx < (int) gdk_mons.get_n_items ()) {
                            var target_mon = gdk_mons.get_item ((uint) m_idx) as Gdk.Monitor;
                            if (target_mon != null) {
                                win_ref.fullscreen_on_monitor (target_mon);
                                dock_state.set_floating_geometry (pid, win_ref.get_width (), win_ref.get_height (), m_idx);
                                dock_state.save_to_disk ();
                            }
                        }
                    });
                    mon_box.append (b_mon);
                }

                mon_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                var b_unfull = new Gtk.Button.with_label ("Exit Fullscreen / Restore Window") {
                    halign = Gtk.Align.START
                };
                b_unfull.add_css_class ("flat");
                b_unfull.clicked.connect (() => {
                    mon_pop.popdown ();
                    win_ref.unfullscreen ();
                });
                mon_box.append (b_unfull);

                mon_pop.set_child (mon_box);
                btn_screen.set_popover (mon_pop);
                header.pack_start (btn_screen);
            }

            // Re-dock to specific quadrant dropdown
            var btn_dock_to = new Gtk.MenuButton () {
                icon_name = "view-grid-symbolic",
                tooltip_text = "Re-dock into Specific Quadrant"
            };
            btn_dock_to.add_css_class ("flat");

            var dock_pop = new Gtk.Popover ();
            var dock_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_start = 8, margin_end = 8, margin_top = 8, margin_bottom = 8
            };
            dock_box.append (new Gtk.Label ("Dock Panel Into Quadrant:") {
                css_classes = { "dim-label", "caption" },
                xalign = 0
            });
            foreach (var qid in QuadrantId.active_for_topology (dock_state.topology)) {
                var target_q = qid;
                var qb = new Gtk.Button.with_label (target_q.to_display_name ()) {
                    halign = Gtk.Align.START
                };
                qb.add_css_class ("flat");
                qb.clicked.connect (() => {
                    dock_pop.popdown ();
                    redock_panel_to (pid, target_q);
                });
                dock_box.append (qb);
            }
            dock_pop.set_child (dock_box);
            btn_dock_to.set_popover (dock_pop);
            header.pack_end (btn_dock_to);

            // Quick 1-click "Re-dock" button
            var btn_redock = new Gtk.Button () {
                tooltip_text = "Re-dock into Main Window"
            };
            btn_redock.add_css_class ("flat");
            var rd_content = new Adw.ButtonContent () {
                icon_name = "view-restore-symbolic",
                label = "Re-dock"
            };
            btn_redock.set_child (rd_content);
            btn_redock.clicked.connect (() => {
                redock_panel (pid);
            });
            header.pack_end (btn_redock);

            toolbar_view.add_top_bar (header);
            widget.hexpand = true;
            widget.vexpand = true;
            widget.visible = true;
            toolbar_view.set_content (widget);
            win.set_content (toolbar_view);

            win.notify["default-width"].connect (() => {
                if (win_ref.default_width > 0 && win_ref.default_height > 0) {
                    dock_state.set_floating_geometry (pid, win_ref.default_width, win_ref.default_height);
                }
            });
            win.notify["default-height"].connect (() => {
                if (win_ref.default_width > 0 && win_ref.default_height > 0) {
                    dock_state.set_floating_geometry (pid, win_ref.default_width, win_ref.default_height);
                }
            });

            win.close_request.connect (() => {
                if (closing_internally) return false;
                int w = win_ref.get_width ();
                int h = win_ref.get_height ();
                if (w > 200 && h > 200) {
                    dock_state.set_floating_geometry (pid, w, h);
                }
                redock_panel (pid);
                return true;
            });

            undocked_windows.set (pid, win);
            dock_state.undock_panel (pid);
            win.present ();
            panel_dock_changed ();
        }

        public void focus_undocked_panel (PanelId pid) {
            if (undocked_windows.has_key (pid)) {
                undocked_windows.get (pid).present ();
            }
        }

        private void teardown_floating_window (PanelId pid) {
            if (theme_handlers.has_key (pid)) {
                ulong hid = theme_handlers.get (pid);
                theme_handlers.unset (pid);
                if (hid != 0) {
                    Core.SettingsManager.get_default ().disconnect (hid);
                }
            }
            var win = undocked_windows.get (pid);
            undocked_windows.unset (pid);

            if (win != null) {
                int w = win.get_width ();
                int h = win.get_height ();
                if (w > 200 && h > 200) {
                    dock_state.set_floating_geometry (pid, w, h);
                }
            }

            var widget = registry.get_panel_widget (pid);
            if (widget != null) {
                detach_widget (widget);
            }

            if (win != null) {
                closing_internally = true;
                win.close ();
                win.destroy ();
                closing_internally = false;
            }
        }

        /**
         * Re-docks a popped-out independent window back into its original quadrant.
         */
        public void redock_panel (PanelId pid) {
            if (!undocked_windows.has_key (pid)) {
                dock_state.redock_panel (pid);
                return;
            }

            teardown_floating_window (pid);
            dock_state.redock_panel (pid);
            panel_dock_changed ();
        }

        /**
         * Re-docks a popped-out independent window directly into a chosen quadrant (Q1-Q6).
         */
        public void redock_panel_to (PanelId pid, QuadrantId target_quad) {
            if (undocked_windows.has_key (pid)) {
                teardown_floating_window (pid);
            }
            dock_state.redock_panel_to (pid, target_quad);
            panel_dock_changed ();
        }

        /**
         * Re-docks every popped-out floating window back into the main app window.
         */
        public void redock_all_panels () {
            var keys = new Gee.ArrayList<PanelId> ();
            foreach (var k in undocked_windows.keys) {
                keys.add (k);
            }
            foreach (var pid in keys) {
                redock_panel (pid);
            }
        }

        /**
         * Synchronizes actual floating windows with dock_state.popped_out_panels
         * (e.g., after loading a multi-screen layout preset).
         */
        public void sync_windows_with_state () {
            var to_close = new Gee.ArrayList<PanelId> ();
            foreach (var k in undocked_windows.keys) {
                if (!dock_state.popped_out_panels.contains (k)) {
                    to_close.add (k);
                }
            }
            foreach (var pid in to_close) {
                teardown_floating_window (pid);
            }

            var to_open = new Gee.ArrayList<PanelId> ();
            foreach (var pid in dock_state.popped_out_panels) {
                if (!undocked_windows.has_key (pid)) {
                    to_open.add (pid);
                }
            }
            foreach (var pid in to_open) {
                undock_panel (pid);
            }
        }

        /**
         * Closes and destroys all floating undocked windows when the owning document tab closes.
         */
        public void close_all_undocked () {
            var keys = new Gee.ArrayList<PanelId> ();
            foreach (var k in undocked_windows.keys) {
                keys.add (k);
            }
            foreach (var pid in keys) {
                teardown_floating_window (pid);
            }
        }

        public bool is_panel_undocked (PanelId pid) {
            return undocked_windows.has_key (pid);
        }

        public Gee.ArrayList<PanelId> list_undocked_panels () {
            var res = new Gee.ArrayList<PanelId> ();
            foreach (var k in undocked_windows.keys) {
                res.add (k);
            }
            return res;
        }

        /**
         * Creates a Popover menu for moving a panel to any active quadrant (4 or 6).
         */
        public Gtk.PopoverMenu create_move_panel_menu (QuadrantId current_quad, PanelId pid) {
            var menu = new GLib.Menu ();
            var group = new GLib.SimpleActionGroup ();

            var section = new GLib.Menu ();
            int idx = 0;
            foreach (var qid in QuadrantId.active_for_topology (dock_state.topology)) {
                if (qid == current_quad) continue;
                var target = qid;
                string act_name = @"move_q_$idx";
                var act = new GLib.SimpleAction (act_name, null);
                act.activate.connect (() => { dock_state.move_tab (current_quad, target, pid); });
                group.add_action (act);
                section.append (@"Move to $(target.to_display_name ())", @"dock.$act_name");
                idx++;
            }
            menu.append_section ("Move Panel To Quadrant", section);

            var popover = new Gtk.PopoverMenu.from_model (menu);
            popover.insert_action_group ("dock", group);
            return popover;
        }
    }
}
