// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Bridges.WebSync;

namespace Imladris.UI {

    /**
     * WebSyncAuthDialog
     * Configures connection and authenticates against a self-hosted Imladris on Web instance.
     */
    public class WebSyncAuthDialog : Adw.PreferencesDialog {

        private WebSyncClient client;
        private Adw.EntryRow url_row;
        private Adw.EntryRow email_row;
        private Adw.EntryRow display_name_row;
        private Adw.PasswordEntryRow password_row;
        private Adw.EntryRow invite_row;
        private Adw.ActionRow status_row;
        private Gtk.ToggleButton mode_login_btn;
        private Gtk.ToggleButton mode_register_btn;
        private Gtk.Button btn_probe;
        private Gtk.Button btn_submit;
        private Gtk.Spinner spinner;

        public signal void authenticated_successfully (WebUser user);

        public WebSyncAuthDialog () {
            Object (title: "Connect to Imladris on Web");
            this.client = WebSyncClient.get_default ();
            setup_ui ();
        }

        private void setup_ui () {
            var page = new Adw.PreferencesPage () {
                title = "Imladris on Web",
                icon_name = "network-server-symbolic"
            };

            // 1. Instance URL Group
            var inst_group = new Adw.PreferencesGroup () {
                title = "Imladris on Web Instance",
                description = "Enter the URL of your self-hosted lab, university, or local Imladris on Web server."
            };

            url_row = new Adw.EntryRow () {
                title = "Instance URL",
                text = client.instance_url,
                input_purpose = Gtk.InputPurpose.URL
            };
            url_row.entry_activated.connect (on_submit_clicked);
            inst_group.add (url_row);

            var preset_row = new Adw.ActionRow () {
                title = "Quick Presets",
                subtitle = "Local Docker Compose / Development instances"
            };
            var preset_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                valign = Gtk.Align.CENTER
            };
            var btn_local_api = new Gtk.Button.with_label ("localhost:8787") { css_classes = { "pill" } };
            btn_local_api.clicked.connect (() => { url_row.text = "http://localhost:8787"; });
            var btn_local_web = new Gtk.Button.with_label ("localhost:8080") { css_classes = { "pill" } };
            btn_local_web.clicked.connect (() => { url_row.text = "http://localhost:8080"; });
            preset_box.append (btn_local_api);
            preset_box.append (btn_local_web);
            preset_row.add_suffix (preset_box);
            inst_group.add (preset_row);

            status_row = new Adw.ActionRow () {
                title = "Server Status",
                subtitle = client.is_authenticated && client.current_user != null
                    ? @"Signed in as $(client.current_user.display_name) ($(client.current_user.email))"
                    : "Not connected"
            };
            spinner = new Gtk.Spinner () { spinning = false, valign = Gtk.Align.CENTER };
            btn_probe = new Gtk.Button.with_label ("Test Health") {
                valign = Gtk.Align.CENTER,
                css_classes = { "pill" }
            };
            btn_probe.clicked.connect (on_probe_clicked);
            var status_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            status_box.append (spinner);
            status_box.append (btn_probe);
            status_row.add_suffix (status_box);
            inst_group.add (status_row);

            page.add (inst_group);

            // 2. Account Credentials Group
            var auth_group = new Adw.PreferencesGroup () {
                title = "Account Authentication",
                description = "Sign in to share documents, generate collaborator invites, and sync offline commits."
            };

            var mode_row = new Adw.ActionRow () {
                title = "Authentication Mode"
            };
            var mode_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
            mode_box.add_css_class ("linked");
            mode_login_btn = new Gtk.ToggleButton.with_label ("Sign In") { active = true };
            mode_register_btn = new Gtk.ToggleButton.with_label ("Register");
            mode_register_btn.set_group (mode_login_btn);
            mode_box.append (mode_login_btn);
            mode_box.append (mode_register_btn);
            mode_row.add_suffix (mode_box);
            auth_group.add (mode_row);

