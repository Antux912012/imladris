// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Gtk;
using Adw;
using Imladris.Services;

namespace Imladris.UI {

    public class EnvVariableItem : GLib.Object {
        public string name { get; set; }
        public string var_type { get; set; }
        public string dimensions { get; set; }
        public string memory_size { get; set; }
        public bool is_dataframe { get; set; }
        public string initial_preview { get; set; }

        public EnvVariableItem (string name, string var_type, string dims, string mem, bool is_df, string prev = "") {
            this.name = name;
            this.var_type = var_type;
            this.dimensions = dims;
            this.memory_size = mem;
            this.is_dataframe = is_df;
            this.initial_preview = prev;
        }
    }

    /**
     * EnvironmentController
     * Manages R & Python Global Environment inspection, dataframe expanders,
     * variable clearing with confirmation, and one-click data grid inspection.
     */
    public class EnvironmentController : Gtk.Box {

        public signal void view_dataframe_requested (string object_name, string runtime_engine);
        public signal void toast_requested (string message);

        private Gtk.ListBox list_box;
        private Gtk.Label header_status_lbl;
        private Gtk.Spinner refresh_spinner;
        private Gtk.SearchEntry search_entry;
        private Gtk.Button btn_clean;
        private Gtk.Button btn_refresh;
        private Gtk.Button btn_import;
        private unowned Gtk.Window? parent_window;
        private Gee.ArrayList<EnvVariableItem> last_items;

        public string active_engine { get; set; default = "r"; }

        public EnvironmentController (Gtk.Window? win) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.parent_window = win;
            this.last_items = new Gee.ArrayList<EnvVariableItem> ();
            this.hexpand = true;
            this.vexpand = true;

            setup_toolbar ();
            setup_list_view ();
        }

        private void setup_toolbar () {
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            toolbar.add_css_class ("dock-subtoolbar");

            var icon = new Gtk.Image.from_icon_name ("view-list-symbolic");
            toolbar.append (icon);

            header_status_lbl = new Gtk.Label ("Global Environment") {
                css_classes = { "dim-label", "caption" },
                xalign = 0
            };
            toolbar.append (header_status_lbl);

            refresh_spinner = new Gtk.Spinner () {
                spinning = false,
                visible = false,
                margin_start = 4
            };
            toolbar.append (refresh_spinner);

            toolbar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Filter objects...",
                width_request = 130
            };
            search_entry.search_changed.connect (apply_filter);
            toolbar.append (search_entry);

            btn_import = new Gtk.Button.from_icon_name ("document-open-symbolic") {
                tooltip_text = "Import Dataset (CSV / Text)..."
            };
            btn_import.add_css_class ("flat");
            btn_import.clicked.connect (prompt_import_dataset);
            toolbar.append (btn_import);

            btn_clean = new Gtk.Button.from_icon_name ("edit-clear-all-symbolic") {
                tooltip_text = "Clear All Objects from Global Environment"
            };
            btn_clean.add_css_class ("flat");
            btn_clean.clicked.connect (prompt_clear_environment);
            toolbar.append (btn_clean);

