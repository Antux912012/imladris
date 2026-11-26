// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Single Responsibility: GtkSourceView 5 VS Code & RStudio-style completion provider and
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
        private string last_query = "";

        public CodeIntelliSenseProvider (DocumentPage? page = null) {
            this.doc_page = page;
        }

        public string? get_title () {
            return "IntelliSense";
        }

        public int get_priority (GtkSource.CompletionContext context) {
            return 30;
        }

        public bool is_trigger (Gtk.TextIter iter, unichar ch) {
            if (!SettingsManager.get_default ().code_intellisense_enabled) {
                return false;
            }
            // Non-word trigger characters only; GtkSourceView 5 natively triggers on word chars and calls refilter()
            if (ch == '.' || ch == '$' || ch == ':' || ch == '\\' || ch == '|' ||
                ch == '{' || ch == '<' || ch == '/' || ch == '`' || ch == '(' ||
                ch == '@' || ch == '#') {
                return true;
            }
            // Keep completion open across hyphenated tokens (e.g., fig-cap, @fig-volcano, :::callout-note)
            if (ch == '-') {
                Gtk.TextIter prev = iter;
                if (prev.backward_chars (2) && (prev.get_char ().isalnum () || prev.get_char () == ':' || prev.get_char () == '@')) {
                    return true;
                }
            }
            return false;
        }

        public bool key_activates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal, uint keyval, Gdk.ModifierType state) {
            return keyval == Gdk.Key.Tab || keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter;
        }

        public GenericArray<GtkSource.CompletionProposal>? list_alternates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            return null;
        }

        public void refilter (GtkSource.CompletionContext context, GLib.ListModel model) {
            var updated = build_proposals_store (context);
            context.set_proposals_for_provider (this, updated);
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
                    if (last_query.length > 0) {
                        var attrs = GtkSource.Completion.fuzzy_highlight (p.item.label, last_query.casefold ());
                        if (attrs != null) {
                            cell.set_text_with_attributes (p.item.label, attrs);
                            break;
                        }
                    }
                    cell.set_text (p.item.label);
                    break;
                case GtkSource.CompletionColumn.AFTER:
                    if (p.item.signature.length > 0) {
                        cell.set_text ("  " + p.item.signature);
                    } else {
                        cell.set_text ("");
                    }
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
            if (buffer == null) {
                return;
            }

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            Gtk.TextIter doc_start, doc_end;
            buffer.get_bounds (out doc_start, out doc_end);
            string full_text = buffer.get_text (doc_start, doc_end, false);
            string doc_type = doc_page != null ? doc_page.doc_type : "markdown";
            int cursor_line = cursor_iter.get_line ();
            var ctx = CodeIntelliSenseEngine.detect_context (full_text, cursor_line, line_prefix, doc_type);

            unichar next_ch = cursor_iter.get_char ();

            buffer.begin_user_action ();

            if (line_prefix.strip ().has_prefix ("#|") && p.item.kind == IntelliSenseSymbolKind.OPTION) {
                int pipe_byte_idx = line_prefix.index_of ("#|");
                int pipe_char_idx = line_prefix.substring (0, pipe_byte_idx).char_count ();
                Gtk.TextIter replace_start = line_start;
                replace_start.forward_chars (pipe_char_idx);
                buffer.delete (ref replace_start, ref cursor_iter);
                string opt_body = p.item.insert_text.has_prefix ("#|")
                    ? p.item.insert_text.substring (2).strip ()
                    : p.item.insert_text;
                string replacement = "#| " + opt_body;
                buffer.insert (ref replace_start, replacement, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            } else if (line_prefix.strip ().has_prefix ("```") && p.item.kind == IntelliSenseSymbolKind.SNIPPET) {
                int fence_byte_idx = line_prefix.index_of ("```");
                int fence_char_idx = line_prefix.substring (0, fence_byte_idx).char_count ();
                Gtk.TextIter replace_start = line_start;
                replace_start.forward_chars (fence_char_idx);
                if (cursor_iter.get_char () == '}') {
                    cursor_iter.forward_char ();
                }
                buffer.delete (ref replace_start, ref cursor_iter);
                buffer.insert (ref replace_start, p.item.insert_text, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            } else if (line_prefix.strip ().has_prefix ("::") && p.item.insert_text.has_prefix (":::")) {
                int col_byte_idx = line_prefix.index_of ("::");
                int col_char_idx = line_prefix.substring (0, col_byte_idx).char_count ();
                Gtk.TextIter replace_start = line_start;
                replace_start.forward_chars (col_char_idx);
                buffer.delete (ref replace_start, ref cursor_iter);
                buffer.insert (ref replace_start, p.item.insert_text, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            } else {
                string token = CodeIntelliSenseEngine.extract_active_token_for_context (line_prefix, ctx);
                Gtk.TextIter replace_start = cursor_iter;
                if (token.length > 0) {
                    replace_start.backward_chars (token.char_count ());
                    buffer.delete (ref replace_start, ref cursor_iter);
                }

                string ins = p.item.insert_text;
                int backtrack = p.item.cursor_backtrack;

                // Avoid duplicating '(' when the character immediately following cursor is already '('
                if (next_ch == '(' && (p.item.kind == IntelliSenseSymbolKind.FUNCTION || p.item.kind == IntelliSenseSymbolKind.METHOD)) {
                    int open_p = ins.index_of ("(");
                    if (open_p > 0) {
                        ins = ins.substring (0, open_p);
                        backtrack = 0;
                    }
                }

                // Avoid duplicating '>' when completing an HTML tag before an existing '>'
                if (next_ch == '>' && p.item.kind == IntelliSenseSymbolKind.TAG && ins.has_suffix (">")) {
                    ins = ins.substring (0, ins.length - 1);
                    backtrack = 0;
                }

                buffer.insert (ref replace_start, ins, -1);
                if (backtrack > 0) {
                    replace_start.backward_chars (backtrack);
                    buffer.place_cursor (replace_start);
                }
            }

            buffer.end_user_action ();
        }

        public async GLib.ListModel populate_async (GtkSource.CompletionContext context, GLib.Cancellable? cancellable) throws GLib.Error {
            return build_proposals_store (context);
        }

        private GLib.ListStore build_proposals_store (GtkSource.CompletionContext context) {
            var store = new GLib.ListStore (typeof (IntelliSenseProposal));
            if (!SettingsManager.get_default ().code_intellisense_enabled) {
                last_query = "";
                return store;
            }

            var buffer = context.get_buffer ();
            if (buffer == null) {
                last_query = "";
                return store;
            }

            Gtk.TextIter cursor_iter;
            context.get_bounds (null, out cursor_iter);

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            Gtk.TextIter doc_start, doc_end;
            buffer.get_bounds (out doc_start, out doc_end);
            string full_text = buffer.get_text (doc_start, doc_end, false);

            string doc_type = doc_page != null ? doc_page.doc_type : "markdown";
            int cursor_line = cursor_iter.get_line ();
            bool manual_trigger = (context.get_activation () == GtkSource.CompletionActivation.USER_REQUESTED);

            var ctx = CodeIntelliSenseEngine.detect_context (full_text, cursor_line, line_prefix, doc_type);
            string token = CodeIntelliSenseEngine.extract_active_token_for_context (line_prefix, ctx);

            // Track active highlight query for fuzzy_highlight in display()
            if (ctx == IntelliSenseContext.QUARTO_HASH_PIPE && line_prefix.strip ().length >= 2) {
                last_query = line_prefix.strip ().substring (2).strip ();
            } else if (ctx == IntelliSenseContext.CHUNK_FENCE_HEADER) {
                last_query = line_prefix.strip ();
            } else {
                last_query = token;
            }

            var items = CodeIntelliSenseEngine.query_completions (
                full_text,
                cursor_line,
                line_prefix,
                doc_type,
                manual_trigger,
                ctx
            );

            // Merge live REPL session variables and DataFrame columns from EnvironmentController
            if ((ctx == IntelliSenseContext.R_CODE || ctx == IntelliSenseContext.PYTHON_CODE)
                && doc_page != null && doc_page.panel_registry != null) {
                var env_vars = doc_page.panel_registry.environment_controller.get_cached_variables ();

                if (ctx == IntelliSenseContext.R_CODE && token.contains ("$")) {
                    string[] parts = token.split ("$", 2);
                    string df_name = parts[0];
                    string col_prefix = parts.length > 1 ? parts[1] : "";
                    foreach (var ev in env_vars) {
                        if (ev.name == df_name && ev.columns_csv.length > 0) {
                            foreach (string col in ev.columns_csv.split (",")) {
                                string clean_col = col.strip ();
                                if (clean_col.length == 0) continue;
                                int sc = CodeIntelliSenseEngine.compute_match_score (clean_col, col_prefix);
                                if (sc > 0) {
                                    items.add (new IntelliSenseItem (
                                        df_name + "$" + clean_col,
                                        df_name + "$" + clean_col,
                                        "live column",
                                        @"Live R Session Column of $(ev.name) ($(ev.dimensions))",
                                        IntelliSenseSymbolKind.COLUMN,
                                        0
                                    ) { score = sc + 260 });
                                }
                            }
                        }
                    }
                } else if (ctx == IntelliSenseContext.PYTHON_CODE && token.contains (".")) {
                    int dot_idx = token.index_of (".");
                    string obj_name = token.substring (0, dot_idx);
                    string member_prefix = token.substring (dot_idx + 1);
                    foreach (var ev in env_vars) {
                        if (ev.name == obj_name && ev.var_engine == "python") {
                            if (ev.columns_csv.length > 0) {
                                foreach (string col in ev.columns_csv.split (",")) {
                                    string clean_col = col.strip ();
                                    if (clean_col.length == 0) continue;
                                    int sc = CodeIntelliSenseEngine.compute_match_score (clean_col, member_prefix);
                                    if (sc > 0) {
                                        items.add (new IntelliSenseItem (
                                            obj_name + "." + clean_col,
                                            obj_name + "." + clean_col,
                                            "live column",
                                            @"Live Python DataFrame Column of $(ev.name) ($(ev.dimensions))",
                                            IntelliSenseSymbolKind.COLUMN,
                                            0
                                        ) { score = sc + 260 });
                                    }
                                }
                            }
                            if (ev.is_dataframe) {
                                foreach (var dfm in CodeIntelliSenseEngine.get_python_df_methods ()) {
                                    int sc = CodeIntelliSenseEngine.compute_match_score (dfm.label, member_prefix);
                                    if (sc > 0) {
                                        items.add (new IntelliSenseItem (
                                            obj_name + "." + dfm.label,
                                            obj_name + "." + dfm.insert_text,
                                            dfm.signature,
                                            dfm.detail,
                                            dfm.kind,
                                            dfm.cursor_backtrack
                                        ) { score = sc + 190 });
                                    }
                                }
                            }
                        }
                    }
                } else if ((token.length > 0 || manual_trigger) && !token.contains ("$") && !token.contains ("::") && !token.contains (".")) {
                    string expected_eng = (ctx == IntelliSenseContext.R_CODE) ? "r" : "python";
                    foreach (var ev in env_vars) {
                        if (ev.var_engine != expected_eng) continue;
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
                            ) { score = sc + 120 };
                            items.add (env_item);
                        }
                    }
                }
            }

            // Sort by score descending, then deduplicate by label keeping highest-scored item
            items.sort ((a, b) => {
                if (a.score != b.score) {
                    return b.score - a.score;
                }
                return strcmp (a.label, b.label);
            });

            var seen_labels = new HashSet<string> ();
            int max_items = 35;
            int added = 0;
            foreach (var item in items) {
                if (added >= max_items) {
                    break;
                }
                if (seen_labels.contains (item.label)) {
                    continue;
                }
                seen_labels.add (item.label);
                store.append (new IntelliSenseProposal (item));
                added++;
            }

            return store;
        }
    }

    /**
     * Implements VS Code & RStudio-style automatic bracket/quote closing, selection wrapping,
     * overtype skip-over, paired Backspace deletion, triple-backtick handling, and Ctrl+Space invocation.
     */
    public class BracketAutoPairController : GLib.Object {

        private static bool is_matching_pair (unichar left, unichar right) {
            return (left == '(' && right == ')')
                || (left == '[' && right == ']')
                || (left == '{' && right == '}')
                || (left == '"' && right == '"')
                || (left == '\'' && right == '\'')
                || (left == '`' && right == '`');
        }

        public static void attach (GtkSource.View view, GtkSource.Buffer buffer) {
            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);

            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                // 1. Ctrl+Space: Trigger Completion Popup Explicitly (VS Code / RStudio standard shortcut)
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

                // 2. BackSpace inside an empty auto-closed pair: delete both chars in one step
                if (keyval == Gdk.Key.BackSpace) {
                    Gtk.TextIter bs_s, bs_e;
                    if (!buffer.get_selection_bounds (out bs_s, out bs_e)) {
                        Gtk.TextIter cur;
                        buffer.get_iter_at_mark (out cur, buffer.get_insert ());
                        Gtk.TextIter prev = cur;
                        if (prev.backward_char () && !cur.is_end ()) {
                            if (is_matching_pair (prev.get_char (), cur.get_char ())) {
                                Gtk.TextIter next = cur;
                                next.forward_char ();
                                buffer.begin_user_action ();
                                buffer.delete (ref prev, ref next);
                                buffer.end_user_action ();
                                return true;
                            }
                        }
                    }
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

                // 3. Overtype skip-over when typing closing bracket or quote already at cursor
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

                // 4. Selection Wrapping: If text is selected, wrap selection in open_str ... close_str
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

                // 5. Auto-Close Pair Insertion
                Gtk.TextIter cursor;
                buffer.get_iter_at_mark (out cursor, buffer.get_insert ());

                // Triple-backtick handling: if preceded by `` then insert single ` and trigger chunk completion
                if (ch == '`') {
                    Gtk.TextIter p1 = cursor;
                    Gtk.TextIter p2 = cursor;
                    if (p1.backward_char () && p1.get_char () == '`' && p2.backward_chars (2) && p2.get_char () == '`') {
                        buffer.begin_user_action ();
                        buffer.insert (ref cursor, "`", -1);
                        buffer.end_user_action ();
                        view.get_completion ().show ();
                        return true;
                    }
                }

                // Avoid auto-closing single quote inside words/contractions (e.g. don't)
                if (ch == '\'') {
                    Gtk.TextIter prev = cursor;
                    if (prev.backward_char () && prev.get_char ().isalnum ()) {
                        return false;
                    }
                }

                // Check previous char before inserting to decide whether to trigger completion
                unichar prev_ch = 0;
                Gtk.TextIter prev_iter = cursor;
                if (prev_iter.backward_char ()) {
                    prev_ch = prev_iter.get_char ();
                }

                buffer.begin_user_action ();
                buffer.insert (ref cursor, open_str + close_str, -1);
                cursor.backward_char ();
                buffer.place_cursor (cursor);
                buffer.end_user_action ();

                if (ch == '{') {
                    view.get_completion ().show ();
                } else if (ch == '(' && (prev_ch.isalnum () || prev_ch == '_' || prev_ch == '.')) {
                    // Show R/Python function argument or library() package completions when typing fn(
                    view.get_completion ().show ();
                }
                return true;
            });

            view.add_controller (key_ctrl);
        }
    }
}
