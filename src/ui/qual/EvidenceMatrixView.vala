// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Qual;

namespace Imladris.UI.Qual {

    /**
     * Virtualized Gtk.ColumnView pivoting Entities x Codes with coder, confidence,
     * and CRA Source Data Verification (SDV) filtering, Quarto table insertion, and CSV/TSV export.
     */
    public class EvidenceMatrixView : Gtk.Box {
        private QualWorkspaceService service;
        private unowned Window? parent_window;
        private GLib.ListStore row_store;
        private Gtk.SingleSelection selection_model;
        private Gtk.ColumnView column_view;
        private Gtk.Entry coder_filter_entry;
        private Gtk.DropDown conf_dropdown;
        private Gtk.DropDown sdv_dropdown;
        private Gtk.Label summary_label;
        private Gtk.Button clear_graph_filter_btn;
        private string? code_filter = null;
        private Gee.ArrayList<EvidenceMatrixRow> current_rows;

        public signal void jump_to_span_requested (string file_path, int line_start, string span_id);
        public signal void insert_quarto_table_requested (string markdown_table);

        public EvidenceMatrixView (QualWorkspaceService svc, Window? win = null) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.service = svc;
            this.parent_window = win;
            this.hexpand = true;
            this.vexpand = true;
            this.current_rows = new Gee.ArrayList<EvidenceMatrixRow> ();

            build_ui ();
            refresh ();
        }

        public void set_code_filter (string? cid) {
            this.code_filter = cid;
            refresh ();
        }

        public void set_service (QualWorkspaceService svc) {
            this.service = svc;
            refresh ();
        }

        private void build_ui () {
            var filter_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 8,
                margin_end = 8
            };
            filter_bar.add_css_class ("dock-subtoolbar");

            coder_filter_entry = new Gtk.Entry () {
                placeholder_text = "Filter coder...",
                width_chars = 12,
                tooltip_text = "Filter matrix by coder ID (disabled while Blinded Mode is active)"
            };
            coder_filter_entry.changed.connect (refresh);
            filter_bar.append (coder_filter_entry);

            conf_dropdown = new Gtk.DropDown (new Gtk.StringList ({ "All Confidence", "high", "moderate", "low" }), null) {
                selected = 0,
                tooltip_text = "Filter by confidence scale"
            };
            conf_dropdown.notify["selected"].connect (() => refresh ());
            filter_bar.append (conf_dropdown);

            sdv_dropdown = new Gtk.DropDown (new Gtk.StringList ({ "All SDV", "Verified", "Hash Mismatch", "Unverified" }), null) {
                selected = 0,
                tooltip_text = "Filter by CRA Source Data Verification (SHA-256) status"
            };
            sdv_dropdown.notify["selected"].connect (() => refresh ());
            filter_bar.append (sdv_dropdown);

            clear_graph_filter_btn = new Gtk.Button.with_label ("Clear Node Filter") {
                visible = false,
                tooltip_text = "Clear active Cytoscape / Graph selection filter"
            };
            clear_graph_filter_btn.add_css_class ("flat");
            clear_graph_filter_btn.clicked.connect (() => {
                service.set_graph_node_filter (null);
            });
            filter_bar.append (clear_graph_filter_btn);

            filter_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            summary_label = new Gtk.Label ("0 cells") {
                css_classes = { "caption", "numeric", "dim-label" }
            };
            filter_bar.append (summary_label);

            var btn_quarto = new Gtk.Button.with_label ("Insert Quarto Table") {
                tooltip_text = "Insert active Evidence Matrix as a captioned Quarto Markdown table"
            };
            btn_quarto.add_css_class ("flat");
            btn_quarto.clicked.connect (() => {
                string md = QualWorkspaceService.format_as_quarto_table (current_rows);
                insert_quarto_table_requested (md);
            });
            filter_bar.append (btn_quarto);

            var btn_csv = new Gtk.Button.with_label ("Export CSV/TSV") {
                tooltip_text = "Export Evidence Matrix to CSV or TSV file"
            };
            btn_csv.add_css_class ("flat");
            btn_csv.clicked.connect (prompt_export_delimited);
            filter_bar.append (btn_csv);

            this.append (filter_bar);

            // Virtualized Gtk.ColumnView
            row_store = new GLib.ListStore (typeof (EvidenceMatrixRow));
            selection_model = new Gtk.SingleSelection (row_store);
            column_view = new Gtk.ColumnView (selection_model) {
                show_row_separators = true,
                show_column_separators = true,
                vexpand = true,
                hexpand = true
            };

