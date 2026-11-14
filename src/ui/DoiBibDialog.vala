// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using Gtk;
using Adw;
using GLib;

namespace Imladris.UI {

    public class DoiBibDialog : Adw.Dialog {

        public signal void insert_citation_requested (string citekey, string bib_filename);

        private string current_bib_path;
        private Gtk.Label bib_path_lbl;
        private Adw.EntryRow doi_entry;
        private Gtk.Button fetch_btn;
        private Gtk.Spinner fetch_spinner;
        private Gtk.TextView preview_view;
        private Gtk.Button add_only_btn;
        private Gtk.Button add_and_cite_btn;
        private Gtk.Label status_lbl;
        private Gtk.SearchEntry filter_entry;
        private Gtk.ListBox entries_list;
        private GLib.Cancellable? list_cancellable = null;

        public DoiBibDialog (string initial_bib_path) {
            Object (
                title: "Bibliography & DOI Manager (.bib)",
                content_width: 680,
                content_height: 700
            );
            this.current_bib_path = initial_bib_path;
            build_ui ();
            refresh_entries_list_async.begin ();
        }

        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header);

            var page = new Adw.PreferencesPage ();

            // GROUP 1: Target .bib file
            var file_group = new Adw.PreferencesGroup () {
                title = "Target Bibliography File (.bib)",
                description = "Manage local BibTeX references in parallel with Zotero."
            };

            var file_row = new Adw.ActionRow () {
                title = "Active .bib File"
            };
            bib_path_lbl = new Gtk.Label (current_bib_path) {
                ellipsize = Pango.EllipsizeMode.START,
                max_width_chars = 48,
                halign = Gtk.Align.START
            };
            bib_path_lbl.add_css_class ("dim-label");
            bib_path_lbl.add_css_class ("caption");
            file_row.add_suffix (bib_path_lbl);

            var choose_btn = new Gtk.Button.with_label ("Choose / Create...") {
                valign = Gtk.Align.CENTER
            };
            choose_btn.clicked.connect (on_choose_bib_clicked);
            file_row.add_suffix (choose_btn);

            file_group.add (file_row);
            page.add (file_group);

            // GROUP 2: DOI Lookup & BibTeX Generation
            var doi_group = new Adw.PreferencesGroup () {
                title = "Generate Entry from DOI",
                description = "Paste a DOI (e.g. 10.1038/s41586-020-2649-2) or https://doi.org/... link."
            };

            doi_entry = new Adw.EntryRow () {
                title = "DOI or DOI URL"
            };
            doi_entry.entry_activated.connect (on_fetch_clicked);

            fetch_spinner = new Gtk.Spinner () {
                valign = Gtk.Align.CENTER,
                visible = false
            };
            fetch_btn = new Gtk.Button.with_label ("Fetch BibTeX") {
                valign = Gtk.Align.CENTER
            };
            fetch_btn.add_css_class ("suggested-action");
            fetch_btn.clicked.connect (on_fetch_clicked);

            doi_entry.add_suffix (fetch_spinner);
            doi_entry.add_suffix (fetch_btn);
            doi_group.add (doi_entry);

