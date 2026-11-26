// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gee;

namespace Imladris.Core {

    public class ReviewAnchor : GLib.Object {
        public int start_line { get; set; default = 1; }
        public int end_line { get; set; default = 1; }
        public int start_col { get; set; default = 0; }
        public int end_col { get; set; default = 0; }
        public string quoted_text { get; set; default = ""; }
        public string context_before { get; set; default = ""; }
        public string context_after { get; set; default = ""; }

        public ReviewAnchor (
            int start_line = 1,
            int end_line = 1,
            int start_col = 0,
            int end_col = 0,
            string quoted_text = "",
            string context_before = "",
            string context_after = ""
        ) {
            this.start_line = int.max (1, start_line);
            this.end_line = int.max (this.start_line, end_line);
            this.start_col = int.max (0, start_col);
            this.end_col = int.max (0, end_col);
            this.quoted_text = quoted_text;
            this.context_before = context_before;
            this.context_after = context_after;
        }

        public string format_range_badge () {
            if (start_line == end_line) {
                return @"L$(start_line)";
            }
            return @"L$(start_line)–$(end_line)";
        }
    }

    public class ReviewMessage : GLib.Object {
        public string id { get; set; default = ""; }
        public string author { get; set; default = "Reviewer"; }
        public string role { get; set; default = "Reviewer"; }
        public string timestamp { get; set; default = ""; }
        public string body { get; set; default = ""; }

        public ReviewMessage (string author, string role, string body, string? id = null, string? timestamp = null) {
            this.id = (id != null && id.length > 0) ? id : GLib.Uuid.string_random ();
            this.author = (author.strip ().length > 0) ? author.strip () : "Reviewer";
            this.role = (role.strip ().length > 0) ? role.strip () : "Reviewer";
            if (timestamp != null && timestamp.length > 0) {
                this.timestamp = timestamp;
            } else {
                var now = new GLib.DateTime.now_local ();
                this.timestamp = now.format ("%Y-%m-%d %H:%M");
            }
            this.body = body;
        }
    }

    public class ReviewThread : GLib.Object {
        public string thread_id { get; set; default = ""; }
        public string status { get; set; default = "open"; }
        public string category { get; set; default = "General"; }
        public bool detached { get; set; default = false; }
        public ReviewAnchor anchor { get; set; }
        public Gee.ArrayList<ReviewMessage> messages { get; private set; }

        public ReviewThread (ReviewAnchor? anchor = null, string category = "General", string? thread_id = null) {
            this.thread_id = (thread_id != null && thread_id.length > 0) ? thread_id : GLib.Uuid.string_random ();
            this.anchor = anchor ?? new ReviewAnchor ();
            this.category = (category.strip ().length > 0) ? category.strip () : "General";
            this.messages = new Gee.ArrayList<ReviewMessage> ();
        }

        public bool is_resolved () {
            return status.down () == "resolved";
        }
    }

    public class ReviewCommentStore : GLib.Object {
        public Gee.ArrayList<ReviewThread> threads { get; private set; }

        public ReviewCommentStore () {
            threads = new Gee.ArrayList<ReviewThread> ();
        }

        public static string resolve_sidecar_path (string doc_path, string? project_root = null) {
            string clean_doc = doc_path.strip ();
            if (project_root != null && project_root.strip ().length > 0) {
                string clean_proj = project_root.strip ();
                string? rel = null;
                var proj_f = GLib.File.new_for_path (clean_proj);
                var doc_f = GLib.File.new_for_path (clean_doc);
                rel = proj_f.get_relative_path (doc_f);
                if (rel != null && rel.length > 0 && !rel.has_prefix ("..")) {
                    string safe_rel = rel.replace ("/", "__").replace ("\\", "__");
                    return GLib.Path.build_filename (clean_proj, ".imladris", "reviews", @"$(safe_rel).comments.json");
                }
            }
            string dir = GLib.Path.get_dirname (clean_doc);
            string bname = GLib.Path.get_basename (clean_doc);
            return GLib.Path.build_filename (dir, @".$(bname).imladris-comments.json");
        }

