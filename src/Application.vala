// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Main application life-cycle manager and action dispatcher.
 * Architecture: Upstream entry point from main.vala; coordinates windows, settings, and desktop integrations.
 * Concurrency: Executes on the GLib MainContext thread.
 */
namespace Imladris {

    public class Application : Adw.Application {

        public const string APP_VERSION = "0.25.0";

        private const GLib.ActionEntry[] APP_ACTIONS = {
            { "new_project_modal", on_new_project_modal },
            { "new_rproj", on_new_rproj },
            { "new_md", on_new_md },
            { "new_qmd", on_new_qmd },
            { "new_rmd", on_new_rmd },
            { "new_ipynb", on_new_ipynb },
            { "new_r", on_new_r },
            { "new_shiny", on_new_shiny },
            { "run_shiny_app", on_run_shiny_app },
            { "new_py", on_new_py },
            { "new_ts", on_new_ts },
            { "new_html", on_new_html },
            { "new_css", on_new_css },
            { "new_bib", on_new_bib },
            { "open", on_open_document },
            { "save", on_save_document },
            { "export_pdf", on_export_pdf },
            { "export_html", on_export_html },
            { "export_odt", on_export_odt },
            { "export_odp", on_export_odp },
            { "export_rtf", on_export_rtf },
            { "render_scientific", on_render_scientific },
            { "export_mallorn", on_export_mallorn },
            { "export_rstudio", on_export_rstudio },
            { "export_jupyter", on_export_jupyter },
            { "package_installer", on_package_installer },
            { "elrond_assist", on_elrond_assist },
            { "toolchain_setup", on_toolchain_setup },
            { "snapshot_environment", on_snapshot_environment },
            { "restore_environment", on_restore_environment },
            { "restart_kernel", on_restart_kernel },
            { "run_cell", on_run_cell },
            { "run_all_cells", on_run_all_cells },
            { "run_line_selection", on_run_line_selection },
            { "interrupt_execution", on_interrupt_execution },
            { "command_palette", on_command_palette },
            { "preferences", on_preferences },
            { "about", on_about },
            { "math_chem_editor", on_math_chem_editor },
            { "mermaid_studio", on_mermaid_studio },
            { "insert_image", on_insert_image },
            { "insert_video", on_insert_video },
            { "print", on_print_document },
            { "quit", on_quit }
        };

        public Application () {
            Object (
                application_id: "io.github.Antux912012.Imladris",
                flags: GLib.ApplicationFlags.HANDLES_OPEN
            );

            add_main_option (
                "version",
                'v',
                GLib.OptionFlags.NONE,
                GLib.OptionArg.NONE,
                "Print application version and exit",
                null
            );

            add_main_option (
                "purge-user-data",
                0,
                GLib.OptionFlags.NONE,
                GLib.OptionArg.NONE,
                "Erase all local user data, cache, and state (GDPR Art. 17)",
                null
            );
        }

        protected override int handle_local_options (GLib.VariantDict options) {
            if (options.contains ("version")) {
                stdout.printf ("Imladris %s\n", APP_VERSION);
                return 0;
            }

            if (options.contains ("purge-user-data")) {
                purge_all_user_data ();
                return 0;
            }

            return -1;
        }

        /**
         * Right to Erasure implementation complying with GDPR Article 17.
         * Deterministically deletes all local application state, cache, and configurations.
         */
        public static void purge_all_user_data () {
            string config_dir = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "imladris");
            string data_dir = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "imladris");
            string cache_dir = GLib.Path.build_filename (GLib.Environment.get_user_cache_dir (), "imladris");

            Core.PlatformUtils.delete_directory_recursive (GLib.File.new_for_path (config_dir));
            Core.PlatformUtils.delete_directory_recursive (GLib.File.new_for_path (data_dir));
            Core.PlatformUtils.delete_directory_recursive (GLib.File.new_for_path (cache_dir));

            var schema_source = GLib.SettingsSchemaSource.get_default ();
            if (schema_source != null && schema_source.lookup ("io.github.Antux912012.Imladris", true) != null) {
                var settings = new GLib.Settings ("io.github.Antux912012.Imladris");
                settings.reset ("hw-acceleration");
                settings.reset ("theme");
                settings.reset ("accent-color");
                settings.reset ("galaxy-server-url");
            }

