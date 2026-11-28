// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Json;
using Imladris.Core.Layout;

namespace Imladris.UI {

    /**
     * LayoutSerializer
     * Handles saving, loading, and managing custom dock layout presets
     * in ~/.config/imladris/layouts/<name>.json.
     * Supports 4-quadrant, 3-pane tall, 6-quadrant ultrawide (21:9 / 34:9),
     * and multi-screen popped-out independent window presets.
     */
    public class LayoutSerializer : GLib.Object {

        public static string get_layouts_dir () {
            string dir = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "imladris", "layouts");
            GLib.DirUtils.create_with_parents (dir, 0755);
            return dir;
        }

        public static string[] list_saved_layouts () {
            var list = new Gee.ArrayList<string> ();
            string dir = get_layouts_dir ();
            try {
                var d = GLib.Dir.open (dir, 0);
                string? name = null;
                while ((name = d.read_name ()) != null) {
                    if (name.has_suffix (".json")) {
                        list.add (name.substring (0, name.length - 5));
                    }
                }
            } catch (GLib.Error e) {
                // Directory might be empty
            }
            list.sort ((a, b) => strcmp (a, b));
            return list.to_array ();
        }

        public static void delete_layout (string name) {
            string sanitized = name.strip ().replace ("/", "_").replace ("\\", "_");
            if (sanitized.length == 0) return;
            string file_path = GLib.Path.build_filename (get_layouts_dir (), sanitized + ".json");
            if (GLib.FileUtils.test (file_path, GLib.FileTest.EXISTS)) {
                GLib.FileUtils.unlink (file_path);
            }
        }

        public static void save_layout (string name, RStudioDockLayoutState state) throws GLib.Error {
            string sanitized = name.strip ().replace ("/", "_").replace ("\\", "_");
            if (sanitized.length == 0) sanitized = "custom-layout";

            string file_path = GLib.Path.build_filename (get_layouts_dir (), sanitized + ".json");

            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("name");
            builder.add_string_value (sanitized);
            builder.set_member_name ("topology");
            builder.add_string_value (state.topology.to_id_string ());

            builder.set_member_name ("ratios");
            builder.begin_object ();
            builder.set_member_name ("mainVertical");
            builder.add_double_value (state.ratios.main_vertical);
            builder.set_member_name ("leftHorizontal");
            builder.add_double_value (state.ratios.left_horizontal);
            builder.set_member_name ("rightHorizontal");
            builder.add_double_value (state.ratios.right_horizontal);
            builder.set_member_name ("centerVertical");
            builder.add_double_value (state.ratios.center_vertical);
            builder.set_member_name ("centerHorizontal");
            builder.add_double_value (state.ratios.center_horizontal);
            builder.end_object ();

            builder.set_member_name ("poppedOutPanels");
            builder.begin_array ();
            foreach (var pid in state.popped_out_panels) {
                builder.add_string_value (pid.to_id_string ());
            }
            builder.end_array ();

            builder.set_member_name ("floatingGeometries");
            builder.begin_object ();
            foreach (var entry in state.floating_geometries.entries) {
                builder.set_member_name (entry.key.to_id_string ());
                builder.begin_object ();
                builder.set_member_name ("width");
                builder.add_int_value (entry.value.width);
                builder.set_member_name ("height");
                builder.add_int_value (entry.value.height);
                builder.set_member_name ("monitorIndex");
                builder.add_int_value (entry.value.monitor_index);
                builder.end_object ();
            }
            builder.end_object ();

            builder.set_member_name ("quadrants");
            builder.begin_object ();
            foreach (var qid in QuadrantId.all ()) {
                var qc = state.quadrants.get (qid);
                if (qc == null) continue;
                builder.set_member_name (qid.to_id_string ());
                builder.begin_object ();
                builder.set_member_name ("sizeState");
                builder.add_string_value (qc.size_state.to_id_string ());
                builder.set_member_name ("activeTab");
                if (qc.active_tab != null) {
                    builder.add_string_value (qc.active_tab.to_id_string ());
                } else {
                    builder.add_null_value ();
                }
                builder.set_member_name ("tabs");
                builder.begin_array ();
                foreach (var p in qc.tabs) {
                    builder.add_string_value (p.to_id_string ());
                }
                builder.end_array ();
                builder.end_object ();
            }
            builder.end_object ();
            builder.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (builder.get_root ());
            gen.pretty = true;
            string json_str = gen.to_data (null);
            GLib.FileUtils.set_contents (file_path, json_str);
        }

