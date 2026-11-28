// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Qual;
using Imladris.Bridges.Cytoscape;

namespace Imladris.UI.Qual {

    /**
     * Native GTK4 / Cairo Qualitative Graph View + Bidirectional Cytoscape Bridge Controls.
     * Supports interactive click-to-filter selection, pan/zoom, Force-Directed / Hierarchical
     * layout switching, CX2 / GraphML offline exchange, and live CyREST push/pull/SVG import.
     */
    public class QualGraphView : Gtk.Box {
        private QualWorkspaceService service;
        private unowned Window? parent_window;
        private QualGraph graph;
        private GraphLayoutMode layout_mode = GraphLayoutMode.FORCE_DIRECTED;
        private Gtk.DrawingArea canvas;
        private Gtk.Label status_lbl;
        private double zoom = 1.0;
        private double pan_x = 0.0;
        private double pan_y = 0.0;
        private double drag_start_x = 0.0;
        private double drag_start_y = 0.0;
        private bool showing_imported_graph = false;

        public signal void insert_figure_requested (string quarto_snippet);

        public QualGraphView (QualWorkspaceService svc, Window? win = null) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.service = svc;
            this.parent_window = win;
            this.hexpand = true;
            this.vexpand = true;
            this.graph = new QualGraph ();

            build_ui ();
            rebuild_graph ();
        }

        private void build_ui () {
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            bar.add_css_class ("dock-subtoolbar");

            var layout_dd = new Gtk.DropDown (new Gtk.StringList ({ "Force-Directed", "Hierarchical" }), null) {
                selected = 0,
                tooltip_text = "Choose network layout algorithm"
            };
            layout_dd.notify["selected"].connect (() => {
                layout_mode = (layout_dd.selected == 1) ? GraphLayoutMode.HIERARCHICAL : GraphLayoutMode.FORCE_DIRECTED;
                NetworkBuilder.apply_layout (graph, layout_mode);
                canvas.queue_draw ();
            });
            bar.append (layout_dd);

            var btn_push = new Gtk.Button.with_label ("Push to Cytoscape") {
                tooltip_text = "Push CX2 network + Nord Visual Style to Cytoscape Desktop (localhost:1234)"
            };
            btn_push.add_css_class ("flat");
            btn_push.clicked.connect (() => push_to_cytoscape_async.begin ());
            bar.append (btn_push);

            var btn_pull = new Gtk.Button.with_label ("Pull Selection") {
                tooltip_text = "Sync selected nodes from Cytoscape Desktop to filter Evidence Matrix"
            };
            btn_pull.add_css_class ("flat");
            btn_pull.clicked.connect (() => pull_selection_async.begin ());
            bar.append (btn_pull);

            var btn_snap = new Gtk.Button.with_label ("Insert SVG Figure") {
                tooltip_text = "Import network SVG snapshot (via CyREST if live, or native vector renderer) into document"
            };
            btn_snap.add_css_class ("flat");
            btn_snap.clicked.connect (() => insert_svg_figure_async.begin ());
            bar.append (btn_snap);

            var btn_export = new Gtk.Button.with_label ("Export CX2/GraphML") {
                tooltip_text = "Save lossless CX2 (.cx2) or GraphML (.graphml) file"
            };
            btn_export.add_css_class ("flat");
            btn_export.clicked.connect (prompt_export_network);
            bar.append (btn_export);

            var btn_import = new Gtk.Button.with_label ("Import") {
                tooltip_text = "Load CX2 (.cx2) or GraphML (.graphml) network"
            };
            btn_import.add_css_class ("flat");
            btn_import.clicked.connect (prompt_import_network);
            bar.append (btn_import);

            bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            status_lbl = new Gtk.Label ("0 nodes") {
                css_classes = { "caption", "numeric", "dim-label" }
            };
            bar.append (status_lbl);
            this.append (bar);

            canvas = new Gtk.DrawingArea () {
                hexpand = true,
                vexpand = true,
                content_width = 480,
                content_height = 320
            };
            canvas.set_draw_func (draw_network);

            var click_ctrl = new Gtk.GestureClick ();
            click_ctrl.pressed.connect ((n_press, x, y) => {
                handle_canvas_click (x, y);
            });
            canvas.add_controller (click_ctrl);

            var drag_ctrl = new Gtk.GestureDrag ();
            drag_ctrl.drag_begin.connect ((sx, sy) => {
                drag_start_x = pan_x;
                drag_start_y = pan_y;
            });
            drag_ctrl.drag_update.connect ((ox, oy) => {
                pan_x = drag_start_x + ox;
                pan_y = drag_start_y + oy;
                canvas.queue_draw ();
            });
            canvas.add_controller (drag_ctrl);

            var scroll_ctrl = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
            scroll_ctrl.scroll.connect ((dx, dy) => {
                zoom = (zoom * (dy < 0 ? 1.12 : 0.89)).clamp (0.35, 3.5);
                canvas.queue_draw ();
                return true;
            });
            canvas.add_controller (scroll_ctrl);

            this.append (canvas);
        }

