// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Imladris.Core.Layout;
using Imladris.UI;

namespace Imladris.Tests {

    public class DockEnvironmentTests : GLib.Object {

        public static void register_tests (bool has_display) {
            Test.add_func ("/dock/panel_id_metadata", test_panel_id_metadata);
            Test.add_func ("/dock/layout_topology_states", test_layout_topology_states);
            Test.add_func ("/dock/ultrawide_6_quadrant_layout", test_ultrawide_6_quadrant_layout);
            Test.add_func ("/dock/quadrant_swap_and_redock_to", test_quadrant_swap_and_redock_to);
            Test.add_func ("/dock/layout_persistence", test_layout_persistence);
            Test.add_func ("/dock/undock_redock_flow", test_undock_redock_flow);
            Test.add_func ("/dock/layout_serializer_presets", test_layout_serializer_presets);
            Test.add_func ("/dock/history_manager", test_history_manager);
            Test.add_func ("/grid/data_row", test_data_row);
            if (has_display) {
                Test.add_func ("/grid/data_viewer_widget", test_data_viewer_widget);
            }
            Test.add_func ("/environment/variable_item_parsing", test_variable_item_parsing);
        }

        private static void test_panel_id_metadata () {
            var p_ai = PanelId.ELROND_AI;
            assert (p_ai.to_id_string () == "elrond-ai");
            assert (p_ai.to_title () == "Elrond AI");
            assert (p_ai.to_icon_name () == "ai-elrond");
            assert (PanelId.from_id_string ("elrond-ai") == PanelId.ELROND_AI);

            var p_grid = PanelId.DATA_VIEWER;
            assert (p_grid.to_id_string () == "data-viewer");
            assert (p_grid.to_title () == "Data Viewer");
            assert (p_grid.to_icon_name () == "view-grid-symbolic");
            assert (PanelId.from_id_string ("data-viewer") == PanelId.DATA_VIEWER);

            var p_hist = PanelId.HISTORY;
            assert (p_hist.to_id_string () == "history");
            assert (p_hist.to_title () == "History");
            assert (p_hist.to_icon_name () == "document-open-recent-symbolic");
            assert (PanelId.from_id_string ("history") == PanelId.HISTORY);

            var p_pkgs = PanelId.PACKAGES;
            assert (p_pkgs.to_id_string () == "packages");
            assert (p_pkgs.to_title () == "Packages");
            assert (p_pkgs.to_icon_name () == "application-x-addon-symbolic");
            assert (PanelId.from_id_string ("packages") == PanelId.PACKAGES);

            var p_web = PanelId.WEB_SYNC;
            assert (p_web.to_id_string () == "web-sync");
            assert (p_web.to_title () == "Imladris Web");
            assert (p_web.to_icon_name () == "network-server-symbolic");
            assert (PanelId.from_id_string ("web-sync") == PanelId.WEB_SYNC);
        }

        private static void test_ultrawide_6_quadrant_layout () {
            assert (LayoutTopology.QUAD_6_ULTRAWIDE.to_id_string () == "QUAD_6_ULTRAWIDE");
            assert (LayoutTopology.from_id_string ("QUAD_6_ULTRAWIDE") == LayoutTopology.QUAD_6_ULTRAWIDE);

            var active6 = QuadrantId.active_for_topology (LayoutTopology.QUAD_6_ULTRAWIDE);
            assert (active6.length == 6);

            var state = new RStudioDockLayoutState ();
            LayoutSerializer.apply_topology_preset (LayoutTopology.QUAD_6_ULTRAWIDE, state);
            assert (state.topology == LayoutTopology.QUAD_6_ULTRAWIDE);

            var q5 = state.quadrants.get (QuadrantId.Q5_TOP_CENTER);
            var q6 = state.quadrants.get (QuadrantId.Q6_BOTTOM_CENTER);
            assert (q5 != null && q5.tabs.contains (PanelId.LIVE_PREVIEW));
            assert (q6 != null && q6.tabs.contains (PanelId.ELROND_AI));

            // Save and reload 6-quadrant layout including center ratios
            state.ratios.set_clamped_all (0.34, 0.62, 0.48, 0.51, 0.59);
            state.save_to_disk ();

            var reloaded = new RStudioDockLayoutState ();
            reloaded.load_from_disk ();
            assert (reloaded.topology == LayoutTopology.QUAD_6_ULTRAWIDE);
            assert (reloaded.quadrants.get (QuadrantId.Q5_TOP_CENTER).tabs.contains (PanelId.LIVE_PREVIEW));
            assert (reloaded.quadrants.get (QuadrantId.Q6_BOTTOM_CENTER).tabs.contains (PanelId.ELROND_AI));

            // Migrate back to 4-quadrant without losing any center panel
            LayoutSerializer.apply_topology_preset (LayoutTopology.QUAD_4, reloaded);
            assert (reloaded.topology == LayoutTopology.QUAD_4);
            assert (reloaded.find_panel_quadrant (PanelId.LIVE_PREVIEW) != null);
            assert (reloaded.find_panel_quadrant (PanelId.ELROND_AI) != null);
            assert (reloaded.find_panel_quadrant (PanelId.LIVE_PREVIEW) != QuadrantId.Q5_TOP_CENTER);
            assert (reloaded.find_panel_quadrant (PanelId.ELROND_AI) != QuadrantId.Q6_BOTTOM_CENTER);

            reloaded.reset_to_default ();
            reloaded.save_to_disk ();
        }

