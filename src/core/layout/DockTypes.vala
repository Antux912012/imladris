// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris.Core.Layout {

    public enum QuadrantId {
        Q1_TOP_LEFT,
        Q2_BOTTOM_LEFT,
        Q3_TOP_RIGHT,
        Q4_BOTTOM_RIGHT,
        Q5_TOP_CENTER,
        Q6_BOTTOM_CENTER;

        public string to_id_string () {
            switch (this) {
                case Q1_TOP_LEFT: return "Q1_TOP_LEFT";
                case Q2_BOTTOM_LEFT: return "Q2_BOTTOM_LEFT";
                case Q3_TOP_RIGHT: return "Q3_TOP_RIGHT";
                case Q4_BOTTOM_RIGHT: return "Q4_BOTTOM_RIGHT";
                case Q5_TOP_CENTER: return "Q5_TOP_CENTER";
                case Q6_BOTTOM_CENTER: return "Q6_BOTTOM_CENTER";
                default: return "Q1_TOP_LEFT";
            }
        }

        public string to_display_name () {
            switch (this) {
                case Q1_TOP_LEFT: return "Top-Left (Editor)";
                case Q2_BOTTOM_LEFT: return "Bottom-Left (Console)";
                case Q5_TOP_CENTER: return "Top-Center (Preview)";
                case Q6_BOTTOM_CENTER: return "Bottom-Center (AI / Plots)";
                case Q3_TOP_RIGHT: return "Top-Right (Environment)";
                case Q4_BOTTOM_RIGHT: return "Bottom-Right (Outputs)";
                default: return "Quadrant";
            }
        }

        public static QuadrantId from_id_string (string str) {
            switch (str) {
                case "Q2_BOTTOM_LEFT": return Q2_BOTTOM_LEFT;
                case "Q3_TOP_RIGHT": return Q3_TOP_RIGHT;
                case "Q4_BOTTOM_RIGHT": return Q4_BOTTOM_RIGHT;
                case "Q5_TOP_CENTER": return Q5_TOP_CENTER;
                case "Q6_BOTTOM_CENTER": return Q6_BOTTOM_CENTER;
                case "Q1_TOP_LEFT":
                default: return Q1_TOP_LEFT;
            }
        }

        public static QuadrantId[] all () {
            return {
                Q1_TOP_LEFT,
                Q2_BOTTOM_LEFT,
                Q5_TOP_CENTER,
                Q6_BOTTOM_CENTER,
                Q3_TOP_RIGHT,
                Q4_BOTTOM_RIGHT
            };
        }

        public static QuadrantId[] active_for_topology (LayoutTopology topo) {
            switch (topo) {
                case LayoutTopology.QUAD_6_ULTRAWIDE:
                    return {
                        Q1_TOP_LEFT,
                        Q2_BOTTOM_LEFT,
                        Q5_TOP_CENTER,
                        Q6_BOTTOM_CENTER,
                        Q3_TOP_RIGHT,
                        Q4_BOTTOM_RIGHT
                    };
                case LayoutTopology.LEFT_TALL_3:
                    return { Q1_TOP_LEFT, Q3_TOP_RIGHT, Q4_BOTTOM_RIGHT };
                case LayoutTopology.RIGHT_TALL_3:
                    return { Q1_TOP_LEFT, Q2_BOTTOM_LEFT, Q4_BOTTOM_RIGHT };
                case LayoutTopology.QUAD_4:
                default:
                    return { Q1_TOP_LEFT, Q2_BOTTOM_LEFT, Q3_TOP_RIGHT, Q4_BOTTOM_RIGHT };
            }
        }
    }

    public enum PanelId {
        SOURCE_EDITOR,
        DATA_VIEWER,
        LIVE_PREVIEW,
        CONSOLE,
        TERMINAL,
        ELROND_AI,
        ENVIRONMENT,
        HISTORY,
        OUTLINE,
        CITATIONS,
        PLOTS,
        FILES,
        PACKAGES,
        HELP,
        SHINY_VIEWER,
        GALAXY,
        WEB_SYNC,
        QUALITATIVE;

        public string to_id_string () {
            switch (this) {
                case SOURCE_EDITOR: return "source-editor";
                case DATA_VIEWER: return "data-viewer";
                case LIVE_PREVIEW: return "live-preview";
                case CONSOLE: return "console";
                case TERMINAL: return "terminal";
                case ELROND_AI: return "elrond-ai";
                case ENVIRONMENT: return "environment";
                case HISTORY: return "history";
                case OUTLINE: return "outline";
                case CITATIONS: return "citations";
                case PLOTS: return "plots";
                case FILES: return "files";
                case PACKAGES: return "packages";
                case HELP: return "help";
                case SHINY_VIEWER: return "shiny-viewer";
                case GALAXY: return "galaxy";
                case WEB_SYNC: return "web-sync";
                case QUALITATIVE: return "qualitative";
                default: return "source-editor";
            }
        }

        public static PanelId? from_id_string (string str) {
            switch (str) {
                case "source-editor": return SOURCE_EDITOR;
                case "data-viewer": return DATA_VIEWER;
                case "live-preview": return LIVE_PREVIEW;
                case "console": return CONSOLE;
                case "terminal": return TERMINAL;
                case "elrond-ai": return ELROND_AI;
                case "environment": return ENVIRONMENT;
                case "history": return HISTORY;
                case "outline": return OUTLINE;
                case "citations": return CITATIONS;
                case "plots": return PLOTS;
                case "files": return FILES;
                case "packages": return PACKAGES;
                case "help": return HELP;
                case "shiny-viewer": return SHINY_VIEWER;
                case "galaxy": return GALAXY;
                case "web-sync": return WEB_SYNC;
                case "qualitative": return QUALITATIVE;
                default: return null;
            }
        }

        public string to_title () {
            switch (this) {
                case SOURCE_EDITOR: return "Source Editor";
                case DATA_VIEWER: return "Data Viewer";
                case LIVE_PREVIEW: return "Preview";
                case CONSOLE: return "Console";
                case TERMINAL: return "Terminal";
                case ELROND_AI: return "Elrond AI";
                case ENVIRONMENT: return "Environment";
                case HISTORY: return "History";
                case OUTLINE: return "Outline";
                case CITATIONS: return "Citations";
                case PLOTS: return "Plots";
                case FILES: return "Files";
                case PACKAGES: return "Packages";
                case HELP: return "Help";
                case SHINY_VIEWER: return "Viewer";
                case GALAXY: return "Arekyer Bridge";
                case WEB_SYNC: return "Imladris Web";
                case QUALITATIVE: return "Qualitative";
                default: return "Panel";
            }
        }

        public string to_icon_name () {
            switch (this) {
                case SOURCE_EDITOR: return "document-edit-symbolic";
                case DATA_VIEWER: return "view-grid-symbolic";
                case LIVE_PREVIEW: return "applications-internet-symbolic";
                case CONSOLE: return "utilities-terminal-symbolic";
                case TERMINAL: return "utilities-terminal-symbolic";
                case ELROND_AI: return "ai-elrond";
                case ENVIRONMENT: return "view-list-symbolic";
                case HISTORY: return "document-open-recent-symbolic";
                case OUTLINE: return "view-list-bullet-symbolic";
                case CITATIONS: return "accessories-dictionary-symbolic";
                case PLOTS: return "x-office-presentation-symbolic";
                case FILES: return "folder-symbolic";
                case PACKAGES: return "application-x-addon-symbolic";
                case HELP: return "help-browser-symbolic";
                case SHINY_VIEWER: return "applications-internet-symbolic";
                case GALAXY: return "applications-internet-symbolic";
                case WEB_SYNC: return "network-server-symbolic";
                case QUALITATIVE: return "view-list-bullet-symbolic";
                default: return "application-x-addon-symbolic";
            }
        }

        public static PanelId[] all () {
            return {
                SOURCE_EDITOR,
                DATA_VIEWER,
                LIVE_PREVIEW,
                CONSOLE,
                TERMINAL,
                ELROND_AI,
                ENVIRONMENT,
                HISTORY,
                OUTLINE,
                CITATIONS,
                PLOTS,
                FILES,
                PACKAGES,
                HELP,
                SHINY_VIEWER,
                GALAXY,
                WEB_SYNC,
                QUALITATIVE
            };
        }
    }

    public enum LayoutTopology {
        QUAD_4,
        LEFT_TALL_3,
        RIGHT_TALL_3,
        QUAD_6_ULTRAWIDE;

        public string to_id_string () {
            switch (this) {
                case LEFT_TALL_3: return "LEFT_TALL_3";
                case RIGHT_TALL_3: return "RIGHT_TALL_3";
                case QUAD_6_ULTRAWIDE: return "QUAD_6_ULTRAWIDE";
                case QUAD_4:
                default: return "QUAD_4";
            }
        }

        public static LayoutTopology from_id_string (string str) {
            switch (str) {
                case "LEFT_TALL_3": return LEFT_TALL_3;
                case "RIGHT_TALL_3": return RIGHT_TALL_3;
                case "QUAD_6_ULTRAWIDE": return QUAD_6_ULTRAWIDE;
                case "QUAD_4":
                default: return QUAD_4;
            }
        }

        public string to_title () {
            switch (this) {
                case LEFT_TALL_3: return "Left Editor Full-Height (3 Panels)";
                case RIGHT_TALL_3: return "Right Side Full-Height (3 Panels)";
                case QUAD_6_ULTRAWIDE: return "3×2 Ultrawide Grid (6 Panels — 21:9 / 34:9)";
                case QUAD_4:
                default: return "2×2 Quadrant Grid (4 Panels)";
            }
        }
    }

    public enum QuadrantSizeState {
        NORMAL,
        MINIMIZED,
        MAXIMIZED;

        public string to_id_string () {
            switch (this) {
                case MINIMIZED: return "MINIMIZED";
                case MAXIMIZED: return "MAXIMIZED";
                case NORMAL:
                default: return "NORMAL";
            }
        }

        public static QuadrantSizeState from_id_string (string s) {
            switch (s) {
                case "MINIMIZED": return MINIMIZED;
                case "MAXIMIZED": return MAXIMIZED;
                default: return NORMAL;
            }
        }
    }

    public class QuadrantConfig : GLib.Object {
        public QuadrantId id { get; set; }
        public Gee.ArrayList<PanelId> tabs { get; owned set; }
        public PanelId? active_tab = null;
        public QuadrantSizeState size_state { get; set; default = QuadrantSizeState.NORMAL; }

        public QuadrantConfig (QuadrantId id, PanelId[] initial_tabs, PanelId? active = null) {
            this.id = id;
            this.tabs = new Gee.ArrayList<PanelId> ();
            foreach (var p in initial_tabs) {
                this.tabs.add (p);
            }
            if (active != null) {
                this.active_tab = active;
            } else if (initial_tabs.length > 0) {
                this.active_tab = initial_tabs[0];
            } else {
                this.active_tab = null;
            }
            this.size_state = QuadrantSizeState.NORMAL;
        }
    }

    public class FloatingWindowGeometry : GLib.Object {
        public int width { get; set; default = 840; }
        public int height { get; set; default = 600; }
        public int monitor_index { get; set; default = -1; }

        public FloatingWindowGeometry (int w = 840, int h = 600, int mon = -1) {
            this.width = w.clamp (360, 4096);
            this.height = h.clamp (280, 2160);
            this.monitor_index = mon;
        }
    }

    public class SplitterRatios : GLib.Object {
        public double main_vertical { get; set; default = 0.55; }
        public double left_horizontal { get; set; default = 0.68; }
        public double right_horizontal { get; set; default = 0.45; }
        public double center_vertical { get; set; default = 0.50; }
        public double center_horizontal { get; set; default = 0.55; }

        public static double clamp_ratio (double val) {
            if (val < 0.15) return 0.15;
            if (val > 0.85) return 0.85;
            return val;
        }

        public void set_clamped (double main_v, double left_h, double right_h) {
            main_vertical = clamp_ratio (main_v);
            left_horizontal = clamp_ratio (left_h);
            right_horizontal = clamp_ratio (right_h);
        }

        public void set_clamped_all (double main_v, double left_h, double right_h, double center_v, double center_h) {
            main_vertical = clamp_ratio (main_v);
            left_horizontal = clamp_ratio (left_h);
            right_horizontal = clamp_ratio (right_h);
            center_vertical = clamp_ratio (center_v);
            center_horizontal = clamp_ratio (center_h);
        }
    }

    public class RStudioDockLayoutState : GLib.Object {
        public string mode { get; set; default = "RSTUDIO"; }
        public bool user_locked_mode { get; set; default = false; }
        public LayoutTopology topology { get; set; default = LayoutTopology.QUAD_4; }
        public QuadrantId? maximized_quadrant = null;
        public SplitterRatios ratios { get; owned set; }
        public Gee.HashMap<QuadrantId, QuadrantConfig> quadrants { get; owned set; }
        public Gee.HashSet<PanelId> popped_out_panels { get; private set; }
        public Gee.HashMap<PanelId, FloatingWindowGeometry> floating_geometries { get; private set; }

        public signal void state_updated ();
        public signal void panel_undocked (PanelId pid);
        public signal void panel_redocked (PanelId pid);

        public RStudioDockLayoutState () {
            ratios = new SplitterRatios ();
            quadrants = new Gee.HashMap<QuadrantId, QuadrantConfig> ();
            popped_out_panels = new Gee.HashSet<PanelId> ();
            floating_geometries = new Gee.HashMap<PanelId, FloatingWindowGeometry> ();
            reset_to_default ();
        }

        public void switch_topology (LayoutTopology top) {
            this.topology = top;
            save_to_disk ();
            state_updated ();
        }

        public QuadrantId? find_panel_quadrant (PanelId pid) {
            foreach (var qid in QuadrantId.all ()) {
                var qc = quadrants.get (qid);
                if (qc != null && qc.tabs.contains (pid)) {
                    return qid;
                }
            }
            return null;
        }

        public void set_floating_geometry (PanelId pid, int width, int height, int monitor_index = -1) {
            var geom = floating_geometries.get (pid);
            if (geom == null) {
                geom = new FloatingWindowGeometry (width, height, monitor_index);
                floating_geometries.set (pid, geom);
            } else {
                geom.width = width.clamp (360, 4096);
                geom.height = height.clamp (280, 2160);
                if (monitor_index >= 0) {
                    geom.monitor_index = monitor_index;
                }
            }
        }

        public FloatingWindowGeometry get_floating_geometry (PanelId pid) {
            var geom = floating_geometries.get (pid);
            if (geom != null) return geom;
            return new FloatingWindowGeometry (860, 620, -1);
        }

        public void undock_panel (PanelId pid) {
            popped_out_panels.add (pid);
            foreach (var qc in quadrants.values) {
                if (qc.active_tab == pid) {
                    PanelId? next_tab = null;
                    foreach (var t in qc.tabs) {
                        if (!popped_out_panels.contains (t)) {
                            next_tab = t;
                            break;
                        }
                    }
                    qc.active_tab = next_tab;
                }
            }
            save_to_disk ();
            panel_undocked (pid);
            state_updated ();
        }

        public void redock_panel (PanelId pid) {
            if (popped_out_panels.contains (pid)) {
                popped_out_panels.remove (pid);
                QuadrantId? owner = find_panel_quadrant (pid);
                if (owner != null) {
                    var qc = quadrants.get (owner);
                    if (qc != null) {
                        qc.active_tab = pid;
                        if (qc.size_state == QuadrantSizeState.MINIMIZED) {
                            qc.size_state = QuadrantSizeState.NORMAL;
                        }
                    }
                }
                save_to_disk ();
                panel_redocked (pid);
                state_updated ();
            }
        }

        public void redock_panel_to (PanelId pid, QuadrantId target_quad) {
            QuadrantId? current_quad = find_panel_quadrant (pid);
            bool was_popped = popped_out_panels.contains (pid);
            if (was_popped) {
                popped_out_panels.remove (pid);
            }
            if (current_quad != null && current_quad != target_quad) {
                move_tab (current_quad, target_quad, pid);
            } else {
                var dst = quadrants.get (target_quad);
                if (dst != null) {
                    if (!dst.tabs.contains (pid)) {
                        dst.tabs.add (pid);
                    }
                    dst.active_tab = pid;
                    if (dst.size_state == QuadrantSizeState.MINIMIZED) {
                        dst.size_state = QuadrantSizeState.NORMAL;
                    }
                }
                save_to_disk ();
                state_updated ();
            }
            if (was_popped) {
                panel_redocked (pid);
            }
        }

        public void reset_to_default () {
            mode = "RSTUDIO";
            user_locked_mode = false;
            topology = LayoutTopology.QUAD_4;
            maximized_quadrant = null;
            ratios.set_clamped_all (0.55, 0.68, 0.45, 0.50, 0.55);
            quadrants.clear ();
            popped_out_panels.clear ();

            quadrants.set (
                QuadrantId.Q1_TOP_LEFT,
                new QuadrantConfig (QuadrantId.Q1_TOP_LEFT, { PanelId.SOURCE_EDITOR, PanelId.DATA_VIEWER }, PanelId.SOURCE_EDITOR)
            );
            quadrants.set (
                QuadrantId.Q2_BOTTOM_LEFT,
                new QuadrantConfig (QuadrantId.Q2_BOTTOM_LEFT, { PanelId.CONSOLE, PanelId.TERMINAL, PanelId.ELROND_AI }, PanelId.CONSOLE)
            );
            quadrants.set (
                QuadrantId.Q3_TOP_RIGHT,
                new QuadrantConfig (QuadrantId.Q3_TOP_RIGHT, { PanelId.ENVIRONMENT, PanelId.QUALITATIVE, PanelId.HISTORY, PanelId.OUTLINE, PanelId.CITATIONS, PanelId.GALAXY, PanelId.WEB_SYNC }, PanelId.ENVIRONMENT)
            );
            quadrants.set (
                QuadrantId.Q4_BOTTOM_RIGHT,
                new QuadrantConfig (QuadrantId.Q4_BOTTOM_RIGHT, { PanelId.FILES, PanelId.PLOTS, PanelId.PACKAGES, PanelId.HELP, PanelId.SHINY_VIEWER, PanelId.LIVE_PREVIEW }, PanelId.FILES)
            );
            quadrants.set (
                QuadrantId.Q5_TOP_CENTER,
                new QuadrantConfig (QuadrantId.Q5_TOP_CENTER, {}, null)
            );
            quadrants.set (
                QuadrantId.Q6_BOTTOM_CENTER,
                new QuadrantConfig (QuadrantId.Q6_BOTTOM_CENTER, {}, null)
            );
            state_updated ();
        }

        /**
         * Configures a balanced 6-Quadrant (3x2) layout optimized for 21:9, 32:9, and 34:9 ultrawide displays.
         */
        public void apply_ultrawide_6_defaults () {
            topology = LayoutTopology.QUAD_6_ULTRAWIDE;
            maximized_quadrant = null;
            ratios.set_clamped_all (0.36, 0.65, 0.48, 0.52, 0.58);

            // Preserve any custom panel presence while distributing panels cleanly across 6 slots
            quadrants.set (
                QuadrantId.Q1_TOP_LEFT,
                new QuadrantConfig (QuadrantId.Q1_TOP_LEFT, { PanelId.SOURCE_EDITOR, PanelId.DATA_VIEWER }, PanelId.SOURCE_EDITOR)
            );
            quadrants.set (
                QuadrantId.Q2_BOTTOM_LEFT,
                new QuadrantConfig (QuadrantId.Q2_BOTTOM_LEFT, { PanelId.CONSOLE, PanelId.TERMINAL }, PanelId.CONSOLE)
            );
            quadrants.set (
                QuadrantId.Q5_TOP_CENTER,
                new QuadrantConfig (QuadrantId.Q5_TOP_CENTER, { PanelId.LIVE_PREVIEW, PanelId.SHINY_VIEWER }, PanelId.LIVE_PREVIEW)
            );
            quadrants.set (
                QuadrantId.Q6_BOTTOM_CENTER,
                new QuadrantConfig (QuadrantId.Q6_BOTTOM_CENTER, { PanelId.ELROND_AI, PanelId.PLOTS }, PanelId.ELROND_AI)
            );
            quadrants.set (
                QuadrantId.Q3_TOP_RIGHT,
                new QuadrantConfig (QuadrantId.Q3_TOP_RIGHT, { PanelId.ENVIRONMENT, PanelId.QUALITATIVE, PanelId.HISTORY, PanelId.OUTLINE, PanelId.CITATIONS, PanelId.GALAXY, PanelId.WEB_SYNC }, PanelId.ENVIRONMENT)
            );
            quadrants.set (
                QuadrantId.Q4_BOTTOM_RIGHT,
                new QuadrantConfig (QuadrantId.Q4_BOTTOM_RIGHT, { PanelId.FILES, PanelId.PACKAGES, PanelId.HELP }, PanelId.FILES)
            );
            save_to_disk ();
            state_updated ();
        }

        // 1. Intra-Quadrant Tab Reorder
        public void reorder_tab (QuadrantId quad_id, int source_index, int dest_index) {
            var q = quadrants.get (quad_id);
            if (q == null) return;
            if (source_index < 0 || source_index >= q.tabs.size) return;
            int clamped_dest = dest_index.clamp (0, q.tabs.size - 1);
            if (source_index == clamped_dest) return;

            PanelId moved = q.tabs.remove_at (source_index);
            q.tabs.insert (clamped_dest, moved);
            save_to_disk ();
            state_updated ();
        }

        // 2. Cross-Quadrant Tab Move + Empty Quadrant Auto-Collapse
        public void move_tab (QuadrantId source_quad_id, QuadrantId target_quad_id, PanelId panel_id, int insert_index = -1) {
            var src = quadrants.get (source_quad_id);
            var dst = quadrants.get (target_quad_id);
            if (src == null || dst == null) return;

            if (source_quad_id == target_quad_id) {
                int cur_idx = src.tabs.index_of (panel_id);
                if (cur_idx >= 0 && insert_index >= 0) {
                    reorder_tab (source_quad_id, cur_idx, insert_index);
                }
                return;
            }

            // 1. Remove PanelId from sourceQuadrant.tabs
            src.tabs.remove (panel_id);

            // 2. If sourceQuadrant.activeTab === panelId, fallback to first docked tab
            if (src.active_tab == panel_id) {
                PanelId? next_active = null;
                foreach (var t in src.tabs) {
                    if (!popped_out_panels.contains (t)) {
                        next_active = t;
                        break;
                    }
                }
                if (next_active != null) {
                    src.active_tab = next_active;
                } else if (src.tabs.size > 0) {
                    src.active_tab = src.tabs.get (0);
                } else {
                    src.active_tab = null;
                }
            }

            // Empty Quadrant Auto-Collapse: automatically set sourceQuadrant.sizeState = 'MINIMIZED'
            if (src.tabs.size == 0) {
                src.size_state = QuadrantSizeState.MINIMIZED;
                if (maximized_quadrant == source_quad_id) {
                    maximized_quadrant = null;
                }
            }

            // 3. Append/insert PanelId into targetQuadrant.tabs and set targetQuadrant.activeTab = panelId
            if (!dst.tabs.contains (panel_id)) {
                if (insert_index >= 0 && insert_index <= dst.tabs.size) {
                    dst.tabs.insert (insert_index, panel_id);
                } else {
                    dst.tabs.add (panel_id);
                }
            }
            dst.active_tab = panel_id;
            if (dst.size_state == QuadrantSizeState.MINIMIZED) {
                dst.size_state = QuadrantSizeState.NORMAL;
            }

            save_to_disk ();
            state_updated ();
        }

        // 3. Whole-Quadrant Swap (move all tabs & active selection between two quadrants)
        public void swap_quadrants (QuadrantId a_id, QuadrantId b_id) {
            if (a_id == b_id) return;
            var qa = quadrants.get (a_id);
            var qb = quadrants.get (b_id);
            if (qa == null || qb == null) return;

            var tmp_tabs = new Gee.ArrayList<PanelId> ();
            foreach (var p in qa.tabs) tmp_tabs.add (p);
            PanelId? tmp_active = qa.active_tab;
            QuadrantSizeState tmp_state = qa.size_state;

            qa.tabs.clear ();
            foreach (var p in qb.tabs) qa.tabs.add (p);
            qa.active_tab = qb.active_tab;
            qa.size_state = qb.size_state;

            qb.tabs.clear ();
            foreach (var p in tmp_tabs) qb.tabs.add (p);
            qb.active_tab = tmp_active;
            qb.size_state = tmp_state;

            if (maximized_quadrant == a_id) {
                maximized_quadrant = b_id;
            } else if (maximized_quadrant == b_id) {
                maximized_quadrant = a_id;
            }

            save_to_disk ();
            state_updated ();
        }

        public void activate_tab (QuadrantId quad_id, PanelId panel_id) {
            var q = quadrants.get (quad_id);
            if (q == null) return;
            if (q.tabs.contains (panel_id)) {
                q.active_tab = panel_id;
                if (q.size_state == QuadrantSizeState.MINIMIZED) {
                    q.size_state = QuadrantSizeState.NORMAL;
                }
                save_to_disk ();
                state_updated ();
            }
        }

        public void activate_panel (PanelId panel_id) {
            foreach (var qid in QuadrantId.all ()) {
                var q = quadrants.get (qid);
                if (q != null && q.tabs.contains (panel_id)) {
                    activate_tab (qid, panel_id);
                    return;
                }
            }
        }

        public void toggle_minimize (QuadrantId quad_id) {
            var q = quadrants.get (quad_id);
            if (q == null) return;
            if (maximized_quadrant == quad_id) {
                maximized_quadrant = null;
            }
            if (q.size_state == QuadrantSizeState.MINIMIZED) {
                q.size_state = QuadrantSizeState.NORMAL;
            } else {
                q.size_state = QuadrantSizeState.MINIMIZED;
            }
            save_to_disk ();
            state_updated ();
        }

        public void toggle_maximize (QuadrantId quad_id) {
            var q = quadrants.get (quad_id);
            if (q == null) return;
            if (maximized_quadrant == quad_id) {
                maximized_quadrant = null;
                q.size_state = QuadrantSizeState.NORMAL;
            } else {
                maximized_quadrant = quad_id;
                q.size_state = QuadrantSizeState.MAXIMIZED;
            }
            save_to_disk ();
            state_updated ();
        }

        private string get_config_file_path () {
            string dir = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "imladris");
            GLib.DirUtils.create_with_parents (dir, 0755);
            return GLib.Path.build_filename (dir, "dock-layout.json");
        }

        public void save_to_disk () {
            try {
                var builder = new Json.Builder ();
                builder.begin_object ();
                builder.set_member_name ("mode");
                builder.add_string_value (mode);
                builder.set_member_name ("userLockedMode");
                builder.add_boolean_value (user_locked_mode);
                builder.set_member_name ("topology");
                builder.add_string_value (topology.to_id_string ());

                builder.set_member_name ("maximizedQuadrant");
                if (maximized_quadrant != null) {
                    builder.add_string_value (maximized_quadrant.to_id_string ());
                } else {
                    builder.add_null_value ();
                }

                builder.set_member_name ("ratios");
                builder.begin_object ();
                builder.set_member_name ("mainVertical");
                builder.add_double_value (ratios.main_vertical);
                builder.set_member_name ("leftHorizontal");
                builder.add_double_value (ratios.left_horizontal);
                builder.set_member_name ("rightHorizontal");
                builder.add_double_value (ratios.right_horizontal);
                builder.set_member_name ("centerVertical");
                builder.add_double_value (ratios.center_vertical);
                builder.set_member_name ("centerHorizontal");
                builder.add_double_value (ratios.center_horizontal);
                builder.end_object ();

                builder.set_member_name ("poppedOutPanels");
                builder.begin_array ();
                foreach (var pid in popped_out_panels) {
                    builder.add_string_value (pid.to_id_string ());
                }
                builder.end_array ();

                builder.set_member_name ("floatingGeometries");
                builder.begin_object ();
                foreach (var entry in floating_geometries.entries) {
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
                    var qc = quadrants.get (qid);
                    if (qc == null) continue;
                    builder.set_member_name (qid.to_id_string ());
                    builder.begin_object ();
                    builder.set_member_name ("id");
                    builder.add_string_value (qid.to_id_string ());
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
                GLib.FileUtils.set_contents (get_config_file_path (), json_str);
            } catch (GLib.Error e) {
                warning ("Failed to persist RStudio dock layout state: %s", e.message);
            }
        }

        public void load_from_disk () {
            string path = get_config_file_path ();
            if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) return;
            try {
                string contents;
                GLib.FileUtils.get_contents (path, out contents);
                var parser = new Json.Parser ();
                parser.load_from_data (contents, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return;
                var obj = root.get_object ();

                if (obj.has_member ("userLockedMode") && obj.get_member ("userLockedMode").get_node_type () == Json.NodeType.VALUE) {
                    user_locked_mode = obj.get_boolean_member ("userLockedMode");
                }
                if (obj.has_member ("topology") && obj.get_member ("topology").get_node_type () == Json.NodeType.VALUE) {
                    topology = LayoutTopology.from_id_string (obj.get_string_member ("topology") ?? "rstudio-default");
                }

                if (obj.has_member ("ratios") && obj.get_member ("ratios").get_node_type () == Json.NodeType.OBJECT) {
                    var r_obj = obj.get_object_member ("ratios");
                    double mv = (r_obj.has_member ("mainVertical") && r_obj.get_member ("mainVertical").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("mainVertical") : 0.55;
                    double lh = (r_obj.has_member ("leftHorizontal") && r_obj.get_member ("leftHorizontal").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("leftHorizontal") : 0.68;
                    double rh = (r_obj.has_member ("rightHorizontal") && r_obj.get_member ("rightHorizontal").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("rightHorizontal") : 0.45;
                    double cv = (r_obj.has_member ("centerVertical") && r_obj.get_member ("centerVertical").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("centerVertical") : 0.50;
                    double ch = (r_obj.has_member ("centerHorizontal") && r_obj.get_member ("centerHorizontal").get_node_type () == Json.NodeType.VALUE) ? r_obj.get_double_member ("centerHorizontal") : 0.55;
                    ratios.set_clamped_all (mv, lh, rh, cv, ch);
                }

                if (obj.has_member ("maximizedQuadrant") && !obj.get_null_member ("maximizedQuadrant") &&
                    obj.get_member ("maximizedQuadrant").get_node_type () == Json.NodeType.VALUE) {
                    maximized_quadrant = QuadrantId.from_id_string (obj.get_string_member ("maximizedQuadrant"));
                } else {
                    maximized_quadrant = null;
                }

                popped_out_panels.clear ();
                if (obj.has_member ("poppedOutPanels") && obj.get_member ("poppedOutPanels").get_node_type () == Json.NodeType.ARRAY) {
                    var p_arr = obj.get_array_member ("poppedOutPanels");
                    for (uint i = 0; i < p_arr.get_length (); i++) {
                        var el = p_arr.get_element (i);
                        if (el == null || el.get_node_type () != Json.NodeType.VALUE) continue;
                        PanelId? pid = PanelId.from_id_string (el.get_string () ?? "");
                        if (pid != null) {
                            popped_out_panels.add (pid);
                        }
                    }
                }

                floating_geometries.clear ();
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
                        floating_geometries.set (pid, new FloatingWindowGeometry (w, h, m));
                    }
                }

                if (obj.has_member ("quadrants") && obj.get_member ("quadrants").get_node_type () == Json.NodeType.OBJECT) {
                    var q_obj = obj.get_object_member ("quadrants");
                    foreach (var qid in QuadrantId.all ()) {
                        string qkey = qid.to_id_string ();
                        if (!q_obj.has_member (qkey) || q_obj.get_member (qkey).get_node_type () != Json.NodeType.OBJECT) continue;
                        var q_item = q_obj.get_object_member (qkey);
                        var qc = quadrants.get (qid);
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

                // Reconcile newly introduced panels into older saved layouts
                ensure_panel_present (PanelId.LIVE_PREVIEW, QuadrantId.Q4_BOTTOM_RIGHT);
                ensure_panel_present (PanelId.SHINY_VIEWER, QuadrantId.Q4_BOTTOM_RIGHT);
                ensure_panel_present (PanelId.WEB_SYNC, QuadrantId.Q3_TOP_RIGHT);
                ensure_panel_present (PanelId.QUALITATIVE, QuadrantId.Q3_TOP_RIGHT);
            } catch (GLib.Error e) {
                warning ("Failed to load RStudio dock layout state: %s", e.message);
            }
        }

        public void ensure_panel_present (PanelId pid, QuadrantId fallback_quad) {
            foreach (var qid in QuadrantId.all ()) {
                var q = quadrants.get (qid);
                if (q != null && q.tabs.contains (pid)) {
                    return;
                }
            }
            var target = quadrants.get (fallback_quad);
            if (target != null) {
                target.tabs.add (pid);
                if (target.active_tab == null) {
                    target.active_tab = pid;
                }
            }
        }
    }
}