        public string serialize_json () {
            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("version");
            builder.add_int_value (1);
            builder.set_member_name ("threads");
            builder.begin_array ();

            foreach (var t in threads) {
                builder.begin_object ();
                builder.set_member_name ("thread_id");
                builder.add_string_value (t.thread_id);
                builder.set_member_name ("status");
                builder.add_string_value (t.status);
                builder.set_member_name ("category");
                builder.add_string_value (t.category);
                builder.set_member_name ("detached");
                builder.add_boolean_value (t.detached);

                builder.set_member_name ("anchor");
                builder.begin_object ();
                builder.set_member_name ("start_line");
                builder.add_int_value (t.anchor.start_line);
                builder.set_member_name ("end_line");
                builder.add_int_value (t.anchor.end_line);
                builder.set_member_name ("start_col");
                builder.add_int_value (t.anchor.start_col);
                builder.set_member_name ("end_col");
                builder.add_int_value (t.anchor.end_col);
                builder.set_member_name ("quoted_text");
                builder.add_string_value (t.anchor.quoted_text);
                builder.set_member_name ("context_before");
                builder.add_string_value (t.anchor.context_before);
                builder.set_member_name ("context_after");
                builder.add_string_value (t.anchor.context_after);
                builder.end_object ();

                builder.set_member_name ("messages");
                builder.begin_array ();
                foreach (var m in t.messages) {
                    builder.begin_object ();
                    builder.set_member_name ("id");
                    builder.add_string_value (m.id);
                    builder.set_member_name ("author");
                    builder.add_string_value (m.author);
                    builder.set_member_name ("role");
                    builder.add_string_value (m.role);
                    builder.set_member_name ("timestamp");
                    builder.add_string_value (m.timestamp);
                    builder.set_member_name ("body");
                    builder.add_string_value (m.body);
                    builder.end_object ();
                }
                builder.end_array ();
                builder.end_object ();
            }

            builder.end_array ();
            builder.end_object ();

            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.set_root (builder.get_root ());
            return gen.to_data (null);
        }

        public static ReviewCommentStore deserialize_json (string json_str) throws GLib.Error {
            var store = new ReviewCommentStore ();
            if (json_str.strip ().length == 0) return store;

            var parser = new Json.Parser ();
            parser.load_from_data (json_str, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                return store;
            }
            var obj = root.get_object ();
            if (!obj.has_member ("threads") || obj.get_member ("threads").get_node_type () != Json.NodeType.ARRAY) {
                return store;
            }

            var t_arr = obj.get_array_member ("threads");
            for (uint i = 0; i < t_arr.get_length (); i++) {
                var t_node = t_arr.get_element (i);
                if (t_node == null || t_node.get_node_type () != Json.NodeType.OBJECT) continue;
                var t_obj = t_node.get_object ();

                string tid = get_str (t_obj, "thread_id") ?? GLib.Uuid.string_random ();
                string cat = get_str (t_obj, "category") ?? "General";
                var anchor = new ReviewAnchor ();
                if (t_obj.has_member ("anchor") && t_obj.get_member ("anchor").get_node_type () == Json.NodeType.OBJECT) {
                    var a_obj = t_obj.get_object_member ("anchor");
                    anchor.start_line = (int) get_int (a_obj, "start_line", 1);
                    anchor.end_line = int.max (anchor.start_line, (int) get_int (a_obj, "end_line", anchor.start_line));
                    anchor.start_col = (int) get_int (a_obj, "start_col", 0);
                    anchor.end_col = (int) get_int (a_obj, "end_col", 0);
                    anchor.quoted_text = get_str (a_obj, "quoted_text") ?? "";
                    anchor.context_before = get_str (a_obj, "context_before") ?? "";
                    anchor.context_after = get_str (a_obj, "context_after") ?? "";
                }

                var thread = new ReviewThread (anchor, cat, tid);
                thread.status = get_str (t_obj, "status") ?? "open";
                if (t_obj.has_member ("detached") && t_obj.get_member ("detached").get_node_type () == Json.NodeType.VALUE) {
                    thread.detached = t_obj.get_boolean_member ("detached");
                }

                if (t_obj.has_member ("messages") && t_obj.get_member ("messages").get_node_type () == Json.NodeType.ARRAY) {
                    var m_arr = t_obj.get_array_member ("messages");
                    for (uint j = 0; j < m_arr.get_length (); j++) {
                        var m_node = m_arr.get_element (j);
                        if (m_node == null || m_node.get_node_type () != Json.NodeType.OBJECT) continue;
                        var m_obj = m_node.get_object ();
                        var msg = new ReviewMessage (
                            get_str (m_obj, "author") ?? "Reviewer",
                            get_str (m_obj, "role") ?? "Reviewer",
                            get_str (m_obj, "body") ?? "",
                            get_str (m_obj, "id"),
                            get_str (m_obj, "timestamp")
                        );
                        thread.messages.add (msg);
                    }
                }
                store.threads.add (thread);
            }
            return store;
        }

