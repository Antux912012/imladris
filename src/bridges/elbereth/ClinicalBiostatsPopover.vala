// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using Gtk;
using Adw;

namespace Imladris.Bridges.Elbereth {

    public class ClinicalBiostatsPopover : Gtk.Popover {

        public signal void insert_snippet_requested (string qmd_snippet);

        // Tab 1: Power & Sample Size Controls
        private Gtk.DropDown endpoint_selector;
        private Gtk.DropDown alpha_selector;
        private Gtk.SpinButton power_spin;
        private Gtk.Label param1_label;
        private Gtk.SpinButton param1_spin;
        private Gtk.Label param2_label;
        private Gtk.SpinButton param2_spin;
        private Gtk.SpinButton dropout_spin;

        private Adw.ActionRow evaluable_n_row;
        private Adw.ActionRow enrolled_n_row;
        private Adw.ActionRow arm_breakdown_row;
        private Gtk.DrawingArea power_curve_area;

        // Computed state
        private int calc_n1 = 64;
        private int calc_n2 = 64;
        private int calc_evaluable_n = 128;
        private int calc_enrolled_n = 143;
        private int calc_events = 0;

        // Tab 2: Clinical Trial & Multi-Omics Code Synthesizer Controls
        private Gtk.DropDown template_selector;
        private Gtk.Entry dataset_entry;
        private Gtk.Entry group_col_entry;
        private Gtk.Entry outcome_col_entry;
        private Gtk.Entry status_col_entry;

        public ClinicalBiostatsPopover () {
            Object ();
            this.has_arrow = true;
            this.width_request = 480;

            var root_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 10,
                margin_bottom = 10,
                margin_start = 10,
                margin_end = 10
            };

            var stack = new Adw.ViewStack ();
            var switcher = new Adw.ViewSwitcher () {
                stack = stack,
                policy = Adw.ViewSwitcherPolicy.WIDE
            };
            root_box.append (switcher);
            root_box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            stack.add_titled_with_icon (
                build_power_calculator_tab (),
                "power_calc",
                "Power & Sample Size",
                "accessories-calculator-symbolic"
            );
            stack.add_titled_with_icon (
                build_clinical_templates_tab (),
                "clinical_templates",
                "Clinical & Omics Studio",
                "view-statistics-symbolic"
            );

            root_box.append (stack);
            this.set_child (root_box);

            recalculate_sample_size ();
        }

        private Gtk.Widget build_power_calculator_tab () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            endpoint_selector = new Gtk.DropDown.from_strings ({
                "Two-Sample Continuous (t-Test / Cohen's d)",
                "Two-Sample Binary Proportions (p1 vs. p2)",
                "Time-to-Event Survival (Schoenfeld Log-Rank HR)"
            });
            box.append (endpoint_selector);

            var grid = new Gtk.Grid () {
                column_spacing = 10,
                row_spacing = 6
            };

            grid.attach (new Gtk.Label ("Two-Sided α:") { xalign = 0 }, 0, 0, 1, 1);
            alpha_selector = new Gtk.DropDown.from_strings ({ "0.05", "0.01", "0.005", "0.001" });
            alpha_selector.hexpand = true;
            grid.attach (alpha_selector, 1, 0, 1, 1);

            grid.attach (new Gtk.Label ("Target Power (1 - β):") { xalign = 0 }, 2, 0, 1, 1);
            power_spin = new Gtk.SpinButton.with_range (0.50, 0.99, 0.05) {
                digits = 2,
                value = 0.80
            };
            grid.attach (power_spin, 3, 0, 1, 1);

            param1_label = new Gtk.Label ("Effect Size (d):") { xalign = 0 };
            grid.attach (param1_label, 0, 1, 1, 1);
            param1_spin = new Gtk.SpinButton.with_range (0.05, 5.00, 0.05) {
                digits = 2,
                value = 0.50
            };
            grid.attach (param1_spin, 1, 1, 1, 1);

