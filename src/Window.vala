// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris {

    public class Window : Adw.ApplicationWindow, Imladris.Plugins.PluginHostWindow {

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
        private Gtk.ToggleButton? tab_btn_packages = null;
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
        private Gtk.Widget? btn_export_mallorn = null;
        private Gtk.Widget? btn_export_rstudio = null;
        private Gtk.Widget? btn_export_jupyter = null;
        private Gtk.Widget? btn_live_preview = null;

        // Plugin Extension Ribbon Tracking
        private Gtk.Box? extensions_ribbon_box = null;
        private Gtk.Separator? ext_separator = null;
        private Gee.HashMap<string, Gtk.Widget> plugin_ribbon_buttons = new Gee.HashMap<string, Gtk.Widget> ();

        private UI.PackageIndexCache pkg_index_cache = new UI.PackageIndexCache ();
        private ulong theme_changed_hid = 0;
        private ulong physics_changed_hid = 0;
        private ulong ui_settings_hid = 0;

        public Window (Adw.Application app) {
            Object (
                application: app,
                title: "Imladris — Polyglot Scientific & Web Studio",
                default_width: 1380,
                default_height: 860
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
            new_submenu.append ("R Script (.R)", "app.new_r");
            new_submenu.append ("Shiny Web App (.R)", "app.new_shiny");
            new_submenu.append ("Python Script (.py)", "app.new_py");
            new_submenu.append ("HTML5 Document (.html)", "app.new_html");

            var export_submenu = new GLib.Menu ();
            export_submenu.append ("Render to HTML", "app.export_html");
            export_submenu.append ("Render to PDF", "app.export_pdf");
            export_submenu.append ("OpenDocument Text (.odt)", "app.export_odt");
            export_submenu.append ("OpenDocument Presentation (.odp)", "app.export_odp");
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

            var ribbon_tabs_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) {
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
                if (cat == "Run") tab_btn.add_css_class ("ribbon-tab-scientific");
                if (cat == "Publish") tab_btn.add_css_class ("ribbon-tab-web");
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
                "Interactive Slides (RevealJS)",
                "Conference Slides (Beamer PDF)",
                "Symposium Poster (Typst/PDF)"
            });
            var export_format_selector = new Gtk.DropDown (export_formats, null) {
                valign = Gtk.Align.CENTER,
                tooltip_text = "Select Scientific Output Format"
            };
            export_format_selector.add_css_class ("flat");

            var btn_render_quarto = new Gtk.Button () {
                tooltip_text = "Compile Scientific Document / Deck / Poster (Ctrl+Shift+K)",
                valign = Gtk.Align.CENTER
            };
            btn_render_quarto.add_css_class ("suggested-action");
            var render_content = new Adw.ButtonContent () {
                icon_name = "media-playback-start-symbolic",
                label = "Render"
            };
            btn_render_quarto.set_child (render_content);
            btn_render_quarto.clicked.connect (() => {
                uint sel = export_format_selector.selected;
                var sc_fmt = Core.ScientificOutputFormat.HTML_MANUSCRIPT;
                if (sel == 1) sc_fmt = Core.ScientificOutputFormat.REVEALJS_SLIDES;
                else if (sel == 2) sc_fmt = Core.ScientificOutputFormat.BEAMER_PDF_SLIDES;
                else if (sel == 3) sc_fmt = Core.ScientificOutputFormat.TYPST_POSTER_PDF;
                compile_scientific_document_async.begin (sc_fmt);
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
            shiny_svc.status_changed.connect ((st) => {
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

            var row_deck = new Adw.ActionRow () {
                title = "New Deck or Poster Template...",
                subtitle = "RevealJS, Beamer, or Typst",
                activatable = true
            };
            row_deck.add_prefix (new Gtk.Image.from_icon_name ("x-office-presentation-symbolic"));
            row_deck.activated.connect (() => {
                sci_popover.popdown ();
                var dlg = new UI.PresentationTemplateDialog ();
                dlg.template_selected.connect ((t_title, starter_content, suggested_fn) => {
                    add_document_tab (suggested_fn, "markdown", starter_content);
                    show_toast (@"Created $t_title ($suggested_fn)");
                });
                dlg.present (this);
            });
            sci_list.append (row_deck);

            var yavanna_popover = new Imladris.Bridges.Yavanna.BioEntityPopover ();
            yavanna_popover.insert_snippet_requested.connect ((snippet) => {
                insert_in_active_editor (snippet);
                show_toast ("Inserted biological provenance record into document");
            });
            var btn_yavanna_inline = new Gtk.MenuButton () {
                icon_name = "applications-science-symbolic",
                label = "Yavanna Bio-Entity",
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
                icon_name = "network-cellular-symbolic",
                label = "Taniquetil AlphaFold",
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
                icon_name = "view-statistics-symbolic",
                label = "Elbereth Biostats",
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
            sci_popover.set_child (sci_box);

            var sci_tools_btn = new Gtk.MenuButton () {
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

            // =================================================================
            // TIER 3: STREAMLINED TAB BAR WITH AI & LAYOUT TOGGLES
            // =================================================================
            var tier3_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
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
                if (doc != null) {
                    doc.cleanup ();
                }
                tab_view.close_page_finish (page, true);
                return true;
            });
            tab_view.page_detached.connect ((page, pos) => {
                if (tab_view.n_pages == 0) {
                    content_stack.visible_child_name = "welcome";
                    tab_bar.visible = false;
                    tier3_box.visible = false;
                    ribbon_scroller.visible = false;
                    status_bar.visible = false;
                }
            });
            tab_view.page_attached.connect ((page, pos) => {
                var sm_ui = Core.SettingsManager.get_default ();
                content_stack.visible_child_name = "editor";
                tab_bar.visible = true;
                tier3_box.visible = true;
                ribbon_scroller.visible = sm_ui.show_ribbon_toolbar && btn_collapse_ribbon.active;
                status_bar.visible = sm_ui.show_status_bar;
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
            status_env_badge_lbl.add_css_class ("env-badge");
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
            elrond_ctrl.statusbar_telemetry_updated.connect ((telemetry_text, is_active) => {
                elrond_telemetry_label.label = telemetry_text;
                if (is_active) {
                    elrond_telemetry_label.remove_css_class ("dim-label");
                    elrond_telemetry_label.add_css_class ("accent");
                } else {
                    elrond_telemetry_label.remove_css_class ("accent");
                    elrond_telemetry_label.add_css_class ("dim-label");
                }
            });

            status_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

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
            content_stack.visible_child_name = "welcome";
            tab_bar.visible = false;
            tier3_box.visible = false;
            ribbon_scroller.visible = false;
            status_bar.visible = false;

            toast_overlay.set_child (content_stack);
            toolbar_view.set_content (toast_overlay);

            Services.WorkspaceStateManager.get_default ().layout_changed.connect ((mode) => {
                apply_workspace_layout (mode);
            });

            Services.WorkspaceStateManager.get_default ().split_changed.connect ((split) => {
                var d = get_active_document ();
                if (d != null) {
                    d.set_split_orientation (split);
                }
            });

            tab_view.notify["selected-page"].connect (() => {
                var d = get_active_document ();
                if (d != null) {
                    string fname = d.file_location != null ? d.file_location.get_basename () : (d.initial_title.contains (".") ? d.initial_title : @"untitled.$(d.doc_type)");
                    Services.WorkspaceStateManager.get_default ().resolve_mode_for_file (fname);
                    d.set_split_orientation (Services.WorkspaceStateManager.get_default ().active_split);
                    var fmt = d.get_document_format ();
                    update_ribbon_state_machine (fmt, current_project_type);
                    if (d.file_location != null && d.file_location.get_parent () != null) {
                        Services.PersistentSessionManager.get_default ().set_working_directory (
                            d.file_location.get_parent ().get_path (), current_project_type
                        );
                    }
                    if (btn_shiny_app != null) {
                        bool is_shiny = Services.ShinyService.get_default ().is_shiny_file (fname, d.source_buffer.text);
                        btn_shiny_app.visible = is_shiny || (d.doc_type == "r" || d.doc_type == "rmd");
                    }
                }
            });

            // Launch on Welcome Dashboard; new document tab created only on user action
            update_ribbon_state_machine (DocumentFormat.QMD, current_project_type);

            var pm = Imladris.Plugins.PluginManager.get_default ();
            pm.active_window = this;
            pm.ribbon_button_added.connect (on_plugin_ribbon_button_added);
            pm.ribbon_button_removed.connect (on_plugin_ribbon_button_removed);
            pm.toast_requested.connect ((msg) => {
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
                toast.button_clicked.connect (() => {
                    foreach (var rec in recs) {
                        string title = rec.file_path != null ? GLib.Path.get_basename (rec.file_path) : "Recovered-Document.md";
                        GLib.File? f = rec.file_path != null ? GLib.File.new_for_path (rec.file_path) : null;
                        add_document_tab (title, rec.doc_type, rec.content, f);
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
                if (Core.SettingsManager.get_default ().inline_editing_enabled) {
                    doc.show_inline_prompt_popover ();
                } else {
                    doc.show_ai_assistant ();
                }
            } else {
                trigger_ai_assistant ();
            }
        }

        public string get_active_editor_text () {
            var doc = get_active_document ();
            if (doc != null && doc.source_buffer != null) {
                return doc.source_buffer.text;
            }
            return "";
        }

        public string get_active_selected_text () {
            var doc = get_active_document ();
            if (doc != null && doc.source_buffer != null) {
                Gtk.TextIter start, end;
                if (doc.source_buffer.get_selection_bounds (out start, out end)) {
                    return doc.source_buffer.get_text (start, end, false);
                }
            }
            return "";
        }

        public void insert_in_active_editor (string text) {
            var doc = get_active_document ();
            if (doc == null) {
                add_document_tab ("Analysis.qmd", "markdown");
                doc = get_active_document ();
            }
            if (doc != null && doc.source_buffer != null) {
                doc.source_buffer.begin_user_action ();
                doc.source_buffer.insert_at_cursor (text, -1);
                doc.source_buffer.end_user_action ();
            }
        }

        public void ask_elrond (string prompt) {
            var doc = get_active_document ();
            if (doc != null) {
                if (Services.WorkspaceStateManager.get_default ().active_layout == Services.LayoutMode.RSTUDIO &&
                    doc.panel_registry != null &&
                    doc.panel_registry.elrond_chat_panel != null) {
                    doc.dock_layout_state.activate_panel (Imladris.Core.Layout.PanelId.ELROND_AI);
                    doc.panel_registry.elrond_chat_panel.submit_external_prompt (prompt);
                } else {
                    doc.show_ai_assistant ();
                    if (doc.assistant_panel != null) {
                        doc.assistant_panel.send_prompt (prompt);
                    }
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
            var spec = (pattern.length > 0 && pattern != "*") ? new GLib.PatternSpec (pattern) : null;
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

        public void add_document_tab (string title, string lang_id, string? initial_text = null, GLib.File? file = null) {
            var doc_page = new DocumentPage (title, lang_id, this);
            if (initial_text != null) {
                doc_page.source_buffer.text = initial_text;
            }
            if (file != null) {
                doc_page.file_location = file;
            }
            doc_page.project_type = current_project_type;
            doc_page.stats_changed.connect ((words, lines, badge) => {
                status_badge_lbl.label = badge;
                status_words_lbl.label = @"Words: $words | Lines: $lines";
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
                add_document_tab ("analysis.qmd", "markdown", "---\ntitle: \"Untitled Quarto Analysis\"\nauthor: \"Scientist\"\nformat: html\n---\n\n## Introduction\n\n");
            });
            quick_group.add (qmd_row);

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
                add_document_tab ("notebook.ipynb", "markdown", template);
            });
            more_expander.add_row (ipynb_row);

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

        public void show_new_project_modal () {
            var dlg = new UI.NewProjectDialog ();
            dlg.item_created.connect ((file, config, is_standalone) => {
                this.current_project_type = config.project_type;
                if (file.get_parent () != null) {
                    this.current_project_dir = file.get_parent ().get_path ();
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
                string raw_text = (string) contents;

                var fmt = DocumentFormat.from_filename (name);
                string text = Adapters.DocumentAdapter.load_to_editor_buffer (raw_text, fmt);

                string lang = "markdown";
                if (name.has_suffix (".ipynb")) lang = "markdown";
                else if (name.has_suffix (".ts")) lang = "typescript";
                else if (name.has_suffix (".html") || name.has_suffix (".htm")) lang = "html";
                else if (name.has_suffix (".rmd") || name.has_suffix (".Rmd")) lang = "rmd";
                else if (name.has_suffix (".r") || name.has_suffix (".R")) lang = "r";
                else if (name.has_suffix (".py")) lang = "python3";

                add_document_tab (name, lang, text, file);

                // Detect surrounding project sandbox/standard status
                var parent_dir = file.get_parent ();
                if (parent_dir != null) {
                    var ptype = Services.SandboxController.detect_project_type (parent_dir.get_path ());
                    this.current_project_type = ptype;
                    this.current_project_dir = parent_dir.get_path ();
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
                    string editor_content = doc.source_buffer.text;
                    var fmt = DocumentFormat.from_filename (doc.file_location.get_basename ());
                    string to_save = Adapters.DocumentAdapter.save_from_editor_buffer (editor_content, fmt);
                    string etag;
                    yield doc.file_location.replace_contents_async (
                        to_save.data,
                        null,
                        false,
                        GLib.FileCreateFlags.REPLACE_DESTINATION,
                        null,
                        out etag
                    );
                    Services.RecoveryService.get_default ().purge_document_cache (doc.doc_id);
                    doc.append_console_log (@"✔ Saved $(doc.file_location.get_basename ())");
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
                        string editor_content = doc.source_buffer.text;
                        var fmt = DocumentFormat.from_filename (file.get_basename ());
                        string to_save = Adapters.DocumentAdapter.save_from_editor_buffer (editor_content, fmt);
                        string etag;
                        yield file.replace_contents_async (
                            to_save.data,
                            null,
                            false,
                            GLib.FileCreateFlags.REPLACE_DESTINATION,
                            null,
                            out etag
                        );
                        Services.RecoveryService.get_default ().purge_document_cache (doc.doc_id);
                        if (tab_view.selected_page != null) {
                            tab_view.selected_page.title = file.get_basename ();
                        }
                        doc.append_console_log (@"✔ Saved $(file.get_basename ())");
                    }
                } catch (GLib.Error e) {
                    doc.append_console_log (@"✖ Save failed: $(e.message)");
                }
            }
        }

        public async bool confirm_standard_project_export_if_needed () {
            if (current_project_type == ProjectType.STANDARD) {
                var alert = new Adw.AlertDialog (
                    "System Libraries (Non-Portable)",
                    "This project relies on system libraries and may fail to run on other machines if required packages are missing."
                );
                alert.add_response ("cancel", "Cancel");
                alert.add_response ("continue", "Continue Export");
                alert.set_response_appearance ("continue", Adw.ResponseAppearance.SUGGESTED);
                alert.set_default_response ("continue");
                alert.set_close_response ("cancel");
                string response = yield alert.choose (this, null);
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
                    if (doc.file_location != null) {
                        yield save_document_async ();
                    }
                    doc.append_console_log (@"▶ Exporting $base_name to $(file.get_basename ())...");
                    string src_path = doc.file_location != null ? doc.file_location.get_path () : @"/tmp/$base_prefix.md";
                    bool ok = yield Services.ExportService.get_default ().export_document_async (
                        src_path,
                        file.get_path (),
                        format,
                        doc.source_buffer.text
                    );
                    if (ok) {
                        doc.append_console_log (@"✔ Successfully exported to $(file.get_path ())");
                        // Generate GxP / EU CRA Cryptographic Provenance Manifest
                        string pdir = (current_project_dir != "") ? current_project_dir : GLib.Path.get_dirname (src_path);
                        Core.ProvenanceAttestationService.generate_attestation_async.begin (
                            src_path,
                            doc.source_buffer.text,
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
                        doc.append_console_log (@"✖ Export to $(format.up ()) failed. Check console output.");
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

        public async void compile_scientific_document_async (Core.ScientificOutputFormat format) {
            var doc = get_active_document ();
            if (doc == null) return;

            string s_path = "";
            if (doc.file_location != null) {
                s_path = doc.file_location.get_path ();
                yield save_document_async ();
            } else {
                string cache_dir = Core.PlatformUtils.get_shared_cache_dir ("render");
                s_path = GLib.Path.build_filename (cache_dir, "document.qmd");
                try {
                    GLib.FileUtils.set_contents (s_path, doc.source_buffer.text);
                } catch (GLib.Error e) {
                    show_toast (@"Failed to cache document for rendering: $(e.message)");
                    return;
                }
            }

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
                    // PDF output (Beamer or Typst)
                    var file = GLib.File.new_for_path (out_path);
                    var launcher = new Gtk.FileLauncher (file);
                    launcher.launch.begin (this, null, null);
                }
            } catch (GLib.Error e) {
                show_toast (@"Compilation failed: $(e.message)");
            }
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

            var action_zotero = new GLib.SimpleAction ("zotero_picker", null);
            action_zotero.activate.connect (() => {
                open_zotero_picker ();
            });
            this.add_action (action_zotero);

            var action_toolchain = new GLib.SimpleAction ("toolchain_setup", null);
            action_toolchain.activate.connect (() => {
                show_toolchain_setup_dialog ();
            });
            this.add_action (action_toolchain);
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
                if (d != null) d.source_buffer.cut_clipboard (d.get_clipboard (), true);
            });
            var btn_copy = RibbonFactory.create_tool_button ("edit-copy-symbolic", null, "Copy");
            ((Gtk.Button) btn_copy).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.copy_clipboard (d.get_clipboard ());
            });
            var btn_paste = RibbonFactory.create_tool_button ("edit-paste-symbolic", null, "Paste");
            ((Gtk.Button) btn_paste).clicked.connect (() => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.paste_clipboard (d.get_clipboard (), null, true);
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
                if (d != null) d.source_buffer.insert_at_cursor (@"<span style=\"color:$hex;\">text</span>", -1);
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
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor (sym, -1);
            });
            var btn_sym = RibbonFactory.create_tool_button ("character-map-symbolic", "Symbols", "Insert Math / Special Symbol", false, false, true, null, null, sym_popover);

            var emoji_popover = SmartRibbonHelpers.create_emoji_popover ((em) => {
                var d = get_active_document ();
                if (d != null) d.source_buffer.insert_at_cursor (em, -1);
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

            btn_package_installer = RibbonFactory.create_tool_button ("software-properties-symbolic", "Packages", "Open Package Installer (Ctrl+Shift+P)");
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

            box.append (RibbonFactory.create_linked_group ({ btn_render_html, btn_render_pdf, btn_export_odt, btn_export_odp }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Interoperability & Reproducibility Exports
            btn_export_mallorn = RibbonFactory.create_tool_button ("package-x-generic-symbolic", ".mallorn", "Export Portable Reproducible Archive", false, false, true, null, "app.export_mallorn");
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
                        d.source_buffer.text,
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

            var btn_preview = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-dual-symbolic", "Console", "Toggle Output Console Panel", true, true, true);
            btn_preview.toggled.connect (() => {
                var d = get_active_document ();
                if (d != null) d.console_revealer.reveal_child = btn_preview.active;
            });
            box.append (btn_preview);
            box.append (RibbonFactory.create_vseparator ());
            // Group 4 removed: Elrond Assistance is in the top tab bar and Ctrl+Shift+E

            return box;
        }

        /**
         * Pillar 2: Context-Aware Ribbon State Machine
         * Dynamically adapts visible and sensitive states based on active Project Type and Document Format
         */
        public void update_ribbon_state_machine (DocumentFormat fmt, ProjectType ptype) {
            bool is_md = (fmt == DocumentFormat.MD);
            bool is_html = (fmt == DocumentFormat.HTML);
            bool is_script = (fmt == DocumentFormat.RSCRIPT || fmt == DocumentFormat.PYSCRIPT);
            bool is_notebook = (fmt == DocumentFormat.RMD || fmt == DocumentFormat.QMD || fmt == DocumentFormat.IPYNB);
            bool is_sandboxed = (ptype == ProjectType.SANDBOXED);

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
                btn_run_chunk.visible = !is_html;
                btn_run_chunk.sensitive = is_notebook;
            }
            if (btn_run_all != null) {
                btn_run_all.visible = !is_html;
                btn_run_all.sensitive = is_notebook;
            }
            if (btn_run_above != null) {
                btn_run_above.visible = is_notebook;
                btn_run_above.sensitive = is_notebook;
            }
            if (btn_run_below != null) {
                btn_run_below.visible = is_notebook;
                btn_run_below.sensitive = is_notebook;
            }

            // 3. Script Execution Controls
            if (btn_run_line != null) {
                btn_run_line.visible = is_script || is_notebook;
                btn_run_line.sensitive = is_script || is_notebook;
            }
            if (btn_source_file != null) {
                btn_source_file.visible = is_script || is_notebook;
                btn_source_file.sensitive = is_script || is_notebook;
            }
            if (btn_interrupt != null) {
                btn_interrupt.visible = is_script || is_notebook;
                btn_interrupt.sensitive = is_script || is_notebook;
            }

            // 4. Kernel / Persistent Sessions
            if (btn_restart_kernel != null) {
                btn_restart_kernel.visible = !is_md && !is_html;
                btn_restart_kernel.sensitive = is_script || is_notebook;
            }

            // 5. Package Installer
            if (btn_package_installer != null) {
                btn_package_installer.visible = !is_md && !is_html;
                btn_package_installer.sensitive = is_script || is_notebook;
            }

            // 6. Snapshot & Restore Environment (Pillar 2 rules)
            if (btn_snapshot_env != null) {
                btn_snapshot_env.visible = is_notebook || (is_script && is_sandboxed);
                if (is_sandboxed) {
                    btn_snapshot_env.sensitive = true;
                    btn_snapshot_env.tooltip_text = "Lock environment package versions (renv::snapshot / pip freeze)";
                } else {
                    btn_snapshot_env.sensitive = false;
                    btn_snapshot_env.tooltip_text = "Only available in Sandboxed Projects";
                }
            }
            if (btn_restore_env != null) {
                btn_restore_env.visible = is_notebook || (is_script && is_sandboxed);
                if (is_sandboxed) {
                    btn_restore_env.sensitive = true;
                    btn_restore_env.tooltip_text = "Restore exact package versions from lockfile (renv::restore / pip install -r)";
                } else {
                    btn_restore_env.sensitive = false;
                    btn_restore_env.tooltip_text = "Only available in Sandboxed Projects";
                }
            }

            // 7. Knit / Render / Export
            if (btn_render_html != null) {
                btn_render_html.visible = true;
                btn_render_html.sensitive = !is_script;
            }
            if (btn_render_pdf != null) {
                btn_render_pdf.visible = !is_html;
                btn_render_pdf.sensitive = !is_script;
            }
            if (btn_export_odt != null) {
                btn_export_odt.visible = !is_html;
                btn_export_odt.sensitive = is_md || is_notebook;
            }
            if (btn_export_odp != null) {
                btn_export_odp.visible = !is_html;
                btn_export_odp.sensitive = is_md || is_notebook;
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
                btn_live_preview.visible = true;
                btn_live_preview.sensitive = is_md || is_html || is_notebook;
            }

            // 9. Packages Ribbon Tab (Pillar 2: visible & enabled for computational workflows)
            bool is_computational = is_script || is_notebook;
            if (tab_btn_packages != null) {
                tab_btn_packages.visible = is_computational;
                tab_btn_packages.sensitive = is_computational;
                if (!is_computational && tab_btn_packages.active && tab_btn_home != null) {
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
            if (doc != null) {
                doc.append_console_log (@"▶ [R] Executing: $r_cmd");
            }
            if (packages_ribbon_bar != null) {
                packages_ribbon_bar.set_r_busy (true, display_label);
            }

            string? plot_file = null;
            ulong sig_id = 0;
            sig_id = Services.PersistentSessionManager.get_default ().session_output_received.connect ((eng, line, is_err) => {
                if (eng == "r" && doc != null) {
                    doc.append_console_log (line);
                }
            });

            try {
                string output = yield Services.PersistentSessionManager.get_default ().execute_r (r_cmd, out plot_file);
                if (doc != null && output.strip ().length > 0) {
                    doc.append_console_log (output.strip ());
                }
                if (doc != null) {
                    doc.append_console_log (@"✔ R package installation finished for $display_label.");
                }
                show_toast (@"Successfully installed $display_label");
            } finally {
                Services.PersistentSessionManager.get_default ().disconnect (sig_id);
                if (packages_ribbon_bar != null) {
                    packages_ribbon_bar.set_r_busy (false, display_label);
                }
            }
        }

        public void show_toolchain_setup_dialog () {
            var dlg = new UI.ToolchainSetupDialog ();
            dlg.installation_completed.connect (() => {
                var doc = get_active_document ();
                if (doc != null) {
                    doc.append_console_log ("✔ Data Science Toolchain installed and verified. Ready to execute code.");
                }
            });
            dlg.present (this);
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
                license_type = Gtk.License.GPL_3_0,
                website = "https://github.com/Antux912012/imladris",
                issue_url = "https://github.com/Antux912012/imladris/issues",
                support_url = "https://github.com/Antux912012/imladris/discussions",
                comments = "A GNOME-native home for scientific writing, notebooks and data work.\n\n✨ Proudly developed with Gemini Assistance."
            };

            dialog.add_link ("Architecture Blueprint", "https://github.com/Antux912012/imladris/blob/main/docs/ARCHITECTURE.md");
            dialog.add_link ("Project Documentation", "https://github.com/Antux912012/imladris#readme");
            dialog.add_link ("Author GitHub Profile (@Antux912012)", "https://github.com/Antux912012");
            dialog.add_link ("Imladris Repository on GitHub", "https://github.com/Antux912012/imladris");

            dialog.add_credit_section ("AI Pair Programming", {
                "Google Gemini Assistance (Advanced Agentic AI Pair Programmer)"
            });

            dialog.add_acknowledgement_section ("Inspiration & Ecosystem", {
                "RStudio & Posit (Workbench ergonomics, DCF & Mallorn project models)",
                "Apostrophe (Distraction-free Markdown writing)",
                "Python Software Foundation & Project Jupyter (Interactive computing & REPL)",
                "The R Foundation & CRAN (Statistical computing & reproducible packages)",
                "LM Studio & Ollama (Local open-weights AI inference)",
                "llama.cpp & Georgi Gerganov (Local LLM runtime)",
                "Quarto & Pandoc (Scientific publishing pipeline)",
                "GNOME & Libadwaita Teams (Modern design language and components)",
                "Papirus Development Team (Icon design)"
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
                        GLib.FileUtils.set_contents (tmp_app, doc.source_buffer.text);
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
            Services.PersistentSessionManager.get_default ().restart_all_sessions ();
            var doc = get_active_document ();
            if (doc != null) {
                doc.append_console_log ("✔ Active persistent R and Python sessions restarted.");
            }
        }

        public void interrupt_active_execution () {
            Services.PersistentSessionManager.get_default ().interrupt_active_execution ();
            var doc = get_active_document ();
            if (doc != null) {
                doc.append_console_log ("⏹ Execution interrupted (SIGINT sent).");
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
                    doc.source_buffer.begin_user_action ();
                    Gtk.TextIter start, end;
                    if (doc.source_buffer.get_selection_bounds (out start, out end)) {
                        doc.source_buffer.delete (ref start, ref end);
                        doc.source_buffer.insert (ref start, formatted_output, formatted_output.length);
                    } else {
                        doc.source_buffer.insert_at_cursor (formatted_output, formatted_output.length);
                    }
                    doc.source_buffer.end_user_action ();
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
                    doc.source_buffer.begin_user_action ();
                    Gtk.TextIter start, end;
                    if (doc.source_buffer.get_selection_bounds (out start, out end)) {
                        doc.source_buffer.delete (ref start, ref end);
                        doc.source_buffer.insert (ref start, formatted_mermaid, formatted_mermaid.length);
                    } else {
                        doc.source_buffer.insert_at_cursor (formatted_mermaid, formatted_mermaid.length);
                    }
                    doc.source_buffer.end_user_action ();
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

        public void open_zotero_picker () {
            var zotero = Services.ZoteroService.get_default ();
            zotero.open_native_citation_picker_async.begin ((obj, res) => {
                string? citation = zotero.open_native_citation_picker_async.end (res);
                if (citation != null && citation.length > 0) {
                    var doc = get_active_document ();
                    if (doc != null) {
                        doc.source_buffer.begin_user_action ();
                        doc.source_buffer.insert_at_cursor (citation, -1);
                        doc.source_buffer.end_user_action ();

                        try {
                            var reg = new Regex ("@([a-zA-Z0-9_:-]+)");
                            MatchInfo mi;
                            if (reg.match (citation, 0, out mi)) {
                                while (mi.matches ()) {
                                    string key = mi.fetch (1);
                                    string full_text;
                                    Gtk.TextIter b_s, b_e;
                                    doc.source_buffer.get_bounds (out b_s, out b_e);
                                    full_text = doc.source_buffer.get_text (b_s, b_e, false);
                                    string updated = zotero.ensure_yaml_bibliography (full_text, "references.bib");
                                    if (updated != full_text) {
                                        doc.source_buffer.begin_user_action ();
                                        doc.source_buffer.set_text (updated);
                                        doc.source_buffer.end_user_action ();
                                    }
                                    zotero.sync_citation_to_project_async.begin (key, doc.current_project_dir);
                                    mi.next ();
                                }
                            }
                        } catch (RegexError e) {}
                    }
                }
            });
        }

        public void source_active_file () {
            var doc = get_active_document ();
            if (doc == null) return;
            string code = doc.source_buffer.text.strip ();
            if (code.length == 0) return;
            var fmt = doc.get_document_format ();
            string engine = (fmt == DocumentFormat.RSCRIPT || fmt == DocumentFormat.RMD) ? "r" : "python";
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
            var btn_mode_apostrophe = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("edit-find-symbolic", "Focus Mode", "Apostrophe Distraction-Free Layout", true, true, true);
            var btn_mode_rstudio = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-grid-symbolic", "RStudio 4-Quad", "RStudio-Style 4-Quadrant Workbench Layout", true, false, true);
            btn_mode_rstudio.set_group (btn_mode_apostrophe);

            btn_mode_apostrophe.toggled.connect (() => {
                if (btn_mode_apostrophe.active) {
                    Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.APOSTROPHE, true);
                }
            });
            btn_mode_rstudio.toggled.connect (() => {
                if (btn_mode_rstudio.active) {
                    Services.WorkspaceStateManager.get_default ().set_layout_mode (Services.LayoutMode.RSTUDIO, true);
                }
            });

            box.append (RibbonFactory.create_linked_group ({ btn_mode_apostrophe, btn_mode_rstudio }));
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Workbench Layout Topologies (QUAD_4, LEFT_TALL_3, RIGHT_TALL_3)
            var btn_topo_quad = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-grid-symbolic", "2×2 Quad", "2×2 Quadrant Grid Topology", true, true, true);
            var btn_topo_left_tall = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-column-symbolic", "Left Tall", "Editor Full-Height on Left, Stacked Right", true, false, true);
            var btn_topo_right_tall = (Gtk.ToggleButton) RibbonFactory.create_tool_button ("view-paged-symbolic", "Right Tall", "Outputs Full-Height on Right, Stacked Left", true, false, true);
            btn_topo_left_tall.set_group (btn_topo_quad);
            btn_topo_right_tall.set_group (btn_topo_quad);

            btn_topo_quad.toggled.connect (() => {
                if (btn_topo_quad.active) {
                    var d = get_active_document ();
                    if (d != null) {
                        UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.QUAD_4, d.dock_layout_state);
                    }
                }
            });
            btn_topo_left_tall.toggled.connect (() => {
                if (btn_topo_left_tall.active) {
                    var d = get_active_document ();
                    if (d != null) {
                        UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.LEFT_TALL_3, d.dock_layout_state);
                    }
                }
            });
            btn_topo_right_tall.toggled.connect (() => {
                if (btn_topo_right_tall.active) {
                    var d = get_active_document ();
                    if (d != null) {
                        UI.LayoutSerializer.apply_topology_preset (Imladris.Core.Layout.LayoutTopology.RIGHT_TALL_3, d.dock_layout_state);
                    }
                }
            });

            box.append (RibbonFactory.create_linked_group ({ btn_topo_quad, btn_topo_left_tall, btn_topo_right_tall }));

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
            lpop_box.append (new Gtk.Label ("Layout Presets") { css_classes = { "dim-label", "caption" }, xalign = 0 });

            var b_save_layout = new Gtk.Button.with_label ("Save Current Layout...") { halign = Gtk.Align.START };
            b_save_layout.add_css_class ("flat");
            b_save_layout.clicked.connect (() => {
                layout_pop.popdown ();
                prompt_save_layout ();
            });
            lpop_box.append (b_save_layout);

            var b_reset_layout = new Gtk.Button.with_label ("Reset to Default Layout") { halign = Gtk.Align.START };
            b_reset_layout.add_css_class ("flat");
            b_reset_layout.clicked.connect (() => {
                layout_pop.popdown ();
                var d = get_active_document ();
                if (d != null) {
                    d.dock_layout_state.reset_to_default ();
                    show_toast ("Reset workbench to default 4-quadrant layout");
                }
            });
            lpop_box.append (b_reset_layout);

            layout_pop.set_child (lpop_box);
            btn_layout_presets.set_popover (layout_pop);
            box.append (btn_layout_presets);
            box.append (RibbonFactory.create_vseparator ());

            // Group 2: Split Mode Switcher
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

            box.append (RibbonFactory.create_linked_group ({ btn_split_v, btn_split_h, btn_edit_only, btn_prev_only }));
            box.append (RibbonFactory.create_vseparator ());

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
            var chk_console = new Gtk.CheckButton.with_label ("Console");
            chk_console.toggled.connect (() => {
                var d = get_active_document ();
                if (d != null) d.console_revealer.reveal_child = chk_console.active;
            });

            chk_grid.attach (chk_line_no, 0, 0, 1, 1);
            chk_grid.attach (chk_syntax, 0, 1, 1, 1);
            chk_grid.attach (chk_wrap, 1, 0, 1, 1);
            chk_grid.attach (chk_console, 1, 1, 1, 1);
            box.append (chk_grid);

            return box;
        }
    }
}
