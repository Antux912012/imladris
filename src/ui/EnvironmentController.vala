// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

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
        public string var_engine { get; set; default = "r"; }
        public string columns_csv { get; set; default = ""; }

        public EnvVariableItem (string name, string var_type, string dims, string mem, bool is_df, string prev = "", string engine = "r", string cols = "") {
            this.name = name;
            this.var_type = var_type;
            this.dimensions = dims;
            this.memory_size = mem;
            this.is_dataframe = is_df;
            this.initial_preview = prev;
            this.var_engine = engine;
            this.columns_csv = cols;
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
        public string session_key { get; set; default = "default"; }

        private PersistentSessionManager get_session_manager () {
            return PersistentSessionManager.peek_for_key (session_key);
        }

        public Gee.ArrayList<EnvVariableItem> get_cached_variables () {
            return last_items;
        }

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

            var kernel_drop = new Gtk.DropDown.from_strings ({ "Auto Kernel", "Quarto", "R Kernel", "Python Kernel" }) {
                tooltip_text = "Select preferred execution kernel (Auto, Quarto, R, or Python)",
                selected = (uint) Core.SettingsManager.get_default ().preferred_kernel
            };
            kernel_drop.notify["selected"].connect (() => {
                Core.SettingsManager.get_default ().preferred_kernel = (Core.KernelOption) kernel_drop.selected;
            });
            toolbar.append (kernel_drop);

            var btn_host_scope = new Gtk.ToggleButton.with_label ("Host") {
                tooltip_text = "Switch between bundled/managed toolchain (off) and host R/Python/Quarto (on)",
                active = (Core.SettingsManager.get_default ().runtime_scope == Core.RuntimeExecutionScope.PREFER_HOST),
                visible = !Core.HostBridge.is_flatpak ()
            };
            btn_host_scope.add_css_class ("flat");
            btn_host_scope.toggled.connect (() => {
                var scope = btn_host_scope.active
                    ? Core.RuntimeExecutionScope.PREFER_HOST
                    : Core.RuntimeExecutionScope.IN_SANDBOX_FIRST;
                Core.SettingsManager.get_default ().runtime_scope = scope;
                toast_requested (btn_host_scope.active
                    ? "Runtime scope: Host system (flatpak-spawn --host)"
                    : "Runtime scope: Out-of-box Flatpak / Managed Toolchain");
            });
            toolbar.append (btn_host_scope);

            var btn_rescan_envs = new Gtk.Button.from_icon_name ("system-search-symbolic") {
                tooltip_text = "Rescan Host & Project Environments (R, Python, uv, Conda, Quarto)"
            };
            btn_rescan_envs.add_css_class ("flat");
            btn_rescan_envs.clicked.connect (() => {
                string ws = get_session_manager ().current_working_dir;
                Core.EnvDiscovery.get_default ().discover_async.begin (ws, true, null, (obj, res) => {
                    var result = Core.EnvDiscovery.get_default ().discover_async.end (res);
                    string r_info = result.latest_r_version != "" ? @"R $(result.latest_r_version)" : "R";
                    toast_requested (@"Rescanned $(result.environments.size) environment(s) ($r_info)");
                });
            });
            toolbar.append (btn_rescan_envs);

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

            if (active_engine == "r" || active_engine == "polyglot") {
                string? plot_out = null;
                yield get_session_manager ().execute_r (
                    "rm(list = ls(all.names = TRUE)); gc(verbose = FALSE)\n",
                    out plot_out
                );
            }
            if (active_engine != "r") {
                string? plot_out = null;
                string py_clear = """
for _k in list(globals().keys()):
    if not _k.startswith('_') and _k not in ('In', 'Out', 'get_ipython', 'exit', 'quit', 'sys', 'os'):
        try:
            del globals()[_k]
        except Exception:
            pass
""";
                yield get_session_manager ().execute_python (py_clear, out plot_out);
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
            string norm = active_engine.down ().strip ();
            if (norm == "polyglot") {
                yield fetch_r_environment (items);
                yield fetch_python_environment (items);
            } else if (norm == "r") {
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
            filter.set_filter_name ("Data Files (*.csv, *.tsv, *.txt, *.parquet, *.rds, *.dta, *.xlsx)");
            filter.add_pattern ("*.csv");
            filter.add_pattern ("*.CSV");
            filter.add_pattern ("*.tsv");
            filter.add_pattern ("*.TSV");
            filter.add_pattern ("*.txt");
            filter.add_pattern ("*.parquet");
            filter.add_pattern ("*.rds");
            filter.add_pattern ("*.dta");
            filter.add_pattern ("*.xlsx");
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            file_dialog.filters = filters;

            file_dialog.open.begin (parent_window, null, (obj, res) => {
                try {
                    var file = file_dialog.open.end (res);
                    if (file != null) {
                        string? path = file.get_path ();
                        if (path == null) {
                            toast_requested ("Cannot import remote or non-local file without a filesystem path.");
                            return;
                        }
                        string base_name = file.get_basename () ?? "dataset";
                        string lower_base = base_name.down ();
                        int dot_idx = base_name.last_index_of (".");
                        string raw_stem = (dot_idx > 0) ? base_name.substring (0, dot_idx) : base_name;
                        var sb_var = new StringBuilder ();
                        for (int ci = 0; ci < raw_stem.length; ci++) {
                            char ch = raw_stem[ci];
                            if (ch.isalnum () || ch == '_') {
                                sb_var.append_c (ch);
                            } else {
                                sb_var.append_c ('_');
                            }
                        }
                        string var_name = sb_var.str;
                        if (var_name.length == 0 || !var_name[0].isalpha ()) {
                            var_name = "dataset_" + var_name;
                        }

                        string safe_path = path.replace ("\\", "\\\\").replace ("\"", "\\\"");
                        bool is_tab = lower_base.has_suffix (".tsv") || lower_base.has_suffix (".tabular") || lower_base.has_suffix (".txt");

                        string norm_engine = active_engine.down ().strip ();
                        if (norm_engine == "r" || norm_engine == "polyglot") {
                            string r_cmd;
                            if (lower_base.has_suffix (".rds")) {
                                r_cmd = @"readRDS(\"$safe_path\")";
                            } else if (lower_base.has_suffix (".parquet")) {
                                r_cmd = @"arrow::read_parquet(\"$safe_path\")";
                            } else if (lower_base.has_suffix (".dta")) {
                                r_cmd = @"haven::read_dta(\"$safe_path\")";
                            } else if (lower_base.has_suffix (".xlsx")) {
                                r_cmd = @"readxl::read_excel(\"$safe_path\")";
                            } else {
                                r_cmd = is_tab
                                    ? @"read.delim(\"$safe_path\", stringsAsFactors = FALSE)"
                                    : @"read.csv(\"$safe_path\")";
                            }
                            string r_code = @"$var_name <- $r_cmd\n";
                            get_session_manager ().execute_r.begin (r_code, (o, r) => {
                                string? unused_plot = null;
                                string out_res = get_session_manager ().execute_r.end (r, out unused_plot);
                                if (out_res.contains ("Error") || out_res.contains ("✖")) {
                                    toast_requested (@"Failed to import '$base_name': $(out_res.strip ())");
                                } else {
                                    toast_requested (@"Imported dataset as '$var_name'");
                                }
                                refresh_environment.begin ();
                                view_dataframe_requested (var_name, "r");
                            });
                        } else {
                            string py_cmd;
                            if (lower_base.has_suffix (".parquet")) {
                                py_cmd = @"pd.read_parquet(\"$safe_path\")";
                            } else if (lower_base.has_suffix (".dta")) {
                                py_cmd = @"pd.read_stata(\"$safe_path\")";
                            } else if (lower_base.has_suffix (".xlsx")) {
                                py_cmd = @"pd.read_excel(\"$safe_path\")";
                            } else {
                                py_cmd = is_tab
                                    ? @"pd.read_csv(\"$safe_path\", sep=\"\\t\")"
                                    : @"pd.read_csv(\"$safe_path\")";
                            }
                            string py_code = @"import pandas as pd\n$var_name = $py_cmd\n";
                            get_session_manager ().execute_python.begin (py_code, (o, r) => {
                                string? unused_plot = null;
                                string out_res = get_session_manager ().execute_python.end (r, out unused_plot);
                                if (out_res.contains ("Traceback") || out_res.contains ("Error") || out_res.contains ("✖")) {
                                    toast_requested (@"Failed to import '$base_name': $(out_res.strip ())");
                                } else {
                                    toast_requested (@"Imported dataset as '$var_name'");
                                }
                                refresh_environment.begin ();
                                view_dataframe_requested (var_name, "python");
                            });
                        }
                    }
                } catch (GLib.Error e) {
                    // Canceled or failed
                }
            });
        }

        private async void fetch_r_environment (Gee.ArrayList<EnvVariableItem> items) {
            string r_probe = """
local({
  objs <- ls(envir = .GlobalEnv, all.names = FALSE)
  res <- lapply(objs, function(x) {
    tryCatch({
      val <- get(x, envir = .GlobalEnv)
      cls <- paste(class(val), collapse=", ")
      dim_str <- if(!is.null(dim(val))) paste(dim(val), collapse = " × ") else if(length(val) > 0) as.character(length(val)) else ""
      sz <- format(object.size(val), units = "auto")
      is_df <- is.data.frame(val) || is.matrix(val) || inherits(val, "dgCMatrix") || inherits(val, "Seurat") || inherits(val, "DESeqDataSet") || inherits(val, "SummarizedExperiment")
      cols <- if(is.data.frame(val) || is.matrix(val) || inherits(val, "dgCMatrix")) paste(utils::head(colnames(val), 80), collapse=",") else if(isS4(val)) paste(utils::head(methods::slotNames(val), 40), collapse=",") else if(is.list(val) && !is.null(names(val))) paste(utils::head(names(val), 80), collapse=",") else ""
      paste(x, cls, dim_str, sz, if(is_df) "1" else "0", cols, sep="\t")
    }, error = function(e) "")
  })
  cat("___IMLADRIS_ENV_START___\n")
  cat(unlist(res[nchar(unlist(res)) > 0]), sep="\n")
  cat("___IMLADRIS_ENV_END___\n")
})
""";
            string? plot_out = null;
            string out_str = yield get_session_manager ().execute_r_with_options (r_probe, null, null, 15000, false, out plot_out);
            parse_env_output (out_str, items, "r");
        }

        private async void fetch_python_environment (Gee.ArrayList<EnvVariableItem> items) {
            string py_probe = """
def _imladris_env_probe():
    import sys
    def _fmt_sz(n):
        if n >= 1073741824: return f"{n/1073741824:.1f} GB"
        if n >= 1048576: return f"{n/1048576:.1f} MB"
        if n >= 1024: return f"{n/1024:.1f} KB"
        return f"{n} bytes"
    res = []
    _ns = globals()
    for k in list(_ns.keys()):
        if not k.startswith('_') and k not in ('In', 'Out', 'get_ipython', 'exit', 'quit', 'sys', 'os'):
            try:
                v = _ns[k]
                cls = type(v).__name__
                dim_str = str(getattr(v, 'shape', len(v) if hasattr(v, '__len__') else ''))
                if hasattr(v, 'estimated_size'):
                    nbytes = int(v.estimated_size())
                elif hasattr(v, 'memory_usage'):
                    _deep = (len(v) <= 50000) if hasattr(v, '__len__') else False
                    nbytes = int(v.memory_usage(deep=_deep).sum())
                elif hasattr(v, 'nbytes'):
                    nbytes = int(v.nbytes)
                elif hasattr(v, 'X') and hasattr(v.X, 'data') and hasattr(v.X.data, 'nbytes'):
                    nbytes = int(v.X.data.nbytes)
                else:
                    nbytes = sys.getsizeof(v)
                sz = _fmt_sz(nbytes)
                is_df = "1" if hasattr(v, 'columns') or hasattr(v, 'obs') or (hasattr(v, 'shape') and hasattr(v.shape, '__len__') and len(v.shape) == 2) else "0"
                cols = ",".join([str(c) for c in list(v.columns)[:80]]) if hasattr(v, 'columns') else (",".join([str(c) for c in list(v.obs.columns)[:40]]) if hasattr(v, 'obs') and hasattr(v.obs, 'columns') else "")
                res.append(f"{k}\t{cls}\t{dim_str}\t{sz}\t{is_df}\t{cols}")
            except Exception:
                pass
    print("___IMLADRIS_ENV_START___")
    print("\n".join(res))
    print("___IMLADRIS_ENV_END___")
_imladris_env_probe()
del _imladris_env_probe
""";
            string? plot_out = null;
            string out_str = yield get_session_manager ().execute_python_with_options (py_probe, null, null, 15000, false, out plot_out);
            parse_env_output (out_str, items, "python");
        }

        private void parse_env_output (string raw, Gee.ArrayList<EnvVariableItem> items, string engine) {
            if (!raw.contains ("___IMLADRIS_ENV_START___")) return;
            int start_idx = raw.index_of ("___IMLADRIS_ENV_START___") + "___IMLADRIS_ENV_START___".length;
            int end_idx = raw.index_of ("___IMLADRIS_ENV_END___");
            if (end_idx < start_idx) return;

            string block = raw.substring (start_idx, end_idx - start_idx).strip ();
            string[] lines = block.split ("\n");
            bool show_badge = (active_engine.down ().strip () == "polyglot");
            string badge = (engine == "r") ? "[R] " : "[Py] ";
            foreach (var line in lines) {
                string[] parts = line.strip ().split ("\t");
                if (parts.length >= 5) {
                    string name = parts[0].strip ();
                    string cls = (show_badge ? badge : "") + parts[1].strip ();
                    string dims = parts[2].strip ();
                    string sz = parts[3].strip ();
                    bool is_df = (parts[4].strip () == "1");
                    string cols = parts.length >= 6 ? parts[5].strip () : "";
                    items.add (new EnvVariableItem (name, cls, dims, sz, is_df, "", engine, cols));
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
                subtitle = @"$(item.var_type)$(item.dimensions != "" ? @" • $(item.dimensions)" : "")$(item.memory_size != "" ? @" • $(item.memory_size)" : "")",
                use_markup = false
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
                string obj_eng = item.var_engine;
                view_btn.clicked.connect (() => {
                    view_dataframe_requested (obj_to_view, obj_eng);
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
            string vengine = item.var_engine;
            expander_row.notify["expanded"].connect (() => {
                if (expander_row.expanded && !fetched) {
                    fetched = true;
                    fetch_variable_summary.begin (vname, vengine, summary_label);
                }
            });

            expander_row.add_row (new Adw.ActionRow () { child = summary_box });
            list_box.append (expander_row);
        }

        private async void fetch_variable_summary (string var_name, string var_engine, Gtk.Label target_label) {
            target_label.label = "Loading summary...";
            if (var_engine == "r") {
                string hex_name = Core.PlatformUtils.encode_hex (var_name.data);
                string r_cmd = """
local({
  .hex <- '%s'
  .vname <- if (nzchar(.hex)) { .idx <- seq.int(1L, nchar(.hex), by = 2L); .s <- rawToChar(as.raw(strtoi(substring(.hex, .idx, .idx + 1L), 16L))); Encoding(.s) <- 'UTF-8'; .s } else ''
  v <- get(.vname, envir = .GlobalEnv)
  cat('--- str() ---\n')
  str(v, max.level = 2, list.len = 25)
  cat('\n--- summary() ---\n')
  print(summary(v))
})
""".printf (hex_name);
                string? plot_out = null;
                string res = yield get_session_manager ().execute_r_with_options (r_cmd, null, null, 15000, false, out plot_out);
                target_label.label = res.strip ().length > 0 ? res.strip () : "No summary available.";
            } else {
                string b64_name = GLib.Base64.encode (var_name.data);
                string py_cmd = """
import base64
try:
    _vname = base64.b64decode('%s').decode('utf-8')
    if _vname not in globals():
        raise KeyError(f"Variable '{_vname}' not found")
    v = globals()[_vname]
    if hasattr(v, 'info'):
        import io
        buf = io.StringIO()
        v.info(buf=buf)
        print(buf.getvalue())
    if hasattr(v, 'describe'):
        print(v.describe().to_string()[:4000])
    elif hasattr(v, '__repr__'):
        r = repr(v)
        print(r[:4000] + ('\n... [truncated]' if len(r) > 4000 else ''))
except Exception as e:
    print(str(e))
""".printf (b64_name);
                string? plot_out = null;
                string res = yield get_session_manager ().execute_python_with_options (py_cmd, null, null, 15000, false, out plot_out);
                target_label.label = res.strip ().length > 0 ? res.strip () : "No summary available.";
            }
        }
    }
}
