// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Interactive tabular data viewer for R and Python dataframes.
 *
 * Architectural Position:
 * Core analytical UI quadrant. Visualizes matrices and dataframes from active sessions.
 * Downstream consumers: Imladris.Window, Imladris.EnvironmentPanel.
 * Upstream dependencies: gtk4, libadwaita-1, gee-0.8, Imladris.Services.PersistentSessionManager.
 *
 * Concurrency Constraints:
 * Executes asynchronous dataframe slice queries via PersistentSessionManager.
 * Renders virtualized Gtk.ColumnView cells strictly on the GLib MainContext thread.
 */

using GLib;
using Gtk;
using Adw;

namespace Imladris.UI {

    /**
     * DataRow
     * Object-backed row model for virtualized Gtk.ColumnView.
     */
    public class DataRow : GLib.Object {
        public int row_index { get; construct set; }
        public string[] cells { get; construct set; }

        public DataRow (int index, string[] values) {
            Object (row_index: index, cells: values);
        }

        public string get_cell (int col_idx) {
            if (col_idx >= 0 && col_idx < cells.length) {
                return cells[col_idx];
            }
            return "";
        }
    }

    /**
     * DataGridViewer
     * Virtualized Libadwaita Dataframe & Matrix Grid Viewer.
     * Backed by Gtk.ColumnView + Gio.ListStore with vectorized pagination.
     */
    public class DataGridViewer : Gtk.Box {

        public string active_object_name { get; private set; default = ""; }
        public string active_engine { get; private set; default = "r"; }

        private Gtk.Label title_label;
        private Gtk.Label dim_badge;
        private Gtk.SearchEntry search_entry;
        private Gtk.ColumnView column_view;
        private GLib.ListStore list_store;
        private Gtk.FilterListModel filter_model;
        private Gtk.SortListModel sort_model;
        private Gtk.SingleSelection selection_model;
        private Gtk.CustomFilter search_filter;

        private Gtk.Button btn_refresh;
        private Gtk.Button btn_popout;
        private Gtk.Button btn_copy;
        private Gtk.Button btn_prev_page;
        private Gtk.Button btn_next_page;
        private Gtk.Label page_label;
        private Gtk.Spinner loading_spinner;

        private string[] current_col_names;
        private Gee.ArrayList<DataRow> all_rows;
        private Adw.Window? popout_win = null;

        private int current_offset = 0;
        private int page_size = 1000;
        private int total_df_rows = 0;
        private int total_df_cols = 0;

        public signal void close_requested ();

        public DataGridViewer () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.hexpand = true;
            this.vexpand = true;
            this.add_css_class ("data-grid-viewer");

            current_col_names = new string[0];
            all_rows = new Gee.ArrayList<DataRow> ();

            setup_toolbar ();
            setup_grid_view ();
            load_empty_placeholder ();
        }

        private static bool is_safe_identifier (string name) {
            return GLib.Regex.match_simple ("^[A-Za-z_][A-Za-z0-9_.$\\[\\]]*$", name.strip ());
        }

