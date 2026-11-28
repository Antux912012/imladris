// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Qual;

namespace Imladris.UI.Qual {

    /**
     * Biostatistical Qualitative Dashboard (Adw.Dialog):
     * Displays Cohen's Kappa, Krippendorff's Alpha, Coder Adjudication Diffs,
     * Fisher's Exact / Chi-Square Co-Occurrence Enrichment, Thematic Saturation Curve (Cairo),
     * and one-click Quarto statistical summary block insertion.
     */
    public class BiostatDashboard : Adw.Dialog {
        private QualWorkspaceService service;
        private unowned Window? parent_window;

        private Adw.ActionRow row_cohen;
        private Adw.ActionRow row_fleiss;
        private Adw.ActionRow row_kripp;
        private Gtk.ListBox diffs_list;
        private Gtk.ListBox enrichment_list;
        private Gtk.DrawingArea saturation_canvas;

        private IrrResult last_cohen;
        private IrrResult last_fleiss;
        private IrrResult last_kripp;
        private Gee.ArrayList<EnrichmentResult> last_enrichments;
        private Gee.ArrayList<SaturationPoint> last_saturation;

        public signal void insert_summary_requested (string quarto_markdown);

        public BiostatDashboard (QualWorkspaceService svc, Window? win = null) {
            Object (
                title: "Qualitative Biostatistics & Adjudication",
                content_width: 820,
                content_height: 620
            );
            this.service = svc;
            this.parent_window = win;
            this.last_enrichments = new Gee.ArrayList<EnrichmentResult> ();
            this.last_saturation = new Gee.ArrayList<SaturationPoint> ();

            build_ui ();
            recalculate ();
        }

        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();

            var stack = new Adw.ViewStack ();
            var switcher = new Adw.ViewSwitcher () {
                stack = stack,
                policy = Adw.ViewSwitcherPolicy.WIDE
            };
            header.set_title_widget (switcher);

            var btn_insert = new Gtk.Button.with_label ("Insert Quarto Summary") {
                tooltip_text = "Insert IRR & Fisher's Exact enrichment tables into active document"
            };
            btn_insert.add_css_class ("suggested-action");
            btn_insert.clicked.connect (() => {
                if (last_cohen != null && last_kripp != null) {
                    string block = QualStatsEngine.format_quarto_summary_block (last_cohen, last_kripp, last_enrichments, last_fleiss);
                    insert_summary_requested (block);
                    this.close ();
                }
            });
            header.pack_end (btn_insert);

            var btn_r_script = new Gtk.Button.from_icon_name ("utilities-terminal-symbolic") {
                tooltip_text = "Provision & Insert .imladris/scripts/qual_stats.R verification chunk"
            };
            btn_r_script.add_css_class ("flat");
            btn_r_script.clicked.connect (() => {
                string r_path = QualStatsEngine.ensure_workspace_r_script (service.workspace_dir);
                string chunk = "\n```{r qual-stats-verify}\nsource(\"" + r_path.replace ("\\", "/") + "\")\n```\n";
                insert_summary_requested (chunk);
                this.close ();
            });
            header.pack_end (btn_r_script);

            toolbar_view.add_top_bar (header);

            stack.add_titled_with_icon (build_irr_and_diffs_page (), "irr", "IRR & Adjudication", "object-select-symbolic");
            stack.add_titled_with_icon (build_enrichment_page (), "enrichment", "Co-Occurrence & Fisher", "view-statistics-symbolic");
            stack.add_titled_with_icon (build_saturation_page (), "saturation", "Thematic Saturation", "x-office-presentation-symbolic");

            toolbar_view.set_content (stack);
            this.set_child (toolbar_view);
        }

