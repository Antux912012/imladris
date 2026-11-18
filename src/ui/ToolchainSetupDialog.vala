// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using Gtk;
using Adw;
using GLib;

namespace Imladris.UI {

    public class ToolchainSetupDialog : Adw.Dialog {

        public signal void installation_completed ();

        private bool is_first_run = false;

        private Adw.ExpanderRow py_expander;
        private Adw.ComboRow py_version_combo;
        private Gtk.Button py_switch_btn;

        private Adw.ExpanderRow r_expander;
        private Adw.ComboRow r_version_combo;
        private Adw.SwitchRow tidy_switch;

        private Adw.SwitchRow latex_switch;
        private Adw.SwitchRow html_css_switch;
        private Adw.SwitchRow ts_switch;
        private Adw.SwitchRow quarto_switch;

        private Adw.ActionRow mamba_status_row;
        private Gtk.Label size_badge;
        private Gtk.Label free_space_badge;

        private Gtk.Button install_btn;
        private Gtk.Button update_btn;
        private Gtk.Button cancel_btn;
        private Gtk.Button? skip_btn = null;

        private Gtk.ProgressBar progress_bar;
        private Gtk.Label status_lbl;
        private Gtk.TextView log_view;
        private Gtk.ScrolledWindow log_scroller;
        private Gtk.Box progress_box;

        private ulong progress_sig_id = 0;
        private ulong log_sig_id = 0;
        private bool is_disposed = false;
        private bool is_busy = false;
        private uint location_size_request = 0;
        private GLib.Cancellable? active_cancellable = null;

        public ToolchainSetupDialog (bool is_first_run = false) {
            Object (
                title: is_first_run ? "Welcome to Imladris — Toolchain Setup" : "Data Science Toolchain Manager",
                content_width: 680,
                content_height: 760
            );
            this.is_first_run = is_first_run;
            this.closed.connect (() => {
                is_disposed = true;
                if (active_cancellable != null) {
                    active_cancellable.cancel ();
                }
                disconnect_tm_signals ();
            });
            build_ui ();
            refresh_component_statuses ();
        }

        public void start_installation () {
            if (!is_disposed && install_btn.sensitive && !is_busy) {
                on_install_clicked ();
            }
        }

        private void disconnect_tm_signals () {
            var tm = Core.ToolchainManager.get_default ();
            if (progress_sig_id != 0) {
                tm.disconnect (progress_sig_id);
                progress_sig_id = 0;
            }
            if (log_sig_id != 0) {
                tm.disconnect (log_sig_id);
                log_sig_id = 0;
            }
        }

        private void connect_tm_signals () {
            disconnect_tm_signals ();
            var tm = Core.ToolchainManager.get_default ();
            progress_sig_id = tm.progress_changed.connect ((step, fraction, detail) => {
                if (is_disposed) return;
                progress_bar.fraction = fraction.clamp (0.0, 1.0);
                status_lbl.label = @"$step: $detail";
            });
            log_sig_id = tm.log_output.connect ((line) => {
                if (is_disposed) return;
                append_log (line);
            });
        }

        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();

            if (is_first_run) {
                skip_btn = new Gtk.Button.with_label ("Skip for Now");
                skip_btn.tooltip_text = "Use system runtimes or configure toolchains later from Tools → Data Science Toolchains";
                skip_btn.clicked.connect (() => {
                    Core.ToolchainManager.get_default ().mark_setup_dismissed ();
                    this.close ();
                });
                header.pack_start (skip_btn);
            }

            toolbar_view.add_top_bar (header);

            var page = new Adw.PreferencesPage ();

            // =================================================================
            // GROUP 1: Overview, Storage & Engine
            // =================================================================
            var info_group = new Adw.PreferencesGroup () {
                title = "Micromamba Toolchain Environment",
                description = is_first_run
                    ? "Select the languages and publishing tools you want Imladris to download and manage via micromamba."
                    : "Manage installed runtimes, update packages, or switch between Python versions."
            };

            var tm = Core.ToolchainManager.get_default ();
            var location_row = new Adw.ActionRow () {
                title = "Installation Location",
                subtitle = tm.base_dir
            };
            location_row.add_prefix (new Gtk.Image.from_icon_name ("drive-harddisk-symbolic"));

            var badges_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.END
            };
            size_badge = new Gtk.Label ("Calculating...") {
                halign = Gtk.Align.END,
                visible = false
            };
            size_badge.add_css_class ("dim-label");
            size_badge.add_css_class ("caption");

