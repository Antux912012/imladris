// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Scientific omni-search command palette dialog.
 * Architecture: Modal overlay triggered via Ctrl+Shift+P or Ctrl+K; dispatches workbench actions.
 * Concurrency: Executes on the GLib MainContext thread.
 */

using GLib;
using Gtk;

namespace Imladris.UI {

    public class CommandPaletteItem : GLib.Object {
        public string title { get; construct set; }
        public string subtitle { get; construct set; }
        public string icon_name { get; construct set; }
        public string action_id { get; construct set; }
        public string category { get; construct set; }

        public CommandPaletteItem (string title, string subtitle, string icon, string action, string cat = "General") {
            Object (title: title, subtitle: subtitle, icon_name: icon, action_id: action, category: cat);
        }
    }

    public class CommandPaletteDialog : Adw.Dialog {

        private Gtk.SearchEntry search_entry;
        private Gtk.ListBox list_box;
        private Gee.ArrayList<CommandPaletteItem> all_items;
        private unowned Window? parent_window;

        public CommandPaletteDialog (Window? win) {
            this.parent_window = win;
            this.title = "Command Palette";
            this.content_width = 580;
            this.content_height = 420;

            all_items = new Gee.ArrayList<CommandPaletteItem> ();
            build_command_catalog ();
            setup_ui ();
        }

