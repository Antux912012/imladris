// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Gee;
using Imladris.Core;

namespace Imladris.Services {

    public class ReviewCommentService : GLib.Object {
        public ReviewCommentStore store { get; private set; }
        public string? sidecar_path { get; private set; default = null; }
        public string? active_thread_id { get; private set; default = null; }

        private unowned GtkSource.Buffer buffer;
        private unowned GtkSource.View view;
        private Gtk.TextTag range_tag;
        private Gtk.TextTag active_tag;
        private Gee.HashMap<string, Gtk.TextMark> start_marks;
        private Gee.HashMap<string, Gtk.TextMark> end_marks;
        private Gee.ArrayList<GtkSource.Mark> gutter_marks;

        public signal void threads_changed ();
        public signal void active_thread_changed (string? thread_id);

        public ReviewCommentService (GtkSource.View view, GtkSource.Buffer buffer) {
            this.view = view;
            this.buffer = buffer;
            this.store = new ReviewCommentStore ();
            this.start_marks = new Gee.HashMap<string, Gtk.TextMark> ();
            this.end_marks = new Gee.HashMap<string, Gtk.TextMark> ();
            this.gutter_marks = new Gee.ArrayList<GtkSource.Mark> ();

            setup_tags_and_gutter ();
        }

        private void setup_tags_and_gutter () {
            var rgba_open = Gdk.RGBA ();
            rgba_open.parse ("rgba(245, 194, 17, 0.22)");
            range_tag = buffer.create_tag ("review-comment-range", "background-rgba", rgba_open);

            var rgba_active = Gdk.RGBA ();
            rgba_active.parse ("rgba(53, 132, 228, 0.30)");
            active_tag = buffer.create_tag ("review-comment-active", "background-rgba", rgba_active);

            var attrs = new GtkSource.MarkAttributes ();
            attrs.set_icon_name ("mail-unread-symbolic");
            view.set_mark_attributes ("review-comment", attrs, 10);
            view.show_line_marks = true;
        }

        public void load_for_document (string? doc_path, string? project_root, string current_text) {
            clear_marks ();
            store = new ReviewCommentStore ();
            if (doc_path == null || doc_path.strip ().length == 0) {
                sidecar_path = null;
                threads_changed ();
                return;
            }

            sidecar_path = ReviewCommentStore.resolve_sidecar_path (doc_path, project_root);
            if (GLib.FileUtils.test (sidecar_path, GLib.FileTest.EXISTS)) {
                try {
                    string json_str;
                    GLib.FileUtils.get_contents (sidecar_path, out json_str);
                    store = ReviewCommentStore.deserialize_json (json_str);
                    store.reanchor_against_text (current_text);
                } catch (GLib.Error e) {
                    GLib.warning ("Failed to load review comments from %s: %s", sidecar_path, e.message);
                }
            }

            rebuild_buffer_marks ();
            refresh_highlights ();
            threads_changed ();
        }