            free_space_badge = new Gtk.Label ("") {
                halign = Gtk.Align.END,
                visible = false
            };
            free_space_badge.add_css_class ("dim-label");
            free_space_badge.add_css_class ("caption");

            badges_box.append (size_badge);
            badges_box.append (free_space_badge);

            var choose_location_button = new Gtk.Button.with_label ("Choose...") {
                valign = Gtk.Align.CENTER
            };
            choose_location_button.clicked.connect (() => {
                var dialog = new Gtk.FileDialog () {
                    title = "Choose Toolchain Folder",
                    modal = true
                };
                if (GLib.FileUtils.test (tm.base_dir, GLib.FileTest.IS_DIR)) {
                    dialog.initial_folder = GLib.File.new_for_path (tm.base_dir);
                }
                dialog.select_folder.begin (this.get_root () as Gtk.Window, null, (obj, res) => {
                    try {
                        var selected_folder = dialog.select_folder.end (res);
                        string? selected_path = selected_folder != null ? selected_folder.get_path () : null;
                        if (selected_path != null) {
                            tm.set_base_dir (selected_path);
                            location_row.subtitle = tm.base_dir;
                            refresh_location_size ();
                            refresh_component_statuses ();
                        }
                    } catch (GLib.Error e) {
                        if (!(e is Gtk.DialogError.DISMISSED)) {
                            progress_box.visible = true;
                            status_lbl.label = "Could not select that folder: %s".printf (e.message);
                        }
                    }
                });
            });
            location_row.add_suffix (badges_box);
            location_row.add_suffix (choose_location_button);

            mamba_status_row = new Adw.ActionRow () {
                title = "Micromamba Engine",
                subtitle = tm.is_micromamba_installed ()
                    ? @"Installed ($(Core.ToolchainManager.get_platform_arch ()))"
                    : @"Will be downloaded automatically ($(Core.ToolchainManager.get_platform_arch ()))"
            };
            mamba_status_row.add_prefix (new Gtk.Image.from_icon_name ("system-run-symbolic"));

            refresh_location_size ();
            info_group.add (location_row);
            info_group.add (mamba_status_row);
            page.add (info_group);

            // =================================================================
            // GROUP 2: Language & Toolchain Components
            // =================================================================
            var comp_group = new Adw.PreferencesGroup () {
                title = "Toolchain Components",
                description = "Choose which components to download, or expand Python/R to pick a specific version."
            };

            // 1. Python (with version selector & version switcher)
            py_expander = new Adw.ExpanderRow () {
                title = "Python + Jupyter Kernel + uv",
                subtitle = "Python interpreter, pip, ipykernel, and fast uv package manager.",
                show_enable_switch = true,
                enable_expansion = true
            };
            py_expander.add_prefix (new Gtk.Image.from_icon_name ("applications-science-symbolic"));

            var py_model = new Gtk.StringList ({ "3.12 (Recommended)", "3.11", "3.10", "3.9" });
            py_version_combo = new Adw.ComboRow () {
                title = "Python Version",
                subtitle = "Select latest or an older Python version for compatibility",
                model = py_model,
                selected = 0
            };

            var py_switch_row = new Adw.ActionRow () {
                title = "Active Python Environment",
                subtitle = "Install or switch directly to the selected Python version"
            };
            py_switch_btn = new Gtk.Button.with_label ("Switch / Install Version") {
                valign = Gtk.Align.CENTER
            };
            py_switch_btn.clicked.connect (on_switch_python_version_clicked);
            py_switch_row.add_suffix (py_switch_btn);

            py_expander.add_row (py_version_combo);
            py_expander.add_row (py_switch_row);
            comp_group.add (py_expander);

            // 2. R (with version selector & Tidyverse toggle)
            r_expander = new Adw.ExpanderRow () {
                title = "R + IRkernel + Build Tools",
                subtitle = "Pre-compiled R interpreter, dev compilers (gcc/gfortran), make, and CRAN headers.",
                show_enable_switch = true,
                enable_expansion = true
            };
            r_expander.add_prefix (new Gtk.Image.from_icon_name ("utilities-terminal-symbolic"));

            var r_model = new Gtk.StringList ({ "4.4 (Recommended)", "4.3" });
            r_version_combo = new Adw.ComboRow () {
                title = "R Version",
                model = r_model,
                selected = 0
            };