            var preview_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 8
            };

            var scroller = new Gtk.ScrolledWindow () {
                height_request = 170,
                hexpand = true
            };
            scroller.add_css_class ("view");
            scroller.add_css_class ("frame");

            preview_view = new Gtk.TextView () {
                monospace = true,
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                left_margin = 8,
                right_margin = 8,
                top_margin = 8,
                bottom_margin = 8
            };
            scroller.set_child (preview_view);
            preview_box.append (scroller);

            var action_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            status_lbl = new Gtk.Label ("") {
                hexpand = true,
                xalign = 0.0f,
                wrap = true
            };
            status_lbl.add_css_class ("caption");
            action_bar.append (status_lbl);

            add_only_btn = new Gtk.Button.with_label ("Add to .bib") {
                sensitive = false
            };
            add_only_btn.clicked.connect (() => save_entry_async.begin (false));
            action_bar.append (add_only_btn);

            add_and_cite_btn = new Gtk.Button.with_label ("Add & Cite [@key]") {
                sensitive = false
            };
            add_and_cite_btn.add_css_class ("suggested-action");
            add_and_cite_btn.clicked.connect (() => save_entry_async.begin (true));
            action_bar.append (add_and_cite_btn);

            preview_box.append (action_bar);
            doi_group.add (preview_box);
            page.add (doi_group);

            // GROUP 3: Local .bib Entries
            var list_group = new Adw.PreferencesGroup () {
                title = "Entries in Active .bib File"
            };

            filter_entry = new Gtk.SearchEntry () {
                placeholder_text = "Filter by citekey, author, title, or year...",
                margin_bottom = 8
            };
            filter_entry.search_changed.connect (() => {
                refresh_entries_list_async.begin ();
            });
            list_group.add (filter_entry);

            entries_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE
            };
            entries_list.add_css_class ("boxed-list");
            list_group.add (entries_list);
            page.add (list_group);

            toolbar_view.content = page;
            this.child = toolbar_view;

            preview_view.buffer.changed.connect (() => {
                bool has_bib = preview_view.buffer.text.strip ().has_prefix ("@");
                add_only_btn.sensitive = has_bib;
                add_and_cite_btn.sensitive = has_bib;
            });
        }

        private void on_choose_bib_clicked () {
            choose_bib_async.begin ();
        }

        private async void choose_bib_async () {
            var filter = new Gtk.FileFilter ();
            filter.name = "BibTeX Files (*.bib)";
            filter.add_pattern ("*.bib");
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);

            var dialog = new Gtk.FileDialog () {
                title = "Open Existing .bib File",
                modal = true,
                filters = filters,
                default_filter = filter
            };
            try {
                var parent_win = this.get_root () as Gtk.Window;
                var file = yield dialog.open (parent_win, null);
                if (file != null) {
                    string? p = file.get_path ();
                    if (p == null) {
                        status_lbl.label = "✖ Please choose a local file path.";
                        return;
                    }
                    if (!p.down ().has_suffix (".bib")) p += ".bib";
                    current_bib_path = p;
                    bib_path_lbl.label = current_bib_path;
                    yield Services.DoiBibService.get_default ().ensure_bib_file_exists_async (current_bib_path);
                    yield refresh_entries_list_async ();
                }
            } catch (GLib.Error e) {}
        }

        private void on_fetch_clicked () {
            fetch_doi_async.begin ();
        }

        private async void fetch_doi_async () {
            string raw = doi_entry.text.strip ();
            if (raw.length == 0) {
                status_lbl.label = "Enter a DOI, https://doi.org/... URL, or PubMed PMID.";
                return;
            }

            fetch_btn.sensitive = false;
            fetch_spinner.visible = true;
            fetch_spinner.start ();
            status_lbl.label = "Resolving DOI / PubMed metadata...";

            try {
                string bib = yield Services.DoiBibService.get_default ().fetch_bibtex_from_identifier_async (raw);
                preview_view.buffer.text = bib;
                status_lbl.label = "✔ BibTeX entry generated. Review and add to .bib.";
            } catch (GLib.Error e) {
                status_lbl.label = @"✖ $(e.message)";
            } finally {
                fetch_spinner.stop ();
                fetch_spinner.visible = false;
                fetch_btn.sensitive = true;
            }
        }

        private async void save_entry_async (bool also_cite) {
            string entry = preview_view.buffer.text.strip ();
            if (!entry.has_prefix ("@")) return;

            try {
                string final_key;
                yield Services.DoiBibService.get_default ().append_entry_to_bib_file_async (current_bib_path, entry, out final_key);
                status_lbl.label = @"✔ Saved @$final_key to $(GLib.Path.get_basename (current_bib_path))";
                yield refresh_entries_list_async ();
                if (also_cite) {
                    insert_citation_requested (final_key, GLib.Path.get_basename (current_bib_path));
                    this.close ();
                }
            } catch (GLib.Error e) {
                status_lbl.label = @"✖ Failed to save .bib: $(e.message)";
            }
        }

        private async void refresh_entries_list_async () {
            if (list_cancellable != null) {
                list_cancellable.cancel ();
            }
            var cancellable = new GLib.Cancellable ();
            list_cancellable = cancellable;

            var f = GLib.File.new_for_path (current_bib_path);
            string? content = null;
            string? err_msg = null;

            if (f.query_exists ()) {
                try {
                    uint8[] data;
                    yield f.load_contents_async (cancellable, out data, null);
                    content = Core.PlatformUtils.data_to_string (data);
                } catch (GLib.Error e) {
                    if (e is GLib.IOError.CANCELLED) return;
                    err_msg = e.message;
                }
            }

            if (cancellable.is_cancelled ()) return;

            Gtk.Widget? child = entries_list.get_first_child ();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling ();
                entries_list.remove (child);
                child = next;
            }

            if (err_msg != null) {
                var err_row = new Adw.ActionRow () {
                    title = "Could not read .bib file",
                    subtitle = err_msg,
                    use_markup = false
                };
                entries_list.append (err_row);
                return;
            }

            if (content == null) {
                var empty_row = new Adw.ActionRow () {
                    title = "No .bib file yet",
                    subtitle = "Fetch a DOI above to create and populate " + GLib.Path.get_basename (current_bib_path),
                    use_markup = false
                };
                entries_list.append (empty_row);
                return;
            }

            string q = filter_entry.text.strip ();
            var items = Services.ZoteroService.get_default ().search_offline_bib (q, content);
            if (items.size == 0) {
                var none_row = new Adw.ActionRow () {
                    title = "No matching entries",
                    subtitle = q == "" ? "Add an entry using a DOI above." : "No entries match your filter.",
                    use_markup = false
                };
                entries_list.append (none_row);
                return;
            }

            foreach (var item in items) {
                var row = new Adw.ActionRow () {
                    title = @"@$(item.citekey) — $(item.title)",
                    subtitle = @"$(item.authors) ($(item.year))",
                    use_markup = false
                };
                string key = item.citekey;
                var cite_btn = new Gtk.Button.with_label ("Cite") {
                    valign = Gtk.Align.CENTER
                };
                cite_btn.clicked.connect (() => {
                    insert_citation_requested (key, GLib.Path.get_basename (current_bib_path));
                    this.close ();
                });
                row.add_suffix (cite_btn);
                entries_list.append (row);
            }
        }
    }
}
