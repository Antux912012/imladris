// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Modal dialog for choosing among the top 10 scientific
 * LaTeX publisher templates and top 10 academic citation styles.
 * Architecture: Adw.Dialog backed by Core.LatexTemplates.
 * Concurrency: Executes on the GLib MainContext thread.
 */

using GLib;
using Gtk;

namespace Imladris.UI {

    public class LatexTemplateDialog : Adw.Dialog {

        public signal void template_selected (string template_title, string starter_content, string suggested_filename);

        private GLib.GenericArray<Core.LatexTemplateInfo> templates;
        private GLib.GenericArray<Core.LatexCitationStyleInfo> citation_styles;
        private int selected_template_idx = 0;

        private Adw.EntryRow title_row;
        private Adw.EntryRow author_row;
        private Adw.EntryRow bib_row;
        private Adw.ComboRow citation_combo;
        private Gtk.Label citation_preview_lbl;
        private Gtk.ListBox template_list;

        public LatexTemplateDialog () {
            this.title = "New LaTeX Manuscript from Publisher Template";
            this.content_width = 660;
            this.content_height = 680;

            templates = Core.LatexTemplates.get_top_templates ();
            citation_styles = Core.LatexTemplates.get_top_citation_styles ();

            setup_ui ();
        }

        private void setup_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header_bar = new Adw.HeaderBar ();

            var cancel_btn = new Gtk.Button.with_label ("Cancel");
            cancel_btn.clicked.connect (() => {
                this.close ();
            });
            header_bar.pack_start (cancel_btn);

            var create_btn = new Gtk.Button.with_label ("Create Manuscript");
            create_btn.add_css_class ("suggested-action");
            create_btn.clicked.connect (emit_selected_template);
            header_bar.pack_end (create_btn);

            toolbar_view.add_top_bar (header_bar);

            var scroller = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true,
                hexpand = true
            };

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
                margin_top = 16,
                margin_bottom = 20,
                margin_start = 20,
                margin_end = 20
            };

            // 1. Metadata Group
            var meta_group = new Adw.PreferencesGroup () {
                title = "Manuscript Details",
                description = "Metadata injected into the selected publisher preamble and bibliography setup."
            };

            title_row = new Adw.EntryRow () {
                title = "Manuscript Title",
                text = "Reproducible Scientific Investigation"
            };
            author_row = new Adw.EntryRow () {
                title = "Author(s)",
                text = GLib.Environment.get_real_name ()
            };
            bib_row = new Adw.EntryRow () {
                title = "Bibliography File (.bib)",
                text = "references.bib"
            };

            meta_group.add (title_row);
            meta_group.add (author_row);
            meta_group.add (bib_row);
            content_box.append (meta_group);

            // 2. Citation Style Group (Top 10)
            var cite_group = new Adw.PreferencesGroup () {
                title = "Citation & Bibliography Style (Top 10)",
                description = "Automatically matched to the publisher template; override with any style accepted by your journal."
            };

            var cite_names = new Gtk.StringList (null);
            for (int i = 0; i < citation_styles.length; i++) {
                cite_names.append (citation_styles[i].name);
            }

            citation_combo = new Adw.ComboRow () {
                title = "Citation Style",
                model = cite_names,
                selected = 0
            };
            cite_group.add (citation_combo);

            citation_preview_lbl = new Gtk.Label ("") {
                wrap = true,
                xalign = 0.0f,
                margin_top = 6,
                margin_start = 4,
                css_classes = { "dim-label", "caption" }
            };
            citation_combo.notify["selected"].connect (update_citation_preview);
            cite_group.add (citation_preview_lbl);

            content_box.append (cite_group);

            // 3. Publisher Template Group (Top 10)
            var tpl_group = new Adw.PreferencesGroup () {
                title = "Publisher & Venue Template (Top 10)",
                description = "Select a journal or conference template. Recommended citation style is applied automatically."
            };

            template_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE
            };
            template_list.add_css_class ("boxed-list");

            for (int i = 0; i < templates.length; i++) {
                var tpl = templates[i];
                var row = new Adw.ActionRow () {
                    title = GLib.Markup.escape_text (tpl.name),
                    subtitle = GLib.Markup.escape_text (@"$(tpl.publisher) · \\documentclass{$(tpl.document_class)} · $(tpl.layout_summary)\n$(tpl.description)"),
                    activatable = true
                };
                row.add_prefix (new Gtk.Image.from_icon_name ("x-office-document-symbolic") {
                    pixel_size = 22
                });
                var badge = new Gtk.Label (tpl.publisher) {
                    valign = Gtk.Align.CENTER,
                    css_classes = { "caption", "dim-label" }
                };
                row.add_suffix (badge);
                template_list.append (row);
            }

            template_list.row_selected.connect ((row) => {
                if (row == null) return;
                int idx = row.get_index ();
                if (idx >= 0 && idx < templates.length) {
                    selected_template_idx = idx;
                    sync_citation_to_template (templates[idx]);
                }
            });

            // Select first row by default
            var first_row = template_list.get_row_at_index (0);
            if (first_row != null) {
                template_list.select_row (first_row);
            }

            tpl_group.add (template_list);
            content_box.append (tpl_group);

            scroller.set_child (content_box);
            toolbar_view.set_content (scroller);
            this.set_child (toolbar_view);

            update_citation_preview ();
        }

        private void sync_citation_to_template (Core.LatexTemplateInfo tpl) {
            for (int i = 0; i < citation_styles.length; i++) {
                if (citation_styles[i].id == tpl.default_citation_id) {
                    citation_combo.selected = (uint) i;
                    break;
                }
            }
            update_citation_preview ();
        }

        private void update_citation_preview () {
            uint sel = citation_combo.selected;
            if (sel < citation_styles.length) {
                var cs = citation_styles[(int) sel];
                citation_preview_lbl.label = @"$(cs.category) — In-text: $(cs.example_in_text) — Command: $(cs.cite_command)\n$(cs.description)";
            }
        }

        private void emit_selected_template () {
            if (selected_template_idx < 0 || selected_template_idx >= templates.length) {
                selected_template_idx = 0;
            }
            var tpl = templates[selected_template_idx];
            uint cite_idx = citation_combo.selected;
            if (cite_idx >= citation_styles.length) {
                cite_idx = 0;
            }
            var cite_style = citation_styles[(int) cite_idx];

            string content = Core.LatexTemplates.generate_document (
                tpl,
                cite_style,
                title_row.text,
                author_row.text,
                bib_row.text
            );

            template_selected (tpl.name, content, tpl.suggested_filename);
            this.close ();
        }
    }
}
