// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Presents a dedicated Libadwaita dialog for scaffolding RStudio projects (.Rproj).
 *
 * Architectural Position:
 * Modal UI component in Imladris.UI.
 * Upstream callers: Imladris.Window and Imladris.Application.
 * Downstream dependencies: Imladris.MallornManager, Imladris.ProjectScaffolder, and Adw.PreferencesDialog.
 *
 * Concurrency Constraints:
 * Runs on the GLib MainContext thread. Performs synchronous file scaffolding without blocking UI loop.
 */

using GLib;
using Gtk;
using Adw;

namespace Imladris.UI {

    /**
     * Modal dialog allowing the user to configure and scaffold an RStudio .Rproj workspace.
     */
    public class RprojCreationDialog : Adw.PreferencesDialog {

        private Adw.EntryRow project_name_row;
        private Adw.ActionRow parent_dir_row;
        private Adw.ComboRow format_row;
        private Adw.SwitchRow sandbox_row;
        private Gtk.Button btn_create;
        private string selected_parent_dir;

        /**
         * Emitted when project files are successfully scaffolded on disk.
         */
        public signal void rproj_created (File rproj_file, File primary_file, ProjectConfig config);

        /**
         * Constructs a new RprojCreationDialog instance.
         */
        public RprojCreationDialog () {
            Object (title: "New RStudio Project (.Rproj)");

            string home_docs = GLib.Path.build_filename (GLib.Environment.get_home_dir (), "Documents");
            this.selected_parent_dir = home_docs;

            setup_ui ();
        }

        /**
         * Assembles preferences groups, rows, and commit buttons.
         */
        private void setup_ui () {
            var page = new Adw.PreferencesPage () {
                title = "RStudio Project Setup",
                icon_name = "utilities-terminal-symbolic"
            };

            // Project Metadata Group
            var meta_group = new Adw.PreferencesGroup () {
                title = "Project Identity & Location",
                description = "Configure project directory and RStudio .Rproj manifest properties."
            };

            project_name_row = new Adw.EntryRow () {
                title = "Project Name",
                text = "Analysis_Project"
            };
            meta_group.add (project_name_row);

            parent_dir_row = new Adw.ActionRow () {
                title = "Parent Directory",
                subtitle = selected_parent_dir
            };

            var btn_browse = new Gtk.Button.with_label ("Browse...") {
                valign = Gtk.Align.CENTER,
                css_classes = { "flat" }
            };
            btn_browse.clicked.connect (on_browse_parent_directory);
            parent_dir_row.add_suffix (btn_browse);
            meta_group.add (parent_dir_row);

            page.add (meta_group);

            // Document & Toolchain Group
            var toolchain_group = new Adw.PreferencesGroup () {
                title = "Primary Document & Environment",
                description = "Select starter notebook syntax and reproducibility sandbox options."
            };

            var format_models = new Gtk.StringList ({
                "R Script (.R)",
                "R Markdown (.Rmd)",
                "Quarto Document (.qmd)"
            });

            format_row = new Adw.ComboRow () {
                title = "Primary Document Format",
                subtitle = "Initial file created inside the R project",
                model = format_models,
                selected = 0
            };
            toolchain_group.add (format_row);

            sandbox_row = new Adw.SwitchRow () {
                title = "Initialize renv Package Sandbox",
                subtitle = "Creates isolated local package environment for 1:1 publication reproducibility",
                active = false
            };
            toolchain_group.add (sandbox_row);

            page.add (toolchain_group);

            // Commit Actions Group
            var commit_group = new Adw.PreferencesGroup ();
            btn_create = new Gtk.Button.with_label ("Create RStudio Project") {
                halign = Gtk.Align.CENTER,
                css_classes = { "suggested-action", "pill" },
                margin_top = 12
            };
            btn_create.clicked.connect (on_create_project_clicked);
            commit_group.add (btn_create);

            page.add (commit_group);

            this.add (page);
        }

        /**
         * Opens native directory chooser to select parent folder.
         */
        private void on_browse_parent_directory () {
            var dialog = new Gtk.FileDialog () {
                title = "Select Parent Directory for R Project",
                modal = true
            };

            dialog.select_folder.begin (this.get_root () as Gtk.Window, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end (res);
                    if (folder != null) {
                        selected_parent_dir = folder.get_path ();
                        parent_dir_row.subtitle = selected_parent_dir;
                    }
                } catch (GLib.Error e) {
                    // Canceled or dismissed
                }
            });
        }

        /**
         * Validates inputs, scaffolds directory, and triggers rproj_created signal.
         */
        private void on_create_project_clicked () {
            string raw_name = project_name_row.text.strip ();
            if (raw_name.length == 0) {
                raw_name = "Untitled_R_Project";
            }

            DocumentFormat fmt = DocumentFormat.RSCRIPT;
            if (format_row.selected == 1) {
                fmt = DocumentFormat.RMD;
            } else if (format_row.selected == 2) {
                fmt = DocumentFormat.QMD;
            }

            bool sandboxed = sandbox_row.active;

            btn_create.sensitive = false;

            try {
                File rproj_file = MallornManager.create_rproj_project (
                    selected_parent_dir,
                    raw_name,
                    fmt,
                    sandboxed
                );

                string project_dir = rproj_file.get_parent ().get_path ();
                string starter_filename = (fmt == DocumentFormat.RMD)
                    ? "analysis.Rmd"
                    : ((fmt == DocumentFormat.QMD) ? "analysis.qmd" : "main.R");
                File primary_file = File.new_for_path (GLib.Path.build_filename (project_dir, starter_filename));

                var cfg = new ProjectConfig () {
                    project_name = ProjectScaffolder.sanitize_dirname (raw_name),
                    custom_project_dir = project_dir,
                    format = fmt,
                    project_type = sandboxed ? ProjectType.SANDBOXED : ProjectType.STANDARD
                };

                rproj_created (rproj_file, primary_file, cfg);
                this.close ();
            } catch (GLib.Error e) {
                btn_create.sensitive = true;
                var toast = new Adw.Toast (@"Failed to create R project: $(e.message)");
                this.add_toast (toast);
            }
        }
    }
}