            tidy_switch = new Adw.SwitchRow () {
                title = "R Tidyverse & RMarkdown Bundle",
                subtitle = "Pre-compiled tidyverse, data.table, rmarkdown, and knitr.",
                use_markup = false,
                active = true
            };
            r_expander.add_row (r_version_combo);
            r_expander.add_row (tidy_switch);
            comp_group.add (r_expander);

            // 3. LaTeX
            latex_switch = new Adw.SwitchRow () {
                title = "LaTeX (Tectonic Engine)",
                subtitle = "Self-updating TeX engine for compiling .tex documents and PDF output.",
                active = true
            };
            latex_switch.add_prefix (new Gtk.Image.from_icon_name ("x-office-document-symbolic"));
            comp_group.add (latex_switch);

            // 4. HTML / CSS
            html_css_switch = new Adw.SwitchRow () {
                title = "HTML / CSS Web Tooling",
                subtitle = "HTML5 validator/formatter (tidy-html5), Node.js, and WeasyPrint CSS-to-PDF engine.",
                active = true
            };
            html_css_switch.add_prefix (new Gtk.Image.from_icon_name ("text-html-symbolic"));
            comp_group.add (html_css_switch);

            // 5. TypeScript (TS)
            ts_switch = new Adw.SwitchRow () {
                title = "TypeScript (TS) + Node.js",
                subtitle = "Node.js runtime and TypeScript compiler (tsc) for .ts execution and diagnostics.",
                active = true
            };
            ts_switch.add_prefix (new Gtk.Image.from_icon_name ("application-x-addon-symbolic"));
            comp_group.add (ts_switch);

            // 6. Quarto
            quarto_switch = new Adw.SwitchRow () {
                title = "Quarto CLI + Typst + Pandoc",
                subtitle = "Publishing system for reproducible HTML, PDF, ODT, and presentation slides.",
                active = true
            };
            quarto_switch.add_prefix (new Gtk.Image.from_icon_name ("document-edit-symbolic"));
            comp_group.add (quarto_switch);

            page.add (comp_group);

            // =================================================================
            // GROUP 3: Actions & Live Progress
            // =================================================================
            var action_group = new Adw.PreferencesGroup () {
                title = "Provisioning & Updates"
            };

            var action_row = new Adw.ActionRow () {
                title = "Download or Update Components",
                subtitle = "Downloads pre-compiled conda-forge binaries into your selected toolchain folder."
            };