        public void save_to_disk () {
            if (sidecar_path == null || sidecar_path.length == 0) return;
            sync_marks_to_store ();
            if (store.threads.size == 0) {
                if (GLib.FileUtils.test (sidecar_path, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (sidecar_path);
                }
                return;
            }
            try {
                string parent = GLib.Path.get_dirname (sidecar_path);
                GLib.DirUtils.create_with_parents (parent, 0755);
                GLib.FileUtils.set_contents (sidecar_path, store.serialize_json ());
            } catch (GLib.Error e) {
                GLib.warning ("Failed to save review comments to %s: %s", sidecar_path, e.message);
            }
        }

        public ReviewThread create_thread_from_selection (string author, string role, string category, string body) {
            Gtk.TextIter start_it, end_it;
            if (!buffer.get_selection_bounds (out start_it, out end_it)) {
                buffer.get_iter_at_mark (out start_it, buffer.get_insert ());
                start_it.set_line_offset (0);
                end_it = start_it;
                end_it.forward_to_line_end ();
            }
            if (start_it.compare (end_it) > 0) {
                Gtk.TextIter tmp = start_it;
                start_it = end_it;
                end_it = tmp;
            }

            string quoted = buffer.get_text (start_it, end_it, false);
            int s_line = start_it.get_line () + 1;
            int e_line = end_it.get_line () + 1;

            string ctx_before = "";
            if (start_it.get_line () > 0) {
                Gtk.TextIter b1, b2;
                buffer.get_iter_at_line (out b1, start_it.get_line () - 1);
                b2 = b1;
                b2.forward_to_line_end ();
                ctx_before = buffer.get_text (b1, b2, false);
            }
            string ctx_after = "";
            if (end_it.get_line () + 1 < buffer.get_line_count ()) {
                Gtk.TextIter a1, a2;
                buffer.get_iter_at_line (out a1, end_it.get_line () + 1);
                a2 = a1;
                a2.forward_to_line_end ();
                ctx_after = buffer.get_text (a1, a2, false);
            }

            var anchor = new ReviewAnchor (
                s_line, e_line,
                start_it.get_line_offset (), end_it.get_line_offset (),
                quoted, ctx_before, ctx_after
            );
            var thread = new ReviewThread (anchor, category);
            thread.messages.add (new ReviewMessage (author, role, body));
            store.threads.add (thread);

            attach_marks_for_thread (thread, start_it, end_it);
            active_thread_id = thread.thread_id;
            refresh_highlights ();
            save_to_disk ();
            threads_changed ();
            active_thread_changed (active_thread_id);
            return thread;
        }

        public void add_reply (string thread_id, string author, string role, string body) {
            var t = store.find_thread (thread_id);
            if (t == null || body.strip ().length == 0) return;
            t.messages.add (new ReviewMessage (author, role, body.strip ()));
            save_to_disk ();
            threads_changed ();
        }

        public void set_thread_resolved (string thread_id, bool resolved) {
            var t = store.find_thread (thread_id);
            if (t == null) return;
            t.status = resolved ? "resolved" : "open";
            refresh_highlights ();
            save_to_disk ();
            threads_changed ();
        }

        public void delete_thread (string thread_id) {
            var t = store.find_thread (thread_id);
            if (t == null) return;
            var sm = start_marks.get (thread_id);
            var em = end_marks.get (thread_id);
            if (sm != null && !sm.get_deleted ()) buffer.delete_mark (sm);
            if (em != null && !em.get_deleted ()) buffer.delete_mark (em);
            start_marks.unset (thread_id);
            end_marks.unset (thread_id);
            store.threads.remove (t);
            if (active_thread_id == thread_id) active_thread_id = null;
            refresh_highlights ();
            save_to_disk ();
            threads_changed ();
        }

        public void focus_thread (string thread_id) {
            active_thread_id = thread_id;
            refresh_highlights ();
            var sm = start_marks.get (thread_id);
            if (sm != null && !sm.get_deleted ()) {
                Gtk.TextIter it;
                buffer.get_iter_at_mark (out it, sm);
                view.scroll_to_iter (it, 0.25, true, 0.0, 0.2);
                buffer.place_cursor (it);
            }
            active_thread_changed (active_thread_id);
        }

        public void sync_cursor_to_thread () {
            Gtk.TextIter cur;
            buffer.get_iter_at_mark (out cur, buffer.get_insert ());
            int cur_line = cur.get_line () + 1;
            sync_marks_to_store ();
            string? hit = null;
            foreach (var t in store.threads) {
                if (!t.detached && cur_line >= t.anchor.start_line && cur_line <= t.anchor.end_line) {
                    hit = t.thread_id;
                    break;
                }
            }
            if (hit != active_thread_id) {
                active_thread_id = hit;
                refresh_highlights ();
                active_thread_changed (active_thread_id);
            }
        }

        public int merge_sidecar_file (string path) throws GLib.Error {
            string json_str;
            GLib.FileUtils.get_contents (path, out json_str);
            var incoming = ReviewCommentStore.deserialize_json (json_str);
            int count = store.merge_from (incoming);
            Gtk.TextIter s, e;
            buffer.get_bounds (out s, out e);
            store.reanchor_against_text (buffer.get_text (s, e, false));
            rebuild_buffer_marks ();
            refresh_highlights ();
            save_to_disk ();
            threads_changed ();
            return count;
        }

        public void sync_marks_to_store () {
            foreach (var t in store.threads) {
                if (t.detached) continue;
                var sm = start_marks.get (t.thread_id);
                var em = end_marks.get (t.thread_id);
                if (sm != null && em != null && !sm.get_deleted () && !em.get_deleted ()) {
                    Gtk.TextIter si, ei;
                    buffer.get_iter_at_mark (out si, sm);
                    buffer.get_iter_at_mark (out ei, em);
                    t.anchor.start_line = si.get_line () + 1;
                    t.anchor.end_line = int.max (t.anchor.start_line, ei.get_line () + 1);
                    t.anchor.start_col = si.get_line_offset ();
                    t.anchor.end_col = ei.get_line_offset ();
                }
            }
        }

        private void rebuild_buffer_marks () {
            clear_marks ();
            int max_line = int.max (0, buffer.get_line_count () - 1);
            foreach (var t in store.threads) {
                if (t.detached) continue;
                Gtk.TextIter si, ei;
                int sl = (t.anchor.start_line - 1).clamp (0, max_line);
                int el = (t.anchor.end_line - 1).clamp (sl, max_line);
                buffer.get_iter_at_line_offset (out si, sl, 0);
                int s_len = si.get_chars_in_line ();
                if (t.anchor.start_col > 0 && t.anchor.start_col < s_len) si.set_line_offset (t.anchor.start_col);
                buffer.get_iter_at_line_offset (out ei, el, 0);
                int e_len = ei.get_chars_in_line ();
                if (t.anchor.end_col > 0 && t.anchor.end_col < e_len) {
                    ei.set_line_offset (t.anchor.end_col);
                } else {
                    ei.forward_to_line_end ();
                }
                attach_marks_for_thread (t, si, ei);
            }
        }

        private void attach_marks_for_thread (ReviewThread t, Gtk.TextIter si, Gtk.TextIter ei) {
            var sm = buffer.create_mark (null, si, true);
            var em = buffer.create_mark (null, ei, false);
            start_marks.set (t.thread_id, sm);
            end_marks.set (t.thread_id, em);
            var gm = buffer.create_source_mark (null, "review-comment", si);
            gutter_marks.add (gm);
        }

        public void refresh_highlights () {
            Gtk.TextIter bs, be;
            buffer.get_bounds (out bs, out be);
            buffer.remove_tag (range_tag, bs, be);
            buffer.remove_tag (active_tag, bs, be);

            foreach (var t in store.threads) {
                if (t.detached || t.is_resolved ()) continue;
                var sm = start_marks.get (t.thread_id);
                var em = end_marks.get (t.thread_id);
                if (sm != null && em != null && !sm.get_deleted () && !em.get_deleted ()) {
                    Gtk.TextIter si, ei;
                    buffer.get_iter_at_mark (out si, sm);
                    buffer.get_iter_at_mark (out ei, em);
                    if (si.compare (ei) == 0) ei.forward_to_line_end ();
                    buffer.apply_tag (
                        (t.thread_id == active_thread_id) ? active_tag : range_tag,
                        si, ei
                    );
                }
            }
        }

        private void clear_marks () {
            foreach (var sm in start_marks.values) {
                if (!sm.get_deleted ()) buffer.delete_mark (sm);
            }
            foreach (var em in end_marks.values) {
                if (!em.get_deleted ()) buffer.delete_mark (em);
            }
            start_marks.clear ();
            end_marks.clear ();
            foreach (var gm in gutter_marks) {
                if (!gm.get_deleted ()) buffer.delete_mark (gm);
            }
            gutter_marks.clear ();
        }
    }
}