        private void build_command_catalog () {
            // Document and Execution
            all_items.add (new CommandPaletteItem ("Run Active Chunk", "Execute current code chunk (Ctrl+Enter)", "media-playback-start-symbolic", "win.run_chunk", "Execution"));
            all_items.add (new CommandPaletteItem ("Run All Chunks", "Execute all notebook code cells sequentially", "media-seek-forward-symbolic", "win.run_all", "Execution"));
            all_items.add (new CommandPaletteItem ("Run Line or Selection", "Execute active line in persistent REPL console", "go-next-symbolic", "win.run_line", "Execution"));
            all_items.add (new CommandPaletteItem ("Restart Execution Kernel", "Clear persistent session states for R and Python", "view-refresh-symbolic", "win.restart_kernel", "Execution"));
            all_items.add (new CommandPaletteItem ("Interrupt Execution", "Send SIGINT to active background worker", "process-stop-symbolic", "win.interrupt_execution", "Execution"));
            all_items.add (new CommandPaletteItem ("Clear Console and Outputs", "Purge all cell outputs and terminal logs", "edit-clear-symbolic", "win.clear_console", "Execution"));

            // Publishing & Export
            all_items.add (new CommandPaletteItem ("Render to HTML", "Compile document to HTML5 via Quarto or DocumentAdapter", "applications-internet-symbolic", "app.export_html", "Publish"));
            all_items.add (new CommandPaletteItem ("Render to PDF", "Compile document to PDF via typst or wkhtmltopdf", "document-send-symbolic", "app.export_pdf", "Publish"));
            all_items.add (new CommandPaletteItem ("Export to OpenDocument Text (.odt)", "Export formatted manuscript for LibreOffice Writer", "x-office-document-symbolic", "app.export_odt", "Publish"));
            all_items.add (new CommandPaletteItem ("Export to OpenDocument Presentation (.odp)", "Export slides for LibreOffice Impress", "x-office-presentation-symbolic", "app.export_odp", "Publish"));
            all_items.add (new CommandPaletteItem ("Export .mallorn Reproducible Bundle", "Package project with lockfile and data into single archive", "package-x-generic-symbolic", "app.export_mallorn", "Publish"));
            all_items.add (new CommandPaletteItem ("Export for RStudio", "Generate .Rproj and renv lockfile manifest", "utilities-terminal-symbolic", "app.export_rstudio", "Publish"));
            all_items.add (new CommandPaletteItem ("Export for Jupyter", "Convert document to .ipynb notebook JSON", "applications-science-symbolic", "app.export_jupyter", "Publish"));

            // Scientific Studios & Bridges
            all_items.add (new CommandPaletteItem ("Elbereth Clinical Biostatistics", "ICH E9 sample size, power curves, ADSL Table 1, and survival analysis", "view-statistics-symbolic", "bridge.elbereth", "Scientific"));
            all_items.add (new CommandPaletteItem ("Taniquetil AlphaFold Structural Bridge", "Macromolecular structures, pLDDT metrics, and Bio3D coordinates", "network-cellular-symbolic", "bridge.taniquetil", "Scientific"));
            all_items.add (new CommandPaletteItem ("Yavanna Bio-Entity Inspector", "NCBI Taxonomy, Ensembl genes, and RT-qPCR oligo melting curves", "applications-science-symbolic", "bridge.yavanna", "Scientific"));
            all_items.add (new CommandPaletteItem ("Math and Chemical Reaction Studio", "Natural scientific notation to LaTeX and Markdown formulas (Ctrl+M)", "accessories-text-editor-symbolic", "app.math_chem_editor", "Scientific"));
            all_items.add (new CommandPaletteItem ("Visual Flow and Mermaid Studio", "Mindmaps, flowcharts, and sequence diagrams studio", "view-grid-symbolic", "app.mermaid_studio", "Scientific"));
            all_items.add (new CommandPaletteItem ("Insert Zotero Citation", "Pick references from local Zotero HTTP connector (Ctrl+Shift+I)", "accessories-dictionary-symbolic", "win.open_zotero", "Scientific"));
            all_items.add (new CommandPaletteItem ("Provision Data Science Toolchains", "Install pre-compiled R 4.4, Python 3.12, and Quarto binaries", "preferences-system-symbolic", "app.toolchain_setup", "Scientific"));

            // Hardware & Physics Controls
            all_items.add (new CommandPaletteItem ("Switch Physics: Alacritty Crisp (65ms)", "Set micro-transition frame pacing like Alacritty terminal", "utilities-terminal-symbolic", "physics.alacritty", "Hardware"));
            all_items.add (new CommandPaletteItem ("Switch Physics: PuTTY Instant (0ms)", "Set zero-latency instantaneous state snap", "utilities-terminal-symbolic", "physics.putty", "Hardware"));
            all_items.add (new CommandPaletteItem ("Switch Physics: Libadwaita Smooth (180ms)", "Set standard GNOME Libadwaita smooth easing", "emblem-system-symbolic", "physics.adwaita", "Hardware"));
            all_items.add (new CommandPaletteItem ("Toggle Steady Cursor", "Toggle blinking versus non-blinking solid terminal caret", "edit-paste-symbolic", "physics.cursor", "Hardware"));
            all_items.add (new CommandPaletteItem ("Open Application Preferences", "Configure GPU backend, appearance, and AI credentials (Ctrl+,)", "preferences-system-symbolic", "app.preferences", "General"));
        }

        private void setup_ui () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 12,
                margin_end = 12
            };