            var btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                valign = Gtk.Align.CENTER
            };

            cancel_btn = new Gtk.Button.with_label ("Cancel") {
                visible = false
            };
            cancel_btn.add_css_class ("destructive-action");
            cancel_btn.clicked.connect (() => {
                if (active_cancellable != null) {
                    active_cancellable.cancel ();
                    status_lbl.label = "Cancelling operation...";
                }
            });

            update_btn = new Gtk.Button.with_label ("Update Installed");
            update_btn.tooltip_text = "Update all currently installed micromamba components to their latest compatible versions";
            update_btn.clicked.connect (on_update_clicked);

            install_btn = new Gtk.Button.with_label ("Install Selected");
            install_btn.add_css_class ("suggested-action");
            install_btn.clicked.connect (on_install_clicked);

            btn_box.append (cancel_btn);
            btn_box.append (update_btn);
            btn_box.append (install_btn);
            action_row.add_suffix (btn_box);
            action_group.add (action_row);

            progress_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 10,
                margin_bottom = 10,
                visible = false
            };

            status_lbl = new Gtk.Label ("Preparing installation...") {
                xalign = 0.0f,
                wrap = true
            };
            status_lbl.add_css_class ("dim-label");
            progress_box.append (status_lbl);

            progress_bar = new Gtk.ProgressBar () {
                fraction = 0.0,
                show_text = true
            };
            progress_box.append (progress_bar);

            log_scroller = new Gtk.ScrolledWindow () {
                height_request = 180,
                hexpand = true,
                vexpand = false
            };
            log_scroller.add_css_class ("view");
            log_scroller.add_css_class ("frame");

            log_view = new Gtk.TextView () {
                editable = false,
                cursor_visible = false,
                monospace = true,
                wrap_mode = Gtk.WrapMode.NONE,
                left_margin = 8,
                right_margin = 8,
                top_margin = 8,
                bottom_margin = 8
            };
            log_scroller.set_child (log_view);
            progress_box.append (log_scroller);

            action_group.add (progress_box);
            page.add (action_group);

            toolbar_view.content = page;
            this.child = toolbar_view;
        }

        private string get_selected_python_version () {
            string[] versions = Core.ToolchainManager.get_supported_python_versions ();
            uint idx = py_version_combo.selected;
            if (idx < versions.length) {
                return versions[idx];
            }
            return "3.12";
        }

        private string get_selected_r_version () {
            string[] versions = Core.ToolchainManager.get_supported_r_versions ();
            uint idx = r_version_combo.selected;
            if (idx < versions.length) {
                return versions[idx];
            }
            return "4.4";
        }

        private void refresh_component_statuses () {
            var tm = Core.ToolchainManager.get_default ();

            mamba_status_row.subtitle = tm.is_micromamba_installed ()
                ? @"Installed ($(Core.ToolchainManager.get_platform_arch ()))"
                : @"Will be downloaded automatically ($(Core.ToolchainManager.get_platform_arch ()))";

            string? py_ver = tm.get_component_version (Core.ToolchainComponent.PYTHON);
            if (py_ver != null) {
                string env_name = GLib.Path.get_basename (tm.active_python_env);
                py_expander.subtitle = @"Installed: Python $py_ver (Active env: $env_name)";
            } else {
                py_expander.subtitle = "Python interpreter, pip, ipykernel, and fast uv package manager.";
            }

            string? r_ver = tm.get_component_version (Core.ToolchainComponent.R);
            r_expander.use_markup = false;
            if (r_ver != null) {
                r_expander.subtitle = @"Installed: R $r_ver + IRkernel & build tools";
            } else {
                r_expander.subtitle = "Pre-compiled R interpreter, dev compilers (gcc/gfortran), make, and CRAN headers.";
            }

            string? tex_ver = tm.get_component_version (Core.ToolchainComponent.LATEX);
            latex_switch.subtitle = tex_ver != null
                ? @"Installed: Tectonic $tex_ver"
                : "Self-updating TeX engine for compiling .tex documents and PDF output.";

            string? html_ver = tm.get_component_version (Core.ToolchainComponent.HTML_CSS);
            html_css_switch.subtitle = html_ver != null
                ? @"Installed: tidy-html5 $html_ver + Node.js + WeasyPrint"
                : "HTML5 validator/formatter (tidy-html5), Node.js, and WeasyPrint CSS-to-PDF engine.";

            string? ts_ver = tm.get_component_version (Core.ToolchainComponent.TYPESCRIPT);
            ts_switch.subtitle = ts_ver != null
                ? @"Installed: TypeScript $ts_ver + Node.js"
                : "Node.js runtime and TypeScript compiler (tsc) for .ts execution and diagnostics.";

            string? q_ver = tm.get_component_version (Core.ToolchainComponent.QUARTO);
            quarto_switch.subtitle = q_ver != null
                ? @"Installed: Quarto $q_ver + Typst + Pandoc"
                : "Publishing system for reproducible HTML, PDF, ODT, and presentation slides.";

            bool any_installed = tm.has_python () || tm.has_r () || tm.has_latex () ||
                tm.has_html_css () || tm.has_typescript () || tm.has_quarto ();
            update_btn.sensitive = any_installed && !is_busy;
            install_btn.label = any_installed ? "Install / Apply Selected" : "Install Selected";
        }

        private void set_controls_busy (bool busy) {
            is_busy = busy;
            install_btn.sensitive = !busy;
            update_btn.sensitive = !busy;
            cancel_btn.visible = busy;
            if (skip_btn != null) {
                skip_btn.sensitive = !busy;
            }
            py_expander.sensitive = !busy;
            r_expander.sensitive = !busy;
            latex_switch.sensitive = !busy;
            html_css_switch.sensitive = !busy;
            ts_switch.sensitive = !busy;
            quarto_switch.sensitive = !busy;
        }

        private void on_install_clicked () {
            set_controls_busy (true);
            active_cancellable = new GLib.Cancellable ();

            progress_box.visible = true;
            progress_bar.fraction = 0.05;
            status_lbl.label = "Initializing micromamba engine...";

            connect_tm_signals ();
            var tm = Core.ToolchainManager.get_default ();

            var req = new Core.ToolchainInstallRequest ();
            req.install_python = py_expander.enable_expansion;
            req.python_version = get_selected_python_version ();
            req.install_r = r_expander.enable_expansion;
            req.r_version = get_selected_r_version ();
            req.install_tidyverse = tidy_switch.active;
            req.install_latex = latex_switch.active;
            req.install_html_css = html_css_switch.active;
            req.install_typescript = ts_switch.active;
            req.install_quarto = quarto_switch.active;

            tm.install_components_async.begin (req, active_cancellable, (obj, res) => {
                bool ok = tm.install_components_async.end (res);
                finish_operation (ok, "Installation complete. Selected runtimes are ready.", "Installation failed or cancelled. Check logs above.");
            });
        }

        private void on_update_clicked () {
            set_controls_busy (true);
            active_cancellable = new GLib.Cancellable ();

            progress_box.visible = true;
            progress_bar.fraction = 0.05;
            status_lbl.label = "Checking conda-forge for component updates...";

            connect_tm_signals ();
            var tm = Core.ToolchainManager.get_default ();

            tm.update_installed_components_async.begin (null, active_cancellable, (obj, res) => {
                bool ok = tm.update_installed_components_async.end (res);
                finish_operation (ok, "All installed components updated successfully.", "Update failed or cancelled. Check logs above.");
            });
        }

        private void on_switch_python_version_clicked () {
            string target_ver = get_selected_python_version ();
            set_controls_busy (true);
            active_cancellable = new GLib.Cancellable ();

            progress_box.visible = true;
            progress_bar.fraction = 0.1;
            status_lbl.label = @"Switching active Python to $target_ver...";

            connect_tm_signals ();
            var tm = Core.ToolchainManager.get_default ();

            tm.install_or_switch_python_version_async.begin (target_ver, active_cancellable, (obj, res) => {
                bool ok = tm.install_or_switch_python_version_async.end (res);
                finish_operation (ok, @"Python $target_ver is now active.", @"Could not activate Python $target_ver. Check logs above.");
            });
        }

        private void finish_operation (bool ok, string success_msg, string error_msg) {
            disconnect_tm_signals ();
            active_cancellable = null;
            Core.PlatformUtils.clear_caches ();

            if (is_disposed) {
                return;
            }

            set_controls_busy (false);
            refresh_location_size ();
            refresh_component_statuses ();

            if (ok) {
                progress_bar.fraction = 1.0;
                status_lbl.label = @"✔ $success_msg";
                installation_completed ();
            } else {
                status_lbl.label = @"✖ $error_msg";
            }
        }

        private void append_log (string line) {
            var buffer = log_view.buffer;
            Gtk.TextIter end;
            buffer.get_end_iter (out end);
            buffer.insert (ref end, line + "\n", -1);

            GLib.Idle.add (() => {
                if (is_disposed) return GLib.Source.REMOVE;
                Gtk.TextIter scroll_end;
                buffer.get_end_iter (out scroll_end);
                var mark = buffer.create_mark (null, scroll_end, false);
                log_view.scroll_to_mark (mark, 0.0f, true, 0.0f, 1.0f);
                return GLib.Source.REMOVE;
            });
        }

        private void refresh_location_size () {
            var tm = Core.ToolchainManager.get_default ();
            uint request = ++location_size_request;
            string path = tm.base_dir;
            size_badge.label = "Calculating...";
            size_badge.visible = false;
            free_space_badge.visible = false;

            new GLib.Thread<void*> ("imladris-toolchain-size", () => {
                int64 usage = tm.get_toolchain_disk_usage_for (path);
                int64 free_bytes = tm.get_available_disk_space_for (path);
                GLib.Idle.add (() => {
                    if (is_disposed || request != location_size_request) {
                        return GLib.Source.REMOVE;
                    }
                    if (usage > 0) {
                        double mb = (double) usage / (1024.0 * 1024.0);
                        size_badge.label = mb >= 1024.0
                            ? "%.2f GB installed".printf (mb / 1024.0)
                            : "%.1f MB installed".printf (mb);
                        size_badge.visible = true;
                    }
                    if (free_bytes > 0) {
                        double free_gb = (double) free_bytes / (1024.0 * 1024.0 * 1024.0);
                        free_space_badge.label = "%.1f GB free".printf (free_gb);
                        free_space_badge.visible = true;
                    }
                    return GLib.Source.REMOVE;
                });
                return null;
            });
        }
    }
}
