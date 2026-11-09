// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Gtk;
using GtkSource;
using Imladris.Services;

namespace Imladris.Editor {

    public class CitationCompletionProposal : GLib.Object, GtkSource.CompletionProposal {
        public string citekey { get; set; }
        public string title { get; set; }
        public string authors { get; set; }
        public string year { get; set; }
        public string insert_text { get; set; }

        public CitationCompletionProposal (CitationItem item, bool inside_brackets = false) {
            this.citekey = item.citekey;
            this.title = item.title;
            this.authors = item.authors;
            this.year = item.year;
            this.insert_text = inside_brackets ? @"@$(item.citekey)" : @"[@$(item.citekey)]";
        }
    }

    public class CitationCompletionProvider : GLib.Object, GtkSource.CompletionProvider {
        private weak DocumentPage? doc_page;

        public CitationCompletionProvider (DocumentPage? doc_page = null) {
            this.doc_page = doc_page;
        }

        public string? get_title () {
            return "Zotero & Citations";
        }

        public int get_priority (GtkSource.CompletionContext context) {
            return 3;
        }

        public bool is_trigger (Gtk.TextIter iter, unichar ch) {
            return ch == '@';
        }

        public bool key_activates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal, uint keyval, Gdk.ModifierType state) {
            return false;
        }

        public GenericArray<GtkSource.CompletionProposal>? list_alternates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            return null;
        }

        public void refilter (GtkSource.CompletionContext context, GLib.ListModel model) {
            // Contextual filtering
        }

        public void activate (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            var p = proposal as CitationCompletionProposal;
            if (p != null) {
                Gtk.TextIter cursor;
                context.get_bounds (out cursor, null);
                var buffer = context.get_buffer ();

                // Find the '@' preceding cursor to replace typed filter prefix
                Gtk.TextIter at_iter = cursor;
                while (at_iter.backward_char ()) {
                    unichar c = at_iter.get_char ();
                    if (c == '@') {
                        break;
                    }
                    if (c == ' ' || c == '\n' || c == '\t' || c == '[') {
                        at_iter = cursor;
                        break;
                    }
                }

                buffer.begin_user_action ();
                if (at_iter.get_char () == '@') {
                    buffer.delete (ref at_iter, ref cursor);
                    buffer.insert (ref at_iter, p.insert_text, -1);
                } else {
                    buffer.insert (ref cursor, p.insert_text, -1);
                }
                buffer.end_user_action ();

                // Auto-sync references.bib in background
                if (doc_page != null) {
                    string project_dir = doc_page.current_project_dir;
                    Gtk.TextIter b_start, b_end;
                    buffer.get_bounds (out b_start, out b_end);
                    string full_text = buffer.get_text (b_start, b_end, false);
                    string updated_text = ZoteroService.get_default ().ensure_yaml_bibliography (full_text, "references.bib");
                    if (updated_text != full_text) {
                        buffer.begin_user_action ();
                        buffer.set_text (updated_text);
                        buffer.end_user_action ();
                    }
                    ZoteroService.get_default ().sync_citation_to_project_async.begin (p.citekey, project_dir);
                }
            }
        }

        public void display (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal, GtkSource.CompletionCell cell) {
            var p = proposal as CitationCompletionProposal;
            if (p == null) return;

            switch (cell.get_column ()) {
                case GtkSource.CompletionColumn.ICON:
                    cell.set_icon_name ("accessories-dictionary-symbolic");
                    break;
                case GtkSource.CompletionColumn.TYPED_TEXT:
                    cell.set_text (@"@$(p.citekey)");
                    break;
                case GtkSource.CompletionColumn.DETAILS:
                    string details = @"$(p.authors) ($(p.year)) - $(p.title)";
                    cell.set_text (details);
                    break;
                default:
                    break;
            }
        }

        public async GLib.ListModel populate_async (GtkSource.CompletionContext context, GLib.Cancellable? cancellable) throws GLib.Error {
            var store = new GLib.ListStore (typeof (CitationCompletionProposal));

            Gtk.TextIter cursor_iter;
            context.get_bounds (out cursor_iter, null);
            var buffer = context.get_buffer ();

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            int at_idx = line_prefix.last_index_of ("@");
            if (at_idx == -1) {
                return store;
            }

            string query = line_prefix.substring (at_idx + 1).strip ();
            bool inside_brackets = (at_idx > 0 && line_prefix[at_idx - 1] == '[');

            // Read references.bib content if available
            string? fallback_bib = null;
            if (doc_page != null) {
                string pdir = doc_page.current_project_dir;
                if (pdir != "") {
                    string bib_path = GLib.Path.build_filename (pdir, "references.bib");
                    var f = GLib.File.new_for_path (bib_path);
                    if (f.query_exists ()) {
                        try {
                            uint8[] data;
                            f.load_contents (null, out data, null);
                            fallback_bib = (string) data;
                        } catch (GLib.Error e) {}
                    }
                }
            }

            var citations = yield ZoteroService.get_default ().search_citations_async (query, fallback_bib);
            foreach (var item in citations) {
                store.append (new CitationCompletionProposal (item, inside_brackets));
            }

            return store;
        }
    }
}