            btn_refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh Environment Objects"
            };
            btn_refresh.add_css_class ("flat");
            btn_refresh.clicked.connect (() => {
                refresh_environment.begin ();
            });
            toolbar.append (btn_refresh);

            this.append (toolbar);
        }

        private void setup_list_view () {
            list_box = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "boxed-list" },
                margin_start = 8,
                margin_end = 8,
                margin_top = 4,
                margin_bottom = 8
            };

            var scroller = new Gtk.ScrolledWindow () {
                child = list_box,
                hexpand = true,
                vexpand = true,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
            };
            this.append (scroller);
        }

        public void prompt_clear_environment () {
            var dialog = new Adw.AlertDialog (
                "Clear Global Environment?",
                "Are you sure you want to remove all user-defined variables from the active session? This action cannot be undone."
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("clear", "Clear All");
            dialog.set_response_appearance ("clear", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response ("cancel");
            dialog.set_close_response ("cancel");

            dialog.response.connect ((resp) => {
                if (resp == "clear") {
                    execute_clear_environment.begin ();
                }
            });

            if (parent_window != null) {
                dialog.present (parent_window);
            }
        }

        private async void execute_clear_environment () {
            refresh_spinner.visible = true;
            refresh_spinner.spinning = true;

            if (active_engine == "r") {
                string? plot_out = null;
                yield PersistentSessionManager.get_default ().execute_r (
                    "rm(list = ls(all.names = TRUE)); gc(verbose = FALSE)\n",
                    out plot_out
                );
            } else {
                string? plot_out = null;
                string py_clear = """
for _k in list(globals().keys()):
    if not _k.startswith('_') and _k not in ('In', 'Out', 'get_ipython', 'exit', 'quit', 'sys', 'os'):
        try:
            del globals()[_k]
        except Exception:
            pass
""";
                yield PersistentSessionManager.get_default ().execute_python (py_clear, out plot_out);
            }

            toast_requested ("Cleared all objects from Global Environment");

            refresh_spinner.spinning = false;
            refresh_spinner.visible = false;
            refresh_environment.begin ();
        }

        public async void refresh_environment () {
            refresh_spinner.visible = true;
            refresh_spinner.spinning = true;

            var items = new Gee.ArrayList<EnvVariableItem> ();

            if (active_engine == "r") {
                yield fetch_r_environment (items);
            } else {
                yield fetch_python_environment (items);
            }

            this.last_items = items;
            apply_filter ();

            refresh_spinner.spinning = false;
            refresh_spinner.visible = false;
        }

        private void apply_filter () {
            string query = search_entry != null ? search_entry.text.strip ().down () : "";
            var filtered = new Gee.ArrayList<EnvVariableItem> ();
            foreach (var it in last_items) {
                if (query.length == 0 || it.name.down ().contains (query) || it.var_type.down ().contains (query)) {
                    filtered.add (it);
                }
            }
            render_items (filtered);
        }

        private void prompt_import_dataset () {
            var file_dialog = new Gtk.FileDialog () {
                title = "Import Dataset (CSV, TSV, Text)"
            };
            var filter = new Gtk.FileFilter ();
            filter.set_filter_name ("Delimited Data (*.csv, *.tsv, *.txt)");
            filter.add_pattern ("*.csv");
            filter.add_pattern ("*.tsv");
            filter.add_pattern ("*.txt");
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            file_dialog.filters = filters;

            file_dialog.open.begin (parent_window, null, (obj, res) => {
                try {
                    var file = file_dialog.open.end (res);
                    if (file != null) {
                        string path = file.get_path ();
                        string base_name = file.get_basename ();
                        string lower_base = base_name.down ();
                        string var_name = base_name.replace (".tabular", "").replace (".csv", "").replace (".tsv", "").replace (".txt", "").replace ("-", "_").replace (" ", "_");
                        if (var_name.length == 0 || !var_name.get_char (0).isalpha ()) {
                            var_name = "dataset_" + var_name;
                        }

                        string safe_path = path.replace ("\\", "\\\\").replace ("\"", "\\\"");
                        bool is_tab = lower_base.has_suffix (".tsv") || lower_base.has_suffix (".tabular") || lower_base.has_suffix (".txt");

                        if (active_engine == "r") {
                            string r_cmd = is_tab
                                ? @"read.delim(\"$safe_path\", stringsAsFactors = FALSE)"
                                : @"read.csv(\"$safe_path\")";
                            string r_code = @"$var_name <- $r_cmd\nView($var_name)\n";
                            PersistentSessionManager.get_default ().execute_r.begin (r_code, (o, r) => {
                                refresh_environment.begin ();
                                view_dataframe_requested (var_name, "r");
                            });
                        } else {
                            string py_cmd = is_tab
                                ? @"pd.read_csv(\"$safe_path\", sep=\"\\t\")"
                                : @"pd.read_csv(\"$safe_path\")";
                            string py_code = @"import pandas as pd\n$var_name = $py_cmd\n";
                            PersistentSessionManager.get_default ().execute_python.begin (py_code, (o, r) => {
                                refresh_environment.begin ();
                                view_dataframe_requested (var_name, "python");
                            });
                        }
                        toast_requested (@"Imported dataset as '$var_name'");
                    }
                } catch (GLib.Error e) {
                    // Canceled or failed
                }
            });
        }

        private async void fetch_r_environment (Gee.ArrayList<EnvVariableItem> items) {
            string r_probe = """
local({
  objs <- ls(all.names = FALSE)
  res <- lapply(objs, function(x) {
    tryCatch({
      val <- get(x)
      cls <- paste(class(val), collapse=", ")
      dim_str <- if(!is.null(dim(val))) paste0(nrow(val), " × ", ncol(val)) else if(length(val) > 0) as.character(length(val)) else ""
      sz <- format(object.size(val), units = "auto")
      is_df <- is.data.frame(val) || is.matrix(val)
      paste(x, cls, dim_str, sz, if(is_df) "1" else "0", sep="\t")
    }, error = function(e) "")
  })
  cat("___IMLADRIS_ENV_START___\n")
  cat(unlist(res[nchar(unlist(res)) > 0]), sep="\n")
  cat("___IMLADRIS_ENV_END___\n")
})
""";
            string? plot_out = null;
            string out_str = yield PersistentSessionManager.get_default ().execute_r (r_probe, out plot_out);
            parse_env_output (out_str, items);
        }

        private async void fetch_python_environment (Gee.ArrayList<EnvVariableItem> items) {
            string py_probe = """
import sys
res = []
for k in list(globals().keys()):
    if not k.startswith('_') and k not in ('In', 'Out', 'get_ipython', 'exit', 'quit', 'sys', 'os'):
        try:
            v = globals()[k]
            cls = type(v).__name__
            dim_str = str(getattr(v, 'shape', len(v) if hasattr(v, '__len__') else ''))
            sz = str(sys.getsizeof(v)) + " bytes"
            is_df = "1" if hasattr(v, 'columns') or hasattr(v, 'shape') else "0"
            res.append(f"{k}\t{cls}\t{dim_str}\t{sz}\t{is_df}")
        except Exception:
            pass
print("___IMLADRIS_ENV_START___")
print("\n".join(res))
print("___IMLADRIS_ENV_END___")
""";
            string? plot_out = null;
            string out_str = yield PersistentSessionManager.get_default ().execute_python (py_probe, out plot_out);
            parse_env_output (out_str, items);
        }

        private void parse_env_output (string raw, Gee.ArrayList<EnvVariableItem> items) {
            if (!raw.contains ("___IMLADRIS_ENV_START___")) return;
            int start_idx = raw.index_of ("___IMLADRIS_ENV_START___") + "___IMLADRIS_ENV_START___".length;
            int end_idx = raw.index_of ("___IMLADRIS_ENV_END___");
            if (end_idx < start_idx) return;

            string block = raw.substring (start_idx, end_idx - start_idx).strip ();
            string[] lines = block.split ("\n");
            foreach (var line in lines) {
                string[] parts = line.strip ().split ("\t");
                if (parts.length >= 5) {
                    string name = parts[0].strip ();
                    string cls = parts[1].strip ();
                    string dims = parts[2].strip ();
                    string sz = parts[3].strip ();
                    bool is_df = (parts[4].strip () == "1");
                    items.add (new EnvVariableItem (name, cls, dims, sz, is_df));
                }
            }
        }

        private void render_items (Gee.ArrayList<EnvVariableItem> items) {
            // Clear current rows
            Gtk.Widget? child = list_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                list_box.remove (child);
                child = next;
            }

            header_status_lbl.label = @"Global Environment ($(items.size) Objects)";

            if (items.size == 0) {
                var empty_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                    margin_top = 32,
                    margin_bottom = 32,
                    halign = Gtk.Align.CENTER,
                    valign = Gtk.Align.CENTER
                };
                var empty_icon = new Gtk.Image.from_icon_name ("view-list-symbolic") {
                    pixel_size = 48,
                    css_classes = { "dim-label" }
                };
                var empty_title = new Gtk.Label ("Environment is empty") {
                    css_classes = { "heading", "dim-label" }
                };
                var empty_sub = new Gtk.Label ("Execute code chunks or console commands to inspect objects") {
                    css_classes = { "caption", "dim-label" }
                };
                empty_box.append (empty_icon);
                empty_box.append (empty_title);
                empty_box.append (empty_sub);
                list_box.append (empty_box);
                return;
            }

            var data_items = new Gee.ArrayList<EnvVariableItem> ();
            var value_items = new Gee.ArrayList<EnvVariableItem> ();
            var func_items = new Gee.ArrayList<EnvVariableItem> ();

            foreach (var item in items) {
                string cls_lower = item.var_type.down ();
                if (item.is_dataframe || cls_lower.contains ("matrix") || cls_lower.contains ("data.frame") || cls_lower.contains ("tibble") || cls_lower.contains ("data.table")) {
                    data_items.add (item);
                } else if (cls_lower.contains ("function") || cls_lower.contains ("builtin") || cls_lower.contains ("closure")) {
                    func_items.add (item);
                } else {
                    value_items.add (item);
                }
            }

            if (data_items.size > 0) {
                add_category_header (@"Data ($(data_items.size))");
                foreach (var it in data_items) {
                    append_variable_row (it);
                }
            }

            if (value_items.size > 0) {
                add_category_header (@"Values ($(value_items.size))");
                foreach (var it in value_items) {
                    append_variable_row (it);
                }
            }

            if (func_items.size > 0) {
                add_category_header (@"Functions ($(func_items.size))");
                foreach (var it in func_items) {
                    append_variable_row (it);
                }
            }
        }

        private void add_category_header (string title) {
            var header_label = new Gtk.Label (title) {
                xalign = 0,
                margin_start = 8,
                margin_top = 8,
                margin_bottom = 2,
                css_classes = { "caption", "dim-label", "heading" }
            };
            list_box.append (header_label);
        }

        private void append_variable_row (EnvVariableItem item) {
            var expander_row = new Adw.ExpanderRow () {
                title = item.name,
                subtitle = @"$(item.var_type)$(item.dimensions != "" ? @" • $(item.dimensions)" : "")$(item.memory_size != "" ? @" • $(item.memory_size)" : "")"
            };

            string icon_name = item.is_dataframe ? "view-grid-symbolic" : (item.dimensions.contains ("×") ? "view-list-symbolic" : "view-list-bullet-symbolic");
            expander_row.add_prefix (new Gtk.Image.from_icon_name (icon_name));

            if (item.is_dataframe) {
                var view_btn = new Gtk.Button.from_icon_name ("view-grid-symbolic") {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = @"View Data / Matrix: $(item.name)"
                };
                view_btn.add_css_class ("flat");
                string obj_to_view = item.name;
                view_btn.clicked.connect (() => {
                    view_dataframe_requested (obj_to_view, active_engine);
                });
                expander_row.add_suffix (view_btn);
            }

            // Summary monospace container inside expander
            var summary_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 6,
                margin_bottom = 8
            };

            var summary_label = new Gtk.Label ("Click to inspect str() / summary()...") {
                xalign = 0,
                selectable = true,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                css_classes = { "monospace", "caption", "dim-label" }
            };
            summary_box.append (summary_label);

            bool fetched = false;
            string vname = item.name;
            expander_row.notify["expanded"].connect (() => {
                if (expander_row.expanded && !fetched) {
                    fetched = true;
                    fetch_variable_summary.begin (vname, summary_label);
                }
            });

            expander_row.add_row (new Adw.ActionRow () { child = summary_box });
            list_box.append (expander_row);
        }

        private async void fetch_variable_summary (string var_name, Gtk.Label target_label) {
            target_label.label = "Loading summary...";
            if (active_engine == "r") {
                string r_cmd = """
local({
  v <- get('%s')
  cat('--- str() ---\n')
  str(v)
  cat('\n--- summary() ---\n')
  print(summary(v))
})
""".printf (var_name);
                string? plot_out = null;
                string res = yield PersistentSessionManager.get_default ().execute_r (r_cmd, out plot_out);
                target_label.label = res.strip ().length > 0 ? res.strip () : "No summary available.";
            } else {
                string py_cmd = """
try:
    v = eval('%s')
    if hasattr(v, 'info'):
        import io
        buf = io.StringIO()
        v.info(buf=buf)
        print(buf.getvalue())
    if hasattr(v, 'describe'):
        print(v.describe().to_string())
    elif hasattr(v, '__repr__'):
        print(repr(v))
except Exception as e:
    print(str(e))
""".printf (var_name);
                string? plot_out = null;
                string res = yield PersistentSessionManager.get_default ().execute_python (py_cmd, out plot_out);
                target_label.label = res.strip ().length > 0 ? res.strip () : "No summary available.";
            }
        }
    }
}