            email_row = new Adw.EntryRow () {
                title = "Email Address",
                text = (client.current_user != null) ? client.current_user.email : "",
                input_purpose = Gtk.InputPurpose.EMAIL
            };
            email_row.entry_activated.connect (on_submit_clicked);
            auth_group.add (email_row);

            display_name_row = new Adw.EntryRow () {
                title = "Display Name",
                text = (client.current_user != null) ? client.current_user.display_name : GLib.Environment.get_real_name (),
                visible = false
            };
            auth_group.add (display_name_row);

            password_row = new Adw.PasswordEntryRow () {
                title = "Password"
            };
            password_row.entry_activated.connect (on_submit_clicked);
            auth_group.add (password_row);

            invite_row = new Adw.EntryRow () {
                title = "Invite Token (Optional)",
                visible = false
            };
            auth_group.add (invite_row);

            mode_register_btn.toggled.connect (() => {
                bool is_reg = mode_register_btn.active;
                display_name_row.visible = is_reg;
                invite_row.visible = is_reg;
                btn_submit.label = is_reg ? "Create Account & Connect" : "Sign In & Connect";
            });

            page.add (auth_group);

            // 3. Submit Action
            var action_group = new Adw.PreferencesGroup ();
            btn_submit = new Gtk.Button.with_label ("Sign In & Connect") {
                halign = Gtk.Align.CENTER,
                css_classes = { "suggested-action", "pill" },
                margin_top = 8
            };
            btn_submit.clicked.connect (on_submit_clicked);
            action_group.add (btn_submit);
            page.add (action_group);

            this.add (page);
        }

        private void on_probe_clicked () {
            string target = url_row.text.strip ();
            if (target.length == 0) {
                status_row.subtitle = "Instance URL cannot be empty.";
                return;
            }
            btn_probe.sensitive = false;
            spinner.spinning = true;
            status_row.subtitle = @"Checking $target/health…";

            client.probe_health_async.begin (target, null, (obj, res) => {
                btn_probe.sensitive = true;
                spinner.spinning = false;
                bool ok = client.probe_health_async.end (res);
                if (ok) {
                    status_row.subtitle = @"Reachable ($target)";
                    this.add_toast (new Adw.Toast ("Imladris on Web server is reachable"));
                } else {
                    status_row.subtitle = Core.SettingsManager.get_default ().airgapped_mode
                        ? "Blocked by Air-Gapped Mode policy"
                        : @"Unable to reach $target";
                    this.add_toast (new Adw.Toast ("Server unreachable — offline commits still work locally"));
                }
            });
        }

        private void on_submit_clicked () {
            string target = url_row.text.strip ();
            string email = email_row.text.strip ();
            string password = password_row.text;

            if (target.length == 0 || email.length == 0 || password.length == 0) {
                this.add_toast (new Adw.Toast ("Please fill in URL, email, and password"));
                return;
            }

            btn_submit.sensitive = false;
            spinner.spinning = true;

            if (mode_register_btn.active) {
                string dname = display_name_row.text.strip ();
                if (dname.length == 0) dname = email;
                string inv = invite_row.text.strip ();
                client.register_async.begin (target, email, dname, password, inv.length > 0 ? inv : null, (obj, res) => {
                    btn_submit.sensitive = true;
                    spinner.spinning = false;
                    try {
                        var user = client.register_async.end (res);
                        authenticated_successfully (user);
                        this.close ();
                    } catch (GLib.Error e) {
                        status_row.subtitle = @"Registration failed: $(e.message)";
                        this.add_toast (new Adw.Toast (e.message));
                    }
                });
            } else {
                client.login_async.begin (target, email, password, (obj, res) => {
                    btn_submit.sensitive = true;
                    spinner.spinning = false;
                    try {
                        var user = client.login_async.end (res);
                        authenticated_successfully (user);
                        this.close ();
                    } catch (GLib.Error e) {
                        status_row.subtitle = @"Sign in failed: $(e.message)";
                        this.add_toast (new Adw.Toast (e.message));
                    }
                });
            }
        }
    }
}
