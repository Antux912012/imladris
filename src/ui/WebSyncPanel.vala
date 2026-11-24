// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Bridges.WebSync;
using Imladris.Services;

namespace Imladris.UI {

    /**
     * WebSyncPanel
     * Native Libadwaita dockable panel for Imladris on Web integration
     * (Share document, offline-first git-style commits, auto-sync on reconnect).
     */
    public class WebSyncPanel : Gtk.Box {

        private unowned DocumentPage doc_page;
        private unowned Window? main_window;
        private WebSyncService sync_service;
        private WebSyncClient client;

        private Gtk.Label conn_status_lbl;
        private Gtk.Button btn_auth;
        private Gtk.Button btn_logout;
        private Gtk.Stack body_stack;

        // Share (Unlinked) View
        private Adw.ComboRow workspace_combo;
        private Gee.ArrayList<WebWorkspace> loaded_workspaces;
        private Adw.EntryRow new_ws_row;
        private Adw.EntryRow remote_path_row;
        private Adw.EntryRow initial_msg_row;
        private Adw.SwitchRow share_auto_row;
        private Gtk.Button btn_share_doc;

        // Linked Sync View
        private Adw.ActionRow linked_ws_row;
        private Gtk.Label linked_status_pill;
        private Adw.Banner conflict_banner;
        private Adw.EntryRow commit_msg_row;
        private Gtk.Label diff_summary_lbl;
        private Gtk.Button btn_commit;
        private Gtk.Button btn_sync_pending;
        private Gtk.Button btn_pull;
        private Adw.SwitchRow auto_commit_row;
        private Adw.PreferencesGroup pending_group;
        private Adw.PreferencesGroup history_group;
        private Gee.ArrayList<Gtk.Widget> pending_rows = new Gee.ArrayList<Gtk.Widget> ();
        private Gee.ArrayList<Gtk.Widget> history_rows = new Gee.ArrayList<Gtk.Widget> ();
        private bool syncing_switch = false;

        private ulong auth_hid = 0;
        private ulong online_hid = 0;
        private ulong link_hid = 0;
        private ulong conn_hid = 0;

        public WebSyncPanel (DocumentPage page, Window? win) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.doc_page = page;
            this.main_window = win;
            this.sync_service = WebSyncService.get_default ();
            this.client = sync_service.get_client ();
            this.loaded_workspaces = new Gee.ArrayList<WebWorkspace> ();
            this.hexpand = true;
            this.vexpand = true;

            setup_ui ();

            auth_hid = client.auth_state_changed.connect ((ok, user) => {
                refresh_ui ();
                if (ok) refresh_workspaces_async.begin ();
            });
            online_hid = client.online_state_changed.connect ((on) => {
                refresh_ui ();
            });
            link_hid = sync_service.link_updated.connect ((key) => {
                if (key == get_doc_key ()) {
                    refresh_ui ();
                }
            });
            conn_hid = sync_service.connectivity_changed.connect ((avail) => {
                refresh_ui ();
            });

            refresh_ui ();
            if (client.is_authenticated && !Core.SettingsManager.get_default ().airgapped_mode) {
                refresh_workspaces_async.begin ();
            }
        }

        public void cleanup () {
            if (auth_hid != 0) { client.disconnect (auth_hid); auth_hid = 0; }
            if (online_hid != 0) { client.disconnect (online_hid); online_hid = 0; }
            if (link_hid != 0) { sync_service.disconnect (link_hid); link_hid = 0; }
            if (conn_hid != 0) { sync_service.disconnect (conn_hid); conn_hid = 0; }
        }

        public string get_doc_key () {
            if (doc_page.file_location != null && doc_page.file_location.get_path () != null) {
                return doc_page.file_location.get_path ();
            }
            return @"unsaved://$(doc_page.doc_id)";
        }

        private string get_default_remote_filename () {
            if (doc_page.file_location != null) {
                return doc_page.file_location.get_basename ();
            }
            if (doc_page.initial_title.length > 0) {
                return doc_page.initial_title;
            }
            return "document.qmd";
        }

        private void toast (string msg) {
            if (main_window != null) {
                main_window.show_toast (msg);
            }
        }

        private void setup_ui () {
            // 1. Compact Header Toolbar
            var top_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_start = 8, margin_end = 8, margin_top = 4, margin_bottom = 4
            };
            top_bar.add_css_class ("dock-subtoolbar");

            top_bar.append (new Gtk.Image.from_icon_name ("network-server-symbolic") { pixel_size = 16 });
            conn_status_lbl = new Gtk.Label ("Imladris on Web") {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                css_classes = { "caption" }
            };
            top_bar.append (conn_status_lbl);

