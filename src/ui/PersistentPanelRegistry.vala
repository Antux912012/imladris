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
        public Gtk.ListBox environment_list { get; private set; }
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

        public PersistentPanelRegistry (DocumentPage page, Window? win) {
            this.doc_page = page;
            this.main_window = win;
            this.panels = new Gee.HashMap<PanelId, Gtk.Widget> ();
            this.plot_gallery = new Gee.ArrayList<string> ();
            this.installed_packages = new Gee.ArrayList<PackageItem> ();

            build_all_persistent_panels ();
        }

        public Gtk.Widget? get_panel_widget (PanelId id) {
            return panels.get (id);
        }

        /**
         * Portal / Host Re-parenting Pattern:
         * Detaches the persistent widget from its previous parent container (if any)
         * and mounts it inside the target viewport without destroying the widget or undo stack.
         */
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

            notebook_cell_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            notebook_cell_toolbar.add_css_class ("dock-subtoolbar");

            var cell_badge = new Gtk.Label ("Notebook / Chunk Actions:") {
                css_classes = { "dim-label", "caption" }
            };
            notebook_cell_toolbar.append (cell_badge);

            var run_cell_btn = new Gtk.Button () {
                tooltip_text = "Execute active code cell or chunk (Ctrl+Enter)"
            };
            run_cell_btn.add_css_class ("flat");
            run_cell_btn.add_css_class ("ribbon-compact-btn");
            var rc_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            rc_box.append (new Gtk.Image.from_icon_name ("media-playback-start-symbolic"));
            rc_box.append (new Gtk.Label ("Run Cell (Ctrl+Enter)"));
            run_cell_btn.set_child (rc_box);
            run_cell_btn.clicked.connect (() => {
                execute_active_cell ();
            });
            notebook_cell_toolbar.append (run_cell_btn);

            var run_all_btn = new Gtk.Button () {
                tooltip_text = "Execute all code cells sequentially"
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

            var add_py_btn = new Gtk.Button.with_label ("+ Python Cell");
            add_py_btn.add_css_class ("flat");
            add_py_btn.add_css_class ("ribbon-compact-btn");
            add_py_btn.clicked.connect (() => {
                doc_page.insert_code_chunk ("python", "echo: true");
            });
            notebook_cell_toolbar.append (add_py_btn);

            var add_r_btn = new Gtk.Button.with_label ("+ R Cell");
            add_r_btn.add_css_class ("flat");
            add_r_btn.add_css_class ("ribbon-compact-btn");
            add_r_btn.clicked.connect (() => {
                doc_page.insert_code_chunk ("r", "echo: true");
            });
            notebook_cell_toolbar.append (add_r_btn);

            source_editor_panel.append (notebook_cell_toolbar);
            source_editor_panel.append (doc_page.editor_scroller);
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
            var preview_lbl = new Gtk.Label ("Rendered Output (WebKitGTK 6.0)") {
                css_classes = { "dim-label", "caption" }
            };
            preview_bar.append (preview_lbl);
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
            live_preview_panel.append (doc_page.web_view);
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
                Services.HistoryManager.get_default ().add_entry (cmd_text, engine);
                run_code_snippet_in_console (engine, cmd_text);
            });

            var stop_btn = new Gtk.Button.from_icon_name ("process-stop-symbolic") {
                tooltip_text = "Interrupt Execution (Stop / SIGINT)"
            };
            stop_btn.add_css_class ("flat");
            stop_btn.add_css_class ("destructive-action");
            stop_btn.clicked.connect (() => {
                Services.PersistentSessionManager.get_default ().interrupt_active_execution ();
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
            environment_controller.view_dataframe_requested.connect ((name, eng) => {
                open_dataframe_in_viewer (name, eng);
            });
            environment_controller.toast_requested.connect ((msg) => {
                if (main_window != null) main_window.show_toast (msg);
            });
            environment_list = new Gtk.ListBox (); // dummy placeholder for AST variables
            panels.set (PanelId.ENVIRONMENT, environment_controller);

            // DATA VIEWER PANEL (Virtualized Matrix & Dataframe Inspector)
            data_grid_viewer = new DataGridViewer ();
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

                // Read local bib if available
                string? fallback_bib = null;
                if (doc_page.current_project_dir != "") {
                    string bib_path = GLib.Path.build_filename (doc_page.current_project_dir, "references.bib");
                    var f = GLib.File.new_for_path (bib_path);
                    if (f.query_exists ()) {
                        try {
                            uint8[] data;
                            f.load_contents (null, out data, null);
                            fallback_bib = (string) data;
                        } catch (GLib.Error e) {}
                    }
                }

                zotero_svc.search_citations_async.begin (q, fallback_bib, (obj, res) => {
                    var items = zotero_svc.search_citations_async.end (res);
                    var child = citations_list.get_first_child ();
                    while (child != null) {
                        var next = child.get_next_sibling ();
                        citations_list.remove (child);
                        child = next;
                    }

                    if (items.size == 0) {
                        var empty_row = new Adw.ActionRow () {
                            title = "No citations found",
                            subtitle = @"No matches for '$q' in Zotero or references.bib"
                        };
                        citations_list.append (empty_row);
                        return;
                    }

                    foreach (var item in items) {
                        var row = new Adw.ActionRow () {
                            title = @"@$(item.citekey)",
                            subtitle = @"$(item.authors) ($(item.year)) — $(item.title)"
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
                            Gtk.TextIter s, e;
                            doc_page.source_buffer.get_bounds (out s, out e);
                            string cur_text = doc_page.source_buffer.get_text (s, e, false);
                            string updated_text = zotero_svc.ensure_yaml_bibliography (cur_text, "references.bib");
                            if (updated_text != cur_text) {
                                doc_page.source_buffer.begin_user_action ();
                                doc_page.source_buffer.set_text (updated_text);
                                doc_page.source_buffer.end_user_action ();
                            }
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
                            } catch (GLib.Error e) {}
                        });
                        row.add_suffix (open_btn);

                        citations_list.append (row);
                    }
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
            Services.HistoryManager.get_default ().entry_added.connect ((entry) => {
                add_history_row (entry);
            });
            Services.HistoryManager.get_default ().history_cleared.connect (() => {
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
            update_plot_view ();
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
                } else if (main_window != null) {
                    main_window.open_file_from_path.begin (fpath);
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
            Services.PersistentSessionManager.get_default ().working_directory_changed.connect ((new_dir) => {
                this.current_browser_dir = new_dir;
                this.root_project_dir = new_dir;
                populate_files_browser ();
                Gtk.TextIter end;
                terminal_view.buffer.get_end_iter (out end);
                terminal_view.buffer.insert (ref end, @"\n[Working Directory changed to: $new_dir]\n$$ ", -1);
            });
            Services.PersistentSessionManager.get_default ().plot_generated.connect ((plot_path) => {
                plot_gallery.add (plot_path);
                active_plot_idx = plot_gallery.size - 1;
                update_plot_view ();
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
            panels.set (PanelId.PACKAGES, pkg_box);
            scan_installed_packages.begin ();

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
            load_default_help_home ();
            panels.set (PanelId.HELP, help_box);

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

            var chunk = Core.ChunkParser.find_chunk_at_line (doc_page.source_buffer.text, cursor_line);
            if (chunk != null) {
                return chunk.language;
            }

            if (doc_page.doc_type == "r" || (doc_page.file_location != null && doc_page.file_location.get_basename ().has_suffix (".R"))) {
                return "r";
            }
            if (doc_page.doc_type == "rmd" || (doc_page.file_location != null && doc_page.file_location.get_basename ().has_suffix (".Rmd"))) {
                return "r";
            }
            return "python";
        }

        /**
         * Pillar 4 & 11: Chunk Execution (Ctrl+Shift+Enter) with Inline Card Output
         */
        public void execute_active_cell () {
            string text = doc_page.source_buffer.text;
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
            string text = doc_page.source_buffer.text;
            var chunks = Core.ChunkParser.parse_chunks (text);
            foreach (var ch in chunks) {
                if (ch.code.length > 0) {
                    run_code_snippet_in_console (ch.language, ch.code, ch.end_line);
                }
            }
        }

        public void execute_cells_above () {
            string text = doc_page.source_buffer.text;
            Gtk.TextIter cursor;
            doc_page.source_buffer.get_iter_at_mark (out cursor, doc_page.source_buffer.get_insert ());
            int cursor_line = cursor.get_line ();

            var chunks = Core.ChunkParser.parse_chunks (text);
            foreach (var ch in chunks) {
                if (ch.end_line < cursor_line && ch.code.length > 0) {
                    run_code_snippet_in_console (ch.language, ch.code, ch.end_line);
                }
            }
        }

        public void open_dataframe_in_viewer (string object_name, string engine = "r") {
            data_grid_viewer.fetch_and_display.begin (object_name, engine);

            foreach (var qid in QuadrantId.all ()) {
                var qc = doc_page.dock_layout_state.quadrants.get (qid);
                if (qc != null && qc.tabs.contains (PanelId.DATA_VIEWER)) {
                    doc_page.dock_layout_state.activate_tab (qid, PanelId.DATA_VIEWER);
                    return;
                }
            }

            // If not found in any quadrant, mount in Q1_TOP_LEFT
            doc_page.dock_layout_state.move_tab (QuadrantId.Q1_TOP_LEFT, QuadrantId.Q1_TOP_LEFT, PanelId.DATA_VIEWER, 1);
            doc_page.dock_layout_state.activate_tab (QuadrantId.Q1_TOP_LEFT, PanelId.DATA_VIEWER);
        }

        public void run_code_snippet_in_console (string engine, string code, int inline_chunk_line = -1) {
            execution_counter++;
            int count = execution_counter;
            doc_page.append_console_log (@"\nIn [$count] ($engine):\n$code");
            Services.HistoryManager.get_default ().add_entry (code, engine);

            // Hook R/Python View(...) command to open interactive matrix & dataframe viewer
            if (code.contains ("View(") || code.contains ("View (")) {
                int v_idx = code.index_of ("View");
                int open_paren = code.index_of ("(", v_idx);
                int close_paren = code.index_of (")", open_paren);
                if (open_paren != -1 && close_paren != -1 && close_paren > open_paren) {
                    string obj = code.substring (open_paren + 1, close_paren - open_paren - 1).strip ();
                    if (obj.length > 0 && !obj.contains ("\n")) {
                        open_dataframe_in_viewer (obj, engine);
                    }
                }
            }

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

            if (engine == "r") {
                string? plot_file = null;
                bool any_line_streamed = false;
                ulong sig_id = 0;
                sig_id = Services.PersistentSessionManager.get_default ().session_output_received.connect ((eng, line, is_err) => {
                    if (eng == "r") {
                        any_line_streamed = true;
                        doc_page.append_console_log (line);
                    }
                });

                Services.PersistentSessionManager.get_default ().execute_r.begin (code, (obj, res) => {
                    Services.PersistentSessionManager.get_default ().disconnect (sig_id);
                    string output = Services.PersistentSessionManager.get_default ().execute_r.end (res, out plot_file).strip ();
                    if (!any_line_streamed && output.length > 0) {
                        doc_page.append_console_log (@"Out [$count]:\n$output");
                        if (output.contains ("Install Toolchain") && main_window != null) {
                            main_window.show_toolchain_setup_dialog ();
                        }
                    }
                    if (plot_file != null) {
                        load_plot_image (plot_file);
                        string base_plot = GLib.Path.get_basename (plot_file);
                        doc_page.append_console_log (@"📊 [Plot rendered in Quadrant 4: $base_plot]");
                    }
                    if (inline_chunk_line >= 0) {
                        doc_page.display_inline_chunk_output (inline_chunk_line, output, plot_file, count);
                    }
                    refresh_environment_and_outline ();
                    environment_controller.active_engine = "r";
                    environment_controller.refresh_environment.begin ();
                });
            } else if (engine == "python") {
                string? plot_file = null;
                bool any_line_streamed = false;
                ulong sig_id = 0;
                sig_id = Services.PersistentSessionManager.get_default ().session_output_received.connect ((eng, line, is_err) => {
                    if (eng == "python") {
                        any_line_streamed = true;
                        doc_page.append_console_log (line);
                    }
                });

                Services.PersistentSessionManager.get_default ().execute_python.begin (code, (obj, res) => {
                    Services.PersistentSessionManager.get_default ().disconnect (sig_id);
                    string output = Services.PersistentSessionManager.get_default ().execute_python.end (res, out plot_file).strip ();
                    if (!any_line_streamed && output.length > 0) {
                        doc_page.append_console_log (@"Out [$count]:\n$output");
                        if (output.contains ("Install Toolchain") && main_window != null) {
                            main_window.show_toolchain_setup_dialog ();
                        }
                    }
                    if (plot_file != null) {
                        load_plot_image (plot_file);
                        string base_plot = GLib.Path.get_basename (plot_file);
                        doc_page.append_console_log (@"📊 [Plot rendered in Quadrant 4: $base_plot]");
                    }
                    if (inline_chunk_line >= 0) {
                        doc_page.display_inline_chunk_output (inline_chunk_line, output, plot_file, count);
                    }
                    refresh_environment_and_outline ();
                    environment_controller.active_engine = "python";
                    environment_controller.refresh_environment.begin ();
                });
            } else {
                ExecutionEngine.capture_command_async.begin ({ "bash", "-c", code }, (obj, res) => {
                    string output = ExecutionEngine.capture_command_async.end (res).strip ();
                    if (output.length > 0) {
                        doc_page.append_console_log (@"Out [$count]:\n$output");
                    }
                    if (inline_chunk_line >= 0) {
                        doc_page.display_inline_chunk_output (inline_chunk_line, output, null, count);
                    }
                    refresh_environment_and_outline ();
                });
            }
        }

        private void run_shell_command (string cmd) {
            Gtk.TextIter end;
            terminal_view.buffer.get_end_iter (out end);
            terminal_view.buffer.insert (ref end, cmd + "\n", -1);

            ExecutionEngine.capture_command_async.begin ({ "bash", "-c", cmd }, (obj, res) => {
                string output = ExecutionEngine.capture_command_async.end (res);
                Gtk.TextIter e2;
                terminal_view.buffer.get_end_iter (out e2);
                terminal_view.buffer.insert (ref e2, output + "\n$ ", -1);
            });
        }

        public void refresh_environment_and_outline () {
            // Clear existing rows
            Gtk.Widget? child = environment_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                environment_list.remove (child);
                child = next;
            }

            child = outline_list.get_first_child ();
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

            string text = doc_page.source_buffer.text;
            string[] lines = text.split ("\n");

            int var_count = 0;
            int chunk_idx = 0;

            for (int i = 0; i < lines.length; i++) {
                string line = lines[i];
                string trimmed = line.strip ();

                // 1. Outline headings & chunks
                if (trimmed.has_prefix ("#")) {
                    var row = new Gtk.ListBoxRow ();
                    var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                        margin_top = 4, margin_bottom = 4, margin_start = 6, margin_end = 6
                    };
                    hbox.append (new Gtk.Image.from_icon_name ("format-text-bold-symbolic"));
                    hbox.append (new Gtk.Label (trimmed) { xalign = 0, hexpand = true });
                    hbox.append (new Gtk.Label (@"L$(i + 1)") { css_classes = { "dim-label", "caption" } });
                    row.set_child (hbox);
                    row.set_data<int> ("target-line", i);
                    outline_list.append (row);
                } else if (trimmed.has_prefix ("```{")) {
                    chunk_idx++;
                    var row = new Gtk.ListBoxRow ();
                    var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                        margin_top = 4, margin_bottom = 4, margin_start = 14, margin_end = 6
                    };
                    hbox.append (new Gtk.Image.from_icon_name ("utilities-terminal-symbolic"));
                    hbox.append (new Gtk.Label (@"Chunk #$chunk_idx: $trimmed") { xalign = 0, hexpand = true, css_classes = { "monospace", "caption" } });
                    hbox.append (new Gtk.Label (@"L$(i + 1)") { css_classes = { "dim-label", "caption" } });
                    row.set_child (hbox);
                    row.set_data<int> ("target-line", i);
                    outline_list.append (row);
                }

                // 2. Environment variable detection (Python / R / YAML assignments)
                if (trimmed.contains ("<-") || (trimmed.contains ("=") && !trimmed.has_prefix ("#") && !trimmed.has_prefix ("<"))) {
                    string[] parts = trimmed.contains ("<-") ? trimmed.split ("<-", 2) : trimmed.split ("=", 2);
                    if (parts.length == 2) {
                        string vname = parts[0].strip ();
                        string vval = parts[1].strip ();
                        if (vname.length > 0 && vname.length < 32 && !vname.contains (" ")) {
                            var_count++;
                            string vtype = "scalar";
                            if (vval.has_prefix ("[") || vval.has_prefix ("c(")) vtype = "vector / list";
                            else if (vval.contains ("read_") || vval.contains ("DataFrame") || vval.contains ("mtcars")) vtype = "data.frame";
                            else if (vval.has_prefix ("\"") || vval.has_prefix ("'")) vtype = "string";
                            add_env_row (vname, vtype, vval);
                        }
                    }
                }

                // 3. Citations detection (@key)
                if (trimmed.contains ("@") && !trimmed.has_prefix ("mailto:")) {
                    string[] words = trimmed.split_set (" [](),;.\t");
                    foreach (string w in words) {
                        if (w.has_prefix ("@") && w.length > 2) {
                            var crow = new Adw.ActionRow () {
                                title = w,
                                subtitle = @"Referenced on line $(i + 1)"
                            };
                            var ins_btn = new Gtk.Button.from_icon_name ("insert-text-symbolic") {
                                valign = Gtk.Align.CENTER,
                                tooltip_text = "Insert citation at cursor"
                            };
                            ins_btn.add_css_class ("flat");
                            string cite_key = w;
                            ins_btn.clicked.connect (() => {
                                doc_page.source_buffer.insert_at_cursor (@"[$cite_key]", -1);
                            });
                            crow.add_suffix (ins_btn);
                            citations_list.append (crow);
                        }
                    }
                }
            }

            // Always show standard active session objects in Environment
            add_env_row ("mtcars", "data.frame [32 × 11]", "mpg, cyl, disp, hp, drat, wt...");
            add_env_row ("session_executions", "integer", @"$execution_counter cell runs");
        }

        private void add_env_row (string name, string type_str, string val_preview) {
            var row = new Adw.ActionRow () {
                title = name,
                subtitle = @"$type_str — $val_preview"
            };
            row.add_prefix (new Gtk.Image.from_icon_name ("view-list-symbolic"));
            environment_list.append (row);
        }

        public void render_default_scientific_plot () {
            string svg_html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    margin: 0;
    padding: 16px;
    background: #ffffff;
    font-family: system-ui, sans-serif;
    color: #1e293b;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .plot-card {
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 16px;
    background: #f8fafc;
    width: 92%;
    max-width: 560px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
  }
  .plot-title {
    font-size: 14px;
    font-weight: 700;
    margin-bottom: 4px;
    color: #0f172a;
  }
  .plot-sub {
    font-size: 11px;
    color: #64748b;
    margin-bottom: 12px;
  }
</style>
</head>
<body>
  <div class="plot-card">
    <div class="plot-title">mtcars: Miles Per Gallon (mpg) vs Horsepower (hp)</div>
    <div class="plot-sub">Rendered SVG Figure • RStudio Quadrant 4 Output</div>
    <svg viewBox="0 0 460 240" width="100%" height="auto" xmlns="http://www.w3.org/2000/svg">
      <rect x="40" y="10" width="400" height="195" fill="#ffffff" stroke="#cbd5e1" stroke-width="1"/>
      <!-- Grid lines -->
      <line x1="40" y1="50" x2="440" y2="50" stroke="#f1f5f9" stroke-width="1"/>
      <line x1="40" y1="100" x2="440" y2="100" stroke="#f1f5f9" stroke-width="1"/>
      <line x1="40" y1="150" x2="440" y2="150" stroke="#f1f5f9" stroke-width="1"/>
      <line x1="140" y1="10" x2="140" y2="205" stroke="#f1f5f9" stroke-width="1"/>
      <line x1="240" y1="10" x2="240" y2="205" stroke="#f1f5f9" stroke-width="1"/>
      <line x1="340" y1="10" x2="340" y2="205" stroke="#f1f5f9" stroke-width="1"/>
      <!-- Regression trend line -->
      <line x1="60" y1="35" x2="410" y2="185" stroke="#3b82f6" stroke-width="2" stroke-dasharray="5,4"/>
      <!-- Data scatter points -->
      <circle cx="85" cy="42" r="5" fill="#2563eb" opacity="0.85"/>
      <circle cx="110" cy="58" r="5" fill="#2563eb" opacity="0.85"/>
      <circle cx="135" cy="74" r="5" fill="#2563eb" opacity="0.85"/>
      <circle cx="160" cy="88" r="5" fill="#10b981" opacity="0.85"/>
      <circle cx="190" cy="95" r="5" fill="#10b981" opacity="0.85"/>
      <circle cx="220" cy="112" r="5" fill="#10b981" opacity="0.85"/>
      <circle cx="260" cy="128" r="5" fill="#f59e0b" opacity="0.85"/>
      <circle cx="305" cy="145" r="5" fill="#f59e0b" opacity="0.85"/>
      <circle cx="355" cy="168" r="5" fill="#ef4444" opacity="0.85"/>
      <circle cx="395" cy="180" r="5" fill="#ef4444" opacity="0.85"/>
      <!-- Axis labels -->
      <text x="240" y="230" font-size="11" text-anchor="middle" fill="#475569">Gross Horsepower (hp)</text>
      <text x="15" y="110" font-size="11" text-anchor="middle" fill="#475569" transform="rotate(-90 15,110)">MPG</text>
    </svg>
  </div>
</body>
</html>""";
            plots_webview.load_html (svg_html, null);
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
            string html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    margin: 0;
    padding: 16px;
    background: #ffffff;
    font-family: system-ui, sans-serif;
    color: #1e293b;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .plot-card {
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 14px;
    background: #f8fafc;
    width: 94%%;
    max-width: 650px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.06);
    text-align: center;
  }
  .plot-img {
    max-width: 100%%;
    height: auto;
    border-radius: 6px;
    border: 1px solid #cbd5e1;
  }
  .plot-title {
    font-size: 13px;
    font-weight: 700;
    margin-top: 10px;
    color: #0f172a;
  }
  .plot-sub {
    font-size: 11px;
    color: #64748b;
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
</html>""".printf (uri, fname);
            plots_webview.load_html (html, null);
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
                current_browser_dir = Services.PersistentSessionManager.get_default ().current_working_dir;
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
                    current_browser_dir = Services.PersistentSessionManager.get_default ().current_working_dir;
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

            var web = WebViewFactory.create ();
            string uri;
            try {
                uri = GLib.Filename.to_uri (plot_file);
            } catch (GLib.Error e) {
                uri = "file://" + plot_file;
            }
            string html = """<!DOCTYPE html><html><body style="margin:0;padding:16px;background:#1e1e2e;display:flex;justify-content:center;align-items:center;min-height:90vh;"><img src="%s" style="max-width:100%%;max-height:90vh;border-radius:8px;box-shadow:0 4px 12px rgba(0,0,0,0.3);" /></body></html>""".printf (uri);
            web.load_html (html, null);

            toolbar_view.set_content (web);
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
                        string target = GLib.Path.build_filename (current_browser_dir, folder_name);
                        GLib.DirUtils.create_with_parents (target, 0755);
                        populate_files_browser ();
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
                        string target = GLib.Path.build_filename (current_browser_dir, fname);
                        try {
                            GLib.FileUtils.set_contents (target, "");
                            populate_files_browser ();
                            if (main_window != null) main_window.open_file_from_path.begin (target);
                        } catch (GLib.Error e) {}
                    }
                }
            });
            if (main_window != null) dialog.present (main_window);
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
                        f.delete (null);
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
                Services.PersistentSessionManager.get_default ().set_working_directory (current_browser_dir);
                if (main_window != null) main_window.show_toast (@"Working directory set to: $(GLib.Path.get_basename (current_browser_dir))");
            });
            vbox.append (btn_swd);

            var btn_gwd = new Gtk.Button.with_label ("Go To Working Directory");
            btn_gwd.add_css_class ("flat");
            btn_gwd.clicked.connect (() => {
                pop.popdown ();
                current_browser_dir = Services.PersistentSessionManager.get_default ().current_working_dir;
                populate_files_browser ();
            });
            vbox.append (btn_gwd);

            var btn_ot = new Gtk.Button.with_label ("Open in Terminal");
            btn_ot.add_css_class ("flat");
            btn_ot.clicked.connect (() => {
                pop.popdown ();
                run_shell_command (@"cd \"$current_browser_dir\"");
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
                    doc_page.source_buffer.insert_at_cursor (cmd + "\n", -1);
                    doc_page.source_view.grab_focus ();
                }
            }
        }

        private void save_history_dialog () {
            string cwd = Services.PersistentSessionManager.get_default ().current_working_dir;
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
  res <- apply(pkgs, 1, function(p) {
    paste(p["Package"], p["Version"], gsub("[\r\n\t]+", " ", p["Title"]), sep="\t")
  })
  cat("___IMLADRIS_PKGS_START___\n")
  cat(res, sep="\n")
  cat("___IMLADRIS_PKGS_END___\n")
})
""";
            string? plot_out = null;
            string out_str = yield Services.PersistentSessionManager.get_default ().execute_r (r_probe, out plot_out);

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

            // Fallback to essential tidyverse & scientific packages
            if (installed_packages.size == 0) {
                installed_packages.add (new PackageItem ("base", "4.4.1", "The R Base Package", true));
                installed_packages.add (new PackageItem ("datasets", "4.4.1", "The R Datasets Package", true));
                installed_packages.add (new PackageItem ("graphics", "4.4.1", "The R Graphics Package", true));
                installed_packages.add (new PackageItem ("ggplot2", "3.5.1", "Create Elegant Data Visualisations", false));
                installed_packages.add (new PackageItem ("dplyr", "1.1.4", "A Grammar of Data Manipulation", false));
                installed_packages.add (new PackageItem ("tidyr", "1.3.1", "Tidy Messy Data", false));
                installed_packages.add (new PackageItem ("readr", "2.1.5", "Read Rectangular Text Data", false));
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

            string query = packages_search_entry != null ? packages_search_entry.text.strip ().down () : "";
            foreach (var pkg in installed_packages) {
                if (query.length > 0 && !pkg.name.down ().contains (query) && !pkg.description.down ().contains (query)) {
                    continue;
                }

                var row = new Adw.ActionRow () {
                    title = pkg.name,
                    subtitle = pkg.description.length > 0 ? pkg.description : "Installed R Package"
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
            string home_html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body { font-family: system-ui, -apple-system, sans-serif; padding: 20px; color: #1e293b; line-height: 1.5; font-size: 13px; background: #ffffff; }
  h2 { color: #1d4ed8; margin-top: 0; font-size: 18px; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px; }
  h3 { color: #334155; margin-bottom: 6px; margin-top: 18px; font-size: 14px; }
  code { background: #f1f5f9; padding: 2px 5px; border-radius: 4px; font-family: monospace; font-size: 12px; }
  ul { padding-left: 20px; }
  li { margin-bottom: 4px; }
  .tip-box { background: #eff6ff; border-left: 4px solid #3b82f6; padding: 10px 14px; border-radius: 4px; margin: 12px 0; }
</style>
</head>
<body>
  <h2>Imladris & RStudio Workbench Documentation</h2>
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
    <li><strong>Quadrant 1 (Top-Left):</strong> Source Editor & Data Viewer (<code>View(df)</code>).</li>
    <li><strong>Quadrant 2 (Bottom-Left):</strong> Interactive Console, Shell Terminal, Elrond AI.</li>
    <li><strong>Quadrant 3 (Top-Right):</strong> Environment Inspector, History, Document Outline, Citations.</li>
    <li><strong>Quadrant 4 (Bottom-Right):</strong> Files Browser, Plots Gallery, Packages Manager, Help & Reference, Web Preview.</li>
  </ul>
</body>
</html>""";
            help_view.load_html (home_html, null);
        }

        public async void show_help_for_topic (string topic) {
            string sanitized = topic.replace ("\"", "").replace ("'", "").strip ();
            if (sanitized.length == 0) return;

            string r_probe = """
local({
  h <- help("%s")
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
""".printf (sanitized);

            string? plot_out = null;
            string out_str = yield Services.PersistentSessionManager.get_default ().execute_r (r_probe, out plot_out);

            if (out_str.contains ("___IMLADRIS_HELP_START___")) {
                int s = out_str.index_of ("___IMLADRIS_HELP_START___") + "___IMLADRIS_HELP_START___".length;
                int e = out_str.index_of ("___IMLADRIS_HELP_END___");
                if (e > s) {
                    string html = out_str.substring (s, e - s).strip ();
                    string styled_html = inject_help_styling (html);
                    help_view.load_html (styled_html, null);
                    activate_panel_in_dock (PanelId.HELP);
                    return;
                }
            }

            render_help_fallback (sanitized);
            activate_panel_in_dock (PanelId.HELP);
        }

        private string inject_help_styling (string raw_html) {
            string style = """<style>
body { font-family: system-ui, sans-serif; padding: 16px 20px; line-height: 1.5; font-size: 13px; color: #1e293b; background: #ffffff; }
h2 { color: #1d4ed8; border-bottom: 1px solid #e2e8f0; padding-bottom: 6px; }
h3 { color: #334155; margin-top: 14px; }
pre, code { font-family: monospace; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 4px; padding: 2px 4px; font-size: 12px; }
pre { padding: 10px; overflow-x: auto; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; }
th, td { border: 1px solid #cbd5e1; padding: 6px 10px; text-align: left; }
th { background: #f1f5f9; }
</style>""";
            if (raw_html.contains ("<head>")) {
                return raw_html.replace ("<head>", "<head>" + style);
            }
            return style + raw_html;
        }

        private void render_help_fallback (string topic) {
            string html = """<!DOCTYPE html><html><body style="font-family:system-ui,sans-serif;padding:24px;color:#334155;text-align:center;">
<h3 style="color:#64748b;">No documentation found for <code>%s</code></h3>
<p style="font-size:12px;color:#94a3b8;">Ensure R is running and package is loaded via <code>library(...)</code>.</p>
</body></html>""".printf (topic);
            help_view.load_html (html, null);
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
    }
}
