// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using Imladris.Core.Layout;

namespace Imladris.UI {

    public class PackageItem : GLib.Object {
        public string name { get; construct set; }
        public string version { get; construct set; }
        public string description { get; construct set; }
        public bool is_loaded { get; construct set; }

        public PackageItem (string name, string ver, string desc, bool loaded = false) {
            Object (name: name, version: ver, description: desc, is_loaded: loaded);
        }
    }

    public class PersistentPanelRegistry : GLib.Object {

        private Gee.HashMap<PanelId, Gtk.Widget> panels;
        private unowned DocumentPage doc_page;
        private unowned Window? main_window;

        // Exposed widgets for DocumentPage integration
        public Gtk.Box source_editor_panel { get; private set; }
        public Gtk.Box notebook_cell_toolbar { get; private set; }
        public Gtk.Box live_preview_panel { get; private set; }
        public Gtk.Box console_panel { get; private set; }
        public Gtk.TextView terminal_view { get; private set; }
        public EnvironmentController environment_controller { get; private set; }
        public DataGridViewer data_grid_viewer { get; private set; }
        public ElrondChatPanel elrond_chat_panel { get; private set; }
        public Gtk.ListBox outline_list { get; private set; }
        public Gtk.ListBox citations_list { get; private set; }
        public WebKit.WebView plots_webview { get; private set; }
        public Gtk.ListBox files_list { get; private set; }
        public Gtk.ListBox history_list { get; private set; }
        public Gtk.ListBox packages_list { get; private set; }
        public Gtk.Entry repl_entry { get; private set; }
        public WebKit.WebView help_view { get; private set; }
        public WebKit.WebView shiny_webview { get; private set; }
        public GalaxyPanel galaxy_panel { get; private set; }
        public WebSyncPanel web_sync_panel { get; private set; }

        private Gtk.Label? shiny_status_lbl = null;
        private Gtk.Button? btn_shiny_refresh = null;
        private Gtk.Button? btn_shiny_popout = null;
        private Gtk.Button? btn_shiny_browser = null;
        private Gtk.Button? btn_shiny_stop = null;
        private ShinyWindow? active_shiny_window = null;

        private Gtk.Label? files_dir_lbl = null;
        private string current_browser_dir = "";
        private string root_project_dir = "";

        private int execution_counter = 0;

        // Plot Gallery State
        private Gee.ArrayList<string> plot_gallery;
        private int active_plot_idx = -1;
        private Gtk.Button btn_prev_plot;
        private Gtk.Button btn_next_plot;
        private Gtk.Label plot_index_label;
        private Gtk.Button btn_zoom_plot;
        private Gtk.Button btn_copy_plot;
        private Gtk.Button btn_export_plot;
        private Gtk.Button btn_remove_plot;
        private Gtk.Button btn_clear_all_plots;

        // Files Selection State
        private string? selected_file_path = null;
        private bool selected_is_dir = false;

        // Packages State
        private Gee.ArrayList<PackageItem> installed_packages;
        private Gtk.SearchEntry packages_search_entry;

        // Singleton signal handler IDs for deterministic cleanup on tab close
        private ulong hist_added_hid = 0;
        private ulong hist_cleared_hid = 0;
        private ulong sess_cwd_hid = 0;
        private ulong sess_plot_hid = 0;
        private ulong shiny_status_hid = 0;
        private ulong shiny_url_hid = 0;
        private uint cit_search_debounce_id = 0;
        private GLib.Cancellable? active_exec_cancellable = null;
        private static GLib.Regex? view_call_regex = null;

        ~PersistentPanelRegistry () {
            cleanup ();
        }

        public string get_session_key () {
            if (doc_page.current_project_dir != "") {
                return doc_page.current_project_dir;
            }
            if (doc_page.file_location != null) {
                var parent = doc_page.file_location.get_parent ();
                if (parent != null && parent.get_path () != null) {
                    return parent.get_path ();
                }
                return doc_page.file_location.get_path () ?? "default";
            }
            return "default";
        }

        private Services.PersistentSessionManager? cached_session_mgr = null;
        private string? acquired_session_key = null;
        private ulong preview_backend_hid = 0;
        private bool syncing_preview_selector = false;

        public Services.PersistentSessionManager get_session_manager () {
            string key = get_session_key ();
            if (cached_session_mgr == null || acquired_session_key != key) {
                if (acquired_session_key != null) {
                    if (cached_session_mgr != null) {
                        if (sess_cwd_hid != 0) { cached_session_mgr.disconnect (sess_cwd_hid); sess_cwd_hid = 0; }
                        if (sess_plot_hid != 0) { cached_session_mgr.disconnect (sess_plot_hid); sess_plot_hid = 0; }
                    }
                    Services.PersistentSessionManager.release_session (acquired_session_key);
                }
                acquired_session_key = key;
                cached_session_mgr = Services.PersistentSessionManager.for_key (key);
            }
            return cached_session_mgr;
        }

        public PersistentPanelRegistry (DocumentPage page, Window? win) {
            this.doc_page = page;
            this.main_window = win;
            this.panels = new Gee.HashMap<PanelId, Gtk.Widget> ();
            this.plot_gallery = new Gee.ArrayList<string> ();
            this.installed_packages = new Gee.ArrayList<PackageItem> ();

            build_all_persistent_panels ();
        }

        public void cleanup () {
            if (active_exec_cancellable != null) {
                active_exec_cancellable.cancel ();
                active_exec_cancellable = null;
            }
            if (cit_search_debounce_id != 0) {
                GLib.Source.remove (cit_search_debounce_id);
                cit_search_debounce_id = 0;
            }
            var hist = Services.HistoryManager.get_default ();
            if (hist_added_hid != 0) { hist.disconnect (hist_added_hid); hist_added_hid = 0; }
            if (hist_cleared_hid != 0) { hist.disconnect (hist_cleared_hid); hist_cleared_hid = 0; }

            if (cached_session_mgr != null) {
                if (sess_cwd_hid != 0) { cached_session_mgr.disconnect (sess_cwd_hid); sess_cwd_hid = 0; }
                if (sess_plot_hid != 0) { cached_session_mgr.disconnect (sess_plot_hid); sess_plot_hid = 0; }
                cached_session_mgr = null;
            }
            if (acquired_session_key != null) {
                Services.PersistentSessionManager.release_session (acquired_session_key);
                acquired_session_key = null;
            }

            var shiny = Services.ShinyService.get_default ();
            if (shiny_status_hid != 0) { shiny.disconnect (shiny_status_hid); shiny_status_hid = 0; }
            if (shiny_url_hid != 0) { shiny.disconnect (shiny_url_hid); shiny_url_hid = 0; }
            if (preview_backend_hid != 0) {
                Core.SettingsManager.get_default ().disconnect (preview_backend_hid);
                preview_backend_hid = 0;
            }
            if (active_shiny_window != null) {
                active_shiny_window.destroy ();
                active_shiny_window = null;
            }
            if (web_sync_panel != null) {
                web_sync_panel.cleanup ();
            }
            detach_all ();
            panels.clear ();
        }

        private async void run_citation_search_async (string q, Services.ZoteroService zotero_svc) {
            string? fallback_bib = null;
            string base_dir = doc_page.current_project_dir;
            if (base_dir == "" && doc_page.file_location != null) {
                var parent = doc_page.file_location.get_parent ();
                if (parent != null) base_dir = parent.get_path () ?? "";
            }
            string bib_rel = "references.bib";
            Core.FrontmatterData? fm = null;
            string fm_body = "";
            Core.FrontmatterParser.split_frontmatter (doc_page.get_clean_source_text (), out fm, out fm_body);
            if (fm != null && fm.bibliography != null && fm.bibliography.strip () != "") {
                bib_rel = fm.bibliography.strip ();
            }
            if (base_dir != "" || GLib.Path.is_absolute (bib_rel)) {
                string bib_path = GLib.Path.is_absolute (bib_rel)
                    ? bib_rel
                    : GLib.Path.build_filename (base_dir, bib_rel);
                var f = GLib.File.new_for_path (bib_path);
                if (f.query_exists ()) {
                    try {
                        uint8[] data;
                        string? etag = null;
                        yield f.load_contents_async (null, out data, out etag);
                        fallback_bib = Core.PlatformUtils.data_to_string (data);
                    } catch (GLib.Error e) {
                        GLib.debug ("Failed to load local %s: %s", bib_path, e.message);
                    }
                }
            }

            var items = yield zotero_svc.search_citations_async (q, fallback_bib);
            var child = citations_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                citations_list.remove (child);
                child = next;
            }

            if (items.size == 0) {
                var empty_row = new Adw.ActionRow () {
                    title = "No citations found",
                    subtitle = @"No matches for '$q' in Zotero or references.bib",
                    use_markup = false
                };
                empty_row.add_prefix (new Gtk.Image.from_icon_name ("system-search-symbolic"));
                citations_list.append (empty_row);
                return;
            }

            foreach (var item in items) {
                var row = new Adw.ActionRow () {
                    title = @"@$(item.citekey)",
                    subtitle = @"$(item.authors) ($(item.year)) — $(item.title)",
                    use_markup = false
                };
                row.add_prefix (new Gtk.Image.from_icon_name ("accessories-dictionary-symbolic"));

                var ins_btn = new Gtk.Button.from_icon_name ("insert-text-symbolic") {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = "Insert citation [@key]"
                };
                ins_btn.add_css_class ("flat");
                string k = item.citekey;
                ins_btn.clicked.connect (() => {
                    doc_page.source_buffer.begin_user_action ();
                    doc_page.source_buffer.insert_at_cursor (@"[@$k]", -1);
                    doc_page.source_buffer.end_user_action ();
                    Editor.CitationCompletionProvider.ensure_buffer_bibliography_line (doc_page.source_buffer, "references.bib");
                    zotero_svc.sync_citation_to_project_async.begin (k, doc_page.current_project_dir);
                });
                row.add_suffix (ins_btn);

                var open_btn = new Gtk.Button.from_icon_name ("system-run-symbolic") {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = "Highlight item in Zotero desktop"
                };
                open_btn.add_css_class ("flat");
                open_btn.clicked.connect (() => {
                    try {
                        string zot_uri = zotero_svc.get_zotero_select_uri (k);
                        GLib.AppInfo.launch_default_for_uri (zot_uri, null);
                    } catch (GLib.Error e) {
                        GLib.debug ("Failed to launch Zotero URI: %s", e.message);
                    }
                });
                row.add_suffix (open_btn);

                citations_list.append (row);
            }
        }

        public Gtk.Widget? get_panel_widget (PanelId id) {
            return panels.get (id);
        }

        /**
         * Portal / Host Re-parenting Pattern:
         * Detaches the persistent widget from its previous parent container (if any)
         * and mounts it inside the target viewport without destroying the widget or undo stack.
         */
        public Gtk.Widget? get_panel (PanelId id) {
            return panels.get (id);
        }

        public void mount_panel (PanelId id, Gtk.Box target_viewport) {
            var widget = panels.get (id);
            if (widget == null) return;

            var current_parent = widget.get_parent ();
            if (current_parent == target_viewport) {
                widget.visible = true;
                return;
            }
            if (current_parent != null) {
                var parent_box = current_parent as Gtk.Box;
                if (parent_box != null) {
                    parent_box.remove (widget);
                } else {
                    widget.unparent ();
                }
            }

            widget.hexpand = true;
            widget.vexpand = true;
            widget.visible = true;
            target_viewport.append (widget);
        }

        public void detach_all () {
            foreach (var entry in panels.entries) {
                var w = entry.value;
                var p = w.get_parent ();
                if (p != null) {
                    var pb = p as Gtk.Box;
                    if (pb != null) {
                        pb.remove (w);
                    } else {
                        w.unparent ();
                    }
                }
            }
        }

        private void build_all_persistent_panels () {
            // 1. SOURCE EDITOR PANEL (with .ipynb / RStudio Cell Execution Toolbar)
            source_editor_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };

