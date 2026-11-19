// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Services {

    public class RecoveryRecord : GLib.Object {
        public string doc_id { get; set; default = ""; }
        public string? file_path { get; set; default = null; }
        public string doc_type { get; set; default = "markdown"; }
        public string content { get; set; default = ""; }
        public int cursor_line { get; set; default = 0; }
        public int cursor_offset { get; set; default = 0; }
        public int64 timestamp { get; set; default = 0; }
        public bool is_dirty { get; set; default = false; }
    }

    public class RecoveryService : GLib.Object {
        private static RecoveryService? instance = null;

        public static RecoveryService get_default () {
            if (instance == null) {
                instance = new RecoveryService ();
            }
            return instance;
        }

        private string cache_dir;
        private GLib.Mutex snapshot_mutex = GLib.Mutex ();
        private Gee.HashMap<string, uint64?> doc_generations = new Gee.HashMap<string, uint64?> ();

        public RecoveryService () {
            Object ();
            cache_dir = GLib.Path.build_filename (GLib.Environment.get_user_cache_dir (), "imladris", "recovery");
            ensure_directory ();
        }

        private void ensure_directory () {
            GLib.DirUtils.create_with_parents (cache_dir, 0700);
        }

        private static string sanitize_doc_id (string doc_id) {
            return GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA256, doc_id, -1);
        }

        private string shadow_path_for_id (string doc_id) {
            return GLib.Path.build_filename (cache_dir, @"$(sanitize_doc_id (doc_id)).shadow");
        }

        private void purge_document_cache_locked (string doc_id) {
            try {
                string hashed = shadow_path_for_id (doc_id);
                var f = GLib.File.new_for_path (hashed);
                if (f.query_exists ()) f.delete ();
                // Also clean any legacy unsanitized path if safe basename
                if (!doc_id.contains ("/") && !doc_id.contains ("..")) {
                    string legacy = GLib.Path.build_filename (cache_dir, @"$(doc_id).shadow");
                    var lf = GLib.File.new_for_path (legacy);
                    if (lf.query_exists ()) lf.delete ();
                }
            } catch (GLib.Error e) {}
        }

        public async void snapshot_async (string doc_id, string? file_path, string doc_type, string content, int line, int offset, bool is_dirty) {
            SourceFunc callback = snapshot_async.callback;

            snapshot_mutex.lock ();
            uint64 gen = (doc_generations.has_key (doc_id) ? doc_generations.get (doc_id) : 0) + 1;
            doc_generations.set (doc_id, gen);
            snapshot_mutex.unlock ();

            new Thread<void*> ("imladris-recovery-worker", () => {
                snapshot_mutex.lock ();
                try {
                    uint64 latest = doc_generations.has_key (doc_id) ? doc_generations.get (doc_id) : 0;
                    if (latest != gen) {
                        // Stale snapshot superseded by newer snapshot or purge
                    } else if (!is_dirty) {
                        purge_document_cache_locked (doc_id);
                    } else {
                        ensure_directory ();
                        string doc_cache_file = shadow_path_for_id (doc_id);
                        string doc_temp_file = @"$(doc_cache_file).$(GLib.get_monotonic_time ()).tmp";

                        var builder = new Json.Builder ();
                        builder.begin_object ();
                        builder.set_member_name ("doc_id");
                        builder.add_string_value (doc_id);
                        builder.set_member_name ("file_path");
                        builder.add_string_value (file_path ?? "");
                        builder.set_member_name ("doc_type");
                        builder.add_string_value (doc_type);
                        builder.set_member_name ("cursor_line");
                        builder.add_int_value (line);
                        builder.set_member_name ("cursor_offset");
                        builder.add_int_value (offset);
                        builder.set_member_name ("timestamp");
                        builder.add_int_value (GLib.get_real_time () / 1000);
                        builder.set_member_name ("content");
                        builder.add_string_value (content);
                        builder.end_object ();

                        var json_gen = new Json.Generator ();
                        json_gen.set_root (builder.get_root ());
                        json_gen.to_file (doc_temp_file);

                        // Restrict permissions before and after atomic rename
                        GLib.FileUtils.chmod (doc_temp_file, 0600);
                        var tmp = GLib.File.new_for_path (doc_temp_file);
                        var dest = GLib.File.new_for_path (doc_cache_file);
                        tmp.move (dest, GLib.FileCopyFlags.OVERWRITE, null, null);
                        GLib.FileUtils.chmod (doc_cache_file, 0600);
                    }
                } catch (GLib.Error e) {
                    GLib.warning ("Recovery snapshot error: %s", e.message);
                } finally {
                    snapshot_mutex.unlock ();
                }

                Idle.add ((owned) callback);
                return null;
            });

            yield;
        }

        public void purge_document_cache (string doc_id) {
            snapshot_mutex.lock ();
            try {
                uint64 gen = (doc_generations.has_key (doc_id) ? doc_generations.get (doc_id) : 0) + 1;
                doc_generations.set (doc_id, gen);
                purge_document_cache_locked (doc_id);
            } finally {
                snapshot_mutex.unlock ();
            }
        }

        public Gee.ArrayList<RecoveryRecord> check_recoverable_sessions () {
            var records = new Gee.ArrayList<RecoveryRecord> ();
            try {
                var dir = GLib.File.new_for_path (cache_dir);
                if (!dir.query_exists ()) return records;

                var enumerator = dir.enumerate_children (GLib.FileAttribute.STANDARD_NAME, GLib.FileQueryInfoFlags.NONE);
                try {
                    GLib.FileInfo info;
                    while ((info = enumerator.next_file ()) != null) {
                        string name = info.get_name ();
                        if (name.has_suffix (".shadow")) {
                            string path = GLib.Path.build_filename (cache_dir, name);
                            var rec = parse_shadow_file (path);
                            if (rec != null) {
                                records.add (rec);
                            }
                        }
                    }
                } finally {
                    try {
                        enumerator.close ();
                    } catch (GLib.Error e) {}
                }
            } catch (GLib.Error e) {
                GLib.warning ("Error checking recovery cache: %s", e.message);
            }
            return records;
        }

        private RecoveryRecord? parse_shadow_file (string path) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;
                var obj = root.get_object ();

                var rec = new RecoveryRecord ();
                rec.doc_id = obj.has_member ("doc_id") ? obj.get_string_member ("doc_id") : "";
                string fp = obj.has_member ("file_path") ? obj.get_string_member ("file_path") : "";
                rec.file_path = (fp != "") ? fp : null;
                rec.doc_type = obj.has_member ("doc_type") ? obj.get_string_member ("doc_type") : "markdown";
                rec.content = obj.has_member ("content") ? obj.get_string_member ("content") : "";
                rec.cursor_line = obj.has_member ("cursor_line") ? (int) obj.get_int_member ("cursor_line") : 0;
                rec.cursor_offset = obj.has_member ("cursor_offset") ? (int) obj.get_int_member ("cursor_offset") : 0;
                rec.timestamp = obj.has_member ("timestamp") ? obj.get_int_member ("timestamp") : 0;
                rec.is_dirty = true;
                return rec;
            } catch (GLib.Error e) {
                return null;
            }
        }
    }
}