            btn_auth = new Gtk.Button.with_label ("Connect…") {
                tooltip_text = "Sign in or configure Imladris on Web server"
            };
            btn_auth.add_css_class ("flat");
            btn_auth.add_css_class ("ribbon-compact-btn");
            btn_auth.clicked.connect (open_auth_dialog);
            top_bar.append (btn_auth);

            btn_logout = new Gtk.Button.from_icon_name ("system-log-out-symbolic") {
                tooltip_text = "Sign Out",
                visible = false
            };
            btn_logout.add_css_class ("flat");
            btn_logout.clicked.connect (() => {
                client.logout_async.begin ((obj, res) => {
                    client.logout_async.end (res);
                    toast ("Signed out of Imladris on Web");
                });
            });
            top_bar.append (btn_logout);
            this.append (top_bar);

            // 2. Body Stack: "share" (unlinked) vs "linked"
            body_stack = new Gtk.Stack () {
                hexpand = true,
                vexpand = true
            };
            body_stack.add_named (build_share_view (), "share");
            body_stack.add_named (build_linked_view (), "linked");

            var scroller = new Gtk.ScrolledWindow () {
                child = body_stack,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                hexpand = true,
                vexpand = true
            };
            this.append (scroller);
        }

        private Gtk.Widget build_share_view () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_start = 12, margin_end = 12, margin_top = 12, margin_bottom = 14
            };

            var ws_group = new Adw.PreferencesGroup () {
                title = "Share to Imladris on Web",
                description = "Publish to a workspace for browser co-authoring and offline git-style commits."
            };

            workspace_combo = new Adw.ComboRow () {
                title = "Workspace",
                model = new Gtk.StringList ({ "(Connect to load workspaces)" })
            };
            var btn_refresh_ws = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh workspaces",
                valign = Gtk.Align.CENTER
            };
            btn_refresh_ws.add_css_class ("flat");
            btn_refresh_ws.clicked.connect (() => {
                refresh_workspaces_async.begin ();
            });
            workspace_combo.add_suffix (btn_refresh_ws);
            ws_group.add (workspace_combo);

            new_ws_row = new Adw.EntryRow () {
                title = "New Workspace Name"
            };
            var btn_create_ws = new Gtk.Button.with_label ("Create") {
                valign = Gtk.Align.CENTER
            };
            btn_create_ws.clicked.connect (on_create_workspace_clicked);
            new_ws_row.add_suffix (btn_create_ws);
            ws_group.add (new_ws_row);

            box.append (ws_group);

            var doc_group = new Adw.PreferencesGroup ();
            remote_path_row = new Adw.EntryRow () {
                title = "Remote Path",
                text = get_default_remote_filename ()
            };
            doc_group.add (remote_path_row);

            initial_msg_row = new Adw.EntryRow () {
                title = "Commit Message"
            };
            doc_group.add (initial_msg_row);

            share_auto_row = new Adw.SwitchRow () {
                title = "Auto-commit on reconnect",
                active = true
            };
            doc_group.add (share_auto_row);
            box.append (doc_group);

            btn_share_doc = new Gtk.Button.with_label ("Share & Push") {
                css_classes = { "suggested-action", "pill" },
                halign = Gtk.Align.START
            };
            btn_share_doc.clicked.connect (on_share_document_clicked);
            box.append (btn_share_doc);

            return box;
        }

        private Gtk.Widget build_linked_view () {
            var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            conflict_banner = new Adw.Banner ("Remote document changed while offline.") {
                button_label = "Pull Remote",
                revealed = false
            };
            conflict_banner.button_clicked.connect (on_pull_clicked);
            outer.append (conflict_banner);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_start = 12, margin_end = 12, margin_top = 10, margin_bottom = 14
            };

            // 1. Workspace Link Group
            var ws_group = new Adw.PreferencesGroup ();
            linked_ws_row = new Adw.ActionRow () {
                title = "Workspace",
                subtitle = ""
            };
            linked_status_pill = new Gtk.Label ("Synced") { valign = Gtk.Align.CENTER };
            linked_status_pill.add_css_class ("web-sync-pill");
            linked_ws_row.add_suffix (linked_status_pill);
            ws_group.add (linked_ws_row);

            var link_actions_row = new Adw.ActionRow () {
                title = "Collaborate"
            };
            var act_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) { valign = Gtk.Align.CENTER };

            var btn_invite = new Gtk.Button.with_label ("Copy Invite");
            btn_invite.add_css_class ("flat");
            btn_invite.clicked.connect (on_copy_invite_clicked);

            var btn_open_web = new Gtk.Button.with_label ("Open Web");
            btn_open_web.add_css_class ("flat");
            btn_open_web.clicked.connect (() => {
                var link = sync_service.get_link (get_doc_key ());
                if (link != null) {
                    try {
                        GLib.AppInfo.launch_default_for_uri (link.get_web_workspace_url (), null);
                    } catch (GLib.Error e) {
                        toast (@"Could not open browser: $(e.message)");
                    }
                }
            });

            var btn_unlink = new Gtk.Button.with_label ("Unlink");
            btn_unlink.add_css_class ("flat");
            btn_unlink.clicked.connect (() => {
                sync_service.unlink_document (get_doc_key ());
                toast ("Unlinked document from Imladris on Web");
            });

            act_box.append (btn_invite);
            act_box.append (btn_open_web);
            act_box.append (btn_unlink);
            link_actions_row.add_suffix (act_box);
            ws_group.add (link_actions_row);
            box.append (ws_group);

            // 2. Git-Style Commit Group
            var commit_group = new Adw.PreferencesGroup () {
                title = "Revision Sync"
            };
            diff_summary_lbl = new Gtk.Label ("Clean") {
                css_classes = { "caption", "dim-label", "numeric" },
                valign = Gtk.Align.CENTER
            };
            commit_group.set_header_suffix (diff_summary_lbl);

            commit_msg_row = new Adw.EntryRow () {
                title = "Commit Message (optional)"
            };
            commit_msg_row.entry_activated.connect (on_commit_clicked);
            commit_group.add (commit_msg_row);

            var commit_act_row = new Adw.ActionRow () {
                title = "Actions"
            };
            var c_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            btn_commit = new Gtk.Button.with_label ("Commit & Push");
            btn_commit.add_css_class ("suggested-action");
            btn_commit.clicked.connect (on_commit_clicked);

            btn_sync_pending = new Gtk.Button.with_label ("Sync");
            btn_sync_pending.clicked.connect (on_sync_pending_clicked);

            btn_pull = new Gtk.Button.with_label ("Pull");
            btn_pull.clicked.connect (on_pull_clicked);

            c_box.append (btn_commit);
            c_box.append (btn_sync_pending);
            c_box.append (btn_pull);
            commit_act_row.add_suffix (c_box);
            commit_group.add (commit_act_row);

            auto_commit_row = new Adw.SwitchRow () {
                title = "Auto-commit on save & reconnect",
                active = true
            };
            auto_commit_row.notify["active"].connect (() => {
                if (syncing_switch) return;
                sync_service.set_auto_commit (get_doc_key (), auto_commit_row.active);
            });
            commit_group.add (auto_commit_row);
            box.append (commit_group);

            // 3. Pending Offline Commits
            pending_group = new Adw.PreferencesGroup () {
                title = "Pending Offline Commits",
                visible = false
            };
            box.append (pending_group);

            // 4. Remote Revision History
            history_group = new Adw.PreferencesGroup () {
                title = "Web Revision History"
            };
            var btn_ref_hist = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Refresh remote history"
            };
            btn_ref_hist.add_css_class ("flat");
            btn_ref_hist.clicked.connect (() => {
                refresh_remote_history_async.begin ();
            });
            history_group.set_header_suffix (btn_ref_hist);
            box.append (history_group);

            outer.append (box);
            return outer;
        }

        public void open_auth_dialog () {
            var dlg = new WebSyncAuthDialog ();
            dlg.authenticated_successfully.connect ((user) => {
                toast (@"Connected to Imladris on Web as $(user.display_name)");
                refresh_ui ();
                refresh_workspaces_async.begin ();
                sync_service.trigger_auto_reconnect_sync ();
            });
            dlg.present (main_window);
        }

        public void refresh_ui () {
            bool airgapped = Core.SettingsManager.get_default ().airgapped_mode;
            if (airgapped) {
                conn_status_lbl.label = "Air-Gapped Mode (Offline Only)";
            } else if (client.is_authenticated && client.current_user != null) {
                string state_word = sync_service.is_network_available () ? "Online" : "Offline";
                conn_status_lbl.label = @"$(client.current_user.display_name) ($state_word)";
            } else {
                conn_status_lbl.label = @"Not signed in — $(client.instance_url)";
            }

            btn_auth.label = client.is_authenticated ? "Account…" : "Connect…";
            btn_logout.visible = client.is_authenticated;

            string key = get_doc_key ();
            var link = sync_service.get_link (key);
            if (link == null) {
                body_stack.visible_child_name = "share";
                if (remote_path_row.text.strip ().length == 0) {
                    remote_path_row.text = get_default_remote_filename ();
                }
                return;
            }

            body_stack.visible_child_name = "linked";
            linked_ws_row.title = link.workspace_name;
            linked_ws_row.subtitle = link.remote_rel_path;

            var status = sync_service.get_status_for_doc (key);
            linked_status_pill.label = status.to_badge_label (link.pending_commits.size);
            linked_status_pill.remove_css_class ("synced");
            linked_status_pill.remove_css_class ("pending");
            linked_status_pill.remove_css_class ("conflict");
            linked_status_pill.remove_css_class ("offline");
            linked_status_pill.add_css_class (status.to_css_class ());

            conflict_banner.revealed = link.has_conflict;

            syncing_switch = true;
            auto_commit_row.active = link.auto_commit_on_reconnect;
            syncing_switch = false;

            bool online_ready = sync_service.is_network_available () && client.is_authenticated && !airgapped;
            btn_commit.label = online_ready ? "Commit & Push" : "Commit Offline";
            btn_sync_pending.label = link.pending_commits.size > 0
                ? @"Sync ($(link.pending_commits.size))"
                : "Sync";
            btn_sync_pending.sensitive = (link.pending_commits.size > 0) && online_ready;
            btn_pull.sensitive = online_ready;

            string live = doc_page.get_clean_source_text ();
            string? base_blob = sync_service.load_object_blob (link.get_latest_local_sha256 ());
            var diff = WebSyncUtils.compute_diff_summary (base_blob ?? "", live);
            diff_summary_lbl.label = diff.changed
                ? @"+$(diff.added) / -$(diff.removed)"
                : "Clean";

            foreach (var r in pending_rows) {
                pending_group.remove (r);
            }
            pending_rows.clear ();
            pending_group.visible = (link.pending_commits.size > 0);
            for (int i = link.pending_commits.size - 1; i >= 0; i--) {
                var c = link.pending_commits.get (i);
                string tag = c.is_auto ? "auto" : "manual";
                var row = new Adw.ActionRow () {
                    title = c.message,
                    subtitle = @"$(c.short_hash ()) • $tag • +$(c.lines_added)/-$(c.lines_removed) • $(WebSyncUtils.format_timestamp (c.created_at))",
                    use_markup = false
                };
                row.add_prefix (new Gtk.Image.from_icon_name ("document-open-recent-symbolic"));
                pending_group.add (row);
                pending_rows.add (row);
            }
        }

        private async void refresh_workspaces_async () {
            if (!client.is_authenticated) return;
            try {
                loaded_workspaces = yield client.list_workspaces_async ();
                var names = new string[loaded_workspaces.size];
                for (int i = 0; i < loaded_workspaces.size; i++) {
                    var w = loaded_workspaces.get (i);
                    names[i] = @"$(w.name) ($(w.role))";
                }
                if (names.length == 0) {
                    workspace_combo.model = new Gtk.StringList ({ "(No workspaces yet)" });
                } else {
                    workspace_combo.model = new Gtk.StringList (names);
                    workspace_combo.selected = 0;
                }
            } catch (GLib.Error e) {
                workspace_combo.model = new Gtk.StringList ({ @"Offline: $(e.message)" });
            }
        }

        private void on_create_workspace_clicked () {
            string name = new_ws_row.text.strip ();
            if (name.length == 0) return;
            if (!client.is_authenticated) {
                open_auth_dialog ();
                return;
            }
            client.create_workspace_async.begin (name, "SHARED", (obj, res) => {
                try {
                    var ws = client.create_workspace_async.end (res);
                    new_ws_row.text = "";
                    toast (@"Created workspace '$(ws.name)' on Imladris Web");
                    refresh_workspaces_async.begin ();
                } catch (GLib.Error e) {
                    toast (@"Failed to create workspace: $(e.message)");
                }
            });
        }

        private void on_share_document_clicked () {
            if (!client.is_authenticated) {
                open_auth_dialog ();
                return;
            }
            if (loaded_workspaces.size == 0) {
                toast ("Select or create a workspace first");
                return;
            }
            uint sel = workspace_combo.selected;
            if (sel >= loaded_workspaces.size) sel = 0;
            var ws = loaded_workspaces.get ((int) sel);

            string rel_path = remote_path_row.text.strip ();
            if (rel_path.length == 0) rel_path = get_default_remote_filename ();
            string init_msg = initial_msg_row.text.strip ();
            bool auto_c = share_auto_row.active;

            btn_share_doc.sensitive = false;
            sync_service.share_document_async.begin (
                get_doc_key (),
                ws.id,
                ws.name,
                ws.slug,
                rel_path,
                doc_page.get_clean_source_text (),
                init_msg.length > 0 ? init_msg : null,
                auto_c,
                (obj, res) => {
                    btn_share_doc.sensitive = true;
                    try {
                        sync_service.share_document_async.end (res);
                        refresh_ui ();
                        refresh_remote_history_async.begin ();
                    } catch (GLib.Error e) {
                        toast (@"Share failed: $(e.message)");
                    }
                }
            );
        }

        private void on_commit_clicked () {
            string msg = commit_msg_row.text.strip ();
            btn_commit.sensitive = false;
            sync_service.commit_document_async.begin (
                get_doc_key (),
                doc_page.get_clean_source_text (),
                msg.length > 0 ? msg : null,
                false,
                false,
                (obj, res) => {
                    btn_commit.sensitive = true;
                    try {
                        bool synced = sync_service.commit_document_async.end (res);
                        commit_msg_row.text = "";
                        refresh_ui ();
                        if (synced) {
                            refresh_remote_history_async.begin ();
                        }
                    } catch (GLib.Error e) {
                        toast (@"Commit failed: $(e.message)");
                    }
                }
            );
        }

        private void on_sync_pending_clicked () {
            btn_sync_pending.sensitive = false;
            sync_service.sync_pending_commits_async.begin (
                get_doc_key (),
                doc_page.get_clean_source_text (),
                false,
                (obj, res) => {
                    try {
                        sync_service.sync_pending_commits_async.end (res);
                        refresh_ui ();
                        refresh_remote_history_async.begin ();
                    } catch (GLib.Error e) {
                        toast (@"Sync failed: $(e.message)");
                        refresh_ui ();
                    }
                }
            );
        }

        private void on_pull_clicked () {
            btn_pull.sensitive = false;
            sync_service.pull_remote_document_async.begin (get_doc_key (), (obj, res) => {
                btn_pull.sensitive = true;
                try {
                    string remote_text = sync_service.pull_remote_document_async.end (res);
                    doc_page.set_initial_content (remote_text, false);
                    refresh_ui ();
                    refresh_remote_history_async.begin ();
                } catch (GLib.Error e) {
                    toast (@"Pull failed: $(e.message)");
                }
            });
        }

        private void on_copy_invite_clicked () {
            var link = sync_service.get_link (get_doc_key ());
            if (link == null) return;
            client.create_invite_url_async.begin (link.workspace_id, "EDITOR", 5, 72, (obj, res) => {
                try {
                    string url = client.create_invite_url_async.end (res);
                    var display = Gdk.Display.get_default ();
                    if (display != null) {
                        display.get_clipboard ().set_text (url);
                    }
                    toast ("Copied collaborator invite link to clipboard");
                } catch (GLib.Error e) {
                    toast (@"Could not create invite link: $(e.message)");
                }
            });
        }

        private async void refresh_remote_history_async () {
            var link = sync_service.get_link (get_doc_key ());
            if (link == null || !client.is_authenticated) return;

            foreach (var r in history_rows) {
                history_group.remove (r);
            }
            history_rows.clear ();

            try {
                var snaps = yield client.list_snapshots_async (link.workspace_id, link.remote_rel_path);
                if (snaps.size == 0) {
                    var empty = new Adw.ActionRow () {
                        title = "No remote revisions yet"
                    };
                    history_group.add (empty);
                    history_rows.add (empty);
                    return;
                }
                int limit = snaps.size < 20 ? snaps.size : 20;
                for (int i = 0; i < limit; i++) {
                    var rev = snaps.get (i);
                    var row = new Adw.ActionRow () {
                        title = rev.message,
                        subtitle = @"$(rev.short_hash ()) • $(rev.updated_by_name) • $(WebSyncUtils.format_timestamp (rev.updated_at))",
                        use_markup = false
                    };
                    row.add_prefix (new Gtk.Image.from_icon_name ("emblem-ok-symbolic"));
                    history_group.add (row);
                    history_rows.add (row);
                }
            } catch (GLib.Error e) {
                var err_row = new Adw.ActionRow () {
                    title = "Offline — Remote history unavailable",
                    subtitle = e.message,
                    use_markup = false
                };
                history_group.add (err_row);
                history_rows.add (err_row);
            }
        }
    }
}
