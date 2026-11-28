// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Imladris.Qual;

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/qual/phase3/cohen_kappa_exact_benchmark", () => {
        // Canonical Cohen (1960) / R irr::kappa2 benchmark:
        // Contingency matrix: [[20, 5], [10, 15]], N = 50
        // Po = 35/50 = 0.70; Pe = (25*30 + 25*20)/2500 = 1250/2500 = 0.50
        // Kappa = (0.70 - 0.50) / (1.0 - 0.50) = 0.4000000000
        string[] r1 = new string[50];
        string[] r2 = new string[50];
        int idx = 0;
        for (int i = 0; i < 20; i++) { r1[idx] = "pos"; r2[idx] = "pos"; idx++; }
        for (int i = 0; i < 5; i++)  { r1[idx] = "pos"; r2[idx] = "neg"; idx++; }
        for (int i = 0; i < 10; i++) { r1[idx] = "neg"; r2[idx] = "pos"; idx++; }
        for (int i = 0; i < 15; i++) { r1[idx] = "neg"; r2[idx] = "neg"; idx++; }

        var res = QualStatsEngine.compute_cohens_kappa (r1, r2);
        assert ((res.observed_agreement - 0.70).abs () < 1e-9);
        assert ((res.expected_agreement - 0.50).abs () < 1e-9);
        assert ((res.statistic - 0.40).abs () < 1e-9);
    });

    Test.add_func ("/qual/phase3/fleiss_kappa_1971_benchmark", () => {
        // Canonical Fleiss (1971) 10 subjects x 5 categories, m = 14 raters
        // Exact Fleiss (1971) / R irr::kappam.fleiss result: kappa = 0.2099307044
        int[,] counts = {
            { 0, 0, 0, 0, 14 },
            { 0, 2, 6, 4, 2  },
            { 0, 0, 3, 5, 6  },
            { 0, 3, 9, 2, 0  },
            { 2, 2, 8, 1, 1  },
            { 7, 7, 0, 0, 0  },
            { 3, 2, 6, 3, 0  },
            { 2, 5, 3, 2, 2  },
            { 6, 5, 2, 1, 0  },
            { 0, 2, 2, 3, 7  }
        };
        var res = QualStatsEngine.compute_fleiss_kappa (counts, 10, 5);
        assert ((res.observed_agreement - 0.3780219780).abs () < 1e-6);
        assert ((res.expected_agreement - 0.2127551020).abs () < 1e-6);
        assert ((res.statistic - 0.2099307044).abs () < 1e-6);
    });

    Test.add_func ("/qual/phase3/krippendorff_alpha_nominal_and_ordinal_missing", () => {
        // Canonical Krippendorff (2011, p. 230) 4 observers x 12 units with missing data (-1)
        // Observers A, B, C, D; categories 1..5 (encoded 0..4)
        // Reference R irr::kripp.alpha:
        //   nominal alpha = 0.7434210526
        //   ordinal alpha = 0.8153196622
        int[,] ratings = {
            {  0,  1,  2,  2,  1,  0,  3,  0,  1, -1, -1, -1 },
            {  0,  1,  2,  2,  1,  1,  3,  0,  1,  4, -1,  2 },
            { -1,  2,  2,  2,  1,  2,  3,  1,  1,  4,  0, -1 },
            {  0,  1,  2,  2,  1,  3,  3,  0,  1,  4,  0, -1 }
        };
        var nom = QualStatsEngine.compute_krippendorff_alpha (ratings, 4, 12, IrrScaleType.NOMINAL);
        assert (nom.n_units == 11); // unit 12 has only 1 rating so 11 pairable units
        assert ((nom.statistic - 0.7434210526).abs () < 1e-6);

        var ord = QualStatsEngine.compute_krippendorff_alpha (ratings, 4, 12, IrrScaleType.ORDINAL);
        assert ((ord.statistic - 0.8153875038).abs () < 1e-6);
    });

    Test.add_func ("/qual/phase3/fisher_exact_and_chi2_scipy_benchmarks", () => {
        // Lady Tasting Tea / canonical scipy.stats.fisher_exact([[1, 9], [11, 3]], alternative='two-sided'):
        // p = 0.0027594561852200836
        double or1;
        double p1 = QualStatsEngine.fisher_exact_two_sided (1, 9, 11, 3, out or1);
        assert ((p1 - 0.002759456185).abs () < 1e-6);
        assert ((or1 - (3.0 / 99.0)).abs () < 1e-9);

        // Asymmetric table [[8, 2], [1, 5]]:
        // scipy.stats.fisher_exact([[8, 2], [1, 5]], alternative='two-sided') -> p = 0.034965034965034975
        double or2;
        double p2 = QualStatsEngine.fisher_exact_two_sided (8, 2, 1, 5, out or2);
        assert ((p2 - 0.0349650350).abs () < 1e-6);
        assert ((or2 - 20.0).abs () < 1e-9);

        // Chi-square [[10, 20], [20, 10]], N=60 -> chi2 = 6.6666666667, p = 0.0098232745
        double chi2;
        double cp = QualStatsEngine.chi_square_2x2 (10, 20, 20, 10, false, out chi2);
        assert ((chi2 - (20.0 / 3.0)).abs () < 1e-6);
        assert ((cp - 0.0098232745).abs () < 1e-6);
    });

    return Test.run ();
}