        private void setup_toolbar () {
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            toolbar.add_css_class ("dock-subtoolbar");

            var icon = new Gtk.Image.from_icon_name ("view-grid-symbolic");
            toolbar.append (icon);

            title_label = new Gtk.Label ("No Object Loaded") {
                css_classes = { "heading" },
                xalign = 0
            };
            toolbar.append (title_label);

            dim_badge = new Gtk.Label ("0 rows × 0 cols") {
                css_classes = { "dim-label", "caption", "pill" },
                margin_start = 4
            };
            toolbar.append (dim_badge);

            loading_spinner = new Gtk.Spinner () {
                spinning = false,
                visible = false,
                margin_start = 4
            };
            toolbar.append (loading_spinner);

            toolbar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            // Pagination Controls
            btn_prev_page = new Gtk.Button.from_icon_name ("go-previous-symbolic") {
                tooltip_text = "Previous Page (1,000 Rows)",
                sensitive = false
            };
            btn_prev_page.add_css_class ("flat");
            btn_prev_page.clicked.connect (() => {
                if (current_offset >= page_size) {
                    current_offset -= page_size;
                    fetch_page_slice.begin ();
                }
            });
            toolbar.append (btn_prev_page);

            page_label = new Gtk.Label ("Page 1") {
                css_classes = { "caption", "dim-label" },
                margin_start = 2,
                margin_end = 2
            };
            toolbar.append (page_label);

            btn_next_page = new Gtk.Button.from_icon_name ("go-next-symbolic") {
                tooltip_text = "Next Page (1,000 Rows)",
                sensitive = false
            };
            btn_next_page.add_css_class ("flat");
            btn_next_page.clicked.connect (() => {
                if (current_offset + page_size < total_df_rows) {
                    current_offset += page_size;
                    fetch_page_slice.begin ();
                }
            });
            toolbar.append (btn_next_page);

            search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Filter current page...",
                width_request = 170
            };
            search_entry.search_changed.connect (() => {
                if (search_filter != null) {
                    search_filter.changed (Gtk.FilterChange.DIFFERENT);
                }
                update_status_dimensions ();
            });
            toolbar.append (search_entry);