        public static bool load_layout (string name, RStudioDockLayoutState state) {
            string file_path = GLib.Path.build_filename (get_layouts_dir (), name + ".json");
            if (!GLib.FileUtils.test (file_path, GLib.FileTest.EXISTS)) return false;

            try {
                string contents;
                GLib.FileUtils.get_contents (file_path, out contents);
                var parser = new Json.Parser ();
                parser.load_from_data (contents, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return false;
                var obj = root.get_object ();

                if (obj.has_member ("topology") && obj.get_member ("topology").get_node_type () == Json.NodeType.VALUE) {
                    state.topology = LayoutTopology.from_id_string (obj.get_string_member ("topology") ?? "rstudio-default");
                }

                if (obj.has_member ("ratios") && obj.get_member ("ratios").get_node_type () == Json.NodeType.OBJECT) {
                    var r_obj = obj.get_object_member ("ratios");
                    double mv = (r_obj.has_member ("mainVertical") && r_obj.get_member ("mainVertical").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("mainVertical") : 0.55;
                    double lh = (r_obj.has_member ("leftHorizontal") && r_obj.get_member ("leftHorizontal").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("leftHorizontal") : 0.68;
                    double rh = (r_obj.has_member ("rightHorizontal") && r_obj.get_member ("rightHorizontal").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("rightHorizontal") : 0.45;
                    double cv = (r_obj.has_member ("centerVertical") && r_obj.get_member ("centerVertical").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("centerVertical") : 0.50;
                    double ch = (r_obj.has_member ("centerHorizontal") && r_obj.get_member ("centerHorizontal").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("centerHorizontal") : 0.55;
                    state.ratios.set_clamped_all (mv, lh, rh, cv, ch);
                }

                state.popped_out_panels.clear ();
                if (obj.has_member ("poppedOutPanels") && obj.get_member ("poppedOutPanels").get_node_type () == Json.NodeType.ARRAY) {
                    var p_arr = obj.get_array_member ("poppedOutPanels");
                    for (uint i = 0; i < p_arr.get_length (); i++) {
                        var el = p_arr.get_element (i);
                        if (el == null || el.get_node_type () != Json.NodeType.VALUE) continue;
                        PanelId? pid = PanelId.from_id_string (el.get_string () ?? "");
                        if (pid != null) {
                            state.popped_out_panels.add (pid);
                        }
                    }
                }

                state.floating_geometries.clear ();
                if (obj.has_member ("floatingGeometries") && obj.get_member ("floatingGeometries").get_node_type () == Json.NodeType.OBJECT) {
                    var fg_obj = obj.get_object_member ("floatingGeometries");
                    foreach (var key in fg_obj.get_members ()) {
                        PanelId? pid = PanelId.from_id_string (key);
                        if (pid == null) continue;
                        if (fg_obj.get_member (key).get_node_type () != Json.NodeType.OBJECT) continue;
                        var g_item = fg_obj.get_object_member (key);
                        int w = (g_item.has_member ("width") && g_item.get_member ("width").get_node_type () == Json.NodeType.VALUE) ? (int) g_item.get_int_member ("width") : 840;
                        int h = (g_item.has_member ("height") && g_item.get_member ("height").get_node_type () == Json.NodeType.VALUE) ? (int) g_item.get_int_member ("height") : 600;
                        int m = (g_item.has_member ("monitorIndex") && g_item.get_member ("monitorIndex").get_node_type () == Json.NodeType.VALUE) ? (int) g_item.get_int_member ("monitorIndex") : -1;
                        state.floating_geometries.set (pid, new FloatingWindowGeometry (w, h, m));
                    }
                }

                if (obj.has_member ("quadrants") && obj.get_member ("quadrants").get_node_type () == Json.NodeType.OBJECT) {
                    var q_obj = obj.get_object_member ("quadrants");
                    foreach (var qid in QuadrantId.all ()) {
                        string qkey = qid.to_id_string ();
                        if (!q_obj.has_member (qkey) || q_obj.get_member (qkey).get_node_type () != Json.NodeType.OBJECT) continue;
                        var q_item = q_obj.get_object_member (qkey);
                        var qc = state.quadrants.get (qid);
                        if (qc == null) continue;

                        if (q_item.has_member ("sizeState") && q_item.get_member ("sizeState").get_node_type () == Json.NodeType.VALUE) {
                            qc.size_state = QuadrantSizeState.from_id_string (q_item.get_string_member ("sizeState") ?? "normal");
                        }

                        if (q_item.has_member ("tabs") && q_item.get_member ("tabs").get_node_type () == Json.NodeType.ARRAY) {
                            qc.tabs.clear ();
                            var t_arr = q_item.get_array_member ("tabs");
                            for (uint i = 0; i < t_arr.get_length (); i++) {
                                var el = t_arr.get_element (i);
                                if (el == null || el.get_node_type () != Json.NodeType.VALUE) continue;
                                PanelId? pid = PanelId.from_id_string (el.get_string () ?? "");
                                if (pid != null) {
                                    qc.tabs.add (pid);
                                }
                            }
                        }

                        if (q_item.has_member ("activeTab") && !q_item.get_null_member ("activeTab") &&
                            q_item.get_member ("activeTab").get_node_type () == Json.NodeType.VALUE) {
                            qc.active_tab = PanelId.from_id_string (q_item.get_string_member ("activeTab"));
                        } else if (qc.tabs.size > 0) {
                            qc.active_tab = qc.tabs.get (0);
                        } else {
                            qc.active_tab = null;
                        }
                    }
                }

                state.ensure_panel_present (PanelId.WEB_SYNC, QuadrantId.Q3_TOP_RIGHT);
                state.ensure_panel_present (PanelId.QUALITATIVE, QuadrantId.Q3_TOP_RIGHT);
                state.save_to_disk ();
                state.state_updated ();
                return true;
            } catch (GLib.Error e) {
                warning ("Failed to load dock layout '%s': %s", name, e.message);
                return false;
            }
        }

        private static void migrate_center_quadrants_to_quad4 (RStudioDockLayoutState state) {
            var q5 = state.quadrants.get (QuadrantId.Q5_TOP_CENTER);
            var q6 = state.quadrants.get (QuadrantId.Q6_BOTTOM_CENTER);
            var q2 = state.quadrants.get (QuadrantId.Q2_BOTTOM_LEFT);
            var q4 = state.quadrants.get (QuadrantId.Q4_BOTTOM_RIGHT);

            if (q5 != null && q4 != null) {
                var moved = new Gee.ArrayList<PanelId> ();
                foreach (var pid in q5.tabs) moved.add (pid);
                foreach (var pid in moved) {
                    q5.tabs.remove (pid);
                    if (!q4.tabs.contains (pid)) {
                        q4.tabs.add (pid);
                    }
                }
                q5.active_tab = null;
                q5.size_state = QuadrantSizeState.MINIMIZED;
            }

            if (q6 != null && q2 != null && q4 != null) {
                var moved = new Gee.ArrayList<PanelId> ();
                foreach (var pid in q6.tabs) moved.add (pid);
                foreach (var pid in moved) {
                    q6.tabs.remove (pid);
                    var dest = (pid == PanelId.ELROND_AI || pid == PanelId.CONSOLE || pid == PanelId.TERMINAL) ? q2 : q4;
                    if (!dest.tabs.contains (pid)) {
                        dest.tabs.add (pid);
                    }
                }
                q6.active_tab = null;
                q6.size_state = QuadrantSizeState.MINIMIZED;
            }
        }

        public static void apply_topology_preset (LayoutTopology topo, RStudioDockLayoutState state) {
            state.topology = topo;
            state.maximized_quadrant = null;

            switch (topo) {
                case LayoutTopology.QUAD_6_ULTRAWIDE:
                    var q5 = state.quadrants.get (QuadrantId.Q5_TOP_CENTER);
                    var q6 = state.quadrants.get (QuadrantId.Q6_BOTTOM_CENTER);
                    bool center_empty = (q5 == null || q5.tabs.size == 0) && (q6 == null || q6.tabs.size == 0);
                    if (center_empty) {
                        state.apply_ultrawide_6_defaults ();
                        return;
                    }
                    state.ratios.set_clamped_all (0.36, 0.65, 0.48, 0.52, 0.58);
                    foreach (var qid in QuadrantId.all ()) {
                        var q = state.quadrants.get (qid);
                        if (q != null) {
                            q.size_state = (q.tabs.size > 0) ? QuadrantSizeState.NORMAL : QuadrantSizeState.MINIMIZED;
                            if (q.active_tab == null && q.tabs.size > 0) {
                                q.active_tab = q.tabs.get (0);
                            }
                        }
                    }
                    break;

                case LayoutTopology.LEFT_TALL_3:
                    migrate_center_quadrants_to_quad4 (state);
                    // Q1 tall on left (migrate Q2 tabs into Q1 so Console/Terminal stay accessible)
                    state.ratios.set_clamped (0.60, 0.70, 0.50);
                    var q1 = state.quadrants.get (QuadrantId.Q1_TOP_LEFT);
                    var q2 = state.quadrants.get (QuadrantId.Q2_BOTTOM_LEFT);
                    if (q1 != null && q2 != null) {
                        foreach (var pid in q2.tabs) {
                            if (!q1.tabs.contains (pid)) {
                                q1.tabs.add (pid);
                            }
                        }
                        q2.size_state = QuadrantSizeState.MINIMIZED;
                        q1.size_state = QuadrantSizeState.NORMAL;
                    }
                    break;

                case LayoutTopology.RIGHT_TALL_3:
                    migrate_center_quadrants_to_quad4 (state);
                    // Q1 and Q2 stacked on left, Q4 tall on right (migrate Q3 tabs into Q4)
                    state.ratios.set_clamped (0.45, 0.50, 0.70);
                    var q3 = state.quadrants.get (QuadrantId.Q3_TOP_RIGHT);
                    var q4 = state.quadrants.get (QuadrantId.Q4_BOTTOM_RIGHT);
                    if (q3 != null && q4 != null) {
                        foreach (var pid in q3.tabs) {
                            if (!q4.tabs.contains (pid)) {
                                q4.tabs.add (pid);
                            }
                        }
                        q3.size_state = QuadrantSizeState.MINIMIZED;
                        q4.size_state = QuadrantSizeState.NORMAL;
                    }
                    break;

                case LayoutTopology.QUAD_4:
                default:
                    migrate_center_quadrants_to_quad4 (state);
                    state.ratios.set_clamped (0.55, 0.68, 0.45);
                    var q1_rest = state.quadrants.get (QuadrantId.Q1_TOP_LEFT);
                    var q2_rest = state.quadrants.get (QuadrantId.Q2_BOTTOM_LEFT);
                    var q3_rest = state.quadrants.get (QuadrantId.Q3_TOP_RIGHT);
                    var q4_rest = state.quadrants.get (QuadrantId.Q4_BOTTOM_RIGHT);
                    if (q1_rest != null && q2_rest != null) {
                        foreach (var pid in q2_rest.tabs) {
                            if (pid != PanelId.SOURCE_EDITOR) q1_rest.tabs.remove (pid);
                        }
                    }
                    if (q3_rest != null && q4_rest != null) {
                        foreach (var pid in q3_rest.tabs) {
                            q4_rest.tabs.remove (pid);
                        }
                    }
                    QuadrantId[] q4_ids = {
                        QuadrantId.Q1_TOP_LEFT,
                        QuadrantId.Q2_BOTTOM_LEFT,
                        QuadrantId.Q3_TOP_RIGHT,
                        QuadrantId.Q4_BOTTOM_RIGHT
                    };
                    foreach (var qid in q4_ids) {
                        var q = state.quadrants.get (qid);
                        if (q != null) {
                            q.size_state = QuadrantSizeState.NORMAL;
                            if (q.active_tab == null && q.tabs.size > 0) {
                                q.active_tab = q.tabs.get (0);
                            }
                        }
                    }
                    break;
            }

            state.save_to_disk ();
            state.state_updated ();
        }
    }
}