        public void set_service (QualWorkspaceService svc) {
            this.service = svc;
            this.showing_imported_graph = false;
            rebuild_graph ();
        }

        public void on_workspace_state_changed () {
            if (showing_imported_graph) {
                canvas.queue_draw ();
            } else {
                rebuild_graph ();
            }
        }

        public void rebuild_graph () {
            showing_imported_graph = false;
            var open_buffers = new Gee.HashMap<string, string> ();
            if (parent_window != null) {
                var doc = parent_window.get_active_document ();
                if (doc != null && doc.file_location != null && doc.file_location.get_path () != null) {
                    open_buffers.set (doc.file_location.get_path (), doc.get_clean_source_text ());
                }
            }
            graph = NetworkBuilder.build_from_workspace (service, layout_mode, open_buffers);
            status_lbl.label = @"$(graph.nodes.size) nodes · $(graph.edges.size) edges";
            canvas.queue_draw ();
        }

        private void handle_canvas_click (double view_x, double view_y) {
            double gx = (view_x - pan_x) / zoom;
            double gy = (view_y - pan_y) / zoom;

            QualGraphNode? hit = null;
            foreach (var n in graph.nodes) {
                double r = (14.0 + GLib.Math.sqrt (n.groundedness) * 4.0).clamp (14.0, 32.0);
                double dx = gx - n.x;
                double dy = gy - n.y;
                if (dx * dx + dy * dy <= (r + 4.0) * (r + 4.0)) {
                    hit = n;
                    break;
                }
            }

            if (hit != null) {
                var sel = new Gee.ArrayList<string> ();
                sel.add (hit.id);
                service.set_graph_node_filter (sel);
            } else if (service.selected_graph_nodes.size > 0) {
                service.set_graph_node_filter (null);
            }
            canvas.queue_draw ();
        }

        private void draw_network (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            bool dark = Adw.StyleManager.get_default ().dark;
            if (dark) cr.set_source_rgb (0.180, 0.204, 0.251); // Nord #2E3440
            else cr.set_source_rgb (0.973, 0.980, 0.988);
            cr.paint ();

            if (graph.nodes.size == 0) {
                cr.set_source_rgba (dark ? 0.85 : 0.28, dark ? 0.87 : 0.33, dark ? 0.91 : 0.41, 0.85);
                cr.set_font_size (12.0);
                cr.move_to (24.0, height / 2.0);
                cr.show_text ("Apply qualitative codes to manuscript excerpts to populate the Entity–Code–Evidence graph.");
                return;
            }

            cr.save ();
            cr.translate (pan_x, pan_y);
            cr.scale (zoom, zoom);

            // Edges
            foreach (var e in graph.edges) {
                var s = graph.node_by_id.get (e.source_id);
                var t = graph.node_by_id.get (e.target_id);
                if (s == null || t == null) continue;
                cr.set_source_rgba (0.506, 0.631, 0.757, 0.55); // Nord #81A1C1
                cr.set_line_width ((1.2 + e.weight * 0.65).clamp (1.2, 5.5));
                cr.move_to (s.x, s.y);
                cr.line_to (t.x, t.y);
                cr.stroke ();
            }

            // Nodes
            foreach (var n in graph.nodes) {
                double r = (14.0 + GLib.Math.sqrt (n.groundedness) * 4.0).clamp (14.0, 32.0);
                Gdk.RGBA col = Gdk.RGBA ();
                if (!col.parse (n.color_hex)) col.parse ("#88C0D0");

                bool is_sel = service.selected_graph_nodes.contains (n.id);
                if (is_sel) {
                    cr.set_source_rgba (0.922, 0.796, 0.545, 0.40);
                    cr.arc (n.x, n.y, r + 6.0, 0, 2 * GLib.Math.PI);
                    cr.fill ();
                }

                cr.set_source_rgba (col.red, col.green, col.blue, 0.94);
                cr.arc (n.x, n.y, r, 0, 2 * GLib.Math.PI);
                cr.fill_preserve ();

                if (n.sdv_verified) {
                    cr.set_source_rgb (dark ? 0.925 : 0.18, dark ? 0.937 : 0.20, dark ? 0.957 : 0.25);
                    cr.set_line_width (2.6);
                } else {
                    cr.set_source_rgb (0.749, 0.380, 0.416); // Nord #BF616A
                    cr.set_line_width (1.5);
                }
                cr.stroke ();

                cr.set_source_rgb (dark ? 0.925 : 0.12, dark ? 0.937 : 0.15, dark ? 0.957 : 0.20);
                cr.set_font_size (11.0);
                Cairo.TextExtents ext;
                cr.text_extents (n.label, out ext);
                cr.move_to (n.x - ext.width / 2.0, n.y + r + 13.0);
                cr.show_text (n.label);
            }

            cr.restore ();
        }

