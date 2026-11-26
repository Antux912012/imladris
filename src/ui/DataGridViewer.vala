// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

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
        public string session_key { get; set; default = "default"; }
        private string? active_file_path = null;

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
        private Gtk.Button btn_prev_cols;
        private Gtk.Button btn_next_cols;
        private Gtk.Label page_label;
        private Gtk.Spinner loading_spinner;

        private string[] current_col_names;
        private Gee.ArrayList<DataRow> all_rows;
        private Adw.Window? popout_win = null;

        private int current_offset = 0;
        private int page_size = 1000;
        private int total_df_rows = 0;
        private int current_col_offset = 0;
        private int col_page_size = 50;
        private int total_df_cols = 0;

        public signal void close_requested ();

        public override void dispose () {
            if (search_filter != null) {
                search_filter.set_filter_func (null);
            }
            if (column_view != null) {
                column_view.set_model (null);
            }
            if (popout_win != null) {
                popout_win.destroy ();
                popout_win = null;
            }
            base.dispose ();
        }

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

        private static GLib.Regex? safe_id_regex = null;
        private uint64 request_gen = 0;

        private static bool try_parse_numeric (string raw, out double val) {
            string s = raw.strip ().replace (",", "").replace ("$", "").replace ("€", "").replace ("£", "").replace ("%", "");
            return double.try_parse (s, out val);
        }

        private static bool is_safe_identifier (string name) {
            try {
                if (safe_id_regex == null) {
                    safe_id_regex = new GLib.Regex ("^[A-Za-z_][A-Za-z0-9_.$@\\[\\]]*$");
                }
                return safe_id_regex.match (name.strip ());
            } catch (GLib.RegexError e) {
                return false;
            }
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

            btn_prev_cols = new Gtk.Button.from_icon_name ("go-first-symbolic") {
                tooltip_text = "Previous 50 Columns"
            };
            btn_prev_cols.add_css_class ("flat");
            btn_prev_cols.clicked.connect (() => {
                if (current_col_offset >= col_page_size) {
                    current_col_offset -= col_page_size;
                    fetch_page_slice.begin ();
                }
            });
            toolbar.append (btn_prev_cols);

            btn_next_cols = new Gtk.Button.from_icon_name ("go-last-symbolic") {
                tooltip_text = "Next 50 Columns"
            };
            btn_next_cols.add_css_class ("flat");
            btn_next_cols.clicked.connect (() => {
                if (current_col_offset + col_page_size < total_df_cols) {
                    current_col_offset += col_page_size;
                    fetch_page_slice.begin ();
                }
            });
            toolbar.append (btn_next_cols);

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
                if (active_engine == "file" && active_file_path != null) {
                    fetch_page_slice.begin ();
                } else if (active_object_name != "") {
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
                    bool a_na = is_na_sentinel (sa);
                    bool b_na = is_na_sentinel (sb);
                    if (a_na && b_na) return GLib.strcmp (sa, sb);
                    if (a_na) return 1;
                    if (b_na) return -1;
                    double da = 0.0, db = 0.0;
                    if (try_parse_numeric (sa, out da) && try_parse_numeric (sb, out db) && !da.is_nan () && !db.is_nan ()) {
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
            int total_cols = (total_df_cols > 0) ? total_df_cols : current_col_names.length;
            string col_range = (total_cols > col_page_size)
                ? @"cols $(current_col_offset + 1)–$(int.min (current_col_offset + col_page_size, total_cols)) of $total_cols"
                : @"$total_cols cols";

            if (total_df_rows > 0) {
                int start_row = current_offset + 1;
                int end_row = int.min (current_offset + page_size, total_df_rows);
                if (search_entry.text.strip ().length > 0) {
                    dim_badge.label = @"Rows $start_row–$end_row of $total_df_rows ($visible_count shown) • $col_range";
                } else {
                    dim_badge.label = @"Rows $start_row–$end_row of $total_df_rows • $col_range";
                }
            } else {
                dim_badge.label = @"$(visible_count) rows • $col_range";
            }
        }

        private void update_pagination_ui () {
            btn_prev_page.sensitive = (current_offset > 0);
            btn_next_page.sensitive = (current_offset + page_size < total_df_rows);
            btn_prev_cols.sensitive = (current_col_offset > 0);
            btn_next_cols.sensitive = (current_col_offset + col_page_size < total_df_cols);

            int page_idx = (current_offset / page_size) + 1;
            int total_pages = (total_df_rows > 0) ? (int) GLib.Math.ceil ((double) total_df_rows / page_size) : 1;
            page_label.label = @"$page_idx / $total_pages";
        }

        private static bool is_na_sentinel (string s) {
            string t = s.strip ().down ();
            return t == "" || t == "na" || t == "<na>" || t == "nan" ||
                   t == "inf" || t == "-inf" || t == "+inf" ||
                   t == "infinity" || t == "-infinity" || t == "+infinity" ||
                   t == "null" || t == "none" || t == "n/a";
        }

        private static string[] parse_delimited_line (string line, char sep) {
            var fields = new Gee.ArrayList<string> ();
            var sb = new GLib.StringBuilder ();
            bool in_quotes = false;
            int len = line.length;

            for (int i = 0; i < len; i++) {
                char c = line[i];
                if (in_quotes) {
                    if (c == '"') {
                        if (i + 1 < len && line[i + 1] == '"') {
                            sb.append_c ('"');
                            i++;
                        } else {
                            in_quotes = false;
                        }
                    } else {
                        sb.append_c ((c == '\t' || c == '\r' || c == '\n') ? ' ' : c);
                    }
                } else {
                    if (c == '"' && sb.len == 0) {
                        in_quotes = true;
                    } else if (c == sep) {
                        fields.add (sb.str);
                        sb.truncate (0);
                    } else {
                        sb.append_c ((c == '\t' || c == '\r' || c == '\n') ? ' ' : c);
                    }
                }
            }
            fields.add (sb.str);

            string[] res = new string[fields.size];
            for (int i = 0; i < fields.size; i++) {
                res[i] = fields[i];
            }
            return res;
        }

        public async void fetch_and_display (string object_name, string engine = "r") {
            this.active_file_path = null;
            this.active_object_name = object_name;
            this.active_engine = engine;
            this.current_offset = 0;
            this.current_col_offset = 0;
            this.total_df_cols = 0;
            yield fetch_page_slice ();
        }

        public void load_delimited_file (string file_path) {
            this.active_file_path = file_path;
            this.active_engine = "file";
            this.current_offset = 0;
            this.current_col_offset = 0;
            this.total_df_cols = 0;
            load_delimited_file_slice_async.begin (file_path);
        }

        private async void load_delimited_file_slice_async (string file_path) {
            uint64 gen = ++request_gen;
            string bname = GLib.Path.get_basename (file_path);
            this.active_object_name = bname;
            title_label.label = @"Loading $bname...";
            loading_spinner.visible = true;
            loading_spinner.spinning = true;

            int start_row = current_offset + 1;
            int end_row = current_offset + page_size;
            string low_path = file_path.down ();
            bool is_gz = low_path.has_suffix (".gz");
            string base_low = is_gz ? low_path.substring (0, low_path.length - 3) : low_path;
            char sep = (base_low.has_suffix (".tsv") || base_low.has_suffix (".tabular") ||
                        base_low.has_suffix (".txt") || base_low.has_suffix (".vcf") ||
                        base_low.has_suffix (".bed") || base_low.has_suffix (".gtf")) ? '\t' : ',';

            string[] cols = new string[0];
            var rows = new Gee.ArrayList<DataRow> ();
            int total_rows = 0;
            string? err_msg = null;

            SourceFunc cb = load_delimited_file_slice_async.callback;
            new GLib.Thread<void*> ("imladris-csv-slice", () => {
                try {
                    var file = GLib.File.new_for_path (file_path);
                    GLib.InputStream base_stream = file.read (null);
                    if (is_gz) {
                        var decomp = new GLib.ZlibDecompressor (GLib.ZlibCompressorFormat.GZIP);
                        base_stream = new GLib.ConverterInputStream (base_stream, decomp);
                    }
                    var dis = new GLib.DataInputStream (base_stream);
                    string? raw_line = null;
                    int row_num = 0;
                    int all_col_count = 0;
                    bool is_vcf_or_gtf = (base_low.has_suffix (".vcf") || base_low.has_suffix (".gtf"));
                    bool is_bed = base_low.has_suffix (".bed");
                    while ((raw_line = dis.read_line (null, null)) != null) {
                        string line = raw_line.replace ("\r", "");
                        if (line.strip () == "") continue;
                        if (is_vcf_or_gtf && line.has_prefix ("##")) continue;
                        if (is_vcf_or_gtf && line.has_prefix ("#!")) continue;
                        if (row_num == 0 && sep == ',' && !line.contains (",") && line.contains (";")) {
                            sep = ';';
                        }
                        if (row_num == 0) {
                            string[] all_cols = parse_delimited_line (line, sep);
                            all_col_count = all_cols.length;
                            if (is_bed && !line.has_prefix ("#") && !line.has_prefix ("chrom")) {
                                var synth = new Gee.ArrayList<string> ();
                                for (int ci = 0; ci < all_col_count; ci++) {
                                    if (ci == 0) synth.add ("chrom");
                                    else if (ci == 1) synth.add ("start");
                                    else if (ci == 2) synth.add ("end");
                                    else synth.add (@"col_$(ci + 1)");
                                }
                                int c_hi = int.min (all_col_count, current_col_offset + col_page_size);
                                cols = (current_col_offset < c_hi) ? synth.to_array ()[current_col_offset:c_hi] : new string[0];
                                row_num++;
                                if (row_num >= start_row && row_num <= end_row) {
                                    string[] sliced = (current_col_offset < c_hi) ? all_cols[current_col_offset:c_hi] : new string[0];
                                    rows.add (new DataRow (row_num, sliced));
                                }
                                row_num++;
                                continue;
                            }
                            if (is_vcf_or_gtf && all_cols.length > 0 && all_cols[0].has_prefix ("#")) {
                                all_cols[0] = all_cols[0].substring (1);
                            }
                            int c_hi = int.min (all_col_count, current_col_offset + col_page_size);
                            cols = (current_col_offset < c_hi) ? all_cols[current_col_offset:c_hi] : new string[0];
                        } else if (row_num >= start_row && row_num <= end_row) {
                            string[] all_cells = parse_delimited_line (line, sep);
                            int c_hi = int.min (all_cells.length, current_col_offset + col_page_size);
                            string[] sliced = (current_col_offset < c_hi) ? all_cells[current_col_offset:c_hi] : new string[0];
                            rows.add (new DataRow (row_num, sliced));
                        }
                        row_num++;
                    }
                    dis.close (null);
                    total_rows = int.max (0, row_num - 1);
                    this.total_df_cols = all_col_count;
                } catch (GLib.Error e) {
                    err_msg = e.message;
                }
                GLib.Idle.add ((owned) cb);
                return null;
            });
            yield;

            if (gen != request_gen) return;
            loading_spinner.spinning = false;
            loading_spinner.visible = false;

            if (err_msg != null) {
                title_label.label = "Failed to load file";
                dim_badge.label = err_msg;
                return;
            }
            this.total_df_rows = total_rows;
            if (cols.length == 0 && rows.size == 0) {
                cols = { "Status", "Details" };
                rows.add (new DataRow (1, new string[] { "No Data", @"File '$bname' is empty." }));
                this.total_df_rows = 0;
            }
            populate_grid_data (bname, cols, rows);
        }

        private async void fetch_page_slice () {
            if (active_engine == "file" && active_file_path != null) {
                yield load_delimited_file_slice_async (active_file_path);
                return;
            }

            if (active_object_name == "") return;

            if (!is_safe_identifier (active_object_name)) {
                title_label.label = "Invalid Identifier";
                dim_badge.label = "Rejected";
                return;
            }

            uint64 gen = ++request_gen;
            title_label.label = @"Loading $active_object_name...";
            loading_spinner.visible = true;
            loading_spinner.spinning = true;

            if (active_engine == "r") {
                yield fetch_r_dataframe (active_object_name);
            } else {
                yield fetch_python_dataframe (active_object_name);
            }

            if (gen != request_gen) return;
            loading_spinner.spinning = false;
            loading_spinner.visible = false;
        }

        private async void fetch_r_dataframe (string obj_name) {
            int start_row = current_offset + 1;
            int end_row = current_offset + page_size;
            string b64_name = Core.PlatformUtils.encode_hex (obj_name.data);

            string r_code = """
local({
  .hex <- '%s'
  .n_hex <- nchar(.hex) %%/%% 2L
  .obj_name <- if (.n_hex > 0L) {
    .out <- rawToChar(as.raw(strtoi(substring(.hex, seq(1L, by = 2L, length.out = .n_hex), seq(2L, by = 2L, length.out = .n_hex)), 16L)))
    Encoding(.out) <- 'UTF-8'
    .out
  } else ''
  if (!exists(.obj_name, envir = .GlobalEnv)) {
    cat('__ERROR__\tObject not found in R GlobalEnv\n')
  } else {
    d <- get(.obj_name, envir = .GlobalEnv)
    if (inherits(d, 'data.table')) d <- as.data.frame(d)
    if (inherits(d, 'Seurat')) d <- d@meta.data
    if (inherits(d, 'SummarizedExperiment') || inherits(d, 'DESeqDataSet')) {
      d <- as.data.frame(SummarizedExperiment::colData(d))
    }
    if (is.matrix(d)) d <- as.data.frame(d)
    nr <- nrow(d); nc <- ncol(d)
    if (is.null(nr)) nr <- 0L
    if (is.null(nc)) nc <- 0L
    col_start <- %dL
    col_limit <- %dL
    if (nc == 0L || col_start > nc) {
      cat('__COLS__\t(no columns)\n')
      cat('__DONE__\t', nr, '\t', nc, '\n', sep='')
    } else {
      col_end <- min(nc, col_start + col_limit - 1L)
      col_idx <- seq.int(col_start, col_end)
      show_nc <- length(col_idx)
      cols <- colnames(d)[col_idx]
      if (is.null(cols)) cols <- paste0('V', col_idx)
      is_sparse_s4 <- isS4(d)
      types <- if (is_sparse_s4) rep(class(d)[1], show_nc) else vapply(d[, col_idx, drop = FALSE], function(x) class(x)[1], character(1))
      headers <- paste0(cols, ' [', types, ']')
      .has_rn <- if (exists('has_rownames', mode = 'function')) {
        tryCatch(has_rownames(d), error = function(e) FALSE)
      } else {
        .rni <- tryCatch(.row_names_info(d, 1L), error = function(e) 0L)
        !is.null(rownames(d)) && length(.rni) == 1L && !is.na(.rni) && .rni > 0L && !identical(rownames(d), as.character(seq_len(nr)))
      }
      if (.has_rn) {
        headers <- c('rowname [character]', headers)
      }
      cat('__COLS__\t', paste(headers, collapse = '\t'), '\n', sep='')
      if (nr > 0L) {
        idx <- seq.int(min(%dL, nr), min(%dL, nr))
        sub_d <- if (is_sparse_s4) as.data.frame(as.matrix(d[idx, col_idx, drop = FALSE])) else d[idx, col_idx, drop = FALSE]
        sub_chr <- lapply(sub_d, function(col) {
          v <- as.character(col)
          v[is.na(v)] <- 'NA'
          gsub('[\t\r\n]', ' ', v)
        })
        if (.has_rn) {
          rn_vals <- gsub('[\t\r\n]', ' ', rownames(sub_d))
          sub_chr <- c(list(rn_vals), sub_chr)
        }
        lines <- do.call(paste, c(sub_chr, sep = '\t'))
        cat(paste0('__ROW__\t', idx, '\t', lines, collapse = '\n'), '\n', sep='')
      }
      cat('__DONE__\t', nr, '\t', nc, '\n', sep='')
    }
  }
})
""".printf (b64_name, current_col_offset + 1, col_page_size, start_row, end_row);

            string? plot_out = null;
            string out_str = yield Services.PersistentSessionManager.peek_for_key (session_key).execute_r_with_options (r_code, null, null, 15000, false, out plot_out);
            parse_tsv_stream (obj_name, out_str);
        }

        private async void fetch_python_dataframe (string obj_name) {
            int start_idx = current_offset;
            int end_idx = current_offset + page_size;
            string b64_name = GLib.Base64.encode (obj_name.data);

            string py_code = """
def _imladris_fetch_df():
    import base64 as _b64
    try:
        _obj_name = _b64.b64decode('%s').decode('utf-8')
        _ns = globals()
        _d = _ns[_obj_name] if _obj_name in _ns else eval(_obj_name, _ns)
        _col_start = %d
        _col_end = _col_start + %d
        if hasattr(_d, 'obs') and hasattr(_d.obs, 'columns'):
            _d = _d.obs
        if hasattr(_d, 'collect') and hasattr(_d, 'columns'):
            _d = _d.head(%d + %d).collect()
        if hasattr(_d, 'to_pandas') and hasattr(_d, 'schema'):
            _nr = len(_d) if hasattr(_d, '__len__') else 0
            _d = _d.slice(%d, %d).to_pandas()
            _r_start, _r_end = 0, len(_d)
        elif type(_d).__name__ == 'Series' and hasattr(_d, 'to_frame'):
            _d = _d.to_frame(name=str(_d.name or 'value'))
            _nr = len(_d)
            _r_start, _r_end = %d, %d
        else:
            _nr = len(_d) if hasattr(_d, '__len__') else _d.shape[0]
            _r_start, _r_end = %d, %d
        if hasattr(_d, 'iloc') and hasattr(_d, 'columns'):
            nc_total = len(_d.columns)
            show_cols = list(_d.columns[_col_start:_col_end])
            _dtypes = _d.dtypes
            cols = [f"{c} [{_dtypes[i + _col_start]}]" for i, c in enumerate(show_cols)]
            has_idx = hasattr(_d, 'index') and (getattr(_d.index, 'name', None) is not None or type(_d.index).__name__ in ('DatetimeIndex', 'Index', 'MultiIndex'))
            if has_idx:
                cols = [f"{_d.index.name or 'index'} [{type(_d.index).__name__}]"] + cols
            print('__COLS__\t' + '\t'.join(cols))
            nc = len(show_cols)
            sub = _d.iloc[_r_start:_r_end, _col_start:_col_start + nc]
            if nc > 0 and len(sub) > 0:
                _rows = sub.astype(str).apply(lambda col: col.str.replace('\t', ' ', regex=False).str.replace('\r', ' ', regex=False).str.replace('\n', ' ', regex=False))
                _idx_vals = [str(ix).replace('\t', ' ').replace('\r', ' ').replace('\n', ' ') for ix in sub.index] if has_idx else None
                for idx, row in enumerate(_rows.itertuples(index=False, name=None), start=%d):
                    if _idx_vals is not None:
                        print(f'__ROW__\t{idx}\t{_idx_vals[idx - %d]}\t' + '\t'.join(row))
                    else:
                        print(f'__ROW__\t{idx}\t' + '\t'.join(row))
            print(f'__DONE__\t{_nr}\t{nc_total}')
        elif hasattr(_d, 'shape') and len(_d.shape) == 2:
            nr = _d.shape[0]
            nc_total = _d.shape[1]
            c_hi = min(nc_total, _col_end)
            cols = [f'col_{i}' for i in range(_col_start, c_hi)]
            print('__COLS__\t' + '\t'.join(cols))
            sub = _d[%d:%d, _col_start:c_hi]
            if hasattr(sub, 'toarray'):
                sub = sub.toarray()
            for idx, r in enumerate(sub, start=%d):
                row_vals = [str(v).replace('\t', ' ').replace('\r', ' ').replace('\n', ' ') for v in r]
                print(f'__ROW__\t{idx}\t' + '\t'.join(row_vals))
            print(f'__DONE__\t{nr}\t{nc_total}')
        else:
            print('__ERROR__\tTarget is not a 2D dataframe or matrix')
    except Exception as e:
        print('__ERROR__\t' + str(e))
_imladris_fetch_df()
del _imladris_fetch_df
""".printf (b64_name, current_col_offset, col_page_size, start_idx, page_size, start_idx, page_size, start_idx, end_idx, start_idx, end_idx, start_idx + 1, start_idx + 1, start_idx, end_idx, start_idx + 1);

            string? plot_out = null;
            string out_str = yield Services.PersistentSessionManager.peek_for_key (session_key).execute_python_with_options (py_code, null, null, 15000, false, out plot_out);
            parse_tsv_stream (obj_name, out_str);
        }

        private void parse_tsv_stream (string obj_name, string stream_text) {
            string[] lines = stream_text.split ("\n");
            string[] cols = new string[0];
            var rows = new Gee.ArrayList<DataRow> ();
            string? err_msg = null;

            foreach (var line in lines) {
                string trimmed = line.strip ();
                if (trimmed.has_prefix ("__ERROR__\t")) {
                    err_msg = trimmed.substring ("__ERROR__\t".length);
                } else if (trimmed.has_prefix ("__COLS__\t")) {
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

            if (err_msg != null && cols.length == 0 && rows.size == 0) {
                cols = { "Error", "Details" };
                rows.add (new DataRow (1, new string[] { "Execution Error", err_msg }));
                this.total_df_rows = 0;
            } else if (cols.length == 0 && rows.size == 0) {
                cols = { "Status", "Details" };
                rows.add (new DataRow (1, new string[] { "No Data", @"Object '$obj_name' is empty or not loaded in active session." }));
                this.total_df_rows = 0;
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

            // Re-parent this viewer inside popout window safely
            var old_parent = this.get_parent ();
            if (old_parent is Gtk.Box) {
                ((Gtk.Box) old_parent).remove (this);
            } else if (old_parent is Adw.ToolbarView) {
                ((Adw.ToolbarView) old_parent).set_content (null);
            } else if (old_parent != null) {
                this.unparent ();
            }

            btn_popout.visible = false;
            toolbar_view.set_content (this);
            popout_win.set_content (toolbar_view);

            popout_win.close_request.connect (() => {
                toolbar_view.set_content (null);
                btn_popout.visible = true;
                popout_win = null;
                close_requested ();
                return false;
            });

            popout_win.present ();
        }
    }
}