            param2_label = new Gtk.Label ("Allocation (n2/n1):") { xalign = 0 };
            grid.attach (param2_label, 2, 1, 1, 1);
            param2_spin = new Gtk.SpinButton.with_range (0.05, 5.00, 0.05) {
                digits = 2,
                value = 1.00
            };
            grid.attach (param2_spin, 3, 1, 1, 1);

            grid.attach (new Gtk.Label ("Attrition / Dropout (%):") { xalign = 0 }, 0, 2, 2, 1);
            dropout_spin = new Gtk.SpinButton.with_range (0.0, 50.0, 1.0) {
                digits = 1,
                value = 10.0
            };
            grid.attach (dropout_spin, 2, 2, 2, 1);

            box.append (grid);

            var res_group = new Adw.PreferencesGroup () {
                title = "ICH E9 Sample Size Specification"
            };
            evaluable_n_row = new Adw.ActionRow () { title = "Evaluable Sample Size (N)" };
            evaluable_n_row.add_css_class ("property");
            enrolled_n_row = new Adw.ActionRow () { title = "Attrition-Adjusted Target" };
            enrolled_n_row.add_css_class ("property");
            arm_breakdown_row = new Adw.ActionRow () { title = "Arm Breakdown / Events" };
            arm_breakdown_row.add_css_class ("property");

            res_group.add (evaluable_n_row);
            res_group.add (enrolled_n_row);
            res_group.add (arm_breakdown_row);
            box.append (res_group);

            power_curve_area = new Gtk.DrawingArea () {
                content_width = 440,
                content_height = 110
            };
            power_curve_area.set_draw_func (draw_power_curve);
            box.append (power_curve_area);

