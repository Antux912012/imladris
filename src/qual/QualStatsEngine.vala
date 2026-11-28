// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Qual {

    public enum IrrScaleType {
        NOMINAL,
        ORDINAL
    }

    public class IrrResult : GLib.Object {
        public string metric_name { get; set; default = ""; }
        public double statistic { get; set; default = 0.0; }
        public double observed_agreement { get; set; default = 0.0; }
        public double expected_agreement { get; set; default = 0.0; }
        public double z_score { get; set; default = 0.0; }
        public double p_value { get; set; default = 1.0; }
        public int n_units { get; set; default = 0; }
        public int n_raters { get; set; default = 0; }
        public int n_categories { get; set; default = 0; }
        public string interpretation { get; set; default = ""; }

        public static string interpret_kappa (double k) {
            if (k < 0.0) return "Poor (< 0.00)";
            if (k < 0.20) return "Slight (0.00–0.20)";
            if (k < 0.40) return "Fair (0.21–0.40)";
            if (k < 0.60) return "Moderate (0.41–0.60)";
            if (k < 0.80) return "Substantial (0.61–0.80)";
            return "Almost Perfect (0.81–1.00)";
        }
    }

    public class AdjudicationDiff : GLib.Object {
        public string file_path { get; set; default = ""; }
        public int line_start { get; set; default = 1; }
        public string excerpt { get; set; default = ""; }
        public string coder_a { get; set; default = ""; }
        public string code_a { get; set; default = ""; }
        public string coder_b { get; set; default = ""; }
        public string code_b { get; set; default = ""; }
        public bool agreed { get; set; default = false; }
    }

    public class EnrichmentResult : GLib.Object {
        public string code_a { get; set; default = ""; }
        public string code_b { get; set; default = ""; }
        public int a_both { get; set; default = 0; }
        public int b_only_a { get; set; default = 0; }
        public int c_only_b { get; set; default = 0; }
        public int d_neither { get; set; default = 0; }
        public double odds_ratio { get; set; default = 1.0; }
        public double fisher_p_two_sided { get; set; default = 1.0; }
        public double chi2_stat { get; set; default = 0.0; }
        public double chi2_p_value { get; set; default = 1.0; }
    }

    public class SaturationPoint : GLib.Object {
        public int doc_index { get; set; default = 0; }
        public string doc_name { get; set; default = ""; }
        public int unique_codes_in_doc { get; set; default = 0; }
        public int new_codes_added { get; set; default = 0; }
        public int cumulative_unique_codes { get; set; default = 0; }
    }

    /**
     * Native Vala Biostatistical Qualitative Calculator:
     * - Cohen's Kappa (2 raters)
     * - Fleiss' Kappa (m >= 2 raters)
     * - Krippendorff's Alpha (nominal & ordinal scales with missing values)
     * - N x N Code Co-Occurrence Matrix
     * - Exact Two-Sided Fisher's Exact Test & Pearson Chi-Square Test
     * - Thematic Saturation Curve & R/Python script bridge (.imladris/scripts/qual_stats.R)
     */
    public class QualStatsEngine : GLib.Object {

        public static IrrResult compute_cohens_kappa (string[] rater1, string[] rater2) {
            var res = new IrrResult () { metric_name = "Cohen's Kappa" };
            int n = int.min (rater1.length, rater2.length);
            if (n == 0) return res;

            var cat_map = new Gee.HashMap<string, int> ();
            var cats = new Gee.ArrayList<string> ();
            int valid_n = 0;
            for (int i = 0; i < n; i++) {
                if (rater1[i] == "" || rater2[i] == "") continue;
                valid_n++;
                if (!cat_map.has_key (rater1[i])) {
                    cat_map.set (rater1[i], cats.size);
                    cats.add (rater1[i]);
                }
                if (!cat_map.has_key (rater2[i])) {
                    cat_map.set (rater2[i], cats.size);
                    cats.add (rater2[i]);
                }
            }
            int k = cats.size;
            res.n_units = valid_n;
            res.n_raters = 2;
            res.n_categories = k;
            if (valid_n == 0 || k == 0) return res;

            int[,] mat = new int[k, k];
            int[] row_sum = new int[k];
            int[] col_sum = new int[k];

            for (int i = 0; i < n; i++) {
                if (rater1[i] == "" || rater2[i] == "") continue;
                int r = cat_map.get (rater1[i]);
                int c = cat_map.get (rater2[i]);
                mat[r, c]++;
                row_sum[r]++;
                col_sum[c]++;
            }

            int diag = 0;
            double pe_num = 0.0;
            double p3_sum = 0.0;
            double dn = (double) valid_n;
            for (int j = 0; j < k; j++) {
                diag += mat[j, j];
                double pr = row_sum[j] / dn;
                double pc = col_sum[j] / dn;
                pe_num += pr * pc;
                p3_sum += pr * pc * (pr + pc);
            }

            double po = diag / dn;
            double pe = pe_num;
            double kappa = (1.0 - pe).abs () < 1e-15 ? 1.0 : (po - pe) / (1.0 - pe);

            // Fleiss/Cohen null variance for z-statistic (matching R irr::kappa2)
            double denom = (1.0 - pe) * GLib.Math.sqrt (dn);
            double num_var = pe + pe * pe - p3_sum;
            double z = 0.0;
            double pval = 1.0;
            if (denom > 1e-15 && num_var > 1e-15) {
                double se0 = GLib.Math.sqrt (num_var) / denom;
                z = kappa / se0;
                pval = GLib.Math.erfc (z.abs () / GLib.Math.SQRT2);
            }

            res.statistic = kappa;
            res.observed_agreement = po;
            res.expected_agreement = pe;
            res.z_score = z;
            res.p_value = pval;
            res.interpretation = IrrResult.interpret_kappa (kappa);
            return res;
        }

        /**
         * Fleiss' Kappa on an N_subjects x K_categories count matrix where each row sums to m raters.
         */
        public static IrrResult compute_fleiss_kappa (int[,] counts, int n_subjects, int n_categories) {
            var res = new IrrResult () {
                metric_name = "Fleiss' Kappa",
                n_units = n_subjects,
                n_categories = n_categories
            };
            if (n_subjects <= 0 || n_categories <= 0) return res;

            int m = 0;
            for (int j = 0; j < n_categories; j++) {
                m += counts[0, j];
            }
            res.n_raters = m;
            if (m < 2) return res;

            double total_ratings = (double) n_subjects * (double) m;
            double[] pj = new double[n_categories];
            for (int j = 0; j < n_categories; j++) {
                int col_tot = 0;
                for (int i = 0; i < n_subjects; i++) {
                    col_tot += counts[i, j];
                }
                pj[j] = col_tot / total_ratings;
            }

            double sum_pi = 0.0;
            double m_pair = (double) m * (double) (m - 1);
            for (int i = 0; i < n_subjects; i++) {
                double sq_sum = 0.0;
                for (int j = 0; j < n_categories; j++) {
                    double nij = (double) counts[i, j];
                    sq_sum += nij * nij;
                }
                sum_pi += (sq_sum - (double) m) / m_pair;
            }

            double p_bar = sum_pi / (double) n_subjects;
            double pe_bar = 0.0;
            double pj_cube = 0.0;
            for (int j = 0; j < n_categories; j++) {
                pe_bar += pj[j] * pj[j];
                pj_cube += pj[j] * pj[j] * pj[j];
            }

            double kappa = (1.0 - pe_bar).abs () < 1e-15 ? 1.0 : (p_bar - pe_bar) / (1.0 - pe_bar);

            // Exact Fleiss (1971) asymptotic variance under null hypothesis (matches R irr::kappam.fleiss)
            double var_num = 2.0 * (pe_bar - (2.0 * m - 3.0) * pe_bar * pe_bar + 2.0 * (m - 2.0) * pj_cube);
            double var_den = (double) n_subjects * m_pair * (1.0 - pe_bar) * (1.0 - pe_bar);
            double z = 0.0;
            double pval = 1.0;
            if (var_den > 1e-15 && var_num > 1e-15) {
                double se = GLib.Math.sqrt (var_num / var_den);
                z = kappa / se;
                pval = GLib.Math.erfc (z.abs () / GLib.Math.SQRT2);
            }

            res.statistic = kappa;
            res.observed_agreement = p_bar;
            res.expected_agreement = pe_bar;
            res.z_score = z;
            res.p_value = pval;
            res.interpretation = IrrResult.interpret_kappa (kappa);
            return res;
        }

        /**
         * Krippendorff's Alpha on reliability matrix ratings[n_raters, n_units],
         * where -1 denotes missing data and >= 0 denotes category index (ordered for ORDINAL).
         * Matches R irr::kripp.alpha to < 1e-10.
         */
        public static IrrResult compute_krippendorff_alpha (
            int[,] ratings,
            int n_raters,
            int n_units,
            IrrScaleType scale = IrrScaleType.NOMINAL
        ) {
            var res = new IrrResult () {
                metric_name = scale == IrrScaleType.ORDINAL ? "Krippendorff's Alpha (Ordinal)" : "Krippendorff's Alpha (Nominal)",
                n_raters = n_raters
            };
            if (n_raters < 2 || n_units < 1) return res;

            // Collect distinct non-missing categories in ascending order
            var cat_set = new Gee.TreeSet<int> ();
            for (int r = 0; r < n_raters; r++) {
                for (int u = 0; u < n_units; u++) {
                    if (ratings[r, u] >= 0) cat_set.add (ratings[r, u]);
                }
            }
            int k = cat_set.size;
            res.n_categories = k;
            if (k <= 1) {
                res.statistic = 1.0;
                res.observed_agreement = 1.0;
                res.expected_agreement = 1.0;
                res.interpretation = IrrResult.interpret_kappa (1.0);
                return res;
            }

            var val_to_idx = new Gee.HashMap<int, int> ();
            int cidx = 0;
            foreach (int v in cat_set) {
                val_to_idx.set (v, cidx++);
            }

            double[,] o_mat = new double[k, k];
            int pairable_units = 0;

            for (int u = 0; u < n_units; u++) {
                int mu = 0;
                int[] unit_counts = new int[k];
                for (int r = 0; r < n_raters; r++) {
                    int val = ratings[r, u];
                    if (val >= 0) {
                        mu++;
                        unit_counts[val_to_idx.get (val)]++;
                    }
                }
                if (mu < 2) continue;
                pairable_units++;
                double denom = (double) (mu - 1);
                for (int c = 0; c < k; c++) {
                    if (unit_counts[c] == 0) continue;
                    o_mat[c, c] += ((double) unit_counts[c] * (double) (unit_counts[c] - 1)) / denom;
                    for (int l = c + 1; l < k; l++) {
                        if (unit_counts[l] == 0) continue;
                        double contrib = ((double) unit_counts[c] * (double) unit_counts[l]) / denom;
                        o_mat[c, l] += contrib;
                        o_mat[l, c] += contrib;
                    }
                }
            }

            res.n_units = pairable_units;
            if (pairable_units == 0) return res;

            double[] nc = new double[k];
            double n_total = 0.0;
            for (int c = 0; c < k; c++) {
                double row_s = 0.0;
                for (int l = 0; l < k; l++) row_s += o_mat[c, l];
                nc[c] = row_s;
                n_total += row_s;
            }
            if (n_total <= 1.0) return res;

            double[,] delta_sq = new double[k, k];
            if (scale == IrrScaleType.NOMINAL) {
                for (int c = 0; c < k; c++) {
                    for (int l = 0; l < k; l++) {
                        delta_sq[c, l] = (c == l) ? 0.0 : 1.0;
                    }
                }
            } else {
                for (int c = 0; c < k; c++) {
                    for (int l = c + 1; l < k; l++) {
                        double sum_between = 0.0;
                        for (int g = c; g <= l; g++) sum_between += nc[g];
                        double d = sum_between - (nc[c] + nc[l]) / 2.0;
                        delta_sq[c, l] = d * d;
                        delta_sq[l, c] = d * d;
                    }
                }
            }

            double do_num = 0.0;
            double de_num = 0.0;
            for (int c = 0; c < k; c++) {
                for (int l = c + 1; l < k; l++) {
                    do_num += o_mat[c, l] * delta_sq[c, l];
                    de_num += nc[c] * nc[l] * delta_sq[c, l];
                }
            }

            double alpha = (de_num < 1e-15) ? 1.0 : 1.0 - (n_total - 1.0) * (do_num / de_num);
            res.statistic = alpha;
            res.observed_agreement = 1.0 - (2.0 * do_num / n_total);
            res.expected_agreement = 1.0 - (2.0 * de_num / (n_total * (n_total - 1.0)));
            res.interpretation = IrrResult.interpret_kappa (alpha);
            return res;
        }

        // =====================================================================
        // EXACT FISHER'S TEST & CHI-SQUARE ENRICHMENT
        // =====================================================================
        private static double log_choose (int n, int k) {
            if (k < 0 || k > n) return -1e300;
            return GLib.Math.lgamma (n + 1.0) - GLib.Math.lgamma (k + 1.0) - GLib.Math.lgamma (n - k + 1.0);
        }

        private static double log_hypergeom (int x, int r1, int r2, int c1, int n) {
            return log_choose (r1, x) + log_choose (r2, c1 - x) - log_choose (n, c1);
        }

        /**
         * Exact two-sided Fisher's Exact Test matching R fisher.test() and scipy.stats.fisher_exact().
         */
        public static double fisher_exact_two_sided (int a, int b, int c, int d, out double odds_ratio) {
            odds_ratio = ((b == 0 || c == 0) ? ((a == 0 || d == 0) ? 1.0 : double.INFINITY) : ((double) a * (double) d) / ((double) b * (double) c));
            int r1 = a + b;
            int r2 = c + d;
            int c1 = a + c;
            int n = r1 + r2;
            if (n <= 0) return 1.0;

            int x_min = int.max (0, c1 - r2);
            int x_max = int.min (r1, c1);
            double log_p_obs = log_hypergeom (a, r1, r2, c1, n);
            double p_obs = GLib.Math.exp (log_p_obs);
            // Relative tolerance 1 + 1e-7 matches R stats::fisher.test / scipy.stats.fisher_exact
            double cutoff = log_p_obs + 1e-11;
            double total_p = 0.0;
            for (int x = x_min; x <= x_max; x++) {
                double lp = log_hypergeom (x, r1, r2, c1, n);
                if (lp <= cutoff || (GLib.Math.exp (lp) <= p_obs * (1.0 + 1e-7))) {
                    total_p += GLib.Math.exp (lp);
                }
            }
            return total_p.clamp (0.0, 1.0);
        }

        /**
         * Pearson's 2x2 Chi-Square test (without Yates correction by default, or with correction).
         * Exact df=1 upper tail: P(Chi2_1 >= x) = erfc(sqrt(x / 2)).
         */
        public static double chi_square_2x2 (int a, int b, int c, int d, bool yates_correction, out double chi2_out) {
            chi2_out = 0.0;
            double n = (double) (a + b + c + d);
            double r1 = a + b;
            double r2 = c + d;
            double c1 = a + c;
            double c2 = b + d;
            if (n <= 0.0 || r1 <= 0.0 || r2 <= 0.0 || c1 <= 0.0 || c2 <= 0.0) {
                return 1.0;
            }
            double det = ((double) a * (double) d - (double) b * (double) c).abs ();
            if (yates_correction) {
                det = double.max (0.0, det - n / 2.0);
            }
            chi2_out = (n * det * det) / (r1 * r2 * c1 * c2);
            return GLib.Math.erfc (GLib.Math.sqrt (chi2_out / 2.0)).clamp (0.0, 1.0);
        }

        /**
         * Computes N x N co-occurrence matrix and pairwise enrichment across sampling units
         * (each document/entity-context forms a unit).
         */
        public static int[,] compute_cooccurrence_and_enrichment (
            Gee.ArrayList<QualSpan> spans,
            out string[] code_ids,
            out Gee.ArrayList<EnrichmentResult> enrichments
        ) {
            enrichments = new Gee.ArrayList<EnrichmentResult> ();
            var code_set = new Gee.TreeSet<string> ();
            // Group spans by sampling unit: file_path + paragraph/section bucket (line / 8) or entity_id
            var unit_codes = new Gee.HashMap<string, Gee.HashSet<string>> ();

            foreach (var sp in spans) {
                if (sp.code_id == "") continue;
                code_set.add (sp.code_id);
                string unit_key = (sp.entity_id != null && sp.entity_id != "")
                    ? (sp.file_path + "::" + sp.entity_id)
                    : @"$(sp.file_path)::blk$(sp.line_start / 6)";
                var set_for_u = unit_codes.get (unit_key);
                if (set_for_u == null) {
                    set_for_u = new Gee.HashSet<string> ();
                    unit_codes.set (unit_key, set_for_u);
                }
                set_for_u.add (sp.code_id);
            }

            int k = code_set.size;
            code_ids = new string[k];
            int idx = 0;
            foreach (string cid in code_set) code_ids[idx++] = cid;

            int[,] matrix = new int[k, k];
            int n_units = unit_codes.size;

            for (int i = 0; i < k; i++) {
                for (int j = i; j < k; j++) {
                    int a = 0, b = 0, c = 0, d = 0;
                    string ci = code_ids[i];
                    string cj = code_ids[j];
                    foreach (var uset in unit_codes.values) {
                        bool has_i = uset.contains (ci);
                        bool has_j = uset.contains (cj);
                        if (has_i && has_j) a++;
                        else if (has_i && !has_j) b++;
                        else if (!has_i && has_j) c++;
                        else d++;
                    }
                    matrix[i, j] = a;
                    matrix[j, i] = a;

                    if (i < j && n_units >= 2) {
                        double or_val;
                        double fp = fisher_exact_two_sided (a, b, c, d, out or_val);
                        double chi2;
                        double cp = chi_square_2x2 (a, b, c, d, false, out chi2);
                        var er = new EnrichmentResult () {
                            code_a = ci,
                            code_b = cj,
                            a_both = a,
                            b_only_a = b,
                            c_only_b = c,
                            d_neither = d,
                            odds_ratio = or_val,
                            fisher_p_two_sided = fp,
                            chi2_stat = chi2,
                            chi2_p_value = cp
                        };
                        enrichments.add (er);
                    }
                }
            }
            enrichments.sort ((x, y) => {
                if (x.fisher_p_two_sided < y.fisher_p_two_sided) return -1;
                if (x.fisher_p_two_sided > y.fisher_p_two_sided) return 1;
                return 0;
            });
            return matrix;
        }

        public static Gee.ArrayList<SaturationPoint> compute_thematic_saturation (Gee.ArrayList<QualSpan> spans) {
            var points = new Gee.ArrayList<SaturationPoint> ();
            var doc_order = new Gee.ArrayList<string> ();
            var doc_codes = new Gee.HashMap<string, Gee.HashSet<string>> ();

            foreach (var sp in spans) {
                string doc = sp.file_path != "" ? GLib.Path.get_basename (sp.file_path) : "Document 1";
                var cset = doc_codes.get (doc);
                if (cset == null) {
                    cset = new Gee.HashSet<string> ();
                    doc_codes.set (doc, cset);
                    doc_order.add (doc);
                }
                if (sp.code_id != "") cset.add (sp.code_id);
            }

            var seen_global = new Gee.HashSet<string> ();
            for (int i = 0; i < doc_order.size; i++) {
                string dname = doc_order[i];
                var dset = doc_codes.get (dname);
                int newly_discovered = 0;
                foreach (string cid in dset) {
                    if (!seen_global.contains (cid)) {
                        seen_global.add (cid);
                        newly_discovered++;
                    }
                }
                points.add (new SaturationPoint () {
                    doc_index = i + 1,
                    doc_name = dname,
                    unique_codes_in_doc = dset.size,
                    new_codes_added = newly_discovered,
                    cumulative_unique_codes = seen_global.size
                });
            }
            return points;
        }

        /**
         * Pairs overlapping spans across coders from the SQLite index to compute workspace IRR
         * (Cohen's Kappa, Fleiss' Kappa / Krippendorff's Alpha) and adjudication diffs.
         */
        public static void analyze_workspace_irr (
            Gee.ArrayList<QualSpan> all_spans,
            out IrrResult cohen_res,
            out IrrResult kripp_res,
            out Gee.ArrayList<AdjudicationDiff> diffs
        ) {
            diffs = new Gee.ArrayList<AdjudicationDiff> ();
            var coders_set = new Gee.TreeSet<string> ();
            // Unit key: file_path + line_start (or normalized excerpt if same line)
            var unit_map = new Gee.HashMap<string, Gee.HashMap<string, QualSpan>> ();
            var unit_keys = new Gee.ArrayList<string> ();

            foreach (var sp in all_spans) {
                if (sp.coder_id == "" || sp.code_id == "") continue;
                coders_set.add (sp.coder_id);
                string ukey = @"$(sp.file_path):$(sp.line_start)";
                var rmap = unit_map.get (ukey);
                if (rmap == null) {
                    rmap = new Gee.HashMap<string, QualSpan> ();
                    unit_map.set (ukey, rmap);
                    unit_keys.add (ukey);
                }
                rmap.set (sp.coder_id, sp);
            }

            var coders = new Gee.ArrayList<string> ();
            foreach (string c in coders_set) coders.add (c);

            if (coders.size < 2 || unit_keys.size == 0) {
                cohen_res = new IrrResult () { metric_name = "Cohen's Kappa", interpretation = "Requires >= 2 coders" };
                kripp_res = new IrrResult () { metric_name = "Krippendorff's Alpha (Nominal)", interpretation = "Requires >= 2 coders" };
                return;
            }

            // Pick the coder pair (cA, cB) with the largest number of overlapping units
            string cA = coders[0];
            string cB = coders[1];
            int best_overlap = -1;
            for (int i = 0; i < coders.size; i++) {
                for (int j = i + 1; j < coders.size; j++) {
                    int overlap = 0;
                    foreach (string ukey in unit_keys) {
                        var rmap = unit_map.get (ukey);
                        if (rmap.has_key (coders[i]) && rmap.has_key (coders[j])) overlap++;
                    }
                    if (overlap > best_overlap) {
                        best_overlap = overlap;
                        cA = coders[i];
                        cB = coders[j];
                    }
                }
            }
            var r1_list = new Gee.ArrayList<string> ();
            var r2_list = new Gee.ArrayList<string> ();

            foreach (string ukey in unit_keys) {
                var rmap = unit_map.get (ukey);
                if (rmap.has_key (cA) && rmap.has_key (cB)) {
                    var spA = rmap.get (cA);
                    var spB = rmap.get (cB);
                    r1_list.add (spA.code_id);
                    r2_list.add (spB.code_id);

                    var diff = new AdjudicationDiff () {
                        file_path = spA.file_path,
                        line_start = spA.line_start,
                        excerpt = spA.excerpt,
                        coder_a = cA,
                        code_a = spA.code_id,
                        coder_b = cB,
                        code_b = spB.code_id,
                        agreed = (spA.code_id == spB.code_id)
                    };
                    diffs.add (diff);
                }
            }

            string[] r1_arr = new string[r1_list.size];
            string[] r2_arr = new string[r2_list.size];
            for (int i = 0; i < r1_list.size; i++) {
                r1_arr[i] = r1_list[i];
                r2_arr[i] = r2_list[i];
            }
            cohen_res = compute_cohens_kappa (r1_arr, r2_arr);

            // Build Krippendorff's Alpha across ALL coders & units (handles missing data natively)
            var code_to_int = new Gee.HashMap<string, int> ();
            int next_code_int = 0;
            int m = coders.size;
            int u_cnt = unit_keys.size;
            int[,] kmat = new int[m, u_cnt];
            for (int r = 0; r < m; r++) {
                for (int u = 0; u < u_cnt; u++) {
                    var rmap = unit_map.get (unit_keys[u]);
                    string cname = coders[r];
                    if (rmap.has_key (cname)) {
                        string cid = rmap.get (cname).code_id;
                        if (!code_to_int.has_key (cid)) {
                            code_to_int.set (cid, next_code_int++);
                        }
                        kmat[r, u] = code_to_int.get (cid);
                    } else {
                        kmat[r, u] = -1;
                    }
                }
            }
            kripp_res = compute_krippendorff_alpha (kmat, m, u_cnt, IrrScaleType.NOMINAL);
        }

        public static IrrResult compute_workspace_fleiss_kappa (Gee.ArrayList<QualSpan> all_spans) {
            var coders_set = new Gee.TreeSet<string> ();
            var codes_set = new Gee.TreeSet<string> ();
            var unit_map = new Gee.HashMap<string, Gee.HashMap<string, string>> ();
            var unit_keys = new Gee.ArrayList<string> ();

            foreach (var sp in all_spans) {
                if (sp.coder_id == "" || sp.code_id == "") continue;
                coders_set.add (sp.coder_id);
                codes_set.add (sp.code_id);
                string ukey = @"$(sp.file_path):$(sp.line_start)";
                var rmap = unit_map.get (ukey);
                if (rmap == null) {
                    rmap = new Gee.HashMap<string, string> ();
                    unit_map.set (ukey, rmap);
                    unit_keys.add (ukey);
                }
                rmap.set (sp.coder_id, sp.code_id);
            }

            int m = coders_set.size;
            if (m < 2 || codes_set.size == 0) {
                return new IrrResult () { metric_name = "Fleiss' Kappa", interpretation = "Requires >= 2 coders" };
            }

            var code_idx = new Gee.HashMap<string, int> ();
            int k = 0;
            foreach (string c in codes_set) code_idx.set (c, k++);

            var complete_units = new Gee.ArrayList<string> ();
            foreach (string ukey in unit_keys) {
                if (unit_map.get (ukey).size == m) complete_units.add (ukey);
            }
            if (complete_units.size == 0) {
                return new IrrResult () { metric_name = "Fleiss' Kappa", n_raters = m, interpretation = "No complete multi-rater units" };
            }

            int[,] counts = new int[complete_units.size, k];
            for (int u = 0; u < complete_units.size; u++) {
                var rmap = unit_map.get (complete_units[u]);
                foreach (string cid in rmap.values) {
                    counts[u, code_idx.get (cid)] += 1;
                }
            }
            return compute_fleiss_kappa (counts, complete_units.size, k);
        }

        public static string format_quarto_summary_block (
            IrrResult cohen,
            IrrResult kripp,
            Gee.ArrayList<EnrichmentResult> enrichments,
            IrrResult? fleiss = null
        ) {
            var sb = new GLib.StringBuilder ();
            sb.append ("\n### Qualitative Biostatistical Reliability & Enrichment Summary\n\n");
            sb.append ("| Reliability Metric | Statistic | Observed ($p_o$) | Expected ($p_e$) | Units ($N$) | $p$-value | Benchmark |\n");
            sb.append ("| :--- | ---: | ---: | ---: | ---: | ---: | :--- |\n");
            sb.append_printf (
                "| **%s** | %.4f | %.4f | %.4f | %d | %.4g | %s |\n",
                cohen.metric_name, cohen.statistic, cohen.observed_agreement,
                cohen.expected_agreement, cohen.n_units, cohen.p_value, cohen.interpretation
            );
            if (fleiss != null && fleiss.n_units > 0) {
                sb.append_printf (
                    "| **%s** | %.4f | %.4f | %.4f | %d | %.4g | %s |\n",
                    fleiss.metric_name, fleiss.statistic, fleiss.observed_agreement,
                    fleiss.expected_agreement, fleiss.n_units, fleiss.p_value, fleiss.interpretation
                );
            }
            sb.append_printf (
                "| **%s** | %.4f | %.4f | %.4f | %d | — | %s |\n\n",
                kripp.metric_name, kripp.statistic, kripp.observed_agreement,
                kripp.expected_agreement, kripp.n_units, kripp.interpretation
            );

            if (enrichments.size > 0) {
                sb.append ("| Code Pair ($A \\times B$) | Co-Occurs ($a$) | Odds Ratio | Fisher Exact $p$ | $\\chi^2$ Statistic |\n");
                sb.append ("| :--- | ---: | ---: | ---: | ---: |\n");
                int max_rows = int.min (10, enrichments.size);
                for (int i = 0; i < max_rows; i++) {
                    var e = enrichments[i];
                    string or_str = (e.odds_ratio.is_infinity () != 0) ? "Inf" : "%.3f".printf (e.odds_ratio);
                    sb.append_printf (
                        "| `%s` × `%s` | %d | %s | %.4g | %.3f |\n",
                        e.code_a, e.code_b, e.a_both, or_str, e.fisher_p_two_sided, e.chi2_stat
                    );
                }
                sb.append ("\n: Inter-rater reliability and Fisher's Exact code co-occurrence enrichment {#tbl-qual-biostats}\n\n");
            }
            return sb.str;
        }

        public static string ensure_workspace_r_script (string workspace_dir) {
            string scripts_dir = GLib.Path.build_filename (workspace_dir, ".imladris", "scripts");
            GLib.DirUtils.create_with_parents (scripts_dir, 0755);
            string script_path = GLib.Path.build_filename (scripts_dir, "qual_stats.R");
            if (!GLib.FileUtils.test (script_path, GLib.FileTest.EXISTS)) {
                try {
                    GLib.FileUtils.set_contents (script_path, get_reference_r_script ());
                } catch (GLib.Error e) {}
            }
            return script_path;
        }

        public static string get_reference_r_script () {
            return """#!/usr/bin/env Rscript
# Imladris Qualitative Biostatistical Verification Bridge (.imladris/scripts/qual_stats.R)
# Computes Krippendorff's Alpha, Fisher's Exact Test, and Thematic Saturation Curves from .imladris-qual.db

args <- commandArgs(trailingOnly = TRUE)
db_path <- if (length(args) >= 1) args[1] else ".imladris-qual.db"

if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RSQLite", quietly = TRUE)) {
  stop("Install DBI and RSQLite to query .imladris-qual.db directly from R.")
}

con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(con), add = TRUE)

spans <- DBI::dbReadTable(con, "spans")
cat(sprintf("Loaded %d qualitative spans across %d coders.\n", nrow(spans), length(unique(spans$coder_id))))

if (nrow(spans) > 0 && requireNamespace("irr", quietly = TRUE)) {
  spans$unit <- paste(spans$file_path, spans$line_start, sep = ":")
  mat_df <- reshape(spans[, c("unit", "coder_id", "code_id")], idvar = "unit", timevar = "coder_id", direction = "wide")
  rating_mat <- t(as.matrix(mat_df[, -1, drop = FALSE]))
  ka <- irr::kripp.alpha(rating_mat, method = "nominal")
  cat(sprintf("Krippendorff's alpha (nominal): %.6f (units = %d, raters = %d)\n", ka$value, ka$subjects, ka$raters))
}

# Fisher's Exact Test & Thematic Saturation Curve
if (nrow(spans) > 0) {
  units <- ifelse(!is.na(spans$entity_id) & nzchar(spans$entity_id), spans$entity_id, spans$file_path)
  codes <- sort(unique(spans$code_id))
  all_units <- unique(units)
  if (length(codes) >= 2 && length(all_units) >= 2) {
    for (i in seq_len(length(codes) - 1)) {
      for (j in (i + 1):length(codes)) {
        has_a <- all_units %in% units[spans$code_id == codes[i]]
        has_b <- all_units %in% units[spans$code_id == codes[j]]
        tbl <- matrix(c(sum(has_a & has_b), sum(has_a & !has_b), sum(!has_a & has_b), sum(!has_a & !has_b)), nrow = 2, byrow = TRUE)
        ft <- stats::fisher.test(tbl, alternative = "two.sided")
        cat(sprintf("Fisher Exact [%s x %s]: co=%d, OR=%.4f, p=%.6g\n", codes[i], codes[j], tbl[1, 1], ft$estimate, ft$p.value))
      }
    }
  }
  docs <- unique(spans$file_path)
  seen <- character(0)
  sat <- data.frame(doc_idx = seq_along(docs), doc = basename(docs), cumulative_codes = integer(length(docs)))
  for (i in seq_along(docs)) {
    seen <- union(seen, spans$code_id[spans$file_path == docs[i]])
    sat$cumulative_codes[i] <- length(seen)
  }
  print(sat)
}
""";
        }
    }
}
