// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris {

    public class Window : Adw.ApplicationWindow, Imladris.Plugins.PluginHostWindow, McpHost {

        private Gtk.Stack ribbon_stack;
        private Gtk.ScrolledWindow ribbon_scroller;
        private Gtk.ToggleButton? btn_collapse_ribbon = null;
        private Adw.TabView tab_view;
        private Adw.TabBar tab_bar;
        private Gtk.Box status_bar;
        private Gtk.Stack content_stack;
        private Adw.StatusPage welcome_page;
        private Gtk.Label status_badge_lbl;
        private Gtk.Label status_env_badge_lbl;
        private Gtk.Label status_words_lbl;
        private Gtk.Label status_kernel_lbl;
        private Gtk.MenuButton zoom_btn;
        private int current_zoom = 100;

        private Adw.ToastOverlay toast_overlay;
        private Gtk.ToggleButton? tab_btn_home = null;
        private Gtk.ToggleButton? tab_btn_run = null;
        private Gtk.ToggleButton? tab_btn_publish = null;
        private Gtk.ToggleButton? tab_btn_packages = null;
        private Gtk.Box? ribbon_tabs_box = null;
        private Gtk.Box? tier3_box = null;
        private Gtk.Button? btn_render_quarto = null;
        private Adw.ButtonContent? render_content = null;
        private Gtk.MenuButton? sci_tools_btn = null;
        private UI.PackagesRibbonBar? packages_ribbon_bar = null;
        private Gtk.Label elrond_telemetry_label;

        public string current_project_dir { get; private set; default = ""; }
        public ProjectType current_project_type { get; private set; default = ProjectType.STANDARD; }

        // Ribbon buttons tracked for Context-Aware State Machine (Pillar 2)
        private Gtk.Widget? btn_insert_r = null;
        private Gtk.Widget? btn_insert_py = null;
        private Gtk.Widget? btn_run_chunk = null;
        private Gtk.Widget? btn_run_all = null;
        private Gtk.Widget? btn_run_above = null;
        private Gtk.Widget? btn_run_below = null;
        private Gtk.Widget? btn_run_line = null;
        private Gtk.Widget? btn_source_file = null;
        private Gtk.Widget? btn_interrupt = null;
        private Gtk.Widget? btn_restart_kernel = null;
        private Gtk.Widget? btn_package_installer = null;
        private Gtk.Widget? btn_snapshot_env = null;
        private Gtk.Widget? btn_restore_env = null;
        private Gtk.Widget? btn_render_html = null;
        private Gtk.Widget? btn_render_pdf = null;
        private Gtk.Button? btn_shiny_app = null;
        private Adw.ButtonContent? shiny_app_content = null;
        private Gtk.Widget? btn_export_odt = null;
        private Gtk.Widget? btn_export_odp = null;
        private Gtk.Widget? btn_export_rtf = null;
        private Gtk.DropDown? export_format_selector = null;
        private Gtk.Widget? btn_export_mallorn = null;
        private Gtk.Widget? btn_export_rstudio = null;
        private Gtk.Widget? btn_export_jupyter = null;
        private Gtk.Widget? btn_live_preview = null;
        private Gtk.ToggleButton? btn_preview = null;
        private Gtk.CheckButton? chk_console = null;
        private Gtk.ToggleButton? btn_mode_apostrophe = null;
        private Gtk.ToggleButton? btn_mode_rstudio = null;
        private Gtk.ToggleButton? btn_topo_quad = null;
        private Gtk.ToggleButton? btn_topo_quad6 = null;
        private Gtk.ToggleButton? btn_topo_left_tall = null;
        private Gtk.ToggleButton? btn_topo_right_tall = null;
        private Gtk.Widget? view_rstudio_group = null;
        private Gtk.Widget? view_rstudio_sep = null;
        private Gtk.Widget? view_focus_split_group = null;
        private Gtk.Widget? view_focus_split_sep = null;
        private Gtk.Button? web_sync_status_btn = null;
        private Gtk.Button? cytoscape_status_btn = null;
        private ulong cyrest_conn_hid = 0;
        private bool syncing_ui_toggles = false;

        // Plugin Extension Ribbon Tracking
        private Gtk.Box? extensions_ribbon_box = null;
        private Gtk.Separator? ext_separator = null;
        private Gee.HashMap<string, Gtk.Widget> plugin_ribbon_buttons = new Gee.HashMap<string, Gtk.Widget> ();

        private UI.PackageIndexCache pkg_index_cache = new UI.PackageIndexCache ();
        private ulong theme_changed_hid = 0;
        private ulong physics_changed_hid = 0;
        private ulong ui_settings_hid = 0;
        private ulong shiny_status_hid = 0;
        private ulong elrond_telemetry_hid = 0;
        private ulong elrond_toast_hid = 0;
        private ulong ws_layout_hid = 0;
        private ulong ws_split_hid = 0;
        private ulong pm_btn_added_hid = 0;
        private ulong pm_btn_removed_hid = 0;
        private ulong pm_toast_hid = 0;
        private ulong web_sync_link_hid = 0;
        private ulong web_sync_toast_hid = 0;
        private ulong web_sync_conn_hid = 0;
        private static Regex? zotero_cite_regex = null;
        private static Regex? pandoc_part_regex = null;

        private bool force_window_close = false;

        public Window (Adw.Application app) {
            Object (
                application: app,
                title: "Imladris — Polyglot Scientific & Web Studio",
                default_width: 1200,
                default_height: 760
            );
        }

        construct {
            setup_actions ();

            var settings = Core.SettingsManager.get_default ();
            if (settings.app_theme == Core.AppTheme.EYE_FRIENDLY) {
                this.add_css_class ("eye-friendly");
            }
            theme_changed_hid = settings.theme_changed.connect ((theme) => {
                if (theme == Core.AppTheme.EYE_FRIENDLY) {
                    this.add_css_class ("eye-friendly");
                } else {
                    this.remove_css_class ("eye-friendly");
                }
            });

            this.close_request.connect (() => {
                if (!force_window_close && tab_view != null) {
                    int unsaved_count = 0;
                    for (int i = 0; i < tab_view.n_pages; i++) {
                        var page = tab_view.get_nth_page (i);
                        var doc = page.child as DocumentPage;
                        if (doc != null && doc.source_buffer != null && doc.source_buffer.get_modified ()) {
                            unsaved_count++;
                        }
                    }
                    if (unsaved_count > 0) {
                        var dlg = new Adw.AlertDialog (
                            "Unsaved Changes",
                            @"$(unsaved_count) open document(s) have unsaved changes. Discard unsaved changes and close?"
                        );
                        dlg.add_response ("cancel", "Cancel");
                        dlg.add_response ("discard", "Discard & Close");
                        dlg.set_default_response ("cancel");
                        dlg.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
                        dlg.response.connect ((resp) => {
                            if (resp == "discard") {
                                force_window_close = true;
                                this.close ();
                            }
                        });
                        dlg.present (this);
                        return true;
                    }
                }
                if (theme_changed_hid != 0) {
                    Core.SettingsManager.get_default ().disconnect (theme_changed_hid);
                    theme_changed_hid = 0;
                }
                if (physics_changed_hid != 0) {
                    Core.SettingsManager.get_default ().disconnect (physics_changed_hid);
                    physics_changed_hid = 0;
                }
                if (ui_settings_hid != 0) {
                    Core.SettingsManager.get_default ().disconnect (ui_settings_hid);
                    ui_settings_hid = 0;
                }
                if (shiny_status_hid != 0) {
                    Services.ShinyService.get_default ().disconnect (shiny_status_hid);
                    shiny_status_hid = 0;
                }
                if (elrond_telemetry_hid != 0) {
                    Imladris.AI.ElrondEngineController.get_default ().disconnect (elrond_telemetry_hid);
                    elrond_telemetry_hid = 0;
                }
                if (elrond_toast_hid != 0) {
                    Imladris.AI.ElrondEngineController.get_default ().disconnect (elrond_toast_hid);
                    elrond_toast_hid = 0;
                }
                if (ws_layout_hid != 0) {
                    Services.WorkspaceStateManager.get_default ().disconnect (ws_layout_hid);
                    ws_layout_hid = 0;
                }
                if (ws_split_hid != 0) {
                    Services.WorkspaceStateManager.get_default ().disconnect (ws_split_hid);
                    ws_split_hid = 0;
                }
                var pm_cleanup = Imladris.Plugins.PluginManager.get_default ();
                if (pm_btn_added_hid != 0) {
                    pm_cleanup.disconnect (pm_btn_added_hid);
                    pm_btn_added_hid = 0;
                }
                if (pm_btn_removed_hid != 0) {
                    pm_cleanup.disconnect (pm_btn_removed_hid);
                    pm_btn_removed_hid = 0;
                }
                if (pm_toast_hid != 0) {
                    pm_cleanup.disconnect (pm_toast_hid);
                    pm_toast_hid = 0;
                }
                var ws_svc_cleanup = Services.WebSyncService.get_default ();
                if (web_sync_link_hid != 0) {
                    ws_svc_cleanup.disconnect (web_sync_link_hid);
                    web_sync_link_hid = 0;
                }
                if (web_sync_toast_hid != 0) {
                    ws_svc_cleanup.disconnect (web_sync_toast_hid);
                    web_sync_toast_hid = 0;
                }
                if (web_sync_conn_hid != 0) {
                    ws_svc_cleanup.disconnect (web_sync_conn_hid);
                    web_sync_conn_hid = 0;
                }
                var cy_cleanup = Bridges.Cytoscape.CyRestClient.get_default ();
                cy_cleanup.stop_background_discovery ();
                if (cyrest_conn_hid != 0) {
                    cy_cleanup.disconnect (cyrest_conn_hid);
                    cyrest_conn_hid = 0;
                }
                for (int i = 0; i < tab_view.n_pages; i++) {
                    var page = tab_view.get_nth_page (i);
                    var doc = page.child as DocumentPage;
                    if (doc != null) {
                        doc.cleanup ();
                    }
                }
                Plugins.PluginManager.get_default ().active_window = null;
                return false;
            });

            var toolbar_view = new Adw.ToolbarView ();
            this.set_content (toolbar_view);

            var top_master_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            toolbar_view.add_top_bar (top_master_box);

            // =================================================================
            // TIER 1: ADW HEADER BAR & CATEGORY SWITCHER
            // =================================================================
            var header_bar = new Adw.HeaderBar () {
                show_title = true
            };
            header_bar.add_css_class ("imladris-topbar");

            // Structured Primary Menu with submenus per GNOME HIG
            var brand_menu = new GLib.Menu ();
            var new_submenu = new GLib.Menu ();
            new_submenu.append ("New Project or Document...", "app.new_project_modal");
            new_submenu.append ("New RStudio Project (.Rproj)...", "app.new_rproj");
            new_submenu.append ("Quarto Document (.qmd)", "app.new_qmd");
            new_submenu.append ("R Markdown (.Rmd)", "app.new_rmd");
            new_submenu.append ("Jupyter Notebook (.ipynb)", "app.new_ipynb");
            new_submenu.append ("Simple Markdown (.md)", "app.new_md");
            new_submenu.append ("Rich Text Document (.rtf)", "app.new_rtf");
            new_submenu.append ("LaTeX Document (.tex)", "app.new_tex");
            new_submenu.append ("LaTeX Publisher Template...", "app.new_tex_template");
            new_submenu.append ("Deck or Poster Template...", "app.new_presentation");
            new_submenu.append ("TypeScript File (.ts)", "app.new_ts");
            new_submenu.append ("HTML5 + CSS + LaTeX (.html)", "app.new_html");
            new_submenu.append ("R Script (.R)", "app.new_r");
            new_submenu.append ("Shiny Web App (.R)", "app.new_shiny");
            new_submenu.append ("Python Script (.py)", "app.new_py");
            new_submenu.append ("CSS Stylesheet (.css)", "app.new_css");
            new_submenu.append ("BibTeX Bibliography (.bib)", "app.new_bib");

            var export_submenu = new GLib.Menu ();
            export_submenu.append ("Render to HTML", "app.export_html");
            export_submenu.append ("Render to PDF", "app.export_pdf");
            export_submenu.append ("OpenDocument Text (.odt)", "app.export_odt");
            export_submenu.append ("OpenDocument Presentation (.odp)", "app.export_odp");
            export_submenu.append ("Rich Text Format (.rtf)", "app.export_rtf");
            export_submenu.append ("Portable .mallorn Archive", "app.export_mallorn");
            export_submenu.append ("Export for RStudio", "app.export_rstudio");
            export_submenu.append ("Export for Jupyter", "app.export_jupyter");

            var file_sec = new GLib.Menu ();
            file_sec.append_submenu ("New", new_submenu);
            file_sec.append ("Open...", "app.open");
            file_sec.append ("Save", "app.save");
            file_sec.append_submenu ("Export", export_submenu);
            brand_menu.append_section (null, file_sec);

            var tools_sec = new GLib.Menu ();
            tools_sec.append ("Command Palette...", "app.command_palette");
            tools_sec.append ("Visual Flow & Mindmap Studio...", "app.mermaid_studio");
            tools_sec.append ("Math & Chemical Reaction Studio...", "app.math_chem_editor");
            tools_sec.append ("Data Science Toolchains...", "app.toolchain_setup");
            brand_menu.append_section (null, tools_sec);

            var app_sec = new GLib.Menu ();
            app_sec.append ("Preferences", "app.preferences");
            app_sec.append ("Keyboard Shortcuts", "app.shortcuts");
            app_sec.append ("Feature Tour...", "app.show_tour");
            app_sec.append ("About Imladris", "app.about");
            app_sec.append ("Quit", "app.quit");
            brand_menu.append_section (null, app_sec);

            var brand_btn = new Gtk.MenuButton () {
                menu_model = brand_menu,
                icon_name = "open-menu-symbolic",
                tooltip_text = "Main Menu",
                primary = true,
                valign = Gtk.Align.CENTER
            };
            header_bar.pack_start (brand_btn);

            ribbon_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                transition_duration = Core.SettingsManager.get_default ().animation_physics.get_stack_duration_ms ()
            };

            ribbon_tabs_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) {
                valign = Gtk.Align.CENTER
            };
            ribbon_tabs_box.add_css_class ("linked");

            string[] categories = {
                "Home", "Insert", "Run", "Publish", "View", "Packages"
            };

            Gtk.ToggleButton? first_tab = null;
            foreach (string cat in categories) {
                var tab_btn = new Gtk.ToggleButton.with_label (cat);
                tab_btn.add_css_class ("ribbon-tab-btn");
                if (cat == "Home") tab_btn_home = tab_btn;
                if (cat == "Run") {
                    tab_btn_run = tab_btn;
                }
                if (cat == "Publish") {
                    tab_btn_publish = tab_btn;
                }
                if (cat == "Packages") {
                    tab_btn.add_css_class ("ribbon-tab-packages");
                    tab_btn_packages = tab_btn;
                }

                if (first_tab == null) {
                    first_tab = tab_btn;
                    tab_btn.active = true;
                } else {
                    tab_btn.set_group (first_tab);
                }

                string target_cat = cat;
                tab_btn.toggled.connect (() => {
                    if (tab_btn.active) {
                        ribbon_stack.visible_child_name = target_cat;
                    }
                });

                ribbon_tabs_box.append (tab_btn);
            }
            header_bar.set_title_widget (ribbon_tabs_box);

            var export_formats = new Gtk.StringList ({
                "Manuscript (HTML)",
                "Article / Report (PDF)",
                "Interactive Slides (RevealJS)",
                "Conference Slides (Beamer PDF)",
                "Symposium Poster (Typst/PDF)"
            });
            export_format_selector = new Gtk.DropDown (export_formats, null) {
                valign = Gtk.Align.CENTER,
                tooltip_text = "Select Scientific Output Format"
            };
            export_format_selector.add_css_class ("flat");

            btn_render_quarto = new Gtk.Button () {
                tooltip_text = "Compile Scientific Document / Deck / Poster (Ctrl+Shift+K)",
                valign = Gtk.Align.CENTER
            };
            btn_render_quarto.add_css_class ("suggested-action");
            render_content = new Adw.ButtonContent () {
                icon_name = "media-playback-start-symbolic",
                label = "Render"
            };
            btn_render_quarto.set_child (render_content);
            btn_render_quarto.clicked.connect (() => {
                trigger_selected_scientific_render ();
            });

            btn_shiny_app = new Gtk.Button () {
                tooltip_text = "Run Shiny Web Application (Ctrl+Shift+A)",
                valign = Gtk.Align.CENTER
            };
            shiny_app_content = new Adw.ButtonContent () {
                icon_name = "media-playback-start-symbolic",
                label = "Run App"
            };
            btn_shiny_app.set_child (shiny_app_content);
            btn_shiny_app.clicked.connect (() => {
                toggle_shiny_app_execution ();
            });

            var shiny_svc = Services.ShinyService.get_default ();
            shiny_status_hid = shiny_svc.status_changed.connect ((st) => {
                if (btn_shiny_app != null && shiny_app_content != null) {
                    if (st == Services.ShinyAppStatus.RUNNING || st == Services.ShinyAppStatus.STARTING) {
                        btn_shiny_app.remove_css_class ("suggested-action");
                        btn_shiny_app.add_css_class ("destructive-action");
                        shiny_app_content.icon_name = "process-stop-symbolic";
                        shiny_app_content.label = "Stop";
                    } else {
                        btn_shiny_app.remove_css_class ("destructive-action");
                        shiny_app_content.icon_name = "media-playback-start-symbolic";
                        shiny_app_content.label = "Run App";
                    }
                }
            });

            // Consolidated Scientific Tools Popover (Cite, Deck/Poster, Yavanna, Taniquetil, Elbereth)
            var sci_popover = new Gtk.Popover ();
            var sci_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE
            };
            sci_list.add_css_class ("boxed-list");

            var row_cite = new Adw.ActionRow () {
                title = "Insert Citation (Zotero)",
                subtitle = "Ctrl+Shift+I",
                activatable = true
            };
            row_cite.add_prefix (new Gtk.Image.from_icon_name ("accessories-dictionary-symbolic"));
            row_cite.activated.connect (() => {
                sci_popover.popdown ();
                open_zotero_picker ();
            });
            sci_list.append (row_cite);

            var row_doi_bib = new Adw.ActionRow () {
                use_markup = false,
                title = "DOI & .bib Bibliography Manager",
                subtitle = "Ctrl+Shift+B",
                activatable = true
            };
            row_doi_bib.add_prefix (new Gtk.Image.from_icon_name ("document-edit-symbolic"));
            row_doi_bib.activated.connect (() => {
                sci_popover.popdown ();
                open_doi_bib_manager ();
            });
            sci_list.append (row_doi_bib);

            var row_deck = new Adw.ActionRow () {
                title = "New Deck or Poster Template...",
                subtitle = "Beamer (LaTeX), Marp/RevealJS (Markdown), TypeScript, or Typst",
                activatable = true
            };
            row_deck.add_prefix (new Gtk.Image.from_icon_name ("x-office-presentation-symbolic"));
            row_deck.activated.connect (() => {
                sci_popover.popdown ();
                show_presentation_template_dialog ();
            });
            sci_list.append (row_deck);

            var row_latex_tpl = new Adw.ActionRow () {
                title = "New LaTeX Publisher Template...",
                subtitle = "10 journal templates (IEEE, ACM, Nature...) & 10 citation styles",
                use_markup = false,
                activatable = true
            };
            row_latex_tpl.add_prefix (new Gtk.Image.from_icon_name ("x-office-document-symbolic"));
            row_latex_tpl.activated.connect (() => {
                sci_popover.popdown ();
                show_latex_template_dialog ();
            });
            sci_list.append (row_latex_tpl);

            var yavanna_popover = new Imladris.Bridges.Yavanna.BioEntityPopover ();
            yavanna_popover.insert_snippet_requested.connect ((snippet) => {
                insert_in_active_editor (snippet);
                show_toast ("Inserted biological provenance record into document");
            });
            var btn_yavanna_inline = new Gtk.MenuButton () {
                child = new Adw.ButtonContent () {
                    icon_name = "applications-science-symbolic",
                    label = "Gene & Primer Lookup (Yavanna)"
                },
                popover = yavanna_popover,
                hexpand = true
            };
            btn_yavanna_inline.add_css_class ("flat");

            var taniquetil_popover = new Imladris.Bridges.Taniquetil.AlphaFoldBridgePopover ();
            taniquetil_popover.insert_snippet_requested.connect ((snippet) => {
                insert_in_active_editor (snippet);
                show_toast ("Inserted AlphaFold structural provenance record");
            });
            var btn_taniquetil_inline = new Gtk.MenuButton () {
                child = new Adw.ButtonContent () {
                    icon_name = "network-cellular-symbolic",
                    label = "Protein 3D Structure (AlphaFold)"
                },
                popover = taniquetil_popover,
                hexpand = true
            };
            btn_taniquetil_inline.add_css_class ("flat");

            var elbereth_popover = new Imladris.Bridges.Elbereth.ClinicalBiostatsPopover ();
            elbereth_popover.insert_snippet_requested.connect ((snippet) => {
                insert_in_active_editor (snippet);
                show_toast ("Inserted clinical biostatistics record into document");
            });
            var btn_elbereth_inline = new Gtk.MenuButton () {
                child = new Adw.ButtonContent () {
                    icon_name = "view-statistics-symbolic",
                    label = "Biostats & Power Calc (Elbereth)"
                },
                popover = elbereth_popover,
                hexpand = true
            };
            btn_elbereth_inline.add_css_class ("flat");

            var sci_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8,
                width_request = 270
            };
            sci_box.append (sci_list);
            sci_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            sci_box.append (btn_yavanna_inline);
            sci_box.append (btn_taniquetil_inline);
            sci_box.append (btn_elbereth_inline);

            var btn_qual_inline = new Gtk.Button () {
                child = new Adw.ButtonContent () {
                    icon_name = "view-list-bullet-symbolic",
                    label = "Qualitative & Cytoscape Studio"
                },
                hexpand = true
            };
            btn_qual_inline.add_css_class ("flat");
            btn_qual_inline.clicked.connect (() => {
                sci_popover.popdown ();
                open_qualitative_studio ();
            });
            sci_box.append (btn_qual_inline);

            var btn_help_hub_inline = new Gtk.Button () {
                child = new Adw.ButtonContent () {
                    icon_name = "help-browser-symbolic",
                    label = "Help & Manuals Hub (F1)"
                },
                hexpand = true
            };
            btn_help_hub_inline.add_css_class ("flat");
            btn_help_hub_inline.clicked.connect (() => {
                sci_popover.popdown ();
                open_help_hub ();
            });
            sci_box.append (btn_help_hub_inline);
            sci_popover.set_child (sci_box);

            sci_tools_btn = new Gtk.MenuButton () {
                icon_name = "applications-science-symbolic",
                tooltip_text = "Scientific Tools, Citations & Templates",
                valign = Gtk.Align.CENTER,
                popover = sci_popover
            };
            sci_tools_btn.add_css_class ("flat");

            btn_collapse_ribbon = new Gtk.ToggleButton () {
                icon_name = "ribbon-toggle-symbolic",
                tooltip_text = "Show / Hide Ribbon Toolbar (Ctrl+F1)",
                valign = Gtk.Align.CENTER,
                active = Core.SettingsManager.get_default ().show_ribbon_toolbar
            };
            btn_collapse_ribbon.add_css_class ("flat");
            btn_collapse_ribbon.toggled.connect (() => {
                bool show = btn_collapse_ribbon.active;
                if (tab_view != null && tab_view.n_pages > 0) {
                    ribbon_scroller.visible = show;
                }
                Core.SettingsManager.get_default ().show_ribbon_toolbar = show;
            });

            header_bar.pack_end (btn_collapse_ribbon);
            header_bar.pack_end (sci_tools_btn);
            header_bar.pack_end (btn_shiny_app);
            header_bar.pack_end (btn_render_quarto);
            header_bar.pack_end (export_format_selector);

            top_master_box.append (header_bar);

            // =================================================================
            // TIER 2: DYNAMIC MODERN RIBBON DECK (5 High-Density Tabs)
            // =================================================================
            ribbon_scroller = new Gtk.ScrolledWindow () {
                vscrollbar_policy = Gtk.PolicyType.NEVER,
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC
            };
            ribbon_scroller.add_css_class ("ribbon-deck");
            ribbon_scroller.set_child (ribbon_stack);
            top_master_box.append (ribbon_scroller);

            packages_ribbon_bar = new UI.PackagesRibbonBar (pkg_index_cache);
            ribbon_stack.add_named (build_home_ribbon (), "Home");
            ribbon_stack.add_named (build_insert_ribbon (), "Insert");
            ribbon_stack.add_named (build_computation_ribbon (), "Run");
            ribbon_stack.add_named (build_publish_ribbon (), "Publish");
            ribbon_stack.add_named (build_view_ribbon (), "View");
            ribbon_stack.add_named (packages_ribbon_bar, "Packages");

            packages_ribbon_bar.dispatch_r_install.connect ((r_cmd, label) => {
                run_r_install_and_snapshot.begin (r_cmd, label);
            });

            packages_ribbon_bar.dispatch_python_install.connect ((argv, working_dir, sandboxed, label) => {
                string py_bin = argv.length > 0 ? argv[0] : "python3";
                run_python_pip_and_snapshot.begin (py_bin, argv, working_dir, sandboxed, label);
            });
            packages_ribbon_bar.status_changed.connect ((msg) => {
                show_toast (msg);
            });

            // =================================================================
            // TIER 3: STREAMLINED TAB BAR WITH AI & LAYOUT TOGGLES
            // =================================================================
            tier3_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            tier3_box.add_css_class ("imladris-subbar");

            var ai_quick_btn = RibbonFactory.create_compact_button ("system-run-symbolic", "Elrond AI");
            ((Gtk.Button) ai_quick_btn).tooltip_text = "Write with Elrond Assistance (AI) — Ctrl+Shift+E";
            ((Gtk.Button) ai_quick_btn).clicked.connect (() => {
                trigger_elrond_assistance ();
            });
            tier3_box.append (ai_quick_btn);

            var rstudio_toggle_btn = RibbonFactory.create_compact_button ("view-grid-symbolic", "4-Pane / Focus");
            ((Gtk.Button) rstudio_toggle_btn).tooltip_text = "Switch between 4-Pane Studio and distraction-free Focus Mode";
            ((Gtk.Button) rstudio_toggle_btn).clicked.connect (() => {
                var mgr = Services.WorkspaceStateManager.get_default ();
                var next_mode = mgr.active_layout == Services.LayoutMode.RSTUDIO
                    ? Services.LayoutMode.APOSTROPHE
                    : Services.LayoutMode.RSTUDIO;
                mgr.set_layout_mode (next_mode, true);
            });
            tier3_box.append (rstudio_toggle_btn);
            tier3_box.append (RibbonFactory.create_vseparator ());

            tab_view = new Adw.TabView ();
            tab_view.close_page.connect ((page) => {
                var doc = page.child as DocumentPage;
                if (doc != null && doc.source_buffer != null && doc.source_buffer.get_modified ()) {
                    var dlg = new Adw.AlertDialog (
                        "Save Changes Before Closing?",
                        @"\"$(page.title)\" has unsaved changes."
                    );
                    dlg.add_response ("cancel", "Cancel");
                    dlg.add_response ("discard", "Discard");
                    dlg.add_response ("save", "Save");
                    dlg.set_default_response ("save");
                    dlg.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
                    dlg.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
                    dlg.response.connect ((resp) => {
                        if (resp == "discard") {
                            doc.cleanup ();
                            tab_view.close_page_finish (page, true);
                        } else if (resp == "save") {
                            tab_view.set_selected_page (page);
                            save_document_async.begin ((obj, res) => {
                                save_document_async.end (res);
                                if (!doc.source_buffer.get_modified ()) {
                                    doc.cleanup ();
                                    tab_view.close_page_finish (page, true);
                                } else {
                                    tab_view.close_page_finish (page, false);
                                }
                            });
                        } else {
                            tab_view.close_page_finish (page, false);
                        }
                    });
                    dlg.present (this);
                    return true;
                }
                if (doc != null) {
                    doc.cleanup ();
                }
                tab_view.close_page_finish (page, true);
                return true;
            });
            tab_view.page_detached.connect ((page, pos) => {
                var doc = page.child as DocumentPage;
                if (doc != null) {
                    Services.WorkspaceStateManager.get_default ().clear_doc_state (doc.doc_id);
                }
                if (tab_view.n_pages == 0) {
                    set_welcome_chrome (true);
                }
            });
            tab_view.page_attached.connect ((page, pos) => {
                set_welcome_chrome (false);
            });
            tab_bar = new Adw.TabBar () {
                view = tab_view,
                autohide = false,
                expand_tabs = false,
                hexpand = true
            };

            var add_tab_btn = new Gtk.Button.from_icon_name ("list-add-symbolic") {
                tooltip_text = "New Project or Document (Ctrl+N)"
            };
            add_tab_btn.add_css_class ("flat");
            add_tab_btn.clicked.connect (() => {
                show_new_project_modal ();
            });
            tab_bar.set_end_action_widget (add_tab_btn);

            tier3_box.append (tab_bar);
            top_master_box.append (tier3_box);

            // =================================================================
            // BOTTOM STATUS BAR (Live Metrics, Kernel Status & Zoom Slider)
            // =================================================================
            status_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            status_bar.add_css_class ("imladris-statusbar");

            status_badge_lbl = new Gtk.Label ("QUARTO / MD");
            status_badge_lbl.add_css_class ("status-badge");
            status_bar.append (status_badge_lbl);

            status_env_badge_lbl = new Gtk.Label ("Sandboxed • Reproducible");
            status_env_badge_lbl.add_css_class ("status-badge");
            status_env_badge_lbl.add_css_class ("env-sandboxed");
            status_bar.append (status_env_badge_lbl);

            var sm_hw = Core.SettingsManager.get_default ();
            physics_changed_hid = sm_hw.physics_changed.connect (() => {
                ribbon_stack.transition_duration = sm_hw.animation_physics.get_stack_duration_ms ();
                content_stack.transition_duration = sm_hw.animation_physics.get_stack_duration_ms ();
            });

            status_kernel_lbl = new Gtk.Label ("Kernels: R • Python 3") {
                css_classes = { "caption" }
            };
            status_bar.append (status_kernel_lbl);

            status_words_lbl = new Gtk.Label ("Words: 0 | Lines: 1") {
                css_classes = { "caption", "numeric" }
            };
            status_bar.append (status_words_lbl);

            var elrond_sep = new Gtk.Separator (Gtk.Orientation.VERTICAL) {
                margin_start = 6,
                margin_end = 6
            };
            status_bar.append (elrond_sep);

            elrond_telemetry_label = new Gtk.Label ("Elrond AI: Off") {
                valign = Gtk.Align.CENTER
            };
            elrond_telemetry_label.add_css_class ("caption");
            elrond_telemetry_label.add_css_class ("dim-label");
            status_bar.append (elrond_telemetry_label);

            var elrond_ctrl = Imladris.AI.ElrondEngineController.get_default ();
            elrond_telemetry_hid = elrond_ctrl.statusbar_telemetry_updated.connect ((telemetry_text, is_active) => {
                elrond_telemetry_label.label = telemetry_text;
                if (is_active) {
                    elrond_telemetry_label.remove_css_class ("dim-label");
                    elrond_telemetry_label.add_css_class ("accent");
                } else {
                    elrond_telemetry_label.remove_css_class ("accent");
                    elrond_telemetry_label.add_css_class ("dim-label");
                }
            });
            elrond_toast_hid = elrond_ctrl.toast_notification_requested.connect ((msg) => {
                show_toast (msg);
            });

            status_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            cytoscape_status_btn = new Gtk.Button.with_label ("Cytoscape: Offline") {
                tooltip_text = "Bidirectional Cytoscape Desktop Bridge (CyREST localhost:1234) — Click to open Qualitative & Graph Studio",
                valign = Gtk.Align.CENTER
            };
            cytoscape_status_btn.add_css_class ("flat");
            cytoscape_status_btn.add_css_class ("web-sync-pill");
            cytoscape_status_btn.add_css_class ("offline");
            cytoscape_status_btn.clicked.connect (() => {
                Bridges.Cytoscape.CyRestClient.get_default ().probe_health_async.begin ();
                open_qualitative_studio ();
            });
            status_bar.append (cytoscape_status_btn);

            var cy_client = Bridges.Cytoscape.CyRestClient.get_default ();
            cyrest_conn_hid = cy_client.connection_status_changed.connect ((connected, label_txt) => {
                if (cytoscape_status_btn != null) {
                    cytoscape_status_btn.label = label_txt;
                    cytoscape_status_btn.remove_css_class ("synced");
                    cytoscape_status_btn.remove_css_class ("offline");
                    cytoscape_status_btn.add_css_class (connected ? "synced" : "offline");
                }
            });
            cy_client.start_background_discovery (20);

            web_sync_status_btn = new Gtk.Button.with_label ("Imladris Web") {
                tooltip_text = "Imladris on Web Sync & Offline Git-Style Commits (Ctrl+Shift+W)",
                valign = Gtk.Align.CENTER
            };
            web_sync_status_btn.add_css_class ("flat");
            web_sync_status_btn.add_css_class ("web-sync-pill");
            web_sync_status_btn.add_css_class ("offline");
            web_sync_status_btn.clicked.connect (() => {
                open_web_sync_panel ();
            });
            status_bar.append (web_sync_status_btn);

            var web_sync_svc = Services.WebSyncService.get_default ();
            web_sync_link_hid = web_sync_svc.link_updated.connect ((k) => {
                update_web_sync_status_badge ();
            });
            web_sync_toast_hid = web_sync_svc.toast_requested.connect ((msg) => {
                show_toast (msg);
            });
            web_sync_conn_hid = web_sync_svc.connectivity_changed.connect ((avail) => {
                update_web_sync_status_badge ();
            });

            var zoom_pop_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4, margin_bottom = 4, margin_start = 4, margin_end = 4
            };
            zoom_pop_box.add_css_class ("linked");
            var btn_z_out = new Gtk.Button.from_icon_name ("zoom-out-symbolic") { tooltip_text = "Zoom Out (Ctrl+-)" };
            btn_z_out.clicked.connect (() => { apply_zoom (current_zoom - 10); });
            var btn_z_reset = new Gtk.Button.with_label ("100%") { tooltip_text = "Reset Zoom (Ctrl+0)" };
            btn_z_reset.clicked.connect (() => { apply_zoom (100); });
            var btn_z_in = new Gtk.Button.from_icon_name ("zoom-in-symbolic") { tooltip_text = "Zoom In (Ctrl++)" };
            btn_z_in.clicked.connect (() => { apply_zoom (current_zoom + 10); });
            zoom_pop_box.append (btn_z_out);
            zoom_pop_box.append (btn_z_reset);
            zoom_pop_box.append (btn_z_in);
            var zoom_pop = new Gtk.Popover () { child = zoom_pop_box };

            current_zoom = Core.SettingsManager.get_default ().default_zoom_percent;
            zoom_btn = new Gtk.MenuButton () {
                label = @"$current_zoom%",
                popover = zoom_pop,
                tooltip_text = "Editor Zoom",
                valign = Gtk.Align.CENTER
            };
            zoom_btn.add_css_class ("flat");
            zoom_btn.add_css_class ("caption");
            zoom_btn.add_css_class ("numeric");
            status_bar.append (zoom_btn);

            ui_settings_hid = Core.SettingsManager.get_default ().ui_settings_changed.connect (() => {
                var sm_ui = Core.SettingsManager.get_default ();
                if (btn_collapse_ribbon.active != sm_ui.show_ribbon_toolbar) {
                    btn_collapse_ribbon.active = sm_ui.show_ribbon_toolbar;
                }
                if (tab_view.n_pages > 0) {
                    ribbon_scroller.visible = sm_ui.show_ribbon_toolbar;
                    status_bar.visible = sm_ui.show_status_bar;
                }
                apply_zoom (sm_ui.default_zoom_percent);
            });

            toolbar_view.add_bottom_bar (status_bar);

            // =================================================================
            // MAIN WORKSPACE & STATE MACHINE LISTENERS
            // =================================================================
            toast_overlay = new Adw.ToastOverlay ();
            content_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                transition_duration = Core.SettingsManager.get_default ().animation_physics.get_stack_duration_ms ()
            };
            Core.SettingsManager.get_default ().apply_physics ();
            welcome_page = build_welcome_page ();
            content_stack.add_named (welcome_page, "welcome");
            content_stack.add_named (tab_view, "editor");
            set_welcome_chrome (true);

            toast_overlay.set_child (content_stack);
            toolbar_view.set_content (toast_overlay);

            ws_layout_hid = Services.WorkspaceStateManager.get_default ().layout_changed.connect ((mode) => {
                apply_workspace_layout (mode);
                sync_document_ui_toggles (get_active_document ());
            });

            ws_split_hid = Services.WorkspaceStateManager.get_default ().split_changed.connect ((split) => {
                var d = get_active_document ();
                if (d != null) {
                    d.set_split_orientation (split, false);
                }
            });

            tab_view.notify["selected-page"].connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    string fname = d.file_location != null ? d.file_location.get_basename () : (d.initial_title.contains (".") ? d.initial_title : @"untitled.$(d.doc_type)");
                    var wsm = Services.WorkspaceStateManager.get_default ();
                    var doc_layout = wsm.get_layout_for_doc (d.doc_id, fname);
                    if (d.get_workbench_mode () != doc_layout) {
                        d.set_workbench_mode (doc_layout);
                    }
                    var doc_split = wsm.get_split_for_doc (d.doc_id);
                    d.set_split_orientation (doc_split, false);
                    var fmt = d.get_document_format ();
                    update_ribbon_state_machine (fmt, current_project_type);
                    sync_document_ui_toggles (d);
                    if (d.file_location != null && d.file_location.get_parent () != null) {
                        string doc_dir = d.file_location.get_parent ().get_path ();
                        d.panel_registry.get_session_manager ().set_working_directory (
                            doc_dir, current_project_type
                        );
                        Services.PersistentSessionManager.get_default ().set_working_directory (
                            doc_dir, current_project_type
                        );
                    }
                    if (btn_shiny_app != null) {
                        var profile = Core.FormatProfile.for_format (fmt);
                        bool is_shiny = profile.supports_shiny_detection &&
                            Services.ShinyService.get_default ().is_shiny_file (fname, d.get_clean_source_text ());
                        btn_shiny_app.visible = is_shiny || (fmt == DocumentFormat.RSCRIPT);
                    }
                }
            });

            // Launch on Welcome Dashboard; new document tab created only on user action

            var pm = Imladris.Plugins.PluginManager.get_default ();
            pm.active_window = this;
            pm_btn_added_hid = pm.ribbon_button_added.connect (on_plugin_ribbon_button_added);
            pm_btn_removed_hid = pm.ribbon_button_removed.connect (on_plugin_ribbon_button_removed);
            pm_toast_hid = pm.toast_requested.connect ((msg) => {
                this.show_toast (msg);
            });

            this.notify["is-active"].connect (() => {
                if (this.is_active) {
                    Imladris.Plugins.PluginManager.get_default ().active_window = this;
                }
            });

            // Re-sync already loaded plugin buttons
            foreach (var p in pm.plugins.values) {
                if (p.is_enabled) {
                    foreach (var btn_id in p.registered_buttons) {
                        on_plugin_ribbon_button_added (p.manifest.id, btn_id, btn_id, p.manifest.icon);
                    }
                }
            }

            // Check for crash recovery snapshots on launch
            GLib.Idle.add (() => {
                check_and_prompt_recovery ();
                return GLib.Source.REMOVE;
            });
        }

        private void apply_workspace_layout (Services.LayoutMode mode) {
            var doc = get_active_document ();
            ribbon_stack.visible = true;
            if (doc != null) {
                doc.set_workbench_mode (mode);
            }
        }

        private void check_and_prompt_recovery () {
            var recs = Services.RecoveryService.get_default ().check_recoverable_sessions ();
            if (recs.size > 0) {
                var toast = new Adw.Toast (@"Imladris detected $(recs.size) unsaved document(s) from a previous session.") {
                    button_label = "Restore",
                    timeout = 0
                };
                bool restored = false;
                toast.button_clicked.connect (() => {
                    restored = true;
                    foreach (var rec in recs) {
                        string fallback_ext = ".md";
                        switch (rec.doc_type.down ()) {
                            case "r": fallback_ext = ".R"; break;
                            case "python": fallback_ext = ".py"; break;
                            case "quarto":
                            case "qmd": fallback_ext = ".qmd"; break;
                            case "rmarkdown":
                            case "rmd": fallback_ext = ".Rmd"; break;
                            case "ipynb": fallback_ext = ".ipynb"; break;
                            case "latex":
                            case "tex": fallback_ext = ".tex"; break;
                            default: fallback_ext = ".md"; break;
                        }
                        string title = rec.file_path != null ? GLib.Path.get_basename (rec.file_path) : @"Recovered-Document$(fallback_ext)";
                        GLib.File? f = rec.file_path != null ? GLib.File.new_for_path (rec.file_path) : null;
                        add_document_tab (title, rec.doc_type, rec.content, f);
                        var restored_doc = get_active_document ();
                        if (restored_doc != null && restored_doc.source_buffer != null) {
                            restored_doc.source_buffer.set_modified (rec.is_dirty);
                            Gtk.TextIter cur_it;
                            int max_line = int.max (0, restored_doc.source_buffer.get_line_count () - 1);
                            int target_line = rec.cursor_line.clamp (0, max_line);
                            restored_doc.source_buffer.get_iter_at_line_offset (out cur_it, target_line, 0);
                            int line_len = cur_it.get_chars_in_line ();
                            if (rec.cursor_offset > 0 && rec.cursor_offset < line_len) {
                                cur_it.set_line_offset (rec.cursor_offset);
                            }
                            restored_doc.source_buffer.place_cursor (cur_it);
                        }
                    }
                });
                toast.dismissed.connect (() => {
                    if (restored) {
                        foreach (var rec in recs) {
                            Services.RecoveryService.get_default ().purge_document_cache (rec.doc_id);
                        }
                    }
                });
                if (toast_overlay != null) {
                    toast_overlay.add_toast (toast);
                }
                var d = get_active_document ();
                if (d != null) {
                    d.append_console_log (@"⚠ Crash Recovery: $(recs.size) unsaved snapshot(s) found in cache.");
                }
            }
        }

        public DocumentPage? get_active_document () {
            if (tab_view.selected_page == null) return null;
            return tab_view.selected_page.child as DocumentPage;
        }

        public void trigger_ai_assistant () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.show_ai_assistant ();
            }
        }

        public void trigger_elrond_assistance () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.show_ai_assistant ();
            } else {
                trigger_ai_assistant ();
            }
        }

        public string get_active_editor_text () {
            var doc = get_active_document ();
            if (doc != null && doc.source_buffer != null) {
                return doc.get_clean_source_text ();
            }
            return "";
        }

        public string get_active_selected_text () {
            var doc = get_active_document ();
            if (doc != null) {
                return doc.get_selected_text ();
            }
            return "";
        }

        public void insert_in_active_editor (string text) {
            var doc = get_active_document ();
            if (doc == null) {
                add_document_tab ("Analysis.qmd", "markdown");
                doc = get_active_document ();
            }
            if (doc != null) {
                Gtk.TextBuffer buf = (doc.rtf_editor != null) ? doc.rtf_editor.buffer : (Gtk.TextBuffer) doc.source_buffer;
                buf.begin_user_action ();
                buf.insert_at_cursor (text, -1);
                buf.end_user_action ();
            }
        }

        public void ask_elrond (string prompt) {
            var doc = get_active_document ();
            if (doc != null) {
                doc.show_ai_assistant ();
                if (doc.panel_registry != null && doc.panel_registry.elrond_chat_panel != null) {
                    doc.panel_registry.elrond_chat_panel.submit_external_prompt (prompt);
                }
            } else {
                trigger_elrond_assistance ();
            }
        }

        public void append_console_log (string text) {
            var doc = get_active_document ();
            if (doc != null) {
                doc.append_console_log (text);
            }
        }

        public string get_workspace_root () {
            if (current_project_dir != null && current_project_dir != "") {
                return current_project_dir;
            }
            var doc = get_active_document ();
            if (doc != null && doc.file_location != null) {
                var parent = doc.file_location.get_parent ();
                if (parent != null) {
                    return parent.get_path ();
                }
            }
            return GLib.Environment.get_home_dir ();
        }

        public string get_active_file_path () {
            var doc = get_active_document ();
            if (doc != null && doc.file_location != null) {
                return doc.file_location.get_path ();
            }
            return "";
        }

        public string[] list_workspace_files (string pattern) {
            string root = get_workspace_root ();
            var results = new Gee.ArrayList<string> ();
            if (root == "" || !GLib.FileUtils.test (root, GLib.FileTest.IS_DIR)) {
                return new string[0];
            }
            GLib.PatternSpec? spec = null;
            if (pattern.length > 0 && pattern != "*") {
                spec = new GLib.PatternSpec (pattern);
            }
            scan_dir_for_workspace_files (root, root, results, spec);
            string[] arr = new string[results.size];
            for (int i = 0; i < results.size; i++) {
                arr[i] = results[i];
            }
            return arr;
        }

        private void scan_dir_for_workspace_files (string base_dir, string current_dir, Gee.ArrayList<string> results, GLib.PatternSpec? spec) {
            try {
                var dir = GLib.Dir.open (current_dir, 0);
                string? name = null;
                while ((name = dir.read_name ()) != null) {
                    if (name.has_prefix (".") || name == "node_modules" || name == "renv" || name == ".venv" || name == "build" || name == "target") {
                        continue;
                    }
                    string full_path = GLib.Path.build_filename (current_dir, name);
                    if (GLib.FileUtils.test (full_path, GLib.FileTest.IS_DIR)) {
                        scan_dir_for_workspace_files (base_dir, full_path, results, spec);
                    } else {
                        bool matches = false;
                        if (spec != null) {
                            matches = spec.match_string (name);
                        } else {
                            matches = (name.has_suffix (".md") || name.has_suffix (".qmd") || name.has_suffix (".Rmd") || name.has_suffix (".ipynb"));
                        }
                        if (matches) {
                            string rel_path = full_path.substring (base_dir.length);
                            if (rel_path.has_prefix ("/")) {
                                rel_path = rel_path.substring (1);
                            }
                            results.add (rel_path);
                        }
                    }
                }
            } catch (GLib.Error e) {
                debug ("Error scanning directory %s: %s", current_dir, e.message);
            }
        }

        public string read_workspace_file (string relative_path) {
            string root = get_workspace_root ();
            if (root == "" || relative_path.has_prefix ("/") || relative_path.contains ("..")) {
                return "";
            }
            string full_path = GLib.Path.build_filename (root, relative_path);
            if (!GLib.FileUtils.test (full_path, GLib.FileTest.EXISTS)) {
                return "";
            }
            try {
                string contents;
                GLib.FileUtils.get_contents (full_path, out contents);
                return contents;
            } catch (GLib.Error e) {
                return "";
            }
        }

        public void open_workspace_file (string relative_path, int line) {
            string root = get_workspace_root ();
            if (root == "" || relative_path.has_prefix ("/") || relative_path.contains ("..")) {
                return;
            }
            string full_path = GLib.Path.build_filename (root, relative_path);
            if (GLib.FileUtils.test (full_path, GLib.FileTest.EXISTS)) {
                open_file_from_path.begin (full_path);
            }
        }

        public void show_web_dialog (string title, string html_content, int width, int height) {
            var dialog = new Adw.Dialog ();
            dialog.title = title;
            dialog.content_width = width > 0 ? width : 950;
            dialog.content_height = height > 0 ? height : 700;

            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header);

            var webview = UI.WebViewFactory.create ();
            var ucm = webview.get_user_content_manager ();
            ucm.register_script_message_handler ("imladrisHost", (string) (void*) null);
            ucm.script_message_received.connect ((val) => {
                try {
                    string json_str = val.to_json (0);
                    var parser = new Json.Parser ();
                    parser.load_from_data (json_str);
                    var root = parser.get_root ();
                    if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                        var obj = root.get_object ();
                        string action = obj.has_member ("action") ? obj.get_string_member ("action") : "";
                        if (action == "open_file") {
                            string fpath = obj.has_member ("path") ? obj.get_string_member ("path") : "";
                            if (fpath != "") {
                                open_workspace_file (fpath, 1);
                                dialog.close ();
                            }
                        } else if (action == "show_toast") {
                            string msg = obj.has_member ("message") ? obj.get_string_member ("message") : "";
                            show_toast (msg);
                        }
                    }
                } catch (GLib.Error e) {
                    debug ("Error handling webview script message: %s", e.message);
                }
            });

            webview.load_html (html_content, "imladris-plugin://dialog/");
            toolbar_view.set_content (webview);
            dialog.set_child (toolbar_view);
            dialog.present (this);
        }

        private void on_plugin_ribbon_button_added (string plugin_id, string button_id, string label, string icon) {
            if (extensions_ribbon_box == null) return;
            string key = plugin_id + ":" + button_id;
            if (plugin_ribbon_buttons.has_key (key)) return;

            string icon_name = (icon != null && icon.strip () != "") ? icon : "application-x-addon-symbolic";
            var btn = RibbonFactory.create_tool_button (icon_name, label, @"$label ($plugin_id)");
            ((Gtk.Button) btn).clicked.connect (() => {
                Imladris.Plugins.PluginManager.get_default ().trigger_ribbon_button (plugin_id, button_id);
            });
            plugin_ribbon_buttons.set (key, btn);
            extensions_ribbon_box.append (btn);
            if (ext_separator != null) ext_separator.visible = true;
            extensions_ribbon_box.visible = true;
        }

        private void on_plugin_ribbon_button_removed (string plugin_id, string button_id) {
            if (extensions_ribbon_box == null) return;
            string key = plugin_id + ":" + button_id;
            if (plugin_ribbon_buttons.has_key (key)) {
                var btn = plugin_ribbon_buttons.get (key);
                extensions_ribbon_box.remove (btn);
                plugin_ribbon_buttons.unset (key);
            }
            if (plugin_ribbon_buttons.is_empty) {
                if (ext_separator != null) ext_separator.visible = false;
                extensions_ribbon_box.visible = false;
            }
        }

        private void set_welcome_chrome (bool is_welcome) {
            if (is_welcome) {
                content_stack.visible_child_name = "welcome";
                tab_bar.visible = false;
                tier3_box.visible = false;
                ribbon_scroller.visible = false;
                status_bar.visible = false;
                if (ribbon_tabs_box != null) ribbon_tabs_box.visible = false;
                if (export_format_selector != null) export_format_selector.visible = false;
                if (btn_render_quarto != null) btn_render_quarto.visible = false;
                if (btn_shiny_app != null) btn_shiny_app.visible = false;
                if (sci_tools_btn != null) sci_tools_btn.visible = false;
            } else {
                var sm_ui = Core.SettingsManager.get_default ();
                content_stack.visible_child_name = "editor";
                tab_bar.visible = true;
                tier3_box.visible = true;
                ribbon_scroller.visible = sm_ui.show_ribbon_toolbar && btn_collapse_ribbon.active;
                status_bar.visible = sm_ui.show_status_bar;
                if (ribbon_tabs_box != null) ribbon_tabs_box.visible = true;
                if (sci_tools_btn != null) sci_tools_btn.visible = true;
            }
        }

        public void add_document_tab (string title, string lang_id, string? initial_text = null, GLib.File? file = null, string? raw_source = null) {
            var doc_page = new DocumentPage (title, lang_id, this);
            if (file != null) {
                doc_page.file_location = file;
            }
            if (raw_source != null) {
                doc_page.raw_ipynb_source = raw_source;
            }
            if (initial_text != null) {
                doc_page.set_initial_content (initial_text, file != null);
            }
            doc_page.project_type = current_project_type;
            doc_page.stats_changed.connect ((words, lines, badge) => {
                if (get_active_document () == doc_page) {
                    status_badge_lbl.label = badge;
                    status_words_lbl.label = @"Words: $words | Lines: $lines";
                }
            });

            var page = tab_view.append (doc_page);
            page.title = title;
            page.icon = new GLib.ThemedIcon ("x-office-document-symbolic");
            tab_view.selected_page = page;
            doc_page.emit_buffer_stats ();

            var fmt = doc_page.get_document_format ();
            update_ribbon_state_machine (fmt, current_project_type);
        }

        private Adw.StatusPage build_welcome_page () {
            var status = new Adw.StatusPage () {
                icon_name = "io.github.Antux912012.Imladris",
                title = "Welcome to Imladris",
                description = "Write scientific documents with Markdown, R, Quarto, and Jupyter.",
                vexpand = true,
                hexpand = true
            };

            var clamp = new Adw.Clamp () {
                maximum_size = 540,
                tightening_threshold = 400
            };

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);

            var quick_group = new Adw.PreferencesGroup () {
                title = "Quick Start"
            };

            var qmd_row = new Adw.ActionRow () {
                title = "New Analysis Notebook (.qmd)",
                subtitle = "Write prose, math, R, and Python in one live document",
                activatable = true
            };
            qmd_row.add_prefix (new Gtk.Image.from_icon_name ("x-office-document-symbolic"));
            qmd_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            qmd_row.activated.connect (() => {
                add_document_tab ("analysis.qmd", "quarto");
            });
            quick_group.add (qmd_row);

            var md_row = new Adw.ActionRow () {
                title = "New Markdown Document (.md)",
                subtitle = "Clean focused prose with live preview and math/diagram support",
                activatable = true
            };
            md_row.add_prefix (new Gtk.Image.from_icon_name ("document-edit-symbolic"));
            md_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            md_row.activated.connect (() => {
                add_document_tab ("notes.md", "markdown");
            });
            quick_group.add (md_row);

            var rtf_row = new Adw.ActionRow () {
                title = "New Rich Text Document (.rtf)",
                subtitle = "WYSIWYG rich text editor with fonts, styles, colors, and live preview",
                activatable = true
            };
            rtf_row.add_prefix (new Gtk.Image.from_icon_name ("x-office-document-symbolic"));
            rtf_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            rtf_row.activated.connect (() => {
                add_document_tab ("untitled.rtf", "rtf");
            });
            quick_group.add (rtf_row);

            var tex_row = new Adw.ActionRow () {
                title = "New LaTeX Manuscript (.tex)",
                subtitle = "Typeset articles with equations, BibTeX citations, and PDF builds",
                activatable = true
            };
            tex_row.add_prefix (new Gtk.Image.from_icon_name ("x-office-document-symbolic"));
            tex_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            tex_row.activated.connect (() => {
                add_document_tab ("document.tex", "latex");
            });
            quick_group.add (tex_row);

            var tex_tpl_row = new Adw.ActionRow () {
                title = "LaTeX Publisher Templates (IEEE, ACM, Nature...)",
                subtitle = "Choose from 10 scientific journal templates and 10 citation styles",
                activatable = true
            };
            tex_tpl_row.add_prefix (new Gtk.Image.from_icon_name ("document-properties-symbolic"));
            tex_tpl_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            tex_tpl_row.activated.connect (() => {
                show_latex_template_dialog ();
            });
            quick_group.add (tex_tpl_row);

            var deck_tpl_row = new Adw.ActionRow () {
                title = "Decks &amp; Posters (Beamer, RevealJS, Typst)",
                subtitle = "Create conference slides, Marp/RevealJS decks, or symposium posters",
                activatable = true
            };
            deck_tpl_row.add_prefix (new Gtk.Image.from_icon_name ("x-office-presentation-symbolic"));
            deck_tpl_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            deck_tpl_row.activated.connect (() => {
                show_presentation_template_dialog ();
            });
            quick_group.add (deck_tpl_row);

            var shiny_row = new Adw.ActionRow () {
                title = "New R Script or Shiny App (.R)",
                subtitle = "Run statistical models or build an interactive web dashboard",
                activatable = true
            };
            shiny_row.add_prefix (new Gtk.Image.from_icon_name ("applications-internet-symbolic"));
            shiny_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            shiny_row.activated.connect (() => {
                string template = ProjectScaffolder.get_shiny_template ();
                add_document_tab ("app.R", "r", template);
            });
            quick_group.add (shiny_row);

            var open_row = new Adw.ActionRow () {
                title = "Open File or Project Folder…",
                subtitle = "Open an existing document, notebook, or RStudio workspace",
                activatable = true
            };
            open_row.add_prefix (new Gtk.Image.from_icon_name ("document-open-symbolic"));
            open_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            open_row.activated.connect (() => {
                if (this.application != null) {
                    this.application.activate_action ("open", null);
                }
            });
            quick_group.add (open_row);

            box.append (quick_group);

            var more_group = new Adw.PreferencesGroup ();
            var more_expander = new Adw.ExpanderRow () {
                title = "More Formats &amp; Templates",
                subtitle = "R Markdown, Jupyter notebooks, RStudio &amp; Mallorn projects"
            };
            more_expander.add_prefix (new Gtk.Image.from_icon_name ("view-more-symbolic"));

            var rmd_row = new Adw.ActionRow () {
                title = "New R Markdown (.Rmd)",
                subtitle = "Reproducible computational analysis powered by knitr and R",
                activatable = true
            };
            rmd_row.add_prefix (new Gtk.Image.from_icon_name ("text-x-generic-symbolic"));
            rmd_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            rmd_row.activated.connect (() => {
                add_document_tab ("report.Rmd", "rmd", "---\ntitle: \"Analysis Report\"\noutput: html_document\n---\n\n```{r setup, include=FALSE}\nknitr::opts_chunk$set(echo = TRUE)\n```\n\n## Introduction\n\n");
            });
            more_expander.add_row (rmd_row);

            var ipynb_row = new Adw.ActionRow () {
                title = "New Jupyter Notebook (.ipynb)",
                subtitle = "Interactive notebook cells with rich inline outputs and plots",
                activatable = true
            };
            ipynb_row.add_prefix (new Gtk.Image.from_icon_name ("utilities-terminal-symbolic"));
            ipynb_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            ipynb_row.activated.connect (() => {
                string template = Core.NotebookSerializer.get_default_ipynb_markdown_template ();
                add_document_tab ("notebook.ipynb", "quarto", template);
            });
            more_expander.add_row (ipynb_row);

            var ts_row = new Adw.ActionRow () {
                title = "New TypeScript Module (.ts)",
                subtitle = "Typed TypeScript source with Node execution and tsc typechecking",
                activatable = true
            };
            ts_row.add_prefix (new Gtk.Image.from_icon_name ("utilities-terminal-symbolic"));
            ts_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            ts_row.activated.connect (() => {
                add_document_tab ("module.ts", "typescript");
            });
            more_expander.add_row (ts_row);

            var html_row = new Adw.ActionRow () {
                title = "New HTML5 Document (.html)",
                subtitle = "Live WebKitGTK 6.0 DOM preview with embedded CSS and LaTeX math",
                activatable = true
            };
            html_row.add_prefix (new Gtk.Image.from_icon_name ("text-html-symbolic"));
            html_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            html_row.activated.connect (() => {
                add_document_tab ("index.html", "html");
            });
            more_expander.add_row (html_row);

            var rproj_row = new Adw.ActionRow () {
                title = "New RStudio Project (.Rproj)…",
                subtitle = "Scaffold a 1:1 RStudio project directory with .Rproj, .Rprofile, and data/",
                activatable = true
            };
            rproj_row.add_prefix (new Gtk.Image.from_icon_name ("folder-symbolic"));
            rproj_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            rproj_row.activated.connect (() => {
                show_new_rproj_modal ();
            });
            more_expander.add_row (rproj_row);

            var wizard_row = new Adw.ActionRow () {
                title = "New Project Wizard…",
                subtitle = "Initialize a sandboxed reproducible environment (.mallorn)",
                activatable = true
            };
            wizard_row.add_prefix (new Gtk.Image.from_icon_name ("system-run-symbolic"));
            wizard_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            wizard_row.activated.connect (() => {
                show_new_project_modal ();
            });
            more_expander.add_row (wizard_row);

            more_group.add (more_expander);
            box.append (more_group);

            clamp.set_child (box);
            status.set_child (clamp);
            return status;
        }

        public void show_onboarding_tour_dialog (bool check_toolchain_after = false) {
            var dlg = new UI.OnboardingTourDialog ();
            dlg.tour_finished.connect ((open_toolchain_setup, skipped) => {
                if (open_toolchain_setup || (check_toolchain_after && !Core.ToolchainManager.get_default ().is_base_environment_installed ())) {
                    show_toolchain_setup_dialog (false, true);
                }
            });
            dlg.present (this);
        }

        public void show_presentation_template_dialog () {
            var dlg = new UI.PresentationTemplateDialog ();
            dlg.template_selected.connect ((t_title, starter_content, suggested_fn) => {
                var fmt = DocumentFormat.from_filename (suggested_fn);
                string lang = fmt.to_syntax_lang ();
                if (lang == "") lang = "markdown";
                add_document_tab (suggested_fn, lang, starter_content);
                show_toast (@"Created $t_title ($suggested_fn)");
            });
            dlg.present (this);
        }

        private void add_shortcut_row (Adw.PreferencesGroup grp, string title, string accel) {
            var row = new Adw.ActionRow () {
                title = title,
                use_markup = false
            };
            uint key = 0;
            Gdk.ModifierType mods = 0;
            string display_accel = accel;
            if (Gtk.accelerator_parse (accel, out key, out mods) && key != 0) {
                display_accel = Gtk.accelerator_get_label (key, mods);
            }
            var badge = new Gtk.Label (display_accel) {
                valign = Gtk.Align.CENTER,
                css_classes = { "dim-label", "caption", "monospace" }
            };
            row.add_suffix (badge);
            grp.add (row);
        }

        public void show_shortcuts_window () {
            var dlg = new Adw.Dialog () {
                title = "Keyboard Shortcuts",
                content_width = 560,
                content_height = 620
            };
            var toolbar_view = new Adw.ToolbarView ();
            toolbar_view.add_top_bar (new Adw.HeaderBar ());

            var page = new Adw.PreferencesPage ();

            var docs_group = new Adw.PreferencesGroup () { title = "Documents & Workspace" };
            add_shortcut_row (docs_group, "New Project or Document", "<Control>n");
            add_shortcut_row (docs_group, "Open File or Project", "<Control>o");
            add_shortcut_row (docs_group, "Save Document", "<Control>s");
            add_shortcut_row (docs_group, "Command Palette", "<Control>k");
            add_shortcut_row (docs_group, "Manage Panels & Popouts", "<Control><Shift>l");
            add_shortcut_row (docs_group, "6-Quadrant Ultrawide Layout", "<Control><Alt>6");
            add_shortcut_row (docs_group, "Imladris on Web Sync", "<Control><Shift>w");
            add_shortcut_row (docs_group, "Toggle Ribbon Deck", "F1");
            add_shortcut_row (docs_group, "Focus Editor", "<Control>1");
            add_shortcut_row (docs_group, "Focus Console", "<Control>2");
            add_shortcut_row (docs_group, "Preferences", "<Control>comma");
            add_shortcut_row (docs_group, "Keyboard Shortcuts", "<Control>question");
            page.add (docs_group);

            var exec_group = new Adw.PreferencesGroup () { title = "Execution & Console" };
            add_shortcut_row (exec_group, "Run Active Code Chunk", "<Control><Shift>Return");
            add_shortcut_row (exec_group, "Run Line or Selection", "<Control>Return");
            add_shortcut_row (exec_group, "Run Cell (Notebook)", "<Shift>Return");
            add_shortcut_row (exec_group, "Run All Chunks", "<Control><Alt>r");
            add_shortcut_row (exec_group, "Clear Console", "<Control>l");
            add_shortcut_row (exec_group, "Restart Execution Kernel", "<Control><Shift>F10");
            page.add (exec_group);

            var sci_group = new Adw.PreferencesGroup () { title = "Editing & Scientific Tools" };
            add_shortcut_row (sci_group, "Insert Table (Popup Picker)", "<Control><Alt>t");
            add_shortcut_row (sci_group, "Insert R Assignment (<-)", "<Alt>minus");
            add_shortcut_row (sci_group, "Insert R Pipe (|>)", "<Control><Shift>m");
            add_shortcut_row (sci_group, "Toggle Line Comment", "<Control><Shift>c");
            add_shortcut_row (sci_group, "Math & Chemical Reaction Studio", "<Control>m");
            add_shortcut_row (sci_group, "Visual Flow & Mermaid Studio", "<Control><Shift>d");
            add_shortcut_row (sci_group, "Insert Zotero Citation", "<Control><Shift>i");
            add_shortcut_row (sci_group, "Bibliography & DOI Manager (.bib)", "<Control><Shift>b");
            add_shortcut_row (sci_group, "Render / Compile Document", "<Control><Shift>k");
            add_shortcut_row (sci_group, "Elrond AI Assistant", "<Control><Shift>e");
            page.add (sci_group);

            toolbar_view.set_content (page);
            dlg.set_child (toolbar_view);
            dlg.present (this);
        }

        public void show_latex_template_dialog () {
            var dlg = new UI.LatexTemplateDialog ();
            dlg.template_selected.connect ((t_title, starter_content, suggested_fn) => {
                add_document_tab (suggested_fn, "latex", starter_content);
                show_toast (@"Created $t_title ($suggested_fn)");
            });
            dlg.present (this);
        }

        public void show_new_project_modal () {
            var dlg = new UI.NewProjectDialog ();
            dlg.item_created.connect ((file, config, is_standalone) => {
                this.current_project_type = config.project_type;
                if (file.get_parent () != null) {
                    this.current_project_dir = file.get_parent ().get_path ();
                    Services.PersistentSessionManager.peek_for_key (this.current_project_dir).set_working_directory (
                        this.current_project_dir, config.project_type
                    );
                    Services.PersistentSessionManager.get_default ().set_working_directory (
                        this.current_project_dir, config.project_type
                    );
                }
                update_environment_badge (config.project_type);
                open_file_from_path.begin (file.get_path ());
            });
            dlg.present (this);
        }

        public void show_new_rproj_modal () {
            var dlg = new UI.RprojCreationDialog ();
            dlg.rproj_created.connect ((rproj_file, primary_file, config) => {
                this.current_project_type = config.project_type;
                this.current_project_dir = rproj_file.get_parent ().get_path ();
                Services.PersistentSessionManager.peek_for_key (this.current_project_dir).set_working_directory (
                    this.current_project_dir, config.project_type
                );
                Services.PersistentSessionManager.get_default ().set_working_directory (
                    this.current_project_dir, config.project_type
                );
                update_environment_badge (config.project_type);
                open_file_from_path.begin (primary_file.get_path ());
                show_toast (@"Created RStudio project $(rproj_file.get_basename ())");
            });
            dlg.present (this);
        }

        public void update_environment_badge (ProjectType ptype) {
            if (ptype == ProjectType.SANDBOXED) {
                status_env_badge_lbl.label = "Sandboxed • Reproducible";
                status_env_badge_lbl.remove_css_class ("env-standard");
                status_env_badge_lbl.add_css_class ("env-sandboxed");
            } else {
                status_env_badge_lbl.label = "System Environment";
                status_env_badge_lbl.remove_css_class ("env-sandboxed");
                status_env_badge_lbl.add_css_class ("env-standard");
            }
        }

        public async void open_file_from_path (string fpath) {
            try {
                var file = GLib.File.new_for_path (fpath);
                string name = file.get_basename ();

                // Check if opening an RStudio .Rproj or .mallorn project marker / archive
                if (name.has_suffix (".mallorn") || name.has_suffix (".Rproj")) {
                    if (name.has_suffix (".mallorn") && MallornManager.is_mallorn_archive (fpath)) {
                        string dest_dir = GLib.Path.build_filename (
                            file.get_parent ().get_path (),
                            name.substring (0, name.length - 8)
                        );
                        try {
                            var unpacked_cfg = MallornManager.unpack_mallorn_archive (fpath, dest_dir);
                            update_environment_badge (unpacked_cfg.project_type);
                            var d = get_active_document ();
                            if (d != null) {
                                d.append_console_log (@"✔ Extracted .mallorn archive to $dest_dir");
                            }
                            // Search for primary notebook in the extracted directory
                            string[] candidates = { "analysis.qmd", "report.Rmd", "notebook.ipynb", "index.qmd" };
                            foreach (var cand in candidates) {
                                string cand_path = GLib.Path.build_filename (dest_dir, cand);
                                if (GLib.FileUtils.test (cand_path, GLib.FileTest.EXISTS)) {
                                    yield open_file_from_path (cand_path);
                                    return;
                                }
                            }
                        } catch (GLib.Error e) {
                            warning ("Failed to unpack mallorn archive: %s", e.message);
                        }
                    } else {
                        // Opened an .Rproj or .mallorn project file in a project folder
                        var proj_dir = file.get_parent ();
                        var ptype = Services.SandboxController.detect_project_type (proj_dir.get_path ());
                        update_environment_badge (ptype);
                        string[] candidates = { "analysis.qmd", "report.Rmd", "notebook.ipynb", "index.qmd", "main.R", "main.py" };
                        foreach (var cand in candidates) {
                            string cand_path = GLib.Path.build_filename (proj_dir.get_path (), cand);
                            if (GLib.FileUtils.test (cand_path, GLib.FileTest.EXISTS)) {
                                yield open_file_from_path (cand_path);
                                return;
                            }
                        }
                    }
                }

                // Normal document opening
                uint8[] contents;
                string etag;
                yield file.load_contents_async (null, out contents, out etag);
                string raw_text = Core.PlatformUtils.data_to_string (contents);

                var fmt = DocumentFormat.from_filename (name);
                string text = Adapters.DocumentAdapter.load_to_editor_buffer (raw_text, fmt);
                string lang = fmt.to_syntax_lang ();

                add_document_tab (name, lang, text, file, fmt == DocumentFormat.IPYNB ? raw_text : null);

                // Detect surrounding project sandbox/standard status
                var parent_dir = file.get_parent ();
                if (parent_dir != null) {
                    var ptype = Services.SandboxController.detect_project_type (parent_dir.get_path ());
                    this.current_project_type = ptype;
                    this.current_project_dir = parent_dir.get_path ();
                    var active_doc = get_active_document ();
                    if (active_doc != null) {
                        active_doc.panel_registry.get_session_manager ().set_working_directory (this.current_project_dir, ptype);
                        active_doc.review_service.load_for_document (file.get_path (), this.current_project_dir, text);
                        if (active_doc.review_service.store.threads.size > 0) {
                            active_doc.set_review_sidebar_visible (true);
                        }
                    }
                    Services.PersistentSessionManager.get_default ().set_working_directory (this.current_project_dir, ptype);
                    update_environment_badge (ptype);
                    update_ribbon_state_machine (fmt, ptype);
                }

                Services.WorkspaceStateManager.get_default ().resolve_mode_for_file (name);
            } catch (GLib.Error e) {
                warning ("Failed to open file from path %s: %s", fpath, e.message);
            }
        }

        public async void open_document_async () {
            var dialog = new Gtk.FileDialog () {
                title = "Open Document or Project",
                modal = true
            };
            try {
                var file = yield dialog.open (this, null);
                if (file != null) {
                    yield open_file_from_path (file.get_path ());
                }
            } catch (GLib.Error e) {
                warning ("Failed to open file: %s", e.message);
            }
        }

        public async void save_document_async () {
            var doc = get_active_document ();
            if (doc == null) return;

            if (doc.file_location != null) {
                try {
                    string editor_content = doc.get_clean_source_text ();
                    var fmt = DocumentFormat.from_filename (doc.file_location.get_basename ());
                    string to_save = Adapters.DocumentAdapter.save_from_editor_buffer (
                        editor_content, fmt, doc.raw_ipynb_source
                    );
                    if (fmt == DocumentFormat.IPYNB) {
                        doc.raw_ipynb_source = to_save;
                    }
                    string etag;
                    yield doc.file_location.replace_contents_async (
                        to_save.data,
                        null,
                        false,
                        GLib.FileCreateFlags.REPLACE_DESTINATION,
                        null,
                        out etag
                    );
                    doc.source_buffer.set_modified (false);
                    doc.review_service.save_to_disk ();
                    if (doc.rtf_editor != null) {
                        doc.rtf_editor.buffer.set_modified (false);
                    }
                    Services.RecoveryService.get_default ().purge_document_cache (doc.doc_id);
                    doc.append_console_log (@"✔ Saved $(doc.file_location.get_basename ())");
                    notify_web_sync_on_save (doc, editor_content);
                } catch (GLib.Error e) {
                    doc.append_console_log (@"✖ Save failed: $(e.message)");
                }
            } else {
                var dialog = new Gtk.FileDialog () {
                    title = "Save Document",
                    modal = true
                };
                try {
                    var file = yield dialog.save (this, null);
                    if (file != null) {
                        doc.file_location = file;
                        string editor_content = doc.get_clean_source_text ();
                        var fmt = DocumentFormat.from_filename (file.get_basename ());
                        string to_save = Adapters.DocumentAdapter.save_from_editor_buffer (
                            editor_content, fmt, doc.raw_ipynb_source
                        );
                        if (fmt == DocumentFormat.IPYNB) {
                            doc.raw_ipynb_source = to_save;
                        }
                        string etag;
                        yield file.replace_contents_async (
                            to_save.data,
                            null,
                            false,
                            GLib.FileCreateFlags.REPLACE_DESTINATION,
                            null,
                            out etag
                        );
                        doc.source_buffer.set_modified (false);
                    doc.review_service.save_to_disk ();
                    if (doc.rtf_editor != null) {
                        doc.rtf_editor.buffer.set_modified (false);
                    }
                        Services.RecoveryService.get_default ().purge_document_cache (doc.doc_id);
                        if (tab_view.selected_page != null) {
                            tab_view.selected_page.title = file.get_basename ();
                        }
                        doc.append_console_log (@"✔ Saved $(file.get_basename ())");
                        notify_web_sync_on_save (doc, editor_content);
                    }
                } catch (GLib.Error e) {
                    doc.append_console_log (@"✖ Save failed: $(e.message)");
                }
            }
        }

        private bool standard_export_warning_dismissed = false;

        public async bool confirm_standard_project_export_if_needed () {
            if (current_project_type == ProjectType.STANDARD && !standard_export_warning_dismissed) {
                var alert = new Adw.AlertDialog (
                    "System Libraries (Non-Portable)",
                    "This project relies on system libraries and may fail to run on other machines if required packages are missing."
                );
                alert.add_response ("cancel", "Cancel");
                alert.add_response ("always", "Continue & Don't Ask Again");
                alert.add_response ("continue", "Continue Export");
                alert.set_response_appearance ("continue", Adw.ResponseAppearance.SUGGESTED);
                alert.set_default_response ("continue");
                alert.set_close_response ("cancel");
                string response = yield alert.choose (this, null);
                if (response == "always") {
                    standard_export_warning_dismissed = true;
                    return true;
                }
                return (response == "continue");
            }
            return true;
        }

        public async void export_document_dialog_async (string format) {
            var doc = get_active_document ();
            if (doc == null) {
                return;
            }

            if (!(yield confirm_standard_project_export_if_needed ())) {
                return;
            }

            var dialog = new Gtk.FileDialog () {
                title = @"Export to $(format.up ())",
                modal = true
            };
            string base_name = doc.file_location != null ? doc.file_location.get_basename () : @"untitled.$(doc.doc_type)";
            int dot_idx = base_name.last_index_of (".");
            string base_prefix = dot_idx >= 0 ? base_name.substring (0, dot_idx) : base_name;
            dialog.initial_name = @"$base_prefix.$format";

            try {
                var file = yield dialog.save (this, null);
                if (file != null) {
                    string? dest_path = file.get_path ();
                    if (dest_path == null) {
                        show_toast ("Selected export destination is not a local file path");
                        return;
                    }
                    if (doc.file_location != null) {
                        yield save_document_async ();
                    }
                    doc.append_console_log (@"▶ Exporting $base_name to $(file.get_basename ())...");
                    string src_ext = doc.get_document_format ().get_extension ();
                    string? doc_path = doc.file_location != null ? doc.file_location.get_path () : null;
                    string src_path = doc_path ?? GLib.Path.build_filename (Core.PlatformUtils.get_shared_cache_dir ("tmp"), @"$base_prefix$src_ext");
                    string clean_source = doc.get_clean_source_text ();
                    bool ok = yield Services.ExportService.get_default ().export_document_async (
                        src_path,
                        dest_path,
                        format,
                        clean_source
                    );
                    if (ok) {
                        doc.append_console_log (@"✔ Successfully exported to $dest_path");
                        // Generate GxP / EU CRA Cryptographic Provenance Manifest
                        string pdir = (current_project_dir != "") ? current_project_dir : GLib.Path.get_dirname (src_path);
                        Core.ProvenanceAttestationService.generate_attestation_async.begin (
                            src_path,
                            clean_source,
                            pdir,
                            (obj, att_res) => {
                                try {
                                    string manifest_path = Core.ProvenanceAttestationService.generate_attestation_async.end (att_res);
                                    doc.append_console_log (@"🔒 [GxP Provenance Lockfile Generated: $(GLib.Path.get_basename (manifest_path))]");
                                } catch (GLib.Error err) {
                                    doc.append_console_log (@"⚠ Provenance generation notice: $(err.message)");
                                }
                            }
                        );
                    } else {
                        string err_detail = Services.ExportService.get_default ().last_error_message;
                        doc.append_console_log (@"✖ Export to $(format.up ()) failed.$(err_detail != "" ? @" $err_detail" : " Check console output.")");
                        show_toast (@"Export to $(format.up ()) failed");
                    }
                }
            } catch (GLib.Error e) {
                if (doc != null) {
                    doc.append_console_log (@"✖ Export dialog failed: $(e.message)");
                }
            }
        }

        public async void export_mallorn_archive_async () {
            var doc = get_active_document ();
            if (doc == null || doc.file_location == null) {
                if (doc != null) {
                    doc.append_console_log ("⚠ Please save the document or project before exporting as .mallorn archive.");
                }
                return;
            }

            if (!(yield confirm_standard_project_export_if_needed ())) {
                return;
            }

            var project_dir = doc.file_location.get_parent ();
            string proj_name = project_dir.get_basename ();

            var dialog = new Gtk.FileDialog () {
                title = "Export Portable .mallorn Archive (1:1 RStudio)",
                modal = true
            };
            dialog.initial_name = @"$proj_name.mallorn";

            try {
                var file = yield dialog.save (this, null);
                if (file != null) {
                    yield save_document_async ();
                    doc.append_console_log (@"▶ Packaging workspace '$proj_name' into $(file.get_basename ())...");
                    try {
                        MallornManager.pack_mallorn_archive (project_dir.get_path (), file.get_path ());
                        doc.append_console_log (@"✔ Successfully packed .mallorn archive to $(file.get_path ())");
                    } catch (GLib.Error e) {
                        doc.append_console_log (@"✖ Failed to create .mallorn archive: $(e.message)");
                    }
                }
            } catch (GLib.Error e) {
                if (doc != null) {
                    doc.append_console_log (@"✖ Export .mallorn dialog failed: $(e.message)");
                }
            }
        }

        public async void export_to_rstudio_async () {
            var doc = get_active_document ();
            if (doc == null || doc.file_location == null) {
                if (doc != null) {
                    doc.append_console_log ("⚠ Please save the document or project before exporting for RStudio.");
                }
                return;
            }

            if (!(yield confirm_standard_project_export_if_needed ())) {
                return;
            }

            var project_dir = doc.file_location.get_parent ();
            string proj_name = project_dir.get_basename ();

            var dialog = new Gtk.FileDialog () {
                title = "Export Project for RStudio",
                modal = true
            };

            try {
                var folder = yield dialog.select_folder (this, null);
                if (folder != null) {
                    yield save_document_async ();
                    string target_dir = Path.build_filename (folder.get_path (), proj_name);
                    doc.append_console_log (@"▶ Exporting project '$proj_name' to RStudio workspace at $target_dir...");
                    try {
                        Services.SandboxController.export_for_rstudio (project_dir.get_path (), target_dir);
                        doc.append_console_log (@"✔ Successfully exported RStudio project to $target_dir");
                    } catch (GLib.Error e) {
                        doc.append_console_log (@"✖ Failed to export for RStudio: $(e.message)");
                    }
                }
            } catch (GLib.Error e) {
                if (doc != null) {
                    doc.append_console_log (@"✖ Export to RStudio dialog cancelled or failed: $(e.message)");
                }
            }
        }

        public async void export_to_jupyter_async () {
            var doc = get_active_document ();
            if (doc == null || doc.file_location == null) {
                if (doc != null) {
                    doc.append_console_log ("⚠ Please save the document or project before exporting for Jupyter.");
                }
                return;
            }

            if (!(yield confirm_standard_project_export_if_needed ())) {
                return;
            }

            var project_dir = doc.file_location.get_parent ();
            string proj_name = project_dir.get_basename ();

            var dialog = new Gtk.FileDialog () {
                title = "Export Project for Jupyter Notebook",
                modal = true
            };

            try {
                var folder = yield dialog.select_folder (this, null);
                if (folder != null) {
                    yield save_document_async ();
                    string target_dir = Path.build_filename (folder.get_path (), proj_name);
                    doc.append_console_log (@"▶ Exporting project '$proj_name' to Jupyter workspace at $target_dir...");
                    try {
                        Services.SandboxController.export_for_jupyter (project_dir.get_path (), target_dir);
                        doc.append_console_log (@"✔ Successfully exported Jupyter project to $target_dir");
                    } catch (GLib.Error e) {
                        doc.append_console_log (@"✖ Failed to export for Jupyter: $(e.message)");
                    }
                }
            } catch (GLib.Error e) {
                if (doc != null) {
                    doc.append_console_log (@"✖ Export to Jupyter dialog cancelled or failed: $(e.message)");
                }
            }
        }

        public void trigger_render (string target_format) {
            export_document_dialog_async.begin (target_format);
        }

        public string get_open_tabs_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("tabs");
            b.begin_array ();
            if (tab_view != null) {
                var selected = tab_view.selected_page;
                for (int i = 0; i < tab_view.n_pages; i++) {
                    var page = tab_view.get_nth_page (i);
                    var doc = page.child as DocumentPage;
                    b.begin_object ();
                    b.set_member_name ("title");
                    b.add_string_value (page.title ?? "Untitled");
                    b.set_member_name ("active");
                    b.add_boolean_value (page == selected);
                    b.set_member_name ("language");
                    b.add_string_value (doc != null ? doc.doc_type : "unknown");
                    b.set_member_name ("file_path");
                    b.add_string_value (doc != null && doc.file_location != null ? (doc.file_location.get_path () ?? "") : "");
                    b.end_object ();
                }
            }
            b.end_array ();
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        public string get_active_document_json () {
            var doc = get_active_document ();
            if (doc == null) {
                return "No active document open.";
            }
            string path = (doc.file_location != null && doc.file_location.get_path () != null) ? doc.file_location.get_path () : "";
            int lines = (doc.rtf_editor != null) ? doc.rtf_editor.buffer.get_line_count () : doc.source_buffer.get_line_count ();
            return @"File: $path\nLanguage: $(doc.doc_type)\nLines: $lines\n\nContent:\n$(doc.get_clean_source_text ())";
        }

        public bool insert_text_in_active (string text) {
            var doc = get_active_document ();
            if (doc == null) return false;
            Gtk.TextBuffer buf = (doc.rtf_editor != null) ? doc.rtf_editor.buffer : (Gtk.TextBuffer) doc.source_buffer;
            buf.begin_user_action ();
            buf.insert_at_cursor (text, -1);
            buf.end_user_action ();
            return true;
        }

        public bool insert_code_chunk_in_active (string engine, string options) {
            var doc = get_active_document ();
            if (doc == null) return false;
            doc.insert_code_chunk (engine, options);
            return true;
        }

        public string trigger_render_from_mcp (string format) {
            trigger_render (format);
            return @"▶ Render pipeline triggered for target: $format";
        }

        public string execute_command_from_mcp (string[] parts) {
            var doc = get_active_document ();
            if (doc == null) return "No active document open.";
            ExecutionEngine.run_command_async.begin (parts, doc);
            return @"▶ Executing command asynchronously: $(string.joinv (" ", parts))";
        }

        public void trigger_selected_scientific_render () {
            uint sel = (export_format_selector != null) ? export_format_selector.selected : 0;
            var doc = get_active_document ();
            if (doc == null) return;

            var doc_fmt = doc.get_document_format ();
            var profile = Core.FormatProfile.for_format (doc_fmt);
            string[] targets = profile.get_export_targets ();
            string selected_label = (sel < targets.length) ? targets[sel] : "";

            if (doc_fmt == DocumentFormat.TEX) {
                if (sel == 3 || selected_label.down ().contains ("html")) {
                    compile_scientific_document_async.begin (Core.ScientificOutputFormat.HTML_MANUSCRIPT, null);
                } else {
                    string engine = "latexmk";
                    if (sel == 1) engine = "xelatex";
                    else if (sel == 2) engine = "pdflatex";
                    compile_scientific_document_async.begin (Core.ScientificOutputFormat.PDF_MANUSCRIPT, engine);
                }
                return;
            }

            if (doc_fmt == DocumentFormat.QMD) {
                var sc_fmt = Core.ScientificOutputFormat.HTML_MANUSCRIPT;
                if (sel == 1) sc_fmt = Core.ScientificOutputFormat.PDF_MANUSCRIPT;
                else if (sel == 2) sc_fmt = Core.ScientificOutputFormat.DOCX_DOCUMENT;
                else if (sel == 3) sc_fmt = Core.ScientificOutputFormat.REVEALJS_SLIDES;
                else if (sel == 4) sc_fmt = Core.ScientificOutputFormat.BEAMER_PDF_SLIDES;
                else if (sel == 5) sc_fmt = Core.ScientificOutputFormat.TYPST_POSTER_PDF;
                compile_scientific_document_async.begin (sc_fmt);
                return;
            }

            if (doc_fmt == DocumentFormat.TS) {
                compile_scientific_document_async.begin (Core.ScientificOutputFormat.HTML_MANUSCRIPT);
                return;
            }

            // Route all other formats (.Rmd, .md, .ipynb, .rtf, .html) by their FormatProfile target label
            render_document_target_async.begin (selected_label);
        }

        private string resolve_render_source_path (DocumentPage doc, DocumentFormat doc_fmt, out string clean_source) throws GLib.Error {
            clean_source = doc.get_clean_source_text ();
            if (doc.file_location != null) {
                return doc.file_location.get_path ();
            }
            string cache_dir = Core.PlatformUtils.get_shared_cache_dir ("render");
            string ext = doc_fmt.get_extension ();
            if (ext == "") ext = ".md";
            string s_path = GLib.Path.build_filename (cache_dir, @"document$ext");
            string payload = (doc_fmt == DocumentFormat.IPYNB)
                ? Adapters.DocumentAdapter.save_from_editor_buffer (clean_source, DocumentFormat.IPYNB)
                : clean_source;
            GLib.FileUtils.set_contents (s_path, payload);
            return s_path;
        }

        private string compute_output_path_for_ext (string s_path, string out_ext) {
            int dot_idx = s_path.last_index_of_char ('.');
            string stem = (dot_idx > 0) ? s_path.substring (0, dot_idx) : s_path;
            return @"$stem.$out_ext";
        }

        private async void render_via_export_service_async (DocumentPage doc, string s_path, string clean_source, string target_ext) {
            string out_path = compute_output_path_for_ext (s_path, target_ext);
            doc.append_console_log (@"▶ Rendering $(GLib.Path.get_basename (s_path)) to $(target_ext.up ())...");
            bool ok = yield Services.ExportService.get_default ().export_document_async (
                s_path,
                out_path,
                target_ext,
                clean_source
            );
            if (!ok || !GLib.FileUtils.test (out_path, GLib.FileTest.EXISTS)) {
                string err_detail = Services.ExportService.get_default ().last_error_message;
                doc.append_console_log (@"✖ Render to $(target_ext.up ()) failed.$(err_detail != "" ? @" $err_detail" : "")");
                show_toast (@"Render to $(target_ext.up ()) failed");
                return;
            }
            doc.append_console_log (@"✔ Rendered $(GLib.Path.get_basename (out_path))");
            show_toast (@"Rendered $(GLib.Path.get_basename (out_path))");
            if (target_ext == "html") {
                string uri = GLib.File.new_for_path (out_path).get_uri ();
                doc.show_live_preview (uri);
            } else {
                var file = GLib.File.new_for_path (out_path);
                var launcher = new Gtk.FileLauncher (file);
                launcher.launch.begin (this, null, null);
            }
        }

        public async void render_document_target_async (string selected_label) {
            var doc = get_active_document ();
            if (doc == null) return;

            var doc_fmt = doc.get_document_format ();
            if (doc.file_location != null) {
                yield save_document_async ();
            }

            string clean_source = "";
            string s_path = "";
            try {
                s_path = resolve_render_source_path (doc, doc_fmt, out clean_source);
            } catch (GLib.Error e) {
                show_toast (@"Failed to prepare document for rendering: $(e.message)");
                return;
            }

            string low = selected_label.down ();
            if (doc_fmt == DocumentFormat.HTML && low.contains ("refresh")) {
                doc.refresh_live_preview (clean_source);
                doc.show_live_preview ();
                show_toast ("Refreshed HTML preview");
                return;
            }
            if (doc_fmt == DocumentFormat.IPYNB && low.contains ("notebook")) {
                yield export_document_dialog_async ("ipynb");
                return;
            }
            if (doc_fmt == DocumentFormat.RTF && (low == "md" || low.contains ("markdown"))) {
                string out_md = compute_output_path_for_ext (s_path, "md");
                try {
                    string md_text = Core.RtfCodec.rtf_to_plain_text (clean_source);
                    GLib.FileUtils.set_contents (out_md, md_text);
                    doc.append_console_log (@"✔ Exported Markdown to $(GLib.Path.get_basename (out_md))");
                    show_toast (@"Exported $(GLib.Path.get_basename (out_md))");
                    var file = GLib.File.new_for_path (out_md);
                    var launcher = new Gtk.FileLauncher (file);
                    launcher.launch.begin (this, null, null);
                } catch (GLib.Error e) {
                    doc.append_console_log (@"✖ Markdown export failed: $(e.message)");
                    show_toast ("Markdown export failed");
                }
                return;
            }

            string target_ext = "html";
            if (low.contains ("pdf")) {
                target_ext = "pdf";
            } else if (low.contains ("docx") || low.contains ("word")) {
                target_ext = "docx";
            } else if (low.contains ("odt")) {
                target_ext = "odt";
            } else if (low.contains ("rtf")) {
                target_ext = "rtf";
            }

            yield render_via_export_service_async (doc, s_path, clean_source, target_ext);
        }

        public async void compile_scientific_document_async (Core.ScientificOutputFormat format, string? preferred_tex_engine = null) {
            var doc = get_active_document ();
            if (doc == null) return;

            var doc_fmt = doc.get_document_format ();
            if (doc.file_location != null) {
                yield save_document_async ();
            }

            string clean_source = "";
            string s_path = "";
            try {
                s_path = resolve_render_source_path (doc, doc_fmt, out clean_source);
            } catch (GLib.Error e) {
                show_toast (@"Failed to cache document for rendering: $(e.message)");
                return;
            }

            if (doc_fmt == DocumentFormat.TEX) {
                if (format == Core.ScientificOutputFormat.HTML_MANUSCRIPT) {
                    yield render_via_export_service_async (doc, s_path, clean_source, "html");
                    return;
                }
                doc.append_console_log (@"▶ Building LaTeX document $(GLib.Path.get_basename (s_path))...");
                var tex_res = yield Runners.LatexBuildRunner.build_async (s_path, preferred_tex_engine);
                if (tex_res.stdout_stderr.strip ().length > 0) {
                    doc.append_console_log (tex_res.stdout_stderr.strip ());
                }
                if (tex_res.success && tex_res.pdf_path != "" && GLib.FileUtils.test (tex_res.pdf_path, GLib.FileTest.EXISTS)) {
                    show_toast (@"Built $(GLib.Path.get_basename (tex_res.pdf_path)) ($(tex_res.engine_used))");
                    var pdf_file = GLib.File.new_for_path (tex_res.pdf_path);
                    var launcher = new Gtk.FileLauncher (pdf_file);
                    launcher.launch.begin (this, null, null);
                } else if (tex_res.engine_used == "" || tex_res.engine_used == "none") {
                    doc.append_console_log ("ℹ No system TeX engine detected; using built-in PDF renderer...");
                    yield render_via_export_service_async (doc, s_path, clean_source, "pdf");
                } else {
                    string err = tex_res.diagnostics.size > 0
                        ? tex_res.diagnostics.get (0).message
                        : (tex_res.stdout_stderr.strip ().length > 0 ? "LaTeX build failed (see console)" : "LaTeX engine not found");
                    doc.append_console_log (@"✖ $err");
                    show_toast (@"LaTeX build failed: $err");
                }
                return;
            }

            if (doc_fmt == DocumentFormat.TS) {
                doc.append_console_log (@"▶ Running TypeScript file $(GLib.Path.get_basename (s_path))...");
                string? proj_dir = (current_project_dir != "") ? current_project_dir : null;
                var ts_res = yield Runners.TypeScriptRunner.run_file_async (s_path, proj_dir);
                if (ts_res.stdout_text.strip ().length > 0) {
                    doc.append_console_log (ts_res.stdout_text.strip ());
                }
                if (ts_res.stderr_text.strip ().length > 0) {
                    doc.append_console_log (ts_res.stderr_text.strip ());
                }
                if (ts_res.success) {
                    show_toast (@"Executed $(GLib.Path.get_basename (s_path)) ($(ts_res.runtime_used))");
                } else {
                    string err = ts_res.stderr_text.strip ().length > 0
                        ? ts_res.stderr_text.strip ()
                        : "TypeScript execution failed";
                    doc.append_console_log (@"✖ $err");
                    show_toast ("TypeScript run failed");
                }
                return;
            }

            string working_dir = GLib.Path.get_dirname (s_path);
            if (Core.PlatformUtils.is_program_available ("quarto", working_dir)) {
                var engine = new Core.QuartoExportEngine ();
                engine.compilation_progress.connect ((line) => {
                    doc.append_console_log (line);
                });
                engine.tex_healing_started.connect (() => {
                    show_toast ("Installing TinyTeX and Beamer packages (first-time setup)...");
                });

                try {
                    string out_path = yield engine.render_document_async (s_path, format);
                    show_toast (@"Rendered $(GLib.Path.get_basename (out_path))");

                    if (format == Core.ScientificOutputFormat.HTML_MANUSCRIPT || format == Core.ScientificOutputFormat.REVEALJS_SLIDES) {
                        string uri = GLib.Filename.to_uri (out_path);
                        doc.show_live_preview (uri);
                    } else {
                        var file = GLib.File.new_for_path (out_path);
                        var launcher = new Gtk.FileLauncher (file);
                        launcher.launch.begin (this, null, null);
                    }
                    return;
                } catch (GLib.Error e) {
                    doc.append_console_log (@"⚠ Quarto render unavailable or failed ($(e.message)); falling back to built-in renderer...");
                }
            } else {
                doc.append_console_log ("ℹ Quarto CLI not found; using built-in Imladris renderer...");
            }

            string fallback_ext = (format == Core.ScientificOutputFormat.HTML_MANUSCRIPT ||
                                   format == Core.ScientificOutputFormat.REVEALJS_SLIDES)
                ? "html"
                : "pdf";
            yield render_via_export_service_async (doc, s_path, clean_source, fallback_ext);
        }

        private void setup_actions () {
            var action_undo = new GLib.SimpleAction ("undo", null);
            action_undo.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.undo ();
            });
            this.add_action (action_undo);

            var action_redo = new GLib.SimpleAction ("redo", null);
            action_redo.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.redo ();
            });
            this.add_action (action_redo);

            var action_collapse = new GLib.SimpleAction ("collapse_ribbon", null);
            action_collapse.activate.connect (() => {
                toggle_ribbon_visibility ();
            });
            this.add_action (action_collapse);

            var action_zoom_in = new GLib.SimpleAction ("zoom_in", null);
            action_zoom_in.activate.connect (() => {
                apply_zoom (current_zoom + 10);
            });
            this.add_action (action_zoom_in);

            var action_zoom_out = new GLib.SimpleAction ("zoom_out", null);
            action_zoom_out.activate.connect (() => {
                apply_zoom (current_zoom - 10);
            });
            this.add_action (action_zoom_out);

            var action_zoom_reset = new GLib.SimpleAction ("zoom_reset", null);
            action_zoom_reset.activate.connect (() => {
                apply_zoom (100);
            });
            this.add_action (action_zoom_reset);

            var action_run_chunk = new GLib.SimpleAction ("run_chunk", null);
            action_run_chunk.activate.connect (() => {
                run_active_chunk ();
            });
            this.add_action (action_run_chunk);

            var action_run_line = new GLib.SimpleAction ("run_line", null);
            action_run_line.activate.connect (() => {
                run_line_or_selection ();
            });
            this.add_action (action_run_line);

            var action_run_above = new GLib.SimpleAction ("run_chunks_above", null);
            action_run_above.activate.connect (() => {
                run_chunks_above ();
            });
            this.add_action (action_run_above);

            var action_clear_console = new GLib.SimpleAction ("clear_console", null);
            action_clear_console.activate.connect (() => {
                clear_console ();
            });
            this.add_action (action_clear_console);

            var action_insert_pipe = new GLib.SimpleAction ("insert_pipe", null);
            action_insert_pipe.activate.connect (() => {
                insert_in_active_editor (" |> ");
            });
            this.add_action (action_insert_pipe);

            var action_insert_chunk = new GLib.SimpleAction ("insert_chunk", null);
            action_insert_chunk.activate.connect (() => {
                var d = get_active_document ();
                string def_lang = (d != null && d.get_document_format () == DocumentFormat.IPYNB) ? "python" : "r";
                insert_in_active_editor ("\n```{" + def_lang + "}\n\n```\n");
            });
            this.add_action (action_insert_chunk);

            var action_insert_table = new GLib.SimpleAction ("insert_table", null);
            action_insert_table.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    d.show_table_picker_popover ();
                }
            });
            this.add_action (action_insert_table);

            var action_toggle_comment = new GLib.SimpleAction ("toggle_comment", null);
            action_toggle_comment.activate.connect (() => {
                toggle_active_line_comment ();
            });
            this.add_action (action_toggle_comment);

            var action_insert_assignment = new GLib.SimpleAction ("insert_assignment", null);
            action_insert_assignment.activate.connect (() => {
                insert_in_active_editor (" <- ");
            });
            this.add_action (action_insert_assignment);

            var action_focus_editor = new GLib.SimpleAction ("focus_editor", null);
            action_focus_editor.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    if (d.rstudio_dock_grid != null && d.rstudio_dock_grid.dock_manager.is_panel_undocked (Core.Layout.PanelId.SOURCE_EDITOR)) {
                        d.rstudio_dock_grid.dock_manager.focus_undocked_panel (Core.Layout.PanelId.SOURCE_EDITOR);
                    } else if (d.dock_layout_state != null) {
                        d.dock_layout_state.activate_panel (Core.Layout.PanelId.SOURCE_EDITOR);
                    }
                    if (d.rtf_editor != null) d.rtf_editor.text_view.grab_focus ();
                    else if (d.source_view != null) d.source_view.grab_focus ();
                }
            });
            this.add_action (action_focus_editor);

            var action_focus_console = new GLib.SimpleAction ("focus_console", null);
            action_focus_console.activate.connect (() => {
                var d = get_active_document ();
                if (d != null && d.panel_registry != null && d.panel_registry.repl_entry != null) {
                    if (d.rstudio_dock_grid != null && d.rstudio_dock_grid.dock_manager.is_panel_undocked (Core.Layout.PanelId.CONSOLE)) {
                        d.rstudio_dock_grid.dock_manager.focus_undocked_panel (Core.Layout.PanelId.CONSOLE);
                    } else if (d.dock_layout_state != null) {
                        d.dock_layout_state.activate_panel (Core.Layout.PanelId.CONSOLE);
                    }
                    d.panel_registry.repl_entry.grab_focus ();
                }
            });
            this.add_action (action_focus_console);

            var action_zotero = new GLib.SimpleAction ("zotero_picker", null);
            action_zotero.activate.connect (() => {
                open_zotero_picker ();
            });
            this.add_action (action_zotero);

            var action_doi_bib = new GLib.SimpleAction ("doi_bib_manager", null);
            action_doi_bib.activate.connect (() => {
                open_doi_bib_manager ();
            });
            this.add_action (action_doi_bib);

            var action_manage_panels = new GLib.SimpleAction ("manage_panels", null);
            action_manage_panels.activate.connect (() => {
                open_panel_manager ();
            });
            this.add_action (action_manage_panels);

            var action_ultrawide_6 = new GLib.SimpleAction ("layout_ultrawide_6", null);
            action_ultrawide_6.activate.connect (() => {
                switch_to_ultrawide_6 ();
            });
            this.add_action (action_ultrawide_6);

            var action_quad_4 = new GLib.SimpleAction ("layout_quad_4", null);
            action_quad_4.activate.connect (() => {
                var d = get_active_document ();
                if (d == null) {
                    show_toast ("Open or create a document first to switch to 4-Quadrant layout");
                    return;
                }
                Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.QUAD_4, d.dock_layout_state);
                sync_document_ui_toggles (d);
                show_toast ("Switched to 4-Quadrant Standard layout");
            });
            this.add_action (action_quad_4);

            var action_focus_mode = new GLib.SimpleAction ("toggle_focus_mode", null);
            action_focus_mode.activate.connect (() => {
                var act = this.lookup_action ("collapse_ribbon");
                if (act != null) act.activate (null);
            });
            this.add_action (action_focus_mode);

            var action_redock_all = new GLib.SimpleAction ("redock_all_panels", null);
            action_redock_all.activate.connect (() => {
                var d = get_active_document ();
                if (d != null && d.rstudio_dock_grid != null) {
                    d.rstudio_dock_grid.dock_manager.redock_all_panels ();
                    show_toast ("Re-docked all independent floating panels");
                }
            });
            this.add_action (action_redock_all);

            var action_open_web_sync = new GLib.SimpleAction ("open_web_sync", null);
            action_open_web_sync.activate.connect (() => {
                open_web_sync_panel ();
            });
            this.add_action (action_open_web_sync);

            var action_web_sync_commit = new GLib.SimpleAction ("web_sync_commit", null);
            action_web_sync_commit.activate.connect (() => {
                trigger_web_sync_quick_commit ();
            });
            this.add_action (action_web_sync_commit);

            var action_add_review = new GLib.SimpleAction ("add_review_comment", null);
            action_add_review.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.prompt_add_review_comment ();
            });
            this.add_action (action_add_review);

            var action_toggle_review = new GLib.SimpleAction ("toggle_review_comments", null);
            action_toggle_review.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.toggle_review_comments_sidebar ();
            });
            this.add_action (action_toggle_review);

            var action_qual_apply = new GLib.SimpleAction ("qual_apply_code", null);
            action_qual_apply.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_qual_code_to_selection (null);
            });
            this.add_action (action_qual_apply);

            var action_qual_memo = new GLib.SimpleAction ("qual_add_memo", null);
            action_qual_memo.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.prompt_add_qual_memo ();
            });
            this.add_action (action_qual_memo);

            var action_qual_query = new GLib.SimpleAction ("qual_raise_query", null);
            action_qual_query.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.prompt_raise_cra_query ();
            });
            this.add_action (action_qual_query);

            var action_open_qual = new GLib.SimpleAction ("open_qual_studio", null);
            action_open_qual.activate.connect (() => {
                open_qualitative_studio ();
            });
            this.add_action (action_open_qual);

            var action_open_qual_bio = new GLib.SimpleAction ("open_qual_biostats", null);
            action_open_qual_bio.activate.connect (() => {
                var d = get_active_document ();
                if (d != null && d.panel_registry != null && d.panel_registry.qual_panel != null) {
                    d.panel_registry.qual_panel.open_biostats_dashboard ();
                }
            });
            this.add_action (action_open_qual_bio);

            var action_open_help_hub = new GLib.SimpleAction ("open_help_hub", null);
            action_open_help_hub.activate.connect (() => {
                open_help_hub ();
            });
            this.add_action (action_open_help_hub);

            var action_lookup_sym = new GLib.SimpleAction ("lookup_symbol_help", null);
            action_lookup_sym.activate.connect (() => {
                var d = get_active_document ();
                if (d != null) d.lookup_symbol_at_cursor_in_help ();
            });
            this.add_action (action_lookup_sym);
        }

        public void open_qualitative_studio () {
            var d = get_active_document ();
            if (d == null) {
                add_document_tab ("analysis.qmd", "quarto");
                d = get_active_document ();
            }
            if (d == null) return;
            if (d.get_workbench_mode () != Services.LayoutMode.RSTUDIO) {
                Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
            }
            d.dock_layout_state.activate_panel (Core.Layout.PanelId.QUALITATIVE);
            d.sync_qual_spans_if_present ();
        }

        public void open_help_hub () {
            var d = get_active_document ();
            if (d == null) {
                add_document_tab ("analysis.qmd", "quarto");
                d = get_active_document ();
            }
            if (d == null) return;
            if (d.get_workbench_mode () != Services.LayoutMode.RSTUDIO) {
                Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
            }
            d.dock_layout_state.activate_panel (Core.Layout.PanelId.HELP);
        }

        private void notify_web_sync_on_save (DocumentPage doc, string editor_content) {
            if (doc.panel_registry == null || doc.panel_registry.web_sync_panel == null) return;
            string key = doc.panel_registry.web_sync_panel.get_doc_key ();
            Services.WebSyncService.get_default ().on_document_saved (key, editor_content);
            doc.panel_registry.web_sync_panel.refresh_ui ();
            update_web_sync_status_badge ();
        }

        public void update_web_sync_status_badge () {
            if (web_sync_status_btn == null) return;
            var d = get_active_document ();
            web_sync_status_btn.remove_css_class ("synced");
            web_sync_status_btn.remove_css_class ("pending");
            web_sync_status_btn.remove_css_class ("conflict");
            web_sync_status_btn.remove_css_class ("offline");

            if (d == null || d.panel_registry == null || d.panel_registry.web_sync_panel == null) {
                web_sync_status_btn.label = "Imladris Web";
                web_sync_status_btn.add_css_class ("offline");
                return;
            }
            string key = d.panel_registry.web_sync_panel.get_doc_key ();
            var svc = Services.WebSyncService.get_default ();
            var link = svc.get_link (key);
            var st = svc.get_status_for_doc (key);
            int pending = (link != null) ? link.pending_commits.size : 0;
            web_sync_status_btn.label = st.to_badge_label (pending);
            web_sync_status_btn.add_css_class (st.to_css_class ());
        }

        public void open_panel_manager () {
            var d = get_active_document ();
            if (d == null) {
                show_toast ("Open or create a document first to manage workbench panels");
                return;
            }
            if (d.get_workbench_mode () != Services.LayoutMode.RSTUDIO) {
                Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
            }
            var dlg = new UI.PanelManagerDialog (d.dock_layout_state, d.rstudio_dock_grid.dock_manager, this);
            dlg.present (this);
        }

        public void switch_to_ultrawide_6 () {
            var d = get_active_document ();
            if (d == null) {
                show_toast ("Open or create a document first to switch to 6-Quadrant Ultrawide layout");
                return;
            }
            Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
            UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.QUAD_6_ULTRAWIDE, d.dock_layout_state);
            sync_document_ui_toggles (d);
            show_toast ("Switched to 6-Quadrant Ultrawide (3×2) layout for 21:9 / 34:9 displays");
        }

        public void open_web_sync_panel () {
            var d = get_active_document ();
            if (d == null) {
                var auth_dlg = new UI.WebSyncAuthDialog ();
                auth_dlg.present (this);
                return;
            }
            if (d.get_workbench_mode () != Services.LayoutMode.RSTUDIO) {
                Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
            }
            if (d.rstudio_dock_grid.dock_manager.is_panel_undocked (Imladris.Core.Layout.PanelId.WEB_SYNC)) {
                d.rstudio_dock_grid.dock_manager.focus_undocked_panel (Imladris.Core.Layout.PanelId.WEB_SYNC);
            } else {
                d.dock_layout_state.activate_panel (Imladris.Core.Layout.PanelId.WEB_SYNC);
            }
            if (d.panel_registry != null && d.panel_registry.web_sync_panel != null) {
                d.panel_registry.web_sync_panel.refresh_ui ();
            }
        }

        public void trigger_web_sync_quick_commit () {
            var d = get_active_document ();
            if (d == null || d.panel_registry == null || d.panel_registry.web_sync_panel == null) {
                show_toast ("No active document to commit");
                return;
            }
            string key = d.panel_registry.web_sync_panel.get_doc_key ();
            var svc = Services.WebSyncService.get_default ();
            if (svc.get_link (key) == null) {
                open_web_sync_panel ();
                show_toast ("Share this document to an Imladris on Web workspace first");
                return;
            }
            var dlg = new Adw.AlertDialog (
                "Commit & Sync to Imladris on Web",
                "Enter a git-style commit message (or leave blank to auto-generate). If offline, the commit is queued locally and synced automatically when back online."
            );
            var entry = new Gtk.Entry () {
                placeholder_text = "e.g. feat(analysis): update regression model results",
                margin_start = 12, margin_end = 12, margin_top = 8, margin_bottom = 8
            };
            dlg.set_extra_child (entry);
            dlg.add_response ("cancel", "Cancel");
            dlg.add_response ("commit", "Commit & Sync");
            dlg.set_response_appearance ("commit", Adw.ResponseAppearance.SUGGESTED);
            dlg.set_default_response ("commit");
            dlg.set_close_response ("cancel");
            dlg.response.connect ((resp) => {
                if (resp == "commit") {
                    string msg = entry.text.strip ();
                    svc.commit_document_async.begin (
                        key,
                        d.get_clean_source_text (),
                        msg.length > 0 ? msg : null,
                        false,
                        false,
                        (obj, res) => {
                            try {
                                svc.commit_document_async.end (res);
                                d.panel_registry.web_sync_panel.refresh_ui ();
                                update_web_sync_status_badge ();
                            } catch (GLib.Error e) {
                                show_toast (@"Web commit failed: $(e.message)");
                            }
                        }
                    );
                }
            });
            dlg.present (this);
        }

        public void toggle_ribbon_visibility () {
            if (btn_collapse_ribbon != null) {
                btn_collapse_ribbon.active = !btn_collapse_ribbon.active;
            } else {
                ribbon_scroller.visible = !ribbon_scroller.visible;
            }
        }

        public void apply_zoom (int percent) {
            current_zoom = percent.clamp (50, 200);
            if (zoom_btn != null) {
                zoom_btn.label = @"$current_zoom%";
            }
            var d = get_active_document ();
            if (d != null) {
                d.set_zoom (current_zoom);
            }
        }

        // =====================================================================
        // 1. HOME RIBBON (Modernized Libadwaita Linked Groups)
        // =====================================================================
        private Gtk.Widget build_home_ribbon () {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

            // Group 1: Clipboard & History
            var btn_undo = RibbonFactory.create_tool_button ("edit-undo-symbolic", null, "Undo (Ctrl+Z)", false, false, true, null, "win.undo");
            var btn_redo = RibbonFactory.create_tool_button ("edit-redo-symbolic", null, "Redo (Ctrl+Shift+Z)", false, false, true, null, "win.redo");
            box.append (RibbonFactory.create_linked_group ({ btn_undo, btn_redo }));

            var btn_cut = RibbonFactory.create_tool_button ("edit-cut-symbolic", null, "Cut");
            ((Gtk.Button) btn_cut).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    Gtk.TextBuffer buf = (d.rtf_editor != null) ? d.rtf_editor.buffer : (Gtk.TextBuffer) d.source_buffer;
                    buf.cut_clipboard (d.get_clipboard (), true);
                }
            });
            var btn_copy = RibbonFactory.create_tool_button ("edit-copy-symbolic", null, "Copy");
            ((Gtk.Button) btn_copy).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    Gtk.TextBuffer buf = (d.rtf_editor != null) ? d.rtf_editor.buffer : (Gtk.TextBuffer) d.source_buffer;
                    buf.copy_clipboard (d.get_clipboard ());
                }
            });
            var btn_paste = RibbonFactory.create_tool_button ("edit-paste-symbolic", null, "Paste");
            ((Gtk.Button) btn_paste).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    Gtk.TextBuffer buf = (d.rtf_editor != null) ? d.rtf_editor.buffer : (Gtk.TextBuffer) d.source_buffer;
                    buf.paste_clipboard (d.get_clipboard (), null, true);
                }
            });
            box.append (RibbonFactory.create_linked_group ({ btn_cut, btn_copy, btn_paste }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Typography & Formatting
            var btn_bold = RibbonFactory.create_tool_button ("format-text-bold-symbolic", null, "Bold (**text**)");
            ((Gtk.Button) btn_bold).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_tag_or_syntax ("bold", "**");
            });

            var btn_italic = RibbonFactory.create_tool_button ("format-text-italic-symbolic", null, "Italic (*text*)");
            ((Gtk.Button) btn_italic).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_tag_or_syntax ("italic", "*");
            });

            var btn_under = RibbonFactory.create_tool_button ("format-text-underline-symbolic", null, "Underline (__text__)");
            ((Gtk.Button) btn_under).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_tag_or_syntax ("underline", "__");
            });

            var btn_strike = RibbonFactory.create_tool_button ("format-text-strikethrough-symbolic", null, "Strikethrough (~~text~~)");
            ((Gtk.Button) btn_strike).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_tag_or_syntax ("strikethrough", "~~");
            });

            var btn_code = RibbonFactory.create_tool_button ("utilities-terminal-symbolic", null, "Inline Code (`code`)");
            ((Gtk.Button) btn_code).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_tag_or_syntax ("code", "`");
            });

            var color_pop = PopoverFactory.create_color_palette_popover ((hex) => {
                var d = get_active_document ();
                if (d == null) return;
                if (d.rtf_editor != null) {
                    d.rtf_editor.apply_foreground_color (hex);
                } else {
                    d.source_buffer.insert_at_cursor (@"<span style=\"color:$hex;\">text</span>", -1);
                }
            });
            var btn_color = RibbonFactory.create_tool_button ("applications-graphics-symbolic", null, "Text Color", false, false, true, null, null, color_pop);

            box.append (RibbonFactory.create_linked_group ({ btn_bold, btn_italic, btn_under, btn_strike, btn_code, btn_color }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 3: Headings & Paragraph Styles
            var btn_h1 = new Gtk.Button.with_label ("H1") { tooltip_text = "Heading 1 (#)" };
            btn_h1.add_css_class ("flat");
            btn_h1.add_css_class ("ribbon-tool-btn");
            btn_h1.clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_heading (1);
            });
            var btn_h2 = new Gtk.Button.with_label ("H2") { tooltip_text = "Heading 2 (##)" };
            btn_h2.add_css_class ("flat");
            btn_h2.add_css_class ("ribbon-tool-btn");
            btn_h2.clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_heading (2);
            });
            var btn_h3 = new Gtk.Button.with_label ("H3") { tooltip_text = "Heading 3 (###)" };
            btn_h3.add_css_class ("flat");
            btn_h3.add_css_class ("ribbon-tool-btn");
            btn_h3.clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.apply_heading (3);
            });
            box.append (RibbonFactory.create_linked_group ({ btn_h1, btn_h2, btn_h3 }));

            var btn_bullet = RibbonFactory.create_tool_button ("view-list-bullet-symbolic", null, "Bullet List (- )");
            ((Gtk.Button) btn_bullet).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.insert_list_item ("- ");
            });
            var btn_number = RibbonFactory.create_tool_button ("view-list-ordered-symbolic", null, "Numbered List (1. )");
            ((Gtk.Button) btn_number).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.insert_list_item ("1. ");
            });
            var btn_quote = RibbonFactory.create_tool_button ("format-text-direction-ltr-symbolic", null, "Blockquote (> )");
            ((Gtk.Button) btn_quote).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.insert_list_item ("> ");
            });
            box.append (RibbonFactory.create_linked_group ({ btn_bullet, btn_number, btn_quote }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 4: Extensions (Obsidian-Style JSC Plugins)
            ext_separator = (Gtk.Separator) RibbonFactory.create_vseparator ();
            ext_separator.visible = false;
            box.append (ext_separator);

            extensions_ribbon_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                valign = Gtk.Align.CENTER,
                visible = false
            };
            box.append (extensions_ribbon_box);

            return box;
        }

        // =====================================================================
        // 2. INSERT RIBBON (Modernized High-Density Layout)
        // =====================================================================
        private Gtk.Widget build_insert_ribbon () {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

            // Group 1: Structure & Chunks
            var table_popover = SmartRibbonHelpers.create_table_builder_popover ((rows, cols) => {
                var d = get_active_document ();
                if (d != null) d.insert_markdown_table (rows, cols);
            });
            var btn_table = RibbonFactory.create_tool_button ("view-grid-symbolic", "Table", "Insert Markdown Table", false, false, true, null, null, table_popover);

            var code_popover = SmartRibbonHelpers.create_code_chunk_popover ((snippet) => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor (snippet, -1);
            });
            var btn_chunk = RibbonFactory.create_tool_button ("utilities-terminal-symbolic", "Code Chunk", "Insert Code Chunk", false, false, true, null, null, code_popover);

            var btn_math = RibbonFactory.create_tool_button ("insert-text-symbolic", "Math Studio", "Open Natural Math & Formula Studio (Ctrl+M)");
            ((Gtk.Button) btn_math).clicked.connect (() => {
                show_math_chem_editor_dialog (Core.FormulaMode.MATH);
            });

            var btn_chem = RibbonFactory.create_tool_button ("applications-science-symbolic", "Chem Reaction", "Open Natural Chemical Formula & Reaction Studio");
            ((Gtk.Button) btn_chem).clicked.connect (() => {
                show_math_chem_editor_dialog (Core.FormulaMode.CHEMISTRY);
            });

            box.append (RibbonFactory.create_linked_group ({ btn_table, btn_chunk, btn_math, btn_chem }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Citations, References & Footnotes
            var cite_popover = SmartRibbonHelpers.create_citation_popover ((cite) => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor (cite, -1);
            });
            var btn_cite = RibbonFactory.create_tool_button ("book-open-symbolic", "Citation", "Insert Citation (@cite)", false, false, true, null, null, cite_popover);

            var btn_xref = RibbonFactory.create_tool_button ("emblem-symbolic-link", "Cross-ref", "Insert Cross-Reference (@fig-)");
            ((Gtk.Button) btn_xref).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor ("@fig-", -1);
            });

            var btn_fn = RibbonFactory.create_tool_button ("format-text-superscript-symbolic", "Footnote", "Insert Footnote (^[])");
            ((Gtk.Button) btn_fn).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor ("^[Footnote text]", -1);
            });

            box.append (RibbonFactory.create_linked_group ({ btn_cite, btn_xref, btn_fn }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 3: Media & Web Elements
            var btn_img = RibbonFactory.create_tool_button ("insert-image-symbolic", "Image", "Insert Image from file manager");
            ((Gtk.Button) btn_img).clicked.connect (() => {
                prompt_insert_media.begin (false);
            });

            var btn_video = RibbonFactory.create_tool_button ("video-x-generic-symbolic", "Video", "Insert Video from file manager");
            ((Gtk.Button) btn_video).clicked.connect (() => {
                prompt_insert_media.begin (true);
            });

            var btn_link = RibbonFactory.create_tool_button ("insert-link-symbolic", "Hyperlink", "Insert Hyperlink");
            ((Gtk.Button) btn_link).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor ("[Link text](https://example.com)", -1);
            });

            var btn_break = RibbonFactory.create_tool_button ("view-more-horizontal-symbolic", "Divider", "Insert Horizontal Rule (---)");
            ((Gtk.Button) btn_break).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor ("\n---\n", -1);
            });

            box.append (RibbonFactory.create_linked_group ({ btn_img, btn_video, btn_link, btn_break }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 4: Symbols, Diagrams & Visuals
            var sym_popover = SmartRibbonHelpers.create_symbols_popover ((sym) => {
                insert_text_in_active (sym);
            });
            var btn_sym = RibbonFactory.create_tool_button ("character-map-symbolic", "Symbols", "Insert Math / Special Symbol", false, false, true, null, null, sym_popover);

            var emoji_popover = SmartRibbonHelpers.create_emoji_popover ((em) => {
                insert_text_in_active (em);
            });
            var btn_emoji = RibbonFactory.create_tool_button ("face-smile-symbolic", "Emoji", "Insert Emoji", false, false, true, null, null, emoji_popover);

            var btn_mermaid = RibbonFactory.create_tool_button ("view-list-symbolic", "Mermaid Flow", "Open Visual Flow & Mindmap Studio (Ctrl+Shift+D)");
            ((Gtk.Button) btn_mermaid).clicked.connect (() => {
                show_mermaid_flow_studio_dialog ();
            });

            var btn_plot = RibbonFactory.create_tool_button ("x-office-presentation-symbolic", "ggplot", "Insert ggplot2 snippet");
            ((Gtk.Button) btn_plot).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor ("\n```{r}\n#| label: fig-plot\n#| fig-cap: 'Scatter Plot'\nlibrary(ggplot2)\nggplot(mtcars, aes(x = wt, y = mpg)) + geom_point()\n```\n", -1);
            });

            box.append (RibbonFactory.create_linked_group ({ btn_sym, btn_emoji, btn_mermaid, btn_plot }));

            return box;
        }

        // =====================================================================
        // 3. COMPUTATION RIBBON (Polyglot R, Python & Quarto)
        // =====================================================================
        private Gtk.Widget build_computation_ribbon () {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

            // Group 1: Insert Code Chunks
            btn_insert_r = RibbonFactory.create_tool_button ("utilities-terminal-symbolic", "R Chunk", "Insert R Code Chunk ({r})");
            ((Gtk.Button) btn_insert_r).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.insert_code_chunk ("r", "echo: true");
            });

            btn_insert_py = RibbonFactory.create_tool_button ("utilities-terminal-symbolic", "Python Chunk", "Insert Python Code Chunk ({python})");
            ((Gtk.Button) btn_insert_py).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.insert_code_chunk ("python", "echo: true");
            });

            box.append (RibbonFactory.create_linked_group ({ btn_insert_r, btn_insert_py }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Chunk Execution Controls
            btn_run_chunk = RibbonFactory.create_tool_button ("media-playback-start-symbolic", "Run Chunk", "Run Active Chunk (Ctrl+Shift+Enter)");
            ((Gtk.Button) btn_run_chunk).clicked.connect (() => {
                run_active_chunk ();
            });

            btn_run_all = RibbonFactory.create_tool_button ("media-seek-forward-symbolic", "Run All", "Run All Chunks in Document");
            ((Gtk.Button) btn_run_all).clicked.connect (() => {
                run_all_chunks ();
            });

            btn_run_above = RibbonFactory.create_tool_button ("media-skip-backward-symbolic", "Run Above", "Run All Chunks Above (Ctrl+Alt+P)");
            ((Gtk.Button) btn_run_above).clicked.connect (() => {
                run_chunks_above ();
            });

            btn_run_below = RibbonFactory.create_tool_button ("media-skip-forward-symbolic", "Run Below", "Run Active and Below Chunks");
            ((Gtk.Button) btn_run_below).clicked.connect (() => {
                run_chunks_below ();
            });

            box.append (RibbonFactory.create_linked_group ({ btn_run_chunk, btn_run_all, btn_run_above, btn_run_below }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 3: Script Execution Controls
            btn_run_line = RibbonFactory.create_tool_button ("media-playback-start-symbolic", "Run Line", "Run Current Line or Selection (Ctrl+Enter)");
            ((Gtk.Button) btn_run_line).clicked.connect (() => {
                run_line_or_selection ();
            });

            btn_source_file = RibbonFactory.create_tool_button ("document-send-symbolic", "Source", "Source Entire File in Kernel");
            ((Gtk.Button) btn_source_file).clicked.connect (() => {
                source_active_file ();
            });

            btn_interrupt = RibbonFactory.create_tool_button ("process-stop-symbolic", "Interrupt", "Interrupt Active Execution (SIGINT)");
            ((Gtk.Button) btn_interrupt).clicked.connect (() => {
                interrupt_active_execution ();
            });

            box.append (RibbonFactory.create_linked_group ({ btn_run_line, btn_source_file, btn_interrupt }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 4: Package Manager & Environment Sandboxing
            btn_restart_kernel = RibbonFactory.create_tool_button ("system-run-symbolic", "Restart Kernel", "Restart Active Kernel Sessions");
            ((Gtk.Button) btn_restart_kernel).clicked.connect (() => {
                restart_active_kernel ();
            });

            btn_package_installer = RibbonFactory.create_tool_button ("software-properties-symbolic", "Packages", "Package Manager (CRAN / Bioconductor / PyPI - Ctrl+Alt+K)");
            ((Gtk.Button) btn_package_installer).clicked.connect (() => {
                show_package_installer_dialog ();
            });

            btn_snapshot_env = RibbonFactory.create_tool_button ("security-high-symbolic", "Snapshot", "Snapshot Environment Lockfile (renv/venv)");
            ((Gtk.Button) btn_snapshot_env).clicked.connect (() => {
                snapshot_current_environment ();
            });

            btn_restore_env = RibbonFactory.create_tool_button ("view-refresh-symbolic", "Restore", "Restore Environment from Lockfile");
            ((Gtk.Button) btn_restore_env).clicked.connect (() => {
                restore_current_environment ();
            });

            var btn_toolchains = RibbonFactory.create_tool_button ("preferences-system-symbolic", "Toolchains", "Automated R, Python & Quarto Toolchain Setup");
            ((Gtk.Button) btn_toolchains).clicked.connect (() => {
                show_toolchain_setup_dialog ();
            });

            box.append (RibbonFactory.create_linked_group ({ btn_restart_kernel, btn_package_installer, btn_snapshot_env, btn_restore_env, btn_toolchains }));
            box.append (RibbonFactory.create_vseparator ());
            // Group 4 removed: Elrond Assistance is in the top tab bar and Ctrl+Shift+E

            return box;
        }

        // =====================================================================
        // 4. PUBLISH RIBBON (Export Pipeline, WebKit Preview & Artifacts)
        // =====================================================================
        private Gtk.Widget build_publish_ribbon () {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

            // Group 1: Primary Document Render & Export
            btn_render_html = RibbonFactory.create_tool_button ("applications-internet-symbolic", "HTML", "Render Document to HTML", false, false, true, null, "app.export_html");
            btn_render_pdf = RibbonFactory.create_tool_button ("document-send-symbolic", "PDF", "Render Document to PDF", false, false, true, null, "app.export_pdf");
            btn_export_odt = RibbonFactory.create_tool_button ("x-office-document-symbolic", "ODT", "Export to OpenDocument Text (.odt)", false, false, true, null, "app.export_odt");
            btn_export_odp = RibbonFactory.create_tool_button ("x-office-presentation-symbolic", "ODP", "Export to OpenDocument Presentation (.odp)", false, false, true, null, "app.export_odp");
            btn_export_rtf = RibbonFactory.create_tool_button ("document-save-as-symbolic", "RTF", "Export to Rich Text Format (.rtf)", false, false, true, null, "app.export_rtf");

            box.append (RibbonFactory.create_linked_group ({ btn_render_html, btn_render_pdf, btn_export_odt, btn_export_odp, btn_export_rtf }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Interoperability & Reproducibility Exports
            btn_export_mallorn = RibbonFactory.create_tool_button ("package-x-generic-symbolic", ".mallorn", "Export Portable .mallorn Bundle (1:1 RStudio & Sandboxed renv/venv)", false, false, true, null, "app.export_mallorn");
            btn_export_rstudio = RibbonFactory.create_tool_button ("utilities-terminal-symbolic", "RStudio", "Export Project for RStudio", false, false, true, null, "app.export_rstudio");
            btn_export_jupyter = RibbonFactory.create_tool_button ("applications-science-symbolic", "Jupyter", "Export Project for Jupyter Notebook", false, false, true, null, "app.export_jupyter");

            var btn_gxp_lock = RibbonFactory.create_tool_button ("security-high-symbolic", "GxP Lock", "Generate Cryptographic GxP SHA-256 Provenance Manifest");
            ((Gtk.Button) btn_gxp_lock).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    string s_path = d.file_location != null ? d.file_location.get_path () : "/tmp/document.qmd";
                    string pdir = (current_project_dir != "") ? current_project_dir : GLib.Path.get_dirname (s_path);
                    Core.ProvenanceAttestationService.generate_attestation_async.begin (
                        s_path,
                        d.get_clean_source_text (),
                        pdir,
                        (obj, att_res) => {
                            try {
                                string manifest_path = Core.ProvenanceAttestationService.generate_attestation_async.end (att_res);
                                d.append_console_log (@"🔒 [GxP Provenance Lockfile Generated: $manifest_path]");
                                show_toast (@"Generated $(GLib.Path.get_basename (manifest_path))");
                            } catch (GLib.Error err) {
                                d.append_console_log (@"✖ Failed to generate provenance manifest: $(err.message)");
                                show_toast (@"Provenance error: $(err.message)");
                            }
                        }
                    );
                } else {
                    show_toast ("No active document for provenance generation");
                }
            });

            box.append (RibbonFactory.create_linked_group ({ btn_export_mallorn, btn_export_rstudio, btn_export_jupyter, btn_gxp_lock }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 3: Live Preview & Diagnostics
            btn_live_preview = RibbonFactory.create_tool_button ("view-refresh-symbolic", "Live Preview", "Render and Open Live WebKit Preview");
            ((Gtk.Button) btn_live_preview).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.show_live_preview ();
            });
            box.append (btn_live_preview);

            btn_preview = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-dual-symbolic", "Side Panel", "Toggle Focus Mode Side Panel (Preview / Elrond)", true, true, true);
            btn_preview.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                var d = get_active_document ();
                if (d != null) {
                    if (btn_preview.active) {
                        d.console_revealer.visible = true;
                    }
                    d.console_revealer.reveal_child = btn_preview.active;
                }
            });
            box.append (btn_preview);
            box.append (RibbonFactory.create_vseparator ());

            // Group 4: Imladris on Web Integration (Share, Offline Git-Style Commits & Auto-Sync)
            var btn_web_share = RibbonFactory.create_tool_button (
                "network-server-symbolic",
                "Imladris Web",
                "Share document to Imladris on Web & manage offline git-style sync (Ctrl+Shift+W)",
                false,
                false,
                true,
                null,
                "win.open_web_sync"
            );
            var btn_web_commit = RibbonFactory.create_tool_button (
                "document-send-symbolic",
                "Commit & Sync",
                "Create a git-style commit checkpoint and push to Imladris on Web (or queue offline)",
                false,
                false,
                true,
                null,
                "win.web_sync_commit"
            );
            box.append (RibbonFactory.create_linked_group ({ btn_web_share, btn_web_commit }));

            return box;
        }

        /**
         * Pillar 2: Context-Aware Ribbon State Machine
         * Dynamically adapts visible and sensitive states based on active Project Type and Document Format
         */
        public void update_ribbon_state_machine (DocumentFormat fmt, ProjectType ptype) {
            var profile = Core.FormatProfile.for_format (fmt);
            bool is_sandboxed = (ptype == ProjectType.SANDBOXED);
            bool has_pages = (tab_view != null && tab_view.n_pages > 0);
            bool is_notebook = profile.supports_chunks;
            bool is_script = (fmt == DocumentFormat.RSCRIPT || fmt == DocumentFormat.PYSCRIPT || fmt == DocumentFormat.TS);
            bool is_md = (fmt == DocumentFormat.MD);
            bool is_html = (fmt == DocumentFormat.HTML);
            bool is_tex = (fmt == DocumentFormat.TEX);

            // HeaderBar format adaptation
            if (btn_render_quarto != null && render_content != null) {
                bool show_primary = has_pages && (profile.header_action_kind != Core.HeaderActionKind.NONE);
                btn_render_quarto.visible = show_primary;
                if (show_primary) {
                    render_content.label = profile.primary_action_label;
                    render_content.icon_name = profile.primary_action_icon;
                    btn_render_quarto.tooltip_text = profile.primary_action_tooltip;
                }
            }
            if (export_format_selector != null) {
                string[] targets = profile.get_export_targets ();
                bool show_selector = has_pages && (targets.length > 0);
                export_format_selector.visible = show_selector;
                if (show_selector) {
                    export_format_selector.model = new Gtk.StringList (targets);
                    export_format_selector.selected = 0;
                }
            }

            // 1. Insert Chunks
            if (btn_insert_r != null) {
                btn_insert_r.visible = is_notebook;
                btn_insert_r.sensitive = is_notebook;
            }
            if (btn_insert_py != null) {
                btn_insert_py.visible = is_notebook;
                btn_insert_py.sensitive = is_notebook;
            }

            // 2. Chunk Execution Controls
            if (btn_run_chunk != null) {
                btn_run_chunk.visible = is_notebook;
                btn_run_chunk.sensitive = is_notebook;
            }
            if (btn_run_all != null) {
                btn_run_all.visible = is_notebook || is_tex || is_script;
                btn_run_all.sensitive = is_notebook || is_tex || is_script;
            }
            if (btn_run_above != null) {
                btn_run_above.visible = is_notebook;
                btn_run_above.sensitive = is_notebook;
            }
            if (btn_run_below != null) {
                btn_run_below.visible = is_notebook;
                btn_run_below.sensitive = is_notebook;
            }

            // 3. Script / Compile Execution Controls
            if (btn_run_line != null) {
                btn_run_line.visible = is_script || is_notebook;
                btn_run_line.sensitive = is_script || is_notebook;
            }
            if (btn_source_file != null) {
                btn_source_file.visible = is_script || is_notebook || is_tex;
                btn_source_file.sensitive = is_script || is_notebook || is_tex;
            }
            if (btn_interrupt != null) {
                btn_interrupt.visible = is_script || is_notebook || is_tex;
                btn_interrupt.sensitive = is_script || is_notebook || is_tex;
            }

            // 4. Kernel / Persistent Sessions
            if (btn_restart_kernel != null) {
                btn_restart_kernel.visible = is_notebook || (fmt == DocumentFormat.RSCRIPT || fmt == DocumentFormat.PYSCRIPT);
                btn_restart_kernel.sensitive = btn_restart_kernel.visible;
            }

            // 5. Package Installer
            if (btn_package_installer != null) {
                btn_package_installer.visible = profile.supports_packages_tab;
                btn_package_installer.sensitive = profile.supports_packages_tab;
            }

            // 6. Snapshot & Restore Environment
            if (btn_snapshot_env != null) {
                btn_snapshot_env.visible = is_notebook || ((fmt == DocumentFormat.RSCRIPT || fmt == DocumentFormat.PYSCRIPT) && is_sandboxed);
                btn_snapshot_env.sensitive = is_sandboxed;
                btn_snapshot_env.tooltip_text = is_sandboxed
                    ? "Lock environment package versions (renv::snapshot / pip freeze)"
                    : "Only available in Sandboxed Projects";
            }
            if (btn_restore_env != null) {
                btn_restore_env.visible = is_notebook || ((fmt == DocumentFormat.RSCRIPT || fmt == DocumentFormat.PYSCRIPT) && is_sandboxed);
                btn_restore_env.sensitive = is_sandboxed;
                btn_restore_env.tooltip_text = is_sandboxed
                    ? "Restore exact package versions from lockfile (renv::restore / pip install -r)"
                    : "Only available in Sandboxed Projects";
            }

            // 7. Knit / Render / Export
            if (btn_render_html != null) {
                btn_render_html.visible = profile.supports_live_preview || is_tex;
                btn_render_html.sensitive = profile.supports_live_preview || is_tex;
            }
            if (btn_render_pdf != null) {
                btn_render_pdf.visible = is_notebook || is_md || is_tex || is_html || fmt == DocumentFormat.RTF;
                btn_render_pdf.sensitive = btn_render_pdf.visible;
            }
            if (btn_export_odt != null) {
                btn_export_odt.visible = is_md || is_notebook || fmt == DocumentFormat.RTF;
                btn_export_odt.sensitive = btn_export_odt.visible;
            }
            if (btn_export_odp != null) {
                btn_export_odp.visible = is_md || is_notebook;
                btn_export_odp.sensitive = is_md || is_notebook;
            }
            if (btn_export_rtf != null) {
                btn_export_rtf.visible = is_md || is_notebook;
                btn_export_rtf.sensitive = is_md || is_notebook;
            }
            if (btn_export_mallorn != null) {
                btn_export_mallorn.visible = is_notebook;
                btn_export_mallorn.sensitive = is_notebook;
            }
            if (btn_export_rstudio != null) {
                btn_export_rstudio.visible = is_notebook;
                btn_export_rstudio.sensitive = is_notebook;
            }
            if (btn_export_jupyter != null) {
                btn_export_jupyter.visible = is_notebook;
                btn_export_jupyter.sensitive = is_notebook;
            }

            // 8. Live preview
            if (btn_live_preview != null) {
                btn_live_preview.visible = profile.supports_live_preview;
                btn_live_preview.sensitive = profile.supports_live_preview;
            }

            // 9. Contextual Ribbon Tabs (Run, Publish, Packages)
            bool show_run_tab = (profile.ribbon_run_mode != Core.RibbonRunMode.HIDDEN);
            if (tab_btn_run != null) {
                tab_btn_run.visible = show_run_tab;
                tab_btn_run.sensitive = show_run_tab;
                if (!show_run_tab && tab_btn_run.active && tab_btn_home != null) {
                    tab_btn_home.active = true;
                }
            }
            if (tab_btn_publish != null) {
                tab_btn_publish.visible = profile.supports_publish_tab;
                tab_btn_publish.sensitive = profile.supports_publish_tab;
                if (!profile.supports_publish_tab && tab_btn_publish.active && tab_btn_home != null) {
                    tab_btn_home.active = true;
                }
            }
            if (tab_btn_packages != null) {
                tab_btn_packages.visible = profile.supports_packages_tab;
                tab_btn_packages.sensitive = profile.supports_packages_tab;
                if (!profile.supports_packages_tab && tab_btn_packages.active && tab_btn_home != null) {
                    tab_btn_home.active = true;
                }
            }
            if (packages_ribbon_bar != null) {
                string pdir = current_project_dir != "" ? current_project_dir : Services.PersistentSessionManager.get_default ().current_working_dir;
                if (pdir == "") pdir = GLib.Environment.get_current_dir ();
                packages_ribbon_bar.project_root = pdir;
                packages_ribbon_bar.is_sandboxed = is_sandboxed;
                packages_ribbon_bar.update_target_badge ();
            }
        }

        public void show_toast (string message) {
            if (toast_overlay != null) {
                toast_overlay.add_toast (new Adw.Toast (message));
            }
        }

        public void show_toast_with_action (string message, string button_label, string action_name) {
            if (toast_overlay != null) {
                var toast = new Adw.Toast (message) {
                    button_label = button_label,
                    action_name = action_name
                };
                toast_overlay.add_toast (toast);
            }
        }

        // Action Handlers for Pillars 2, 3, 4
        public void show_package_installer_dialog () {
            if (tab_btn_packages != null) {
                tab_btn_packages.visible = true;
                tab_btn_packages.active = true;
                if (btn_collapse_ribbon != null && !btn_collapse_ribbon.active) {
                    btn_collapse_ribbon.active = true;
                }
                var doc = get_active_document ();
                var fmt = DocumentFormat.QMD;
                if (doc != null) {
                    fmt = doc.get_document_format ();
                }
                bool is_py = (fmt == DocumentFormat.PYSCRIPT || fmt == DocumentFormat.IPYNB);
                if (packages_ribbon_bar != null) {
                    packages_ribbon_bar.focus_search (is_py);
                }
            }
        }

        public async void run_r_install_and_snapshot (string r_cmd, string display_label) {
            var doc = get_active_document ();
            var sess = (doc != null) ? doc.panel_registry.get_session_manager () : Services.PersistentSessionManager.get_default ();
            if (doc != null) {
                doc.append_console_log (@"▶ [R] Executing: $r_cmd");
            }
            if (packages_ribbon_bar != null) {
                packages_ribbon_bar.set_r_busy (true, display_label);
            }

            string? plot_file = null;
            ulong sig_id = 0;
            sig_id = sess.session_output_received.connect ((eng, line, is_err) => {
                if (eng == "r" && doc != null) {
                    doc.append_console_log (line);
                }
            });

            try {
                string output = yield sess.execute_r (r_cmd, out plot_file);
                string trimmed_out = output.strip ();
                if (doc != null && trimmed_out.length > 0) {
                    doc.append_console_log (trimmed_out);
                }
                bool has_err = trimmed_out.contains ("✖") || trimmed_out.contains ("Error:") ||
                    trimmed_out.contains ("ERROR:") || trimmed_out.contains ("non-zero exit status");
                if (has_err) {
                    if (doc != null) {
                        doc.append_console_log (@"✖ R package installation failed for $display_label.");
                    }
                    show_toast (@"R package installation failed for $display_label (see console)");
                } else {
                    if (doc != null) {
                        doc.append_console_log (@"✔ R package installation finished for $display_label.");
                    }
                    show_toast (@"Successfully installed $display_label");
                }
            } finally {
                sess.disconnect (sig_id);
                if (packages_ribbon_bar != null) {
                    packages_ribbon_bar.set_r_busy (false, display_label);
                }
            }
        }

        public void show_toolchain_setup_dialog (bool start_installation = false, bool is_first_run = false) {
            var dlg = new UI.ToolchainSetupDialog (is_first_run);
            dlg.installation_completed.connect (() => {
                var doc = get_active_document ();
                if (doc != null) {
                    doc.append_console_log ("✔ Data Science Toolchain installed and verified. Ready to execute code.");
                }
            });
            dlg.present (this);
            if (start_installation) {
                GLib.Idle.add (() => {
                    dlg.start_installation ();
                    return GLib.Source.REMOVE;
                });
            }
        }

        public void show_about_dialog () {
            string[] devs = { "Antonio De Gaetano <https://github.com/Antux912012>" };
            var dialog = new Adw.AboutDialog () {
                application_name = "Imladris",
                application_icon = "io.github.Antux912012.Imladris",
                version = Application.APP_VERSION,
                developer_name = "Antonio De Gaetano",
                developers = devs,
                copyright = "© 2026 Antonio De Gaetano",
                license_type = Gtk.License.APACHE_2_0,
                website = "https://antux912012.github.io/imladris/",
                issue_url = "https://github.com/Antux912012/imladris/issues",
                support_url = "https://github.com/Antux912012/imladris/discussions",
                comments = "Native Linux scientific notebook studio for Quarto, R, Python, and Jupyter.\n\nEngineered in compiled Vala and GTK4 with 4-quadrant workbench ergonomics, VS Code & RStudio-grade autocompletion, quick table authoring, multi-tier AI quota failover, and domain bridges for bioinformatics and biostatistics.\n\nCore studio licensed under Apache-2.0 (Hybrid Open-Core for Academic & Enterprise R&D).\n\n✨ Developed with Google Gemini and Anthropic Claude AI pair-programming assistance."
            };

            dialog.add_link ("Architecture Blueprint", "https://github.com/Antux912012/imladris/blob/main/docs/ARCHITECTURE.md");
            dialog.add_link ("Project Documentation", "https://github.com/Antux912012/imladris#readme");
            dialog.add_link ("Technical Wiki", "https://github.com/Antux912012/imladris/wiki");
            dialog.add_link ("Flatpak Package (FlatPark)", "https://flatpark.org/apps/io.github.Antux912012.Imladris/");
            dialog.add_link ("Author GitHub Profile (@Antux912012)", "https://github.com/Antux912012");
            dialog.add_link ("Imladris Repository on GitHub", "https://github.com/Antux912012/imladris");

            dialog.add_credit_section ("AI Pair Programming", {
                "Google Gemini (AI pair programming and source/documentation auditing)",
                "Anthropic Claude (AI pair programming and source/documentation auditing)"
            });

            dialog.add_acknowledgement_section ("Inspiration & Ecosystem", {
                "RStudio & Posit (Workbench ergonomics, DCF & Mallorn project models)",
                "Apostrophe (Distraction-free Markdown writing)",
                "Python Software Foundation & Project Jupyter (Interactive computing & REPL)",
                "The R Foundation & CRAN (Statistical computing & reproducible packages)",
                "The Galaxy Project (Cloud genomics and scientific workflow integration)",
                "DeepMind & EMBL-EBI (AlphaFold Protein Structure Database)",
                "LM Studio & Ollama (Local open-weights AI inference)",
                "llama.cpp & Georgi Gerganov (Local LLM runtime)",
                "GitHub Copilot (AI pair programmer OAuth integration)",
                "Quarto & Pandoc (Scientific publishing pipeline)",
                "Zotero & BetterBibTeX (Reference & CSL citation management)",
                "KaTeX & Mermaid.js (Mathematical typesetting and flow diagrams)",
                "GNOME & Libadwaita Teams (Modern design language and components)",
                "Papirus Development Team (Bundled Papirus symbolic icons — GPL-3.0-or-later)"
            });

            dialog.present (this);
        }

        public async void prompt_insert_media (bool is_video) {
            var doc = get_active_document ();
            if (doc == null) return;

            var file_dialog = new Gtk.FileDialog () {
                title = is_video ? "Insert Video into Document" : "Insert Image into Document"
            };

            var filter_list = new GLib.ListStore (typeof (Gtk.FileFilter));

            if (!is_video) {
                var img_filter = new Gtk.FileFilter () { name = "Image Files (*.png, *.jpg, *.svg, *.webp, *.gif)" };
                img_filter.add_pattern ("*.png");
                img_filter.add_pattern ("*.jpg");
                img_filter.add_pattern ("*.jpeg");
                img_filter.add_pattern ("*.svg");
                img_filter.add_pattern ("*.webp");
                img_filter.add_pattern ("*.gif");
                img_filter.add_pattern ("*.bmp");
                img_filter.add_pattern ("*.avif");
                img_filter.add_pattern ("*.PNG");
                img_filter.add_pattern ("*.JPG");
                img_filter.add_pattern ("*.JPEG");
                img_filter.add_pattern ("*.SVG");
                filter_list.append (img_filter);
            } else {
                var vid_filter = new Gtk.FileFilter () { name = "Video Files (*.mp4, *.webm, *.ogg, *.mov, *.mkv)" };
                vid_filter.add_pattern ("*.mp4");
                vid_filter.add_pattern ("*.webm");
                vid_filter.add_pattern ("*.ogg");
                vid_filter.add_pattern ("*.mov");
                vid_filter.add_pattern ("*.mkv");
                vid_filter.add_pattern ("*.m4v");
                vid_filter.add_pattern ("*.MP4");
                vid_filter.add_pattern ("*.WEBM");
                filter_list.append (vid_filter);
            }

            var all_filter = new Gtk.FileFilter () { name = "All Files (*.*)" };
            all_filter.add_pattern ("*");
            filter_list.append (all_filter);

            file_dialog.filters = filter_list;

            if (doc.file_location != null) {
                file_dialog.initial_folder = doc.file_location.get_parent ();
            } else if (current_project_dir != "" && FileUtils.test (current_project_dir, FileTest.IS_DIR)) {
                file_dialog.initial_folder = File.new_for_path (current_project_dir);
            }

            try {
                var selected_file = yield file_dialog.open (this, null);
                if (selected_file != null) {
                    string src_path = selected_file.get_path ();
                    if (src_path != null) {
                        string? pdir = (current_project_dir != "") ? current_project_dir : null;
                        bool sandboxed = (current_project_type == ProjectType.SANDBOXED);
                        string? doc_path = (doc.file_location != null) ? doc.file_location.get_path () : null;
                        string sel_caption = doc.get_selected_text ();

                        string snippet = Services.MediaHelper.process_and_link_media (
                            src_path,
                            pdir,
                            sandboxed,
                            doc_path,
                            is_video,
                            sel_caption
                        );

                        doc.insert_media_snippet (snippet);
                    }
                }
            } catch (Error e) {
                // User cancelled or dialog closed
            }
        }

        public async void run_python_pip_and_snapshot (string py_bin, string[] args, string working_dir, bool sandboxed, string display_label = "") {
            var doc = get_active_document ();
            if (doc != null) {
                string cmd_disp = string.joinv (" ", args);
                string tag = args.length > 0 && args[0].contains ("uv") ? "Python/uv" : "Python/pip";
                doc.append_console_log (@"▶ [$tag] Executing: $cmd_disp");
            }
            if (packages_ribbon_bar != null && display_label != "") {
                packages_ribbon_bar.set_python_busy (true, display_label);
            }

            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                if (working_dir != "" && GLib.FileUtils.test (working_dir, GLib.FileTest.IS_DIR)) {
                    launcher.set_cwd (working_dir);
                }

                string[] spawn_args = args;
                if (Core.PlatformUtils.is_flatpak ()) {
                    if (args.length > 0 && GLib.Environment.find_program_in_path (args[0]) == null) {
                        spawn_args = Core.PlatformUtils.build_host_command (args, working_dir);
                    }
                }

                var proc = launcher.spawnv (spawn_args);
                var dis = new GLib.DataInputStream (proc.get_stdout_pipe ());
                string? line = null;
                while ((line = yield dis.read_line_async (GLib.Priority.DEFAULT, null)) != null) {
                    if (doc != null && line.strip ().length > 0) {
                        doc.append_console_log (line);
                    }
                }
                yield proc.wait_async (null);

                if (proc.get_successful ()) {
                    if (doc != null) {
                        doc.append_console_log ("✔ Package installation finished.");
                    }
                    if (display_label != "") {
                        show_toast (@"Successfully installed $display_label");
                    }
                    if (sandboxed && working_dir != "") {
                        Services.SandboxController.snapshot_environment (working_dir);
                        if (doc != null) {
                            doc.append_console_log ("✔ Sandboxed project requirements.txt updated.");
                        }
                    }
                } else {
                    if (doc != null) {
                        doc.append_console_log (@"✖ Installation failed for $display_label (exit code: $(proc.get_exit_status ()))");
                    }
                    if (display_label != "") {
                        show_toast (@"Installation failed for $display_label");
                    }
                }
            } catch (GLib.Error e) {
                if (doc != null) {
                    doc.append_console_log (@"✖ Package installer error: $(e.message)");
                }
                if (display_label != "") {
                    show_toast (@"Installation error: $(e.message)");
                }
            } finally {
                if (packages_ribbon_bar != null && display_label != "") {
                    packages_ribbon_bar.set_python_busy (false, display_label);
                }
            }
        }

        public void snapshot_current_environment () {
            if (current_project_type != ProjectType.SANDBOXED) {
                var doc = get_active_document ();
                if (doc != null) {
                    doc.append_console_log ("⚠ Environment snapshot is only available in Sandboxed Projects.");
                }
                return;
            }
            string pdir = current_project_dir != "" ? current_project_dir : GLib.Environment.get_current_dir ();
            var doc = get_active_document ();
            try {
                Services.SandboxController.snapshot_environment (pdir);
                if (doc != null) {
                    doc.append_console_log (@"✔ Environment lockfile snapshotted in $pdir");
                }
            } catch (GLib.Error e) {
                if (doc != null) {
                    doc.append_console_log (@"✖ Snapshot error: $(e.message)");
                }
            }
        }

        public void restore_current_environment () {
            if (current_project_type != ProjectType.SANDBOXED) {
                var doc = get_active_document ();
                if (doc != null) {
                    doc.append_console_log ("⚠ Environment restore is only available in Sandboxed Projects.");
                }
                return;
            }
            string pdir = current_project_dir != "" ? current_project_dir : GLib.Environment.get_current_dir ();
            var doc = get_active_document ();
            try {
                Services.SandboxController.restore_environment (pdir);
                if (doc != null) {
                    doc.append_console_log (@"✔ Restoring isolated packages in $pdir (renv / venv)...");
                }
            } catch (GLib.Error e) {
                if (doc != null) {
                    doc.append_console_log (@"✖ Restore error: $(e.message)");
                }
            }
        }

        public void toggle_shiny_app_execution () {
            var service = Services.ShinyService.get_default ();
            if (service.status == Services.ShinyAppStatus.RUNNING || service.status == Services.ShinyAppStatus.STARTING) {
                service.stop_app ();
                var d = get_active_document ();
                if (d != null) d.append_console_log ("⏹ Stopped Shiny Web Application.");
            } else {
                var doc = get_active_document ();
                string target_path = "";
                if (doc != null && doc.file_location != null) {
                    target_path = doc.file_location.get_path ();
                } else if (current_project_dir != "") {
                    target_path = current_project_dir;
                } else if (doc != null) {
                    string tmp_dir = Core.PlatformUtils.get_shared_cache_dir ("tmp");
                    string tmp_app = GLib.Path.build_filename (tmp_dir, "app.R");
                    try {
                        GLib.FileUtils.set_contents (tmp_app, doc.get_clean_source_text ());
                        target_path = tmp_app;
                    } catch (GLib.Error e) {
                        doc.append_console_log (@"✖ Failed to write temporary app.R: $(e.message)");
                        return;
                    }
                }
                if (target_path != "") {
                    if (doc != null) {
                        doc.append_console_log (@"⚡ Launching Shiny Web Application from $target_path...");
                    }
                    service.launch_app_async.begin (target_path, service.current_target);
                }
            }
        }

        public void restart_active_kernel () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.panel_registry.get_session_manager ().restart_all_sessions ();
                doc.append_console_log ("✔ Active persistent R and Python sessions restarted.");
            } else {
                Services.PersistentSessionManager.get_default ().restart_all_sessions ();
            }
        }

        public void interrupt_active_execution () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.panel_registry.get_session_manager ().interrupt_active_execution ();
                doc.append_console_log ("⏹ Execution interrupted (SIGINT sent).");
            } else {
                Services.PersistentSessionManager.get_default ().interrupt_active_execution ();
            }
        }

        public void run_line_or_selection () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.panel_registry.execute_current_line_or_selection ();
            }
        }

        public void run_active_chunk () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.panel_registry.execute_active_cell ();
            }
        }

        public void run_all_chunks () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.panel_registry.execute_all_cells ();
            }
        }

        public void run_chunks_above () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.run_chunks_above ();
            }
        }

        public void run_chunks_below () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.run_chunks_below ();
            }
        }

        public void show_math_chem_editor_dialog (Core.FormulaMode initial_mode = Core.FormulaMode.AUTO) {
            string sel = get_active_selected_text ();
            var dlg = new UI.MathChemEditorDialog (initial_mode, sel.length > 0 ? sel : null);
            dlg.formula_inserted.connect ((formatted_output, save_document) => {
                var doc = get_active_document ();
                if (doc == null) {
                    add_document_tab ("Formulas.qmd", "markdown");
                    doc = get_active_document ();
                }
                if (doc != null) {
                    Gtk.TextBuffer buf = (doc.rtf_editor != null) ? doc.rtf_editor.buffer : (Gtk.TextBuffer) doc.source_buffer;
                    buf.begin_user_action ();
                    Gtk.TextIter start, end;
                    if (buf.get_selection_bounds (out start, out end)) {
                        buf.delete (ref start, ref end);
                        buf.insert (ref start, formatted_output, formatted_output.length);
                    } else {
                        buf.insert_at_cursor (formatted_output, formatted_output.length);
                    }
                    buf.end_user_action ();
                    doc.refresh_live_preview ();
                    show_toast ("Inserted formula into document");
                    if (save_document) {
                        save_document_async.begin ();
                    }
                }
            });
            dlg.present (this);
        }

        public void show_mermaid_flow_studio_dialog () {
            string sel = get_active_selected_text ();
            var dlg = new UI.MermaidFlowStudioDialog (sel.length > 0 ? sel : null);
            dlg.diagram_inserted.connect ((formatted_mermaid, save_document) => {
                var doc = get_active_document ();
                if (doc == null) {
                    add_document_tab ("Diagram.qmd", "markdown");
                    doc = get_active_document ();
                }
                if (doc != null) {
                    Gtk.TextBuffer buf = (doc.rtf_editor != null) ? doc.rtf_editor.buffer : (Gtk.TextBuffer) doc.source_buffer;
                    buf.begin_user_action ();
                    Gtk.TextIter start, end;
                    if (buf.get_selection_bounds (out start, out end)) {
                        buf.delete (ref start, ref end);
                        buf.insert (ref start, formatted_mermaid, formatted_mermaid.length);
                    } else {
                        buf.insert_at_cursor (formatted_mermaid, formatted_mermaid.length);
                    }
                    buf.end_user_action ();
                    doc.refresh_live_preview ();
                    show_toast ("Inserted Mermaid diagram into document");
                    if (save_document) {
                        save_document_async.begin ();
                    }
                }
            });
            dlg.present (this);
        }

        public void print_active_document () {
            var doc = get_active_document ();
            if (doc != null && doc.web_view != null) {
                var print_op = new WebKit.PrintOperation (doc.web_view);
                print_op.run_dialog (this);
            }
        }

        public void clear_console () {
            var doc = get_active_document ();
            if (doc != null) {
                doc.clear_console ();
            }
        }

        public void toggle_active_line_comment () {
            var doc = get_active_document ();
            if (doc == null) return;
            var buf = doc.source_buffer;
            var fmt = doc.get_document_format ();
            var profile = Core.FormatProfile.for_format (fmt);

            Gtk.TextIter cursor;
            buf.get_iter_at_mark (out cursor, buf.get_insert ());
            int cursor_line = cursor.get_line ();
            Gtk.TextIter line_start = cursor;
            line_start.set_line_offset (0);
            Gtk.TextIter line_end = line_start;
            if (!line_end.ends_line ()) {
                line_end.forward_to_line_end ();
            }
            string line_text = buf.get_text (line_start, line_end, false);
            string trimmed = line_text.strip ();

            string line_prefix = profile.line_comment_prefix;
            string block_open = profile.block_comment_open;
            string block_close = profile.block_comment_close;

            if (profile.supports_chunks) {
                var chunk = Core.ChunkParser.find_chunk_at_line (doc.get_clean_source_text (), cursor_line);
                if (chunk != null) {
                    string clang = chunk.language.down ();
                    if (clang == "ts" || clang == "typescript" || clang == "js" || clang == "mermaid" || clang == "css") {
                        line_prefix = "// ";
                    } else if (clang == "sql") {
                        line_prefix = "-- ";
                    } else {
                        line_prefix = "# ";
                    }
                    block_open = "";
                    block_close = "";
                }
            }

            buf.begin_user_action ();
            if (line_prefix.length > 0) {
                string bare = line_prefix.strip ();
                if (trimmed.has_prefix (line_prefix)) {
                    int bidx = line_text.index_of (line_prefix);
                    int cidx = line_text.substring (0, bidx).char_count ();
                    Gtk.TextIter del_start = line_start;
                    del_start.forward_chars (cidx);
                    Gtk.TextIter del_end = del_start;
                    del_end.forward_chars (line_prefix.char_count ());
                    buf.delete (ref del_start, ref del_end);
                } else if (bare.length > 0 && trimmed.has_prefix (bare)) {
                    int bidx = line_text.index_of (bare);
                    int cidx = line_text.substring (0, bidx).char_count ();
                    Gtk.TextIter del_start = line_start;
                    del_start.forward_chars (cidx);
                    Gtk.TextIter del_end = del_start;
                    del_end.forward_chars (bare.char_count ());
                    buf.delete (ref del_start, ref del_end);
                } else {
                    buf.insert (ref line_start, line_prefix, -1);
                }
            } else if (block_open.length > 0 && block_close.length > 0) {
                string open_t = block_open.strip ();
                string close_t = block_close.strip ();
                if (trimmed.has_prefix (open_t) && trimmed.has_suffix (close_t) && trimmed.length >= open_t.length + close_t.length) {
                    string unwrapped = trimmed.substring (open_t.length, trimmed.length - open_t.length - close_t.length).strip ();
                    buf.delete (ref line_start, ref line_end);
                    buf.insert (ref line_start, unwrapped, -1);
                } else {
                    buf.delete (ref line_start, ref line_end);
                    buf.insert (ref line_start, @"$(block_open)$(line_text)$(block_close)", -1);
                }
            }
            buf.end_user_action ();
        }

        public void open_zotero_picker () {
            var zotero = Services.ZoteroService.get_default ();
            zotero.open_native_citation_picker_async.begin ((obj, res) => {
                string? citation = zotero.open_native_citation_picker_async.end (res);
                if (citation != null && citation.length > 0) {
                    var doc = get_active_document ();
                    if (doc != null) {
                        var fmt = doc.get_document_format ();
                        var profile = Core.FormatProfile.for_format (fmt);
                        doc.source_buffer.begin_user_action ();
                        if (profile.citation_style == Core.CitationStyle.LATEX_CITE) {
                            doc.source_buffer.insert_at_cursor (convert_pandoc_citation_to_latex (citation), -1);
                        } else {
                            doc.source_buffer.insert_at_cursor (citation, -1);
                        }
                        doc.source_buffer.end_user_action ();

                        if (profile.citation_style == Core.CitationStyle.PANDOC_AT) {
                            Editor.CitationCompletionProvider.ensure_buffer_bibliography_line (doc.source_buffer, "references.bib");
                        }
                        try {
                            if (zotero_cite_regex == null) {
                                zotero_cite_regex = new Regex ("@([a-zA-Z0-9_:-]+)");
                            }
                            MatchInfo mi;
                            if (zotero_cite_regex.match (citation, 0, out mi)) {
                                while (mi.matches ()) {
                                    string key = mi.fetch (1);
                                    zotero.sync_citation_to_project_async.begin (key, doc.current_project_dir);
                                    mi.next ();
                                }
                            }
                        } catch (RegexError e) {}
                    }
                } else {
                    show_toast ("Zotero desktop is not running — opening DOI & .bib Manager");
                    open_doi_bib_manager ();
                }
            });
        }

        private static string convert_pandoc_citation_to_latex (string citation) {
            string inner = citation.strip ();
            if (inner.has_prefix ("[") && inner.has_suffix ("]") && inner.length >= 2) {
                inner = inner.substring (1, inner.length - 2).strip ();
            }

            string[] parts = inner.split (";");
            var keys_only = new GenericArray<string> ();
            var formatted_parts = new GenericArray<string> ();
            bool has_locator = false;

            try {
                if (pandoc_part_regex == null) {
                    pandoc_part_regex = new Regex ("^[^@]*@([a-zA-Z0-9_:-]+)(?:\\s*,\\s*(.+))?$");
                }
                foreach (string raw_part in parts) {
                    string p = raw_part.strip ();
                    if (p.length == 0) continue;
                    MatchInfo mi;
                    if (pandoc_part_regex.match (p, 0, out mi)) {
                        string key = mi.fetch (1);
                        string? loc = mi.fetch (2);
                        if (loc != null && loc.strip ().length > 0) {
                            has_locator = true;
                            formatted_parts.add (@"\\cite[$(loc.strip ())]{$key}");
                        } else {
                            keys_only.add (key);
                            formatted_parts.add (@"\\cite{$key}");
                        }
                    }
                }
            } catch (RegexError e) {}

            if (formatted_parts.length > 0) {
                if (!has_locator && keys_only.length > 0) {
                    var sb = new StringBuilder ();
                    for (int i = 0; i < keys_only.length; i++) {
                        if (i > 0) sb.append (", ");
                        sb.append (keys_only[i]);
                    }
                    return @"\\cite{$(sb.str)}";
                }
                var sb = new StringBuilder ();
                for (int i = 0; i < formatted_parts.length; i++) {
                    sb.append (formatted_parts[i]);
                }
                return sb.str;
            }

            string fallback = citation.replace ("[@", "").replace ("]", "").replace ("@", "").replace (";", ",").strip ();
            return @"\\cite{$fallback}";
        }

        public void open_doi_bib_manager () {
            var doc = get_active_document ();
            string base_dir = current_project_dir;
            if (base_dir == "" && doc != null && doc.file_location != null) {
                var parent = doc.file_location.get_parent ();
                if (parent != null) base_dir = parent.get_path () ?? "";
            }
            if (base_dir == "") {
                base_dir = GLib.Environment.get_home_dir ();
            }
            string bib_subdir_path = GLib.Path.build_filename (base_dir, "bibliography", "references.bib");
            string bib_root_path = GLib.Path.build_filename (base_dir, "references.bib");
            string bib_path = GLib.FileUtils.test (bib_subdir_path, GLib.FileTest.EXISTS) ? bib_subdir_path : bib_root_path;
            string? doc_path = (doc != null && doc.file_location != null) ? doc.file_location.get_path () : null;
            if (doc_path != null && doc_path.down ().has_suffix (".bib")) {
                bib_path = doc_path;
            }

            bool is_latex = (doc != null && doc.get_document_format () == DocumentFormat.TEX);
            var dlg = new UI.DoiBibDialog (bib_path, is_latex);
            dlg.insert_citation_requested.connect ((citekey, bib_filename) => {
                var active = get_active_document ();
                if (active != null) {
                    var fmt = active.get_document_format ();
                    var profile = Core.FormatProfile.for_format (fmt);
                    active.source_buffer.begin_user_action ();
                    if (profile.citation_style == Core.CitationStyle.LATEX_CITE) {
                        active.source_buffer.insert_at_cursor (@"\\cite{$citekey}", -1);
                    } else {
                        active.source_buffer.insert_at_cursor (@"[@$citekey]", -1);
                    }
                    active.source_buffer.end_user_action ();
                    if (profile.citation_style == Core.CitationStyle.PANDOC_AT) {
                        Editor.CitationCompletionProvider.ensure_buffer_bibliography_line (active.source_buffer, bib_filename);
                    }
                }
            });
            dlg.present (this);
        }

        public void source_active_file () {
            var doc = get_active_document ();
            if (doc == null) return;
            string code = doc.get_clean_source_text ().strip ();
            if (code.length == 0) return;
            var fmt = doc.get_document_format ();
            string engine = (fmt == DocumentFormat.RSCRIPT || fmt == DocumentFormat.RMD)
                ? "r"
                : (fmt == DocumentFormat.TS ? "ts" : "python");
            doc.panel_registry.run_code_snippet_in_console (engine, code);
        }

        private void prompt_save_layout () {
            var doc = get_active_document ();
            if (doc == null) return;

            var dialog = new Adw.AlertDialog ("Save Layout Preset", "Enter a name for this custom workbench layout:");
            var entry = new Gtk.Entry () {
                placeholder_text = "e.g. Dual-Screen or Biostats-Focus",
                margin_start = 12, margin_end = 12, margin_top = 8, margin_bottom = 8
            };
            dialog.set_extra_child (entry);
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", "Save");
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_default_response ("save");
            dialog.set_close_response ("cancel");

            dialog.response.connect ((resp) => {
                if (resp == "save") {
                    string name = entry.text.strip ();
                    if (name.length > 0) {
                        try {
                            UI.LayoutSerializer.save_layout (name, doc.dock_layout_state);
                            show_toast (@"Saved layout preset '$name'");
                        } catch (GLib.Error e) {
                            show_toast (@"Failed to save layout: $(e.message)");
                        }
                    }
                }
            });
            dialog.present (this);
        }

        // =====================================================================
        // 5. VIEW RIBBON (Layouts, Split Modes, Zoom & Display Options)
        // =====================================================================
        private Gtk.Widget build_view_ribbon () {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

            // Group 1: Workspace Mode Toggle
            btn_mode_apostrophe = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("edit-find-symbolic", "Focus Mode", "Apostrophe Distraction-Free Layout", true, true, true);
            btn_mode_rstudio = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-grid-symbolic", "RStudio 4-Quad", "RStudio-Style 4-Quadrant Workbench Layout", true, false, true);
            btn_mode_rstudio.set_group (btn_mode_apostrophe);

            btn_mode_apostrophe.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                if (btn_mode_apostrophe.active) {
                    Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.APOSTROPHE, true);
                }
            });
            btn_mode_rstudio.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                if (btn_mode_rstudio.active) {
                    Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                }
            });

            box.append (RibbonFactory.create_linked_group ({ btn_mode_apostrophe, btn_mode_rstudio }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Workbench Layout Topologies (shown in RStudio Workbench mode)
            var rstudio_ctrls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            btn_topo_quad = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-grid-symbolic", "2×2 Quad", "2×2 Quadrant Grid (4 Panels)", true, true, true);
            btn_topo_quad6 = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-grid-symbolic", "3×2 (6)", "6-Quadrant Ultrawide Grid for 21:9 / 34:9 Displays (Ctrl+Alt+6)", true, false, true);
            btn_topo_left_tall = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-column-symbolic", "Left Tall", "Editor Full-Height on Left, Stacked Right", true, false, true);
            btn_topo_right_tall = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-paged-symbolic", "Right Tall", "Outputs Full-Height on Right, Stacked Left", true, false, true);
            btn_topo_quad6.set_group (btn_topo_quad);
            btn_topo_left_tall.set_group (btn_topo_quad);
            btn_topo_right_tall.set_group (btn_topo_quad);

            btn_topo_quad.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                if (btn_topo_quad.active) {
                    var d = get_active_document ();
                    if (d != null) {
                        Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                        UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.QUAD_4, d.dock_layout_state);
                    }
                }
            });
            btn_topo_quad6.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                if (btn_topo_quad6.active) {
                    var d = get_active_document ();
                    if (d != null) {
                        Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                        UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.QUAD_6_ULTRAWIDE, d.dock_layout_state);
                    }
                }
            });
            btn_topo_left_tall.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                if (btn_topo_left_tall.active) {
                    var d = get_active_document ();
                    if (d != null) {
                        Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                        UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.LEFT_TALL_3, d.dock_layout_state);
                    }
                }
            });
            btn_topo_right_tall.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                if (btn_topo_right_tall.active) {
                    var d = get_active_document ();
                    if (d != null) {
                        Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                        UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.RIGHT_TALL_3, d.dock_layout_state);
                    }
                }
            });

            rstudio_ctrls.append (RibbonFactory.create_linked_group ({ btn_topo_quad, btn_topo_quad6, btn_topo_left_tall, btn_topo_right_tall }));

            var btn_manage_panels = RibbonFactory.create_tool_button (
                "window-new-symbolic",
                "Manage Panels",
                "Rearrange panels across quadrants, pop out to 2-3 screens, or apply 6-Quadrant presets (Ctrl+Shift+L)",
                false,
                false,
                true,
                null,
                "win.manage_panels"
            );
            var btn_redock_all = RibbonFactory.create_tool_button (
                "view-restore-symbolic",
                "Re-dock All",
                "Return all independent floating panels back into the main window",
                false,
                false,
                true,
                null,
                "win.redock_all_panels"
            );
            rstudio_ctrls.append (RibbonFactory.create_linked_group ({ btn_manage_panels, btn_redock_all }));

            var btn_layout_presets = new Gtk.MenuButton () {
                icon_name = "view-more-symbolic",
                tooltip_text = "Layout Presets & Persistence",
                valign = Gtk.Align.CENTER
            };
            btn_layout_presets.add_css_class ("flat");

            var layout_pop = new Gtk.Popover ();
            var lpop_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6
            };
            layout_pop.set_child (lpop_box);
            layout_pop.map.connect (() => {
                Gtk.Widget? ch = lpop_box.get_first_child ();
                while (ch != null) {
                    var next = ch.get_next_sibling ();
                    lpop_box.remove (ch);
                    ch = next;
                }

                lpop_box.append (new Gtk.Label ("Layout Presets") { css_classes = { "dim-label", "caption" }, xalign = 0 });

                var b_save_layout = new Gtk.Button.with_label ("Save Current Layout...") { halign = Gtk.Align.START };
                b_save_layout.add_css_class ("flat");
                b_save_layout.clicked.connect (() => {
                    layout_pop.popdown ();
                    prompt_save_layout ();
                });
                lpop_box.append (b_save_layout);

                string[] saved_presets = UI.LayoutSerializer.list_saved_layouts ();
                if (saved_presets.length > 0) {
                    lpop_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                    lpop_box.append (new Gtk.Label ("Load Saved Preset:") { css_classes = { "dim-label", "caption" }, xalign = 0 });
                    foreach (string preset_name in saved_presets) {
                        string target_preset = preset_name;
                        var b_load = new Gtk.Button.with_label (target_preset) { halign = Gtk.Align.START };
                        b_load.add_css_class ("flat");
                        b_load.clicked.connect (() => {
                            layout_pop.popdown ();
                            var d = get_active_document ();
                            if (d != null && UI.LayoutSerializer.load_layout (target_preset, d.dock_layout_state)) {
                                Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                                d.rstudio_dock_grid.dock_manager.sync_windows_with_state ();
                                sync_document_ui_toggles (d);
                                show_toast (@"Loaded layout preset '$target_preset'");
                            }
                        });
                        lpop_box.append (b_load);
                    }
                }

                lpop_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                var b_reset_layout = new Gtk.Button.with_label ("Reset to Default Layout") { halign = Gtk.Align.START };
                b_reset_layout.add_css_class ("flat");
                b_reset_layout.clicked.connect (() => {
                    layout_pop.popdown ();
                    var d = get_active_document ();
                    if (d != null) {
                        d.rstudio_dock_grid.dock_manager.redock_all_panels ();
                        d.dock_layout_state.reset_to_default ();
                        d.dock_layout_state.save_to_disk ();
                        sync_document_ui_toggles (d);
                        show_toast ("Reset workbench to default 4-quadrant layout");
                    }
                });
                lpop_box.append (b_reset_layout);
            });

            btn_layout_presets.set_popover (layout_pop);
            rstudio_ctrls.append (btn_layout_presets);
            view_rstudio_group = rstudio_ctrls;
            view_rstudio_sep = RibbonFactory.create_vseparator ();
            box.append (view_rstudio_group);
            box.append (view_rstudio_sep);

            // Group 3: Focus Mode Split Switcher (shown only in Focus Mode)
            var btn_split_v = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-column-symbolic", "Vertical", "Side-by-Side Split", true, true, true);
            var btn_split_h = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-paged-symbolic", "Horizontal", "Top-and-Bottom Split", true, false, true);
            var btn_edit_only = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("x-office-document-symbolic", "Editor Only", "Editor-Only Mode", true, false, true);
            var btn_prev_only = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("applications-internet-symbolic", "Preview Only", "Preview-Only Mode", true, false, true);

            btn_split_h.set_group (btn_split_v);
            btn_edit_only.set_group (btn_split_v);
            btn_prev_only.set_group (btn_split_v);

            btn_split_v.toggled.connect (() => {
                if (btn_split_v.active) Services.WorkspaceStateManager.get_default ().set_split_mode (Services.SplitMode.VERTICAL_SPLIT);
            });
            btn_split_h.toggled.connect (() => {
                if (btn_split_h.active) Services.WorkspaceStateManager.get_default ().set_split_mode (Services.SplitMode.HORIZONTAL_SPLIT);
            });
            btn_edit_only.toggled.connect (() => {
                if (btn_edit_only.active) Services.WorkspaceStateManager.get_default ().set_split_mode (Services.SplitMode.EDITOR_ONLY);
            });
            btn_prev_only.toggled.connect (() => {
                if (btn_prev_only.active) Services.WorkspaceStateManager.get_default ().set_split_mode (Services.SplitMode.PREVIEW_ONLY);
            });

            view_focus_split_group = RibbonFactory.create_linked_group ({ btn_split_v, btn_split_h, btn_edit_only, btn_prev_only });
            view_focus_split_sep = RibbonFactory.create_vseparator ();
            box.append (view_focus_split_group);
            box.append (view_focus_split_sep);

            // Group 3: Zoom Controls
            var btn_zoom_out = RibbonFactory.create_tool_button ("zoom-out-symbolic", null, "Zoom Out (Ctrl+-)", false, false, true, null, "win.zoom_out");
            var btn_zoom_100 = RibbonFactory.create_tool_button ("zoom-original-symbolic", "100%", "Zoom 100% (Ctrl+0)", false, false, true, null, "win.zoom_reset");
            var btn_zoom_in = RibbonFactory.create_tool_button ("zoom-in-symbolic", null, "Zoom In (Ctrl++)", false, false, true, null, "win.zoom_in");

            box.append (RibbonFactory.create_linked_group ({ btn_zoom_out, btn_zoom_100, btn_zoom_in }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 4: Editor Display Options
            var chk_grid = new Gtk.Grid () { row_spacing = 2, column_spacing = 8, valign = Gtk.Align.CENTER };
            var chk_line_no = new Gtk.CheckButton.with_label ("Line Numbers") { active = true };
            chk_line_no.toggled.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_view.show_line_numbers = chk_line_no.active;
            });
            var chk_syntax = new Gtk.CheckButton.with_label ("Highlight") { active = true };
            chk_syntax.toggled.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.highlight_syntax = chk_syntax.active;
            });
            var chk_wrap = new Gtk.CheckButton.with_label ("Word Wrap") { active = true };
            chk_wrap.toggled.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_view.wrap_mode = chk_wrap.active ? Gtk.WrapMode.WORD_CHAR : Gtk.WrapMode.NONE;
            });
            chk_console = new Gtk.CheckButton.with_label ("Side Panel");
            chk_console.tooltip_text = "Show or hide Focus Mode side panel";
            chk_console.toggled.connect (() => {
                if (syncing_ui_toggles) return;
                var d = get_active_document ();
                if (d != null) {
                    if (chk_console.active) {
                        d.console_revealer.visible = true;
                    }
                    d.console_revealer.reveal_child = chk_console.active;
                }
            });

            chk_grid.attach (chk_line_no, 0, 0, 1, 1);
            chk_grid.attach (chk_syntax, 0, 1, 1, 1);
            chk_grid.attach (chk_wrap, 1, 0, 1, 1);
            chk_grid.attach (chk_console, 1, 1, 1, 1);
            box.append (chk_grid);

            return box;
        }

        public void sync_document_ui_toggles (DocumentPage? d) {
            if (d == null) return;
            syncing_ui_toggles = true;
            try {
                bool panel_open = d.console_revealer.visible && d.console_revealer.reveal_child;
                if (btn_preview != null && btn_preview.active != panel_open) {
                    btn_preview.active = panel_open;
                }
                if (chk_console != null && chk_console.active != panel_open) {
                    chk_console.active = panel_open;
                }
                var mode = d.get_workbench_mode ();
                bool is_rstudio = (mode == Services.LayoutMode.RSTUDIO);
                if (is_rstudio) {
                    if (btn_mode_rstudio != null && !btn_mode_rstudio.active) {
                        btn_mode_rstudio.active = true;
                    }
                } else {
                    if (btn_mode_apostrophe != null && !btn_mode_apostrophe.active) {
                        btn_mode_apostrophe.active = true;
                    }
                }
                if (view_rstudio_group != null) view_rstudio_group.visible = is_rstudio;
                if (view_rstudio_sep != null) view_rstudio_sep.visible = is_rstudio;
                if (view_focus_split_group != null) view_focus_split_group.visible = !is_rstudio;
                if (view_focus_split_sep != null) view_focus_split_sep.visible = !is_rstudio;
                if (btn_preview != null) btn_preview.visible = !is_rstudio;
                if (chk_console != null) chk_console.visible = !is_rstudio;
                if (d.dock_layout_state != null) {
                    switch (d.dock_layout_state.topology) {
                        case Imladris.Core.Layout.LayoutTopology.QUAD_6_ULTRAWIDE:
                            if (btn_topo_quad6 != null && !btn_topo_quad6.active) btn_topo_quad6.active = true;
                            break;
                        case Imladris.Core.Layout.LayoutTopology.LEFT_TALL_3:
                            if (btn_topo_left_tall != null && !btn_topo_left_tall.active) btn_topo_left_tall.active = true;
                            break;
                        case Imladris.Core.Layout.LayoutTopology.RIGHT_TALL_3:
                            if (btn_topo_right_tall != null && !btn_topo_right_tall.active) btn_topo_right_tall.active = true;
                            break;
                        case Imladris.Core.Layout.LayoutTopology.QUAD_4:
                        default:
                            if (btn_topo_quad != null && !btn_topo_quad.active) btn_topo_quad.active = true;
                            break;
                    }
                }
                update_web_sync_status_badge ();
            } finally {
                syncing_ui_toggles = false;
            }
        }
    }
}
