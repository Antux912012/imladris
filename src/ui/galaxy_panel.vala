// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Renders Galaxy histories and datasets in the workbench quadrant.
 *
 * Architectural Position:
 * Persistent UI panel docked inside Quadrant 3 / Quadrant 2.
 * Upstream caller: Imladris.UI.PersistentPanelRegistry and DocumentPage.
 * Downstream dependency: Imladris.Bridges.GalaxyClient and Adw/GTK4 list widgets.
 *
 * Concurrency Constraints:
 * Runs on the GLib MainContext thread. Dispatches network requests asynchronously
 * through GalaxyClient without blocking the UI.
 */

using GLib;
using Gtk;
using Adw;
using Gee;
using Imladris.Bridges;

namespace Imladris.UI {

    /**
     * UI inspector panel for navigating remote Galaxy histories and inserting
     * reproducible data fetching code chunks into the active editor buffer.
     */
    public class GalaxyPanel : Gtk.Box {

        private GalaxyClient client;
        private Gtk.Label status_badge;
        private Gtk.Button btn_refresh;
        private Gtk.Button btn_settings;
        private Gtk.SearchEntry search_entry;
        private Gtk.ListBox histories_list;
        private Gtk.Stack main_stack;
        private Gtk.Spinner loading_spinner;
        private Adw.StatusPage empty_status_page;

        private Gee.ArrayList<GalaxyHistory> loaded_histories;
        private Gee.HashMap<string, Gtk.ListBox> dataset_lists;

        public signal void insert_chunk_requested (string code_chunk);

        public GalaxyPanel () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            this.client = GalaxyClient.get_default ();
            this.loaded_histories = new Gee.ArrayList<GalaxyHistory> ();
            this.dataset_lists = new Gee.HashMap<string, Gtk.ListBox> ();

            this.hexpand = true;
            this.vexpand = true;

            setup_ui ();
            connect_signals ();

            // Initial automatic probe
            if (client.api_key.length > 0) {
                probe_connection_and_refresh ();
            } else {
                update_status_display (false);
            }
        }

        private void setup_ui () {
            // 1. Top Subtoolbar
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            toolbar.add_css_class ("dock-subtoolbar");

            status_badge = new Gtk.Label ("○ Galaxy Offline") {
                css_classes = { "caption", "dim-label" }
            };

            btn_refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh Histories from Galaxy",
                css_classes = { "flat" }
            };
            btn_refresh.clicked.connect (refresh_histories);

            btn_settings = new Gtk.Button.from_icon_name ("emblem-system-symbolic") {
                tooltip_text = "Configure Galaxy Connection",
                css_classes = { "flat" }
            };
            btn_settings.clicked.connect (open_auth_dialog);

