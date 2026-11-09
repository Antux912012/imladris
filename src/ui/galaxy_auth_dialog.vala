// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Manages Galaxy Project instance authentication and credential configuration.
 *
 * Architectural Position:
 * Libadwaita dialog presentation component.
 * Upstream caller: Imladris.UI.GalaxyPanel or Main Window Settings action.
 * Downstream dependency: Imladris.Bridges.GalaxyClient and Adw.PreferencesDialog.
 *
 * Concurrency Constraints:
 * Runs on the GLib MainContext thread. Performs non-blocking asynchronous verification
 * through GalaxyClient without freezing the GTK UI.
 */

using GLib;
using Gtk;
using Adw;
using Imladris.Bridges;

namespace Imladris.UI {

    /**
     * Modal dialog for authenticating with Galaxy bioinformatics instances.
     */
    public class GalaxyAuthDialog : Adw.PreferencesDialog {

        private GalaxyClient client;
        private Adw.EntryRow server_url_row;
        private Adw.PasswordEntryRow api_key_row;
        private Adw.ActionRow status_row;
        private Gtk.Button btn_test;
        private Gtk.Button btn_save;
        private Gtk.Spinner test_spinner;

        public signal void credentials_saved ();

        public GalaxyAuthDialog () {
            Object (title: "Galaxy Project Configuration");
            this.client = GalaxyClient.get_default ();

            setup_ui ();
        }

        private void setup_ui () {
            var page = new Adw.PreferencesPage () {
                title = "Galaxy Authentication",
                icon_name = "applications-internet-symbolic"
            };

            // Server & Instance Group
            var instance_group = new Adw.PreferencesGroup () {
                title = "Galaxy Server Instance",
                description = "Connect to an enterprise, cloud, or local Galaxy bioinformatics server."
            };

            server_url_row = new Adw.EntryRow () {
                title = "Server URL",
                text = client.server_url
            };
            instance_group.add (server_url_row);

            // Preset Server Quick Select
            var preset_row = new Adw.ActionRow () {
                title = "Public Instance Presets",
                subtitle = "Choose from major public Galaxy instances"
            };

            var preset_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                valign = Gtk.Align.CENTER
            };

            var btn_eu = new Gtk.Button.with_label ("usegalaxy.eu") {
                css_classes = { "pill", "flat" }
            };
            btn_eu.clicked.connect (() => {
                server_url_row.text = "https://usegalaxy.eu";
            });

            var btn_org = new Gtk.Button.with_label ("usegalaxy.org") {
                css_classes = { "pill", "flat" }
            };
            btn_org.clicked.connect (() => {
                server_url_row.text = "https://usegalaxy.org";
            });

            var btn_au = new Gtk.Button.with_label ("usegalaxy.org.au") {
                css_classes = { "pill", "flat" }
            };
            btn_au.clicked.connect (() => {
                server_url_row.text = "https://usegalaxy.org.au";
            });

            preset_box.append (btn_eu);
            preset_box.append (btn_org);
            preset_box.append (btn_au);
            preset_row.add_suffix (preset_box);
            instance_group.add (preset_row);

            page.add (instance_group);

            // Security & API Key Group
            var credentials_group = new Adw.PreferencesGroup () {
                title = "API Credentials",
                description = "Obtain your API Key from Galaxy: User Preferences → Manage API Key."
            };

            api_key_row = new Adw.PasswordEntryRow () {
                title = "Galaxy API Key",
                text = client.api_key
            };
            credentials_group.add (api_key_row);

            // Connection Validation Row
            status_row = new Adw.ActionRow () {
                title = "Connection Status",
                subtitle = client.is_authenticated ? "Connected as " + (client.current_user != null ? client.current_user.email : "Authenticated") : "Not validated"
            };

            test_spinner = new Gtk.Spinner () {
                spinning = false,
                valign = Gtk.Align.CENTER
            };

            btn_test = new Gtk.Button.with_label ("Test Connection") {
                valign = Gtk.Align.CENTER,
                css_classes = { "pill" }
            };
            btn_test.clicked.connect (on_test_connection_clicked);

            var action_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                valign = Gtk.Align.CENTER
            };
            action_box.append (test_spinner);
            action_box.append (btn_test);

            status_row.add_suffix (action_box);
            credentials_group.add (status_row);

            page.add (credentials_group);

            // Commit Actions Group
            var save_group = new Adw.PreferencesGroup ();
            btn_save = new Gtk.Button.with_label ("Save Credentials") {
                halign = Gtk.Align.CENTER,
                css_classes = { "suggested-action", "pill" },
                margin_top = 12
            };
            btn_save.clicked.connect (on_save_clicked);
            save_group.add (btn_save);

            page.add (save_group);

            this.add (page);
        }

        private void on_test_connection_clicked () {
            string test_url = server_url_row.text.strip ();
            string test_key = api_key_row.text.strip ();

            if (test_url.length == 0) {
                status_row.subtitle = "Server URL cannot be empty.";
                return;
            }

            if (test_key.length == 0) {
                status_row.subtitle = "API key cannot be empty.";
                return;
            }

            btn_test.sensitive = false;
            test_spinner.spinning = true;
            status_row.subtitle = "Verifying connection...";

            client.test_connection_async.begin (test_url, test_key, (obj, res) => {
                btn_test.sensitive = true;
                test_spinner.spinning = false;

                try {
                    var user = client.test_connection_async.end (res);
                    status_row.subtitle = @"Connected as $(user.username) ($(user.email))";
                    var toast = new Adw.Toast ("Galaxy connection successful");
                    this.add_toast (toast);
                } catch (GLib.Error e) {
                    status_row.subtitle = @"Failed: $(e.message)";
                    var toast = new Adw.Toast (@"Connection error: $(e.message)");
                    this.add_toast (toast);
                }
            });
        }

        private void on_save_clicked () {
            string s_url = server_url_row.text.strip ();
            string s_key = api_key_row.text.strip ();

            client.save_credentials (s_url, s_key);
            credentials_saved ();
            this.close ();
        }
    }
}
