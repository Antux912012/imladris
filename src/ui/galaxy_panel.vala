// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Renders Galaxy Project histories and datasets in the workbench quadrant.
 *
 * Architectural Position:
 * Persistent UI inspector docked in Quadrant 2 or Quadrant 3.
 * Upstream caller: Imladris.UI.PersistentPanelRegistry and DocumentPage.
 * Downstream dependency: Imladris.GalaxyClient, Imladris.GalaxyChunkGenerator, and Libadwaita list widgets.
 *
 * Concurrency Constraints:
 * Executes on the GLib MainContext thread. Dispatches network requests asynchronously
 * through GalaxyClient without blocking the GTK UI frame loop.
 */

using GLib;
using Gtk;
using Adw;

namespace Imladris.UI {

    /**
     * UI inspector panel for navigating remote Galaxy histories and inserting
     * reproducible data fetching code chunks into the active editor buffer.
     */
    public class GalaxyPanel : Gtk.Box {

        private GalaxyClient client;
        private Gtk.Image status_icon;
        private Gtk.Label status_label;
        private Gtk.Button btn_refresh;
        private Gtk.Button btn_settings;
        private Gtk.DropDown history_dropdown;
        private Gtk.SearchEntry search_entry;
        private Gtk.ListView dataset_list_view;
        private Gtk.Stack content_stack;
        private Gtk.Spinner loading_spinner;
        private Adw.StatusPage empty_status_page;

        private GLib.ListStore history_store;
        private GLib.ListStore dataset_store;
        private Gtk.CustomFilter dataset_filter;
        private Gtk.FilterListModel filter_model;
        private Gtk.SingleSelection selection_model;

        private string active_history_name = "Galaxy History";
        private string active_history_id = "";

        /**
         * Emitted when user clicks to inject an R or Python code chunk into the manuscript.
         */
        public signal void inject_code_chunk_requested (string code_chunk);

        /**
         * Emitted when user requests a workbench toast notification.
         */
        public signal void toast_notification_requested (string message);

        /**
         * Backwards-compatible signal alias for legacy workbench listeners.
         */
        public signal void insert_chunk_requested (string code_chunk);

        /**
         * Constructs a new GalaxyPanel inspector instance.
         */
        public GalaxyPanel () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

            this.client = GalaxyClient.get_default ();
            this.history_store = new GLib.ListStore (typeof (GalaxyHistory));
            this.dataset_store = new GLib.ListStore (typeof (GalaxyDataset));

            this.hexpand = true;
            this.vexpand = true;

            setup_ui ();
            connect_signals ();

            // Probe connection on launch if credentials exist
            if (client.api_key.length > 0) {
                probe_connection_and_refresh ();
            } else {
                update_status_display (false, "Disconnected");
            }
        }

        /**
         * Initializes and arranges all sub-widgets inside the vertical panel.
         */
        private void setup_ui () {
            // 1. Top Subtoolbar
            var toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };
            toolbar.add_css_class ("toolbar");
            toolbar.add_css_class ("dock-subtoolbar");

            status_icon = new Gtk.Image.from_icon_name ("network-offline-symbolic") {
                pixel_size = 14
            };

            status_label = new Gtk.Label ("Disconnected") {
                css_classes = { "caption", "dim-label" },
                hexpand = true,
                xalign = 0,
                ellipsize = Pango.EllipsizeMode.END
            };