        private async void push_to_cytoscape_async () {
            rebuild_graph ();
            var client = CyRestClient.get_default ();
            string cy_layout = (layout_mode == GraphLayoutMode.HIERARCHICAL) ? "hierarchical" : "force-directed";
            try {
                int64 suid = yield client.push_network_cx2_async (graph, cy_layout);
                if (parent_window != null) {
                    parent_window.show_toast (@"Pushed CX2 network & Nord style to Cytoscape (SUID $suid)");
                }
            } catch (CyRestError e) {
                if (parent_window != null) {
                    parent_window.show_toast (@"Cytoscape Desktop offline on $(client.host):$(client.port) — use Export CX2 for offline sharing");
                }
            }
        }

        private async void pull_selection_async () {
            var client = CyRestClient.get_default ();
            try {
                var selected = yield client.pull_selected_nodes_async ();
                service.set_graph_node_filter (selected);
                if (parent_window != null) {
                    parent_window.show_toast (@"Synced $(selected.size) selected node(s) from Cytoscape");
                }
            } catch (CyRestError e) {
                if (parent_window != null) {
                    parent_window.show_toast (@"Could not pull Cytoscape selection: $(e.message)");
                }
            }
        }

        private async void insert_svg_figure_async () {
            rebuild_graph ();
            string fig_dir = GLib.Path.build_filename (service.workspace_dir, "figures");
            GLib.DirUtils.create_with_parents (fig_dir, 0755);
            string fname = "qual-network-" + new GLib.DateTime.now_utc ().format ("%Y%m%d-%H%M%S") + ".svg";
            string dest = GLib.Path.build_filename (fig_dir, fname);
            string rel = "figures/" + fname;

            var client = CyRestClient.get_default ();
            if (client.is_connected && client.last_network_suid > 0) {
                try {
                    string qmd = yield client.export_figure_to_quarto_async (client.last_network_suid, dest, rel, "svg", graph.name);
                    insert_figure_requested (qmd);
                    return;
                } catch (CyRestError e) {}
            }

            // Native vector SVG fallback when Cytoscape Desktop is not running live
            string svg = NetworkBuilder.export_svg (graph);
            try {
                GLib.FileUtils.set_contents (dest, svg);
                insert_figure_requested (@"\n![$(graph.name)]($rel){#fig-qual-network}\n");
            } catch (GLib.Error e) {
                if (parent_window != null) parent_window.show_toast (@"Failed to write SVG figure: $(e.message)");
            }
        }

        private void prompt_export_network () {
            rebuild_graph ();
            var dlg = new Gtk.FileDialog () {
                title = "Export Qualitative Network (.cx2 or .graphml)",
                initial_name = "qualitative-network.cx2"
            };
            dlg.save.begin (parent_window, null, (o, r) => {
                try {
                    var f = dlg.save.end (r);
                    if (f != null && f.get_path () != null) {
                        string p = f.get_path ();
                        string payload = p.down ().has_suffix (".graphml")
                            ? GraphMlSerializer.serialize (graph)
                            : Cx2Serializer.serialize (graph);
                        GLib.FileUtils.set_contents (p, payload);
                        if (parent_window != null) parent_window.show_toast (@"Exported $(GLib.Path.get_basename (p))");
                    }
                } catch (GLib.Error e) {}
            });
        }

        private void prompt_import_network () {
            var dlg = new Gtk.FileDialog () { title = "Import CX2 or GraphML Network" };
            dlg.open.begin (parent_window, null, (o, r) => {
                try {
                    var f = dlg.open.end (r);
                    if (f != null && f.get_path () != null) {
                        string p = f.get_path ();
                        string raw;
                        GLib.FileUtils.get_contents (p, out raw);
                        graph = p.down ().has_suffix (".graphml")
                            ? GraphMlSerializer.deserialize (raw)
                            : Cx2Serializer.deserialize (raw);
                        showing_imported_graph = true;
                        status_lbl.label = @"$(graph.nodes.size) nodes · $(graph.edges.size) edges (imported)";
                        canvas.queue_draw ();
                        if (parent_window != null) parent_window.show_toast (@"Imported $(graph.nodes.size) nodes from $(GLib.Path.get_basename (p))");
                    }
                } catch (GLib.Error e) {
                    if (parent_window != null) parent_window.show_toast (@"Network import failed: $(e.message)");
                }
            });
        }
    }
}
