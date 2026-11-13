// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: AlphaFold Protein Structure Database (AFDB) bridge and
 * macromolecular pLDDT confidence visualization popover.
 *
 * Architectural Position:
 * Popover inspector attached to the main window header bar.
 * Upstream caller: Imladris.Window.
 * Downstream dependencies: libsoup-3.0, json-glib-1.0, GTK4, Libadwaita, Cairo.
 *
 * Concurrency Constraints:
 * Executes asynchronous REST requests via Soup.Session on the GLib MainContext thread.
 * Renders Cairo confidence tracks without dynamic memory allocations during draw passes.
 */

using GLib;
using Gtk;
using Adw;
using Soup;
using Json;

namespace Imladris.Bridges.Taniquetil {

    public errordomain TaniquetilError {
        NETWORK_ERROR,
        STRUCTURE_NOT_FOUND,
        PARSE_ERROR
    }

    public class AlphaFoldBridgePopover : Gtk.Popover {

        public signal void insert_snippet_requested (string qmd_snippet);

        private Soup.Session http_session;
        private GLib.Cancellable? active_cancellable = null;

        // UI Components
        private Gtk.SearchEntry accession_entry;
        private Gtk.Button btn_resolve;
        private Gtk.Spinner resolve_spinner;
        private Gtk.Label status_label;

        private Adw.ActionRow row_entry_id;
        private Adw.ActionRow row_protein;
        private Adw.ActionRow row_organism;
        private Adw.ActionRow row_length;
        private Adw.ActionRow row_mean_plddt;

        private Gtk.DrawingArea plddt_bar;
        private Gtk.Label plddt_legend_label;

        private Gtk.Box action_box;
        private Gtk.Button btn_inject_badge;
        private Gtk.Button btn_inject_r;
        private Gtk.Button btn_inject_py;

        // Resolved Structural Metadata
        private string entry_id = "";
        private string uniprot_acc = "";
        private string uniprot_id = "";
        private string gene_symbol = "";
        private string organism_name = "";
        private int64 seq_length = 0;
        private double global_plddt = 0.0;
        private double fraction_very_high = 0.0;
        private double fraction_confident = 0.0;
        private double fraction_low = 0.0;
        private double fraction_very_low = 0.0;
        private string pdb_url = "";
        private string cif_url = "";
        private string pae_doc_url = "";
        private int64 latest_version = 4;

        public AlphaFoldBridgePopover () {
            GLib.Object ();
            this.has_arrow = true;
            this.autohide = true;

            this.http_session = new Soup.Session () {
                timeout = 20,
                user_agent = "Imladris-Workbench/1.0 (Taniquetil AlphaFold Bridge; Linux)"
            };

            setup_ui ();
        }

        private void setup_ui () {
            var root_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10) {
                margin_top = 14,
                margin_bottom = 14,
                margin_start = 14,
                margin_end = 14,
                width_request = 400
            };

            // Header Title
            var title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var title_icon = new Gtk.Image.from_icon_name ("applications-science-symbolic");
            var title_lbl = new Gtk.Label ("AlphaFold Structural Inspector") {
                css_classes = { "heading" },
                xalign = 0
            };
            title_box.append (title_icon);
            title_box.append (title_lbl);
            root_box.append (title_box);

            var desc_lbl = new Gtk.Label ("Inspect 3D structure predictions, pLDDT metrics, and PAE matrices.") {
                css_classes = { "caption", "dim-label" },
                wrap = true,
                xalign = 0
            };
            root_box.append (desc_lbl);

            // Search Bar
            var search_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            accession_entry = new Gtk.SearchEntry () {
                placeholder_text = "e.g., P04637, P53_HUMAN, or BRCA1",
                hexpand = true
            };
            accession_entry.activate.connect (on_resolve_clicked);

            btn_resolve = new Gtk.Button.with_label ("Fetch");
            btn_resolve.add_css_class ("suggested-action");
            btn_resolve.clicked.connect (on_resolve_clicked);

