using GLib;
using Gee;

namespace Imladris.Services {

    public class HistoryEntry : GLib.Object {
        public string command { get; construct set; }
        public string engine { get; construct set; }
        public GLib.DateTime timestamp { get; construct set; }

        public HistoryEntry (string cmd, string eng) {
            Object (
                command: cmd,
                engine: eng,
                timestamp: new GLib.DateTime.now_local ()
            );
        }
    }

    /**
     * HistoryManager
     * Centralized RStudio-compatible command history tracker.
     * Synchronizes executed console expressions, code chunks, .Rhistory persistence,
     * and Console Up/Down Arrow readline navigation.
     */
    public class HistoryManager : GLib.Object {

        private static HistoryManager? _instance = null;

        public static HistoryManager get_default () {
            if (_instance == null) {
                _instance = new HistoryManager ();
            }
            return _instance;
        }

        private ArrayList<HistoryEntry> entries;
        private int nav_index = -1;
        private string saved_uncommitted_line = "";

        public signal void entry_added (HistoryEntry entry);
        public signal void history_cleared ();

        public HistoryManager () {
            entries = new ArrayList<HistoryEntry> ();
            load_initial_rhistory ();
        }

        public ArrayList<HistoryEntry> get_all_entries () {
            return entries;
        }

        public int size {
            get { return entries.size; }
        }

        public void add_entry (string cmd, string engine = "r") {
            string trimmed = cmd.strip ();
            if (trimmed.length == 0) return;

            // Avoid immediate duplicate of the last entry
            if (entries.size > 0) {
                var last = entries.get (entries.size - 1);
                if (last.command == trimmed && last.engine == engine) {
                    reset_navigation ();
                    return;
                }
            }

            var entry = new HistoryEntry (trimmed, engine);
            entries.add (entry);

            // Cap at 2000 entries
            while (entries.size > 2000) {
                entries.remove_at (0);
            }

            reset_navigation ();
            entry_added (entry);

            // Auto-append to project .Rhistory if in R mode
            if (engine == "r") {
                append_to_rhistory_async.begin (trimmed);
            }
        }

        public void clear () {
            entries.clear ();
            reset_navigation ();
            history_cleared ();
        }

        public void reset_navigation () {
            nav_index = -1;
            saved_uncommitted_line = "";
        }

        /**
         * Console Readline Up Arrow: navigate backwards in history
         */
        public string? navigate_up (string current_input) {
            if (entries.size == 0) return null;

            if (nav_index == -1) {
                saved_uncommitted_line = current_input;
                nav_index = entries.size - 1;
            } else if (nav_index > 0) {
                nav_index--;
            }

            if (nav_index >= 0 && nav_index < entries.size) {
                return entries.get (nav_index).command;
            }
            return null;
        }

        /**
         * Console Readline Down Arrow: navigate forwards in history
         */
        public string? navigate_down () {
            if (nav_index == -1) return null;

            if (nav_index < entries.size - 1) {
                nav_index++;
                return entries.get (nav_index).command;
            } else {
                nav_index = -1;
                return saved_uncommitted_line;
            }
        }

        public bool save_to_file (string filepath) {
            var sb = new StringBuilder ();
            foreach (var e in entries) {
                sb.append (e.command);
                sb.append ("\n");
            }
            try {
                FileUtils.set_contents (filepath, sb.str);
                return true;
            } catch (GLib.Error err) {
                GLib.warning ("Failed to save history to %s: %s", filepath, err.message);
                return false;
            }
        }

        private async void append_to_rhistory_async (string command) {
            string cwd = PersistentSessionManager.get_default ().current_working_dir;
            if (cwd.length == 0 || !FileUtils.test (cwd, FileTest.IS_DIR)) return;

            string rhistory_path = Path.build_filename (cwd, ".Rhistory");
            try {
                var file = File.new_for_path (rhistory_path);
                FileOutputStream? stream = null;
                if (!file.query_exists ()) {
                    stream = yield file.create_async (FileCreateFlags.NONE, Priority.DEFAULT);
                } else {
                    stream = yield file.append_to_async (FileCreateFlags.NONE, Priority.DEFAULT);
                }
                string line = command + "\n";
                yield stream.write_all_async (line.data, Priority.DEFAULT, null, null);
                yield stream.close_async (Priority.DEFAULT);
            } catch (GLib.Error e) {
                // Ignore transient write errors
            }
        }

        private void load_initial_rhistory () {
            string cwd = PersistentSessionManager.get_default ().current_working_dir;
            if (cwd.length == 0) cwd = Environment.get_current_dir ();
            string rhistory_path = Path.build_filename (cwd, ".Rhistory");

            if (FileUtils.test (rhistory_path, FileTest.EXISTS)) {
                try {
                    string contents;
                    FileUtils.get_contents (rhistory_path, out contents);
                    string[] lines = contents.split ("\n");
                    foreach (var l in lines) {
                        string t = l.strip ();
                        if (t.length > 0) {
                            entries.add (new HistoryEntry (t, "r"));
                        }
                    }
                } catch (GLib.Error e) {}
            }
        }
    }
}
