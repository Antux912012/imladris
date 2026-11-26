// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Core;
using Imladris.Services;

namespace Imladris.UI {

    public class ReviewCommentsPanel : Gtk.Box {
        private ReviewCommentService service;
        private unowned Window? parent_window;
        private Gtk.Box threads_box;
        private Gtk.Label count_label;
        private Gtk.Entry author_entry;
        private Gtk.DropDown role_dropdown;
        private Gtk.ToggleButton filter_open_btn;
        private Gtk.ToggleButton filter_resolved_btn;
        private Gtk.ToggleButton filter_all_btn;
        private Gtk.Button flip_btn;
        private string filter_mode = "open";

        public signal void flip_side_requested ();
        public signal void close_requested ();
        public signal void add_comment_requested ();

        public ReviewCommentsPanel (ReviewCommentService service, Window? parent_window = null) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.service = service;
            this.parent_window = parent_window;
            this.width_request = 300;
            this.vexpand = true;
            this.add_css_class ("review-comments-sidebar");

            build_ui ();

            service.threads_changed.connect (rebuild_threads_ui);
            service.active_thread_changed.connect ((tid) => {
                rebuild_threads_ui ();
            });
            rebuild_threads_ui ();
        }

        private void build_ui () {
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 8,
                margin_start = 10,
                margin_end = 10
            };

            var title_lbl = new Gtk.Label ("Review Notes") {
                css_classes = { "heading" },
                xalign = 0,
                hexpand = true
            };
            count_label = new Gtk.Label ("0") {
                css_classes = { "caption", "dim-label" }
            };

            flip_btn = new Gtk.Button.from_icon_name ("object-flip-horizontal-symbolic") {
                tooltip_text = "Switch Sidebar Side (Left / Right)"
            };
            flip_btn.add_css_class ("flat");
            flip_btn.clicked.connect (() => flip_side_requested ());

            var close_btn = new Gtk.Button.from_icon_name ("window-close-symbolic") {
                tooltip_text = "Hide Review Notes Sidebar"
            };
            close_btn.add_css_class ("flat");
            close_btn.clicked.connect (() => close_requested ());

            header.append (title_lbl);
            header.append (count_label);
            header.append (flip_btn);
            header.append (close_btn);
            this.append (header);

