// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: GtkSourceView 5 VS Code-style completion provider and
 * automatic bracket/quote pairing controller.
 *
 * Architectural Position:
 * Bridges CodeIntelliSenseEngine and EnvironmentController to GtkSource.View.
 *
 * Concurrency Constraints:
 * Runs exclusively on the GTK4 MainContext thread.
 */

using GLib;
using Gtk;
using GtkSource;
using Gee;
using Imladris.Core;
using Imladris.UI;

namespace Imladris.Editor {

    public class IntelliSenseProposal : GLib.Object, GtkSource.CompletionProposal {
        public IntelliSenseItem item { get; set; }

        public IntelliSenseProposal (IntelliSenseItem item) {
            this.item = item;
        }
    }

    public class CodeIntelliSenseProvider : GLib.Object, GtkSource.CompletionProvider {

        private weak DocumentPage? doc_page;

        public CodeIntelliSenseProvider (DocumentPage? page = null) {
            this.doc_page = page;
        }

        public string? get_title () {
            return "IntelliSense";
        }

        public int get_priority (GtkSource.CompletionContext context) {
            return 25;
        }

        public bool is_trigger (Gtk.TextIter iter, unichar ch) {
            if (!SettingsManager.get_default ().code_intellisense_enabled) {
                return false;
            }
            return ch.isalnum () || ch == '.' || ch == '$' || ch == ':' || ch == '\\' || ch == '|' || ch == '{' || ch == '_';
        }

        public bool key_activates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal, uint keyval, Gdk.ModifierType state) {
            return keyval == Gdk.Key.Tab || keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter;
        }