        public void reanchor_against_text (string doc_text) {
            string[] lines = doc_text.split ("\n");
            if (lines.length == 0) return;

            foreach (var t in threads) {
                string needle = t.anchor.quoted_text.strip ();
                if (needle.length == 0) {
                    t.anchor.start_line = t.anchor.start_line.clamp (1, lines.length);
                    t.anchor.end_line = t.anchor.end_line.clamp (t.anchor.start_line, lines.length);
                    t.detached = false;
                    continue;
                }

                // 1. Check if current [start_line..end_line] still contains the quoted text
                if (t.anchor.start_line >= 1 && t.anchor.end_line <= lines.length) {
                    string span = join_line_slice (lines, t.anchor.start_line, t.anchor.end_line);
                    if (span.contains (needle)) {
                        t.detached = false;
                        continue;
                    }
                }

                // 2. Fuzzy line search across the document
                string[] needle_lines = t.anchor.quoted_text.split ("\n");
                string first_needle = needle_lines[0].strip ();
                int span_len = int.max (1, needle_lines.length);
                int found_start = -1;

                if (first_needle.length > 0) {
                    int best_score = -1;
                    for (int li = 0; li <= lines.length - span_len; li++) {
                        string candidate = join_line_slice (lines, li + 1, li + span_len);
                        if (candidate.contains (needle)) {
                            int score = 100;
                            if (t.anchor.context_before.strip ().length > 0 && li > 0 &&
                                lines[li - 1].contains (t.anchor.context_before.strip ())) {
                                score += 20;
                            }
                            if (t.anchor.context_after.strip ().length > 0 && li + span_len < lines.length &&
                                lines[li + span_len].contains (t.anchor.context_after.strip ())) {
                                score += 20;
                            }
                            if (score > best_score) {
                                best_score = score;
                                found_start = li + 1;
                            }
                        }
                    }
                }

                if (found_start > 0) {
                    t.anchor.start_line = found_start;
                    t.anchor.end_line = int.min (lines.length, found_start + span_len - 1);
                    t.detached = false;
                } else {
                    t.detached = true;
                }
            }
        }

        public int merge_from (ReviewCommentStore incoming) {
            int merged_count = 0;
            foreach (var inc_t in incoming.threads) {
                ReviewThread? existing = find_thread (inc_t.thread_id);
                if (existing == null) {
                    threads.add (inc_t);
                    merged_count += int.max (1, inc_t.messages.size);
                } else {
                    foreach (var inc_m in inc_t.messages) {
                        bool seen = false;
                        foreach (var ex_m in existing.messages) {
                            if (ex_m.id == inc_m.id) {
                                seen = true;
                                break;
                            }
                        }
                        if (!seen) {
                            existing.messages.add (inc_m);
                            merged_count++;
                        }
                    }
                    if (inc_t.is_resolved ()) {
                        existing.status = "resolved";
                    }
                }
            }
            return merged_count;
        }

        public ReviewThread? find_thread (string thread_id) {
            foreach (var t in threads) {
                if (t.thread_id == thread_id) return t;
            }
            return null;
        }

        public string export_rebuttal_markdown (string doc_title) {
            var sb = new GLib.StringBuilder ();
            sb.append_printf ("# Review Notes & Rebuttal Summary: %s\n\n", doc_title);
            sb.append ("| Lines | Category | Status | Quoted Snippet | Thread Discussion |\n");
            sb.append ("| :--- | :--- | :--- | :--- | :--- |\n");
            foreach (var t in threads) {
                string range = t.detached ? "Detached" : t.anchor.format_range_badge ();
                string snippet = t.anchor.quoted_text.replace ("\n", " ").replace ("|", "\\|").strip ();
                if (snippet.length > 80) snippet = snippet.substring (0, 80) + "...";
                var msg_sb = new GLib.StringBuilder ();
                for (int i = 0; i < t.messages.size; i++) {
                    var m = t.messages.get (i);
                    if (i > 0) msg_sb.append (" <br> ");
                    msg_sb.append_printf ("**%s** (%s): %s",
                        m.author.replace ("|", "\\|"),
                        m.role.replace ("|", "\\|"),
                        m.body.replace ("\n", " ").replace ("|", "\\|")
                    );
                }
                sb.append_printf ("| %s | %s | %s | `%s` | %s |\n",
                    range, t.category, t.status, snippet, msg_sb.str);
            }
            return sb.str;
        }

        private static string join_line_slice (string[] lines, int start_1based, int end_1based) {
            var sb = new GLib.StringBuilder ();
            int s = int.max (0, start_1based - 1);
            int e = int.min (lines.length - 1, end_1based - 1);
            for (int i = s; i <= e; i++) {
                if (i > s) sb.append_c ('\n');
                sb.append (lines[i]);
            }
            return sb.str;
        }

        private static string? get_str (Json.Object obj, string name) {
            if (!obj.has_member (name) || obj.get_null_member (name)) return null;
            var n = obj.get_member (name);
            return (n.get_node_type () == Json.NodeType.VALUE) ? n.get_string () : null;
        }

        private static int64 get_int (Json.Object obj, string name, int64 fallback) {
            if (!obj.has_member (name) || obj.get_null_member (name)) return fallback;
            var n = obj.get_member (name);
            return (n.get_node_type () == Json.NodeType.VALUE) ? n.get_int () : fallback;
        }
    }
}