            btn_refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Reload Histories from Galaxy",
                css_classes = { "flat" }
            };
            btn_refresh.clicked.connect (on_refresh_clicked);

            btn_settings = new Gtk.Button.from_icon_name ("emblem-system-symbolic") {
                tooltip_text = "Configure Galaxy Connection",
                css_classes = { "flat" }
            };
            btn_settings.clicked.connect (open_auth_dialog);

            toolbar.append (status_icon);
            toolbar.append (status_label);
            toolbar.append (btn_refresh);
            toolbar.append (btn_settings);
            this.append (toolbar);

            // 2. History Selector DropDown
            var selector_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_start = 8,
                margin_end = 8,
                margin_top = 4,
                margin_bottom = 4
            };

            var dropdown_factory = new Gtk.SignalListItemFactory ();
            dropdown_factory.setup.connect ((item) => {
                var list_item = (Gtk.ListItem) item;
                var lbl = new Gtk.Label ("") {
                    xalign = 0,
                    ellipsize = Pango.EllipsizeMode.END
                };
                list_item.set_child (lbl);
            });
            dropdown_factory.bind.connect ((item) => {
                var list_item = (Gtk.ListItem) item;
                var lbl = (Gtk.Label) list_item.get_child ();
                var hist = (GalaxyHistory) list_item.get_item ();
                if (lbl != null && hist != null) {
                    lbl.set_text (hist.name);
                }
            });

            history_dropdown = new Gtk.DropDown (history_store, null) {
                factory = dropdown_factory,
                list_factory = dropdown_factory,
                hexpand = true
            };
            history_dropdown.notify["selected-item"].connect (on_history_selection_changed);
            selector_box.append (history_dropdown);
            this.append (selector_box);

            // 3. Search & Filter Entry
            var search_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_start = 8,
                margin_end = 8,
                margin_top = 2,
                margin_bottom = 4
            };

            search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Filter datasets by name or format...",
                hexpand = true
            };
            search_entry.search_changed.connect (on_search_query_changed);
            search_box.append (search_entry);
            this.append (search_box);

            // 4. Content Stack (Spinner, Empty page, and Dataset List)
            content_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                hexpand = true,
                vexpand = true
            };

            loading_spinner = new Gtk.Spinner () {
                spinning = false,
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER,
                width_request = 36,
                height_request = 36
            };
            content_stack.add_named (loading_spinner, "loading");

            empty_status_page = new Adw.StatusPage () {
                icon_name = "applications-internet-symbolic",
                title = "No Datasets Found",
                description = "Configure your Galaxy connection or select an active history."
            };
            content_stack.add_named (empty_status_page, "empty");

            // 5. ListView with Custom Filter and SignalListItemFactory
            dataset_filter = new Gtk.CustomFilter (dataset_filter_func);
            filter_model = new Gtk.FilterListModel (dataset_store, dataset_filter);
            selection_model = new Gtk.SingleSelection (filter_model);

            var list_factory = new Gtk.SignalListItemFactory ();
            list_factory.setup.connect (on_factory_setup);
            list_factory.bind.connect (on_factory_bind);
            list_factory.unbind.connect (on_factory_unbind);

            dataset_list_view = new Gtk.ListView (selection_model, list_factory) {
                css_classes = { "rich-list", "separators" }
            };

            var scrolled_view = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                child = dataset_list_view,
                hexpand = true,
                vexpand = true
            };
            content_stack.add_named (scrolled_view, "datasets");

            content_stack.set_visible_child_name ("empty");
            this.append (content_stack);
        }

        /**
         * Connects event handlers to client state notifications.
         */
        private void connect_signals () {
            client.authenticated_changed.connect ((auth_state) => {
                string server_name = extract_host (client.server_url);
                if (auth_state) {
                    update_status_display (true, @"$(server_name) • Connected");
                } else {
                    update_status_display (false, @"$(server_name) • Offline");
                }
            });

            client.error_occurred.connect ((msg) => {
                update_status_display (false, "Error: " + msg);
            });
        }

        /**
         * Filter predicate evaluated by Gtk.CustomFilter for real-time search.
         */
        private bool dataset_filter_func (GLib.Object item) {
            var ds = item as GalaxyDataset;
            if (ds == null) {
                return false;
            }

            string query = search_entry.text.strip ().down ();
            if (query.length == 0) {
                return true;
            }

            return (ds.name.down ().contains (query) || ds.extension.down ().contains (query));
        }

        /**
         * Handles user changes in the search entry box.
         */
        private void on_search_query_changed () {
            dataset_filter.changed (Gtk.FilterChange.DIFFERENT);
        }

        /**
         * Setups individual list row item containers.
         */
        private void on_factory_setup (GLib.Object item) {
            var list_item = (Gtk.ListItem) item;

            var row_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                margin_start = 8,
                margin_end = 8,
                margin_top = 6,
                margin_bottom = 6
            };
            row_box.add_css_class ("galaxy-dataset-row");

            // State Pill Badge
            var state_badge = new Gtk.Label ("●") {
                valign = Gtk.Align.CENTER
            };
            state_badge.add_css_class ("caption");
            row_box.append (state_badge);

            // Title and Details Container
            var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                hexpand = true,
                valign = Gtk.Align.CENTER
            };

            var title_label = new Gtk.Label ("") {
                xalign = 0,
                ellipsize = Pango.EllipsizeMode.END,
                use_markup = true
            };
            title_label.add_css_class ("bold");

            var meta_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            var ext_label = new Gtk.Label ("") {
                xalign = 0
            };
            ext_label.add_css_class ("caption");
            ext_label.add_css_class ("monospace");

            var size_label = new Gtk.Label ("") {
                xalign = 0
            };
            size_label.add_css_class ("caption");
            size_label.add_css_class ("dim-label");

            meta_box.append (ext_label);
            meta_box.append (size_label);

            info_box.append (title_label);
            info_box.append (meta_box);
            row_box.append (info_box);

            // Action Buttons for Chunk Injection
            var action_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                valign = Gtk.Align.CENTER
            };

            var btn_r = new Gtk.Button.with_label ("+ R") {
                tooltip_text = "Inject reproducible R Quarto chunk into manuscript",
                css_classes = { "suggested-action", "flat", "small-button" }
            };

            var btn_py = new Gtk.Button.with_label ("+ Py") {
                tooltip_text = "Inject reproducible Python Quarto chunk into manuscript",
                css_classes = { "accent", "flat", "small-button" }
            };

            action_box.append (btn_r);
            action_box.append (btn_py);
            row_box.append (action_box);

            list_item.set_child (row_box);
        }

        /**
         * Binds domain dataset properties to UI row widgets and attaches action handlers.
         */
        private void on_factory_bind (GLib.Object item) {
            var list_item = (Gtk.ListItem) item;
            var row_box = (Gtk.Box) list_item.get_child ();
            var ds = (GalaxyDataset) list_item.get_item ();

            if (row_box == null || ds == null) {
                return;
            }

            // Retrieve child widgets
            var state_badge = (Gtk.Label) row_box.get_first_child ();
            var info_box = (Gtk.Box) state_badge.get_next_sibling ();
            var action_box = (Gtk.Box) info_box.get_next_sibling ();

            var title_label = (Gtk.Label) info_box.get_first_child ();
            var meta_box = (Gtk.Box) title_label.get_next_sibling ();
            var ext_label = (Gtk.Label) meta_box.get_first_child ();
            var size_label = (Gtk.Label) ext_label.get_next_sibling ();

            var btn_r = (Gtk.Button) action_box.get_first_child ();
            var btn_py = (Gtk.Button) btn_r.get_next_sibling ();

            // Set state indicator badge color and symbol
            var state_enum = ds.get_state_enum ();
            state_badge.set_text ("●");
            state_badge.tooltip_text = @"State: $(ds.state)";
            if (state_enum == GalaxyDatasetState.OK) {
                state_badge.css_classes = { "caption", "success" };
            } else if (state_enum == GalaxyDatasetState.RUNNING || state_enum == GalaxyDatasetState.QUEUED) {
                state_badge.css_classes = { "caption", "warning" };
            } else if (state_enum == GalaxyDatasetState.ERROR) {
                state_badge.css_classes = { "caption", "error" };
            } else {
                state_badge.css_classes = { "caption", "dim-label" };
            }

            // Set labels
            title_label.set_markup (@"<b>#$(ds.hid):</b> $(GLib.Markup.escape_text (ds.name))");
            ext_label.set_text (@"[$(ds.extension.up ())]");
            size_label.set_text (ds.get_formatted_size ());

            // Connect button signals
            ulong r_id = btn_r.clicked.connect (() => {
                string chunk = GalaxyChunkGenerator.generate_chunk (
                    ds,
                    client.server_url,
                    active_history_name,
                    TargetLanguage.R_QUARTO
                );
                inject_code_chunk_requested (chunk);
                insert_chunk_requested (chunk);
                toast_notification_requested (@"Injected R chunk for dataset #$(ds.hid)");
            });

            ulong py_id = btn_py.clicked.connect (() => {
                string chunk = GalaxyChunkGenerator.generate_chunk (
                    ds,
                    client.server_url,
                    active_history_name,
                    TargetLanguage.PYTHON_QUARTO
                );
                inject_code_chunk_requested (chunk);
                insert_chunk_requested (chunk);
                toast_notification_requested (@"Injected Python chunk for dataset #$(ds.hid)");
            });

            // Store signal connection IDs on the list item for clean detachment
            list_item.set_data<ulong> ("r_signal", r_id);
            list_item.set_data<ulong> ("py_signal", py_id);
            list_item.set_data<Gtk.Button> ("r_btn", btn_r);
            list_item.set_data<Gtk.Button> ("py_btn", btn_py);
        }

        /**
         * Disconnects signal handlers to prevent memory leaks during list item recycling.
         */
        private void on_factory_unbind (GLib.Object item) {
            var list_item = (Gtk.ListItem) item;
            var btn_r = list_item.get_data<Gtk.Button> ("r_btn");
            var btn_py = list_item.get_data<Gtk.Button> ("py_btn");
            ulong r_id = list_item.get_data<ulong> ("r_signal");
            ulong py_id = list_item.get_data<ulong> ("py_signal");

            if (btn_r != null && r_id > 0) {
                btn_r.disconnect (r_id);
            }
            if (btn_py != null && py_id > 0) {
                btn_py.disconnect (py_id);
            }

            list_item.set_data<ulong> ("r_signal", 0);
            list_item.set_data<ulong> ("py_signal", 0);
            list_item.set_data ("r_btn", null);
            list_item.set_data ("py_btn", null);
        }

        /**
         * Updates status bar icon and textual description.
         */
        private void update_status_display (bool online, string message) {
            status_label.label = message;
            if (online) {
                status_icon.icon_name = "network-wireless-signal-excellent-symbolic";
                status_label.remove_css_class ("dim-label");
                status_label.remove_css_class ("error");
                status_label.add_css_class ("success");
            } else {
                status_icon.icon_name = "network-offline-symbolic";
                status_label.remove_css_class ("success");
                status_label.add_css_class ("dim-label");
            }
        }

        /**
         * Extracts clean host name from server URL for compact UI display.
         */
        private string extract_host (string url) {
            string host = url.replace ("https://", "").replace ("http://", "");
            int slash_idx = host.index_of_char ('/');
            if (slash_idx > 0) {
                host = host.substring (0, slash_idx);
            }
            return host.length > 0 ? host : "Galaxy";
        }

        /**
         * Initiates asynchronous verification of Galaxy credentials and downloads histories.
         */
        public void probe_connection_and_refresh () {
            string host = extract_host (client.server_url);
            update_status_display (false, @"Connecting to $(host)...");

            client.verify_connection_async.begin (null, (obj, res) => {
                try {
                    string identity = client.verify_connection_async.end (res);
                    update_status_display (true, @"$(host) • $(identity)");
                    refresh_histories ();
                } catch (GLib.Error e) {
                    update_status_display (false, @"$(host) • Disconnected");
                }
            });
        }

        /**
         * Refreshes remote Galaxy histories asynchronously.
         */
        public void refresh_histories () {
            show_loading (true);

            client.fetch_histories_async.begin (null, (obj, res) => {
                show_loading (false);

                try {
                    var histories = client.fetch_histories_async.end (res);
                    history_store.remove_all ();

                    for (int i = 0; i < histories.length; i++) {
                        history_store.append (histories[i]);
                    }

                    if (histories.length > 0) {
                        history_dropdown.selected = 0;
                        var first_hist = histories[0];
                        load_history_datasets (first_hist.id, first_hist.name);
                    } else {
                        dataset_store.remove_all ();
                        content_stack.set_visible_child_name ("empty");
                    }
                } catch (GLib.Error e) {
                    update_status_display (false, @"Refresh error: $(e.message)");
                    content_stack.set_visible_child_name ("empty");
                }
            });
        }

        /**
         * Triggered when the user changes the active history in the dropdown.
         */
        private void on_history_selection_changed () {
            var selected_obj = history_dropdown.selected_item as GalaxyHistory;
            if (selected_obj != null) {
                load_history_datasets (selected_obj.id, selected_obj.name);
            }
        }

        /**
         * Downloads datasets for the selected history.
         */
        private void load_history_datasets (string history_id, string history_name) {
            this.active_history_id = history_id;
            this.active_history_name = history_name;

            show_loading (true);

            client.fetch_history_datasets_async.begin (history_id, null, (obj, res) => {
                show_loading (false);

                try {
                    var datasets = client.fetch_history_datasets_async.end (res);
                    dataset_store.remove_all ();

                    for (int i = 0; i < datasets.length; i++) {
                        dataset_store.append (datasets[i]);
                    }

                    if (datasets.length > 0) {
                        content_stack.set_visible_child_name ("datasets");
                    } else {
                        empty_status_page.title = "No Datasets in History";
                        empty_status_page.description = @"History '$(history_name)' contains no files.";
                        content_stack.set_visible_child_name ("empty");
                    }
                } catch (GLib.Error e) {
                    empty_status_page.title = "Fetch Failed";
                    empty_status_page.description = e.message;
                    content_stack.set_visible_child_name ("empty");
                }
            });
        }

        /**
         * Toggles spinner visibility in the content stack.
         */
        private void show_loading (bool loading) {
            if (loading) {
                loading_spinner.spinning = true;
                content_stack.set_visible_child_name ("loading");
            } else {
                loading_spinner.spinning = false;
            }
        }

        /**
         * Toolbar refresh button click handler.
         */
        private void on_refresh_clicked () {
            probe_connection_and_refresh ();
        }

        /**
         * Opens the Galaxy authentication configuration modal dialog.
         */
        private void open_auth_dialog () {
            var dialog = new GalaxyAuthDialog ();
            dialog.credentials_saved.connect (() => {
                probe_connection_and_refresh ();
            });
            dialog.present (this.get_root () as Gtk.Widget);
        }
    }
}
