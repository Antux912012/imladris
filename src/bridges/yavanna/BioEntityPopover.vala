// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Self-contained popover bridge for resolving cloud
 * bioinformatics accessions (UniProtKB & Ensembl) and calculating biophysical
 * properties for RT-qPCR oligos and primers in memory.
 *
 * Architectural Position:
 * Popover inspector attached to the main window header bar or ribbon.
 * Upstream caller: Imladris.Window.
 * Downstream dependencies: libsoup-3.0, json-glib-1.0, GTK4, Libadwaita.
 *
 * Concurrency Constraints:
 * Network queries run asynchronously via Soup.Session on the GLib MainContext thread.
 * In-memory sequence computations execute without blocking the UI frame budget.
 */

using GLib;
using Gtk;
using Adw;
using Soup;
using Json;

namespace Imladris.Bridges.Yavanna {

    public errordomain YavannaError {
        NETWORK_ERROR,
        ENTITY_NOT_FOUND,
        PARSE_ERROR,
        INVALID_SEQUENCE
    }

    public class BioEntityPopover : Gtk.Popover {

        /**
         * Emitted when the user requests injection of a Markdown snippet,
         * citation badge, oligo specification table, or R/Python code chunk.
         */
        public signal void insert_snippet_requested (string qmd_snippet);

        private Soup.Session http_session;
        private GLib.Cancellable? active_cancellable = null;

        // Tab 1: Cloud Bio-Accession Resolver state
        private Gtk.DropDown db_selector;
        private Gtk.SearchEntry accession_entry;
        private Gtk.Button btn_resolve;
        private Gtk.Spinner resolve_spinner;
        private Gtk.Label resolve_status_label;
        private Adw.ActionRow row_title;
        private Adw.ActionRow row_organism;
        private Adw.ActionRow row_spec;
        private Gtk.Box action_bar_box;
        private Gtk.Button btn_inject_md;
        private Gtk.Button btn_inject_r;
        private Gtk.Button btn_inject_py;

        // Resolved entity cache
        private string resolved_db = "";
        private string resolved_id = "";
        private string resolved_name = "";
        private string resolved_spec = "";
        private string resolved_canonical_url = "";
        private string resolved_api_url = "";

        // Tab 2: RT-qPCR Oligo Calculator state
        private Gtk.Entry oligo_entry;
        private Gtk.Label lbl_length_val;
        private Gtk.Label lbl_gc_val;
        private Gtk.Label lbl_tm_val;
        private Gtk.Label lbl_mw_val;
        private Gtk.Label lbl_rev_comp_val;
        private Gtk.Label oligo_validation_label;
        private Gtk.Button btn_inject_oligo;

        // Oligo cached metrics
        private string clean_sequence = "";
        private string reverse_complement = "";
        private int oligo_length = 0;
        private double oligo_gc_percent = 0.0;
        private double oligo_tm = 0.0;
        private double oligo_mw = 0.0;

        public BioEntityPopover () {
            GLib.Object ();
            this.http_session = new Soup.Session ();
            this.http_session.timeout = 10;
            this.http_session.user_agent = "Imladris-Scientific-Workbench/1.0";

            build_ui ();
        }

        private void build_ui () {
            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 10,
                margin_bottom = 10,
                width_request = 440
            };

            // Header Title
            var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_bottom = 4
            };
            var title_icon = new Gtk.Image.from_icon_name ("applications-science-symbolic") {
                pixel_size = 18
            };
            var title_label = new Gtk.Label ("<b>Yavanna Bio-Entity &amp; Oligo Inspector</b>") {
                use_markup = true,
                xalign = 0,
                hexpand = true
            };
            header_box.append (title_icon);
            header_box.append (title_label);
            main_box.append (header_box);

            // Notebook / ViewStack for 2 Tabs
            var view_stack = new Adw.ViewStack ();
            view_stack.add_titled (build_tab1_resolver (), "resolver", "Accession Resolver");
            view_stack.add_titled (build_tab2_oligo (), "oligo", "RT-qPCR Oligo");

            var stack_switcher = new Adw.ViewSwitcher () {
                stack = view_stack,
                policy = Adw.ViewSwitcherPolicy.WIDE,
                halign = Gtk.Align.CENTER,
                margin_bottom = 6
            };
            main_box.append (stack_switcher);
            main_box.append (view_stack);

