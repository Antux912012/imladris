// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Provides an interactive visual flowchart, mindmap,
 * sequence, and state diagram studio (similar to draw.io and MindNode) that
 * synchronizes graphical node-and-edge manipulation with Mermaid code.
 *
 * Architectural Position:
 * Modal studio dialog inside Imladris.UI.
 * Upstream callers: Imladris.Window (Insert Ribbon, Primary Menu, Ctrl+Shift+M).
 * Downstream dependencies: Imladris.Core.MermaidFlowEngine, GTK4, Libadwaita, Cairo.
 *
 * Concurrency Constraints:
 * Executes exclusively on the GLib MainContext thread. Cairo drawing callbacks
 * operate within the 16.6 ms (60 Hz) frame budget without synchronous file I/O.
 */
namespace Imladris.UI {

    /**
     * Interactive visual creator for Mermaid flowcharts, mindmaps, sequence
     * diagrams, and state machines.
     */
    public class MermaidFlowStudioDialog : Adw.Dialog {

        /**
         * Emitted when the user inserts the generated Mermaid block into the active report.
         *
         * @param formatted_mermaid The complete Mermaid code chunk or fence.
         * @param save_document     True if the host document should be saved immediately.
         */
        public signal void diagram_inserted (string formatted_mermaid, bool save_document);

        private class GraphSnapshot : GLib.Object {
            public Core.MermaidDiagramKind kind;
            public Core.MermaidFlowDirection direction;
            public Gee.ArrayList<Core.MermaidNode> nodes = new Gee.ArrayList<Core.MermaidNode> ();
            public Gee.ArrayList<Core.MermaidEdge> edges = new Gee.ArrayList<Core.MermaidEdge> ();
        }

        private Adw.ToastOverlay toast_overlay;
        private Gtk.DropDown kind_dropdown;
        private Gtk.DropDown direction_dropdown;
        private Gtk.DropDown target_format_dropdown;
        private Gtk.DropDown preset_dropdown;
        private Gtk.ToggleButton connect_mode_btn;
        private Gtk.Button btn_undo;
        private Gtk.Button btn_redo;

        // Visual Canvas State
        private Gtk.DrawingArea canvas;
        private Gtk.Label canvas_status_label;
        private Gtk.Label zoom_badge_label;
        private Core.MermaidDiagramKind current_kind = Core.MermaidDiagramKind.FLOWCHART;
        private Core.MermaidFlowDirection current_direction = Core.MermaidFlowDirection.TOP_DOWN;
        private Gee.ArrayList<Core.MermaidNode> nodes = new Gee.ArrayList<Core.MermaidNode> ();
        private Gee.ArrayList<Core.MermaidEdge> edges = new Gee.ArrayList<Core.MermaidEdge> ();
        private Gee.ArrayList<Core.MermaidPreset> presets;

        // Selection & Interaction State
        private Core.MermaidNode? selected_node = null;
        private Core.MermaidEdge? selected_edge = null;
        private Core.MermaidNode? hovered_node = null;
        private Core.MermaidNode? connect_source_node = null;
        private bool is_dragging_node = false;
        private bool is_dragging_wire = false;
        private bool is_panning_canvas = false;
        private double drag_start_world_x = 0.0;
        private double drag_start_world_y = 0.0;
        private double node_orig_x = 0.0;
        private double node_orig_y = 0.0;
        private double wire_cursor_x = 0.0;
        private double wire_cursor_y = 0.0;
        private double pan_x = 0.0;
        private double pan_y = 0.0;
        private double pan_orig_x = 0.0;
        private double pan_orig_y = 0.0;
        private double zoom_factor = 1.0;
        private int next_node_seq = 1;
        private int next_edge_seq = 1;

        // Undo / Redo Stacks
        private Gee.ArrayList<GraphSnapshot> undo_stack = new Gee.ArrayList<GraphSnapshot> ();
        private Gee.ArrayList<GraphSnapshot> redo_stack = new Gee.ArrayList<GraphSnapshot> ();

        // Inspector Widgets
        private Gtk.Stack inspector_stack;
        private Gtk.Entry node_label_entry;
        private Gtk.DropDown node_shape_dropdown;
        private Gtk.Entry node_subgraph_entry;
        private Gtk.Button[] palette_buttons = new Gtk.Button[7];
        private Gtk.Entry edge_label_entry;
        private Gtk.DropDown edge_style_dropdown;
        private Gtk.Entry fig_label_entry;
        private Gtk.Entry fig_caption_entry;
        private Gtk.TextView code_view;
        private bool syncing_ui = false;

        /**
         * Constructs a new Visual Flow & Mindmap Studio dialog.
         *
         * @param initial_mermaid Optional existing Mermaid block from editor selection.
         */
        public MermaidFlowStudioDialog (string? initial_mermaid = null) {
            Object (
                title: "Visual Flow & Mindmap Studio",
                content_width: 1180,
                content_height: 780
            );

            this.presets = Core.MermaidFlowEngine.get_presets ();
            build_ui ();

            if (initial_mermaid != null && initial_mermaid.strip ().length > 0) {
                load_from_mermaid_code (initial_mermaid);
            } else {
                load_default_starter_diagram ();
            }
        }

        private void build_ui () {
            toast_overlay = new Adw.ToastOverlay ();
            var toolbar_view = new Adw.ToolbarView ();

            // 1. HeaderBar
            var header_bar = new Adw.HeaderBar ();

            var history_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                css_classes = { "linked" }
            };
            btn_undo = new Gtk.Button.from_icon_name ("edit-undo-symbolic") {
                tooltip_text = "Undo Canvas Action (Ctrl+Z)",
                sensitive = false
            };
            btn_undo.clicked.connect (perform_undo);

            btn_redo = new Gtk.Button.from_icon_name ("edit-redo-symbolic") {
                tooltip_text = "Redo Canvas Action (Ctrl+Y)",
                sensitive = false
            };
            btn_redo.clicked.connect (perform_redo);
            history_box.append (btn_undo);
            history_box.append (btn_redo);
            header_bar.pack_start (history_box);

            var btn_autolayout = new Gtk.Button () {
                tooltip_text = "Automatically Arrange Nodes on Canvas"
            };
            var layout_content = new Adw.ButtonContent () {
                icon_name = "view-grid-symbolic",
                label = "Auto-Layout"
            };
            btn_autolayout.set_child (layout_content);
            btn_autolayout.clicked.connect (() => {
                push_undo_snapshot ();
                Core.MermaidFlowEngine.auto_layout (
                    current_kind,
                    current_direction,
                    nodes,
                    edges,
                    canvas.get_width () > 100 ? canvas.get_width () : 740.0,
                    canvas.get_height () > 100 ? canvas.get_height () : 520.0
                );
                canvas.queue_draw ();
                show_studio_toast ("Arranged diagram layout");
            });
            header_bar.pack_end (btn_autolayout);

            var btn_copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy Generated Mermaid Block to Clipboard"
            };
            btn_copy.clicked.connect (on_copy_code_clicked);
            header_bar.pack_end (btn_copy);

            toolbar_view.add_top_bar (header_bar);