            // Action & Filter Toolbar
            var actions_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_start = 10,
                margin_end = 10
            };

            var add_btn = new Gtk.Button.with_label ("+ Comment") {
                tooltip_text = "Add Review Comment to Selection (Ctrl+Alt+M)"
            };
            add_btn.add_css_class ("suggested-action");
            add_btn.add_css_class ("pill");
            add_btn.clicked.connect (() => add_comment_requested ());

            var io_menu = new GLib.Menu ();
            io_menu.append ("Import & Merge (.comments.json)...", "review.import");
            io_menu.append ("Export Review Summary (.md)...", "review.export_md");

            var ag = new GLib.SimpleActionGroup ();
            var act_imp = new GLib.SimpleAction ("import", null);
            act_imp.activate.connect (prompt_import_comments);
            ag.add_action (act_imp);
            var act_exp = new GLib.SimpleAction ("export_md", null);
            act_exp.activate.connect (prompt_export_markdown);
            ag.add_action (act_exp);
            this.insert_action_group ("review", ag);

            var io_btn = new Gtk.MenuButton () {
                icon_name = "document-send-symbolic",
                tooltip_text = "Import or Export Review Notes",
                menu_model = io_menu
            };
            io_btn.add_css_class ("flat");

            actions_row.append (add_btn);
            actions_row.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });
            actions_row.append (io_btn);
            this.append (actions_row);

            // Filter Pills
            var filter_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                margin_start = 10,
                margin_end = 10,
                homogeneous = true
            };
            filter_box.add_css_class ("linked");
            filter_open_btn = new Gtk.ToggleButton.with_label ("Open") { active = true };
            filter_resolved_btn = new Gtk.ToggleButton.with_label ("Resolved") { group = filter_open_btn };
            filter_all_btn = new Gtk.ToggleButton.with_label ("All") { group = filter_open_btn };

            filter_open_btn.toggled.connect (() => { if (filter_open_btn.active) { filter_mode = "open"; rebuild_threads_ui (); } });
            filter_resolved_btn.toggled.connect (() => { if (filter_resolved_btn.active) { filter_mode = "resolved"; rebuild_threads_ui (); } });
            filter_all_btn.toggled.connect (() => { if (filter_all_btn.active) { filter_mode = "all"; rebuild_threads_ui (); } });

            filter_box.append (filter_open_btn);
            filter_box.append (filter_resolved_btn);
            filter_box.append (filter_all_btn);
            this.append (filter_box);

            // Reviewer Identity Bar
            var id_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_start = 10,
                margin_end = 10
            };
            string default_name = GLib.Environment.get_real_name ();
            if (default_name == "" || default_name == "Unknown") default_name = GLib.Environment.get_user_name ();
            author_entry = new Gtk.Entry () {
                text = default_name,
                placeholder_text = "Reviewer name...",
                hexpand = true
            };
            role_dropdown = new Gtk.DropDown (new Gtk.StringList ({ "Professor", "Reviewer", "Co-author", "Student" }), null) {
                selected = 0
            };
            id_box.append (author_entry);
            id_box.append (role_dropdown);
            this.append (id_box);

            this.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var scroller = new Gtk.ScrolledWindow () {
                vexpand = true,
                hexpand = true,
                hscrollbar_policy = Gtk.PolicyType.NEVER
            };
            threads_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 8,
                margin_bottom = 12,
                margin_start = 10,
                margin_end = 10
            };
            scroller.set_child (threads_box);
            this.append (scroller);
        }

        public string get_current_author () {
            string a = author_entry.text.strip ();
            return a.length > 0 ? a : "Reviewer";
        }

        public string get_current_role () {
            var item = role_dropdown.selected_item as Gtk.StringObject;
            return item != null ? item.string : "Reviewer";
        }

        public void rebuild_threads_ui () {
            Gtk.Widget? child = threads_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                threads_box.remove (child);
                child = next;
            }

            service.sync_marks_to_store ();
            int open_cnt = 0;
            int shown_cnt = 0;

            foreach (var t in service.store.threads) {
                if (!t.is_resolved ()) open_cnt++;
                if (filter_mode == "open" && t.is_resolved ()) continue;
                if (filter_mode == "resolved" && !t.is_resolved ()) continue;
                shown_cnt++;
                threads_box.append (build_thread_card (t));
            }
            count_label.label = @"$(open_cnt) open";

            if (shown_cnt == 0) {
                var empty_lbl = new Gtk.Label (
                    "No review comments in this view.\nSelect lines in the editor and press Ctrl+Alt+M or click + Comment."
                ) {
                    wrap = true,
                    justify = Gtk.Justification.CENTER,
                    margin_top = 24
                };
                empty_lbl.add_css_class ("dim-label");
                empty_lbl.add_css_class ("caption");
                threads_box.append (empty_lbl);
            }
        }

        private Gtk.Widget build_thread_card (ReviewThread t) {
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 2,
                margin_bottom = 2
            };
            card.add_css_class ("card");
            if (t.thread_id == service.active_thread_id) {
                card.add_css_class ("accent");
            }

            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 10,
                margin_end = 10
            };

            // Card Top Row: Line badge + Category + Resolve + Delete
            var top_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            string range_text = t.detached ? "Detached" : t.anchor.format_range_badge ();
            var range_btn = new Gtk.Button.with_label (range_text) {
                tooltip_text = "Jump to anchored lines"
            };
            range_btn.add_css_class ("flat");
            range_btn.add_css_class ("caption");
            range_btn.clicked.connect (() => service.focus_thread (t.thread_id));

            var cat_lbl = new Gtk.Label (t.category) {
                css_classes = { "caption", "dim-label" },
                xalign = 0,
                hexpand = true
            };

            var res_btn = new Gtk.Button.from_icon_name (t.is_resolved () ? "view-refresh-symbolic" : "object-select-symbolic") {
                tooltip_text = t.is_resolved () ? "Reopen Thread" : "Resolve Thread"
            };
            res_btn.add_css_class ("flat");
            res_btn.clicked.connect (() => service.set_thread_resolved (t.thread_id, !t.is_resolved ()));

            var del_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                tooltip_text = "Delete Thread"
            };
            del_btn.add_css_class ("flat");
            del_btn.clicked.connect (() => service.delete_thread (t.thread_id));

            top_row.append (range_btn);
            top_row.append (cat_lbl);
            top_row.append (res_btn);
            top_row.append (del_btn);
            inner.append (top_row);

            if (t.anchor.quoted_text.strip ().length > 0) {
                string snip = t.anchor.quoted_text.strip ().replace ("\n", " ");
                if (snip.length > 90) snip = snip.substring (0, 90) + "...";
                var quote_lbl = new Gtk.Label (snip) {
                    xalign = 0,
                    wrap = true,
                    css_classes = { "caption", "monospace", "dim-label" }
                };
                inner.append (quote_lbl);
            }

            // Chat-style messages
            foreach (var m in t.messages) {
                var msg_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
                    margin_top = 4
                };
                var meta_lbl = new Gtk.Label (@"$(m.author) · $(m.role) · $(m.timestamp)") {
                    xalign = 0,
                    css_classes = { "caption", "dim-label" }
                };
                var body_lbl = new Gtk.Label (m.body) {
                    xalign = 0,
                    wrap = true,
                    selectable = true
                };
                msg_box.append (meta_lbl);
                msg_box.append (body_lbl);
                inner.append (msg_box);
            }

            // Inline Reply Bar
            var reply_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4
            };
            var reply_entry = new Gtk.Entry () {
                placeholder_text = "Reply...",
                hexpand = true
            };
            var send_btn = new Gtk.Button.from_icon_name ("mail-send-symbolic") {
                tooltip_text = "Send Reply"
            };
            send_btn.add_css_class ("flat");
            reply_entry.activate.connect (() => {
                if (reply_entry.text.strip ().length > 0) {
                    service.add_reply (t.thread_id, get_current_author (), get_current_role (), reply_entry.text);
                    reply_entry.text = "";
                }
            });
            send_btn.clicked.connect (() => {
                if (reply_entry.text.strip ().length > 0) {
                    service.add_reply (t.thread_id, get_current_author (), get_current_role (), reply_entry.text);
                    reply_entry.text = "";
                }
            });
            reply_row.append (reply_entry);
            reply_row.append (send_btn);
            inner.append (reply_row);

            card.append (inner);
            return card;
        }

        private void prompt_import_comments () {
            var dlg = new Gtk.FileDialog () { title = "Import & Merge Review Comments" };
            var filter = new Gtk.FileFilter ();
            filter.set_filter_name ("Review Comments (*.comments.json)");
            filter.add_pattern ("*.json");
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);
            dlg.filters = filters;

            dlg.open.begin (parent_window, null, (o, r) => {
                try {
                    var f = dlg.open.end (r);
                    if (f != null && f.get_path () != null) {
                        int merged = service.merge_sidecar_file (f.get_path ());
                        if (parent_window != null) {
                            parent_window.show_toast (@"Merged $(merged) review item(s)");
                        }
                    }
                } catch (GLib.Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED) && parent_window != null) {
                        parent_window.show_toast (@"Failed to import comments: $(e.message)");
                    }
                }
            });
        }

        private void prompt_export_markdown () {
            var dlg = new Gtk.FileDialog () {
                title = "Export Review Summary (.md)",
                initial_name = "review-summary.md"
            };
            dlg.save.begin (parent_window, null, (o, r) => {
                try {
                    var f = dlg.save.end (r);
                    if (f != null && f.get_path () != null) {
                        service.sync_marks_to_store ();
                        string md = service.store.export_rebuttal_markdown (GLib.Path.get_basename (f.get_path ()));
                        GLib.FileUtils.set_contents (f.get_path (), md);
                        if (parent_window != null) {
                            parent_window.show_toast ("Exported review summary Markdown");
                        }
                    }
                } catch (GLib.Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED) && parent_window != null) {
                        parent_window.show_toast (@"Failed to export summary: $(e.message)");
                    }
                }
            });
        }
    }
}