        private static void test_quadrant_swap_and_redock_to () {
            var state = new RStudioDockLayoutState ();
            assert (state.find_panel_quadrant (PanelId.SOURCE_EDITOR) == QuadrantId.Q1_TOP_LEFT);
            assert (state.find_panel_quadrant (PanelId.ENVIRONMENT) == QuadrantId.Q3_TOP_RIGHT);

            // Swap Q1 and Q3
            state.swap_quadrants (QuadrantId.Q1_TOP_LEFT, QuadrantId.Q3_TOP_RIGHT);
            assert (state.find_panel_quadrant (PanelId.SOURCE_EDITOR) == QuadrantId.Q3_TOP_RIGHT);
            assert (state.find_panel_quadrant (PanelId.ENVIRONMENT) == QuadrantId.Q1_TOP_LEFT);

            // Undock panel with geometry and redock directly into Q2
            state.set_floating_geometry (PanelId.PLOTS, 1200, 800, 1);
            state.undock_panel (PanelId.PLOTS);
            assert (state.popped_out_panels.contains (PanelId.PLOTS));
            assert (state.get_floating_geometry (PanelId.PLOTS).width == 1200);
            assert (state.get_floating_geometry (PanelId.PLOTS).monitor_index == 1);

            state.redock_panel_to (PanelId.PLOTS, QuadrantId.Q2_BOTTOM_LEFT);
            assert (!state.popped_out_panels.contains (PanelId.PLOTS));
            assert (state.find_panel_quadrant (PanelId.PLOTS) == QuadrantId.Q2_BOTTOM_LEFT);
            assert (state.quadrants.get (QuadrantId.Q2_BOTTOM_LEFT).active_tab == PanelId.PLOTS);
        }

        private static void test_layout_topology_states () {
            assert (LayoutTopology.QUAD_4.to_id_string () == "QUAD_4");
            assert (LayoutTopology.LEFT_TALL_3.to_id_string () == "LEFT_TALL_3");
            assert (LayoutTopology.RIGHT_TALL_3.to_id_string () == "RIGHT_TALL_3");

            assert (LayoutTopology.from_id_string ("QUAD_4") == LayoutTopology.QUAD_4);
            assert (LayoutTopology.from_id_string ("LEFT_TALL_3") == LayoutTopology.LEFT_TALL_3);
            assert (LayoutTopology.from_id_string ("RIGHT_TALL_3") == LayoutTopology.RIGHT_TALL_3);

            var state = new RStudioDockLayoutState ();
            assert (state.topology == LayoutTopology.QUAD_4);

            var q1 = state.quadrants.get (QuadrantId.Q1_TOP_LEFT);
            assert (q1 != null);
            assert (q1.tabs.contains (PanelId.SOURCE_EDITOR));
            assert (q1.tabs.contains (PanelId.DATA_VIEWER));

            var q2 = state.quadrants.get (QuadrantId.Q2_BOTTOM_LEFT);
            assert (q2 != null);
            assert (q2.tabs.contains (PanelId.CONSOLE));
            assert (q2.tabs.contains (PanelId.TERMINAL));
            assert (q2.tabs.contains (PanelId.ELROND_AI));

            var q3 = state.quadrants.get (QuadrantId.Q3_TOP_RIGHT);
            assert (q3 != null);
            assert (q3.tabs.contains (PanelId.ENVIRONMENT));
            assert (q3.tabs.contains (PanelId.HISTORY));

            var q4 = state.quadrants.get (QuadrantId.Q4_BOTTOM_RIGHT);
            assert (q4 != null);
            assert (q4.tabs.contains (PanelId.FILES));
            assert (q4.tabs.contains (PanelId.PLOTS));
            assert (q4.tabs.contains (PanelId.PACKAGES));
            assert (q4.tabs.contains (PanelId.HELP));
        }