            search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Filter histories and datasets...",
                hexpand = true
            };
            search_entry.search_changed.connect (on_search_changed);

            toolbar.append (status_badge);
            toolbar.append (search_entry);
            toolbar.append (btn_refresh);
            toolbar.append (btn_settings);

            this.append (toolbar);

            // 2. Main Content Stack (Empty / Loading / Histories List)
            main_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                hexpand = true,
                vexpand = true
            };

            // Loading View
            var loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.CENTER
            };
            loading_spinner = new Gtk.Spinner () {
                spinning = true,
                width_request = 36,
                height_request = 36
            };
            var loading_lbl = new Gtk.Label ("Connecting to Galaxy server...") {
                css_classes = { "dim-label" }
            };
            loading_box.append (loading_spinner);
            loading_box.append (loading_lbl);
            main_stack.add_named (loading_box, "loading");

            // Empty / Offline View
            empty_status_page = new Adw.StatusPage () {
                icon_name = "applications-internet-symbolic",
                title = "Galaxy Bridge",
                description = "Connect an active Galaxy server to inspect histories and inject reproducible code chunks."
            };
            var btn_connect_prompt = new Gtk.Button.with_label ("Configure Galaxy API") {
                halign = Gtk.Align.CENTER,
                css_classes = { "suggested-action", "pill" },
                margin_top = 8
            };
            btn_connect_prompt.clicked.connect (open_auth_dialog);
            empty_status_page.set_child (btn_connect_prompt);
            main_stack.add_named (empty_status_page, "empty");

            // Histories List View
            histories_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "navigation-sidebar" },
                hexpand = true
            };

            var scrolled = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                child = histories_list,
                hexpand = true,
                vexpand = true
            };
            main_stack.add_named (scrolled, "histories");

            main_stack.set_visible_child_name ("empty");
            this.append (main_stack);
        }

        private void connect_signals () {
            client.authenticated_changed.connect ((auth) => {
                update_status_display (auth);
            });
        }

        private void update_status_display (bool is_online) {
            if (is_online) {
                string short_url = client.server_url.replace ("https://", "").replace ("http://", "");
                status_badge.label = @"● $(short_url)";
                status_badge.remove_css_class ("dim-label");
                status_badge.add_css_class ("success");
            } else {
                status_badge.label = "○ Galaxy Offline";
                status_badge.remove_css_class ("success");
                status_badge.add_css_class ("dim-label");
            }
        }

        public void probe_connection_and_refresh () {
            main_stack.set_visible_child_name ("loading");
            client.test_connection_async.begin (null, null, (obj, res) => {
                try {
                    client.test_connection_async.end (res);
                    update_status_display (true);
                    refresh_histories ();
                } catch (GLib.Error e) {
                    update_status_display (false);
                    empty_status_page.description = @"Connection error: $(e.message). Verify server URL and API key.";
                    main_stack.set_visible_child_name ("empty");
                }
            });
        }

        public void refresh_histories () {
            btn_refresh.sensitive = false;
            main_stack.set_visible_child_name ("loading");

            client.fetch_histories_async.begin ((obj, res) => {
                btn_refresh.sensitive = true;
                try {
                    loaded_histories = client.fetch_histories_async.end (res);
                    populate_histories_list ();
                } catch (GLib.Error e) {
                    empty_status_page.description = @"Failed to fetch histories: $(e.message)";
                    main_stack.set_visible_child_name ("empty");
                }
            });
        }

        private void populate_histories_list () {
            clear_histories_list ();

            if (loaded_histories.size == 0) {
                empty_status_page.description = "No histories found on the configured Galaxy server.";
                main_stack.set_visible_child_name ("empty");
                return;
            }

            foreach (var history in loaded_histories) {
                var row = create_history_row (history);
                histories_list.append (row);
            }

            main_stack.set_visible_child_name ("histories");
        }

        private void clear_histories_list () {
            Gtk.Widget? child = histories_list.get_first_child ();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling ();
                histories_list.remove (child);
                child = next;
            }
            dataset_lists.clear ();
        }

        private Gtk.Widget create_history_row (GalaxyHistory history) {
            var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6,
                css_classes = { "card" }
            };

            // History Header Row
            var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8
            };

            var exp_icon = new Gtk.Image.from_icon_name ("pan-end-symbolic");

            var title_lbl = new Gtk.Label (history.name) {
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                css_classes = { "heading" }
            };

            var btn_fetch = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Reload Datasets",
                css_classes = { "flat" }
            };

            header_box.append (exp_icon);
            header_box.append (title_lbl);
            header_box.append (btn_fetch);
            row_box.append (header_box);

            // Container for Datasets
            var datasets_container = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                margin_start = 16,
                margin_end = 8,
                margin_bottom = 6,
                visible = false
            };

            var datasets_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "boxed-list" }
            };
            dataset_lists.set (history.id, datasets_list);
            datasets_container.append (datasets_list);

            row_box.append (datasets_container);

            // Toggle Expand Gesture
            var click_gesture = new Gtk.GestureClick ();
            click_gesture.pressed.connect ((n_press, x, y) => {
                bool is_expanded = datasets_container.visible;
                datasets_container.visible = !is_expanded;
                exp_icon.icon_name = !is_expanded ? "pan-down-symbolic" : "pan-end-symbolic";

                if (!is_expanded && !history.is_loaded) {
                    load_history_datasets (history, datasets_container, datasets_list);
                }
            });
            header_box.add_controller (click_gesture);

            btn_fetch.clicked.connect (() => {
                datasets_container.visible = true;
                exp_icon.icon_name = "pan-down-symbolic";
                load_history_datasets (history, datasets_container, datasets_list);
            });

            return row_box;
        }

        private void load_history_datasets (
            GalaxyHistory history,
            Gtk.Box container,
            Gtk.ListBox list_widget
        ) {
            clear_list_box (list_widget);

            var spin = new Gtk.Spinner () {
                spinning = true,
                margin_top = 8,
                margin_bottom = 8,
                halign = Gtk.Align.CENTER
            };
            list_widget.append (spin);

            client.fetch_datasets_async.begin (history.id, (obj, res) => {
                clear_list_box (list_widget);
                try {
                    var datasets = client.fetch_datasets_async.end (res);
                    history.datasets.clear ();
                    foreach (var ds in datasets) {
                        history.datasets.add (ds);
                        var ds_row = create_dataset_row (history, ds);
                        list_widget.append (ds_row);
                    }
                    history.is_loaded = true;

                    if (datasets.size == 0) {
                        var empty_lbl = new Gtk.Label ("History is empty.") {
                            css_classes = { "dim-label" },
                            margin_top = 6,
                            margin_bottom = 6
                        };
                        list_widget.append (empty_lbl);
                    }
                } catch (GLib.Error e) {
                    var err_lbl = new Gtk.Label (@"Failed to load datasets: $(e.message)") {
                        css_classes = { "error" },
                        margin_top = 6,
                        margin_bottom = 6
                    };
                    list_widget.append (err_lbl);
                }
            });
        }

        private Gtk.Widget create_dataset_row (GalaxyHistory history, GalaxyDataset dataset) {
            var row_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6
            };

            // State Indicator Icon
            var state_icon = new Gtk.Image.from_icon_name (dataset.state.get_symbolic_icon ()) {
                tooltip_text = @"State: $(dataset.state.to_id_string ())"
            };
            state_icon.add_css_class (dataset.state.get_badge_css_class ());

            // Name and Meta Column
            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                hexpand = true
            };

            var name_lbl = new Gtk.Label (dataset.name) {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END,
                css_classes = { "caption" }
            };

            string meta_info = dataset.extension.up ();
            if (dataset.file_size > 0) {
                meta_info += @" · $(dataset.get_formatted_size ())";
            }
            var meta_lbl = new Gtk.Label (meta_info) {
                halign = Gtk.Align.START,
                css_classes = { "caption", "dim-label" }
            };

            text_box.append (name_lbl);
            text_box.append (meta_lbl);

            // Action Buttons
            var btn_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

            var btn_r = new Gtk.Button.with_label ("R") {
                tooltip_text = "Insert Reproducible R Fetch Chunk into active document",
                css_classes = { "flat", "caption" }
            };
            btn_r.clicked.connect (() => {
                string chunk = dataset.generate_r_quarto_chunk (client.server_url);
                insert_chunk_requested (chunk);
            });

            var btn_py = new Gtk.Button.with_label ("Py") {
                tooltip_text = "Insert Reproducible Python Fetch Chunk into active document",
                css_classes = { "flat", "caption" }
            };
            btn_py.clicked.connect (() => {
                string chunk = dataset.generate_python_quarto_chunk (client.server_url);
                insert_chunk_requested (chunk);
            });

            var btn_more = new Gtk.MenuButton () {
                icon_name = "view-more-horizontal-symbolic",
                tooltip_text = "More Actions",
                css_classes = { "flat" }
            };

            // Setup Contextual Popover
            var popover = new Gtk.Popover ();
            var menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 6,
                margin_end = 6
            };

            var btn_copy_url = new Gtk.Button.with_label ("Copy Download URL") {
                css_classes = { "flat" }
            };
            btn_copy_url.clicked.connect (() => {
                string url = dataset.download_url.length > 0 ? dataset.download_url : @"$(client.server_url)/api/datasets/$(dataset.id)/display";
                var clipboard = this.get_clipboard ();
                clipboard.set_text (url);
                popover.popdown ();
            });

            var btn_copy_id = new Gtk.Button.with_label ("Copy Dataset ID") {
                css_classes = { "flat" }
            };
            btn_copy_id.clicked.connect (() => {
                var clipboard = this.get_clipboard ();
                clipboard.set_text (dataset.id);
                popover.popdown ();
            });

            menu_box.append (btn_copy_url);
            menu_box.append (btn_copy_id);
            popover.set_child (menu_box);
            btn_more.popover = popover;

            btn_box.append (btn_r);
            btn_box.append (btn_py);
            btn_box.append (btn_more);

            row_box.append (state_icon);
            row_box.append (text_box);
            row_box.append (btn_box);

            return row_box;
        }

        private void clear_list_box (Gtk.ListBox box) {
            Gtk.Widget? child = box.get_first_child ();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling ();
                box.remove (child);
                child = next;
            }
        }

        private void on_search_changed () {
            string query = search_entry.text.strip ().down ();
            if (query.length == 0) {
                populate_histories_list ();
                return;
            }

            clear_histories_list ();
            foreach (var history in loaded_histories) {
                bool history_matches = query in history.name.down ();
                bool has_matching_dataset = false;

                foreach (var ds in history.datasets) {
                    if (query in ds.name.down () || query in ds.extension.down ()) {
                        has_matching_dataset = true;
                        break;
                    }
                }

                if (history_matches || has_matching_dataset) {
                    var row = create_history_row (history);
                    histories_list.append (row);
                }
            }
        }

        private void open_auth_dialog () {
            var dialog = new GalaxyAuthDialog ();
            dialog.credentials_saved.connect (() => {
                probe_connection_and_refresh ();
            });
            dialog.present (this.get_root () as Gtk.Widget);
        }
    }
}
