// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris {

    public delegate void TableInsertCallback (int rows, int cols);
    public delegate void ColorSelectCallback (string hex_color);

    public class PopoverFactory : Object {
        private const int MAX_GRID_ROWS = 8;
        private const int MAX_GRID_COLS = 8;

        private static void highlight_table_cells (Gtk.Button[,] cells, Gtk.Label status_lbl, int target_r, int target_c) {
            for (int rr = 0; rr < MAX_GRID_ROWS; rr++) {
                for (int cc = 0; cc < MAX_GRID_COLS; cc++) {
                    if (rr < target_r && cc < target_c) {
                        cells[rr, cc].add_css_class ("table-cell-selected");
                    } else {
                        cells[rr, cc].remove_css_class ("table-cell-selected");
                    }
                }
            }
            if (target_r > 0 && target_c > 0) {
                status_lbl.label = @"Insert $(target_r) × $(target_c) Table";
            } else {
                status_lbl.label = "Insert Table (Hover or Choose Size)";
            }
        }

        /**
         * Builds an interactive 8x8 Table Grid Picker Popover with live hover preview
         * and custom Row/Column spinbuttons for arbitrary table dimensions.
         */
        public static Gtk.Popover create_table_picker_popover (owned TableInsertCallback cb) {
            var popover = new Gtk.Popover ();
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 10,
                margin_bottom = 10,
                margin_start = 10,
                margin_end = 10
            };

            var status_lbl = new Gtk.Label ("Insert Table (Hover or Choose Size)") {
                css_classes = { "heading" }
            };
            vbox.append (status_lbl);

            var grid = new Gtk.Grid () {
                row_spacing = 3,
                column_spacing = 3,
                halign = Gtk.Align.CENTER
            };

            var cells = new Gtk.Button[MAX_GRID_ROWS, MAX_GRID_COLS];
            var rows_spin = new Gtk.SpinButton.with_range (1, 50, 1) {
                value = 3,
                width_chars = 3,
                tooltip_text = "Number of data rows"
            };
            var cols_spin = new Gtk.SpinButton.with_range (1, 20, 1) {
                value = 3,
                width_chars = 3,
                tooltip_text = "Number of columns"
            };

            var grid_motion = new Gtk.EventControllerMotion ();
            grid_motion.leave.connect (() => {
                highlight_table_cells (cells, status_lbl, 0, 0);
            });
            grid.add_controller (grid_motion);

            for (int r = 1; r <= MAX_GRID_ROWS; r++) {
                for (int c = 1; c <= MAX_GRID_COLS; c++) {
                    int row_val = r;
                    int col_val = c;
                    var cell_btn = new Gtk.Button () {
                        tooltip_text = @"$row_val × $col_val Table",
                        can_focus = false
                    };
                    cell_btn.add_css_class ("table-cell-btn");

                    var motion = new Gtk.EventControllerMotion ();
                    motion.enter.connect (() => {
                        highlight_table_cells (cells, status_lbl, row_val, col_val);
                    });
                    cell_btn.add_controller (motion);

                    cell_btn.clicked.connect (() => {
                        popover.popdown ();
                        cb (row_val, col_val);
                    });
                    cells[r - 1, c - 1] = cell_btn;
                    grid.attach (cell_btn, c - 1, r - 1, 1, 1);
                }
            }

            vbox.append (grid);
            vbox.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var custom_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                halign = Gtk.Align.CENTER
            };
            custom_box.append (new Gtk.Label ("Rows:") { css_classes = { "dim-label", "caption" } });
            custom_box.append (rows_spin);
            custom_box.append (new Gtk.Label ("×") { css_classes = { "dim-label" } });
            custom_box.append (new Gtk.Label ("Cols:") { css_classes = { "dim-label", "caption" } });
            custom_box.append (cols_spin);

            var insert_btn = new Gtk.Button.with_label ("Insert") {
                tooltip_text = "Insert table with specified rows and columns"
            };
            insert_btn.add_css_class ("suggested-action");

            insert_btn.clicked.connect (() => {
                int r_count = rows_spin.get_value_as_int ();
                int c_count = cols_spin.get_value_as_int ();
                popover.popdown ();
                cb (r_count, c_count);
            });
            rows_spin.activate.connect (() => {
                insert_btn.activate ();
            });
            cols_spin.activate.connect (() => {
                insert_btn.activate ();
            });

            custom_box.append (insert_btn);
            vbox.append (custom_box);

            popover.set_child (vbox);
            popover.set_default_widget (insert_btn);
            return popover;
        }

        /**
         * Builds a Color Palette Swatch Popover for text foreground or background highlighting.
         */
        public static Gtk.Popover create_color_palette_popover (owned ColorSelectCallback cb) {
            var popover = new Gtk.Popover ();
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8
            };

            vbox.append (new Gtk.Label ("Select Color"));

            string[] colors = {
                "#000000", "#e01b24", "#ff7800", "#f6d32d",
                "#2ec27e", "#3584e4", "#9141ac", "#ffffff"
            };

            var flow = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            foreach (string hex in colors) {
                string target_hex = hex;
                var btn = new Gtk.Button () {
                    tooltip_text = target_hex
                };
                btn.add_css_class ("color-swatch-btn");
                btn.clicked.connect (() => {
                    popover.popdown ();
                    cb (target_hex);
                });
                flow.append (btn);
            }

            vbox.append (flow);
            popover.set_child (vbox);
            return popover;
        }
    }
}