        public GenericArray<GtkSource.CompletionProposal>? list_alternates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            return null;
        }

        public void refilter (GtkSource.CompletionContext context, GLib.ListModel model) {
            // Re-populated cleanly via populate_async on keystrokes
        }

        public void display (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal, GtkSource.CompletionCell cell) {
            var p = proposal as IntelliSenseProposal;
            if (p == null) {
                return;
            }

            switch (cell.get_column ()) {
                case GtkSource.CompletionColumn.ICON:
                    cell.set_icon_name (p.item.kind.to_icon_name ());
                    break;
                case GtkSource.CompletionColumn.TYPED_TEXT:
                    cell.set_text (p.item.label);
                    break;
                case GtkSource.CompletionColumn.AFTER:
                    cell.set_text (" " + p.item.signature);
                    break;
                case GtkSource.CompletionColumn.DETAILS:
                    cell.set_text (p.item.detail);
                    break;
                default:
                    break;
            }
        }

        public void activate (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            var p = proposal as IntelliSenseProposal;
            if (p == null) {
                return;
            }

            Gtk.TextIter cursor_iter;
            context.get_bounds (null, out cursor_iter);
            var buffer = context.get_buffer ();

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            buffer.begin_user_action ();

            if (line_prefix.strip ().has_prefix ("#|") && p.item.kind == IntelliSenseSymbolKind.OPTION) {
                int pipe_idx = line_prefix.index_of ("#|");
                Gtk.TextIter replace_start = line_start;
                replace_start.forward_chars (pipe_idx);
                buffer.delete (ref replace_start, ref cursor_iter);
                string replacement = "#| " + p.item.insert_text;
                buffer.insert (ref replace_start, replacement, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            } else if (line_prefix.strip ().has_prefix ("```") && p.item.kind == IntelliSenseSymbolKind.SNIPPET) {
                int fence_idx = line_prefix.index_of ("```");
                Gtk.TextIter replace_start = line_start;
                replace_start.forward_chars (fence_idx);
                buffer.delete (ref replace_start, ref cursor_iter);
                buffer.insert (ref replace_start, p.item.insert_text, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            } else {
                string token = CodeIntelliSenseEngine.extract_active_token (line_prefix);
                Gtk.TextIter replace_start = cursor_iter;
                if (token.length > 0) {
                    replace_start.backward_chars (token.char_count ());
                    buffer.delete (ref replace_start, ref cursor_iter);
                }
                buffer.insert (ref replace_start, p.item.insert_text, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            }

            buffer.end_user_action ();
        }

        public async GLib.ListModel populate_async (GtkSource.CompletionContext context, GLib.Cancellable? cancellable) throws GLib.Error {
            var store = new GLib.ListStore (typeof (IntelliSenseProposal));
            if (!SettingsManager.get_default ().code_intellisense_enabled) {
                return store;
            }

            Gtk.TextIter cursor_iter;
            context.get_bounds (null, out cursor_iter);
            var buffer = context.get_buffer ();

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            Gtk.TextIter doc_start, doc_end;
            buffer.get_bounds (out doc_start, out doc_end);
            string full_text = buffer.get_text (doc_start, doc_end, false);

            string doc_type = doc_page != null ? doc_page.doc_type : "markdown";
            int cursor_line = cursor_iter.get_line ();

            var items = CodeIntelliSenseEngine.query_completions (
                full_text,
                cursor_line,
                line_prefix,
                doc_type
            );

            // Merge live REPL session variables from EnvironmentController when in R or Python context
            var ctx = CodeIntelliSenseEngine.detect_context (full_text, cursor_line, line_prefix, doc_type);
            if ((ctx == IntelliSenseContext.R_CODE || ctx == IntelliSenseContext.PYTHON_CODE) && doc_page != null && doc_page.panel_registry != null) {
                string token = CodeIntelliSenseEngine.extract_active_token (line_prefix);
                if (token.length > 0 && !token.contains ("$") && !token.contains ("::")) {
                    var env_vars = doc_page.panel_registry.environment_controller.get_cached_variables ();
                    foreach (var ev in env_vars) {
                        int sc = CodeIntelliSenseEngine.compute_match_score (ev.name, token);
                        if (sc > 0) {
                            var kind = ev.is_dataframe ? IntelliSenseSymbolKind.DATAFRAME : IntelliSenseSymbolKind.VARIABLE;
                            var env_item = new IntelliSenseItem (
                                ev.name,
                                ev.name,
                                ev.var_type,
                                @"Active REPL Object ($(ev.dimensions))",
                                kind,
                                0
                            ) { score = sc + 100 };
                            store.append (new IntelliSenseProposal (env_item));
                        }
                    }
                }
            }

            int max_items = 25;
            int added = 0;
            foreach (var item in items) {
                if (added >= max_items) {
                    break;
                }
                store.append (new IntelliSenseProposal (item));
                added++;
            }

            return store;
        }
    }

    /**
     * Implements VS Code-style automatic bracket/quote closing, selection wrapping,
     * overtype skip-over, and Ctrl+Space manual completion invocation.
     */
    public class BracketAutoPairController : GLib.Object {

        public static void attach (GtkSource.View view, GtkSource.Buffer buffer) {
            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);

            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                // 1. Ctrl+Space: Trigger Completion Popup Explicitly (VS Code standard shortcut)
                if (keyval == Gdk.Key.space && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    view.get_completion ().show ();
                    return true;
                }

                if (!SettingsManager.get_default ().auto_close_brackets) {
                    return false;
                }

                // Ignore when Ctrl or Alt is held
                if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) != 0) {
                    return false;
                }

                unichar ch = Gdk.keyval_to_unicode (keyval);
                if (ch == 0) {
                    return false;
                }

                string? open_str = null;
                string? close_str = null;
                bool is_quote = false;

                switch (ch) {
                    case '(':
                        open_str = "("; close_str = ")"; break;
                    case '[':
                        open_str = "["; close_str = "]"; break;
                    case '{':
                        open_str = "{"; close_str = "}"; break;
                    case '"':
                        open_str = "\""; close_str = "\""; is_quote = true; break;
                    case '\'':
                        open_str = "'"; close_str = "'"; is_quote = true; break;
                    case '`':
                        open_str = "`"; close_str = "`"; is_quote = true; break;
                    default:
                        break;
                }

                // 2. Overtype skip-over when typing closing bracket or quote already at cursor
                if (ch == ')' || ch == ']' || ch == '}' || is_quote) {
                    Gtk.TextIter s_sel, e_sel;
                    if (!buffer.get_selection_bounds (out s_sel, out e_sel)) {
                        Gtk.TextIter cur;
                        buffer.get_iter_at_mark (out cur, buffer.get_insert ());
                        if (cur.get_char () == ch) {
                            cur.forward_char ();
                            buffer.place_cursor (cur);
                            return true;
                        }
                    }
                }

                if (open_str == null || close_str == null) {
                    return false;
                }

                // 3. Selection Wrapping: If text is selected, wrap selection in open_str ... close_str
                Gtk.TextIter sel_start, sel_end;
                if (buffer.get_selection_bounds (out sel_start, out sel_end)) {
                    string selected_text = buffer.get_text (sel_start, sel_end, false);
                    string wrapped = open_str + selected_text + close_str;
                    buffer.begin_user_action ();
                    buffer.delete (ref sel_start, ref sel_end);
                    buffer.insert (ref sel_start, wrapped, -1);
                    buffer.end_user_action ();
                    return true;
                }

                // 4. Auto-Close Pair Insertion
                Gtk.TextIter cursor;
                buffer.get_iter_at_mark (out cursor, buffer.get_insert ());

                // Avoid auto-closing single quote inside words/contractions (e.g. don't)
                if (ch == '\'') {
                    Gtk.TextIter prev = cursor;
                    if (prev.backward_char () && prev.get_char ().isalnum ()) {
                        return false;
                    }
                }

                buffer.begin_user_action ();
                buffer.insert (ref cursor, open_str + close_str, -1);
                cursor.backward_char ();
                buffer.place_cursor (cursor);
                buffer.end_user_action ();

                if (ch == '{') {
                    view.get_completion ().show ();
                }
                return true;
            });

            view.add_controller (key_ctrl);
        }
    }
}