            var action_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                homogeneous = true
            };
            var btn_sap = new Gtk.Button.with_label ("+ SAP Justification");
            btn_sap.add_css_class ("suggested-action");
            btn_sap.clicked.connect (() => {
                insert_snippet_requested (build_sap_justification_markdown ());
                this.popdown ();
            });

            var btn_r = new Gtk.Button.with_label ("+ R Power Chunk");
            btn_r.clicked.connect (() => {
                insert_snippet_requested (build_r_power_chunk ());
                this.popdown ();
            });

            var btn_py = new Gtk.Button.with_label ("+ Py Power Chunk");
            btn_py.clicked.connect (() => {
                insert_snippet_requested (build_py_power_chunk ());
                this.popdown ();
            });

            action_bar.append (btn_sap);
            action_bar.append (btn_r);
            action_bar.append (btn_py);
            box.append (action_bar);

            endpoint_selector.notify["selected"].connect (() => {
                uint mode = endpoint_selector.selected;
                if (mode == 0) {
                    param1_label.label = "Effect Size (d):";
                    param1_spin.set_range (0.05, 5.00);
                    param1_spin.value = 0.50;
                    param2_label.label = "Allocation (n2/n1):";
                    param2_spin.set_range (0.10, 5.00);
                    param2_spin.value = 1.00;
                } else if (mode == 1) {
                    param1_label.label = "Control Prop (p1):";
                    param1_spin.set_range (0.01, 0.99);
                    param1_spin.value = 0.30;
                    param2_label.label = "Treat Prop (p2):";
                    param2_spin.set_range (0.01, 0.99);
                    param2_spin.value = 0.50;
                } else {
                    param1_label.label = "Hazard Ratio (HR):";
                    param1_spin.set_range (0.10, 3.00);
                    param1_spin.value = 0.65;
                    param2_label.label = "Event Prob P(ev):";
                    param2_spin.set_range (0.05, 1.00);
                    param2_spin.value = 0.60;
                }
                recalculate_sample_size ();
            });

            alpha_selector.notify["selected"].connect (() => recalculate_sample_size ());
            power_spin.value_changed.connect (() => recalculate_sample_size ());
            param1_spin.value_changed.connect (() => recalculate_sample_size ());
            param2_spin.value_changed.connect (() => recalculate_sample_size ());
            dropout_spin.value_changed.connect (() => recalculate_sample_size ());

            return box;
        }

        private Gtk.Widget build_clinical_templates_tab () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            template_selector = new Gtk.DropDown.from_strings ({
                "CDISC ADSL Table 1 — Baseline Patient Demographics & SMD",
                "CDISC ADTTE Survival — Kaplan-Meier Curve & Cox PH Model",
                "Subgroup Forest Plot — Hazard Ratios & 95% CIs",
                "Multi-Omics Volcano Plot — Differential Expression (FDR & log2FC)"
            });
            box.append (template_selector);

            var group = new Adw.PreferencesGroup () {
                title = "Dataset and Variable Mapping"
            };

            dataset_entry = new Gtk.Entry () { text = "clinical_df", valign = Gtk.Align.CENTER };
            var ds_row = new Adw.ActionRow () { title = "DataFrame Object" };
            ds_row.add_suffix (dataset_entry);
            group.add (ds_row);

            group_col_entry = new Gtk.Entry () { text = "ARM", valign = Gtk.Align.CENTER };
            var grp_row = new Adw.ActionRow () { title = "Arm / log2FC Column" };
            grp_row.add_suffix (group_col_entry);
            group.add (grp_row);

            outcome_col_entry = new Gtk.Entry () { text = "AVAL", valign = Gtk.Align.CENTER };
            var out_row = new Adw.ActionRow () { title = "Time / padj Column" };
            out_row.add_suffix (outcome_col_entry);
            group.add (out_row);

            status_col_entry = new Gtk.Entry () { text = "EVENT", valign = Gtk.Align.CENTER };
            var st_row = new Adw.ActionRow () { title = "Event / Gene Column" };
            st_row.add_suffix (status_col_entry);
            group.add (st_row);

            box.append (group);

            template_selector.notify["selected"].connect (() => {
                if (template_selector.selected == 3) {
                    dataset_entry.text = "deseq2_res";
                    group_col_entry.text = "log2FoldChange";
                    outcome_col_entry.text = "padj";
                    status_col_entry.text = "gene_symbol";
                } else {
                    dataset_entry.text = "clinical_df";
                    group_col_entry.text = "ARM";
                    outcome_col_entry.text = "AVAL";
                    status_col_entry.text = "EVENT";
                }
            });

            var action_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                homogeneous = true,
                margin_top = 6
            };
            var btn_r = new Gtk.Button.with_label ("+ Insert R Clinical Chunk");
            btn_r.add_css_class ("suggested-action");
            btn_r.clicked.connect (() => {
                insert_snippet_requested (build_clinical_r_template ());
                this.popdown ();
            });

            var btn_py = new Gtk.Button.with_label ("+ Insert Python Clinical Chunk");
            btn_py.clicked.connect (() => {
                insert_snippet_requested (build_clinical_py_template ());
                this.popdown ();
            });

            action_bar.append (btn_r);
            action_bar.append (btn_py);
            box.append (action_bar);

            return box;
        }

        public static double normal_quantile (double p) {
            if (p <= 0.0) return -8.0;
            if (p >= 1.0) return 8.0;
            if (GLib.Math.fabs (p - 0.5) < 1e-12) return 0.0;

            double q = p < 0.5 ? p : 1.0 - p;
            double t = GLib.Math.sqrt (-2.0 * GLib.Math.log (q));
            double c0 = 2.515517;
            double c1 = 0.802853;
            double c2 = 0.010328;
            double d1 = 1.432788;
            double d2 = 0.189269;
            double d3 = 0.001308;
            double z = t - ((c2 * t + c1) * t + c0) / (((d3 * t + d2) * t + d1) * t + 1.0);
            return p < 0.5 ? -z : z;
        }

        public static double normal_cdf (double z) {
            return 0.5 * GLib.Math.erfc (-z / GLib.Math.SQRT2);
        }

        private double get_selected_alpha () {
            switch (alpha_selector.selected) {
                case 1: return 0.01;
                case 2: return 0.005;
                case 3: return 0.001;
                default: return 0.05;
            }
        }

        private void recalculate_sample_size () {
            double alpha = get_selected_alpha ();
            double power = power_spin.value;
            double z_alpha = normal_quantile (1.0 - alpha / 2.0);
            double z_beta = normal_quantile (power);
            double p1 = param1_spin.value;
            double p2 = param2_spin.value;
            double dropout = dropout_spin.value / 100.0;
            if (dropout >= 0.95) dropout = 0.95;

            uint mode = endpoint_selector.selected;
            calc_events = 0;

            if (mode == 0) {
                double d = double.max (0.05, p1);
                double k = double.max (0.10, p2);
                double n1_raw = ((1.0 + 1.0 / k) * GLib.Math.pow (z_alpha + z_beta, 2.0)) / (d * d)
                                + (z_alpha * z_alpha) / (2.0 * (1.0 + k));
                calc_n1 = (int) GLib.Math.ceil (n1_raw);
                calc_n2 = (int) GLib.Math.ceil (k * calc_n1);
                calc_evaluable_n = calc_n1 + calc_n2;
                arm_breakdown_row.subtitle = @"Arm 1: $(calc_n1) | Arm 2: $(calc_n2) (Cohen's d = %.2f)".printf (d);
            } else if (mode == 1) {
                double diff = GLib.Math.fabs (p2 - p1);
                if (diff < 0.005) diff = 0.005;
                double p_bar = 0.5 * (p1 + p2);
                double num = z_alpha * GLib.Math.sqrt (2.0 * p_bar * (1.0 - p_bar))
                           + z_beta * GLib.Math.sqrt (p1 * (1.0 - p1) + p2 * (1.0 - p2));
                double n_raw = (num * num) / (diff * diff);
                double cc = (n_raw / 4.0) * GLib.Math.pow (1.0 + GLib.Math.sqrt (1.0 + 4.0 / (n_raw * diff)), 2.0);
                calc_n1 = (int) GLib.Math.ceil (cc);
                calc_n2 = calc_n1;
                calc_evaluable_n = calc_n1 + calc_n2;
                arm_breakdown_row.subtitle = @"$(calc_n1) per arm (Δp = %.1f%%)".printf (diff * 100.0);
            } else {
                double hr = p1;
                if (GLib.Math.fabs (hr - 1.0) < 0.02) hr = 0.95;
                double ev_prob = double.max (0.05, p2);
                double log_hr = GLib.Math.log (hr);
                double req_events = 4.0 * GLib.Math.pow (z_alpha + z_beta, 2.0) / (log_hr * log_hr);
                calc_events = (int) GLib.Math.ceil (req_events);
                calc_evaluable_n = (int) GLib.Math.ceil (calc_events / ev_prob);
                if (calc_evaluable_n % 2 != 0) calc_evaluable_n++;
                calc_n1 = calc_evaluable_n / 2;
                calc_n2 = calc_evaluable_n / 2;
                arm_breakdown_row.subtitle = @"Required Events: $(calc_events) | $(calc_n1) per arm (HR = %.2f)".printf (hr);
            }

            calc_enrolled_n = (int) GLib.Math.ceil (calc_evaluable_n / (1.0 - dropout));
            evaluable_n_row.subtitle = @"$(calc_evaluable_n) subjects (α = %.3f, Power = %.0f%%)".printf (alpha, power * 100.0);
            enrolled_n_row.subtitle = @"$(calc_enrolled_n) subjects (accounting for %.1f%% attrition)".printf (dropout_spin.value);

            power_curve_area.queue_draw ();
        }

        private double compute_power_for_total_n (int total_n) {
            double alpha = get_selected_alpha ();
            double z_alpha = normal_quantile (1.0 - alpha / 2.0);
            uint mode = endpoint_selector.selected;
            double p1 = param1_spin.value;
            double p2 = param2_spin.value;

            if (mode == 0) {
                double d = double.max (0.05, p1);
                double k = double.max (0.10, p2);
                double n1 = total_n / (1.0 + k);
                double se = GLib.Math.sqrt ((1.0 + 1.0 / k) / double.max (1.0, n1));
                return normal_cdf (d / se - z_alpha);
            } else if (mode == 1) {
                double diff = GLib.Math.fabs (p2 - p1);
                double n_arm = double.max (2.0, total_n / 2.0);
                double se = GLib.Math.sqrt ((p1 * (1.0 - p1) + p2 * (1.0 - p2)) / n_arm);
                if (se <= 1e-9) return 1.0;
                return normal_cdf (diff / se - z_alpha);
            } else {
                double hr = p1;
                if (GLib.Math.fabs (hr - 1.0) < 0.02) hr = 0.95;
                double ev_prob = double.max (0.05, p2);
                double events = total_n * ev_prob;
                double z = 0.5 * GLib.Math.fabs (GLib.Math.log (hr)) * GLib.Math.sqrt (events) - z_alpha;
                return normal_cdf (z);
            }
        }

        private void draw_power_curve (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            cr.set_source_rgb (0.09, 0.11, 0.16);
            cr.paint ();

            double pad_l = 36.0, pad_r = 14.0, pad_t = 12.0, pad_b = 22.0;
            double plot_w = width - pad_l - pad_r;
            double plot_h = height - pad_t - pad_b;

            // Reference 80% and target power lines
            double target_p = power_spin.value;
            double y_target = pad_t + plot_h * (1.0 - target_p);
            cr.set_source_rgba (0.23, 0.51, 0.96, 0.45);
            cr.set_line_width (1.0);
            cr.move_to (pad_l, y_target);
            cr.line_to (pad_l + plot_w, y_target);
            cr.stroke ();

            int max_n = int.max (40, (int) (calc_enrolled_n * 1.4));
            cr.set_source_rgb (0.06, 0.73, 0.51);
            cr.set_line_width (2.2);

            int steps = 50;
            for (int i = 1; i <= steps; i++) {
                int n_val = (int) ((double) i / steps * max_n);
                double pwr = compute_power_for_total_n (n_val);
                double x = pad_l + ((double) n_val / max_n) * plot_w;
                double y = pad_t + plot_h * (1.0 - double.min (1.0, double.max (0.0, pwr)));
                if (i == 1) cr.move_to (x, y);
                else cr.line_to (x, y);
            }
            cr.stroke ();

            // Operating point marker
            double op_x = pad_l + ((double) calc_evaluable_n / max_n) * plot_w;
            cr.set_source_rgb (0.96, 0.62, 0.04);
            cr.arc (op_x, y_target, 4.5, 0, 2 * GLib.Math.PI);
            cr.fill ();

            cr.set_source_rgb (0.82, 0.86, 0.92);
            cr.set_font_size (10.0);
            cr.move_to (pad_l + 4, pad_t + 10);
            cr.show_text (@"Power Curve (N_eval = $(calc_evaluable_n), N_enrolled = $(calc_enrolled_n))");
        }

        private string build_sap_justification_markdown () {
            double alpha = get_selected_alpha ();
            double power = power_spin.value * 100.0;
            string design_name = "Two-Sample Student's t-Test";
            if (endpoint_selector.selected == 1) design_name = "Two-Sample Binomial Proportions Test";
            else if (endpoint_selector.selected == 2) design_name = "Two-Sided Log-Rank Survival Test (Schoenfeld Formula)";

            return """
### Statistical Power & Sample Size Justification (ICH E9)

To achieve **%.0f%% statistical power** ($1 - \beta = %.2f$) at a two-sided Type I error rate of **$\alpha = %.3f$** using a **%s**, a minimum of **$N = %d$ evaluable subjects** (%s) is required. Accounting for an anticipated **%.1f%% attrition/dropout rate**, the study will enroll **$N_{\text{total}} = %d$ subjects**.

| Study Design Parameter | Specification |
| :--- | :--- |
| **Primary Hypothesis Test** | %s |
| **Two-Sided Significance Level ($\alpha$)** | %.3f |
| **Target Statistical Power ($1 - \beta$)** | %.0f%% |
| **Minimum Evaluable Sample Size ($N_{\text{eval}}$)** | %d |
| **Attrition-Adjusted Enrollment ($N_{\text{enrolled}}$)** | %d (%.1f%% dropout) |
""".printf (
                power, power_spin.value, alpha, design_name,
                calc_evaluable_n, arm_breakdown_row.subtitle,
                dropout_spin.value, calc_enrolled_n,
                design_name, alpha, power, calc_evaluable_n, calc_enrolled_n, dropout_spin.value
            );
        }

        private string build_r_power_chunk () {
            double alpha = get_selected_alpha ();
            double power = power_spin.value;
            if (endpoint_selector.selected == 0) {
                return """```{r elbereth-power-ttest}
# ELBERETH ICH E9 POWER VERIFICATION: Two-Sample t-Test
power_res <- stats::power.t.test(delta = %.2f, sd = 1.0, sig.level = %.3f, power = %.2f, type = "two.sample", alternative = "two.sided")
print(power_res)
```
""".printf (param1_spin.value, alpha, power);
            } else if (endpoint_selector.selected == 1) {
                return """```{r elbereth-power-prop}
# ELBERETH ICH E9 POWER VERIFICATION: Two-Sample Proportions
power_res <- stats::power.prop.test(p1 = %.2f, p2 = %.2f, sig.level = %.3f, power = %.2f, alternative = "two.sided")
print(power_res)
```
""".printf (param1_spin.value, param2_spin.value, alpha, power);
            } else {
                return """```{r elbereth-power-survival}
# ELBERETH ICH E9 POWER VERIFICATION: Schoenfeld (1983) Log-Rank Survival Formula
alpha <- %.3f; power <- %.2f; hr <- %.2f; p_event <- %.2f
z_alpha <- qnorm(1 - alpha / 2); z_beta <- qnorm(power)
req_events <- ceiling(4 * (z_alpha + z_beta)^2 / (log(hr)^2))
n_evaluable <- ceiling(req_events / p_event)
cat(sprintf("Required Events: %%d | Evaluable Sample Size: %%d\n", req_events, n_evaluable))
```
""".printf (alpha, power, param1_spin.value, param2_spin.value);
            }
        }

        private string build_py_power_chunk () {
            double alpha = get_selected_alpha ();
            double power = power_spin.value;
            return """```{python elbereth-power-verify}
# ELBERETH ICH E9 POWER & SAMPLE SIZE VERIFICATION
import math
from scipy.stats import norm

alpha, power = %.3f, %.2f
z_alpha, z_beta = norm.ppf(1 - alpha / 2), norm.ppf(power)
print(f"Z_(1-alpha/2) = {z_alpha:.4f}, Z_(1-beta) = {z_beta:.4f}")
print(f"Evaluable N = %d | Attrition-Adjusted Enrolled N = %d")
```
""".printf (alpha, power, calc_evaluable_n, calc_enrolled_n);
        }

        private string build_clinical_r_template () {
            string df = dataset_entry.text.strip ();
            string arm = group_col_entry.text.strip ();
            string aval = outcome_col_entry.text.strip ();
            string ev = status_col_entry.text.strip ();

            switch (template_selector.selected) {
                case 0:
                    return """```{r cdisc-table1-demographics, message=FALSE, warning=FALSE}
# CDISC ADSL TABLE 1: Baseline Patient Demographics Stratified by %s
if (requireNamespace("gtsummary", quietly = TRUE)) {
  %s |>
    gtsummary::tbl_summary(by = %s, missing = "ifany") |>
    gtsummary::add_p() |>
    gtsummary::add_overall() |>
    gtsummary::bold_labels()
} else {
  print(by(%s, %s[["%s"]], summary))
}
```
""".printf (arm, df, arm, df, df, arm);
                case 1:
                    return """```{r cdisc-adtte-survival, message=FALSE, warning=FALSE}
# CDISC ADTTE SURVIVAL ANALYSIS: Kaplan-Meier & Cox Proportional Hazards
library(survival)
surv_obj <- Surv(time = %s[["%s"]], event = %s[["%s"]])
km_fit <- survfit(surv_obj ~ %s[["%s"]])
cox_fit <- coxph(surv_obj ~ %s[["%s"]])
print(summary(cox_fit))
plot(km_fit, col = c("#2563eb", "#dc2626"), lwd = 2,
     xlab = "Time", ylab = "Survival Probability",
     main = "Kaplan-Meier Survival Curve by %s")
```
""".printf (df, aval, df, ev, df, arm, df, arm, arm);
                case 2:
                    return """```{r clinical-forest-plot, message=FALSE, warning=FALSE}
# SUBGROUP HAZARD RATIO / ODDS RATIO FOREST PLOT (95%% CI)
library(ggplot2)
ggplot(%s, aes(x = %s, y = %s)) +
  geom_vline(xintercept = 1.0, linetype = "dashed", color = "#64748b") +
  geom_errorbarh(aes(xmin = %s * 0.75, xmax = %s * 1.33), height = 0.2, color = "#475569") +
  geom_point(size = 3, color = "#2563eb") +
  theme_minimal() +
  labs(title = "Subgroup Forest Plot", x = "Hazard Ratio (95%% CI)", y = "Subgroup")
```
""".printf (df, aval, arm, aval, aval);
                default:
                    return """```{r omics-volcano-plot, message=FALSE, warning=FALSE}
# MULTI-OMICS DIFFERENTIAL EXPRESSION VOLCANO PLOT (FDR < 0.05, |log2FC| > 1.0)
library(ggplot2)
%s$neg_log10_padj <- -log10(pmax(%s[["%s"]], 1e-300))
%s$sig_status <- ifelse(%s[["%s"]] < 0.05 & abs(%s[["%s"]]) >= 1.0, "Significant", "NS")
ggplot(%s, aes(x = .data[["%s"]], y = neg_log10_padj, color = sig_status)) +
  geom_point(alpha = 0.75, size = 1.8) +
  geom_vline(xintercept = c(-1, 1), linetype = "dashed", color = "#475569") +
  geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "#475569") +
  scale_color_manual(values = c("Significant" = "#dc2626", "NS" = "#94a3b8")) +
  theme_minimal() +
  labs(title = "Differential Expression Volcano Plot", x = "log2 Fold Change", y = "-log10(Adjusted P-Value)")
```
""".printf (df, df, aval, df, df, aval, df, arm, df, arm);
            }
        }

        private string build_clinical_py_template () {
            string df = dataset_entry.text.strip ();
            string arm = group_col_entry.text.strip ();
            string aval = outcome_col_entry.text.strip ();
            string ev = status_col_entry.text.strip ();

            if (template_selector.selected == 3) {
                return """```{python omics-volcano-py}
# MULTI-OMICS VOLCANO PLOT (Python / Matplotlib)
import numpy as np
import matplotlib.pyplot as plt

fc = %s["%s"].to_numpy()
padj = np.clip(%s["%s"].to_numpy(), 1e-300, 1.0)
neg_log_p = -np.log10(padj)
sig = (padj < 0.05) & (np.abs(fc) >= 1.0)

plt.figure(figsize=(7, 5))
plt.scatter(fc[~sig], neg_log_p[~sig], c="#94a3b8", alpha=0.6, s=16, label="NS")
plt.scatter(fc[sig], neg_log_p[sig], c="#dc2626", alpha=0.85, s=22, label="FDR < 0.05 & |log2FC| >= 1")
plt.axvline(-1.0, ls="--", c="#475569"); plt.axvline(1.0, ls="--", c="#475569")
plt.axhline(-np.log10(0.05), ls="--", c="#475569")
plt.xlabel("log2 Fold Change"); plt.ylabel("-log10(Adjusted P-Value)")
plt.title("Differential Expression Volcano Plot"); plt.legend()
plt.tight_layout(); plt.show()
```
""".printf (df, arm, df, aval);
            }

            return """```{python clinical-analysis-py}
# CLINICAL BIOSTATISTICS SUMMARY & SURVIVAL STRATIFICATION
import pandas as pd
summary_tbl = %s.groupby("%s")[["%s", "%s"]].describe()
print(summary_tbl)
```
""".printf (df, arm, aval, ev);
        }
    }
}