        private Gtk.Widget build_irr_and_diffs_page () {
            var page = new Adw.PreferencesPage ();

            var irr_group = new Adw.PreferencesGroup () {
                title = "Inter-Rater Reliability (IRR)",
                description = "Computed across overlapping document spans across independent coders."
            };
            row_cohen = new Adw.ActionRow () { title = "Cohen's Kappa (κ)" };
            row_cohen.add_css_class ("property");
            row_fleiss = new Adw.ActionRow () { title = "Fleiss' Kappa (κ_F)" };
            row_fleiss.add_css_class ("property");
            row_kripp = new Adw.ActionRow () { title = "Krippendorff's Alpha (α)" };
            row_kripp.add_css_class ("property");
            irr_group.add (row_cohen);
            irr_group.add (row_fleiss);
            irr_group.add (row_kripp);
            page.add (irr_group);

            var diff_group = new Adw.PreferencesGroup () {
                title = "Dual-Coder Adjudication Comparison",
                description = "Overlapping spans comparing independent coder assignments."
            };
            diffs_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "boxed-list" }
            };
            diff_group.add (diffs_list);
            page.add (diff_group);

            return page;
        }

        private Gtk.Widget build_enrichment_page () {
            var page = new Adw.PreferencesPage ();
            var grp = new Adw.PreferencesGroup () {
                title = "Code Co-Occurrence & Exact Enrichment",
                description = "Two-sided Fisher's Exact Test and Pearson's χ² test across document/entity units."
            };
            enrichment_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "boxed-list" }
            };
            grp.add (enrichment_list);
            page.add (grp);
            return page;
        }

        private Gtk.Widget build_saturation_page () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 16,
                margin_bottom = 16,
                margin_start = 20,
                margin_end = 20,
                vexpand = true,
                hexpand = true
            };
            var desc = new Gtk.Label ("Cumulative unique qualitative codes discovered across sequential workspace documents (stopping criterion when Δcodes = 0).") {
                xalign = 0,
                wrap = true,
                css_classes = { "dim-label" }
            };
            box.append (desc);

            saturation_canvas = new Gtk.DrawingArea () {
                vexpand = true,
                hexpand = true,
                content_height = 320
            };
            saturation_canvas.set_draw_func (draw_saturation_curve);
            box.append (saturation_canvas);
            return box;
        }

        public void recalculate () {
            var all_spans = service.db != null ? service.db.list_spans () : new Gee.ArrayList<QualSpan> ();
            Gee.ArrayList<AdjudicationDiff> diffs;
            QualStatsEngine.analyze_workspace_irr (all_spans, out last_cohen, out last_kripp, out diffs);
            last_fleiss = QualStatsEngine.compute_workspace_fleiss_kappa (all_spans);

            row_cohen.subtitle = @"κ = %.4f · Po = %.3f · Pe = %.3f · N = $(last_cohen.n_units) · p = %.3g ($(last_cohen.interpretation))".printf (
                last_cohen.statistic, last_cohen.observed_agreement, last_cohen.expected_agreement, last_cohen.p_value
            );
            row_fleiss.subtitle = @"κ_F = %.4f · Raters = $(last_fleiss.n_raters) · Units = $(last_fleiss.n_units) · p = %.3g ($(last_fleiss.interpretation))".printf (
                last_fleiss.statistic, last_fleiss.p_value
            );
            row_kripp.subtitle = @"α = %.4f · Raters = $(last_kripp.n_raters) · Units = $(last_kripp.n_units) ($(last_kripp.interpretation))".printf (
                last_kripp.statistic
            );

            clear_listbox (diffs_list);
            if (diffs.size == 0) {
                diffs_list.append (new Adw.ActionRow () {
                    title = "No dual-coded overlapping spans yet",
                    subtitle = "Have two coders annotate the same lines (or run Elrond AI Coding) to inspect agreement."
                });
            } else {
                foreach (var d in diffs) {
                    string badge = d.agreed ? "Agreed" : "Discrepancy";
                    var r = new Adw.ActionRow () {
                        title = @"$(GLib.Path.get_basename (d.file_path)):L$(d.line_start) — $(d.coder_a): $(d.code_a) vs $(d.coder_b): $(d.code_b)",
                        subtitle = d.excerpt,
                        use_markup = false
                    };
                    var pill = new Gtk.Label (badge) {
                        valign = Gtk.Align.CENTER,
                        css_classes = { "caption", d.agreed ? "success" : "warning" }
                    };
                    r.add_suffix (pill);
                    diffs_list.append (r);
                }
            }

            string[] cids;
            QualStatsEngine.compute_cooccurrence_and_enrichment (all_spans, out cids, out last_enrichments);
            clear_listbox (enrichment_list);
            if (last_enrichments.size == 0) {
                enrichment_list.append (new Adw.ActionRow () {
                    title = "Insufficient multi-code units for enrichment test",
                    subtitle = "Apply at least two distinct codes across multiple entities or sections."
                });
            } else {
                foreach (var e in last_enrichments) {
                    string or_s = (e.odds_ratio.is_infinity () != 0) ? "∞" : "%.2f".printf (e.odds_ratio);
                    var r = new Adw.ActionRow () {
                        title = @"$(e.code_a) × $(e.code_b)",
                        subtitle = @"Co-occurs: $(e.a_both) | Odds Ratio: $or_s | Fisher p = %.4g | χ² = %.3f (p = %.4g)".printf (
                            e.fisher_p_two_sided, e.chi2_stat, e.chi2_p_value
                        ),
                        use_markup = false
                    };
                    enrichment_list.append (r);
                }
            }

            last_saturation = QualStatsEngine.compute_thematic_saturation (all_spans);
            saturation_canvas.queue_draw ();
        }

        private static void clear_listbox (Gtk.ListBox lb) {
            var ch = lb.get_first_child ();
            while (ch != null) {
                var nx = ch.get_next_sibling ();
                lb.remove (ch);
                ch = nx;
            }
        }

        private void draw_saturation_curve (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            bool dark = Adw.StyleManager.get_default ().dark;
            if (dark) cr.set_source_rgb (0.18, 0.20, 0.25); // Nord #2E3440
            else cr.set_source_rgb (0.98, 0.98, 0.99);
            cr.paint ();

            double pad_l = 48.0, pad_r = 24.0, pad_t = 24.0, pad_b = 36.0;
            double pw = double.max (10.0, width - pad_l - pad_r);
            double ph = double.max (10.0, height - pad_t - pad_b);

            cr.set_source_rgba (dark ? 0.85 : 0.20, dark ? 0.87 : 0.24, dark ? 0.91 : 0.30, 0.35);
            cr.set_line_width (1.0);
            cr.move_to (pad_l, pad_t);
            cr.line_to (pad_l, pad_t + ph);
            cr.line_to (pad_l + pw, pad_t + ph);
            cr.stroke ();

            if (last_saturation == null || last_saturation.size == 0) {
                cr.set_source_rgba (dark ? 0.85 : 0.25, dark ? 0.87 : 0.28, dark ? 0.91 : 0.33, 0.8);
                cr.set_font_size (12.0);
                cr.move_to (pad_l + 16, pad_t + ph / 2.0);
                cr.show_text ("Index spans across one or more documents to plot thematic saturation.");
                return;
            }

            int max_y = int.max (1, last_saturation[last_saturation.size - 1].cumulative_unique_codes);
            int n = last_saturation.size;

            // Nord Frost #88C0D0 line
            cr.set_source_rgb (0.533, 0.753, 0.816);
            cr.set_line_width (2.5);
            for (int i = 0; i < n; i++) {
                double x = (n == 1) ? (pad_l + pw / 2.0) : (pad_l + ((double) i / (double) (n - 1)) * pw);
                double y = pad_t + ph * (1.0 - ((double) last_saturation[i].cumulative_unique_codes / (double) max_y));
                if (i == 0) cr.move_to (x, y);
                else cr.line_to (x, y);
            }
            cr.stroke ();

            for (int i = 0; i < n; i++) {
                var pt = last_saturation[i];
                double x = (n == 1) ? (pad_l + pw / 2.0) : (pad_l + ((double) i / (double) (n - 1)) * pw);
                double y = pad_t + ph * (1.0 - ((double) pt.cumulative_unique_codes / (double) max_y));
                // Nord Aurora Green (#A3BE8C) when saturated (0 new codes), Frost otherwise
                if (pt.new_codes_added == 0) cr.set_source_rgb (0.639, 0.745, 0.549);
                else cr.set_source_rgb (0.533, 0.753, 0.816);
                cr.arc (x, y, 4.5, 0, 2 * GLib.Math.PI);
                cr.fill ();

                cr.set_source_rgba (dark ? 0.92 : 0.15, dark ? 0.94 : 0.18, dark ? 0.96 : 0.22, 0.9);
                cr.set_font_size (10.5);
                cr.move_to (x - 10, y - 8);
                cr.show_text (@"$(pt.cumulative_unique_codes)");
            }
        }
    }
}