        private static void test_history_manager () {
            var hm = Imladris.Services.HistoryManager.get_default ();
            hm.clear ();
            assert (hm.size == 0);

            hm.add_entry ("x <- 42", "r");
            hm.add_entry ("plot(x)", "r");
            assert (hm.size == 2);

            string? up1 = hm.navigate_up ("");
            assert (up1 == "plot(x)");
            string? up2 = hm.navigate_up ("");
            assert (up2 == "x <- 42");

            string? down1 = hm.navigate_down ();
            assert (down1 == "plot(x)");
            string? down2 = hm.navigate_down ();
            assert (down2 == "");

            hm.clear ();
            assert (hm.size == 0);
        }

        private static void test_layout_persistence () {
            var state = new RStudioDockLayoutState ();
            state.switch_topology (LayoutTopology.LEFT_TALL_3);
            assert (state.topology == LayoutTopology.LEFT_TALL_3);

            state.save_to_disk ();

            var loaded_state = new RStudioDockLayoutState ();
            loaded_state.load_from_disk ();
            assert (loaded_state.topology == LayoutTopology.LEFT_TALL_3);

            // Clean up to default
            loaded_state.reset_to_default ();
            loaded_state.save_to_disk ();
        }

        private static void test_undock_redock_flow () {
            var state = new RStudioDockLayoutState ();
            assert (!state.popped_out_panels.contains (PanelId.LIVE_PREVIEW));

            state.undock_panel (PanelId.LIVE_PREVIEW);
            assert (state.popped_out_panels.contains (PanelId.LIVE_PREVIEW));

            state.redock_panel (PanelId.LIVE_PREVIEW);
            assert (!state.popped_out_panels.contains (PanelId.LIVE_PREVIEW));
        }

        private static void test_layout_serializer_presets () {
            var state = new RStudioDockLayoutState ();
            LayoutSerializer.apply_topology_preset (LayoutTopology.RIGHT_TALL_3, state);
            assert (state.topology == LayoutTopology.RIGHT_TALL_3);

            try {
                LayoutSerializer.save_layout ("test-biostat-layout", state);
                string[] saved = LayoutSerializer.list_saved_layouts ();
                bool found = false;
                foreach (var s in saved) {
                    if (s == "test-biostat-layout") found = true;
                }
                assert (found);

                var new_state = new RStudioDockLayoutState ();
                bool ok = LayoutSerializer.load_layout ("test-biostat-layout", new_state);
                assert (ok);
                assert (new_state.topology == LayoutTopology.RIGHT_TALL_3);
            } catch (GLib.Error e) {
                assert_not_reached ();
            }
        }

        private static void test_data_row () {
            string[] cells = { "21.0", "6", "160", "110" };
            var row = new DataRow (1, cells);
            assert (row.row_index == 1);
            assert (row.get_cell (0) == "21.0");
            assert (row.get_cell (1) == "6");
            assert (row.get_cell (3) == "110");
            assert (row.get_cell (10) == ""); // Out of bounds returns empty string
        }

        private static void test_data_viewer_widget () {
            string[] cells = { "21.0", "6", "160", "110" };
            var row = new DataRow (1, cells);
            var viewer = new DataGridViewer ();
            assert (viewer.active_object_name == "");

            var list = new Gee.ArrayList<DataRow> ();
            list.add (row);
            viewer.populate_grid_data ("test_df", { "mpg", "cyl", "disp", "hp" }, list);
            assert (viewer.active_object_name == "test_df");
        }

        private static void test_variable_item_parsing () {
            var item = new EnvVariableItem ("mtcars", "data.frame", "32 × 11", "7.2 Kb", true);
            assert (item.name == "mtcars");
            assert (item.var_type == "data.frame");
            assert (item.dimensions == "32 × 11");
            assert (item.is_dataframe == true);
        }
    }

    public static int main (string[] args) {
        string tmp_xdg = "";
        try {
            tmp_xdg = GLib.DirUtils.make_tmp ("imladris-dock-test-XXXXXX");
            GLib.Environment.set_variable ("XDG_CONFIG_HOME", GLib.Path.build_filename (tmp_xdg, "config"), true);
            GLib.Environment.set_variable ("XDG_DATA_HOME", GLib.Path.build_filename (tmp_xdg, "data"), true);
            GLib.Environment.set_variable ("XDG_CACHE_HOME", GLib.Path.build_filename (tmp_xdg, "cache"), true);
        } catch (GLib.Error e) {
            warning ("Temp dir setup failed: %s", e.message);
        }

        bool has_display = Gtk.init_check ();
        Test.init (ref args);
        DockEnvironmentTests.register_tests (has_display);
        int rc = Test.run ();

        if (tmp_xdg != "") {
            Core.PlatformUtils.delete_directory_recursive (GLib.File.new_for_path (tmp_xdg));
        }
        return rc;
    }
}