            stdout.printf ("[GDPR Art. 17] All local user data, cache, and state files erased successfully.\n");
        }

        protected override void startup () {
            base.startup ();

            setup_papirus_icon_theme ();

            this.add_action_entries (APP_ACTIONS, this);
            this.set_accels_for_action ("app.new_project_modal", { "<Control>n", "<Control><Shift>n" });
            this.set_accels_for_action ("app.open", { "<Control>o" });
            this.set_accels_for_action ("app.save", { "<Control>s" });
            this.set_accels_for_action ("app.package_installer", { "<Control><Alt>k" });
            this.set_accels_for_action ("app.render_scientific", { "<Control><Shift>k" });
            this.set_accels_for_action ("app.run_shiny_app", { "<Control><Shift>a" });
            this.set_accels_for_action ("app.elrond_assist", { "<Control><Shift>e" });
            this.set_accels_for_action ("app.command_palette", { "<Control><Shift>p", "<Control>k" });
            this.set_accels_for_action ("app.preferences", { "<Control>comma" });
            this.set_accels_for_action ("app.math_chem_editor", { "<Control>m" });
            this.set_accels_for_action ("app.mermaid_studio", { "<Control><Shift>d", "<Control><Alt>m" });
            this.set_accels_for_action ("win.insert_chunk", { "<Control><Alt>i" });
            this.set_accels_for_action ("win.insert_pipe", { "<Control><Shift>m" });
            this.set_accels_for_action ("win.toggle_comment", { "<Control><Shift>c" });
            this.set_accels_for_action ("win.insert_assignment", { "<Alt>minus" });
            this.set_accels_for_action ("win.focus_editor", { "<Control>1" });
            this.set_accels_for_action ("win.focus_console", { "<Control>2" });
            this.set_accels_for_action ("win.zotero_picker", { "<Control><Shift>i" });
            this.set_accels_for_action ("win.doi_bib_manager", { "<Control><Shift>b" });
            this.set_accels_for_action ("app.insert_video", { "<Control><Shift>v" });
            this.set_accels_for_action ("app.quit", { "<Control>q" });
            this.set_accels_for_action ("win.undo", { "<Control>z" });
            this.set_accels_for_action ("win.redo", { "<Control><Shift>z", "<Control>y" });
            this.set_accels_for_action ("win.collapse_ribbon", { "<Control>F1" });
            this.set_accels_for_action ("win.zoom_in", { "<Control>plus", "<Control>equal" });
            this.set_accels_for_action ("win.zoom_out", { "<Control>minus" });
            this.set_accels_for_action ("win.zoom_reset", { "<Control>0" });
            this.set_accels_for_action ("win.run_chunk", { "<Control><Shift>Return" });
            this.set_accels_for_action ("win.run_line", { "<Control>Return" });
            this.set_accels_for_action ("app.run_all_cells", { "<Control><Alt>r" });
            this.set_accels_for_action ("win.run_chunks_above", { "<Control><Alt>p" });
            this.set_accels_for_action ("win.clear_console", { "<Control>l" });
            this.set_accels_for_action ("app.restart_kernel", { "<Control><Shift>F10" });

            var provider = new Gtk.CssProvider ();
            provider.load_from_resource ("/org/imladris/app/style.css");
            var display = Gdk.Display.get_default ();
            if (display != null) {
                Gtk.StyleContext.add_provider_for_display (
                    display,
                    provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );
            }

            Core.SettingsManager.get_default ().apply_theme (Core.SettingsManager.get_default ().app_theme);
            Core.SettingsManager.get_default ().apply_accent_color (Core.SettingsManager.get_default ().accent_color);

            Imladris.Plugins.PluginManager.get_default ().initialize ();
        }

        protected override void activate () {
            var win = this.active_window as Window;
            if (win == null) {
                win = new Window (this);
            }
            win.present ();
        }

        protected override void shutdown () {
            Services.PersistentSessionManager.get_default ().shutdown_all ();
            base.shutdown ();
        }

        protected override void open (GLib.File[] files, string hint) {
            var win = this.active_window as Window;
            if (win == null) {
                win = new Window (this);
            }
            foreach (var file in files) {
                win.open_file_from_path.begin (file.get_path ());
            }
            win.present ();
        }

        private void on_new_project_modal () {
            var win = this.active_window as Window;
            if (win != null) win.show_new_project_modal ();
        }

        private void on_new_rproj () {
            var win = this.active_window as Window;
            if (win != null) win.show_new_rproj_modal ();
        }

        private void on_new_md () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("notes.md", "markdown");
        }

        private void on_new_qmd () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("analysis.qmd", "markdown");
        }

        private void on_new_rmd () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("report.Rmd", "rmd");
        }

        private void on_new_ipynb () {
            var win = this.active_window as Window;
            if (win != null) {
                string template = Core.NotebookSerializer.get_default_ipynb_markdown_template ();
                win.add_document_tab ("notebook.ipynb", "markdown", template);
            }
        }

        private void on_new_r () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("script.R", "r");
        }

        private void on_new_shiny () {
            var win = this.active_window as Window;
            if (win != null) {
                string template = ProjectScaffolder.get_shiny_template ();
                win.add_document_tab ("app.R", "r", template);
            }
        }

        private void on_run_shiny_app () {
            var win = this.active_window as Window;
            if (win != null) {
                win.toggle_shiny_app_execution ();
            }
        }

        private void on_new_py () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("script.py", "python3");
        }

        private void on_new_ts () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("module.ts", "typescript");
        }

        private void on_new_html () {
            var win = this.active_window as Window;
            if (win != null) {
                string html_starter = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Scientific HTML Report</title>
  <style>
    :root {
      --bg: #ffffff;
      --fg: #1e293b;
      --accent: #0284c7;
      --card: #f8fafc;
      --border: #e2e8f0;
    }
    body {
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      color: var(--fg);
      background: var(--bg);
      max-width: 820px;
      margin: 0 auto;
      padding: 40px 24px;
      line-height: 1.65;
    }
    h1 { color: #0f172a; border-bottom: 2px solid var(--border); padding-bottom: 8px; }
    .callout {
      background: var(--card);
      border-left: 4px solid var(--accent);
      padding: 14px 18px;
      border-radius: 6px;
      margin: 20px 0;
    }
  </style>
</head>
<body>
  <h1>Scientific HTML Report</h1>
  <p>Inline LaTeX math: $\alpha + \beta = \gamma$ and chemical formulas $\ce{H2O}$.</p>
  <div class="callout">
    <strong>Display Equation:</strong>
    $$E = mc^2$$
  </div>
</body>
</html>
""";
                win.add_document_tab ("index.html", "html", html_starter);
            }
        }

        private void on_new_css () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("style.css", "css", "/* Imladris Stylesheet */\nbody {\n  font-family: system-ui, sans-serif;\n  line-height: 1.6;\n}\n");
        }

        private void on_new_bib () {
            var win = this.active_window as Window;
            if (win != null) win.add_document_tab ("references.bib", "bibtex", "% BibTeX Bibliography managed by Imladris\n% Use Ctrl+Shift+B (DOI / .bib Manager) to generate entries from a DOI link.\n\n");
        }

        private void on_open_document () {
            var win = this.active_window as Window;
            if (win != null) win.open_document_async.begin ();
        }

        private void on_save_document () {
            var win = this.active_window as Window;
            if (win != null) win.save_document_async.begin ();
        }

        private void on_export_pdf () {
            var win = this.active_window as Window;
            if (win != null) win.export_document_dialog_async.begin ("pdf");
        }

        private void on_export_html () {
            var win = this.active_window as Window;
            if (win != null) win.export_document_dialog_async.begin ("html");
        }

        private void on_export_odt () {
            var win = this.active_window as Window;
            if (win != null) win.export_document_dialog_async.begin ("odt");
        }

        private void on_export_odp () {
            var win = this.active_window as Window;
            if (win != null) win.export_document_dialog_async.begin ("odp");
        }

        private void on_export_rtf () {
            var win = this.active_window as Window;
            if (win != null) win.export_document_dialog_async.begin ("rtf");
        }

        private void on_render_scientific () {
            var win = this.active_window as Window;
            if (win != null) win.trigger_selected_scientific_render ();
        }

        private void on_export_mallorn () {
            var win = this.active_window as Window;
            if (win != null) win.export_mallorn_archive_async.begin ();
        }

        private void on_export_rstudio () {
            var win = this.active_window as Window;
            if (win != null) win.export_to_rstudio_async.begin ();
        }

        private void on_export_jupyter () {
            var win = this.active_window as Window;
            if (win != null) win.export_to_jupyter_async.begin ();
        }

        private void on_package_installer () {
            var win = this.active_window as Window;
            if (win != null) win.show_package_installer_dialog ();
        }

        private void on_elrond_assist () {
            var win = this.active_window as Window;
            if (win != null) win.trigger_elrond_assistance ();
        }

        private void on_toolchain_setup () {
            var win = this.active_window as Window;
            if (win != null) win.show_toolchain_setup_dialog ();
        }

        private void on_snapshot_environment () {
            var win = this.active_window as Window;
            if (win != null) win.snapshot_current_environment ();
        }

        private void on_restore_environment () {
            var win = this.active_window as Window;
            if (win != null) win.restore_current_environment ();
        }

        private void on_restart_kernel () {
            var win = this.active_window as Window;
            if (win != null) win.restart_active_kernel ();
        }

        private void on_run_cell () {
            var win = this.active_window as Window;
            if (win != null) win.run_active_chunk ();
        }

        private void on_run_all_cells () {
            var win = this.active_window as Window;
            if (win != null) win.run_all_chunks ();
        }

        private void on_run_line_selection () {
            var win = this.active_window as Window;
            if (win != null) win.run_line_or_selection ();
        }

        private void on_interrupt_execution () {
            var win = this.active_window as Window;
            if (win != null) win.interrupt_active_execution ();
        }

        private void on_command_palette () {
            var win = this.active_window as Window;
            if (win != null) {
                var dlg = new UI.CommandPaletteDialog (win);
                dlg.present (win);
            }
        }

        private void on_preferences () {
            var win = this.active_window;
            if (win != null) new UI.PreferencesDialog ().present (win);
        }

        private void on_about () {
            var win = this.active_window as Window;
            if (win != null) win.show_about_dialog ();
        }

        private void on_math_chem_editor () {
            var win = this.active_window as Window;
            if (win != null) win.show_math_chem_editor_dialog ();
        }

        private void on_mermaid_studio () {
            var win = this.active_window as Window;
            if (win != null) win.show_mermaid_flow_studio_dialog ();
        }

        private void on_insert_image () {
            var win = this.active_window as Window;
            if (win != null) win.prompt_insert_media.begin (false);
        }

        private void on_insert_video () {
            var win = this.active_window as Window;
            if (win != null) win.prompt_insert_media.begin (true);
        }

        private void on_print_document () {
            var win = this.active_window as Window;
            if (win != null) win.print_active_document ();
        }

        private void setup_papirus_icon_theme () {
            // Respect the user's desktop icon theme per GNOME HIG; only register bundled icons as fallback.
            var display = Gdk.Display.get_default ();
            if (display != null) {
                var icon_theme = Gtk.IconTheme.get_for_display (display);

                // Add bundled Papirus SVG resource path as a guaranteed fallback
                icon_theme.add_resource_path ("/org/imladris/icons/papirus");

                // If system has Papirus installed in standard XDG data dirs, prioritize it
                string[]? search_path = icon_theme.get_search_path ();
                bool has_usr_share = false;
                if (search_path != null) {
                    foreach (var p in search_path) {
                        if (p == "/usr/share/icons") {
                            has_usr_share = true;
                            break;
                        }
                    }
                }
                if (!has_usr_share) {
                    icon_theme.add_search_path ("/usr/share/icons");
                }

                // Also add local project data/icons path if running in development mode
                var cur_dir = GLib.Environment.get_current_dir ();
                var local_icon_path = GLib.Path.build_filename (cur_dir, "data", "icons", "hicolor");
                if (GLib.FileUtils.test (local_icon_path, GLib.FileTest.IS_DIR)) {
                    icon_theme.add_search_path (local_icon_path);
                }
            }
        }

        private void on_quit () {
            this.quit ();
        }
    }
}