            btn_refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh Dataframe Slice"
            };
            btn_refresh.add_css_class ("flat");
            btn_refresh.clicked.connect (() => {
                if (active_object_name != "") {
                    fetch_and_display.begin (active_object_name, active_engine);
                }
            });
            toolbar.append (btn_refresh);

            btn_copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy Current Page TSV to Clipboard"
            };
            btn_copy.add_css_class ("flat");
            btn_copy.clicked.connect (copy_to_clipboard);
            toolbar.append (btn_copy);

            btn_popout = new Gtk.Button.from_icon_name ("window-new-symbolic") {
                tooltip_text = "Pop-out into Standalone Window"
            };
            btn_popout.add_css_class ("flat");
            btn_popout.clicked.connect (() => {
                popout_window (null);
            });
            toolbar.append (btn_popout);

            this.append (toolbar);
        }

        private void setup_grid_view () {
            list_store = new GLib.ListStore (typeof (DataRow));

            search_filter = new Gtk.CustomFilter ((item) => {
                string query = search_entry.text.strip ().down ();
                if (query.length == 0) return true;
                var row = item as DataRow;
                if (row == null) return false;
                foreach (var c in row.cells) {
                    if (c.down ().contains (query)) return true;
                }
                return false;
            });

            filter_model = new Gtk.FilterListModel (list_store, search_filter);
            sort_model = new Gtk.SortListModel (filter_model, null);
            selection_model = new Gtk.SingleSelection (sort_model);

            column_view = new Gtk.ColumnView (selection_model) {
                show_row_separators = true,
                show_column_separators = true,
                reorderable = true
            };
            column_view.add_css_class ("data-grid-table");

            sort_model.sorter = column_view.sorter;

            var scroller = new Gtk.ScrolledWindow () {
                child = column_view,
                hexpand = true,
                vexpand = true,
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
            };

            this.append (scroller);
        }

        private void load_empty_placeholder () {
            string[] cols = { "#", "Info" };
            var rows = new Gee.ArrayList<DataRow> ();
            rows.add (new DataRow (1, new string[] { "—", "Use View(dataframe) in R/Python or click 'View Data' in the Environment panel to inspect dataframes." }));
            populate_grid_data ("", cols, rows);
            title_label.label = "No Object Loaded";
            dim_badge.label = "0 rows × 0 cols";
            update_pagination_ui ();
        }

        public void populate_grid_data (string object_name, string[] col_names, Gee.ArrayList<DataRow> rows) {
            this.active_object_name = object_name;
            this.current_col_names = col_names;
            title_label.label = (object_name != "") ? object_name : "No Object Loaded";

            // Remove existing columns safely in reverse order
            var cols_model = column_view.get_columns ();
            uint n_cols = cols_model.get_n_items ();
            for (int i = (int) n_cols - 1; i >= 0; i--) {
                var col = cols_model.get_item ((uint) i) as Gtk.ColumnViewColumn;
                if (col != null) {
                    column_view.remove_column (col);
                }
            }

            // Create index column "#"
            var idx_factory = new Gtk.SignalListItemFactory ();
            idx_factory.setup.connect ((item) => {
                var list_item = (Gtk.ColumnViewCell) item;
                var lbl = new Gtk.Label ("") {
                    xalign = 1,
                    margin_start = 8,
                    margin_end = 8,
                    css_classes = { "dim-label", "monospace", "caption" }
                };
                list_item.set_child (lbl);
            });
            idx_factory.bind.connect ((item) => {
                var list_item = (Gtk.ColumnViewCell) item;
                var row = list_item.get_item () as DataRow;
                var lbl = list_item.get_child () as Gtk.Label;
                if (row != null && lbl != null) {
                    lbl.label = @"$(row.row_index)";
                }
            });

            var idx_sorter = new Gtk.CustomSorter ((a, b) => {
                var ra = a as DataRow;
                var rb = b as DataRow;
                if (ra == null || rb == null) return 0;
                return ra.row_index - rb.row_index;
            });

            var idx_col = new Gtk.ColumnViewColumn ("#", idx_factory) {
                sorter = idx_sorter,
                resizable = false
            };
            column_view.append_column (idx_col);

            // Add dynamic columns
            for (int i = 0; i < col_names.length; i++) {
                int col_index = i;
                string cname = col_names[i];

                var factory = new Gtk.SignalListItemFactory ();
                factory.setup.connect ((item) => {
                    var list_item = (Gtk.ColumnViewCell) item;
                    var lbl = new Gtk.Label ("") {
                        xalign = 0,
                        selectable = true,
                        margin_start = 6,
                        margin_end = 6,
                        css_classes = { "monospace", "body" }
                    };
                    list_item.set_child (lbl);
                });
                factory.bind.connect ((item) => {
                    var list_item = (Gtk.ColumnViewCell) item;
                    var row = list_item.get_item () as DataRow;
                    var lbl = list_item.get_child () as Gtk.Label;
                    if (row != null && lbl != null) {
                        lbl.label = row.get_cell (col_index);
                    }
                });

                var col_sorter = new Gtk.CustomSorter ((a, b) => {
                    var ra = a as DataRow;
                    var rb = b as DataRow;
                    if (ra == null || rb == null) return 0;
                    string sa = ra.get_cell (col_index);
                    string sb = rb.get_cell (col_index);
                    double da = 0.0, db = 0.0;
                    if (double.try_parse (sa, out da) && double.try_parse (sb, out db)) {
                        if (da < db) return -1;
                        if (da > db) return 1;
                        return 0;
                    }
                    return GLib.strcmp (sa, sb);
                });

                var cv_col = new Gtk.ColumnViewColumn (cname, factory) {
                    sorter = col_sorter,
                    resizable = true
                };
                column_view.append_column (cv_col);
            }

            // Populate rows
            list_store.remove_all ();
            all_rows.clear ();

            foreach (var r in rows) {
                all_rows.add (r);
                list_store.append (r);
            }

            update_status_dimensions ();
            update_pagination_ui ();
        }

        private void update_status_dimensions () {
            uint visible_count = filter_model.get_n_items ();
            int total_cols = current_col_names.length;

            if (total_df_rows > 0) {
                int start_row = current_offset + 1;
                int end_row = int.min (current_offset + page_size, total_df_rows);
                dim_badge.label = @"Rows $start_row–$end_row of $total_df_rows • $total_cols cols";
            } else {
                dim_badge.label = @"$(visible_count) rows • $total_cols cols";
            }
        }

        private void update_pagination_ui () {
            btn_prev_page.sensitive = (current_offset > 0);
            btn_next_page.sensitive = (current_offset + page_size < total_df_rows);

            int page_idx = (current_offset / page_size) + 1;
            int total_pages = (total_df_rows > 0) ? (int) GLib.Math.ceil ((double) total_df_rows / page_size) : 1;
            page_label.label = @"$page_idx / $total_pages";
        }

        public async void fetch_and_display (string object_name, string engine = "r") {
            this.active_object_name = object_name;
            this.active_engine = engine;
            this.current_offset = 0;
            yield fetch_page_slice ();
        }

        private async void fetch_page_slice () {
            if (active_object_name == "") return;

            if (!is_safe_identifier (active_object_name)) {
                title_label.label = "Invalid Identifier";
                dim_badge.label = "Rejected";
                return;
            }

            title_label.label = @"Loading $active_object_name...";
            loading_spinner.visible = true;
            loading_spinner.spinning = true;

            if (active_engine == "r") {
                yield fetch_r_dataframe (active_object_name);
            } else {
                yield fetch_python_dataframe (active_object_name);
            }

            loading_spinner.spinning = false;
            loading_spinner.visible = false;
        }

        private async void fetch_r_dataframe (string obj_name) {
            int start_row = current_offset + 1;
            int end_row = current_offset + page_size;

            string r_code = """
local({
  if (!exists('%s', envir = .GlobalEnv)) {
    cat('__ERROR__\tObject not found in R GlobalEnv\n')
  } else {
    d <- get('%s', envir = .GlobalEnv)
    if (is.matrix(d)) d <- as.data.frame(d)
    nr <- nrow(d); nc <- ncol(d)
    cols <- colnames(d)
    if (is.null(cols)) cols <- paste0('V', seq_len(nc))
    types <- vapply(d, function(x) class(x)[1], character(1))
    headers <- paste0(cols, ' [', types, ']')
    cat('__COLS__\t', paste(headers, collapse = '\t'), '\n', sep='')
    if (nr > 0) {
      idx <- seq.int(min(%dL, nr), min(%dL, nr))
      sub_d <- d[idx, , drop = FALSE]
      sub_chr <- lapply(sub_d, function(col) {
        v <- as.character(col)
        v[is.na(v)] <- 'NA'
        gsub('[\t\r\n]', ' ', v)
      })
      lines <- do.call(paste, c(sub_chr, sep = '\t'))
      cat(paste0('__ROW__\t', idx, '\t', lines, collapse = '\n'), '\n', sep='')
    }
    cat('__DONE__\t', nr, '\t', nc, '\n', sep='')
  }
})
""".printf (obj_name, obj_name, start_row, end_row);

            string? plot_out = null;
            string out_str = yield Services.PersistentSessionManager.get_default ().execute_r (r_code, out plot_out);
            parse_tsv_stream (obj_name, out_str);
        }

        private async void fetch_python_dataframe (string obj_name) {
            int start_idx = current_offset;
            int end_idx = current_offset + page_size;

            string py_code = """
try:
    _d = eval('%s')
    if hasattr(_d, 'to_dict') and hasattr(_d, 'columns'):
        cols = [f"{c} [{_d[c].dtype}]" for c in _d.columns]
        print('__COLS__\t' + '\t'.join(cols))
        nr = len(_d)
        nc = len(_d.columns)
        sub = _d.iloc[%d:%d]
        for idx, (_, r) in enumerate(sub.iterrows(), start=%d):
            row_vals = [str(v).replace('\t', ' ').replace('\n', ' ') for v in r.values]
            print(f'__ROW__\t{idx}\t' + '\t'.join(row_vals))
        print(f'__DONE__\t{nr}\t{nc}')
    elif hasattr(_d, 'shape') and len(_d.shape) == 2:
        cols = [f'col_{i}' for i in range(_d.shape[1])]
        print('__COLS__\t' + '\t'.join(cols))
        nr = _d.shape[0]
        nc = _d.shape[1]
        sub = _d[%d:%d]
        for idx, r in enumerate(sub, start=%d):
            row_vals = [str(v).replace('\t', ' ').replace('\n', ' ') for v in r]
            print(f'__ROW__\t{idx}\t' + '\t'.join(row_vals))
        print(f'__DONE__\t{nr}\t{nc}')
    else:
        print('__ERROR__\tTarget is not a 2D dataframe or matrix')
except Exception as e:
    print('__ERROR__\t' + str(e))
""".printf (obj_name, start_idx, end_idx, start_idx + 1, start_idx, end_idx, start_idx + 1);

            string? plot_out = null;
            string out_str = yield Services.PersistentSessionManager.get_default ().execute_python (py_code, out plot_out);
            parse_tsv_stream (obj_name, out_str);
        }

        private void parse_tsv_stream (string obj_name, string stream_text) {
            string[] lines = stream_text.split ("\n");
            string[] cols = new string[0];
            var rows = new Gee.ArrayList<DataRow> ();

            foreach (var line in lines) {
                string trimmed = line.strip ();
                if (trimmed.has_prefix ("__COLS__\t")) {
                    string cdata = trimmed.substring ("__COLS__\t".length);
                    cols = cdata.split ("\t");
                } else if (trimmed.has_prefix ("__ROW__\t")) {
                    string rdata = trimmed.substring ("__ROW__\t".length);
                    string[] parts = rdata.split ("\t");
                    if (parts.length >= 2) {
                        int r_idx = int.parse (parts[0]);
                        string[] cell_vals = new string[parts.length - 1];
                        for (int i = 1; i < parts.length; i++) {
                            cell_vals[i - 1] = parts[i];
                        }
                        rows.add (new DataRow (r_idx, cell_vals));
                    }
                } else if (trimmed.has_prefix ("__DONE__\t")) {
                    string[] dim_parts = trimmed.substring ("__DONE__\t".length).split ("\t");
                    if (dim_parts.length >= 2) {
                        this.total_df_rows = int.parse (dim_parts[0]);
                        this.total_df_cols = int.parse (dim_parts[1]);
                    }
                }
            }

            if (cols.length == 0 && rows.size == 0) {
                cols = { "Status", "Details" };
                rows.add (new DataRow (1, new string[] { "No Data", @"Object '$obj_name' is empty or not loaded in active session." }));
                this.total_df_rows = 0;
                this.total_df_cols = 0;
            }

            populate_grid_data (obj_name, cols, rows);
        }

        private void copy_to_clipboard () {
            var sb = new GLib.StringBuilder ();
            sb.append (string.joinv ("\t", current_col_names) + "\n");
            foreach (var r in all_rows) {
                sb.append (string.joinv ("\t", r.cells) + "\n");
            }
            var display = Gdk.Display.get_default ();
            if (display != null) {
                display.get_clipboard ().set_text (sb.str);
            }
        }

        public void popout_window (Gtk.Window? parent_window) {
            if (popout_win != null) {
                popout_win.present ();
                return;
            }

            popout_win = new Adw.Window () {
                title = @"Data Viewer — $active_object_name",
                default_width = 860,
                default_height = 620
            };
            if (parent_window != null) {
                popout_win.set_transient_for (parent_window);
            }

            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header);

            // Re-parent this viewer inside popout window
            var old_parent = this.get_parent () as Gtk.Box;
            if (old_parent != null) {
                old_parent.remove (this);
            } else {
                this.unparent ();
            }

            btn_popout.visible = false;
            toolbar_view.set_content (this);
            popout_win.set_content (toolbar_view);

            popout_win.close_request.connect (() => {
                btn_popout.visible = true;
                popout_win = null;
                close_requested ();
                return false;
            });

            popout_win.present ();
        }
    }
}