            add_text_column ("Entity", 150, false, (r) => r.entity_label);
            add_text_column ("Code", 160, false, (r) => @"$(r.code_label) [$(r.code_id)]");
            add_text_column ("Spans", 68, false, (r) => r.span_count.to_string (), true);
            add_text_column ("Coder(s)", 110, false, (r) => r.coders_summary);
            add_text_column ("Confidence", 90, false, (r) => r.top_confidence);
            add_text_column ("SDV (SHA-256)", 115, false, (r) => r.sdv_summary);
            add_text_column ("Representative Evidence Excerpt", 240, true, (r) => r.sample_excerpt);

            column_view.activate.connect ((pos) => {
                var r = row_store.get_item (pos) as EvidenceMatrixRow;
                if (r != null) {
                    jump_to_span_requested (r.first_file_path, r.first_line, r.first_span_id);
                }
            });

            var scroller = new Gtk.ScrolledWindow () {
                child = column_view,
                vexpand = true,
                hexpand = true
            };
            this.append (scroller);
        }

        private delegate string RowFieldGetter (EvidenceMatrixRow row);

        private void add_text_column (string title, int fixed_w, bool expand, owned RowFieldGetter getter, bool numeric = false) {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((obj) => {
                var li = (Gtk.ListItem) obj;
                var lbl = new Gtk.Label ("") {
                    xalign = numeric ? 1.0f : 0.0f,
                    ellipsize = Pango.EllipsizeMode.END,
                    margin_start = 6,
                    margin_end = 6,
                    margin_top = 4,
                    margin_bottom = 4
                };
                if (numeric) lbl.add_css_class ("numeric");
                li.set_child (lbl);
            });
            factory.bind.connect ((obj) => {
                var li = (Gtk.ListItem) obj;
                var row = li.get_item () as EvidenceMatrixRow;
                var lbl = li.get_child () as Gtk.Label;
                if (row != null && lbl != null) {
                    string val = getter (row);
                    lbl.label = val;
                    lbl.tooltip_text = val;
                }
            });
            var col = new Gtk.ColumnViewColumn (title, factory) {
                resizable = true,
                expand = expand
            };
            if (!expand) col.fixed_width = fixed_w;
            column_view.append_column (col);
        }

        public void refresh () {
            coder_filter_entry.sensitive = !service.blinded_mode;
            clear_graph_filter_btn.visible = (service.selected_graph_nodes.size > 0);

            string? f_coder = coder_filter_entry.text.strip ();
            if (f_coder == "") f_coder = null;

            string? f_conf = null;
            if (conf_dropdown.selected > 0) {
                var so = conf_dropdown.selected_item as Gtk.StringObject;
                if (so != null) f_conf = so.string;
            }

            string? f_sdv = null;
            if (sdv_dropdown.selected > 0) {
                var so = sdv_dropdown.selected_item as Gtk.StringObject;
                if (so != null) f_sdv = so.string;
            }

            var open_buffers = new Gee.HashMap<string, string> ();
            if (parent_window != null) {
                var doc = parent_window.get_active_document ();
                if (doc != null && doc.file_location != null && doc.file_location.get_path () != null) {
                    open_buffers.set (doc.file_location.get_path (), doc.get_clean_source_text ());
                }
            }

            var all_rows = service.build_matrix_rows (f_coder, f_conf, f_sdv, open_buffers);
            current_rows.clear ();
            row_store.remove_all ();

            int total_spans = 0;
            foreach (var r in all_rows) {
                if (code_filter != null && code_filter != "" && r.code_id != code_filter) {
                    continue;
                }
                current_rows.add (r);
                row_store.append (r);
                total_spans += r.span_count;
            }
            summary_label.label = @"$(current_rows.size) matrix cells · $(total_spans) spans";
        }

        private void prompt_export_delimited () {
            var dlg = new Gtk.FileDialog () {
                title = "Export Evidence Matrix (CSV / TSV)",
                initial_name = "qualitative_evidence_matrix.csv"
            };
            dlg.save.begin (parent_window, null, (obj, res) => {
                try {
                    var file = dlg.save.end (res);
                    if (file != null && file.get_path () != null) {
                        string path = file.get_path ();
                        char sep = path.down ().has_suffix (".tsv") ? '\t' : ',';
                        string data = QualWorkspaceService.format_as_delimited (current_rows, sep);
                        GLib.FileUtils.set_contents (path, data);
                        if (parent_window != null) {
                            parent_window.show_toast (@"Exported $(current_rows.size) matrix rows to $(GLib.Path.get_basename (path))");
                        }
                    }
                } catch (GLib.Error e) {}
            });
        }
    }
}