            search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Type a command, test, statistical tool, or shortcut...",
                hexpand = true
            };
            search_entry.search_changed.connect (filter_items);
            search_entry.activate.connect (activate_top_row);

            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Escape) {
                    this.close ();
                    return true;
                }
                if (keyval == Gdk.Key.Down) {
                    var first_row = list_box.get_row_at_index (0);
                    if (first_row != null) {
                        first_row.grab_focus ();
                        return true;
                    }
                }
                return false;
            });
            search_entry.add_controller (key_ctrl);

            box.append (search_entry);

            list_box = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
                show_separators = true,
                hexpand = true,
                vexpand = true
            };
            list_box.add_css_class ("boxed-list");
            list_box.row_activated.connect (on_row_activated);

            var scroller = new Gtk.ScrolledWindow () {
                child = list_box,
                hexpand = true,
                vexpand = true,
                min_content_height = 320
            };
            box.append (scroller);

            this.set_child (box);
            filter_items ();
        }

        private void filter_items () {
            // Remove existing rows
            var child = list_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                list_box.remove (child);
                child = next;
            }

            string query = search_entry.text.strip ().down ();
            int count = 0;

            foreach (var item in all_items) {
                bool match = (query == "");
                if (!match) {
                    string t = item.title.down ();
                    string s = item.subtitle.down ();
                    string c = item.category.down ();
                    match = t.contains (query) || s.contains (query) || c.contains (query);
                }

                if (match) {
                    var row = new Adw.ActionRow () {
                        title = item.title,
                        subtitle = item.subtitle
                    };
                    row.add_prefix (new Gtk.Image.from_icon_name (item.icon_name) { pixel_size = 18 });
                    row.set_data<string> ("action_id", item.action_id);

                    var cat_badge = new Gtk.Label (item.category) {
                        css_classes = { "caption", "dim-label" },
                        valign = Gtk.Align.CENTER
                    };
                    row.add_suffix (cat_badge);
                    list_box.append (row);

                    count++;
                    if (count >= 24) break;
                }
            }
        }

        private void activate_top_row () {
            var first_row = list_box.get_row_at_index (0);
            if (first_row != null) {
                on_row_activated (first_row);
            }
        }

        private void on_row_activated (Gtk.ListBoxRow row) {
            string? action_id = row.get_data<string> ("action_id");
            this.close ();
            if (action_id == null) return;

            dispatch_action (action_id);
        }

        private void dispatch_action (string action_id) {
            var sm = Core.SettingsManager.get_default ();

            if (action_id == "physics.alacritty") {
                sm.animation_physics = Core.AnimationPhysicsMode.ALACRITTY_CRISP;
                if (parent_window != null) parent_window.show_toast ("Switched to Alacritty Crisp Physics (65ms)");
            } else if (action_id == "physics.putty") {
                sm.animation_physics = Core.AnimationPhysicsMode.PUTTY_INSTANT;
                if (parent_window != null) parent_window.show_toast ("Switched to PuTTY Instant Physics (0ms)");
            } else if (action_id == "physics.adwaita") {
                sm.animation_physics = Core.AnimationPhysicsMode.ADWAITA_SMOOTH;
                if (parent_window != null) parent_window.show_toast ("Switched to Libadwaita Smooth Physics (180ms)");
            } else if (action_id == "physics.cursor") {
                sm.steady_cursor = !sm.steady_cursor;
                if (parent_window != null) parent_window.show_toast (sm.steady_cursor ? "Steady Cursor Enabled" : "Blinking Cursor Enabled");
            } else if (action_id.has_prefix ("win.")) {
                if (parent_window != null) {
                    string act = action_id.substring (4);
                    if (act == "run_chunk") parent_window.run_active_chunk ();
                    else if (act == "run_all") parent_window.run_all_chunks ();
                    else if (act == "run_line") parent_window.run_line_or_selection ();
                    else if (act == "restart_kernel") parent_window.restart_active_kernel ();
                    else if (act == "interrupt_execution") parent_window.interrupt_active_execution ();
                    else if (act == "clear_console") parent_window.clear_console ();
                    else if (act == "open_zotero") parent_window.open_zotero_picker ();
                }
            } else if (action_id.has_prefix ("bridge.")) {
                if (parent_window != null) {
                    string b = action_id.substring (7);
                    if (b == "elbereth") {
                        var p = new Bridges.Elbereth.ClinicalBiostatsPopover ();
                        p.set_parent (parent_window);
                        p.popup ();
                    } else if (b == "yavanna") {
                        var p = new Bridges.Yavanna.BioEntityPopover ();
                        p.set_parent (parent_window);
                        p.popup ();
                    } else if (b == "taniquetil") {
                        var p = new Bridges.Taniquetil.AlphaFoldBridgePopover ();
                        p.set_parent (parent_window);
                        p.popup ();
                    }
                }
            } else if (action_id.has_prefix ("app.")) {
                var app = GLib.Application.get_default () as Gtk.Application;
                if (app != null) {
                    string act = action_id.substring (4);
                    app.activate_action (act, null);
                }
            }
        }
    }
}