            notebook_cell_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 3,
                margin_bottom = 3,
                margin_start = 6,
                margin_end = 6
            };
            notebook_cell_toolbar.add_css_class ("dock-subtoolbar");

            var run_cell_btn = new Gtk.Button () {
                tooltip_text = "Execute active code cell or chunk (Ctrl+Shift+Enter)"
            };
            run_cell_btn.add_css_class ("flat");
            run_cell_btn.add_css_class ("ribbon-compact-btn");
            var rc_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            rc_box.append (new Gtk.Image.from_icon_name ("media-playback-start-symbolic"));
            rc_box.append (new Gtk.Label ("Run Cell"));
            run_cell_btn.set_child (rc_box);
            run_cell_btn.clicked.connect (() => {
                execute_active_cell ();
            });
            notebook_cell_toolbar.append (run_cell_btn);

            var run_advance_btn = new Gtk.Button () {
                tooltip_text = "Execute active cell and advance to next (Shift+Enter)"
            };
            run_advance_btn.add_css_class ("flat");
            run_advance_btn.add_css_class ("ribbon-compact-btn");
            var radv_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            radv_box.append (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            radv_box.append (new Gtk.Label ("Run & Advance"));
            run_advance_btn.set_child (radv_box);
            run_advance_btn.clicked.connect (() => {
                execute_active_cell_and_advance ();
            });
            notebook_cell_toolbar.append (run_advance_btn);

            var run_all_btn = new Gtk.Button () {
                tooltip_text = "Execute all code cells sequentially (Ctrl+Alt+R)"
            };
            run_all_btn.add_css_class ("flat");
            run_all_btn.add_css_class ("ribbon-compact-btn");
            var ra_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            ra_box.append (new Gtk.Image.from_icon_name ("media-seek-forward-symbolic"));
            ra_box.append (new Gtk.Label ("Run All"));
            run_all_btn.set_child (ra_box);
            run_all_btn.clicked.connect (() => {
                execute_all_cells ();
            });
            notebook_cell_toolbar.append (run_all_btn);

            var clear_out_btn = new Gtk.Button () {
                tooltip_text = "Clear all console and cell outputs (Ctrl+L)"
            };
            clear_out_btn.add_css_class ("flat");
            clear_out_btn.add_css_class ("ribbon-compact-btn");
            var clr_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            clr_box.append (new Gtk.Image.from_icon_name ("edit-clear-symbolic"));
            clr_box.append (new Gtk.Label ("Clear"));
            clear_out_btn.set_child (clr_box);
            clear_out_btn.clicked.connect (() => {
                clear_all_outputs ();
            });
            notebook_cell_toolbar.append (clear_out_btn);

            var restart_k_btn = new Gtk.Button () {
                tooltip_text = "Restart execution kernel and reset state (Ctrl+Shift+F10)"
            };
            restart_k_btn.add_css_class ("flat");
            restart_k_btn.add_css_class ("ribbon-compact-btn");
            var rst_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            rst_box.append (new Gtk.Image.from_icon_name ("view-refresh-symbolic"));
            rst_box.append (new Gtk.Label ("Restart"));
            restart_k_btn.set_child (rst_box);
            restart_k_btn.clicked.connect (() => {
                restart_kernel ();
            });
            notebook_cell_toolbar.append (restart_k_btn);

            notebook_cell_toolbar.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

            var add_py_btn = new Gtk.Button.with_label ("+ Python") {
                tooltip_text = "Insert executable Python code chunk"
            };
            add_py_btn.add_css_class ("flat");
            add_py_btn.add_css_class ("ribbon-compact-btn");
            add_py_btn.clicked.connect (() => {
                doc_page.insert_code_chunk ("python", "echo: true");
            });
            notebook_cell_toolbar.append (add_py_btn);

            var add_r_btn = new Gtk.Button.with_label ("+ R") {
                tooltip_text = "Insert executable R code chunk"
            };
            add_r_btn.add_css_class ("flat");
            add_r_btn.add_css_class ("ribbon-compact-btn");
            add_r_btn.clicked.connect (() => {
                doc_page.insert_code_chunk ("r", "echo: true");
            });
            notebook_cell_toolbar.append (add_r_btn);

            var add_md_btn = new Gtk.Button.with_label ("+ Markdown") {
                tooltip_text = "Insert Markdown narrative section"
            };
            add_md_btn.add_css_class ("flat");
            add_md_btn.add_css_class ("ribbon-compact-btn");
            add_md_btn.clicked.connect (() => {
                doc_page.insert_markdown_cell ();
            });
            notebook_cell_toolbar.append (add_md_btn);

            var add_math_chem_btn = new Gtk.Button.with_label ("+ Math/Chem") {
                tooltip_text = "Open Math & Chemical Reaction Studio (Ctrl+M)"
            };
            add_math_chem_btn.add_css_class ("flat");
            add_math_chem_btn.add_css_class ("ribbon-compact-btn");
            add_math_chem_btn.clicked.connect (() => {
                if (main_window != null) {
                    main_window.show_math_chem_editor_dialog ();
                }
            });
            notebook_cell_toolbar.append (add_math_chem_btn);

            var cell_toolbar_scroll = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.NEVER,
                hexpand = true,
                child = notebook_cell_toolbar
            };
            source_editor_panel.append (cell_toolbar_scroll);
            source_editor_panel.append ((doc_page.rtf_editor != null) ? (Gtk.Widget) doc_page.rtf_editor : (Gtk.Widget) doc_page.editor_scroller);
            panels.set (PanelId.SOURCE_EDITOR, source_editor_panel);

            // 2. LIVE PREVIEW PANEL
            live_preview_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var preview_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            var preview_lbl = new Gtk.Label ("Preview") {
                css_classes = { "dim-label", "caption" }
            };
            preview_bar.append (preview_lbl);

            var preview_modes = new Gtk.StringList ({
                "WebKitGTK 6.0 (HTML5)",
                "Native GTK4 / Pango",
                "Native PDF Pages (Cairo)"
            });
            var preview_selector = new Gtk.DropDown (preview_modes, null) {
                valign = Gtk.Align.CENTER,
                tooltip_text = "Choose Live Preview Engine",
                selected = (uint) Core.SettingsManager.get_default ().preview_backend
            };
            preview_selector.add_css_class ("flat");
            preview_selector.notify["selected"].connect (() => {
                if (syncing_preview_selector) return;
                Core.SettingsManager.get_default ().preview_backend = (Core.PreviewBackend) preview_selector.selected;
            });
            unowned Gtk.DropDown preview_sel_ref = preview_selector;
            preview_backend_hid = Core.SettingsManager.get_default ().preview_backend_changed.connect ((pb) => {
                syncing_preview_selector = true;
                preview_sel_ref.selected = (uint) pb;
                syncing_preview_selector = false;
            });
            preview_bar.append (preview_selector);
            preview_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            var refresh_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh Live Preview"
            };
            refresh_btn.add_css_class ("flat");
            refresh_btn.clicked.connect (() => {
                doc_page.refresh_live_preview ();
            });
            preview_bar.append (refresh_btn);

            live_preview_panel.append (preview_bar);
            live_preview_panel.append (doc_page.preview_stack);
            panels.set (PanelId.LIVE_PREVIEW, live_preview_panel);

            // 3. CONSOLE PANEL (REPL & Cell Execution Stream with In [n]: / Out [n]:)
            console_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var console_scroller = new Gtk.ScrolledWindow () {
                child = doc_page.console_view,
                hexpand = true,
                vexpand = true
            };
            console_panel.append (console_scroller);

            var repl_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6
            };
            var kernel_drop = new Gtk.DropDown.from_strings ({ "Python 3", "Rscript", "Bash" });
            var fmt_profile = Core.FormatProfile.for_format (doc_page.get_document_format ());
            string def_k = fmt_profile.default_kernel.down ().strip ();
            if (def_k == "r" || def_k == "rscript") {
                kernel_drop.selected = 1;
            } else if (def_k == "bash" || def_k == "sh") {
                kernel_drop.selected = 2;
            } else {
                kernel_drop.selected = 0;
            }
            repl_bar.append (kernel_drop);

            repl_entry = new Gtk.Entry () {
                placeholder_text = "Evaluate expression in kernel (e.g. 2 + 2, ?plot, print(sys.version))...",
                hexpand = true
            };
            var eval_btn = new Gtk.Button.with_label ("Execute");
            eval_btn.add_css_class ("suggested-action");

            var repl_key_ctrl = new Gtk.EventControllerKey ();
            repl_key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Up) {
                    string? prev = Services.HistoryManager.get_default ().navigate_up (repl_entry.text);
                    if (prev != null) {
                        repl_entry.text = prev;
                        repl_entry.set_position (-1);
                        return true;
                    }
                } else if (keyval == Gdk.Key.Down) {
                    string? next_cmd = Services.HistoryManager.get_default ().navigate_down ();
                    if (next_cmd != null) {
                        repl_entry.text = next_cmd;
                        repl_entry.set_position (-1);
                        return true;
                    }
                } else if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && (keyval == Gdk.Key.l || keyval == Gdk.Key.L)) {
                    doc_page.console_view.buffer.text = "";
                    return true;
                }
                return false;
            });
            repl_entry.add_controller (repl_key_ctrl);

            repl_entry.activate.connect (() => {
                eval_btn.activate ();
            });
            eval_btn.clicked.connect (() => {
                string cmd_text = repl_entry.text.strip ();
                if (cmd_text.length == 0) return;
                repl_entry.text = "";
                uint sel = kernel_drop.selected;
                string engine = sel == 1 ? "r" : (sel == 2 ? "bash" : "python");
                run_code_snippet_in_console (engine, cmd_text);
            });

            var stop_btn = new Gtk.Button.from_icon_name ("process-stop-symbolic") {
                tooltip_text = "Interrupt Execution (Stop / SIGINT)"
            };
            stop_btn.add_css_class ("flat");
            stop_btn.add_css_class ("destructive-action");
            stop_btn.clicked.connect (() => {
                if (active_exec_cancellable != null) {
                    active_exec_cancellable.cancel ();
                    active_exec_cancellable = null;
                }
                get_session_manager ().interrupt_active_execution ();
                doc_page.append_console_log ("\n[Execution interrupted by user]");
            });

            var clear_con_btn = new Gtk.Button.from_icon_name ("edit-clear-all-symbolic") {
                tooltip_text = "Clear Console (Ctrl+L)"
            };
            clear_con_btn.add_css_class ("flat");
            clear_con_btn.clicked.connect (() => {
                doc_page.console_view.buffer.text = "";
            });

            repl_bar.append (repl_entry);
            repl_bar.append (eval_btn);
            repl_bar.append (stop_btn);
            repl_bar.append (clear_con_btn);
            console_panel.append (repl_bar);
            panels.set (PanelId.CONSOLE, console_panel);

            // 4. TERMINAL PANEL
            var term_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            terminal_view = new Gtk.TextView () {
                editable = false,
                monospace = true,
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                top_margin = 10,
                bottom_margin = 10,
                left_margin = 10,
                right_margin = 10
            };
            terminal_view.buffer.text = "Imladris System Shell (bash)\nWorking Directory: " + GLib.Environment.get_current_dir () + "\n$ ";
            var term_scroll = new Gtk.ScrolledWindow () {
                child = terminal_view,
                hexpand = true,
                vexpand = true
            };
            var term_input_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6
            };
            var term_prompt_lbl = new Gtk.Label ("$") { css_classes = { "monospace", "heading" } };
            var term_entry = new Gtk.Entry () {
                placeholder_text = "Run shell command (e.g. ls -la, git status, quarto --version)...",
                hexpand = true
            };
            term_entry.activate.connect (() => {
                string c = term_entry.text.strip ();
                if (c.length == 0) return;
                term_entry.text = "";
                run_shell_command (c);
            });
            term_input_bar.append (term_prompt_lbl);
            term_input_bar.append (term_entry);
            term_box.append (term_scroll);
            term_box.append (term_input_bar);
            panels.set (PanelId.TERMINAL, term_box);

            // 5. ENVIRONMENT PANEL (Active Dataframe & Variable Inspector)
            environment_controller = new EnvironmentController (main_window);
            environment_controller.session_key = get_session_key ();
            environment_controller.view_dataframe_requested.connect ((name, eng) => {
                open_dataframe_in_viewer (name, eng);
            });
            environment_controller.toast_requested.connect ((msg) => {
                if (main_window != null) main_window.show_toast (msg);
            });
            panels.set (PanelId.ENVIRONMENT, environment_controller);

            // DATA VIEWER PANEL (Virtualized Matrix & Dataframe Inspector)
            data_grid_viewer = new DataGridViewer ();
            data_grid_viewer.session_key = get_session_key ();
            data_grid_viewer.close_requested.connect (() => {
                doc_page.rstudio_dock_grid.refresh_dock_layout ();
            });
            panels.set (PanelId.DATA_VIEWER, data_grid_viewer);

            // ELROND AI CHAT PANEL (Local Copilot Tab)
            elrond_chat_panel = new ElrondChatPanel (doc_page, this, main_window);
            panels.set (PanelId.ELROND_AI, elrond_chat_panel);

            // 6. OUTLINE PANEL (Document AST Table of Contents)
            var outline_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var outline_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            outline_bar.append (new Gtk.Label ("Document AST Outline (Click to jump)") { css_classes = { "dim-label", "caption" } });
            outline_box.append (outline_bar);

            outline_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
                margin_start = 6,
                margin_end = 6,
                margin_bottom = 6
            };
            outline_list.row_activated.connect ((row) => {
                int target_line = (int) row.get_data<int> ("target-line");
                Gtk.TextIter iter;
                doc_page.source_buffer.get_iter_at_line (out iter, target_line);
                doc_page.source_buffer.place_cursor (iter);
                doc_page.source_view.scroll_to_iter (iter, 0.15, true, 0.0, 0.3);
                doc_page.source_view.grab_focus ();
            });
            var outline_scroll = new Gtk.ScrolledWindow () {
                child = outline_list,
                hexpand = true,
                vexpand = true
            };
            outline_box.append (outline_scroll);
            panels.set (PanelId.OUTLINE, outline_box);

            // 7. CITATIONS PANEL (Zotero & BibTeX / CSL Bibliography Manager)
            var cit_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };

            var cit_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            cit_toolbar.add_css_class ("dock-subtoolbar");

            var zotero_status_badge = new Gtk.Label ("Zotero") {
                css_classes = { "caption", "dim-label" }
            };

            // Probe Zotero status
            var zotero_svc = Services.ZoteroService.get_default ();
            zotero_svc.is_zotero_running_async.begin ((obj, res) => {
                bool running = zotero_svc.is_zotero_running_async.end (res);
                if (running) {
                    zotero_status_badge.label = "● Zotero Connected";
                    zotero_status_badge.remove_css_class ("dim-label");
                    zotero_status_badge.add_css_class ("success");
                } else {
                    zotero_status_badge.label = "○ Zotero Offline (references.bib)";
                }
            });

            var btn_zotero_picker = new Gtk.Button.from_icon_name ("accessories-dictionary-symbolic") {
                tooltip_text = "Pick in Zotero (Ctrl+Shift+I)"
            };
            btn_zotero_picker.clicked.connect (() => {
                zotero_svc.open_native_citation_picker_async.begin ((obj, res) => {
                    string? cite = zotero_svc.open_native_citation_picker_async.end (res);
                    if (cite != null && cite.length > 0) {
                        doc_page.source_buffer.begin_user_action ();
                        doc_page.source_buffer.insert_at_cursor (cite, -1);
                        doc_page.source_buffer.end_user_action ();
                        refresh_environment_and_outline ();
                    }
                });
            });

            var cit_search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Search Zotero & references.bib...",
                hexpand = true
            };

            cit_toolbar.append (zotero_status_badge);
            cit_toolbar.append (cit_search_entry);
            cit_toolbar.append (btn_zotero_picker);
            cit_box.append (cit_toolbar);

            var cit_input_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            var cit_key_entry = new Gtk.Entry () {
                placeholder_text = "Quick citation key (e.g. knuth1984)...",
                hexpand = true
            };
            var cit_add_btn = new Gtk.Button.with_label ("Insert @key");
            cit_add_btn.clicked.connect (() => {
                string key = cit_key_entry.text.strip ().replace ("@", "");
                if (key.length > 0) {
                    doc_page.source_buffer.begin_user_action ();
                    doc_page.source_buffer.insert_at_cursor (@"[@$key]", -1);
                    doc_page.source_buffer.end_user_action ();
                    cit_key_entry.text = "";
                    refresh_environment_and_outline ();
                }
            });
            cit_input_row.append (cit_key_entry);
            cit_input_row.append (cit_add_btn);
            cit_box.append (cit_input_row);

            citations_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "boxed-list" }
            };

            cit_search_entry.search_changed.connect (() => {
                string q = cit_search_entry.text.strip ();
                if (q == "") {
                    refresh_environment_and_outline ();
                    return;
                }

                // Read local bib asynchronously if available
                if (cit_search_debounce_id != 0) {
                    GLib.Source.remove (cit_search_debounce_id);
                    cit_search_debounce_id = 0;
                }
                cit_search_debounce_id = GLib.Timeout.add (180, () => {
                    cit_search_debounce_id = 0;
                    run_citation_search_async.begin (q, zotero_svc);
                    return false;
                });
            });

            var cit_scroll = new Gtk.ScrolledWindow () {
                child = citations_list,
                hexpand = true,
                vexpand = true
            };
            cit_box.append (cit_scroll);
            panels.set (PanelId.CITATIONS, cit_box);

            // 8. HISTORY PANEL (RStudio Command History with Filter & Insertion)
            var history_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var hist_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            hist_bar.add_css_class ("dock-subtoolbar");
            hist_bar.append (new Gtk.Image.from_icon_name ("document-open-recent-symbolic"));

            var hist_search = new Gtk.SearchEntry () {
                placeholder_text = "Filter history...",
                hexpand = true
            };
            hist_search.search_changed.connect (() => {
                filter_history_ui (hist_search.text.strip ().down ());
            });
            hist_bar.append (hist_search);

            var to_console_btn = new Gtk.Button.from_icon_name ("utilities-terminal-symbolic") {
                tooltip_text = "To Console (Copy to Console Prompt)"
            };
            to_console_btn.add_css_class ("flat");
            to_console_btn.clicked.connect (history_to_console);
            hist_bar.append (to_console_btn);

            var to_source_btn = new Gtk.Button.from_icon_name ("document-edit-symbolic") {
                tooltip_text = "To Source (Insert at Cursor in Editor)"
            };
            to_source_btn.add_css_class ("flat");
            to_source_btn.clicked.connect (history_to_source);
            hist_bar.append (to_source_btn);

            var save_hist_btn = new Gtk.Button.from_icon_name ("document-save-symbolic") {
                tooltip_text = "Save History (.Rhistory)"
            };
            save_hist_btn.add_css_class ("flat");
            save_hist_btn.clicked.connect (save_history_dialog);
            hist_bar.append (save_hist_btn);

            var clear_hist_btn = new Gtk.Button.from_icon_name ("edit-clear-all-symbolic") {
                tooltip_text = "Clear History"
            };
            clear_hist_btn.add_css_class ("flat");
            clear_hist_btn.clicked.connect (() => {
                Services.HistoryManager.get_default ().clear ();
            });
            hist_bar.append (clear_hist_btn);

            history_box.append (hist_bar);

            history_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
                css_classes = { "boxed-list" },
                margin_start = 6,
                margin_end = 6,
                margin_bottom = 6
            };
            history_list.row_activated.connect ((row) => {
                string? cmd = row.get_data<string> ("cmd-text");
                if (cmd != null && repl_entry != null) {
                    repl_entry.text = cmd;
                    repl_entry.grab_focus ();
                    repl_entry.set_position (-1);
                }
            });
            var hist_scroll = new Gtk.ScrolledWindow () {
                child = history_list,
                hexpand = true,
                vexpand = true
            };
            history_box.append (hist_scroll);
            panels.set (PanelId.HISTORY, history_box);

            // Populate initial history from HistoryManager
            var initial_entries = Services.HistoryManager.get_default ().get_all_entries ();
            foreach (var ent in initial_entries) {
                add_history_row (ent);
            }
            hist_added_hid = Services.HistoryManager.get_default ().entry_added.connect ((entry) => {
                add_history_row (entry);
            });
            hist_cleared_hid = Services.HistoryManager.get_default ().history_cleared.connect (() => {
                clear_history_ui ();
            });

            // 9. PLOTS PANEL (RStudio-Compatible Multi-Plot Gallery & Deck)
            var plots_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var plots_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            plots_bar.add_css_class ("dock-subtoolbar");

            btn_prev_plot = new Gtk.Button.from_icon_name ("go-previous-symbolic") {
                tooltip_text = "Previous Plot",
                sensitive = false
            };
            btn_prev_plot.add_css_class ("flat");
            btn_prev_plot.clicked.connect (() => {
                if (active_plot_idx > 0) {
                    active_plot_idx--;
                    update_plot_view ();
                }
            });
            plots_bar.append (btn_prev_plot);

            btn_next_plot = new Gtk.Button.from_icon_name ("go-next-symbolic") {
                tooltip_text = "Next Plot",
                sensitive = false
            };
            btn_next_plot.add_css_class ("flat");
            btn_next_plot.clicked.connect (() => {
                if (active_plot_idx < plot_gallery.size - 1) {
                    active_plot_idx++;
                    update_plot_view ();
                }
            });
            plots_bar.append (btn_next_plot);

            plot_index_label = new Gtk.Label ("No Plots") {
                css_classes = { "dim-label", "caption" },
                margin_start = 4,
                margin_end = 4
            };
            plots_bar.append (plot_index_label);

            plots_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            btn_zoom_plot = new Gtk.Button.from_icon_name ("zoom-in-symbolic") {
                tooltip_text = "Zoom Plot in Floating Window",
                sensitive = false
            };
            btn_zoom_plot.add_css_class ("flat");
            btn_zoom_plot.clicked.connect (zoom_active_plot);
            plots_bar.append (btn_zoom_plot);

            btn_copy_plot = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy Plot to Clipboard",
                sensitive = false
            };
            btn_copy_plot.add_css_class ("flat");
            btn_copy_plot.clicked.connect (copy_active_plot_to_clipboard);
            plots_bar.append (btn_copy_plot);

            btn_export_plot = new Gtk.Button.from_icon_name ("document-save-as-symbolic") {
                tooltip_text = "Export Plot to File...",
                sensitive = false
            };
            btn_export_plot.add_css_class ("flat");
            btn_export_plot.clicked.connect (export_active_plot_dialog);
            plots_bar.append (btn_export_plot);

            btn_remove_plot = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                tooltip_text = "Remove Current Plot",
                sensitive = false
            };
            btn_remove_plot.add_css_class ("flat");
            btn_remove_plot.clicked.connect (remove_active_plot);
            plots_bar.append (btn_remove_plot);

            btn_clear_all_plots = new Gtk.Button.from_icon_name ("edit-clear-all-symbolic") {
                tooltip_text = "Clear All Plots",
                sensitive = false
            };
            btn_clear_all_plots.add_css_class ("flat");
            btn_clear_all_plots.clicked.connect (clear_all_plots);
            plots_bar.append (btn_clear_all_plots);

            plots_box.append (plots_bar);

            plots_webview = WebViewFactory.create ();
            plots_box.append (plots_webview);
            bool plots_initialized = false;
            plots_webview.map.connect (() => {
                if (!plots_initialized) {
                    plots_initialized = true;
                    update_plot_view ();
                }
            });
            panels.set (PanelId.PLOTS, plots_box);

            // 10. FILES PANEL (Project Directory Browser with RStudio Actions)
            var files_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var files_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            files_bar.add_css_class ("dock-subtoolbar");

            files_dir_lbl = new Gtk.Label ("📁 Workspace") {
                css_classes = { "dim-label", "caption" },
                ellipsize = Pango.EllipsizeMode.START,
                max_width_chars = 20
            };
            files_bar.append (files_dir_lbl);
            files_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            var up_btn = new Gtk.Button.from_icon_name ("go-up-symbolic") {
                tooltip_text = "Up to Parent Directory"
            };
            up_btn.add_css_class ("flat");
            up_btn.clicked.connect (() => {
                navigate_files_up ();
            });
            files_bar.append (up_btn);

            var home_btn = new Gtk.Button.from_icon_name ("go-home-symbolic") {
                tooltip_text = "Go to Project Root"
            };
            home_btn.add_css_class ("flat");
            home_btn.clicked.connect (() => {
                navigate_files_home ();
            });
            files_bar.append (home_btn);

            var new_folder_btn = new Gtk.Button.from_icon_name ("folder-new-symbolic") {
                tooltip_text = "New Folder"
            };
            new_folder_btn.add_css_class ("flat");
            new_folder_btn.clicked.connect (prompt_new_folder);
            files_bar.append (new_folder_btn);

            var new_file_btn = new Gtk.Button.from_icon_name ("document-new-symbolic") {
                tooltip_text = "New Blank File"
            };
            new_file_btn.add_css_class ("flat");
            new_file_btn.clicked.connect (prompt_new_file);
            files_bar.append (new_file_btn);

            var del_file_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                tooltip_text = "Delete Selected File or Directory"
            };
            del_file_btn.add_css_class ("flat");
            del_file_btn.clicked.connect (prompt_delete_selected_file);
            files_bar.append (del_file_btn);

            var ren_file_btn = new Gtk.Button.from_icon_name ("document-edit-symbolic") {
                tooltip_text = "Rename Selected File or Directory"
            };
            ren_file_btn.add_css_class ("flat");
            ren_file_btn.clicked.connect (prompt_rename_selected_file);
            files_bar.append (ren_file_btn);

            var more_btn = new Gtk.MenuButton () {
                icon_name = "view-more-symbolic",
                tooltip_text = "More File Options..."
            };
            more_btn.add_css_class ("flat");
            more_btn.popover = create_files_more_popover ();
            files_bar.append (more_btn);

            var refresh_files_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh Workspace Files"
            };
            refresh_files_btn.add_css_class ("flat");
            refresh_files_btn.clicked.connect (() => {
                populate_files_browser ();
            });
            files_bar.append (refresh_files_btn);
            files_box.append (files_bar);

            files_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
                margin_start = 6,
                margin_end = 6,
                margin_bottom = 6
            };
            files_list.row_selected.connect ((row) => {
                if (row != null) {
                    selected_file_path = row.get_data<string> ("file-path");
                    selected_is_dir = row.get_data<bool> ("is-dir");
                } else {
                    selected_file_path = null;
                }
            });
            files_list.row_activated.connect ((row) => {
                bool is_dir = row.get_data<bool> ("is-dir");
                string? fpath = row.get_data<string> ("file-path");
                if (fpath == null) return;
                if (is_dir) {
                    current_browser_dir = fpath;
                    populate_files_browser ();
                } else {
                    string lower_f = fpath.down ();
                    if (lower_f.has_suffix (".csv") || lower_f.has_suffix (".tsv") ||
                        lower_f.has_suffix (".csv.gz") || lower_f.has_suffix (".tsv.gz") ||
                        lower_f.has_suffix (".vcf") || lower_f.has_suffix (".vcf.gz") ||
                        lower_f.has_suffix (".bed") || lower_f.has_suffix (".gtf")) {
                        data_grid_viewer.load_delimited_file (fpath);
                        doc_page.dock_layout_state.activate_tab (QuadrantId.Q1_TOP_LEFT, PanelId.DATA_VIEWER);
                        string bname = GLib.Path.get_basename (fpath);
                        string safe_p = fpath.replace ("\\", "/").replace ("'", "\\'");
                        bool is_tab = !lower_f.has_suffix (".csv") && !lower_f.has_suffix (".csv.gz");
                        string r_fn = is_tab ? "read.delim" : "read.csv";
                        string py_sep = is_tab ? ", sep='\\t'" : "";
                        doc_page.append_console_log (@"📊 Previewing '$bname' in Data Viewer.\n  • R:      df <- $r_fn('$safe_p')\n  • Python: df = pd.read_csv('$safe_p'$py_sep)");
                    } else if (main_window != null) {
                        main_window.open_file_from_path.begin (fpath);
                    }
                }
            });
            var files_scroll = new Gtk.ScrolledWindow () {
                child = files_list,
                hexpand = true,
                vexpand = true
            };
            files_box.append (files_scroll);
            populate_files_browser ();
            panels.set (PanelId.FILES, files_box);

            // Connect PersistentSessionManager signals for pwd & plots sync
            var sess_mgr = get_session_manager ();
            sess_cwd_hid = sess_mgr.working_directory_changed.connect ((new_dir) => {
                this.current_browser_dir = new_dir;
                this.root_project_dir = new_dir;
                populate_files_browser ();
                Gtk.TextIter end;
                terminal_view.buffer.get_end_iter (out end);
                terminal_view.buffer.insert (ref end, "\n[Working Directory changed to: " + new_dir + "]\n$ ", -1);
            });
            sess_plot_hid = sess_mgr.plot_generated.connect ((plot_path) => {
                register_generated_plot (plot_path);
            });

            // 11. PACKAGES PANEL (Installed Packages Explorer & Library Toggle)
            var pkg_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var pkg_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            pkg_bar.add_css_class ("dock-subtoolbar");

            pkg_bar.append (new Gtk.Image.from_icon_name ("application-x-addon-symbolic"));
            packages_search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Filter packages...",
                hexpand = true
            };
            packages_search_entry.search_changed.connect (filter_packages_ui);
            pkg_bar.append (packages_search_entry);

            var install_pkg_btn = new Gtk.Button.from_icon_name ("list-add-symbolic") {
                tooltip_text = "Install Packages (CRAN / PyPI)..."
            };
            install_pkg_btn.add_css_class ("flat");
            install_pkg_btn.clicked.connect (() => {
                if (main_window != null) main_window.show_package_installer_dialog ();
            });
            pkg_bar.append (install_pkg_btn);

            var refresh_pkg_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh Installed Packages"
            };
            refresh_pkg_btn.add_css_class ("flat");
            refresh_pkg_btn.clicked.connect (() => {
                scan_installed_packages.begin ();
            });
            pkg_bar.append (refresh_pkg_btn);
            pkg_box.append (pkg_bar);

            packages_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "boxed-list" },
                margin_start = 6,
                margin_end = 6,
                margin_bottom = 6
            };
            var pkg_scroll = new Gtk.ScrolledWindow () {
                child = packages_list,
                hexpand = true,
                vexpand = true
            };
            pkg_box.append (pkg_scroll);
            bool packages_initialized = false;
            pkg_box.map.connect (() => {
                if (!packages_initialized) {
                    packages_initialized = true;
                    scan_installed_packages.begin ();
                }
            });
            panels.set (PanelId.PACKAGES, pkg_box);

            // 12. HELP PANEL (Documentation & RStudio Help Reference Browser)
            var help_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            var help_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            help_bar.add_css_class ("dock-subtoolbar");

            var btn_help_back = new Gtk.Button.from_icon_name ("go-previous-symbolic") {
                tooltip_text = "Back in Help History"
            };
            btn_help_back.add_css_class ("flat");
            btn_help_back.clicked.connect (() => {
                if (help_view.can_go_back ()) help_view.go_back ();
            });
            help_bar.append (btn_help_back);

            var btn_help_fwd = new Gtk.Button.from_icon_name ("go-next-symbolic") {
                tooltip_text = "Forward in Help History"
            };
            btn_help_fwd.add_css_class ("flat");
            btn_help_fwd.clicked.connect (() => {
                if (help_view.can_go_forward ()) help_view.go_forward ();
            });
            help_bar.append (btn_help_fwd);

            var btn_help_home = new Gtk.Button.from_icon_name ("go-home-symbolic") {
                tooltip_text = "Help Home / Reference"
            };
            btn_help_home.add_css_class ("flat");
            btn_help_home.clicked.connect (load_default_help_home);
            help_bar.append (btn_help_home);

            var help_search = new Gtk.SearchEntry () {
                placeholder_text = "Search Help (e.g. ggplot, lm, summary)...",
                hexpand = true
            };
            help_search.activate.connect (() => {
                string q = help_search.text.strip ();
                if (q.length > 0) {
                    show_help_for_topic.begin (q);
                }
            });
            help_bar.append (help_search);
            help_box.append (help_bar);

            help_view = WebViewFactory.create ();
            help_box.append (help_view);
            bool help_initialized = false;
            help_view.map.connect (() => {
                if (!help_initialized) {
                    help_initialized = true;
                    load_default_help_home ();
                }
            });
            panels.set (PanelId.HELP, help_box);

            // 15. SHINY VIEWER PANEL (Interactive R Shiny Application Viewer)
            var shiny_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };

            var shiny_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6
            };
            shiny_bar.add_css_class ("toolbar");

            btn_shiny_refresh = (Gtk.Button) RibbonFactory.create_compact_button ("view-refresh-symbolic");
            btn_shiny_refresh.tooltip_text = "Reload Shiny App";
            btn_shiny_refresh.clicked.connect (() => {
                if (shiny_webview != null) shiny_webview.reload ();
            });
            shiny_bar.append (btn_shiny_refresh);

            btn_shiny_browser = (Gtk.Button) RibbonFactory.create_compact_button ("applications-internet-symbolic", "Browser");
            btn_shiny_browser.tooltip_text = "Open in System Browser";
            btn_shiny_browser.clicked.connect (() => {
                var service = Services.ShinyService.get_default ();
                if (service.active_url != null) {
                    try {
                        GLib.AppInfo.launch_default_for_uri (service.active_url, null);
                    } catch (GLib.Error e) {}
                }
            });
            shiny_bar.append (btn_shiny_browser);

            btn_shiny_popout = (Gtk.Button) RibbonFactory.create_compact_button ("view-restore-symbolic", "Window");
            btn_shiny_popout.tooltip_text = "Open in Dedicated Window";
            btn_shiny_popout.clicked.connect (() => {
                open_shiny_in_dedicated_window ();
            });
            shiny_bar.append (btn_shiny_popout);

            btn_shiny_stop = (Gtk.Button) RibbonFactory.create_compact_button ("process-stop-symbolic", "Stop");
            btn_shiny_stop.tooltip_text = "Stop Shiny Server";
            btn_shiny_stop.add_css_class ("destructive-action");
            btn_shiny_stop.clicked.connect (() => {
                Services.ShinyService.get_default ().stop_app ();
            });
            shiny_bar.append (btn_shiny_stop);

            shiny_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            shiny_status_lbl = new Gtk.Label ("○ Idle") { valign = Gtk.Align.CENTER };
            shiny_status_lbl.add_css_class ("caption");
            shiny_status_lbl.add_css_class ("dim-label");
            shiny_bar.append (shiny_status_lbl);

            shiny_box.append (shiny_bar);

            shiny_webview = WebViewFactory.create ();
            shiny_box.append (shiny_webview);
            bool shiny_placeholder_loaded = false;
            shiny_webview.map.connect (() => {
                if (!shiny_placeholder_loaded && Services.ShinyService.get_default ().active_url == null) {
                    shiny_placeholder_loaded = true;
                    load_empty_shiny_placeholder ();
                }
            });

            panels.set (PanelId.SHINY_VIEWER, shiny_box);

            var shiny_svc = Services.ShinyService.get_default ();
            shiny_status_hid = shiny_svc.status_changed.connect ((st) => {
                if (shiny_status_lbl != null) {
                    shiny_status_lbl.label = st.to_badge_label ();
                    if (st == Services.ShinyAppStatus.RUNNING) {
                        shiny_status_lbl.remove_css_class ("dim-label");
                        shiny_status_lbl.add_css_class ("accent");
                        if (btn_shiny_stop != null) btn_shiny_stop.sensitive = true;
                    } else {
                        shiny_status_lbl.remove_css_class ("accent");
                        shiny_status_lbl.add_css_class ("dim-label");
                        if (btn_shiny_stop != null) btn_shiny_stop.sensitive = false;
                        if (st == Services.ShinyAppStatus.STOPPED) {
                            load_empty_shiny_placeholder ();
                        }
                    }
                }
            });

            shiny_url_hid = shiny_svc.url_ready.connect ((url) => {
                if (shiny_svc.current_target == Services.ShinyViewerTarget.VIEWER_PANE) {
                    if (shiny_webview != null) {
                        shiny_webview.load_uri (url);
                    }
                    doc_page.dock_layout_state.activate_panel (PanelId.SHINY_VIEWER);
                } else if (shiny_svc.current_target == Services.ShinyViewerTarget.DEDICATED_WINDOW) {
                    open_shiny_in_dedicated_window ();
                } else if (shiny_svc.current_target == Services.ShinyViewerTarget.EXTERNAL_BROWSER) {
                    try {
                        GLib.AppInfo.launch_default_for_uri (url, null);
                    } catch (GLib.Error e) {}
                }
            });

            // 16. GALAXY PROJECT PANEL (Arekyer Galaxy-to-Quarto Provenance Bridge)
            galaxy_panel = new GalaxyPanel ();
            galaxy_panel.inject_code_chunk_requested.connect ((chunk_text) => {
                var buffer = doc_page.source_buffer as GtkSource.Buffer;
                if (buffer == null) return;

                var arekyer = Imladris.Bridges.Arekyer.ArekyerBridge.get_default ();
                arekyer.inject_into_buffer (buffer, chunk_text);

                doc_page.source_view.grab_focus ();
                if (main_window != null) {
                    main_window.show_toast ("Injected Galaxy provenance chunk into manuscript.");
                }
                refresh_environment_and_outline ();
            });
            galaxy_panel.toast_notification_requested.connect ((msg) => {
                if (main_window != null) {
                    main_window.show_toast (msg);
                }
            });
            panels.set (PanelId.GALAXY, galaxy_panel);

            // 17. IMLADRIS ON WEB SYNC PANEL (Offline-First Git-Style Collaboration Bridge)
            web_sync_panel = new WebSyncPanel (doc_page, main_window);
            panels.set (PanelId.WEB_SYNC, web_sync_panel);

            // Initial AST & Environment scan
            refresh_environment_and_outline ();
        }

        /**
         * Pillar 4: Shared State Execution — Line or Selection (Ctrl+Enter)
         */
        public void execute_current_line_or_selection () {
            string code_to_run = "";
            Gtk.TextIter sel_start, sel_end;
            bool has_sel = doc_page.source_buffer.get_selection_bounds (out sel_start, out sel_end);

            if (has_sel) {
                code_to_run = doc_page.source_buffer.get_text (sel_start, sel_end, false).strip ();
            } else {
                Gtk.TextIter cursor;
                doc_page.source_buffer.get_iter_at_mark (out cursor, doc_page.source_buffer.get_insert ());
                int line_idx = cursor.get_line ();
                Gtk.TextIter line_start, line_end;
                doc_page.source_buffer.get_iter_at_line (out line_start, line_idx);
                line_end = line_start;
                line_end.forward_to_line_end ();
                code_to_run = doc_page.source_buffer.get_text (line_start, line_end, false).strip ();

                // Advance cursor to next line (RStudio & Jupyter behavior)
                if (line_end.forward_line ()) {
                    doc_page.source_buffer.place_cursor (line_end);
                    doc_page.source_view.scroll_to_iter (line_end, 0.1, false, 0.0, 0.0);
                }
            }

            if (code_to_run.length == 0) return;

            string engine = detect_engine_at_cursor ();
            run_code_snippet_in_console (engine, code_to_run);
        }

        private string detect_engine_at_cursor () {
            Gtk.TextIter cursor;
            doc_page.source_buffer.get_iter_at_mark (out cursor, doc_page.source_buffer.get_insert ());
            int cursor_line = cursor.get_line ();

            var chunk = Core.ChunkParser.find_chunk_at_line (doc_page.get_clean_source_text (), cursor_line);
            if (chunk != null) {
                return chunk.language;
            }

            var profile = Core.FormatProfile.for_format (doc_page.get_document_format ());
            if (profile.default_kernel.length > 0) {
                return profile.default_kernel;
            }

            if (doc_page.doc_type == "r" || (doc_page.file_location != null && doc_page.file_location.get_basename ().has_suffix (".R"))) {
                return "r";
            }
            if (doc_page.doc_type == "rmd" || (doc_page.file_location != null && doc_page.file_location.get_basename ().has_suffix (".Rmd"))) {
                return "r";
            }
            return "python";
        }

        private Gtk.TextMark create_line_end_mark (int line) {
            Gtk.TextIter iter;
            int max_line = int.max (0, doc_page.source_buffer.get_line_count () - 1);
            int clamped = line.clamp (0, max_line);
            doc_page.source_buffer.get_iter_at_line (out iter, clamped);
            if (!iter.ends_line ()) {
                iter.forward_to_line_end ();
            }
            return doc_page.source_buffer.create_mark (null, iter, false);
        }

        private GLib.Cancellable reset_exec_cancellable () {
            if (active_exec_cancellable != null) {
                active_exec_cancellable.cancel ();
            }
            active_exec_cancellable = new GLib.Cancellable ();
            return active_exec_cancellable;
        }

        private async void execute_chunks_sequentially_async (Gee.ArrayList<Core.CodeChunk> chunks) {
            var cancellable = reset_exec_cancellable ();
            var marks = new Gee.ArrayList<Gtk.TextMark> ();
            foreach (var ch in chunks) {
                marks.add (create_line_end_mark (ch.end_line));
            }

            for (int i = 0; i < chunks.size; i++) {
                if (cancellable.is_cancelled ()) {
                    break;
                }
                var ch = chunks.get (i);
                var mark = marks.get (i);
                yield run_code_snippet_in_console_async (ch.language, ch.code, mark, cancellable);
            }

            foreach (var mark in marks) {
                if (!mark.get_deleted ()) {
                    doc_page.source_buffer.delete_mark (mark);
                }
            }
        }

        /**
         * Pillar 4 & 11: Chunk Execution (Ctrl+Shift+Enter) with Inline Card Output
         */
        public void execute_active_cell () {
            string text = doc_page.get_clean_source_text ();
            Gtk.TextIter cursor;
            doc_page.source_buffer.get_iter_at_mark (out cursor, doc_page.source_buffer.get_insert ());
            int cursor_line = cursor.get_line ();

            var chunk = Core.ChunkParser.find_chunk_at_line (text, cursor_line);
            if (chunk == null || chunk.code.length == 0) {
                // Fallback: execute current line or selection
                execute_current_line_or_selection ();
                return;
            }

            run_code_snippet_in_console (chunk.language, chunk.code, chunk.end_line);
        }

        public void execute_all_cells () {
            string text = doc_page.get_clean_source_text ();
            var chunks = Core.ChunkParser.parse_chunks (text);
            var runnable = new Gee.ArrayList<Core.CodeChunk> ();
            foreach (var ch in chunks) {
                if (ch.eval_enabled && ch.code.length > 0) {
                    runnable.add (ch);
                }
            }
            if (runnable.size > 0) {
                execute_chunks_sequentially_async.begin (runnable);
            }
        }

        /**
         * Jupyter Parity: Executes active cell and advances cursor to next cell (Shift+Enter).
         * If at the end of the document, appends a new code cell of the same language.
         */
        public void execute_active_cell_and_advance () {
            string text = doc_page.get_clean_source_text ();
            Gtk.TextIter cursor;
            doc_page.source_buffer.get_iter_at_mark (out cursor, doc_page.source_buffer.get_insert ());
            int cursor_line = cursor.get_line ();

            var chunk = Core.ChunkParser.find_chunk_at_line (text, cursor_line);
            if (chunk == null) {
                execute_current_line_or_selection ();
                return;
            }

            if (chunk.code.length > 0) {
                run_code_snippet_in_console (chunk.language, chunk.code, chunk.end_line);
            }

            var all_chunks = Core.ChunkParser.parse_chunks (text);
            Core.CodeChunk? next_chunk = null;
            foreach (var ch in all_chunks) {
                if (ch.start_line > chunk.end_line) {
                    next_chunk = ch;
                    break;
                }
            }

            if (next_chunk != null) {
                Gtk.TextIter next_iter;
                doc_page.source_buffer.get_iter_at_line (out next_iter, next_chunk.start_line + 1);
                doc_page.source_buffer.place_cursor (next_iter);
                doc_page.source_view.scroll_to_iter (next_iter, 0.1, false, 0.0, 0.0);
            } else {
                Gtk.TextIter end_iter;
                doc_page.source_buffer.get_end_iter (out end_iter);
                doc_page.source_buffer.place_cursor (end_iter);
                doc_page.insert_code_chunk (chunk.language);
            }
        }

        /**
         * Jupyter Parity: Restarts active REPL session kernel and resets state.
         */
        public void restart_kernel () {
            if (active_exec_cancellable != null) {
                active_exec_cancellable.cancel ();
                active_exec_cancellable = null;
            }
            get_session_manager ().restart_all_sessions ();
            execution_counter = 0;
            doc_page.append_console_log ("\n--- Kernel Restarted: Session State Cleared ---");
            if (main_window != null) {
                main_window.show_toast ("Kernel restarted");
            }
            refresh_environment_and_outline ();
        }

        /**
         * Jupyter Parity: Clears console view logs and execution outputs.
         */
        public void clear_all_outputs () {
            doc_page.console_view.buffer.set_text ("", -1);
            doc_page.clear_inline_chunk_outputs ();
            if (main_window != null) {
                main_window.show_toast ("Cleared all outputs");
            }
        }

        public void execute_cells_above () {
            string text = doc_page.get_clean_source_text ();
            Gtk.TextIter cursor;
            doc_page.source_buffer.get_iter_at_mark (out cursor, doc_page.source_buffer.get_insert ());
            int cursor_line = cursor.get_line ();

            var chunks = Core.ChunkParser.parse_chunks (text);
            var runnable = new Gee.ArrayList<Core.CodeChunk> ();
            foreach (var ch in chunks) {
                if (ch.end_line < cursor_line && ch.eval_enabled && ch.code.length > 0) {
                    runnable.add (ch);
                }
            }
            if (runnable.size > 0) {
                execute_chunks_sequentially_async.begin (runnable);
            }
        }

        public void execute_cells_below () {
            string text = doc_page.get_clean_source_text ();
            Gtk.TextIter cursor;
            doc_page.source_buffer.get_iter_at_mark (out cursor, doc_page.source_buffer.get_insert ());
            int cursor_line = cursor.get_line ();

            var chunks = Core.ChunkParser.parse_chunks (text);
            var runnable = new Gee.ArrayList<Core.CodeChunk> ();
            foreach (var ch in chunks) {
                if (ch.end_line >= cursor_line && ch.eval_enabled && ch.code.length > 0) {
                    runnable.add (ch);
                }
            }
            if (runnable.size > 0) {
                execute_chunks_sequentially_async.begin (runnable);
            }
        }

        public void open_dataframe_in_viewer (string object_name, string engine = "r") {
            data_grid_viewer.session_key = get_session_key ();
            data_grid_viewer.fetch_and_display.begin (object_name, engine);

            foreach (var qid in QuadrantId.all ()) {
                var qc = doc_page.dock_layout_state.quadrants.get (qid);
                if (qc != null && qc.tabs.contains (PanelId.DATA_VIEWER)) {
                    doc_page.dock_layout_state.activate_tab (qid, PanelId.DATA_VIEWER);
                    return;
                }
            }

            // If not found in any quadrant, add to Q1_TOP_LEFT and activate
            var q1 = doc_page.dock_layout_state.quadrants.get (QuadrantId.Q1_TOP_LEFT);
            if (q1 != null && !q1.tabs.contains (PanelId.DATA_VIEWER)) {
                q1.tabs.add (PanelId.DATA_VIEWER);
            }
            doc_page.dock_layout_state.activate_tab (QuadrantId.Q1_TOP_LEFT, PanelId.DATA_VIEWER);
        }

        private string? extract_view_object (string code) {
            // Strip # comments and quoted literals so View(...) inside strings/comments is ignored
            var sanitized = new GLib.StringBuilder ();
            bool in_single = false;
            bool in_double = false;
            bool escaped = false;
            bool in_comment = false;
            for (int i = 0; i < code.length; i++) {
                char c = code[i];
                if (c == '\n') {
                    in_comment = false;
                    in_single = false;
                    in_double = false;
                    escaped = false;
                    sanitized.append_c (c);
                    continue;
                }
                if (in_comment) continue;
                if (escaped) { escaped = false; continue; }
                if (c == '\\' && (in_single || in_double)) { escaped = true; continue; }
                if (c == '\'' && !in_double) { in_single = !in_single; continue; }
                if (c == '"' && !in_single) { in_double = !in_double; continue; }
                if (in_single || in_double) continue;
                if (c == '#') { in_comment = true; continue; }
                sanitized.append_c (c);
            }

            try {
                if (view_call_regex == null) {
                    view_call_regex = new GLib.Regex ("\\bView\\s*\\(\\s*([A-Za-z_\\.][A-Za-z0-9_\\.@$]*)\\s*\\)");
                }
                GLib.MatchInfo mi;
                if (view_call_regex.match (sanitized.str, 0, out mi)) {
                    return mi.fetch (1);
                }
            } catch (GLib.RegexError e) {}
            return null;
        }

        public void run_code_snippet_in_console (string engine, string code, int inline_chunk_line = -1) {
            Gtk.TextMark? mark = null;
            if (inline_chunk_line >= 0) {
                mark = create_line_end_mark (inline_chunk_line);
            }
            var cancellable = reset_exec_cancellable ();
            run_code_snippet_in_console_async.begin (engine, code, mark, cancellable, (obj, res) => {
                run_code_snippet_in_console_async.end (res);
                if (mark != null && !mark.get_deleted ()) {
                    doc_page.source_buffer.delete_mark (mark);
                }
            });
        }

        private int resolve_target_line (Gtk.TextMark? end_mark) {
            if (end_mark != null && !end_mark.get_deleted ()) {
                Gtk.TextIter iter;
                doc_page.source_buffer.get_iter_at_mark (out iter, end_mark);
                return iter.get_line ();
            }
            return -1;
        }

        public async void run_code_snippet_in_console_async (
            string engine,
            string code,
            Gtk.TextMark? end_mark = null,
            GLib.Cancellable? cancellable = null
        ) {
            execution_counter++;
            int count = execution_counter;
            doc_page.append_console_log (@"\nIn [$count] ($engine):\n$code");
            Services.HistoryManager.get_default ().add_entry (code, engine);

            string? view_obj = extract_view_object (code);

            // Hook R ?topic or help(topic) documentation command
            if (code.has_prefix ("?") || code.has_prefix ("help(") || code.has_prefix ("help (")) {
                string topic = "";
                if (code.has_prefix ("?")) {
                    topic = code.substring (1).strip ();
                } else {
                    int p1 = code.index_of ("(");
                    int p2 = code.index_of (")", p1);
                    if (p1 != -1 && p2 != -1 && p2 > p1) {
                        topic = code.substring (p1 + 1, p2 - p1 - 1).replace ("\"", "").replace ("'", "").strip ();
                    }
                }
                if (topic.length > 0) {
                    show_help_for_topic.begin (topic);
                }
            }

            int64 start_us = GLib.get_monotonic_time ();
            var sess_mgr = get_session_manager ();
            string norm_engine = engine.down ().strip ();

            if (norm_engine == "r") {
                string? plot_file = null;
                bool any_line_streamed = false;
                string output = yield sess_mgr.execute_r_with_options (
                    code,
                    (eng, line, is_err) => {
                        any_line_streamed = true;
                        if (doc_page != null) doc_page.append_console_log (line);
                    },
                    cancellable,
                    60000,
                    true,
                    out plot_file
                );
                if (doc_page == null || (cancellable != null && cancellable.is_cancelled ())) return;
                output = output.strip ();
                double elapsed_ms = (GLib.get_monotonic_time () - start_us) / 1000.0;
                if (!any_line_streamed && output.length > 0) {
                    doc_page.append_console_log (@"Out [$count]:\n$output");
                }
                if (output.contains ("Install Toolchain") && main_window != null) {
                    main_window.show_toolchain_setup_dialog ();
                }
                if (plot_file != null && plot_file.length > 0) {
                    register_generated_plot (plot_file);
                    activate_panel_in_dock (PanelId.PLOTS);
                    string base_plot = GLib.Path.get_basename (plot_file);
                    doc_page.append_console_log (@"📊 [Plot rendered in Quadrant 4: $base_plot]");
                }
                int target_line = resolve_target_line (end_mark);
                if (target_line >= 0) {
                    doc_page.display_inline_chunk_output (target_line, output, plot_file, count, elapsed_ms);
                }
                if (view_obj != null && view_obj.length > 0) {
                    open_dataframe_in_viewer (view_obj, "r");
                }
                refresh_environment_and_outline ();
                var doc_fmt_r = doc_page.get_document_format ();
                environment_controller.active_engine = (doc_fmt_r == DocumentFormat.QMD || doc_fmt_r == DocumentFormat.IPYNB) ? "polyglot" : "r";
                environment_controller.refresh_environment.begin ();
            } else if (norm_engine == "python" || norm_engine == "py") {
                string? plot_file = null;
                bool any_line_streamed = false;
                string output = yield sess_mgr.execute_python_with_options (
                    code,
                    (eng, line, is_err) => {
                        any_line_streamed = true;
                        if (doc_page != null) doc_page.append_console_log (line);
                    },
                    cancellable,
                    60000,
                    true,
                    out plot_file
                );
                if (doc_page == null || (cancellable != null && cancellable.is_cancelled ())) return;
                output = output.strip ();
                double elapsed_ms = (GLib.get_monotonic_time () - start_us) / 1000.0;
                if (!any_line_streamed && output.length > 0) {
                    doc_page.append_console_log (@"Out [$count]:\n$output");
                }
                if (output.contains ("Install Toolchain") && main_window != null) {
                    main_window.show_toolchain_setup_dialog ();
                }
                if (plot_file != null && plot_file.length > 0) {
                    register_generated_plot (plot_file);
                    activate_panel_in_dock (PanelId.PLOTS);
                    string base_plot = GLib.Path.get_basename (plot_file);
                    doc_page.append_console_log (@"📊 [Plot rendered in Quadrant 4: $base_plot]");
                }
                int target_line = resolve_target_line (end_mark);
                if (target_line >= 0) {
                    doc_page.display_inline_chunk_output (target_line, output, plot_file, count, elapsed_ms);
                }
                if (view_obj != null && view_obj.length > 0) {
                    open_dataframe_in_viewer (view_obj, "python");
                }
                refresh_environment_and_outline ();
                var doc_fmt_py = doc_page.get_document_format ();
                environment_controller.active_engine = (doc_fmt_py == DocumentFormat.QMD || doc_fmt_py == DocumentFormat.IPYNB) ? "polyglot" : "python";
                environment_controller.refresh_environment.begin ();
            } else if (norm_engine == "ts" || norm_engine == "typescript") {
                string? proj_dir = doc_page.current_project_dir != "" ? doc_page.current_project_dir : null;
                var ts_res = yield Runners.TypeScriptRunner.run_snippet_async (code, proj_dir, cancellable);
                double elapsed_ms = (GLib.get_monotonic_time () - start_us) / 1000.0;
                var combined = new GLib.StringBuilder ();
                if (ts_res.stdout_text.strip ().length > 0) {
                    combined.append (ts_res.stdout_text.strip ());
                }
                if (ts_res.stderr_text.strip ().length > 0) {
                    if (combined.len > 0) combined.append ("\n");
                    combined.append (ts_res.stderr_text.strip ());
                }
                string output = combined.str;
                if (output.length > 0) {
                    doc_page.append_console_log (@"Out [$count] ($(ts_res.runtime_used)):\n$output");
                }
                int target_line = resolve_target_line (end_mark);
                if (target_line >= 0) {
                    doc_page.display_inline_chunk_output (target_line, output, null, count, elapsed_ms);
                }
                refresh_environment_and_outline ();
            } else if (norm_engine == "bash" || norm_engine == "sh" || norm_engine == "zsh") {
                string? bash_cwd = current_browser_dir != "" ? current_browser_dir : (doc_page.current_project_dir != "" ? doc_page.current_project_dir : null);
                string skey = GLib.Checksum.compute_for_string (GLib.ChecksumType.MD5, get_session_key ());
                string env_cache = GLib.Path.build_filename (Core.PlatformUtils.get_shared_cache_dir ("tmp"), @"imladris_bash_env_$(skey).sh");
                string cwd_cache = GLib.Path.build_filename (Core.PlatformUtils.get_shared_cache_dir ("tmp"), @"imladris_bash_cwd_$(skey).txt");
                string persistent_cmd = "if [ -f " + GLib.Shell.quote (env_cache) + " ]; then source " + GLib.Shell.quote (env_cache) + " 2>/dev/null || true; fi\n" +
                    "_imladris_save_bash() {\n  pwd > " + GLib.Shell.quote (cwd_cache) + "\n  export -p > " + GLib.Shell.quote (env_cache) + "\n}\n" +
                    "trap _imladris_save_bash EXIT\n" +
                    code;
                string output = (yield ExecutionEngine.capture_command_in_dir_async ({ "bash", "-c", persistent_cmd }, bash_cwd, cancellable)).strip ();
                if (GLib.FileUtils.test (cwd_cache, GLib.FileTest.EXISTS)) {
                    try {
                        string new_cwd;
                        GLib.FileUtils.get_contents (cwd_cache, out new_cwd);
                        new_cwd = new_cwd.strip ();
                        if (new_cwd.length > 0 && GLib.FileUtils.test (new_cwd, GLib.FileTest.IS_DIR)) {
                            current_browser_dir = new_cwd;
                        }
                    } catch (GLib.Error e) {}
                }
                if (doc_page == null || (cancellable != null && cancellable.is_cancelled ())) return;
                double elapsed_ms = (GLib.get_monotonic_time () - start_us) / 1000.0;
                if (output.length > 0) {
                    doc_page.append_console_log (@"Out [$count]:\n$output");
                }
                int target_line = resolve_target_line (end_mark);
                if (target_line >= 0) {
                    doc_page.display_inline_chunk_output (target_line, output, null, count, elapsed_ms);
                }
                refresh_environment_and_outline ();
            } else {
                string msg = @"✖ Unsupported chunk engine '$engine'. Supported interactive engines: r, python, ts/typescript, bash/sh.";
                doc_page.append_console_log (msg);
                int target_line = resolve_target_line (end_mark);
                if (target_line >= 0) {
                    doc_page.display_inline_chunk_output (target_line, msg, null, count, 0.0);
                }
            }
        }

        private void run_shell_command (string cmd) {
            Gtk.TextIter end;
            terminal_view.buffer.get_end_iter (out end);
            terminal_view.buffer.insert (ref end, cmd + "\n", -1);

            string trimmed = cmd.strip ();
            string cwd = current_browser_dir != "" ? current_browser_dir : get_session_manager ().current_working_dir;
            if (cwd == "") cwd = GLib.Environment.get_current_dir ();

            if (trimmed == "cd" || trimmed.has_prefix ("cd ")) {
                string raw_target = trimmed == "cd" ? "~" : trimmed.substring (3).strip ();
                if ((raw_target.has_prefix ("\"") && raw_target.has_suffix ("\"")) ||
                    (raw_target.has_prefix ("'") && raw_target.has_suffix ("'"))) {
                    if (raw_target.length >= 2) {
                        raw_target = raw_target.substring (1, raw_target.length - 2);
                    }
                }
                string resolved;
                if (raw_target == "" || raw_target == "~") {
                    resolved = GLib.Environment.get_home_dir ();
                } else if (raw_target.has_prefix ("~/")) {
                    resolved = GLib.Path.build_filename (GLib.Environment.get_home_dir (), raw_target.substring (2));
                } else if (GLib.Path.is_absolute (raw_target)) {
                    resolved = raw_target;
                } else {
                    resolved = GLib.Path.build_filename (cwd, raw_target);
                }
                var target_file = GLib.File.new_for_path (resolved);
                string? norm_path = target_file.get_path ();
                if (norm_path != null && GLib.FileUtils.test (norm_path, GLib.FileTest.IS_DIR)) {
                    current_browser_dir = norm_path;
                    populate_files_browser ();
                    Gtk.TextIter e_cd;
                    terminal_view.buffer.get_end_iter (out e_cd);
                    terminal_view.buffer.insert (ref e_cd, "[cwd: " + norm_path + "]\n$ ", -1);
                } else {
                    Gtk.TextIter e_err;
                    terminal_view.buffer.get_end_iter (out e_err);
                    terminal_view.buffer.insert (ref e_err, "✖ cd: no such directory: " + raw_target + "\n$ ", -1);
                }
                return;
            }

            ExecutionEngine.capture_command_in_dir_async.begin ({ "bash", "-c", cmd }, cwd, null, 60000, (obj, res) => {
                string output = ExecutionEngine.capture_command_in_dir_async.end (res);
                Gtk.TextIter e2;
                terminal_view.buffer.get_end_iter (out e2);
                terminal_view.buffer.insert (ref e2, output + "\n$ ", -1);
            });
        }

        public void refresh_environment_and_outline (string? cached_text = null) {
            Gtk.Widget? child = outline_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                outline_list.remove (child);
                child = next;
            }

            child = citations_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                citations_list.remove (child);
                child = next;
            }

            string text = cached_text ?? doc_page.get_clean_source_text ();
            string fmt_code = doc_page.get_document_format ().get_extension ().replace (".", "").down ();
            string outline_json = Core.NativeCore.extract_outline_json (text, fmt_code);
            try {
                var jp = new Json.Parser ();
                jp.load_from_data (outline_json, -1);
                var root = jp.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.ARRAY) {
                    var arr = root.get_array ();
                    for (uint idx = 0; idx < arr.get_length (); idx++) {
                        var item = arr.get_object_element (idx);
                        int level = (int) item.get_int_member ("level");
                        string title = item.get_string_member ("title");
                        int line1 = (int) item.get_int_member ("line");
                        string kind = item.get_string_member ("kind");
                        int line0 = line1 > 0 ? line1 - 1 : 0;

                        var row = new Gtk.ListBoxRow ();
                        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                            margin_top = 4,
                            margin_bottom = 4,
                            margin_start = 6 + ((level - 1) * 10),
                            margin_end = 6
                        };
                        string icon_name = kind == "chunk" ? "utilities-terminal-symbolic" : "format-text-bold-symbolic";
                        hbox.append (new Gtk.Image.from_icon_name (icon_name));
                        var lbl = new Gtk.Label (title) { xalign = 0, hexpand = true };
                        if (kind == "chunk") lbl.add_css_class ("monospace");
                        hbox.append (lbl);
                        hbox.append (new Gtk.Label (@"L$line1") { css_classes = { "dim-label", "caption" } });
                        row.set_child (hbox);
                        row.set_data<int> ("target-line", line0);
                        outline_list.append (row);
                    }
                }
            } catch (GLib.Error e) {
                GLib.warning ("Outline parse failed: %s", e.message);
            }

            string[] lines = text.split ("\n");
            for (int i = 0; i < lines.length; i++) {
                string trimmed = lines[i].strip ();

                // 2. Citations detection (@key) excluding Quarto cross-refs, Roxygen/Python/CSS tags, and emails
                if (trimmed.contains ("@") && !trimmed.has_prefix ("mailto:") && !trimmed.has_prefix ("#'")) {
                    string[] words = trimmed.split_set (" [](),;\t\"'<>");
                    foreach (string raw_w in words) {
                        string w = raw_w;
                        while (w.length > 0 && (w.has_suffix (".") || w.has_suffix (":"))) {
                            w = w.substring (0, w.length - 1);
                        }
                        if (w.has_prefix ("@") && w.length > 2 && !w.substring (1).contains ("@")) {
                            string wl = w.down ();
                            if (wl.has_prefix ("@fig-") || wl.has_prefix ("@tbl-") ||
                                wl.has_prefix ("@sec-") || wl.has_prefix ("@eq-") ||
                                wl.has_prefix ("@lst-") || wl.has_prefix ("@thm-") ||
                                wl.has_prefix ("@cor-") || wl.has_prefix ("@prp-") ||
                                wl.has_prefix ("@cnj-") || wl.has_prefix ("@def-") ||
                                wl.has_prefix ("@exm-") || wl.has_prefix ("@exr-") ||
                                wl.has_prefix ("@alg-") ||
                                is_non_citation_at_tag (wl)) {
                                continue;
                            }
                            var crow = new Adw.ActionRow () {
                                title = w,
                                subtitle = @"Referenced on line $(i + 1)",
                                use_markup = false
                            };
                            var ins_btn = new Gtk.Button.from_icon_name ("insert-text-symbolic") {
                                valign = Gtk.Align.CENTER,
                                tooltip_text = "Insert citation at cursor"
                            };
                            ins_btn.add_css_class ("flat");
                            string cite_key = w;
                            ins_btn.clicked.connect (() => {
                                doc_page.source_buffer.begin_user_action ();
                                doc_page.source_buffer.insert_at_cursor (@"[$cite_key]", -1);
                                doc_page.source_buffer.end_user_action ();
                            });
                            crow.add_suffix (ins_btn);
                            citations_list.append (crow);
                        }
                    }
                }
            }
        }

        private static bool is_non_citation_at_tag (string wl) {
            const string[] IGNORED_TAGS = {
                "@param", "@export", "@return", "@details", "@examples", "@import", "@importfrom",
                "@rdname", "@title", "@description", "@author", "@seealso", "@family", "@keywords",
                "@slot", "@field", "@section", "@note", "@references", "@aliases", "@usage",
                "@format", "@source", "@name", "@doctype", "@nord", "@include", "@method",
                "@s3method", "@inherit", "@inheritparams", "@inheritsection", "@inheritdotparams",
                "@dataclass", "@property", "@staticmethod", "@classmethod", "@abstractmethod",
                "@override", "@lru_cache", "@pytest", "@app", "@route", "@component", "@injectable",
                "@media", "@keyframes", "@font-face", "@supports", "@charset", "@namespace",
                "@page", "@layer", "@deprecated", "@todo", "@fixme", "@license", "@copyright",
                "@version", "@since"
            };
            foreach (unowned string tag in IGNORED_TAGS) {
                if (wl == tag) return true;
            }
            return false;
        }

        private void get_plot_theme_colors (out string bg, out string text, out string card_bg, out string card_border, out string title_col, out string sub_col) {
            var app_theme = Core.SettingsManager.get_default ().app_theme;
            bool is_dark = Adw.StyleManager.get_default ().dark;
            bool use_dark = (app_theme == Core.AppTheme.DARK) || (app_theme == Core.AppTheme.SYSTEM && is_dark);
            bool use_sepia = (app_theme == Core.AppTheme.EYE_FRIENDLY);

            bg = use_dark ? "#1e1e1e" : (use_sepia ? "#faf5ee" : "#ffffff");
            text = use_dark ? "#e2e8f0" : (use_sepia ? "#383431" : "#1e293b");
            card_bg = use_dark ? "#262626" : (use_sepia ? "#f0e7dc" : "#f8fafc");
            card_border = use_dark ? "#404040" : (use_sepia ? "#dcd0c2" : "#e2e8f0");
            title_col = use_dark ? "#f8fafc" : (use_sepia ? "#2b2623" : "#0f172a");
            sub_col = use_dark ? "#94a3b8" : (use_sepia ? "#5c534b" : "#64748b");
        }

        public void render_default_scientific_plot () {
            string bg, text, card_bg, card_border, title_col, sub_col;
            get_plot_theme_colors (out bg, out text, out card_bg, out card_border, out title_col, out sub_col);
            string empty_html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    margin: 0;
    padding: 24px;
    background: %s;
    font-family: system-ui, -apple-system, sans-serif;
    color: %s;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 75vh;
    text-align: center;
  }
  .empty-card {
    border: 1px dashed %s;
    border-radius: 10px;
    padding: 28px 24px;
    background: %s;
    max-width: 380px;
  }
  .empty-title {
    font-size: 14px;
    font-weight: 700;
    margin-bottom: 6px;
    color: %s;
  }
  .empty-sub {
    font-size: 12px;
    line-height: 1.5;
    color: %s;
  }