            resolve_spinner = new Gtk.Spinner () {
                spinning = false,
                visible = false
            };

            search_box.append (accession_entry);
            search_box.append (btn_resolve);
            search_box.append (resolve_spinner);
            root_box.append (search_box);

            status_label = new Gtk.Label ("") {
                css_classes = { "caption" },
                wrap = true,
                xalign = 0,
                visible = false
            };
            root_box.append (status_label);

            // Metadata Group
            var meta_group = new Adw.PreferencesGroup () {
                title = "Prediction Metadata"
            };

            row_entry_id = new Adw.ActionRow () { title = "Model ID", subtitle = "—" };
            row_entry_id.add_css_class ("property");
            meta_group.add (row_entry_id);

            row_protein = new Adw.ActionRow () { title = "Protein / Gene", subtitle = "—" };
            row_protein.add_css_class ("property");
            meta_group.add (row_protein);

            row_organism = new Adw.ActionRow () { title = "Organism", subtitle = "—" };
            row_organism.add_css_class ("property");
            meta_group.add (row_organism);

            row_length = new Adw.ActionRow () { title = "Sequence Length", subtitle = "—" };
            row_length.add_css_class ("property");
            meta_group.add (row_length);

            row_mean_plddt = new Adw.ActionRow () { title = "Mean pLDDT", subtitle = "—" };
            row_mean_plddt.add_css_class ("property");
            meta_group.add (row_mean_plddt);

            root_box.append (meta_group);

            // Cairo pLDDT Confidence Track
            var plddt_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var plddt_title = new Gtk.Label ("Per-Residue Confidence Distribution") {
                css_classes = { "caption", "heading" },
                xalign = 0
            };
            plddt_box.append (plddt_title);

            plddt_bar = new Gtk.DrawingArea () {
                content_width = 380,
                content_height = 20,
                hexpand = true
            };
            plddt_bar.set_draw_func (draw_plddt_bar);
            plddt_box.append (plddt_bar);

            plddt_legend_label = new Gtk.Label ("■ >90 (Very High)  ■ 70-90 (Confident)  ■ 50-70 (Low)  ■ <50 (Disordered)") {
                css_classes = { "caption", "dim-label" },
                xalign = 0
            };
            plddt_box.append (plddt_legend_label);
            root_box.append (plddt_box);

            // Action Buttons
            action_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 6,
                sensitive = false
            };

            btn_inject_badge = new Gtk.Button.with_label ("+ Citation");
            btn_inject_badge.tooltip_text = "Insert Markdown structural provenance badge";
            btn_inject_badge.clicked.connect (inject_markdown_badge);

            btn_inject_r = new Gtk.Button.with_label ("+ R Bio3D");
            btn_inject_r.tooltip_text = "Insert R Bio3D coordinate & pLDDT loader";
            btn_inject_r.clicked.connect (inject_r_chunk);

            btn_inject_py = new Gtk.Button.with_label ("+ Py Structure");
            btn_inject_py.tooltip_text = "Insert Python structure and PAE matrix loader";
            btn_inject_py.clicked.connect (inject_python_chunk);

            action_box.append (btn_inject_badge);
            action_box.append (btn_inject_r);
            action_box.append (btn_inject_py);
            root_box.append (action_box);

