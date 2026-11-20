// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris.Services {

    public enum LayoutMode {
        APOSTROPHE,
        RSTUDIO;

        public static LayoutMode from_extension (string filename) {
            var profile = Core.FormatProfile.for_filename (filename);
            return profile.default_rstudio_layout ? RSTUDIO : APOSTROPHE;
        }

        public string to_label () {
            switch (this) {
                case RSTUDIO:
                    return "RStudio Workbench (4-Quadrant)";
                case APOSTROPHE:
                default:
                    return "Apostrophe Mode (Focused Writer)";
            }
        }
    }

    public enum SplitMode {
        EDITOR_ONLY,
        PREVIEW_ONLY,
        VERTICAL_SPLIT,
        HORIZONTAL_SPLIT;

        public string to_label () {
            switch (this) {
                case EDITOR_ONLY:
                    return "Editor Only";
                case PREVIEW_ONLY:
                    return "Preview Only";
                case HORIZONTAL_SPLIT:
                    return "Horizontal Split (Top/Bottom)";
                case VERTICAL_SPLIT:
                default:
                    return "Vertical Split (Side-by-Side)";
            }
        }
    }

    public class WorkspaceStateManager : GLib.Object {
        private static WorkspaceStateManager? instance = null;

        public static WorkspaceStateManager get_default () {
            if (instance == null) {
                instance = new WorkspaceStateManager ();
            }
            return instance;
        }

        public LayoutMode active_layout { get; set; default = LayoutMode.APOSTROPHE; }
        public SplitMode active_split { get; set; default = SplitMode.VERTICAL_SPLIT; }
        public bool user_override_lock { get; set; default = false; }

        private GLib.HashTable<string, int> doc_layouts = new GLib.HashTable<string, int> (GLib.str_hash, GLib.str_equal);
        private GLib.HashTable<string, int> doc_splits = new GLib.HashTable<string, int> (GLib.str_hash, GLib.str_equal);
        private GLib.HashTable<string, bool> doc_overrides = new GLib.HashTable<string, bool> (GLib.str_hash, GLib.str_equal);

        public signal void layout_changed (LayoutMode new_layout);
        public signal void split_changed (SplitMode new_split);

        public LayoutMode get_layout_for_doc (string doc_id, string filename) {
            if (doc_layouts.contains (doc_id)) {
                return (LayoutMode) doc_layouts.lookup (doc_id);
            }
            return LayoutMode.from_extension (filename);
        }

        public void set_layout_for_doc (string doc_id, LayoutMode mode, bool user_manual_override = false) {
            doc_layouts.insert (doc_id, (int) mode);
            if (user_manual_override) {
                doc_overrides.insert (doc_id, true);
            }
            if (active_layout != mode) {
                active_layout = mode;
                layout_changed (mode);
            }
        }

        public SplitMode get_split_for_doc (string doc_id) {
            if (doc_splits.contains (doc_id)) {
                return (SplitMode) doc_splits.lookup (doc_id);
            }
            return active_split;
        }

        public void set_split_for_doc (string doc_id, SplitMode mode) {
            doc_splits.insert (doc_id, (int) mode);
            set_split_mode (mode);
        }

        public void clear_doc_state (string doc_id) {
            doc_layouts.remove (doc_id);
            doc_splits.remove (doc_id);
            doc_overrides.remove (doc_id);
        }

        public void set_layout_mode (LayoutMode mode, bool user_manual_override = false) {
            if (user_manual_override) {
                user_override_lock = true;
            }
            if (active_layout != mode) {
                active_layout = mode;
                layout_changed (mode);
            }
        }

        public void set_split_mode (SplitMode mode) {
            if (active_split != mode) {
                active_split = mode;
                split_changed (mode);
            }
        }

        public void resolve_mode_for_file (string filename) {
            if (user_override_lock) {
                return; // Respect user manual choice during session
            }
            var target_mode = LayoutMode.from_extension (filename);
            set_layout_mode (target_mode, false);
        }
    }
}
