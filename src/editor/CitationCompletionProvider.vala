// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

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

        public CitationCompletionProposal (CitationItem item, bool inside_brackets = false, Core.CitationStyle citation_style = Core.CitationStyle.PANDOC_AT, bool inside_latex_cite = false) {
            this.citekey = item.citekey;
            this.title = item.title;
            this.authors = item.authors;
            this.year = item.year;
            if (citation_style == Core.CitationStyle.LATEX_CITE) {
                this.insert_text = inside_latex_cite ? item.citekey : @"\\cite{$(item.citekey)}";
            } else {
                this.insert_text = inside_brackets ? @"@$(item.citekey)" : @"[@$(item.citekey)]";
            }
        }
    }

    public class CitationCompletionProvider : GLib.Object, GtkSource.CompletionProvider {
        private weak DocumentPage? doc_page;
        private Gee.ArrayList<CitationItem> cached_items = new Gee.ArrayList<CitationItem> ();
        private bool cached_inside_brackets = false;
        private bool cached_inside_latex_cite = false;
        private Core.CitationStyle cached_cite_style = Core.CitationStyle.PANDOC_AT;
        private string last_query = "";

        public CitationCompletionProvider (DocumentPage? doc_page = null) {
            this.doc_page = doc_page;
        }

        private Core.CitationStyle get_citation_style () {
            if (doc_page != null) {
                return Core.FormatProfile.for_format (doc_page.get_document_format ()).citation_style;
            }
            return Core.CitationStyle.PANDOC_AT;
        }

        public string? get_title () {
            return "Zotero & Citations";
        }

        public int get_priority (GtkSource.CompletionContext context) {
            return 40;
        }

        public bool is_trigger (Gtk.TextIter iter, unichar ch) {
            if (ch == '@') {
                return true;
            }
            // Keep citation popup alive for citekeys with '-', ':', '.' (e.g. @smith-2024)
            if (ch == '-' || ch == ':' || ch == '.') {
                Gtk.TextIter line_start = iter;
                line_start.set_line_offset (0);
                string prefix = iter.get_buffer ().get_text (line_start, iter, false);
                int at_idx = prefix.last_index_of ("@");
                if (at_idx >= 0) {
                    string after_at = prefix.substring (at_idx + 1);
                    if (!after_at.contains (" ") && !after_at.contains ("\t")) {
                        return true;
                    }
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
            var store = new GLib.ListStore (typeof (CitationCompletionProposal));
            var buffer = context.get_buffer ();
            if (buffer == null) {
                context.set_proposals_for_provider (this, store);
                return;
            }

            Gtk.TextIter begin_iter, cursor_iter;
            if (!context.get_bounds (out begin_iter, out cursor_iter)) {
                context.set_proposals_for_provider (this, store);
                return;
            }

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            int at_idx = line_prefix.last_index_of ("@");
            if (at_idx == -1) {
                last_query = "";
                context.set_proposals_for_provider (this, store);
                return;
            }

            string after_at = line_prefix.substring (at_idx + 1);
            if (after_at.contains (" ") || after_at.contains ("\t")) {
                last_query = "";
                context.set_proposals_for_provider (this, store);
                return;
            }

            string q_low = after_at.strip ().down ();
            last_query = "@" + q_low;

            foreach (var item in cached_items) {
                if (q_low.length == 0
                    || item.citekey.down ().contains (q_low)
                    || item.authors.down ().contains (q_low)
                    || item.title.down ().contains (q_low)
                    || item.year.down ().contains (q_low)
                    || CodeIntelliSenseEngine.compute_match_score (item.citekey, q_low) > 0) {
                    store.append (new CitationCompletionProposal (item, cached_inside_brackets, cached_cite_style, cached_inside_latex_cite));
                }
            }

            context.set_proposals_for_provider (this, store);
        }

        public void activate (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            var p = proposal as CitationCompletionProposal;
            if (p != null) {
                Gtk.TextIter begin_iter, cursor;
                if (!context.get_bounds (out begin_iter, out cursor)) {
                    return;
                }
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

                // Auto-sync references.bib in background without resetting cursor/marks
                if (doc_page != null) {
                    string project_dir = doc_page.current_project_dir;
                    if (get_citation_style () != Core.CitationStyle.LATEX_CITE) {
                        ensure_buffer_bibliography_line (buffer, "references.bib");
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
                    string lbl = @"@$(p.citekey)";
                    if (last_query.length > 0) {
                        var attrs = GtkSource.Completion.fuzzy_highlight (lbl, last_query.casefold ());
                        if (attrs != null) {
                            cell.set_text_with_attributes (lbl, attrs);
                            break;
                        }
                    }
                    cell.set_text (lbl);
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

            Gtk.TextIter begin_iter, cursor_iter;
            if (!context.get_bounds (out begin_iter, out cursor_iter)) {
                return store;
            }
            var buffer = context.get_buffer ();

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            int at_idx = line_prefix.last_index_of ("@");
            if (at_idx == -1) {
                return store;
            }

            string after_at = line_prefix.substring (at_idx + 1);
            if (after_at.contains (" ") || after_at.contains ("\t")) {
                return store;
            }

            string query = after_at.strip ();
            last_query = "@" + query.down ();
            bool inside_brackets = (at_idx > 0 && line_prefix[at_idx - 1] == '[');
            bool inside_latex_cite = false;
            try {
                var cite_ctx_rx = new GLib.Regex ("\\\\cite[a-zA-Z*]*\\s*(?:\\[[^\\]]*\\]\\s*)*\\{[^}]*$");
                inside_latex_cite = cite_ctx_rx.match (line_prefix.substring (0, at_idx));
            } catch (GLib.RegexError e) {}

            var cite_style = get_citation_style ();
            cached_inside_brackets = inside_brackets;
            cached_inside_latex_cite = inside_latex_cite;
            cached_cite_style = cite_style;

            // Read local .bib content asynchronously if available (from frontmatter, LaTeX \bibliography/\addbibresource, file dir, or project dir)
            string? fallback_bib = null;
            if (doc_page != null) {
                string base_dir = doc_page.current_project_dir;
                if (base_dir == "" && doc_page.file_location != null) {
                    var parent = doc_page.file_location.get_parent ();
                    if (parent != null) base_dir = parent.get_path () ?? "";
                }
                if (base_dir != "") {
                    var bib_names = new Gee.ArrayList<string> ();
                    Gtk.TextIter b_start, b_end;
                    buffer.get_bounds (out b_start, out b_end);
                    string full_text = buffer.get_text (b_start, b_end, false);
                    if (cite_style == Core.CitationStyle.LATEX_CITE) {
                        var latex_bibs = extract_latex_bib_filenames (full_text);
                        foreach (var lb in latex_bibs) {
                            bib_names.add (lb);
                        }
                    } else {
                        Core.FrontmatterData? fm;
                        string fm_body;
                        Core.FrontmatterParser.split_frontmatter (full_text, out fm, out fm_body);
                        if (fm != null && fm.bibliography != null && fm.bibliography.strip () != "") {
                            foreach (var fb in fm.bibliography.split (",")) {
                                string clean_fb = fb.strip ();
                                if (clean_fb.length > 0) bib_names.add (clean_fb);
                            }
                        }
                    }
                    if (bib_names.size == 0) {
                        bib_names.add ("references.bib");
                    }
                    var combined_bib = new GLib.StringBuilder ();
                    foreach (var bib_name in bib_names) {
                        string bib_path = GLib.Path.is_absolute (bib_name) ? bib_name : GLib.Path.build_filename (base_dir, bib_name);
                        var f = GLib.File.new_for_path (bib_path);
                        try {
                            uint8[] data;
                            string? etag = null;
                            yield f.load_contents_async (cancellable, out data, out etag);
                            combined_bib.append (Core.PlatformUtils.data_to_string (data));
                            combined_bib.append ("\n");
                        } catch (GLib.Error e) {
                            // .bib missing or cancelled
                        }
                    }
                    if (combined_bib.len > 0) {
                        fallback_bib = combined_bib.str;
                    }
                }
            }

            var citations = yield ZoteroService.get_default ().search_citations_async (query, fallback_bib);
            cached_items = citations;
            foreach (var item in citations) {
                store.append (new CitationCompletionProposal (item, inside_brackets, cite_style, inside_latex_cite));
            }

            return store;
        }

        private static string[] extract_latex_bib_filenames (string full_text) {
            var results = new Gee.ArrayList<string> ();
            try {
                var reg = new GLib.Regex ("\\\\(?:bibliography|addbibresource)\\s*(?:\\[[^\\]]*\\]\\s*)?\\{([^}]+)\\}");
                GLib.MatchInfo mi;
                if (reg.match (full_text, 0, out mi)) {
                    do {
                        string group = mi.fetch (1);
                        foreach (var part in group.split (",")) {
                            string raw = part.strip ();
                            if (raw.length > 0) {
                                results.add (raw.down ().has_suffix (".bib") ? raw : @"$raw.bib");
                            }
                        }
                    } while (mi.next ());
                }
            } catch (GLib.RegexError e) {}
            return results.to_array ();
        }

        public static void ensure_buffer_bibliography_line (Gtk.TextBuffer buffer, string bib_filename = "references.bib") {
            Gtk.TextIter b_start, b_end;
            buffer.get_bounds (out b_start, out b_end);
            string full_text = buffer.get_text (b_start, b_end, false);
            try {
                var reg_yaml = new GLib.Regex ("^---\\r?\\n([\\s\\S]*?)\\r?\\n---");
                GLib.MatchInfo mi;
                if (!reg_yaml.match (full_text, 0, out mi)) {
                    buffer.begin_user_action ();
                    buffer.insert (ref b_start, @"---\nbibliography: $bib_filename\n---\n\n", -1);
                    buffer.end_user_action ();
                    return;
                }
                string yaml_content = mi.fetch (1);
                var reg_bib = new GLib.Regex ("^bibliography\\s*:", GLib.RegexCompileFlags.MULTILINE);
                if (reg_bib.match (yaml_content)) {
                    return;
                }
                int start_pos, end_pos;
                if (mi.fetch_pos (1, out start_pos, out end_pos)) {
                    int char_offset = full_text.substring (0, end_pos).char_count ();
                    Gtk.TextIter insert_iter;
                    buffer.get_iter_at_offset (out insert_iter, char_offset);
                    buffer.begin_user_action ();
                    buffer.insert (ref insert_iter, @"\nbibliography: $bib_filename", -1);
                    buffer.end_user_action ();
                }
            } catch (GLib.RegexError e) {}
        }
    }
}