            this.set_child (main_box);
        }

        // =====================================================================
        // TAB 1: CLOUD BIO-ACCESSION RESOLVER
        // =====================================================================
        private Gtk.Widget build_tab1_resolver () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            // DB selection row & search
            var db_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var db_model = new Gtk.StringList ({
                "UniProtKB (Protein)",
                "Ensembl (Human GRCh38 Gene)"
            });
            db_selector = new Gtk.DropDown (db_model, null) {
                selected = 0
            };
            db_selector.notify["selected"].connect (() => {
                if (db_selector.selected == 0) {
                    accession_entry.placeholder_text = "e.g., P04637 or TP53_HUMAN";
                } else {
                    accession_entry.placeholder_text = "e.g., BRCA1 or ENSG00000012048";
                }
            });
            db_box.append (db_selector);

            accession_entry = new Gtk.SearchEntry () {
                placeholder_text = "e.g., P04637 or TP53_HUMAN",
                hexpand = true
            };
            accession_entry.activate.connect (on_resolve_triggered);
            db_box.append (accession_entry);

            btn_resolve = new Gtk.Button.from_icon_name ("system-search-symbolic") {
                tooltip_text = "Resolve Accession Metadata"
            };
            btn_resolve.clicked.connect (on_resolve_triggered);
            db_box.append (btn_resolve);

            box.append (db_box);

            // Status indication
            var status_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                halign = Gtk.Align.START,
                margin_top = 2
            };
            resolve_spinner = new Gtk.Spinner () {
                spinning = false,
                visible = false
            };
            resolve_status_label = new Gtk.Label ("Enter an accession or gene symbol to resolve") {
                css_classes = { "caption", "dim-label" }
            };
            status_box.append (resolve_spinner);
            status_box.append (resolve_status_label);
            box.append (status_box);

            // Resolved Property Rows
            var result_group = new Adw.PreferencesGroup () {
                title = "Resolved Bio-Entity Properties"
            };

            row_title = new Adw.ActionRow () {
                title = "Title / Symbol",
                subtitle = "—"
            };
            row_title.add_css_class ("property");
            result_group.add (row_title);

            row_organism = new Adw.ActionRow () {
                title = "Organism and Taxon",
                subtitle = "—"
            };
            row_organism.add_css_class ("property");
            result_group.add (row_organism);

            row_spec = new Adw.ActionRow () {
                title = "Coordinates / Spec",
                subtitle = "—"
            };
            row_spec.add_css_class ("property");
            result_group.add (row_spec);

            box.append (result_group);

            // Action Injection Bar
            action_bar_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                halign = Gtk.Align.END,
                margin_top = 6
            };

            btn_inject_md = new Gtk.Button.with_label ("+ Markdown Provenance") {
                sensitive = false,
                css_classes = { "pill-button" }
            };
            btn_inject_md.clicked.connect (on_inject_md_clicked);
            action_bar_box.append (btn_inject_md);

            btn_inject_r = new Gtk.Button.with_label ("+ R Chunk") {
                sensitive = false,
                css_classes = { "pill-button" }
            };
            btn_inject_r.clicked.connect (on_inject_r_clicked);
            action_bar_box.append (btn_inject_r);

            btn_inject_py = new Gtk.Button.with_label ("+ Py Chunk") {
                sensitive = false,
                css_classes = { "pill-button" }
            };
            btn_inject_py.clicked.connect (on_inject_py_clicked);
            action_bar_box.append (btn_inject_py);

            box.append (action_bar_box);
            return box;
        }

        private void on_resolve_triggered () {
            string query = accession_entry.text.strip ();
            if (query.length == 0) return;

            if (active_cancellable != null) {
                active_cancellable.cancel ();
            }
            active_cancellable = new GLib.Cancellable ();

            resolve_spinner.visible = true;
            resolve_spinner.spinning = true;
            btn_resolve.sensitive = false;
            resolve_status_label.label = @"Querying $(db_selector.selected == 0 ? "UniProtKB" : "Ensembl")...";

            if (db_selector.selected == 0) {
                resolve_uniprot_async.begin (query, active_cancellable);
            } else {
                resolve_ensembl_async.begin (query, active_cancellable);
            }
        }

        private async void resolve_uniprot_async (string accession, GLib.Cancellable cancellable) {
            string clean_acc = accession.strip ().up ();
            string url = @"https://rest.uniprot.org/uniprotkb/$clean_acc.json";
            var msg = new Soup.Message ("GET", url);
            msg.request_headers.append ("Accept", "application/json");

            try {
                var bytes = yield http_session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
                if (msg.status_code != 200) {
                    string search_url = @"https://rest.uniprot.org/uniprotkb/search?query=$(GLib.Uri.escape_string (clean_acc, null, false))&size=1";
                    var smsg = new Soup.Message ("GET", search_url);
                    smsg.request_headers.append ("Accept", "application/json");
                    var sbytes = yield http_session.send_and_read_async (smsg, GLib.Priority.DEFAULT, cancellable);
                    if (smsg.status_code == 200 && sbytes != null) {
                        var sp = new Json.Parser ();
                        sp.load_from_data (Core.PlatformUtils.bytes_to_string (sbytes), -1);
                        var sroot = sp.get_root ();
                        if (sroot != null && sroot.get_node_type () == Json.NodeType.OBJECT) {
                            var sobj = sroot.get_object ();
                            if (sobj.has_member ("results") && sobj.get_array_member ("results").get_length () > 0) {
                                var first_hit = sobj.get_array_member ("results").get_object_element (0);
                                if (first_hit.has_member ("primaryAccession")) {
                                    clean_acc = first_hit.get_string_member ("primaryAccession");
                                    url = @"https://rest.uniprot.org/uniprotkb/$clean_acc.json";
                                    msg = new Soup.Message ("GET", url);
                                    msg.request_headers.append ("Accept", "application/json");
                                    bytes = yield http_session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
                                }
                            }
                        }
                    }
                }
                if (msg.status_code != 200) {
                    throw new YavannaError.ENTITY_NOT_FOUND (@"UniProt returned HTTP $(msg.status_code)");
                }

                string json_text = Core.PlatformUtils.bytes_to_string (bytes);
                var parser = new Json.Parser ();
                parser.load_from_data (json_text);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    throw new YavannaError.PARSE_ERROR ("Invalid JSON payload from UniProt");
                }
                var obj = root.get_object ();

                string prim_acc = obj.has_member ("primaryAccession") ? obj.get_string_member ("primaryAccession") : accession;

                string full_name = "Protein";
                if (obj.has_member ("proteinDescription")) {
                    var pd = obj.get_object_member ("proteinDescription");
                    if (pd.has_member ("recommendedName")) {
                        var rn = pd.get_object_member ("recommendedName");
                        if (rn.has_member ("fullName")) {
                            var fn = rn.get_object_member ("fullName");
                            if (fn.has_member ("value")) {
                                full_name = fn.get_string_member ("value");
                            }
                        }
                    }
                }

                string org_name = "Homo sapiens";
                int64 taxon_id = 9606;
                if (obj.has_member ("organism")) {
                    var org = obj.get_object_member ("organism");
                    if (org.has_member ("scientificName")) {
                        org_name = org.get_string_member ("scientificName");
                    }
                    if (org.has_member ("taxonId")) {
                        taxon_id = org.get_int_member ("taxonId");
                    }
                }

                int64 seq_len = 0;
                int64 mol_wt = 0;
                if (obj.has_member ("sequence")) {
                    var seq = obj.get_object_member ("sequence");
                    if (seq.has_member ("length")) seq_len = seq.get_int_member ("length");
                    if (seq.has_member ("molWeight")) mol_wt = seq.get_int_member ("molWeight");
                }

                // Cache resolved metadata
                resolved_db = "UniProtKB";
                resolved_id = prim_acc;
                resolved_name = full_name;
                resolved_spec = @"Length: $(seq_len) aa | Mass: $(mol_wt) Da";
                resolved_canonical_url = @"https://www.uniprot.org/uniprotkb/$prim_acc/entry";
                resolved_api_url = url;

                // Update UI rows
                row_title.subtitle = @"$full_name ($prim_acc)";
                row_organism.subtitle = @"$org_name (Taxon ID: $taxon_id)";
                row_spec.subtitle = resolved_spec;

                resolve_status_label.label = "✔ Successfully resolved from UniProtKB";
                btn_inject_md.sensitive = true;
                btn_inject_r.sensitive = true;
                btn_inject_py.sensitive = true;
            } catch (GLib.Error e) {
                if (!(e is GLib.IOError.CANCELLED)) {
                    resolve_status_label.label = @"✖ Error: $(e.message)";
                    clear_resolved_cache ();
                }
            } finally {
                resolve_spinner.spinning = false;
                resolve_spinner.visible = false;
                btn_resolve.sensitive = true;
            }
        }

        private async void resolve_ensembl_async (string query, GLib.Cancellable cancellable) {
            string clean_q = query.strip ();
            string url = @"https://rest.ensembl.org/lookup/symbol/homo_sapiens/$clean_q?content-type=application/json";
            if (clean_q.up ().has_prefix ("ENSG")) {
                url = @"https://rest.ensembl.org/lookup/id/$(clean_q.up ())?content-type=application/json";
            }

            var msg = new Soup.Message ("GET", url);
            msg.request_headers.append ("Accept", "application/json");

            try {
                var bytes = yield http_session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
                if (msg.status_code != 200) {
                    throw new YavannaError.ENTITY_NOT_FOUND (@"Ensembl returned HTTP $(msg.status_code)");
                }

                string json_text = Core.PlatformUtils.bytes_to_string (bytes);
                var parser = new Json.Parser ();
                parser.load_from_data (json_text);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    throw new YavannaError.PARSE_ERROR ("Invalid JSON payload from Ensembl");
                }
                var obj = root.get_object ();

                string gene_id = obj.has_member ("id") ? obj.get_string_member ("id") : query;
                string display_name = obj.has_member ("display_name") ? obj.get_string_member ("display_name") : query;
                string assembly = obj.has_member ("assembly_name") ? obj.get_string_member ("assembly_name") : "GRCh38";
                string seq_region = obj.has_member ("seq_region_name") ? obj.get_string_member ("seq_region_name") : "1";
                int64 start_pos = obj.has_member ("start") ? obj.get_int_member ("start") : 0;
                int64 end_pos = obj.has_member ("end") ? obj.get_int_member ("end") : 0;
                int64 strand = obj.has_member ("strand") ? obj.get_int_member ("strand") : 1;
                string strand_sym = (strand >= 0) ? "(+)" : "(-)";

                resolved_db = "Ensembl";
                resolved_id = gene_id;
                resolved_name = display_name;
                resolved_spec = @"Chr $seq_region:$start_pos-$end_pos $strand_sym ($assembly)";
                resolved_canonical_url = @"https://www.ensembl.org/Homo_sapiens/Gene/Summary?g=$gene_id";
                resolved_api_url = url;

                row_title.subtitle = @"$display_name ($gene_id)";
                row_organism.subtitle = "Homo sapiens (Taxon ID: 9606)";
                row_spec.subtitle = resolved_spec;

                resolve_status_label.label = "✔ Successfully resolved from Ensembl";
                btn_inject_md.sensitive = true;
                btn_inject_r.sensitive = true;
                btn_inject_py.sensitive = true;
            } catch (GLib.Error e) {
                if (!(e is GLib.IOError.CANCELLED)) {
                    resolve_status_label.label = @"✖ Error: $(e.message)";
                    clear_resolved_cache ();
                }
            } finally {
                resolve_spinner.spinning = false;
                resolve_spinner.visible = false;
                btn_resolve.sensitive = true;
            }
        }

        private void clear_resolved_cache () {
            resolved_db = "";
            resolved_id = "";
            resolved_name = "";
            resolved_spec = "";
            resolved_canonical_url = "";
            resolved_api_url = "";
            row_title.subtitle = "—";
            row_organism.subtitle = "—";
            row_spec.subtitle = "—";
            btn_inject_md.sensitive = false;
            btn_inject_r.sensitive = false;
            btn_inject_py.sensitive = false;
        }

        private void on_inject_md_clicked () {
            if (resolved_id.length == 0) return;
            string date_str = new GLib.DateTime.now_local ().format ("%Y-%m-%d");
            string snippet = @"[**$resolved_name** ($resolved_db:$resolved_id | $resolved_spec | Verified: $date_str)]($resolved_canonical_url)";
            insert_snippet_requested (snippet);
            this.popdown ();
        }

        private void on_inject_r_clicked () {
            if (resolved_id.length == 0) return;
            string clean_id = resolved_id.down ().replace ("_", "-");
            string snippet =
"""```{r yavanna-%s, message=FALSE}
# YAVANNA BIO-ENTITY PROVENANCE: %s:%s (%s)
entity_url <- "%s"
entity_json <- jsonlite::fromJSON(entity_url)
```
""".printf (clean_id, resolved_db, resolved_id, resolved_name, resolved_api_url);
            insert_snippet_requested (snippet);
            this.popdown ();
        }

        private void on_inject_py_clicked () {
            if (resolved_id.length == 0) return;
            string clean_id = resolved_id.down ().replace ("_", "-");
            string snippet =
"""```{python}
#| label: yavanna-%s
# YAVANNA BIO-ENTITY PROVENANCE: %s:%s (%s)
import requests
resp = requests.get("%s", headers={"Accept": "application/json"}, timeout=10)
resp.raise_for_status()
entity_data = resp.json()
```
""".printf (clean_id, resolved_db, resolved_id, resolved_name, resolved_api_url);
            insert_snippet_requested (snippet);
            this.popdown ();
        }

        // =====================================================================
        // TAB 2: RT-qPCR OLIGO / PRIMER CALCULATOR
        // =====================================================================
        private Gtk.Widget build_tab2_oligo () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            box.append (new Gtk.Label ("5' → 3' Primer / Oligonucleotide Sequence:") {
                xalign = 0,
                css_classes = { "caption", "dim-label" }
            });

            oligo_entry = new Gtk.Entry () {
                placeholder_text = "e.g. 5'-CCTCTGTTCCACATACAGG-3' or AGCTTCG",
                hexpand = true
            };
            oligo_entry.changed.connect (() => {
                recalculate_oligo_metrics (oligo_entry.text);
            });
            box.append (oligo_entry);

            oligo_validation_label = new Gtk.Label ("Enter forward primer sequence (5' → 3')") {
                xalign = 0,
                css_classes = { "caption", "dim-label" }
            };
            box.append (oligo_validation_label);

            // Metrics Grid
            var metrics_frame = new Gtk.Frame (null);
            var grid = new Gtk.Grid () {
                row_spacing = 6,
                column_spacing = 16,
                margin_start = 12,
                margin_end = 12,
                margin_top = 10,
                margin_bottom = 10
            };

            grid.attach (new Gtk.Label ("Length (N):") { xalign = 0, css_classes = { "dim-label" } }, 0, 0);
            lbl_length_val = new Gtk.Label ("0 nt") { xalign = 0, css_classes = { "bold" } };
            grid.attach (lbl_length_val, 1, 0);

            grid.attach (new Gtk.Label ("GC Content:") { xalign = 0, css_classes = { "dim-label" } }, 2, 0);
            lbl_gc_val = new Gtk.Label ("0.0%") { xalign = 0, css_classes = { "bold" } };
            grid.attach (lbl_gc_val, 3, 0);

            grid.attach (new Gtk.Label ("Estimated Tm (50mM Na⁺):") { xalign = 0, css_classes = { "dim-label" } }, 0, 1);
            lbl_tm_val = new Gtk.Label ("0.0 °C") { xalign = 0, css_classes = { "bold" } };
            grid.attach (lbl_tm_val, 1, 1);

            grid.attach (new Gtk.Label ("Molecular Weight:") { xalign = 0, css_classes = { "dim-label" } }, 2, 1);
            lbl_mw_val = new Gtk.Label ("0.0 Da") { xalign = 0, css_classes = { "bold" } };
            grid.attach (lbl_mw_val, 3, 1);

            grid.attach (new Gtk.Label ("Reverse Complement:") { xalign = 0, css_classes = { "dim-label" } }, 0, 2);
            lbl_rev_comp_val = new Gtk.Label ("—") {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                css_classes = { "bold", "monospace" }
            };
            grid.attach (lbl_rev_comp_val, 1, 2, 3, 1);

            metrics_frame.set_child (grid);
            box.append (metrics_frame);

            btn_inject_oligo = new Gtk.Button.with_label ("+ Insert Oligo Table") {
                sensitive = false,
                halign = Gtk.Align.END,
                css_classes = { "pill-button", "suggested-action" },
                margin_top = 4
            };
            btn_inject_oligo.clicked.connect (on_inject_oligo_clicked);
            box.append (btn_inject_oligo);

            return box;
        }

        private void recalculate_oligo_metrics (string raw_input) {
            // 1. Sanitize: uppercase, strip whitespace, quotes, dashes, and 5'/3' markers
            string clean = raw_input.up ()
                .replace ("5'", "")
                .replace ("3'", "")
                .replace ("-", "")
                .replace (" ", "")
                .replace ("\t", "")
                .replace ("\n", "")
                .replace ("\r", "");

            var valid_builder = new StringBuilder ();
            bool had_invalid = false;

            for (int i = 0; i < clean.length; i++) {
                char c = clean[i];
                if (c == 'A' || c == 'T' || c == 'G' || c == 'C' || c == 'U') {
                    valid_builder.append_c (c);
                } else {
                    had_invalid = true;
                }
            }

            clean_sequence = valid_builder.str;
            int n = clean_sequence.length;
            oligo_length = n;

            if (n == 0) {
                lbl_length_val.label = "0 nt";
                lbl_gc_val.label = "0.0%";
                lbl_tm_val.label = "0.0 °C";
                lbl_mw_val.label = "0.0 Da";
                lbl_rev_comp_val.label = "—";
                btn_inject_oligo.sensitive = false;
                oligo_validation_label.label = had_invalid ? "⚠ Invalid characters detected (allowed: A, T, G, C, U)" : "Enter forward primer sequence (5' → 3')";
                return;
            }

            // 2. Count bases
            int count_a = 0;
            int count_t = 0;
            int count_g = 0;
            int count_c = 0;

            for (int i = 0; i < n; i++) {
                char c = clean_sequence[i];
                if (c == 'A') count_a++;
                else if (c == 'T' || c == 'U') count_t++;
                else if (c == 'G') count_g++;
                else if (c == 'C') count_c++;
            }

            // 3. GC Content
            oligo_gc_percent = ((double) (count_g + count_c) / (double) n) * 100.0;

            // 4. Melting Temperature (Tm)
            if (n < 14) {
                // Wallace Rule
                oligo_tm = 2.0 * (count_a + count_t) + 4.0 * (count_g + count_c);
            } else {
                // Standard Salt-Adjusted Marmur-Doty Approximation for 50 mM Na+
                oligo_tm = 64.9 + 41.0 * (((double) (count_g + count_c) - 16.4) / (double) n);
            }

            // 5. Approximate Single-Stranded DNA Molecular Weight
            oligo_mw = ((double) count_a * 313.21) +
                       ((double) count_t * 304.20) +
                       ((double) count_g * 329.21) +
                       ((double) count_c * 289.18) - 61.96;
            if (oligo_mw < 0.0) oligo_mw = 0.0;

            // 6. 5' -> 3' Reverse Complement
            var rev_comp_sb = new StringBuilder ();
            for (int i = n - 1; i >= 0; i--) {
                char c = clean_sequence[i];
                if (c == 'A') rev_comp_sb.append_c ('T');
                else if (c == 'T' || c == 'U') rev_comp_sb.append_c ('A');
                else if (c == 'G') rev_comp_sb.append_c ('C');
                else if (c == 'C') rev_comp_sb.append_c ('G');
            }
            reverse_complement = rev_comp_sb.str;

            // Update UI Labels
            lbl_length_val.label = @"$n nt";
            lbl_gc_val.label = "%.1f%%".printf (oligo_gc_percent);
            lbl_tm_val.label = "%.1f °C".printf (oligo_tm);
            lbl_mw_val.label = "%.1f Da".printf (oligo_mw);
            lbl_rev_comp_val.label = @"5'-$reverse_complement-3'";

            btn_inject_oligo.sensitive = (n >= 4);

            if (had_invalid) {
                oligo_validation_label.label = "⚠ Stripped invalid characters. Cleaned sequence active.";
            } else if (oligo_gc_percent >= 40.0 && oligo_gc_percent <= 60.0 && oligo_tm >= 55.0 && oligo_tm <= 65.0) {
                oligo_validation_label.label = "✔ Optimal RT-qPCR parameters (40-60% GC, 55-65 °C Tm)";
            } else {
                oligo_validation_label.label = "Ready to insert oligo specification table";
            }
        }

        private void on_inject_oligo_clicked () {
            if (clean_sequence.length == 0) return;

            string table_snippet =
"""| Oligo Parameter | Specification |
| :--- | :--- |
| **Forward Sequence (5' → 3')** | `5'-%s-3'` |
| **Reverse Complement (5' → 3')** | `5'-%s-3'` |
| **Length ($N$)** | %d nt |
| **GC Content** | %.1f%% |
| **Estimated $T_m$ (50 mM Na⁺)** | %.1f °C |
| **Molecular Weight (ssDNA)** | %.1f Da |
""".printf (
                clean_sequence,
                reverse_complement,
                oligo_length,
                oligo_gc_percent,
                oligo_tm,
                oligo_mw
            );

            insert_snippet_requested (table_snippet);
            this.popdown ();
        }
    }
}