</style>
</head>
<body>
  <div class="empty-card">
    <div class="empty-title">No Plots Generated Yet</div>
    <div class="empty-sub">Execute an R or Python plotting cell (e.g. <code>ggplot2</code>, <code>plot()</code>, or <code>matplotlib</code>) to inspect figures here.</div>
  </div>
</body>
</html>""".printf (bg, text, card_border, card_bg, title_col, sub_col);
            plots_webview.load_html (empty_html, "file:///");
        }

        public void load_plot_image (string plot_file_path) {
            if (!GLib.FileUtils.test (plot_file_path, GLib.FileTest.EXISTS)) return;
            string uri;
            try {
                uri = GLib.Filename.to_uri (plot_file_path);
            } catch (GLib.ConvertError e) {
                uri = "file://" + plot_file_path;
            }
            string fname = GLib.Path.get_basename (plot_file_path);
            string bg, text, card_bg, card_border, title_col, sub_col;
            get_plot_theme_colors (out bg, out text, out card_bg, out card_border, out title_col, out sub_col);
            string html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    margin: 0;
    padding: 16px;
    background: %s;
    font-family: system-ui, sans-serif;
    color: %s;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .plot-card {
    border: 1px solid %s;
    border-radius: 8px;
    padding: 14px;
    background: %s;
    width: 94%%;
    max-width: 650px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.06);
    text-align: center;
  }
  .plot-img {
    max-width: 100%%;
    height: auto;
    border-radius: 6px;
    border: 1px solid %s;
  }
  .plot-title {
    font-size: 13px;
    font-weight: 700;
    margin-top: 10px;
    color: %s;
  }
  .plot-sub {
    font-size: 11px;
    color: %s;
    margin-top: 2px;
  }
</style>
</head>
<body>
  <div class="plot-card">
    <img class="plot-img" src="%s" alt="Generated Plot" />
    <div class="plot-title">%s</div>
    <div class="plot-sub">Rendered Graphic Output • Quadrant 4</div>
  </div>
</body>
</html>""".printf (bg, text, card_border, card_bg, card_border, title_col, sub_col, uri, GLib.Markup.escape_text (fname));
            plots_webview.load_html (html, "file:///");
        }

        private void navigate_files_up () {
            if (current_browser_dir == "") return;
            var f = GLib.File.new_for_path (current_browser_dir);
            var parent = f.get_parent ();
            if (parent != null) {
                current_browser_dir = parent.get_path ();
                populate_files_browser ();
            }
        }

        private void navigate_files_home () {
            if (root_project_dir != "") {
                current_browser_dir = root_project_dir;
            } else {
                current_browser_dir = get_session_manager ().current_working_dir;
            }
            populate_files_browser ();
        }

        public void populate_files_browser () {
            Gtk.Widget? child = files_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                files_list.remove (child);
                child = next;
            }

            if (current_browser_dir == "") {
                if (doc_page.file_location != null && doc_page.file_location.get_parent () != null) {
                    current_browser_dir = doc_page.file_location.get_parent ().get_path ();
                } else {
                    current_browser_dir = get_session_manager ().current_working_dir;
                }
            }
            if (root_project_dir == "") {
                root_project_dir = current_browser_dir;
            }

            string dir_path = current_browser_dir;
            if (files_dir_lbl != null) {
                string base_name = GLib.Path.get_basename (dir_path);
                files_dir_lbl.label = @"📁 $base_name";
            }

            // Up row if deeper than root
            if (current_browser_dir != root_project_dir) {
                var up_row = new Gtk.ListBoxRow ();
                var up_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                    margin_top = 4, margin_bottom = 4, margin_start = 6, margin_end = 6
                };
                up_box.append (new Gtk.Image.from_icon_name ("go-up-symbolic"));
                up_box.append (new Gtk.Label (".. (Parent Directory)") { xalign = 0, hexpand = true });
                up_row.set_child (up_box);
                var f = GLib.File.new_for_path (current_browser_dir);
                var parent = f.get_parent ();
                if (parent != null) {
                    up_row.set_data<string> ("file-path", parent.get_path ());
                    up_row.set_data<bool> ("is-dir", true);
                    files_list.append (up_row);
                }
            }

            try {
                var dir = GLib.Dir.open (dir_path, 0);
                string? name = null;
                var dir_entries = new Gee.ArrayList<string> ();
                var file_entries = new Gee.ArrayList<string> ();

                while ((name = dir.read_name ()) != null) {
                    if (name.has_prefix (".")) continue;
                    string full = GLib.Path.build_filename (dir_path, name);
                    if (GLib.FileUtils.test (full, GLib.FileTest.IS_DIR)) {
                        dir_entries.add (name);
                    } else if (GLib.FileUtils.test (full, GLib.FileTest.IS_REGULAR)) {
                        file_entries.add (name);
                    }
                }

                dir_entries.sort ();
                file_entries.sort ();

                foreach (var dname in dir_entries) {
                    string full = GLib.Path.build_filename (dir_path, dname);
                    var row = new Gtk.ListBoxRow ();
                    var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                        margin_top = 4, margin_bottom = 4, margin_start = 6, margin_end = 6
                    };
                    box.append (new Gtk.Image.from_icon_name ("folder-symbolic"));
                    box.append (new Gtk.Label (dname + "/") { xalign = 0, hexpand = true });
                    row.set_child (box);
                    row.set_data<string> ("file-path", full);
                    row.set_data<bool> ("is-dir", true);
                    files_list.append (row);
                }

                foreach (var fname in file_entries) {
                    string full = GLib.Path.build_filename (dir_path, fname);
                    var row = new Gtk.ListBoxRow ();
                    var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                        margin_top = 4, margin_bottom = 4, margin_start = 6, margin_end = 6
                    };
                    string icon_name = "text-x-generic-symbolic";
                    if (fname.has_suffix (".R") || fname.has_suffix (".py") || fname.has_suffix (".sh")) {
                        icon_name = "utilities-terminal-symbolic";
                    } else if (fname.has_suffix (".ipynb") || fname.has_suffix (".qmd") || fname.has_suffix (".Rmd")) {
                        icon_name = "applications-science-symbolic";
                    } else if (fname.has_suffix (".html") || fname.has_suffix (".htm")) {
                        icon_name = "text-html-symbolic";
                    } else if (fname.has_suffix (".png") || fname.has_suffix (".jpg") || fname.has_suffix (".svg")) {
                        icon_name = "image-x-generic-symbolic";
                    }
                    box.append (new Gtk.Image.from_icon_name (icon_name));
                    box.append (new Gtk.Label (fname) { xalign = 0, hexpand = true });
                    row.set_child (box);
                    row.set_data<string> ("file-path", full);
                    row.set_data<bool> ("is-dir", false);
                    files_list.append (row);
                }
            } catch (GLib.Error e) {
                warning ("Directory scan error: %s", e.message);
            }
        }

        // =================================================================
        // PLOTS GALLERY & EXPORT HELPERS
        // =================================================================
        public void register_generated_plot (string plot_file_path) {
            if (!GLib.FileUtils.test (plot_file_path, GLib.FileTest.EXISTS)) return;
            if (plot_gallery.size == 0 || plot_gallery.get (plot_gallery.size - 1) != plot_file_path) {
                plot_gallery.add (plot_file_path);
            }
            active_plot_idx = plot_gallery.size - 1;
            update_plot_view ();
        }

        private void update_plot_view () {
            if (plot_gallery.size == 0) {
                btn_prev_plot.sensitive = false;
                btn_next_plot.sensitive = false;
                btn_zoom_plot.sensitive = false;
                btn_copy_plot.sensitive = false;
                btn_export_plot.sensitive = false;
                btn_remove_plot.sensitive = false;
                btn_clear_all_plots.sensitive = false;
                plot_index_label.label = "No Plots";
                render_default_scientific_plot ();
                return;
            }

            if (active_plot_idx < 0) active_plot_idx = 0;
            if (active_plot_idx >= plot_gallery.size) active_plot_idx = plot_gallery.size - 1;

            btn_prev_plot.sensitive = (active_plot_idx > 0);
            btn_next_plot.sensitive = (active_plot_idx < plot_gallery.size - 1);
            btn_zoom_plot.sensitive = true;
            btn_copy_plot.sensitive = true;
            btn_export_plot.sensitive = true;
            btn_remove_plot.sensitive = true;
            btn_clear_all_plots.sensitive = true;

            plot_index_label.label = @"Plot $(active_plot_idx + 1) of $(plot_gallery.size)";
            load_plot_image (plot_gallery.get (active_plot_idx));
        }

        private void zoom_active_plot () {
            if (active_plot_idx < 0 || active_plot_idx >= plot_gallery.size) return;
            string plot_file = plot_gallery.get (active_plot_idx);
            if (!GLib.FileUtils.test (plot_file, GLib.FileTest.EXISTS)) return;

            var zoom_win = new Adw.Window () {
                title = @"Zoom: $(GLib.Path.get_basename (plot_file))",
                default_width = 960,
                default_height = 680
            };
            if (main_window != null) zoom_win.set_transient_for (main_window);

            var toolbar_view = new Adw.ToolbarView ();
            toolbar_view.add_top_bar (new Adw.HeaderBar ());

            var picture = new Gtk.Picture.for_filename (plot_file);
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            picture.can_shrink = true;
            picture.hexpand = true;
            picture.vexpand = true;
            picture.margin_top = 12;
            picture.margin_bottom = 12;
            picture.margin_start = 12;
            picture.margin_end = 12;

            toolbar_view.set_content (picture);
            zoom_win.set_content (toolbar_view);
            zoom_win.present ();
        }

        private void copy_active_plot_to_clipboard () {
            if (active_plot_idx < 0 || active_plot_idx >= plot_gallery.size) return;
            string plot_file = plot_gallery.get (active_plot_idx);
            try {
                var file = GLib.File.new_for_path (plot_file);
                var texture = Gdk.Texture.from_file (file);
                var display = Gdk.Display.get_default ();
                if (display != null) {
                    display.get_clipboard ().set_texture (texture);
                    if (main_window != null) main_window.show_toast ("Plot copied to clipboard");
                }
            } catch (GLib.Error e) {
                warning ("Failed to copy plot to clipboard: %s", e.message);
            }
        }

        private void export_active_plot_dialog () {
            if (active_plot_idx < 0 || active_plot_idx >= plot_gallery.size) return;
            string plot_file = plot_gallery.get (active_plot_idx);
            string base_name = GLib.Path.get_basename (plot_file);

            var dialog = new Gtk.FileDialog () {
                title = "Export Plot As Image",
                initial_name = base_name
            };

            dialog.save.begin (main_window, null, (obj, res) => {
                try {
                    var dest_file = dialog.save.end (res);
                    if (dest_file != null) {
                        var src_file = GLib.File.new_for_path (plot_file);
                        src_file.copy (dest_file, GLib.FileCopyFlags.OVERWRITE, null, null);
                        if (main_window != null) main_window.show_toast (@"Plot exported to $(dest_file.get_basename ())");
                    }
                } catch (GLib.Error e) {
                    // Canceled or failed
                }
            });
        }

        private void remove_active_plot () {
            if (active_plot_idx >= 0 && active_plot_idx < plot_gallery.size) {
                plot_gallery.remove_at (active_plot_idx);
                if (active_plot_idx >= plot_gallery.size) {
                    active_plot_idx = plot_gallery.size - 1;
                }
                update_plot_view ();
            }
        }

        private void clear_all_plots () {
            plot_gallery.clear ();
            active_plot_idx = -1;
            update_plot_view ();
        }

        // =================================================================
        // FILES PANEL ACTIONS (New Folder, New File, Delete, Rename)
        // =================================================================
        private void prompt_new_folder () {
            var dialog = new Adw.AlertDialog ("New Folder", "Enter folder name:");
            var entry = new Gtk.Entry () { placeholder_text = "Folder name..." };
            dialog.set_extra_child (entry);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("create", "Create");
            dialog.set_default_response ("create");
            dialog.set_response_appearance ("create", Adw.ResponseAppearance.SUGGESTED);

            dialog.response.connect ((resp) => {
                if (resp == "create") {
                    string folder_name = entry.text.strip ();
                    if (folder_name.length > 0) {
                        if (folder_name.contains ("..") || folder_name.contains ("/") || folder_name.contains ("\\")) {
                            if (main_window != null) {
                                main_window.show_toast ("Invalid folder name: path separators and '..' are not allowed.");
                            }
                            return;
                        }
                        string target = GLib.Path.build_filename (current_browser_dir, folder_name);
                        if (GLib.DirUtils.create_with_parents (target, 0755) != 0) {
                            if (main_window != null) {
                                main_window.show_toast (@"Failed to create folder '$folder_name'.");
                            }
                        } else {
                            populate_files_browser ();
                        }
                    }
                }
            });
            if (main_window != null) dialog.present (main_window);
        }

        private void prompt_new_file () {
            var dialog = new Adw.AlertDialog ("New Blank File", "Enter file name:");
            var entry = new Gtk.Entry () { placeholder_text = "e.g. script.R, analysis.qmd, data.csv..." };
            dialog.set_extra_child (entry);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("create", "Create");
            dialog.set_default_response ("create");
            dialog.set_response_appearance ("create", Adw.ResponseAppearance.SUGGESTED);

            dialog.response.connect ((resp) => {
                if (resp == "create") {
                    string fname = entry.text.strip ();
                    if (fname.length > 0) {
                        if (fname.contains ("..") || fname.contains ("/") || fname.contains ("\\")) {
                            if (main_window != null) {
                                main_window.show_toast ("Invalid file name: path separators and '..' are not allowed.");
                            }
                            return;
                        }
                        string target = GLib.Path.build_filename (current_browser_dir, fname);
                        try {
                            if (fname.has_suffix (".Rproj")) {
                                string p_name = fname.substring (0, fname.length - 6);
                                MallornManager.create_rproj_file (current_browser_dir, p_name);
                            } else if (fname.has_suffix (".ipynb")) {
                                string starter = Core.NotebookSerializer.get_default_ipynb_markdown_template ();
                                string ipynb_json = Core.NotebookSerializer.markdown_to_ipynb (starter, "python");
                                GLib.FileUtils.set_contents (target, ipynb_json);
                            } else {
                                GLib.FileUtils.set_contents (target, "");
                            }
                            populate_files_browser ();
                            if (main_window != null) main_window.open_file_from_path.begin (target);
                        } catch (GLib.Error e) {
                            if (main_window != null) {
                                main_window.show_toast (@"Failed to create file '$fname': $(e.message)");
                            }
                        }
                    }
                }
            });
            if (main_window != null) dialog.present (main_window);
        }

        private static void delete_file_recursive (GLib.File file) throws GLib.Error {
            var info = file.query_info (GLib.FileAttribute.STANDARD_TYPE, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                var enumerator = file.enumerate_children (
                    GLib.FileAttribute.STANDARD_NAME + "," + GLib.FileAttribute.STANDARD_TYPE,
                    GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                    null
                );
                GLib.FileInfo? child_info = null;
                while ((child_info = enumerator.next_file (null)) != null) {
                    delete_file_recursive (file.get_child (child_info.get_name ()));
                }
                enumerator.close (null);
            }
            file.delete (null);
        }

        private void prompt_delete_selected_file () {
            if (selected_file_path == null) {
                if (main_window != null) main_window.show_toast ("Select a file or folder first");
                return;
            }
            string base_name = GLib.Path.get_basename (selected_file_path);
            var dialog = new Adw.AlertDialog (@"Delete '$base_name'?", "Are you sure you want to delete this permanently?");
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", "Delete");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);

            dialog.response.connect ((resp) => {
                if (resp == "delete") {
                    try {
                        var f = GLib.File.new_for_path (selected_file_path);
                        delete_file_recursive (f);
                        selected_file_path = null;
                        populate_files_browser ();
                        if (main_window != null) main_window.show_toast (@"Deleted '$base_name'");
                    } catch (GLib.Error e) {
                        if (main_window != null) main_window.show_toast (@"Failed to delete: $(e.message)");
                    }
                }
            });
            if (main_window != null) dialog.present (main_window);
        }

        private void prompt_rename_selected_file () {
            if (selected_file_path == null) {
                if (main_window != null) main_window.show_toast ("Select a file or folder first");
                return;
            }
            string old_name = GLib.Path.get_basename (selected_file_path);
            var dialog = new Adw.AlertDialog (@"Rename '$old_name'", "Enter new name:");
            var entry = new Gtk.Entry () { text = old_name };
            dialog.set_extra_child (entry);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("rename", "Rename");
            dialog.set_default_response ("rename");

            dialog.response.connect ((resp) => {
                if (resp == "rename") {
                    string new_name = entry.text.strip ();
                    if (new_name.length > 0 && new_name != old_name) {
                        string parent_dir = GLib.Path.get_dirname (selected_file_path);
                        string new_path = GLib.Path.build_filename (parent_dir, new_name);
                        try {
                            var src = GLib.File.new_for_path (selected_file_path);
                            var dst = GLib.File.new_for_path (new_path);
                            src.move (dst, GLib.FileCopyFlags.NONE, null, null);
                            selected_file_path = new_path;
                            populate_files_browser ();
                            if (main_window != null) main_window.show_toast (@"Renamed to '$new_name'");
                        } catch (GLib.Error e) {
                            if (main_window != null) main_window.show_toast (@"Failed to rename: $(e.message)");
                        }
                    }
                }
            });
            if (main_window != null) dialog.present (main_window);
        }

        private Gtk.Popover create_files_more_popover () {
            var pop = new Gtk.Popover ();
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6
            };

            var btn_swd = new Gtk.Button.with_label ("Set As Working Directory");
            btn_swd.add_css_class ("flat");
            btn_swd.clicked.connect (() => {
                pop.popdown ();
                get_session_manager ().set_working_directory (current_browser_dir);
                if (main_window != null) main_window.show_toast (@"Working directory set to: $(GLib.Path.get_basename (current_browser_dir))");
            });
            vbox.append (btn_swd);

            var btn_gwd = new Gtk.Button.with_label ("Go To Working Directory");
            btn_gwd.add_css_class ("flat");
            btn_gwd.clicked.connect (() => {
                pop.popdown ();
                current_browser_dir = get_session_manager ().current_working_dir;
                populate_files_browser ();
            });
            vbox.append (btn_gwd);

            var btn_ot = new Gtk.Button.with_label ("Open in Terminal");
            btn_ot.add_css_class ("flat");
            btn_ot.clicked.connect (() => {
                pop.popdown ();
                string target_dir = current_browser_dir != "" ? current_browser_dir : get_session_manager ().current_working_dir;
                activate_panel_in_dock (PanelId.TERMINAL);
                Gtk.TextIter end;
                terminal_view.buffer.get_end_iter (out end);
                terminal_view.buffer.insert (ref end, "\n[cwd: " + target_dir + "]\n$ ", -1);
            });
            vbox.append (btn_ot);

            pop.set_child (vbox);
            return pop;
        }

        // =================================================================
        // HISTORY PANEL HELPERS
        // =================================================================
        private void history_to_console () {
            var selected_row = history_list.get_selected_row ();
            if (selected_row != null) {
                string? cmd = selected_row.get_data<string> ("cmd-text");
                if (cmd != null && repl_entry != null) {
                    repl_entry.text = cmd;
                    repl_entry.grab_focus ();
                    repl_entry.set_position (-1);
                }
            }
        }

        private void history_to_source () {
            var selected_row = history_list.get_selected_row ();
            if (selected_row != null) {
                string? cmd = selected_row.get_data<string> ("cmd-text");
                if (cmd != null) {
                    doc_page.source_buffer.begin_user_action ();
                    doc_page.source_buffer.insert_at_cursor (cmd + "\n", -1);
                    doc_page.source_buffer.end_user_action ();
                    doc_page.source_view.grab_focus ();
                }
            }
        }

        private void save_history_dialog () {
            string cwd = get_session_manager ().current_working_dir;
            if (cwd.length == 0) cwd = GLib.Environment.get_current_dir ();
            string rhistory_path = GLib.Path.build_filename (cwd, ".Rhistory");

            bool ok = Services.HistoryManager.get_default ().save_to_file (rhistory_path);
            if (ok && main_window != null) {
                main_window.show_toast (@"Command history saved to $(GLib.Path.get_basename (rhistory_path))");
            }
        }

        private void add_history_row (Services.HistoryEntry entry) {
            var row = new Gtk.ListBoxRow ();
            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 4, margin_bottom = 4, margin_start = 6, margin_end = 6
            };
            string icon_name = entry.engine == "r" ? "utilities-terminal-symbolic" : "text-x-python-symbolic";
            hbox.append (new Gtk.Image.from_icon_name (icon_name));
            var lbl = new Gtk.Label (entry.command) {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                css_classes = { "monospace", "caption" }
            };
            hbox.append (lbl);

            string ts = entry.timestamp.format ("%H:%M:%S");
            var ts_lbl = new Gtk.Label (ts) {
                css_classes = { "dim-label", "caption" }
            };
            hbox.append (ts_lbl);

            row.set_child (hbox);
            row.set_data<string> ("cmd-text", entry.command);
            history_list.append (row);
        }

        private void clear_history_ui () {
            Gtk.Widget? child = history_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                history_list.remove (child);
                child = next;
            }
        }

        private void filter_history_ui (string query) {
            Gtk.Widget? child = history_list.get_first_child ();
            while (child != null) {
                var row = child as Gtk.ListBoxRow;
                if (row != null) {
                    string? cmd = row.get_data<string> ("cmd-text");
                    row.visible = (query.length == 0 || (cmd != null && cmd.down ().contains (query)));
                }
                child = child.get_next_sibling ();
            }
        }

        // =================================================================
        // PACKAGES PANEL HELPERS
        // =================================================================
        public async void scan_installed_packages () {
            installed_packages.clear ();
            string r_probe = """
local({
  pkgs <- installed.packages()
  cat("___IMLADRIS_PKGS_START___\n")
  if (nrow(pkgs) > 0L) {
    titles <- gsub("[\r\n\t]+", " ", pkgs[, "Title"])
    titles[is.na(titles)] <- ""
    res <- paste(pkgs[, "Package"], pkgs[, "Version"], titles, sep = "\t")
    cat(res, sep = "\n")
  }
  cat("___IMLADRIS_PKGS_END___\n")
})
""";
            string? plot_out = null;
            string out_str = yield get_session_manager ().execute_r (r_probe, out plot_out);

            if (out_str.contains ("___IMLADRIS_PKGS_START___")) {
                int s = out_str.index_of ("___IMLADRIS_PKGS_START___") + "___IMLADRIS_PKGS_START___".length;
                int e = out_str.index_of ("___IMLADRIS_PKGS_END___");
                if (e > s) {
                    string block = out_str.substring (s, e - s).strip ();
                    string[] lines = block.split ("\n");
                    foreach (var l in lines) {
                        string[] parts = l.strip ().split ("\t");
                        if (parts.length >= 2) {
                            string pname = parts[0].strip ();
                            string pver = parts[1].strip ();
                            string pdesc = parts.length >= 3 ? parts[2].strip () : "";
                            installed_packages.add (new PackageItem (pname, pver, pdesc, false));
                        }
                    }
                }
            }

            filter_packages_ui ();
        }

        private void filter_packages_ui () {
            Gtk.Widget? child = packages_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                packages_list.remove (child);
                child = next;
            }

            if (installed_packages.size == 0) {
                var empty_row = new Adw.ActionRow () {
                    title = "No R packages detected",
                    subtitle = "Configure an R runtime in Data Science Toolchains, then click Refresh",
                    use_markup = false
                };
                empty_row.add_prefix (new Gtk.Image.from_icon_name ("application-x-addon-symbolic"));
                packages_list.append (empty_row);
                return;
            }

            string query = packages_search_entry != null ? packages_search_entry.text.strip ().down () : "";
            foreach (var pkg in installed_packages) {
                if (query.length > 0 && !pkg.name.down ().contains (query) && !pkg.description.down ().contains (query)) {
                    continue;
                }

                var row = new Adw.ActionRow () {
                    title = pkg.name,
                    subtitle = pkg.description.length > 0 ? pkg.description : "Installed R Package",
                    use_markup = false
                };

                var check = new Gtk.CheckButton () {
                    active = pkg.is_loaded,
                    valign = Gtk.Align.CENTER
                };
                string pkg_name = pkg.name;
                check.toggled.connect (() => {
                    pkg.is_loaded = check.active;
                    if (check.active) {
                        run_code_snippet_in_console ("r", @"library($pkg_name)");
                    } else {
                        run_code_snippet_in_console ("r", @"detach(\"package:$pkg_name\", unload = TRUE)");
                    }
                });
                row.add_prefix (check);

                var ver_badge = new Gtk.Label (pkg.version) {
                    css_classes = { "dim-label", "caption", "pill", "monospace" },
                    valign = Gtk.Align.CENTER
                };
                row.add_suffix (ver_badge);

                packages_list.append (row);
            }
        }

        // =================================================================
        // HELP PANEL & R DOCUMENTATION HELPERS
        // =================================================================
        private void load_default_help_home () {
            string bg, text, card_bg, card_border, title_col, sub_col;
            get_plot_theme_colors (out bg, out text, out card_bg, out card_border, out title_col, out sub_col);
            string home_html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body { font-family: system-ui, -apple-system, sans-serif; padding: 20px; color: %s; line-height: 1.5; font-size: 13px; background: %s; }
  h2 { color: %s; margin-top: 0; font-size: 18px; border-bottom: 1px solid %s; padding-bottom: 8px; }
  h3 { color: %s; margin-bottom: 6px; margin-top: 18px; font-size: 14px; }
  code { background: %s; border: 1px solid %s; padding: 2px 5px; border-radius: 4px; font-family: monospace; font-size: 12px; }
  ul { padding-left: 20px; }
  li { margin-bottom: 4px; }
  .tip-box { background: %s; border-left: 4px solid #3b82f6; padding: 10px 14px; border-radius: 4px; margin: 12px 0; color: %s; }
</style>
</head>
<body>
  <h2>Imladris &amp; RStudio Workbench Documentation</h2>
  <div class="tip-box">
    <strong>Instant Help Query:</strong> Type <code>?topic</code> or <code>help(name)</code> in the Console or search entry above to render full R man pages.
  </div>
  <h3>Core Keybindings</h3>
  <ul>
    <li><code>Ctrl+Enter</code> — Run Current Line or Selection (advances cursor to next line).</li>
    <li><code>Ctrl+Shift+Enter</code> — Run Current Active Chunk.</li>
    <li><code>Ctrl+Alt+P</code> — Run All Chunks Above.</li>
    <li><code>Ctrl+Alt+R</code> — Run All Chunks in Document.</li>
    <li><code>Ctrl+Shift+F10</code> — Restart R / Python Session.</li>
    <li><code>Ctrl+L</code> — Clear Interactive Console.</li>
  </ul>
  <h3>Quadrant Layout System</h3>
  <ul>
    <li><strong>Quadrant 1 (Top-Left):</strong> Source Editor &amp; Data Viewer (<code>View(df)</code>).</li>
    <li><strong>Quadrant 2 (Bottom-Left):</strong> Interactive Console, Shell Terminal, Elrond AI.</li>
    <li><strong>Quadrant 3 (Top-Right):</strong> Environment Inspector, History, Document Outline, Citations.</li>
    <li><strong>Quadrant 4 (Bottom-Right):</strong> Files Browser, Plots Gallery, Packages Manager, Help &amp; Reference, Web Preview.</li>
  </ul>
</body>
</html>""".printf (text, bg, title_col, card_border, title_col, card_bg, card_border, card_bg, sub_col);
            help_view.load_html (home_html, "file:///");
        }

        public async void show_help_for_topic (string topic) {
            string sanitized = topic.replace ("\\", "\\\\").replace ("\"", "").replace ("'", "").strip ();
            if (sanitized.length == 0) return;

            string r_probe = """
local({
  h <- help("__IMLADRIS_TOPIC__")
  if (length(h) > 0) {
    txt <- utils:::.getHelpFile(h)
    f <- tempfile(fileext = ".html")
    tools::Rd2HTML(txt, out = f)
    cat("___IMLADRIS_HELP_START___\n")
    cat(readChar(f, file.info(f)$size, useBytes = TRUE))
    cat("\n___IMLADRIS_HELP_END___\n")
    unlink(f)
  } else {
    cat("___IMLADRIS_HELP_NOT_FOUND___\n")
  }
})
""".replace ("__IMLADRIS_TOPIC__", sanitized);

            string? plot_out = null;
            string out_str = yield get_session_manager ().execute_r (r_probe, out plot_out);

            if (out_str.contains ("___IMLADRIS_HELP_START___")) {
                int s = out_str.index_of ("___IMLADRIS_HELP_START___") + "___IMLADRIS_HELP_START___".length;
                int e = out_str.index_of ("___IMLADRIS_HELP_END___");
                if (e > s) {
                    string html = out_str.substring (s, e - s).strip ();
                    string styled_html = inject_help_styling (html);
                    help_view.load_html (styled_html, "file:///");
                    activate_panel_in_dock (PanelId.HELP);
                    return;
                }
            }

            render_help_fallback (sanitized);
            activate_panel_in_dock (PanelId.HELP);
        }

        private string inject_help_styling (string raw_html) {
            string bg, text, card_bg, card_border, title_col, sub_col;
            get_plot_theme_colors (out bg, out text, out card_bg, out card_border, out title_col, out sub_col);
            string style = """<style>
body { font-family: system-ui, sans-serif; padding: 16px 20px; line-height: 1.5; font-size: 13px; color: %s; background: %s; }
h2 { color: %s; border-bottom: 1px solid %s; padding-bottom: 6px; }
h3 { color: %s; margin-top: 14px; }
a { color: #3b82f6; }
pre, code { font-family: monospace; background: %s; border: 1px solid %s; border-radius: 4px; padding: 2px 4px; font-size: 12px; color: %s; }
pre { padding: 10px; overflow-x: auto; }
table { border-collapse: collapse; width: 100%%; margin: 12px 0; }
th, td { border: 1px solid %s; padding: 6px 10px; text-align: left; }
th { background: %s; }
</style>""".printf (text, bg, title_col, card_border, title_col, card_bg, card_border, text, card_border, card_bg);
            if (raw_html.contains ("<head>")) {
                return raw_html.replace ("<head>", "<head>" + style);
            }
            return style + raw_html;
        }

        private void render_help_fallback (string topic) {
            string bg, text, card_bg, card_border, title_col, sub_col;
            get_plot_theme_colors (out bg, out text, out card_bg, out card_border, out title_col, out sub_col);
            string safe_topic = GLib.Markup.escape_text (topic);
            string html = """<!DOCTYPE html><html><body style="font-family:system-ui,sans-serif;padding:24px;background:%s;color:%s;text-align:center;">
<h3 style="color:%s;">No documentation found for <code>%s</code></h3>
<p style="font-size:12px;color:%s;">Ensure R is running and package is loaded via <code>library(...)</code>.</p>
</body></html>""".printf (bg, text, title_col, safe_topic, sub_col);
            help_view.load_html (html, "file:///");
        }

        private void activate_panel_in_dock (PanelId pid) {
            foreach (var qid in QuadrantId.all ()) {
                var qc = doc_page.dock_layout_state.quadrants.get (qid);
                if (qc != null && qc.tabs.contains (pid)) {
                    doc_page.dock_layout_state.activate_tab (qid, pid);
                    return;
                }
            }
        }

        private void load_empty_shiny_placeholder () {
            if (shiny_webview == null) return;
            string bg, text, card_bg, card_border, title_col, sub_col;
            get_plot_theme_colors (out bg, out text, out card_bg, out card_border, out title_col, out sub_col);
            string html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    background: %s;
    color: %s;
    font-family: system-ui, -apple-system, sans-serif;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 90vh;
    margin: 0;
    text-align: center;
  }
  .icon { font-size: 40px; margin-bottom: 12px; opacity: 0.7; }
  h2 { color: %s; margin: 0 0 8px 0; font-size: 16px; }
  p { font-size: 13px; max-width: 320px; line-height: 1.5; margin: 0; }
  code { background: %s; border: 1px solid %s; padding: 2px 6px; border-radius: 4px; color: %s; }
</style>
</head>
<body>
  <div class="icon">⚡</div>
  <h2>Shiny Web App Viewer</h2>
  <p>Run a Shiny application (<code>app.R</code> or <code>shinyApp()</code>) to preview interactive reactive dashboards directly in this pane.</p>
</body>
</html>""".printf (bg, sub_col, title_col, card_bg, card_border, text);
            shiny_webview.load_html (html, "file:///");
        }

        public void open_shiny_in_dedicated_window () {
            var service = Services.ShinyService.get_default ();
            if (service.active_url == null) return;
            if (active_shiny_window != null) {
                active_shiny_window.present ();
                return;
            }
            active_shiny_window = new ShinyWindow (main_window, service.active_url);
            active_shiny_window.close_request.connect (() => {
                active_shiny_window = null;
                return false;
            });
            active_shiny_window.present ();
        }
    }
}