            this.set_child (root_box);
        }

        private void draw_plddt_bar (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            // Draw background track
            cr.save ();
            cr.set_source_rgb (0.2, 0.2, 0.2);
            cr.rectangle (0, 0, width, height);
            cr.fill ();

            if (global_plddt > 0.0) {
                double w_vh = width * fraction_very_high;
                double w_c = width * fraction_confident;
                double w_l = width * fraction_low;
                double w_vl = width * fraction_very_low;

                double cur_x = 0.0;

                // 1. Very High: #0053D6
                cr.set_source_rgb (0.0, 0.325, 0.839);
                cr.rectangle (cur_x, 0, w_vh, height);
                cr.fill ();
                cur_x += w_vh;

                // 2. Confident: #65CBF3
                cr.set_source_rgb (0.396, 0.796, 0.953);
                cr.rectangle (cur_x, 0, w_c, height);
                cr.fill ();
                cur_x += w_c;

                // 3. Low: #FFDB13
                cr.set_source_rgb (1.0, 0.859, 0.075);
                cr.rectangle (cur_x, 0, w_l, height);
                cr.fill ();
                cur_x += w_l;

                // 4. Very Low: #FF7D45
                cr.set_source_rgb (1.0, 0.490, 0.271);
                cr.rectangle (cur_x, 0, w_vl, height);
                cr.fill ();
            }
            cr.restore ();
        }

        private void on_resolve_clicked () {
            string raw_query = accession_entry.text.strip ();
            if (raw_query.length == 0) return;

            if (active_cancellable != null) {
                active_cancellable.cancel ();
            }
            active_cancellable = new GLib.Cancellable ();

            resolve_spinner.visible = true;
            resolve_spinner.spinning = true;
            btn_resolve.sensitive = false;
            status_label.visible = false;
            action_box.sensitive = false;

            resolve_alphafold_model.begin (raw_query, active_cancellable);
        }

        private async void resolve_alphafold_model (string query, GLib.Cancellable cancellable) {
            try {
                string url = @"https://alphafold.ebi.ac.uk/api/prediction/$query";
                var msg = new Soup.Message ("GET", url);
                msg.request_headers.append ("Accept", "application/json");

                var bytes = yield http_session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
                uint status = msg.status_code;

                if (status == 404) {
                    throw new TaniquetilError.STRUCTURE_NOT_FOUND (@"No AlphaFold prediction found for '$query'.");
                }
                if (status < 200 || status >= 300) {
                    throw new TaniquetilError.NETWORK_ERROR (@"Server error (HTTP $status).");
                }

                string json_text = Core.PlatformUtils.bytes_to_string (bytes);
                var parser = new Json.Parser ();
                parser.load_from_data (json_text, -1);

                var root_node = parser.get_root ();
                if (root_node == null || root_node.get_node_type () != Json.NodeType.ARRAY) {
                    throw new TaniquetilError.PARSE_ERROR ("Invalid JSON response from AlphaFold DB.");
                }

                var array = root_node.get_array ();
                if (array.get_length () == 0) {
                    throw new TaniquetilError.STRUCTURE_NOT_FOUND ("No prediction records in array.");
                }

                var pred = array.get_object_element (0);
                this.entry_id = pred.has_member ("entryId") ? pred.get_string_member ("entryId") : query;
                this.uniprot_acc = pred.has_member ("uniprotAccession") ? pred.get_string_member ("uniprotAccession") : query;
                this.uniprot_id = pred.has_member ("uniprotId") ? pred.get_string_member ("uniprotId") : "";
                this.gene_symbol = pred.has_member ("gene") ? pred.get_string_member ("gene") : "";
                this.organism_name = pred.has_member ("organismScientificName") ? pred.get_string_member ("organismScientificName") : "Unknown";
                this.seq_length = pred.has_member ("uniprotEnd") ? pred.get_int_member ("uniprotEnd") : 0;
                this.global_plddt = pred.has_member ("globalMetricValue") ? pred.get_double_member ("globalMetricValue") : 0.0;
                this.fraction_very_high = pred.has_member ("fractionPlddtVeryHigh") ? pred.get_double_member ("fractionPlddtVeryHigh") : 0.0;
                this.fraction_confident = pred.has_member ("fractionPlddtConfident") ? pred.get_double_member ("fractionPlddtConfident") : 0.0;
                this.fraction_low = pred.has_member ("fractionPlddtLow") ? pred.get_double_member ("fractionPlddtLow") : 0.0;
                this.fraction_very_low = pred.has_member ("fractionPlddtVeryLow") ? pred.get_double_member ("fractionPlddtVeryLow") : 0.0;
                this.pdb_url = pred.has_member ("pdbUrl") ? pred.get_string_member ("pdbUrl") : "";
                this.cif_url = pred.has_member ("cifUrl") ? pred.get_string_member ("cifUrl") : "";
                this.pae_doc_url = pred.has_member ("paeDocUrl") ? pred.get_string_member ("paeDocUrl") : "";
                this.latest_version = pred.has_member ("latestVersion") ? pred.get_int_member ("latestVersion") : 4;

                // Update UI Labels
                row_entry_id.subtitle = this.entry_id;
                row_protein.subtitle = @"$(this.gene_symbol != "" ? this.gene_symbol : this.uniprot_id) ($(this.uniprot_acc))";
                row_organism.subtitle = this.organism_name;
                row_length.subtitle = @"$(this.seq_length) residues";
                row_mean_plddt.subtitle = @"%.1f / 100".printf (this.global_plddt);

                plddt_bar.queue_draw ();
                action_box.sensitive = true;

                status_label.label = "✔ AlphaFold structure resolved successfully.";
                status_label.remove_css_class ("error");
                status_label.visible = true;

            } catch (GLib.Error e) {
                status_label.label = @"✖ Error: $(e.message)";
                status_label.add_css_class ("error");
                status_label.visible = true;
            } finally {
                resolve_spinner.spinning = false;
                resolve_spinner.visible = false;
                btn_resolve.sensitive = true;
                active_cancellable = null;
            }
        }

        private void inject_markdown_badge () {
            string today = new GLib.DateTime.now_local ().format ("%Y-%m-%d");
            double vh_pct = fraction_very_high * 100.0;
            string snippet = "[**%s** (%s / UniProt:%s | %lld aa | Mean pLDDT: %.1f | Very High: %.1f%% | Verified: %s)](https://alphafold.ebi.ac.uk/entry/%s)\n".printf (
                entry_id,
                gene_symbol != "" ? gene_symbol : uniprot_id,
                uniprot_acc,
                seq_length,
                global_plddt,
                vh_pct,
                today,
                uniprot_acc
            );
            insert_snippet_requested (snippet);
            this.popdown ();
        }

        private void inject_r_chunk () {
            string chunk = """
```{r taniquetil-%s, message=FALSE}
# TANIQUETIL ALPHAFOLD PROVENANCE: %s (%s | Mean pLDDT: %.1f)
af_pdb_url <- "%s"
af_pae_url <- "%s"
af_pdb_file <- tempfile(fileext = ".pdb")
utils::download.file(af_pdb_url, af_pdb_file, quiet = TRUE)
pdb_model <- bio3d::read.pdb(af_pdb_file)
# Extract per-residue pLDDT stored in B-factor column
plddt_scores <- pdb_model$atom[pdb_model$calpha, "b"]
summary(plddt_scores)
```
""".printf (entry_id.replace ("-", "_"), entry_id, gene_symbol, global_plddt, pdb_url, pae_doc_url);

            insert_snippet_requested (chunk);
            this.popdown ();
        }

        private void inject_python_chunk () {
            string chunk = """
```{python taniquetil-%s}
# TANIQUETIL ALPHAFOLD PROVENANCE: %s (%s | Mean pLDDT: %.1f)
import requests
af_cif_url = "%s"
af_pae_url = "%s"
pae_resp = requests.get(af_pae_url, timeout=15)
pae_resp.raise_for_status()
pae_data = pae_resp.json()
print(f"Loaded %s: mean pLDDT = %.1f (%lld residues)")
```
""".printf (entry_id.replace ("-", "_"), entry_id, gene_symbol, global_plddt, cif_url, pae_doc_url, entry_id, global_plddt, seq_length);

            insert_snippet_requested (chunk);
            this.popdown ();
        }
    }
}