            // 2. Top Studio Configuration Bar
            var top_config_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 6,
                margin_bottom = 6
            };
            top_config_bar.add_css_class ("toolbar");

            top_config_bar.append (new Gtk.Label ("Diagram:") { css_classes = { "dim-label", "caption" } });
            var kind_model = new Gtk.StringList ({
                "Flowchart (draw.io)",
                "Mindmap (Hierarchical)",
                "Sequence Diagram",
                "State Machine"
            });
            kind_dropdown = new Gtk.DropDown (kind_model, null) {
                selected = 0,
                tooltip_text = "Select Diagram Type"
            };
            kind_dropdown.notify["selected"].connect (() => {
                if (syncing_ui) return;
                push_undo_snapshot ();
                current_kind = (Core.MermaidDiagramKind) kind_dropdown.selected;
                direction_dropdown.sensitive = (current_kind == Core.MermaidDiagramKind.FLOWCHART || current_kind == Core.MermaidDiagramKind.STATE);
                Core.MermaidFlowEngine.auto_layout (current_kind, current_direction, nodes, edges);
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            top_config_bar.append (kind_dropdown);

            top_config_bar.append (new Gtk.Label ("Direction:") { css_classes = { "dim-label", "caption" } });
            var dir_model = new Gtk.StringList ({
                "Top → Down (TD)",
                "Left → Right (LR)",
                "Bottom → Top (BT)",
                "Right → Left (RL)"
            });
            direction_dropdown = new Gtk.DropDown (dir_model, null) {
                selected = 0,
                tooltip_text = "Flow Direction"
            };
            direction_dropdown.notify["selected"].connect (() => {
                if (syncing_ui) return;
                push_undo_snapshot ();
                current_direction = (Core.MermaidFlowDirection) direction_dropdown.selected;
                Core.MermaidFlowEngine.auto_layout (current_kind, current_direction, nodes, edges);
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            top_config_bar.append (direction_dropdown);

            top_config_bar.append (new Gtk.Label ("Output:") { css_classes = { "dim-label", "caption" } });
            var fmt_model = new Gtk.StringList ({
                "Quarto Chunk (```{mermaid})",
                "Markdown Fence (```mermaid)",
                "Raw Mermaid Syntax"
            });
            target_format_dropdown = new Gtk.DropDown (fmt_model, null) {
                selected = 0,
                tooltip_text = "Format inserted into your document"
            };
            target_format_dropdown.notify["selected"].connect (() => {
                if (!syncing_ui) refresh_mermaid_output ();
            });
            top_config_bar.append (target_format_dropdown);

            var preset_strings = new Gtk.StringList (null);
            preset_strings.append ("— Load Scientific Preset —");
            foreach (var p in presets) {
                preset_strings.append (p.title);
            }
            preset_dropdown = new Gtk.DropDown (preset_strings, null) {
                selected = 0,
                hexpand = true,
                tooltip_text = "Load a ready-to-edit scientific flowchart, mindmap, or sequence diagram"
            };
            preset_dropdown.notify["selected"].connect (on_preset_selected);
            top_config_bar.append (preset_dropdown);

            toolbar_view.add_top_bar (top_config_bar);

            // 3. Main Split Workspace: Left/Center Visual Canvas + Right Inspector & Code
            var main_paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                position = 740,
                wide_handle = true,
                hexpand = true,
                vexpand = true
            };

            // 3A. Left/Center Visual Canvas Area with Tool Palette
            var canvas_container = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                hexpand = true,
                vexpand = true
            };

            // Left Shape & Mindmap Palette Dock
            var palette_scroll = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                width_request = 148
            };
            var palette_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_start = 8,
                margin_end = 8,
                margin_top = 8,
                margin_bottom = 8
            };
            palette_box.add_css_class ("mermaid-palette-sidebar");

            var lbl_shapes = new Gtk.Label ("ADD SHAPES") {
                css_classes = { "caption", "dim-label", "heading" },
                xalign = 0,
                margin_bottom = 2
            };
            palette_box.append (lbl_shapes);

            palette_box.append (create_shape_add_button ("Process [ ]", "Add Process Rectangle Node", Core.MermaidNodeShape.RECTANGLE));
            palette_box.append (create_shape_add_button ("Decision { }", "Add Decision Diamond Node", Core.MermaidNodeShape.DIAMOND));
            palette_box.append (create_shape_add_button ("Start / End ([ ])", "Add Terminal Stadium Node", Core.MermaidNodeShape.STADIUM));
            palette_box.append (create_shape_add_button ("Rounded ( )", "Add Rounded Event Node", Core.MermaidNodeShape.ROUNDED));
            palette_box.append (create_shape_add_button ("Database [( )]", "Add Cylinder Database Node", Core.MermaidNodeShape.DATABASE));
            palette_box.append (create_shape_add_button ("Input / Out [/ /]", "Add Parallelogram Data Node", Core.MermaidNodeShape.PARALLELOGRAM));
            palette_box.append (create_shape_add_button ("Subroutine [[ ]]", "Add Subroutine Module Node", Core.MermaidNodeShape.SUBROUTINE));
            palette_box.append (create_shape_add_button ("Hexagon {{ }}", "Add Hexagon Preparation Node", Core.MermaidNodeShape.HEXAGON));
            palette_box.append (create_shape_add_button ("Circle (( ))", "Add Circle / Root Topic Node", Core.MermaidNodeShape.CIRCLE));

            palette_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 6, margin_bottom = 6 });

            var lbl_branch = new Gtk.Label ("MINDMAP & LINKS") {
                css_classes = { "caption", "dim-label", "heading" },
                xalign = 0,
                margin_bottom = 2
            };
            palette_box.append (lbl_branch);

            var btn_add_child = new Gtk.Button.with_label ("+ Child Branch") {
                tooltip_text = "Add a connected child node to the currently selected node (Tab)"
            };
            btn_add_child.add_css_class ("flat");
            btn_add_child.add_css_class ("mermaid-palette-btn");
            btn_add_child.clicked.connect (add_child_to_selected);
            palette_box.append (btn_add_child);

            var btn_add_sibling = new Gtk.Button.with_label ("+ Sibling Branch") {
                tooltip_text = "Add a sibling node sharing the same parent (Enter)"
            };
            btn_add_sibling.add_css_class ("flat");
            btn_add_sibling.add_css_class ("mermaid-palette-btn");
            btn_add_sibling.clicked.connect (add_sibling_to_selected);
            palette_box.append (btn_add_sibling);

            connect_mode_btn = new Gtk.ToggleButton.with_label ("↗ Connect Nodes") {
                tooltip_text = "Toggle Connect Mode: click source node then target node (or drag any node port handle ○)"
            };
            connect_mode_btn.add_css_class ("flat");
            connect_mode_btn.add_css_class ("mermaid-palette-btn");
            connect_mode_btn.toggled.connect (() => {
                connect_source_node = null;
                update_canvas_status ();
                canvas.queue_draw ();
            });
            palette_box.append (connect_mode_btn);

            palette_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL) { margin_top = 6, margin_bottom = 6 });

            var btn_del_sel = new Gtk.Button.with_label ("🗑 Delete Selected") {
                tooltip_text = "Delete selected node or connector (Delete / BackSpace)"
            };
            btn_del_sel.add_css_class ("flat");
            btn_del_sel.add_css_class ("destructive-action");
            btn_del_sel.clicked.connect (delete_selected_element);
            palette_box.append (btn_del_sel);

            var btn_clear_all = new Gtk.Button.with_label ("Clear Canvas") {
                tooltip_text = "Remove all nodes and start from an empty canvas"
            };
            btn_clear_all.add_css_class ("flat");
            btn_clear_all.clicked.connect (() => {
                push_undo_snapshot ();
                nodes.clear ();
                edges.clear ();
                selected_node = null;
                selected_edge = null;
                update_inspector_panel ();
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            palette_box.append (btn_clear_all);

            palette_scroll.set_child (palette_box);
            canvas_container.append (palette_scroll);
            canvas_container.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

            // Interactive Cairo Canvas with Floating Overlay Controls
            var canvas_overlay = new Gtk.Overlay () {
                hexpand = true,
                vexpand = true
            };

            canvas = new Gtk.DrawingArea () {
                hexpand = true,
                vexpand = true,
                focusable = true,
                can_focus = true
            };
            canvas.set_draw_func (draw_canvas);
            setup_canvas_controllers ();
            canvas_overlay.set_child (canvas);

            // Bottom floating HUD bar over canvas
            var hud_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                halign = Gtk.Align.FILL,
                valign = Gtk.Align.END,
                margin_start = 12,
                margin_end = 12,
                margin_bottom = 10
            };

            canvas_status_label = new Gtk.Label ("Drag nodes to move • Drag port handles (○) to connect • Double-click to rename") {
                css_classes = { "pill-indicator", "caption" },
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END,
                hexpand = true
            };
            hud_box.append (canvas_status_label);

            var zoom_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                css_classes = { "linked", "card" },
                halign = Gtk.Align.END
            };
            var btn_z_out = new Gtk.Button.from_icon_name ("zoom-out-symbolic") {
                tooltip_text = "Zoom Out Canvas",
                css_classes = { "flat" }
            };
            btn_z_out.clicked.connect (() => {
                set_canvas_zoom (zoom_factor - 0.15);
            });
            zoom_badge_label = new Gtk.Label ("100%") {
                css_classes = { "caption", "numeric" },
                width_chars = 5
            };
            var btn_z_reset = new Gtk.Button () {
                child = zoom_badge_label,
                tooltip_text = "Reset Canvas Zoom & Pan",
                css_classes = { "flat" }
            };
            btn_z_reset.clicked.connect (() => {
                pan_x = 0.0;
                pan_y = 0.0;
                set_canvas_zoom (1.0);
            });
            var btn_z_in = new Gtk.Button.from_icon_name ("zoom-in-symbolic") {
                tooltip_text = "Zoom In Canvas",
                css_classes = { "flat" }
            };
            btn_z_in.clicked.connect (() => {
                set_canvas_zoom (zoom_factor + 0.15);
            });
            zoom_box.append (btn_z_out);
            zoom_box.append (btn_z_reset);
            zoom_box.append (btn_z_in);
            hud_box.append (zoom_box);

            canvas_overlay.add_overlay (hud_box);
            canvas_container.append (canvas_overlay);
            main_paned.set_start_child (canvas_container);

            // 3B. Right Inspector + Live Synchronized Mermaid Code Editor
            var right_scroll = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                width_request = 360
            };

            var right_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 10,
                margin_bottom = 10
            };

            // Inspector Stack (Node Selected / Edge Selected / Empty Hints)
            inspector_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE
            };
            inspector_stack.add_named (build_node_inspector (), "node");
            inspector_stack.add_named (build_edge_inspector (), "edge");
            inspector_stack.add_named (build_empty_inspector (), "none");
            right_box.append (inspector_stack);

            // Quarto Figure Cross-Reference Metadata
            var meta_card = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                css_classes = { "card" },
                margin_top = 2
            };
            var meta_inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_start = 10,
                margin_end = 10,
                margin_top = 8,
                margin_bottom = 8
            };
            var meta_title = new Gtk.Label ("<b>Report Figure Metadata (Optional)</b>") {
                use_markup = true,
                xalign = 0,
                css_classes = { "caption" }
            };
            meta_inner.append (meta_title);

            fig_label_entry = new Gtk.Entry () {
                placeholder_text = "Figure ID (e.g. fig-pipeline)"
            };
            fig_label_entry.changed.connect (() => {
                if (!syncing_ui) refresh_mermaid_output ();
            });
            meta_inner.append (fig_label_entry);

            fig_caption_entry = new Gtk.Entry () {
                placeholder_text = "Figure Caption (e.g. Overview of experimental workflow)"
            };
            fig_caption_entry.changed.connect (() => {
                if (!syncing_ui) refresh_mermaid_output ();
            });
            meta_inner.append (fig_caption_entry);
            meta_card.append (meta_inner);
            right_box.append (meta_card);

            // Live Synchronized Mermaid Code Editor
            var code_header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var code_lbl = new Gtk.Label ("<b>Generated Mermaid Code (Two-Way Sync)</b>") {
                use_markup = true,
                xalign = 0,
                hexpand = true,
                css_classes = { "caption" }
            };
            var btn_parse_code = new Gtk.Button.with_label ("Sync Code → Canvas") {
                tooltip_text = "Parse edited Mermaid code back onto the visual canvas",
                css_classes = { "flat", "caption" }
            };
            btn_parse_code.clicked.connect (() => {
                push_undo_snapshot ();
                load_from_mermaid_code (code_view.buffer.text);
                show_studio_toast ("Updated visual canvas from Mermaid code");
            });
            code_header_box.append (code_lbl);
            code_header_box.append (btn_parse_code);
            right_box.append (code_header_box);

            var code_frame = new Gtk.Frame (null) {
                vexpand = true
            };
            var code_scroll = new Gtk.ScrolledWindow () {
                min_content_height = 190,
                vexpand = true
            };
            code_view = new Gtk.TextView () {
                monospace = true,
                wrap_mode = Gtk.WrapMode.NONE,
                top_margin = 8,
                bottom_margin = 8,
                left_margin = 10,
                right_margin = 10
            };
            code_scroll.set_child (code_view);
            code_frame.set_child (code_scroll);
            right_box.append (code_frame);

            right_scroll.set_child (right_box);
            main_paned.set_end_child (right_scroll);

            toolbar_view.set_content (main_paned);

            // 4. Bottom Action Bar
            var bottom_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 16,
                margin_end = 16
            };

            var btn_cancel = new Gtk.Button.with_label ("Cancel");
            btn_cancel.clicked.connect (() => {
                this.close ();
            });
            bottom_bar.append (btn_cancel);

            var btn_export_svg = new Gtk.Button () {
                tooltip_text = "Export Diagram as Standalone Vector SVG File"
            };
            var svg_content = new Adw.ButtonContent () {
                icon_name = "image-x-generic-symbolic",
                label = "Export SVG..."
            };
            btn_export_svg.set_child (svg_content);
            btn_export_svg.clicked.connect (() => {
                export_svg_async.begin ();
            });
            bottom_bar.append (btn_export_svg);

            bottom_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            var btn_insert = new Gtk.Button () {
                css_classes = { "pill-button" }
            };
            var ins_content = new Adw.ButtonContent () {
                icon_name = "insert-text-symbolic",
                label = "Insert as Code"
            };
            btn_insert.set_child (ins_content);
            btn_insert.clicked.connect (() => {
                emit_and_close (false);
            });
            bottom_bar.append (btn_insert);

            var btn_insert_save = new Gtk.Button () {
                css_classes = { "pill-button", "suggested-action" }
            };
            var save_content = new Adw.ButtonContent () {
                icon_name = "document-save-symbolic",
                label = "Insert & Save Report"
            };
            btn_insert_save.set_child (save_content);
            btn_insert_save.clicked.connect (() => {
                emit_and_close (true);
            });
            bottom_bar.append (btn_insert_save);

            toolbar_view.add_bottom_bar (bottom_bar);
            toast_overlay.set_child (toolbar_view);
            this.set_child (toast_overlay);
        }

        private Gtk.Widget create_shape_add_button (string label, string tooltip, Core.MermaidNodeShape shape) {
            var btn = new Gtk.Button.with_label (label) {
                tooltip_text = tooltip,
                halign = Gtk.Align.FILL
            };
            btn.add_css_class ("flat");
            btn.add_css_class ("mermaid-palette-btn");
            btn.clicked.connect (() => {
                add_node_with_shape (shape);
            });
            return btn;
        }

        private Gtk.Widget build_node_inspector () {
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                css_classes = { "card" }
            };
            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 10,
                margin_bottom = 10
            };

            var title = new Gtk.Label ("<b>Selected Node Inspector</b>") {
                use_markup = true,
                xalign = 0
            };
            inner.append (title);

            inner.append (new Gtk.Label ("Node Text Label:") { css_classes = { "caption", "dim-label" }, xalign = 0 });
            node_label_entry = new Gtk.Entry () {
                placeholder_text = "Enter step or topic title..."
            };
            node_label_entry.changed.connect (() => {
                if (syncing_ui || selected_node == null) return;
                selected_node.label = node_label_entry.text;
                selected_node.update_dimensions_for_label ();
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            inner.append (node_label_entry);

            inner.append (new Gtk.Label ("Geometric Shape:") { css_classes = { "caption", "dim-label" }, xalign = 0 });
            var shape_model = new Gtk.StringList ({
                "Rectangle [Process]",
                "Rounded (Event)",
                "Stadium ([Start / End])",
                "Diamond {Decision}",
                "Database [(Storage)]",
                "Subroutine [[Module]]",
                "Hexagon {{Condition}}",
                "Circle ((Topic))",
                "Parallelogram [/Data I/O/]",
                "Cloud )Idea("
            });
            node_shape_dropdown = new Gtk.DropDown (shape_model, null);
            node_shape_dropdown.notify["selected"].connect (() => {
                if (syncing_ui || selected_node == null) return;
                selected_node.shape = (Core.MermaidNodeShape) node_shape_dropdown.selected;
                selected_node.update_dimensions_for_label ();
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            inner.append (node_shape_dropdown);

            inner.append (new Gtk.Label ("Semantic Color Theme:") { css_classes = { "caption", "dim-label" }, xalign = 0 });
            var swatch_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            string[] swatch_names = { "Default", "Blue", "Green", "Amber", "Red", "Purple", "Teal" };
            string[] swatch_classes = { "slate", "blue", "green", "yellow", "red", "purple", "teal" };
            for (int i = 0; i < 7; i++) {
                int idx = i;
                var sbtn = new Gtk.Button () {
                    tooltip_text = swatch_names[i],
                    css_classes = { "accent-swatch-button" }
                };
                var circle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                    css_classes = { "accent-circle", "accent-circle-" + swatch_classes[i] }
                };
                sbtn.set_child (circle);
                sbtn.clicked.connect (() => {
                    if (selected_node == null) return;
                    selected_node.palette = (Core.MermaidNodePalette) idx;
                    update_palette_selection (selected_node.palette);
                    refresh_mermaid_output ();
                    canvas.queue_draw ();
                });
                palette_buttons[i] = sbtn;
                swatch_row.append (sbtn);
            }
            inner.append (swatch_row);

            inner.append (new Gtk.Label ("Subgraph / Swimlane Group (Optional):") { css_classes = { "caption", "dim-label" }, xalign = 0 });
            node_subgraph_entry = new Gtk.Entry () {
                placeholder_text = "e.g. Cloud Alignment or Statistical QC"
            };
            node_subgraph_entry.changed.connect (() => {
                if (syncing_ui || selected_node == null) return;
                selected_node.subgraph_title = node_subgraph_entry.text;
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            inner.append (node_subgraph_entry);

            card.append (inner);
            return card;
        }

        private Gtk.Widget build_edge_inspector () {
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                css_classes = { "card" }
            };
            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 10,
                margin_bottom = 10
            };

            inner.append (new Gtk.Label ("<b>Selected Connector Inspector</b>") { use_markup = true, xalign = 0 });
            inner.append (new Gtk.Label ("Connector Label (e.g. Yes / No / p < 0.05):") { css_classes = { "caption", "dim-label" }, xalign = 0 });

            edge_label_entry = new Gtk.Entry () {
                placeholder_text = "Optional label on arrow..."
            };
            edge_label_entry.changed.connect (() => {
                if (syncing_ui || selected_edge == null) return;
                selected_edge.label = edge_label_entry.text;
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            inner.append (edge_label_entry);

            inner.append (new Gtk.Label ("Line & Arrow Style:") { css_classes = { "caption", "dim-label" }, xalign = 0 });
            var style_model = new Gtk.StringList ({
                "Solid Arrow (-->)",
                "Dotted Arrow (-.->)",
                "Thick Arrow (==>)",
                "Solid Line (---)",
                "Bidirectional (<-->)"
            });
            edge_style_dropdown = new Gtk.DropDown (style_model, null);
            edge_style_dropdown.notify["selected"].connect (() => {
                if (syncing_ui || selected_edge == null) return;
                selected_edge.style = (Core.MermaidEdgeStyle) edge_style_dropdown.selected;
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            inner.append (edge_style_dropdown);

            var edge_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var btn_rev = new Gtk.Button.with_label ("⇄ Reverse Direction") {
                hexpand = true
            };
            btn_rev.clicked.connect (() => {
                if (selected_edge == null) return;
                push_undo_snapshot ();
                string tmp = selected_edge.from_id;
                selected_edge.from_id = selected_edge.to_id;
                selected_edge.to_id = tmp;
                refresh_mermaid_output ();
                canvas.queue_draw ();
            });
            edge_actions.append (btn_rev);

            var btn_del = new Gtk.Button.with_label ("Delete Arrow") {
                css_classes = { "destructive-action" }
            };
            btn_del.clicked.connect (delete_selected_element);
            edge_actions.append (btn_del);
            inner.append (edge_actions);

            card.append (inner);
            return card;
        }

        private Gtk.Widget build_empty_inspector () {
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                css_classes = { "card" }
            };
            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 12,
                margin_bottom = 12
            };
            inner.append (new Gtk.Label ("<b>Interactive Canvas Guide</b>") { use_markup = true, xalign = 0 });
            var tips = new Gtk.Label (
                "• <b>Click any node or arrow</b> on the canvas to edit its label, shape, and color.\n" +
                "• <b>Drag a node's port circle (○)</b> onto another node to draw a connector arrow.\n" +
                "• <b>Click + Child Branch</b> (or press <tt>Tab</tt>) to grow your flowchart or mindmap."
            ) {
                use_markup = true,
                wrap = true,
                xalign = 0,
                css_classes = { "caption", "dim-label" }
            };
            inner.append (tips);
            card.append (inner);
            return card;
        }

        private void setup_canvas_controllers () {
            // Pointer motion for hover & port highlighting
            var motion_ctrl = new Gtk.EventControllerMotion ();
            motion_ctrl.motion.connect ((mx, my) => {
                double wx = screen_to_world_x (mx);
                double wy = screen_to_world_y (my);
                var prev_hover = hovered_node;
                hovered_node = find_node_at (wx, wy);
                if (prev_hover != hovered_node) {
                    canvas.queue_draw ();
                }
            });
            canvas.add_controller (motion_ctrl);

            // Click controller for selection, Connect Mode, and double-click rename
            var click_ctrl = new Gtk.GestureClick ();
            click_ctrl.pressed.connect ((n_press, sx, sy) => {
                canvas.grab_focus ();
                double wx = screen_to_world_x (sx);
                double wy = screen_to_world_y (sy);

                var hit_node = find_node_at (wx, wy);

                if (connect_mode_btn.active && hit_node != null) {
                    if (connect_source_node == null) {
                        connect_source_node = hit_node;
                        selected_node = hit_node;
                        selected_edge = null;
                        update_canvas_status ();
                        update_inspector_panel ();
                        canvas.queue_draw ();
                        return;
                    } else if (connect_source_node != hit_node) {
                        push_undo_snapshot ();
                        create_edge_between (connect_source_node, hit_node);
                        connect_source_node = null;
                        connect_mode_btn.active = false;
                        update_canvas_status ();
                        refresh_mermaid_output ();
                        canvas.queue_draw ();
                        return;
                    }
                }

                if (hit_node != null) {
                    selected_node = hit_node;
                    selected_edge = null;
                    update_inspector_panel ();
                    canvas.queue_draw ();
                    if (n_press == 2) {
                        node_label_entry.grab_focus ();
                        node_label_entry.select_region (0, -1);
                    }
                    return;
                }

                var hit_edge = find_edge_at (wx, wy);
                if (hit_edge != null) {
                    selected_edge = hit_edge;
                    selected_node = null;
                    update_inspector_panel ();
                    canvas.queue_draw ();
                    return;
                }

                selected_node = null;
                selected_edge = null;
                connect_source_node = null;
                update_inspector_panel ();
                canvas.queue_draw ();
            });
            canvas.add_controller (click_ctrl);

            // Drag controller for moving nodes, drawing port wires, or panning canvas
            var drag_ctrl = new Gtk.GestureDrag ();
            drag_ctrl.drag_begin.connect ((start_x, start_y) => {
                double wx = screen_to_world_x (start_x);
                double wy = screen_to_world_y (start_y);
                drag_start_world_x = wx;
                drag_start_world_y = wy;

                // 1. Check if user grabbed a connection port handle on any node
                var port_owner = find_port_owner_at (wx, wy);
                if (port_owner != null) {
                    is_dragging_wire = true;
                    is_dragging_node = false;
                    is_panning_canvas = false;
                    connect_source_node = port_owner;
                    selected_node = port_owner;
                    wire_cursor_x = wx;
                    wire_cursor_y = wy;
                    canvas.queue_draw ();
                    return;
                }

                // 2. Check if user grabbed a node body to move it
                var hit_node = find_node_at (wx, wy);
                if (hit_node != null) {
                    push_undo_snapshot ();
                    is_dragging_node = true;
                    is_dragging_wire = false;
                    is_panning_canvas = false;
                    selected_node = hit_node;
                    selected_edge = null;
                    node_orig_x = hit_node.x;
                    node_orig_y = hit_node.y;
                    update_inspector_panel ();
                    canvas.queue_draw ();
                    return;
                }

                // 3. Otherwise pan the canvas
                is_panning_canvas = true;
                is_dragging_node = false;
                is_dragging_wire = false;
                pan_orig_x = pan_x;
                pan_orig_y = pan_y;
            });

            drag_ctrl.drag_update.connect ((offset_x, offset_y) => {
                if (is_dragging_node && selected_node != null) {
                    double raw_x = node_orig_x + offset_x / zoom_factor;
                    double raw_y = node_orig_y + offset_y / zoom_factor;
                    // Snap to 10px grid for clean alignment
                    selected_node.x = double.max (60.0, Math.round (raw_x / 10.0) * 10.0);
                    selected_node.y = double.max (40.0, Math.round (raw_y / 10.0) * 10.0);
                    canvas.queue_draw ();
                } else if (is_dragging_wire && connect_source_node != null) {
                    wire_cursor_x = drag_start_world_x + offset_x / zoom_factor;
                    wire_cursor_y = drag_start_world_y + offset_y / zoom_factor;
                    hovered_node = find_node_at (wire_cursor_x, wire_cursor_y);
                    canvas.queue_draw ();
                } else if (is_panning_canvas) {
                    pan_x = pan_orig_x + offset_x;
                    pan_y = pan_orig_y + offset_y;
                    canvas.queue_draw ();
                }
            });

            drag_ctrl.drag_end.connect ((offset_x, offset_y) => {
                if (is_dragging_wire && connect_source_node != null) {
                    double end_wx = drag_start_world_x + offset_x / zoom_factor;
                    double end_wy = drag_start_world_y + offset_y / zoom_factor;
                    var target = find_node_at (end_wx, end_wy);
                    if (target != null && target != connect_source_node) {
                        push_undo_snapshot ();
                        create_edge_between (connect_source_node, target);
                        refresh_mermaid_output ();
                    }
                    connect_source_node = null;
                }
                is_dragging_node = false;
                is_dragging_wire = false;
                is_panning_canvas = false;
                canvas.queue_draw ();
            });
            canvas.add_controller (drag_ctrl);

            // Scroll controller for smooth canvas zooming
            var scroll_ctrl = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
            scroll_ctrl.scroll.connect ((dx, dy) => {
                if (dy < 0) {
                    set_canvas_zoom (zoom_factor + 0.10);
                } else if (dy > 0) {
                    set_canvas_zoom (zoom_factor - 0.10);
                }
                return true;
            });
            canvas.add_controller (scroll_ctrl);

            // Keyboard shortcuts on canvas (Delete, Tab for Child, Enter for Sibling, Ctrl+Z/Y)
            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
                if (ctrl && (keyval == Gdk.Key.z || keyval == Gdk.Key.Z)) {
                    perform_undo ();
                    return true;
                }
                if (ctrl && (keyval == Gdk.Key.y || keyval == Gdk.Key.Y)) {
                    perform_redo ();
                    return true;
                }
                if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) {
                    delete_selected_element ();
                    return true;
                }
                if (keyval == Gdk.Key.Tab) {
                    add_child_to_selected ();
                    return true;
                }
                return false;
            });
            canvas.add_controller (key_ctrl);
        }

        private void set_canvas_zoom (double new_zoom) {
            zoom_factor = double.min (2.0, double.max (0.5, new_zoom));
            zoom_badge_label.label = @"$((int) Math.round (zoom_factor * 100.0))%";
            canvas.queue_draw ();
        }

        private double screen_to_world_x (double sx) {
            return (sx - pan_x) / zoom_factor;
        }

        private double screen_to_world_y (double sy) {
            return (sy - pan_y) / zoom_factor;
        }

        private Core.MermaidNode? find_node_at (double wx, double wy) {
            for (int i = nodes.size - 1; i >= 0; i--) {
                var n = nodes[i];
                double hw = n.width / 2.0;
                double hh = n.height / 2.0;
                if (wx >= n.x - hw && wx <= n.x + hw && wy >= n.y - hh && wy <= n.y + hh) {
                    return n;
                }
            }
            return null;
        }

        private Core.MermaidNode? find_port_owner_at (double wx, double wy) {
            double port_radius = 9.0;
            for (int i = nodes.size - 1; i >= 0; i--) {
                var n = nodes[i];
                double[,] ports = {
                    { n.x, n.y - n.height / 2.0 },
                    { n.x + n.width / 2.0, n.y },
                    { n.x, n.y + n.height / 2.0 },
                    { n.x - n.width / 2.0, n.y }
                };
                for (int p = 0; p < 4; p++) {
                    double dx = wx - ports[p, 0];
                    double dy = wy - ports[p, 1];
                    if (Math.sqrt (dx * dx + dy * dy) <= port_radius) {
                        return n;
                    }
                }
            }
            return null;
        }

        private Core.MermaidEdge? find_edge_at (double wx, double wy) {
            var lookup = new Gee.HashMap<string, Core.MermaidNode> ();
            foreach (var n in nodes) lookup.set (n.id, n);

            for (int i = 0; i < edges.size; i++) {
                var e = edges[i];
                if (!lookup.has_key (e.from_id) || !lookup.has_key (e.to_id)) continue;
                var src = lookup.get (e.from_id);
                var dst = lookup.get (e.to_id);

                double x1 = src.x;
                double y1 = src.y;
                double x2 = dst.x;
                double y2 = dst.y;
                if (current_kind == Core.MermaidDiagramKind.SEQUENCE) {
                    y1 = 150.0 + i * 52.0;
                    y2 = y1;
                }

                double dist = point_to_segment_distance (wx, wy, x1, y1, x2, y2);
                if (dist <= 9.0) {
                    return e;
                }
            }
            return null;
        }

        private double point_to_segment_distance (double px, double py, double x1, double y1, double x2, double y2) {
            double dx = x2 - x1;
            double dy = y2 - y1;
            double len_sq = dx * dx + dy * dy;
            if (len_sq < 1.0) {
                return Math.sqrt ((px - x1) * (px - x1) + (py - y1) * (py - y1));
            }
            double t = ((px - x1) * dx + (py - y1) * dy) / len_sq;
            t = double.min (1.0, double.max (0.0, t));
            double proj_x = x1 + t * dx;
            double proj_y = y1 + t * dy;
            return Math.sqrt ((px - proj_x) * (px - proj_x) + (py - proj_y) * (py - proj_y));
        }

        // =====================================================================
        // GRAPH MANIPULATION ACTIONS
        // =====================================================================
        private void add_node_with_shape (Core.MermaidNodeShape shape) {
            push_undo_snapshot ();
            string new_id = generate_unique_node_id ();
            string default_lbl = "Step " + next_node_seq.to_string ();
            if (shape == Core.MermaidNodeShape.DIAMOND) default_lbl = "Condition?";
            else if (shape == Core.MermaidNodeShape.STADIUM) default_lbl = "Start / End";
            else if (shape == Core.MermaidNodeShape.DATABASE) default_lbl = "Dataset DB";
            else if (shape == Core.MermaidNodeShape.PARALLELOGRAM) default_lbl = "Input Data";
            else if (shape == Core.MermaidNodeShape.CIRCLE) default_lbl = "Topic";

            double nx = 240.0 + (nodes.size % 3) * 190.0;
            double ny = 120.0 + (nodes.size / 3) * 110.0;
            if (selected_node != null) {
                if (current_direction == Core.MermaidFlowDirection.LEFT_RIGHT) {
                    nx = selected_node.x + 210.0;
                    ny = selected_node.y;
                } else {
                    nx = selected_node.x;
                    ny = selected_node.y + 115.0;
                }
            }

            var created = new Core.MermaidNode (new_id, default_lbl, shape, nx, ny);
            if (selected_node != null) {
                created.parent_id = selected_node.id;
                create_edge_between (selected_node, created);
            }
            nodes.add (created);
            selected_node = created;
            selected_edge = null;
            update_inspector_panel ();
            refresh_mermaid_output ();
            canvas.queue_draw ();
        }

        private void add_child_to_selected () {
            if (selected_node == null && nodes.size > 0) {
                selected_node = nodes[0];
            }
            if (selected_node == null) {
                add_node_with_shape (Core.MermaidNodeShape.ROUNDED);
                return;
            }

            push_undo_snapshot ();
            var parent = selected_node;
            string new_id = generate_unique_node_id ();
            var child_shape = (current_kind == Core.MermaidDiagramKind.MINDMAP)
                ? Core.MermaidNodeShape.ROUNDED
                : Core.MermaidNodeShape.RECTANGLE;

            // Count existing children of parent to fan out position cleanly
            int child_count = 0;
            foreach (var e in edges) {
                if (e.from_id == parent.id) child_count++;
            }

            double cx = parent.x + (child_count % 2 == 0 ? 1.0 : -1.0) * ((child_count / 2) * 180.0);
            double cy = parent.y + 115.0;
            if (current_kind == Core.MermaidDiagramKind.MINDMAP) {
                cx = parent.x + (parent.x >= 380.0 ? 210.0 : -210.0);
                cy = parent.y + (child_count - 1) * 75.0;
            } else if (current_direction == Core.MermaidFlowDirection.LEFT_RIGHT) {
                cx = parent.x + 215.0;
                cy = parent.y + (child_count * 85.0);
            }

            var child = new Core.MermaidNode (new_id, "Subtopic " + next_node_seq.to_string (), child_shape, double.max (80.0, cx), double.max (60.0, cy));
            child.parent_id = parent.id;
            nodes.add (child);
            create_edge_between (parent, child);

            selected_node = child;
            selected_edge = null;
            update_inspector_panel ();
            refresh_mermaid_output ();
            canvas.queue_draw ();
        }

        private void add_sibling_to_selected () {
            if (selected_node == null) {
                add_node_with_shape (Core.MermaidNodeShape.RECTANGLE);
                return;
            }

            // Find parent of selected_node
            Core.MermaidNode? parent = null;
            if (selected_node.parent_id.length > 0) {
                foreach (var n in nodes) {
                    if (n.id == selected_node.parent_id) {
                        parent = n;
                        break;
                    }
                }
            }
            if (parent == null) {
                foreach (var e in edges) {
                    if (e.to_id == selected_node.id) {
                        foreach (var n in nodes) {
                            if (n.id == e.from_id) {
                                parent = n;
                                break;
                            }
                        }
                        break;
                    }
                }
            }

            if (parent != null) {
                selected_node = parent;
                add_child_to_selected ();
            } else {
                add_node_with_shape (selected_node.shape);
            }
        }

        private void create_edge_between (Core.MermaidNode src, Core.MermaidNode dst) {
            foreach (var existing in edges) {
                if (existing.from_id == src.id && existing.to_id == dst.id) {
                    selected_edge = existing;
                    return;
                }
            }
            var edge = new Core.MermaidEdge (@"E$(next_edge_seq++)", src.id, dst.id);
            edges.add (edge);
        }

        private void delete_selected_element () {
            if (selected_node != null) {
                push_undo_snapshot ();
                string target_id = selected_node.id;
                nodes.remove (selected_node);
                var to_remove = new Gee.ArrayList<Core.MermaidEdge> ();
                foreach (var e in edges) {
                    if (e.from_id == target_id || e.to_id == target_id) {
                        to_remove.add (e);
                    }
                }
                foreach (var r in to_remove) {
                    edges.remove (r);
                }
                selected_node = null;
                update_inspector_panel ();
                refresh_mermaid_output ();
                canvas.queue_draw ();
            } else if (selected_edge != null) {
                push_undo_snapshot ();
                edges.remove (selected_edge);
                selected_edge = null;
                update_inspector_panel ();
                refresh_mermaid_output ();
                canvas.queue_draw ();
            }
        }

        private string generate_unique_node_id () {
            while (true) {
                string cand = @"N$(next_node_seq++)";
                bool exists = false;
                foreach (var n in nodes) {
                    if (n.id == cand) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) return cand;
            }
        }

        // =====================================================================
        // UNDO / REDO HISTORY
        // =====================================================================
        private GraphSnapshot capture_snapshot () {
            var snap = new GraphSnapshot ();
            snap.kind = current_kind;
            snap.direction = current_direction;
            foreach (var n in nodes) snap.nodes.add (n.clone ());
            foreach (var e in edges) snap.edges.add (e.clone ());
            return snap;
        }

        private void push_undo_snapshot () {
            undo_stack.add (capture_snapshot ());
            if (undo_stack.size > 40) {
                undo_stack.remove_at (0);
            }
            redo_stack.clear ();
            btn_undo.sensitive = (undo_stack.size > 0);
            btn_redo.sensitive = false;
        }

        private void restore_snapshot (GraphSnapshot snap) {
            current_kind = snap.kind;
            current_direction = snap.direction;
            nodes.clear ();
            edges.clear ();
            foreach (var n in snap.nodes) nodes.add (n.clone ());
            foreach (var e in snap.edges) edges.add (e.clone ());
            selected_node = null;
            selected_edge = null;

            syncing_ui = true;
            kind_dropdown.selected = (uint) current_kind;
            direction_dropdown.selected = (uint) current_direction;
            syncing_ui = false;

            update_inspector_panel ();
            refresh_mermaid_output ();
            canvas.queue_draw ();
        }

        private void perform_undo () {
            if (undo_stack.size == 0) return;
            redo_stack.add (capture_snapshot ());
            var prev = undo_stack.remove_at (undo_stack.size - 1);
            restore_snapshot (prev);
            btn_undo.sensitive = (undo_stack.size > 0);
            btn_redo.sensitive = (redo_stack.size > 0);
        }

        private void perform_redo () {
            if (redo_stack.size == 0) return;
            undo_stack.add (capture_snapshot ());
            var next = redo_stack.remove_at (redo_stack.size - 1);
            restore_snapshot (next);
            btn_undo.sensitive = (undo_stack.size > 0);
            btn_redo.sensitive = (redo_stack.size > 0);
        }

        // =====================================================================
        // INSPECTOR & CODE SYNCHRONIZATION
        // =====================================================================
        private void update_inspector_panel () {
            syncing_ui = true;
            if (selected_node != null) {
                inspector_stack.visible_child_name = "node";
                node_label_entry.text = selected_node.label;
                node_shape_dropdown.selected = (uint) selected_node.shape;
                node_subgraph_entry.text = selected_node.subgraph_title;
                update_palette_selection (selected_node.palette);
            } else if (selected_edge != null) {
                inspector_stack.visible_child_name = "edge";
                edge_label_entry.text = selected_edge.label;
                edge_style_dropdown.selected = (uint) selected_edge.style;
            } else {
                inspector_stack.visible_child_name = "none";
            }
            syncing_ui = false;
            update_canvas_status ();
        }

        private void update_palette_selection (Core.MermaidNodePalette active_pal) {
            for (int i = 0; i < 7; i++) {
                if (palette_buttons[i] == null) continue;
                if (i == (int) active_pal) {
                    palette_buttons[i].add_css_class ("is-selected");
                } else {
                    palette_buttons[i].remove_css_class ("is-selected");
                }
            }
        }

        private void update_canvas_status () {
            if (connect_mode_btn.active) {
                if (connect_source_node == null) {
                    canvas_status_label.label = "Connect Mode: Click the SOURCE node on the canvas...";
                } else {
                    canvas_status_label.label = @"Connect Mode: Click the TARGET node to connect from '$(connect_source_node.label)'...";
                }
            } else if (selected_node != null) {
                canvas_status_label.label = @"Selected Node: $(selected_node.label) ($(nodes.size) nodes, $(edges.size) edges) • Drag ○ port to connect";
            } else if (selected_edge != null) {
                canvas_status_label.label = @"Selected Connector: $(selected_edge.from_id) → $(selected_edge.to_id)";
            } else {
                canvas_status_label.label = @"$(nodes.size) nodes • $(edges.size) connectors • Drag node to move • Drag ○ port to connect";
            }
        }

        private void refresh_mermaid_output () {
            string raw = Core.MermaidFlowEngine.generate_mermaid_code (
                current_kind,
                current_direction,
                nodes,
                edges
            );
            var target_fmt = (Core.MermaidTargetFormat) target_format_dropdown.selected;
            string formatted = Core.MermaidFlowEngine.format_for_document (
                raw,
                target_fmt,
                fig_label_entry != null ? fig_label_entry.text : null,
                fig_caption_entry != null ? fig_caption_entry.text : null
            );
            code_view.buffer.text = formatted.strip ();
            update_canvas_status ();
        }

        private void load_from_mermaid_code (string code_text) {
            Core.MermaidDiagramKind parsed_kind;
            Core.MermaidFlowDirection parsed_dir;
            Gee.ArrayList<Core.MermaidNode> parsed_nodes;
            Gee.ArrayList<Core.MermaidEdge> parsed_edges;

            Core.MermaidFlowEngine.parse_mermaid_code (
                code_text,
                out parsed_kind,
                out parsed_dir,
                out parsed_nodes,
                out parsed_edges
            );

            this.current_kind = parsed_kind;
            this.current_direction = parsed_dir;
            this.nodes = parsed_nodes;
            this.edges = parsed_edges;
            this.next_node_seq = nodes.size + 1;
            this.next_edge_seq = edges.size + 1;
            this.selected_node = nodes.size > 0 ? nodes[0] : null;
            this.selected_edge = null;

            syncing_ui = true;
            kind_dropdown.selected = (uint) current_kind;
            direction_dropdown.selected = (uint) current_direction;
            direction_dropdown.sensitive = (current_kind == Core.MermaidDiagramKind.FLOWCHART || current_kind == Core.MermaidDiagramKind.STATE);
            syncing_ui = false;

            update_inspector_panel ();
            refresh_mermaid_output ();
            canvas.queue_draw ();
        }

        private void load_default_starter_diagram () {
            if (presets.size > 0) {
                load_from_mermaid_code (presets[0].mermaid_code);
            }
        }

        private void on_preset_selected () {
            uint idx = preset_dropdown.selected;
            if (idx == 0 || idx > presets.size) return;
            push_undo_snapshot ();
            var preset = presets[(int) idx - 1];
            load_from_mermaid_code (preset.mermaid_code);
            show_studio_toast (@"Loaded preset: $(preset.title)");
        }

        // =====================================================================
        // CAIRO 2D VECTOR INTERACTIVE CANVAS RENDERER
        // =====================================================================
        private void draw_canvas (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            bool is_dark = Adw.StyleManager.get_default ().dark;
            bool is_sepia = Core.SettingsManager.get_default ().app_theme == Core.AppTheme.EYE_FRIENDLY;

            // 1. Background Fill
            if (is_sepia) {
                cr.set_source_rgb (0.980, 0.960, 0.933);
            } else if (is_dark) {
                cr.set_source_rgb (0.118, 0.125, 0.145);
            } else {
                cr.set_source_rgb (0.973, 0.980, 0.988);
            }
            cr.paint ();

            // 2. Subtle Dot Grid (draw.io / Miro / Pantheon style)
            double grid_step = 20.0 * zoom_factor;
            if (grid_step >= 10.0) {
                if (is_dark) {
                    cr.set_source_rgba (1.0, 1.0, 1.0, 0.10);
                } else {
                    cr.set_source_rgba (0.20, 0.25, 0.33, 0.16);
                }
                double offset_x = Math.fmod (pan_x, grid_step);
                double offset_y = Math.fmod (pan_y, grid_step);
                for (double gx = offset_x; gx < width; gx += grid_step) {
                    for (double gy = offset_y; gy < height; gy += grid_step) {
                        cr.arc (gx, gy, 1.2, 0, 2 * Math.PI);
                        cr.fill ();
                    }
                }
            }

            cr.save ();
            cr.translate (pan_x, pan_y);
            cr.scale (zoom_factor, zoom_factor);

            // Build quick node lookup
            var node_lookup = new Gee.HashMap<string, Core.MermaidNode> ();
            foreach (var n in nodes) {
                node_lookup.set (n.id, n);
            }

            // 3. Draw Subgraph Swimlanes if present
            draw_subgraphs (cr, is_dark);

            // 4. Draw Sequence Diagram Lifelines if in SEQUENCE mode
            if (current_kind == Core.MermaidDiagramKind.SEQUENCE) {
                draw_sequence_diagram (cr, is_dark, node_lookup);
            } else {
                // 5. Draw Edges / Mindmap Branches
                foreach (var e in edges) {
                    if (!node_lookup.has_key (e.from_id) || !node_lookup.has_key (e.to_id)) continue;
                    var src = node_lookup.get (e.from_id);
                    var dst = node_lookup.get (e.to_id);
                    draw_edge (cr, e, src, dst, is_dark);
                }
            }

            // 6. Draw Live Dragging Connection Wire if active
            if (is_dragging_wire && connect_source_node != null) {
                cr.save ();
                cr.set_source_rgba (0.208, 0.518, 0.894, 0.90);
                cr.set_line_width (2.2);
                cr.set_dash ({ 6.0, 4.0 }, 0);
                cr.move_to (connect_source_node.x, connect_source_node.y);
                cr.line_to (wire_cursor_x, wire_cursor_y);
                cr.stroke ();
                cr.restore ();
                draw_arrowhead (cr, connect_source_node.x, connect_source_node.y, wire_cursor_x, wire_cursor_y, 0.208, 0.518, 0.894);
            }

            // 7. Draw Nodes and Interactive Connection Ports
            foreach (var n in nodes) {
                draw_node (cr, n, is_dark);
            }

            cr.restore ();
        }

        private void draw_subgraphs (Cairo.Context cr, bool is_dark) {
            var groups = new Gee.HashMap<string, Gee.ArrayList<Core.MermaidNode>> ();
            foreach (var n in nodes) {
                string sg = n.subgraph_title.strip ();
                if (sg.length > 0) {
                    if (!groups.has_key (sg)) {
                        groups.set (sg, new Gee.ArrayList<Core.MermaidNode> ());
                    }
                    groups.get (sg).add (n);
                }
            }

            foreach (var entry in groups.entries) {
                double min_x = 1e9, min_y = 1e9, max_x = -1e9, max_y = -1e9;
                foreach (var n in entry.value) {
                    if (n.x - n.width / 2.0 < min_x) min_x = n.x - n.width / 2.0;
                    if (n.y - n.height / 2.0 < min_y) min_y = n.y - n.height / 2.0;
                    if (n.x + n.width / 2.0 > max_x) max_x = n.x + n.width / 2.0;
                    if (n.y + n.height / 2.0 > max_y) max_y = n.y + n.height / 2.0;
                }
                double pad = 26.0;
                double bx = min_x - pad;
                double by = min_y - pad - 12.0;
                double bw = (max_x - min_x) + pad * 2.0;
                double bh = (max_y - min_y) + pad * 2.0 + 12.0;

                cr.save ();
                draw_rounded_rect_path (cr, bx, by, bw, bh, 10.0);
                if (is_dark) {
                    cr.set_source_rgba (0.208, 0.518, 0.894, 0.08);
                } else {
                    cr.set_source_rgba (0.208, 0.518, 0.894, 0.06);
                }
                cr.fill_preserve ();
                cr.set_source_rgba (0.208, 0.518, 0.894, 0.45);
                cr.set_line_width (1.5);
                cr.set_dash ({ 6.0, 4.0 }, 0);
                cr.stroke ();
                cr.restore ();

                draw_centered_text (cr, entry.key, bx + bw / 2.0, by + 14.0, true, 10.5, 0.208, 0.518, 0.894);
            }
        }

        private void draw_sequence_diagram (
            Cairo.Context cr,
            bool is_dark,
            Gee.HashMap<string, Core.MermaidNode> node_lookup
        ) {
            double bottom_y = 180.0 + edges.size * 54.0;
            foreach (var n in nodes) {
                cr.save ();
                if (is_dark) {
                    cr.set_source_rgba (0.70, 0.76, 0.84, 0.35);
                } else {
                    cr.set_source_rgba (0.30, 0.36, 0.45, 0.40);
                }
                cr.set_line_width (1.5);
                cr.set_dash ({ 5.0, 4.0 }, 0);
                cr.move_to (n.x, n.y + n.height / 2.0);
                cr.line_to (n.x, bottom_y);
                cr.stroke ();
                cr.restore ();
            }

            for (int i = 0; i < edges.size; i++) {
                var e = edges[i];
                if (!node_lookup.has_key (e.from_id) || !node_lookup.has_key (e.to_id)) continue;
                var src = node_lookup.get (e.from_id);
                var dst = node_lookup.get (e.to_id);
                double y = 150.0 + i * 52.0;

                bool is_sel = (selected_edge == e);
                double r = is_sel ? 0.208 : (is_dark ? 0.82 : 0.28);
                double g = is_sel ? 0.518 : (is_dark ? 0.86 : 0.33);
                double b = is_sel ? 0.894 : (is_dark ? 0.92 : 0.41);

                cr.save ();
                cr.set_source_rgb (r, g, b);
                cr.set_line_width (is_sel ? 2.8 : 2.0);
                if (e.style == Core.MermaidEdgeStyle.DOTTED_ARROW) {
                    cr.set_dash ({ 6.0, 4.0 }, 0);
                }
                cr.move_to (src.x, y);
                cr.line_to (dst.x, y);
                cr.stroke ();
                cr.restore ();

                draw_arrowhead (cr, src.x, y, dst.x, y, r, g, b);

                string msg_text = @"$(i + 1). $(e.label.length > 0 ? e.label : "call")";
                draw_centered_text (cr, msg_text, (src.x + dst.x) / 2.0, y - 10.0, true, 10.0, r, g, b);
            }
        }

        private void draw_edge (
            Cairo.Context cr,
            Core.MermaidEdge e,
            Core.MermaidNode src,
            Core.MermaidNode dst,
            bool is_dark
        ) {
            bool is_sel = (selected_edge == e);
            double r = is_sel ? 0.208 : (is_dark ? 0.74 : 0.34);
            double g = is_sel ? 0.518 : (is_dark ? 0.80 : 0.40);
            double b = is_sel ? 0.894 : (is_dark ? 0.88 : 0.49);

            double sx, sy, tx, ty;
            compute_boundary_point (src, dst.x, dst.y, out sx, out sy);
            compute_boundary_point (dst, src.x, src.y, out tx, out ty);

            cr.save ();
            cr.set_source_rgb (r, g, b);
            double lw = (e.style == Core.MermaidEdgeStyle.THICK_ARROW) ? 3.4 : (is_sel ? 2.8 : 2.0);
            cr.set_line_width (lw);
            if (e.style == Core.MermaidEdgeStyle.DOTTED_ARROW) {
                cr.set_dash ({ 6.0, 4.0 }, 0);
            }

            if (current_kind == Core.MermaidDiagramKind.MINDMAP) {
                double mid_x = (sx + tx) / 2.0;
                cr.move_to (sx, sy);
                cr.curve_to (mid_x, sy, mid_x, ty, tx, ty);
                cr.stroke ();
            } else {
                cr.move_to (sx, sy);
                cr.line_to (tx, ty);
                cr.stroke ();
            }
            cr.restore ();

            if (current_kind != Core.MermaidDiagramKind.MINDMAP && e.style != Core.MermaidEdgeStyle.SOLID_LINE) {
                draw_arrowhead (cr, sx, sy, tx, ty, r, g, b);
                if (e.style == Core.MermaidEdgeStyle.BIDIRECTIONAL) {
                    draw_arrowhead (cr, tx, ty, sx, sy, r, g, b);
                }
            }

            if (e.label.strip ().length > 0) {
                double mx = (sx + tx) / 2.0;
                double my = (sy + ty) / 2.0;
                double pill_w = double.max (38.0, e.label.char_count () * 7.2 + 14.0);
                double pill_h = 20.0;

                cr.save ();
                draw_rounded_rect_path (cr, mx - pill_w / 2.0, my - pill_h / 2.0, pill_w, pill_h, 9.0);
                if (is_dark) {
                    cr.set_source_rgb (0.18, 0.20, 0.24);
                } else {
                    cr.set_source_rgb (1.0, 1.0, 1.0);
                }
                cr.fill_preserve ();
                cr.set_source_rgb (r, g, b);
                cr.set_line_width (1.2);
                cr.stroke ();
                cr.restore ();

                draw_centered_text (cr, e.label.strip (), mx, my, false, 9.5, r, g, b);
            }
        }

        private void compute_boundary_point (
            Core.MermaidNode node,
            double target_x,
            double target_y,
            out double bx,
            out double by
        ) {
            double dx = target_x - node.x;
            double dy = target_y - node.y;
            if (Math.fabs (dx) < 0.001 && Math.fabs (dy) < 0.001) {
                bx = node.x;
                by = node.y;
                return;
            }

            double hw = node.width / 2.0;
            double hh = node.height / 2.0;

            if (node.shape == Core.MermaidNodeShape.CIRCLE) {
                double len = Math.sqrt (dx * dx + dy * dy);
                bx = node.x + (dx / len) * hw;
                by = node.y + (dy / len) * hh;
                return;
            }

            if (node.shape == Core.MermaidNodeShape.DIAMOND) {
                double denom = Math.fabs (dx) / hw + Math.fabs (dy) / hh;
                double scale = denom > 0.0 ? (1.0 / denom) : 1.0;
                bx = node.x + dx * scale;
                by = node.y + dy * scale;
                return;
            }

            double tx = Math.fabs (dx) > 0.001 ? hw / Math.fabs (dx) : 1e9;
            double ty = Math.fabs (dy) > 0.001 ? hh / Math.fabs (dy) : 1e9;
            double t = double.min (tx, ty);
            bx = node.x + dx * t;
            by = node.y + dy * t;
        }

        private void draw_arrowhead (
            Cairo.Context cr,
            double x1,
            double y1,
            double x2,
            double y2,
            double r,
            double g,
            double b
        ) {
            double angle = Math.atan2 (y2 - y1, x2 - x1);
            double arrow_len = 10.5;
            double arrow_ang = 0.46;

            cr.save ();
            cr.set_source_rgb (r, g, b);
            cr.move_to (x2, y2);
            cr.line_to (x2 - arrow_len * Math.cos (angle - arrow_ang), y2 - arrow_len * Math.sin (angle - arrow_ang));
            cr.line_to (x2 - arrow_len * Math.cos (angle + arrow_ang), y2 - arrow_len * Math.sin (angle + arrow_ang));
            cr.close_path ();
            cr.fill ();
            cr.restore ();
        }

        private void draw_node (Cairo.Context cr, Core.MermaidNode n, bool is_dark) {
            bool is_sel = (selected_node == n) || (connect_source_node == n);
            bool is_hov = (hovered_node == n);
            double x = n.x - n.width / 2.0;
            double y = n.y - n.height / 2.0;
            double w = n.width;
            double h = n.height;

            // 1. Subtle Elevation Shadow
            cr.save ();
            draw_node_shape_path (cr, n.shape, x, y + 2.5, w, h);
            cr.set_source_rgba (0.0, 0.0, 0.0, is_dark ? 0.35 : 0.10);
            cr.fill ();
            cr.restore ();

            // 2. Node Fill & Stroke Colors
            Gdk.RGBA fill_rgba = Gdk.RGBA ();
            Gdk.RGBA stroke_rgba = Gdk.RGBA ();
            Gdk.RGBA text_rgba = Gdk.RGBA ();

            if (n.palette == Core.MermaidNodePalette.DEFAULT && is_dark) {
                fill_rgba.parse ("#262932");
                stroke_rgba.parse ("#64748b");
                text_rgba.parse ("#f1f5f9");
            } else {
                fill_rgba.parse (n.palette.get_fill_hex ());
                stroke_rgba.parse (n.palette.get_stroke_hex ());
                text_rgba.parse (n.palette.get_text_hex ());
            }

            cr.save ();
            draw_node_shape_path (cr, n.shape, x, y, w, h);
            cr.set_source_rgb (fill_rgba.red, fill_rgba.green, fill_rgba.blue);
            cr.fill_preserve ();

            if (is_sel) {
                cr.set_source_rgb (0.208, 0.518, 0.894);
                cr.set_line_width (3.0);
            } else {
                cr.set_source_rgb (stroke_rgba.red, stroke_rgba.green, stroke_rgba.blue);
                cr.set_line_width (2.0);
            }
            cr.stroke ();

            // Extra interior details for Database Cylinder and Subroutine
            if (n.shape == Core.MermaidNodeShape.DATABASE) {
                double cap_ry = 8.0;
                cr.save ();
                cr.translate (n.x, y + cap_ry);
                cr.scale (w / 2.0, cap_ry);
                cr.arc (0.0, 0.0, 1.0, 0.0, Math.PI);
                cr.restore ();
                cr.stroke ();
            } else if (n.shape == Core.MermaidNodeShape.SUBROUTINE) {
                cr.move_to (x + 10.0, y);
                cr.line_to (x + 10.0, y + h);
                cr.move_to (x + w - 10.0, y);
                cr.line_to (x + w - 10.0, y + h);
                cr.stroke ();
            }
            cr.restore ();

            // 3. Selection Focus Ring
            if (is_sel) {
                cr.save ();
                draw_node_shape_path (cr, n.shape, x - 3.5, y - 3.5, w + 7.0, h + 7.0);
                cr.set_source_rgba (0.208, 0.518, 0.894, 0.35);
                cr.set_line_width (2.0);
                cr.stroke ();
                cr.restore ();
            }

            // 4. Node Label via PangoCairo
            draw_centered_text (cr, n.label, n.x, n.y, true, 10.5, text_rgba.red, text_rgba.green, text_rgba.blue);

            // 5. Interactive Connection Port Handles (North, East, South, West) on Hover or Selection
            if (is_sel || is_hov || is_dragging_wire) {
                double[,] ports = {
                    { n.x, y },
                    { x + w, n.y },
                    { n.x, y + h },
                    { x, n.y }
                };
                for (int p = 0; p < 4; p++) {
                    cr.save ();
                    cr.arc (ports[p, 0], ports[p, 1], 5.2, 0, 2 * Math.PI);
                    cr.set_source_rgb (1.0, 1.0, 1.0);
                    cr.fill_preserve ();
                    cr.set_source_rgb (0.208, 0.518, 0.894);
                    cr.set_line_width (2.0);
                    cr.stroke ();
                    cr.restore ();
                }
            }
        }

        private void draw_node_shape_path (
            Cairo.Context cr,
            Core.MermaidNodeShape shape,
            double x,
            double y,
            double w,
            double h
        ) {
            cr.new_path ();
            switch (shape) {
                case Core.MermaidNodeShape.CIRCLE:
                    double r = double.min (w, h) / 2.0;
                    cr.arc (x + w / 2.0, y + h / 2.0, r, 0, 2 * Math.PI);
                    cr.close_path ();
                    break;

                case Core.MermaidNodeShape.STADIUM:
                    draw_rounded_rect_path (cr, x, y, w, h, h / 2.0);
                    break;

                case Core.MermaidNodeShape.ROUNDED:
                case Core.MermaidNodeShape.CLOUD:
                    draw_rounded_rect_path (cr, x, y, w, h, 14.0);
                    break;

                case Core.MermaidNodeShape.DIAMOND:
                    cr.move_to (x + w / 2.0, y);
                    cr.line_to (x + w, y + h / 2.0);
                    cr.line_to (x + w / 2.0, y + h);
                    cr.line_to (x, y + h / 2.0);
                    cr.close_path ();
                    break;

                case Core.MermaidNodeShape.HEXAGON:
                    double inset = 16.0;
                    cr.move_to (x + inset, y);
                    cr.line_to (x + w - inset, y);
                    cr.line_to (x + w, y + h / 2.0);
                    cr.line_to (x + w - inset, y + h);
                    cr.line_to (x + inset, y + h);
                    cr.line_to (x, y + h / 2.0);
                    cr.close_path ();
                    break;

                case Core.MermaidNodeShape.PARALLELOGRAM:
                    double slant = 14.0;
                    cr.move_to (x + slant, y);
                    cr.line_to (x + w, y);
                    cr.line_to (x + w - slant, y + h);
                    cr.line_to (x, y + h);
                    cr.close_path ();
                    break;

                default:
                    draw_rounded_rect_path (cr, x, y, w, h, 6.0);
                    break;
            }
        }

        private void draw_rounded_rect_path (Cairo.Context cr, double x, double y, double w, double h, double radius) {
            double r = double.min (radius, double.min (w / 2.0, h / 2.0));
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2.0, 0.0);
            cr.arc (x + w - r, y + h - r, r, 0.0, Math.PI / 2.0);
            cr.arc (x + r, y + h - r, r, Math.PI / 2.0, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3.0 * Math.PI / 2.0);
            cr.close_path ();
        }

        private void draw_centered_text (
            Cairo.Context cr,
            string text,
            double cx,
            double cy,
            bool bold,
            double pt_size,
            double r,
            double g,
            double b
        ) {
            var layout = Pango.cairo_create_layout (cr);
            var desc = new Pango.FontDescription ();
            desc.set_family ("Inter, Cantarell, Sans");
            desc.set_weight (bold ? Pango.Weight.SEMIBOLD : Pango.Weight.NORMAL);
            desc.set_size ((int) (pt_size * Pango.SCALE));
            layout.set_font_description (desc);
            layout.set_text (text, -1);

            int tw, th;
            layout.get_pixel_size (out tw, out th);

            cr.save ();
            cr.set_source_rgb (r, g, b);
            cr.move_to (cx - tw / 2.0, cy - th / 2.0);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }

        // =====================================================================
        // EXPORT & INSERTION HANDLERS
        // =====================================================================
        private void on_copy_code_clicked () {
            string text = code_view.buffer.text;
            var clipboard = this.get_clipboard ();
            clipboard.set_text (text);
            show_studio_toast ("Copied Mermaid block to clipboard");
        }

        private async void export_svg_async () {
            var dialog = new Gtk.FileDialog () {
                title = "Export Diagram as Vector SVG",
                initial_name = "imladris-diagram.svg",
                modal = true
            };
            var parent_win = this.get_root () as Gtk.Window;
            try {
                var file = yield dialog.save (parent_win, null);
                if (file != null && file.get_path () != null) {
                    string svg = Core.MermaidFlowEngine.export_to_svg (nodes, edges);
                    GLib.FileUtils.set_contents (file.get_path (), svg);
                    show_studio_toast (@"Exported vector SVG to $(file.get_basename ())");
                }
            } catch (GLib.Error e) {
                // User cancelled dialog
            }
        }

        private void emit_and_close (bool save_doc) {
            string raw = Core.MermaidFlowEngine.generate_mermaid_code (
                current_kind,
                current_direction,
                nodes,
                edges
            );
            var target_fmt = (Core.MermaidTargetFormat) target_format_dropdown.selected;
            string output = Core.MermaidFlowEngine.format_for_document (
                raw,
                target_fmt,
                fig_label_entry.text,
                fig_caption_entry.text
            );
            diagram_inserted (output, save_doc);
            this.close ();
        }

        private void show_studio_toast (string msg) {
            if (toast_overlay != null) {
                toast_overlay.add_toast (new Adw.Toast (msg));
            }
        }
    }
}
