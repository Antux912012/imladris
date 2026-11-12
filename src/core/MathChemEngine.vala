// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Parses natural mathematical and chemical expressions and
 * converts them into LaTeX, mhchem, Markdown, Unicode, and offline HTML preview markup.
 *
 * Architectural Position:
 * Core domain parser and formatting engine in Imladris.Core.
 * Upstream callers: Imladris.UI.MathChemEditorDialog, Imladris.Adapters.DocumentAdapter,
 * and unit test suites.
 * Downstream dependencies: GLib, GLib.Regex.
 *
 * Concurrency Constraints:
 * Stateless transformation methods. Safe to call from the GLib MainContext thread.
 */

namespace Imladris.Core {

    /**
     * Domain mode for formula parsing.
     */
    public enum FormulaMode {
        MATH,
        CHEMISTRY,
        AUTO;

        /**
         * Return the human-readable label for the formula mode.
         *
         * @return Display label string.
         */
        public string to_label () {
            switch (this) {
                case MATH: return "Mathematics";
                case CHEMISTRY: return "Chemical Formula / Reaction";
                case AUTO: return "Auto-Detect";
                default: return "Mathematics";
            }
        }
    }

    /**
     * Target serialization format when inserting or saving a formula into a document.
     */
    public enum FormulaOutputFormat {
        LATEX_DISPLAY,
        LATEX_INLINE,
        LATEX_MHCHEM,
        LATEX_EQUATION,
        MARKDOWN_SUBSUP,
        MARKDOWN_UNICODE;

        /**
         * Return the human-readable description for the output format.
         *
         * @return Display label string.
         */
        public string to_label () {
            switch (this) {
                case LATEX_DISPLAY: return "LaTeX Display Block ($$ ... $$)";
                case LATEX_INLINE: return "LaTeX Inline ($ ... $)";
                case LATEX_MHCHEM: return "LaTeX Chemistry (\\ce{ ... })";
                case LATEX_EQUATION: return "LaTeX Numbered Equation (\\begin{equation})";
                case MARKDOWN_SUBSUP: return "Markdown Sub/Superscript (~sub~ / ^sup^)";
                case MARKDOWN_UNICODE: return "Markdown Unicode Scientific (H₂O / x²)";
                default: return "LaTeX Display Block ($$ ... $$)";
            }
        }
    }

    /**
     * Preset template entry for mathematical equations and chemical reactions.
     */
    public class FormulaPreset : GLib.Object {
        public string title { get; set; default = ""; }
        public string category { get; set; default = ""; }
        public string natural_input { get; set; default = ""; }
        public FormulaMode mode { get; set; default = FormulaMode.MATH; }
        public string description { get; set; default = ""; }

        /**
         * Create a new formula preset descriptor.
         *
         * @param title Short template name.
         * @param category Category identifier ("Math" or "Chemistry").
         * @param natural_input Natural expression string.
         * @param mode Target parser mode.
         * @param description Explanatory note.
         */
        public FormulaPreset (
            string title,
            string category,
            string natural_input,
            FormulaMode mode,
            string description
        ) {
            this.title = title;
            this.category = category;
            this.natural_input = natural_input;
            this.mode = mode;
            this.description = description;
        }
    }

    /**
     * Stateless parser and converter for natural math and chemical expressions.
     */
    public class MathChemEngine : GLib.Object {

        /**
         * Return built-in presets for common mathematical formulas and chemical reactions.
         *
         * @return ArrayList of FormulaPreset objects.
         */
        public static Gee.ArrayList<FormulaPreset> get_presets () {
            var list = new Gee.ArrayList<FormulaPreset> ();

            // Mathematics Presets
            list.add (new FormulaPreset (
                "Quadratic Formula",
                "Math",
                "x = (-b +- sqrt(b^2 - 4*a*c)) / (2*a)",
                FormulaMode.MATH,
                "Roots of a second-degree polynomial equation"
            ));
            list.add (new FormulaPreset (
                "Gaussian Normal Distribution",
                "Math",
                "f(x) = (1 / (sigma * sqrt(2*pi))) * exp(-((x - mu)^2) / (2*sigma^2))",
                FormulaMode.MATH,
                "Probability density function of the normal distribution"
            ));
            list.add (new FormulaPreset (
                "Definite Gaussian Integral",
                "Math",
                "int(0, inf) e^(-x^2) dx = sqrt(pi) / 2",
                FormulaMode.MATH,
                "Improper integral of the Gaussian function"
            ));
            list.add (new FormulaPreset (
                "Sample Standard Deviation",
                "Math",
                "s = sqrt((1 / (n - 1)) * sum(i=1, n) (x_i - bar(x))^2)",
                FormulaMode.MATH,
                "Unbiased estimator of population variance root"
            ));
            list.add (new FormulaPreset (
                "Bayes' Theorem",
                "Math",
                "P(A|B) = (P(B|A) * P(A)) / P(B)",
                FormulaMode.MATH,
                "Conditional probability inversion formula"
            ));
            list.add (new FormulaPreset (
                "Shannon Entropy",
                "Math",
                "H(X) = -sum(i=1, n) P(x_i) * log_2(P(x_i))",
                FormulaMode.MATH,
                "Information content measure in bits"
            ));
            list.add (new FormulaPreset (
                "Linear Transformation Matrix",
                "Math",
                "A = matrix([cos(theta), -sin(theta)], [sin(theta), cos(theta)])",
                FormulaMode.MATH,
                "Two-dimensional rotation matrix in Euclidean space"
            ));
            list.add (new FormulaPreset (
                "Partial Differential Wave Equation",
                "Math",
                "partial^2 u / partial t^2 = c^2 * nabla^2 u",
                FormulaMode.MATH,
                "Second-order linear wave propagation PDE"
            ));

            // Chemistry & Biochemistry Presets
            list.add (new FormulaPreset (
                "Photosynthesis Reaction",
                "Chemistry",
                "6CO2(g) + 6H2O(l) ->[h*nu][chlorophyll] C6H12O6(aq) + 6O2(g)",
                FormulaMode.CHEMISTRY,
                "Light-driven synthesis of glucose from carbon dioxide and water"
            ));
            list.add (new FormulaPreset (
                "Haber-Bosch Ammonia Synthesis",
                "Chemistry",
                "N2(g) + 3H2(g) <=>[Fe catalyst][450 C, 200 atm] 2NH3(g)",
                FormulaMode.CHEMISTRY,
                "Reversible catalytic nitrogen fixation equilibrium"
            ));
            list.add (new FormulaPreset (
                "Acetic Acid Dissociation",
                "Chemistry",
                "CH3COOH(aq) + H2O(l) <=> CH3COO^-(aq) + H3O^+(aq)",
                FormulaMode.CHEMISTRY,
                "Weak acid proton transfer equilibrium in aqueous solution"
            ));
            list.add (new FormulaPreset (
                "Silver Chloride Precipitation",
                "Chemistry",
                "Ag^+(aq) + Cl^-(aq) -> AgCl(v)",
                FormulaMode.CHEMISTRY,
                "Ionic precipitation forming insoluble solid"
            ));
            list.add (new FormulaPreset (
                "Carbonate Buffering System",
                "Chemistry",
                "CO2(g) + H2O(l) <=> H2CO3(aq) <=> HCO3^-(aq) + H^+(aq)",
                FormulaMode.CHEMISTRY,
                "Blood plasma and ocean bicarbonate buffer equilibrium"
            ));
            list.add (new FormulaPreset (
                "Redox Permanganate Titration",
                "Chemistry",
                "MnO4^-(aq) + 5Fe^2+(aq) + 8H^+(aq) -> Mn^2+(aq) + 5Fe^3+(aq) + 4H2O(l)",
                FormulaMode.CHEMISTRY,
                "Half-cell balanced oxidation-reduction reaction in acidic medium"
            ));
            list.add (new FormulaPreset (
                "Water Autoionization",
                "Chemistry",
                "2H2O(l) <=> H3O^+(aq) + OH^-(aq)",
                FormulaMode.CHEMISTRY,
                "Self-ionization equilibrium of water"
            ));
            list.add (new FormulaPreset (
                "Cellular Aerobic Respiration",
                "Chemistry",
                "C6H12O6(s) + 6O2(g) ->[enzymes] 6CO2(g) + 6H2O(l) + ATP",
                FormulaMode.CHEMISTRY,
                "Metabolic oxidation of glucose releasing chemical energy"
            ));

            return list;
        }

        /**
         * Detect whether a natural input string represents a chemical reaction/formula
         * or a mathematical expression.
         *
         * @param input Raw user input string.
         * @return Resolved FormulaMode (MATH or CHEMISTRY).
         */
        public static FormulaMode detect_mode (string input) {
            string s = input.strip ();
            if (s.length == 0) return FormulaMode.MATH;

            if (s.has_prefix ("\\ce{")) return FormulaMode.CHEMISTRY;

            // Check for chemical states of matter or reaction arrows with brackets
            if (s.contains ("(aq)") || s.contains ("(s)") || s.contains ("(l)") || s.contains ("(g)") ||
                s.contains ("(v)") || s.contains ("->[") || s.contains ("<=>")) {
                return FormulaMode.CHEMISTRY;
            }

            // Check for typical math keywords first
            string[] math_keywords = {
                "sqrt(", "int(", "sum(", "prod(", "lim(", "matrix(", "binom(",
                "sin(", "cos(", "tan(", "log(", "ln(", "exp(", "\\frac", "\\int",
                "\\sum", "sigma", "alpha", "beta", "theta", "pi", "nabla", "partial",
                "=", "<=", ">=", "!=", "+-"
            };
            foreach (string kw in math_keywords) {
                if (s.contains (kw)) {
                    return FormulaMode.MATH;
                }
            }

            // Check for chemical formula patterns like H2O, CO2, CH3, SO4^2-, NaOH, Fe2O3
            try {
                var chem_regex = new GLib.Regex ("\\b[0-9]*[A-Z][a-z]?[0-9]+([A-Z][a-z]?[0-9]*)*(\\^[0-9]*[+-])?\\b");
                if (chem_regex.match (s)) {
                    return FormulaMode.CHEMISTRY;
                }
                var ion_regex = new GLib.Regex ("\\b[A-Z][a-zA-Z0-9]*\\^[0-9]*[+-]");
                if (ion_regex.match (s)) {
                    return FormulaMode.CHEMISTRY;
                }
            } catch (GLib.RegexError e) {}

            return FormulaMode.MATH;
        }

        /**
         * Convert natural input into the target output format for insertion or file saving.
         *
         * @param natural_input User-written natural formula or reaction.
         * @param mode Formula parsing mode (MATH, CHEMISTRY, or AUTO).
         * @param format Target serialization format (LaTeX or Markdown variants).
         * @return Formatted string ready for document insertion.
         */
        public static string convert (
            string natural_input,
            FormulaMode mode,
            FormulaOutputFormat format
        ) {
            string trimmed = natural_input.strip ();
            if (trimmed.length == 0) return "";

            FormulaMode effective_mode = (mode == FormulaMode.AUTO) ? detect_mode (trimmed) : mode;

            // Strip outer wrappers if the user pasted an already-wrapped expression
            string clean_input = strip_outer_delimiters (trimmed);

            switch (format) {
                case FormulaOutputFormat.LATEX_DISPLAY:
                    string body = (effective_mode == FormulaMode.CHEMISTRY)
                        ? natural_chem_to_latex (clean_input)
                        : natural_math_to_latex (clean_input);
                    return "$$\n" + body + "\n$$";

                case FormulaOutputFormat.LATEX_INLINE:
                    string body = (effective_mode == FormulaMode.CHEMISTRY)
                        ? natural_chem_to_latex (clean_input)
                        : natural_math_to_latex (clean_input);
                    return "$" + body + "$";

                case FormulaOutputFormat.LATEX_MHCHEM:
                    string mhchem = natural_chem_to_mhchem (clean_input);
                    return "$$\\ce{" + mhchem + "}$$";

                case FormulaOutputFormat.LATEX_EQUATION:
                    string body = (effective_mode == FormulaMode.CHEMISTRY)
                        ? natural_chem_to_latex (clean_input)
                        : natural_math_to_latex (clean_input);
                    return "\\begin{equation}\n  " + body + "\n\\end{equation}";

                case FormulaOutputFormat.MARKDOWN_SUBSUP:
                    return (effective_mode == FormulaMode.CHEMISTRY)
                        ? natural_chem_to_markdown (clean_input, false)
                        : natural_math_to_markdown (clean_input, false);

                case FormulaOutputFormat.MARKDOWN_UNICODE:
                    return (effective_mode == FormulaMode.CHEMISTRY)
                        ? natural_chem_to_markdown (clean_input, true)
                        : natural_math_to_markdown (clean_input, true);

                default:
                    string body = natural_math_to_latex (clean_input);
                    return "$$\n" + body + "\n$$";
            }
        }

        /**
         * Remove surrounding $$, $, or \ce{} delimiters from an input string.
         *
         * @param input Raw string.
         * @return Unwrapped inner content.
         */
        public static string strip_outer_delimiters (string input) {
            string s = input.strip ();
            if (s.has_prefix ("$$") && s.has_suffix ("$$") && s.length >= 4) {
                s = s.substring (2, s.length - 4).strip ();
            } else if (s.has_prefix ("$") && s.has_suffix ("$") && s.length >= 2) {
                s = s.substring (1, s.length - 2).strip ();
            }
            if (s.has_prefix ("\\ce{") && s.has_suffix ("}") && s.length >= 5) {
                s = s.substring (4, s.length - 5).strip ();
            }
            return s;
        }

        // =====================================================================
        // NATURAL MATH TO LATEX CONVERTER
        // =====================================================================

        /**
         * Convert a natural mathematical expression into standard LaTeX math syntax.
         *
         * @param input Natural math string (e.g. "(-b +- sqrt(b^2 - 4*a*c)) / (2*a)").
         * @return LaTeX math string (e.g. "\frac{-b \pm \sqrt{b^{2} - 4 \cdot a \cdot c}}{2 \cdot a}").
         */
        public static string natural_math_to_latex (string input) {
            string s = input.strip ();
            if (s.length == 0) return "";

            // 1. Expand matrix([[a, b], [c, d]]) or matrix([a, b], [c, d])
            s = expand_matrices (s);

            // 2. Expand structured calculus / algebraic functions:
            // int(a, b), sum(a, b), prod(a, b), lim(a), root(n, x), cbrt(x), sqrt(x), frac(a, b), binom(n, k)
            s = expand_two_arg_func (s, "int", "\\int_{", "}^{", "}");
            s = expand_two_arg_func (s, "integral", "\\int_{", "}^{", "}");
            s = expand_two_arg_func (s, "sum", "\\sum_{", "}^{", "}");
            s = expand_two_arg_func (s, "prod", "\\prod_{", "}^{", "}");
            s = expand_two_arg_func (s, "frac", "\\frac{", "}{", "}");
            s = expand_two_arg_func (s, "binom", "\\binom{", "}{", "}");
            s = expand_two_arg_func (s, "root", "\\sqrt[", "]{", "}");

            s = expand_one_arg_func (s, "lim", "\\lim_{", "}");
            s = expand_one_arg_func (s, "sqrt", "\\sqrt{", "}");
            s = expand_one_arg_func (s, "cbrt", "\\sqrt[3]{", "}");
            s = expand_one_arg_func (s, "vec", "\\vec{", "}");
            s = expand_one_arg_func (s, "hat", "\\hat{", "}");
            s = expand_one_arg_func (s, "bar", "\\bar{", "}");
            s = expand_one_arg_func (s, "abs", "\\left|", "\\right|");
            s = expand_one_arg_func (s, "norm", "\\left\\|", "\\right\\|");

            // 3. Convert derivative shorthands before general fraction expansion
            s = s.replace ("partial^2 / partial", "\\frac{\\partial^2}{\\partial}");
            try {
                var pderiv2_rx = new GLib.Regex ("partial\\^2\\s*([a-zA-Z0-9_]+)\\s*/\\s*partial\\s*([a-zA-Z0-9_]+)\\^2");
                s = pderiv2_rx.replace (s, -1, 0, "\\\\frac{\\\\partial^2 \\1}{\\\\partial \\2^2}");

                var pderiv_rx = new GLib.Regex ("partial\\s*([a-zA-Z0-9_]*)\\s*/\\s*partial\\s*([a-zA-Z0-9_]+)");
                s = pderiv_rx.replace (s, -1, 0, "\\\\frac{\\\\partial \\1}{\\\\partial \\2}");

                var dderiv_rx = new GLib.Regex ("\\bd([a-zA-Z0-9_]*)\\s*/\\s*d([a-zA-Z0-9_]+)\\b");
                s = dderiv_rx.replace (s, -1, 0, "\\\\frac{d\\1}{d\\2}");
            } catch (GLib.RegexError e) {}

            // 4. Convert natural division (a) / (b) and token / token into \frac{a}{b}
            s = convert_natural_fractions (s);

            // 5. Convert parenthesized exponents x^(a+b) -> x^{a+b} and subscripts x_(i,j) -> x_{i,j}
            s = convert_script_groups (s, '^');
            s = convert_script_groups (s, '_');

            // 6. Convert multi-character simple exponents/subscripts: x^2 -> x^{2}, x_i -> x_{i}
            try {
                var exp_rx = new GLib.Regex ("\\^([+-]?[a-zA-Z0-9]+)");
                s = exp_rx.replace (s, -1, 0, "^{\\1}");

                var sub_rx = new GLib.Regex ("_([a-zA-Z0-9]+)");
                s = sub_rx.replace (s, -1, 0, "_{\\1}");
            } catch (GLib.RegexError e) {}

            // 7. Replace multi-character relational and arrow operators
            s = s.replace ("<=>", "\\iff ");
            s = s.replace ("<->", "\\leftrightarrow ");
            s = s.replace ("=>", "\\implies ");
            s = s.replace ("->", "\\to ");
            s = s.replace ("<-", "\\leftarrow ");
            s = s.replace ("+-", "\\pm ");
            s = s.replace ("-+", "\\mp ");
            s = s.replace ("!=", "\\neq ");
            s = s.replace ("<=", "\\leq ");
            s = s.replace (">=", "\\geq ");
            s = s.replace ("~=", "\\approx ");
            s = s.replace ("==", "\\equiv ");
            s = s.replace ("*", " \\cdot ");

            // 8. Replace Greek letter names and mathematical constants/functions
            s = replace_math_identifiers (s);

            // Clean up redundant whitespace
            try {
                var ws_rx = new GLib.Regex ("  +");
                s = ws_rx.replace (s, -1, 0, " ");
            } catch (GLib.RegexError e) {}

            return s.strip ();
        }

        /**
         * Expand matrix([a, b], [c, d]) into LaTeX pmatrix environment.
         */
        private static string expand_matrices (string input) {
            string s = input;
            int idx = s.index_of ("matrix(");
            while (idx >= 0) {
                int open_p = idx + 6;
                int close_p = find_matching_delimiter (s, open_p, '(', ')');
                if (close_p < 0) break;

                string inner = s.substring (open_p + 1, close_p - open_p - 1).strip ();
                var rows = new Gee.ArrayList<string> ();

                // Parse [r1], [r2] or r1; r2
                if (inner.contains ("[")) {
                    int pos = 0;
                    while (pos < inner.length) {
                        int b_start = inner.index_of ("[", pos);
                        if (b_start < 0) break;
                        int b_end = find_matching_delimiter (inner, b_start, '[', ']');
                        if (b_end < 0) break;
                        string row_content = inner.substring (b_start + 1, b_end - b_start - 1);
                        string[] cells = row_content.split (",");
                        var cell_list = new Gee.ArrayList<string> ();
                        foreach (string c in cells) {
                            cell_list.add (natural_math_to_latex (c.strip ()));
                        }
                        rows.add (string.joinv (" & ", cell_list.to_array ()));
                        pos = b_end + 1;
                    }
                } else {
                    string[] raw_rows = inner.split (";");
                    foreach (string r in raw_rows) {
                        string[] cells = r.split (",");
                        var cell_list = new Gee.ArrayList<string> ();
                        foreach (string c in cells) {
                            cell_list.add (natural_math_to_latex (c.strip ()));
                        }
                        rows.add (string.joinv (" & ", cell_list.to_array ()));
                    }
                }

                string matrix_latex = "\\begin{pmatrix} " + string.joinv (" \\\\ ", rows.to_array ()) + " \\end{pmatrix}";
                s = s.substring (0, idx) + matrix_latex + s.substring (close_p + 1);
                idx = s.index_of ("matrix(");
            }
            return s;
        }

        /**
         * Expand two-argument natural syntax func(arg1, arg2) into LaTeX prefix + arg1 + mid + arg2 + suffix.
         */
        private static string expand_two_arg_func (
            string input,
            string func_name,
            string prefix,
            string mid,
            string suffix
        ) {
            string s = input;
            string token = func_name + "(";
            int search_from = 0;

            while (search_from < s.length) {
                int idx = s.index_of (token, search_from);
                if (idx < 0) break;

                // Ensure not preceded by backslash or alphanumeric character
                if (idx > 0 && (s[idx - 1] == '\\' || s[idx - 1].isalnum ())) {
                    search_from = idx + token.length;
                    continue;
                }

                int open_p = idx + func_name.length;
                int close_p = find_matching_delimiter (s, open_p, '(', ')');
                if (close_p < 0) break;

                string inner = s.substring (open_p + 1, close_p - open_p - 1);
                int comma_idx = find_top_level_comma (inner);
                if (comma_idx >= 0) {
                    string arg1 = natural_math_to_latex (inner.substring (0, comma_idx).strip ());
                    string arg2 = natural_math_to_latex (inner.substring (comma_idx + 1).strip ());
                    string replacement = prefix + arg1 + mid + arg2 + suffix;
                    s = s.substring (0, idx) + replacement + s.substring (close_p + 1);
                    search_from = idx + replacement.length;
                } else {
                    search_from = close_p + 1;
                }
            }
            return s;
        }

        /**
         * Expand single-argument natural syntax func(arg) into LaTeX prefix + arg + suffix.
         */
        private static string expand_one_arg_func (
            string input,
            string func_name,
            string prefix,
            string suffix
        ) {
            string s = input;
            string token = func_name + "(";
            int search_from = 0;

            while (search_from < s.length) {
                int idx = s.index_of (token, search_from);
                if (idx < 0) break;

                if (idx > 0 && (s[idx - 1] == '\\' || s[idx - 1].isalnum ())) {
                    search_from = idx + token.length;
                    continue;
                }

                int open_p = idx + func_name.length;
                int close_p = find_matching_delimiter (s, open_p, '(', ')');
                if (close_p < 0) break;

                string inner = natural_math_to_latex (s.substring (open_p + 1, close_p - open_p - 1).strip ());
                string replacement = prefix + inner + suffix;
                s = s.substring (0, idx) + replacement + s.substring (close_p + 1);
                search_from = idx + replacement.length;
            }
            return s;
        }

        /**
         * Convert parenthesized script groups like ^(a+b) or _(i+1) into ^{a+b} and _{i+1}.
         */
        private static string convert_script_groups (string input, char op) {
            string s = input;
            string pat = @"$op(";
            int idx = s.index_of (pat);
            while (idx >= 0) {
                int open_p = idx + 1;
                int close_p = find_matching_delimiter (s, open_p, '(', ')');
                if (close_p < 0) break;

                string inner = natural_math_to_latex (s.substring (open_p + 1, close_p - open_p - 1));
                s = s.substring (0, idx) + @"$op{$inner}" + s.substring (close_p + 1);
                idx = s.index_of (pat);
            }
            return s;
        }

        /**
         * Convert natural division (num) / (den) and a / b into \frac{num}{den}.
         */
        private static string convert_natural_fractions (string input) {
            string s = input;
            int search_pos = 0;

            while (search_pos < s.length) {
                int slash = s.index_of ("/", search_pos);
                if (slash <= 0 || slash >= s.length - 1) break;

                // Extract numerator to the left of slash
                int left_end = slash - 1;
                while (left_end >= 0 && s[left_end] == ' ') left_end--;
                if (left_end < 0) {
                    search_pos = slash + 1;
                    continue;
                }

                int left_start = left_end;
                string num_str = "";
                if (s[left_end] == ')') {
                    left_start = find_matching_delimiter_backward (s, left_end, '(', ')');
                    if (left_start < 0) {
                        search_pos = slash + 1;
                        continue;
                    }
                    // Check if preceded by function name like sin(x)/y
                    int fn_start = left_start;
                    while (fn_start > 0 && (s[fn_start - 1].isalnum () || s[fn_start - 1] == '\\')) {
                        fn_start--;
                    }
                    if (fn_start < left_start) {
                        left_start = fn_start;
                        num_str = s.substring (left_start, left_end - left_start + 1);
                    } else {
                        num_str = s.substring (left_start + 1, left_end - left_start - 1);
                    }
                } else if (s[left_end] == '}') {
                    left_start = find_matching_delimiter_backward (s, left_end, '{', '}');
                    if (left_start < 0) {
                        search_pos = slash + 1;
                        continue;
                    }
                    while (left_start > 0 && (s[left_start - 1].isalnum () || s[left_start - 1] == '\\' || s[left_start - 1] == '^' || s[left_start - 1] == '_')) {
                        left_start--;
                    }
                    num_str = s.substring (left_start, left_end - left_start + 1);
                } else {
                    while (left_start > 0 && (s[left_start - 1].isalnum () || s[left_start - 1] == '_' || s[left_start - 1] == '^' || s[left_start - 1] == '\\' || s[left_start - 1] == '.')) {
                        left_start--;
                    }
                    num_str = s.substring (left_start, left_end - left_start + 1);
                }

                if (num_str.strip ().length == 0) {
                    search_pos = slash + 1;
                    continue;
                }

                // Extract denominator to the right of slash
                int right_start = slash + 1;
                while (right_start < s.length && s[right_start] == ' ') right_start++;
                if (right_start >= s.length) break;

                int right_end = right_start;
                string den_str = "";
                if (s[right_start] == '(') {
                    right_end = find_matching_delimiter (s, right_start, '(', ')');
                    if (right_end < 0) {
                        search_pos = slash + 1;
                        continue;
                    }
                    den_str = s.substring (right_start + 1, right_end - right_start - 1);
                } else {
                    while (right_end < s.length && (s[right_end].isalnum () || s[right_end] == '_' || s[right_end] == '^' || s[right_end] == '\\' || s[right_end] == '.' || s[right_end] == '{' || s[right_end] == '}')) {
                        if (s[right_end] == '(') {
                            int sub_close = find_matching_delimiter (s, right_end, '(', ')');
                            if (sub_close > right_end) {
                                right_end = sub_close + 1;
                                break;
                            }
                        }
                        right_end++;
                    }
                    right_end--;
                    den_str = s.substring (right_start, right_end - right_start + 1);
                }

                if (den_str.strip ().length == 0) {
                    search_pos = slash + 1;
                    continue;
                }

                string clean_num = natural_math_to_latex (num_str.strip ());
                string clean_den = natural_math_to_latex (den_str.strip ());
                string frac = @"\\frac{$clean_num}{$clean_den}";
                s = s.substring (0, left_start) + frac + s.substring (right_end + 1);
                search_pos = left_start + frac.length;
            }

            return s;
        }

        /**
         * Replace natural Greek letter names and math function names with LaTeX commands.
         */
        private static string replace_math_identifiers (string input) {
            string s = input;
            string[,] tokens = {
                { "infinity", "\\infty" },
                { "inf", "\\infty" },
                { "alpha", "\\alpha" },
                { "beta", "\\beta" },
                { "gamma", "\\gamma" },
                { "delta", "\\delta" },
                { "epsilon", "\\epsilon" },
                { "varepsilon", "\\varepsilon" },
                { "zeta", "\\zeta" },
                { "eta", "\\eta" },
                { "theta", "\\theta" },
                { "iota", "\\iota" },
                { "kappa", "\\kappa" },
                { "lambda", "\\lambda" },
                { "mu", "\\mu" },
                { "nu", "\\nu" },
                { "xi", "\\xi" },
                { "pi", "\\pi" },
                { "rho", "\\rho" },
                { "sigma", "\\sigma" },
                { "tau", "\\tau" },
                { "upsilon", "\\upsilon" },
                { "phi", "\\phi" },
                { "varphi", "\\varphi" },
                { "chi", "\\chi" },
                { "psi", "\\psi" },
                { "omega", "\\omega" },
                { "Gamma", "\\Gamma" },
                { "Delta", "\\Delta" },
                { "Theta", "\\Theta" },
                { "Lambda", "\\Lambda" },
                { "Xi", "\\Xi" },
                { "Pi", "\\Pi" },
                { "Sigma", "\\Sigma" },
                { "Phi", "\\Phi" },
                { "Psi", "\\Psi" },
                { "Omega", "\\Omega" },
                { "nabla", "\\nabla" },
                { "partial", "\\partial" },
                { "forall", "\\forall" },
                { "exists", "\\exists" },
                { "notin", "\\notin" },
                { "subset", "\\subset" },
                { "subseteq", "\\subseteq" },
                { "union", "\\cup" },
                { "intersect", "\\cap" },
                { "approx", "\\approx" },
                { "propto", "\\propto" },
                { "times", "\\times" },
                { "cdot", "\\cdot" },
                { "arcsin", "\\arcsin" },
                { "arccos", "\\arccos" },
                { "arctan", "\\arctan" },
                { "sinh", "\\sinh" },
                { "cosh", "\\cosh" },
                { "tanh", "\\tanh" },
                { "sin", "\\sin" },
                { "cos", "\\cos" },
                { "tan", "\\tan" },
                { "log", "\\log" },
                { "ln", "\\ln" },
                { "exp", "\\exp" },
                { "det", "\\det" },
                { "min", "\\min" },
                { "max", "\\max" }
            };

            try {
                for (int i = 0; i < tokens.length[0]; i++) {
                    string word = tokens[i, 0];
                    string repl = tokens[i, 1].replace ("\\", "\\\\");
                    var rx = new GLib.Regex (@"(?<!\\\\)\\b$word\\b");
                    s = rx.replace (s, -1, 0, repl);
                }
            } catch (GLib.RegexError e) {}

            return s;
        }

        // =====================================================================
        // NATURAL CHEMISTRY TO LATEX & MHCHEM CONVERTER
        // =====================================================================

        /**
         * Normalize a natural chemical formula or reaction into mhchem \ce{...} inner syntax.
         *
         * @param input Natural chemical reaction (e.g. "2H2 + O2 -> 2H2O").
         * @return Normalized mhchem content.
         */
        public static string natural_chem_to_mhchem (string input) {
            string s = input.strip ();
            s = s.replace ("(v)", " v");
            s = s.replace ("(down)", " v");
            s = s.replace ("(^)", " ^");
            s = s.replace ("(up)", " ^");
            s = s.replace ("h*nu", "h\\nu");
            return s;
        }

        /**
         * Convert a natural chemical formula or reaction into standard LaTeX math syntax
         * that renders everywhere without requiring the external mhchem TeX package.
         *
         * @param input Natural chemical formula or reaction string.
         * @return Standard LaTeX string with \text{}, subscripts, superscripts, and reaction arrows.
         */
        public static string natural_chem_to_latex (string input) {
            string s = input.strip ();
            if (s.length == 0) return "";

            var out_sb = new GLib.StringBuilder ();
            int i = 0;
            int len = s.length;

            while (i < len) {
                // Skip whitespace and preserve single space
                if (s[i] == ' ' || s[i] == '\t') {
                    out_sb.append (" ");
                    while (i < len && (s[i] == ' ' || s[i] == '\t')) i++;
                    continue;
                }

                // 1. Check for Reaction Arrows: <=>[above][below], ->[above][below], <-->[...], <->, <-
                if (s.substring (i).has_prefix ("<=>") || s.substring (i).has_prefix ("<-->") ||
                    s.substring (i).has_prefix ("<->") || s.substring (i).has_prefix ("->") ||
                    s.substring (i).has_prefix ("<-")) {
                    string arrow_type = "->";
                    if (s.substring (i).has_prefix ("<-->")) {
                        arrow_type = "<=>";
                        i += 4;
                    } else if (s.substring (i).has_prefix ("<=>")) {
                        arrow_type = "<=>";
                        i += 3;
                    } else if (s.substring (i).has_prefix ("<->")) {
                        arrow_type = "<->";
                        i += 3;
                    } else if (s.substring (i).has_prefix ("->")) {
                        arrow_type = "->";
                        i += 2;
                    } else {
                        arrow_type = "<-";
                        i += 2;
                    }

                    string above = "";
                    string below = "";
                    if (i < len && s[i] == '[') {
                        int close1 = find_matching_delimiter (s, i, '[', ']');
                        if (close1 > i) {
                            above = format_arrow_condition_latex (s.substring (i + 1, close1 - i - 1));
                            i = close1 + 1;
                            if (i < len && s[i] == '[') {
                                int close2 = find_matching_delimiter (s, i, '[', ']');
                                if (close2 > i) {
                                    below = format_arrow_condition_latex (s.substring (i + 1, close2 - i - 1));
                                    i = close2 + 1;
                                }
                            }
                        }
                    }

                    if (arrow_type == "<=>") {
                        if (above != "" && below != "") {
                            out_sb.append (@"\\underset{$below}{\\overset{$above}{\\rightleftharpoons}}");
                        } else if (above != "") {
                            out_sb.append (@"\\overset{$above}{\\rightleftharpoons}");
                        } else {
                            out_sb.append ("\\rightleftharpoons");
                        }
                    } else if (arrow_type == "<->") {
                        out_sb.append ("\\leftrightarrow");
                    } else if (arrow_type == "<-") {
                        out_sb.append ("\\leftarrow");
                    } else {
                        if (above != "" && below != "") {
                            out_sb.append (@"\\xrightarrow[$below]{$above}");
                        } else if (above != "") {
                            out_sb.append (@"\\xrightarrow{$above}");
                        } else {
                            out_sb.append ("\\rightarrow");
                        }
                    }
                    continue;
                }

                // 2. Check for state of matter or precipitate/gas symbols: (s), (l), (g), (aq), (v), (^)
                if (s[i] == '(') {
                    int close_p = find_matching_delimiter (s, i, '(', ')');
                    if (close_p > i) {
                        string inner_p = s.substring (i + 1, close_p - i - 1).strip ();
                        if (inner_p == "s" || inner_p == "l" || inner_p == "g" || inner_p == "aq") {
                            out_sb.append (@"_{\\text{($inner_p)}}");
                            i = close_p + 1;
                            continue;
                        } else if (inner_p == "v" || inner_p == "down") {
                            out_sb.append ("\\downarrow");
                            i = close_p + 1;
                            continue;
                        } else if (inner_p == "^" || inner_p == "up") {
                            out_sb.append ("\\uparrow");
                            i = close_p + 1;
                            continue;
                        }
                    }
                }

                // 3. Check for explicit charge ^2-, ^3+, ^+, ^-
                if (s[i] == '^') {
                    i++;
                    int c_start = i;
                    if (i < len && s[i] == '{') {
                        int close_b = find_matching_delimiter (s, i, '{', '}');
                        if (close_b > i) {
                            string charge = s.substring (i + 1, close_b - i - 1);
                            out_sb.append (@"^{$charge}");
                            i = close_b + 1;
                            continue;
                        }
                    }
                    while (i < len && (s[i].isdigit () || s[i] == '+' || s[i] == '-')) {
                        i++;
                    }
                    string charge = s.substring (c_start, i - c_start);
                    if (charge.length > 0) {
                        out_sb.append (@"^{$charge}");
                    }
                    continue;
                }

                // 4. Check for hydrate dot '*'
                if (s[i] == '*') {
                    out_sb.append (" \\cdot ");
                    i++;
                    continue;
                }

                // 5. Check for chemical element symbol(s) [A-Z][A-Za-z]* followed by optional subscript digits
                if (s[i].isupper ()) {
                    int el_start = i;
                    i++;
                    while (i < len && s[i].isalpha ()) i++;
                    string el = s.substring (el_start, i - el_start);
                    out_sb.append (@"\\text{$el}");

                    // Subscript digits immediately following element
                    if (i < len && s[i].isdigit ()) {
                        int d_start = i;
                        while (i < len && s[i].isdigit ()) i++;
                        string digits = s.substring (d_start, i - d_start);
                        out_sb.append (@"_{$digits}");
                    }
                    continue;
                }

                // 6. Closing parenthesis followed by subscript digits e.g. Ca(OH)2
                if (s[i] == ')') {
                    out_sb.append (")");
                    i++;
                    if (i < len && s[i].isdigit ()) {
                        int d_start = i;
                        while (i < len && s[i].isdigit ()) i++;
                        string digits = s.substring (d_start, i - d_start);
                        out_sb.append (@"_{$digits}");
                    }
                    continue;
                }

                // Default character (stoichiometric coefficient, +, =, (, etc.)
                out_sb.append_c (s[i]);
                i++;
            }

            return out_sb.str.strip ();
        }

        private static string format_arrow_condition_latex (string cond) {
            string c = cond.strip ();
            if (c == "Delta" || c == "heat") return "\\Delta";
            if (c == "h*nu" || c == "h\\nu" || c == "light") return "h\\nu";
            return @"\\text{$c}";
        }

        // =====================================================================
        // MARKDOWN & UNICODE CONVERTERS
        // =====================================================================

        /**
         * Convert natural chemistry into Markdown (~sub~ / ^sup^) or Unicode notation.
         *
         * @param input Natural chemical reaction or formula.
         * @param use_unicode_digits True for Unicode subscripts/superscripts (H₂O), false for Pandoc (~2~).
         * @return Formatted Markdown string.
         */
        public static string natural_chem_to_markdown (string input, bool use_unicode_digits) {
            string s = input.strip ();
            if (s.length == 0) return "";

            var out_sb = new GLib.StringBuilder ();
            int i = 0;
            int len = s.length;

            while (i < len) {
                if (s.substring (i).has_prefix ("<=>") || s.substring (i).has_prefix ("<-->")) {
                    i += s.substring (i).has_prefix ("<-->") ? 4 : 3;
                    string cond = extract_bracket_conditions_markdown (s, ref i);
                    out_sb.append (cond != "" ? @" ⇌ [$cond] " : " ⇌ ");
                    continue;
                }
                if (s.substring (i).has_prefix ("<->")) {
                    i += 3;
                    out_sb.append (" ↔ ");
                    continue;
                }
                if (s.substring (i).has_prefix ("->")) {
                    i += 2;
                    string cond = extract_bracket_conditions_markdown (s, ref i);
                    out_sb.append (cond != "" ? @" → [$cond] " : " → ");
                    continue;
                }
                if (s.substring (i).has_prefix ("<-")) {
                    i += 2;
                    out_sb.append (" ← ");
                    continue;
                }

                if (s[i] == '(') {
                    int close_p = find_matching_delimiter (s, i, '(', ')');
                    if (close_p > i) {
                        string inner_p = s.substring (i + 1, close_p - i - 1).strip ();
                        if (inner_p == "v" || inner_p == "down") {
                            out_sb.append ("↓");
                            i = close_p + 1;
                            continue;
                        } else if (inner_p == "^" || inner_p == "up") {
                            out_sb.append ("↑");
                            i = close_p + 1;
                            continue;
                        }
                    }
                }

                if (s[i] == '^') {
                    i++;
                    int c_start = i;
                    while (i < len && (s[i].isdigit () || s[i] == '+' || s[i] == '-')) i++;
                    string charge = s.substring (c_start, i - c_start);
                    if (charge.length > 0) {
                        out_sb.append (use_unicode_digits ? to_unicode_superscript (charge) : @"^$charge^");
                    }
                    continue;
                }

                if (s[i].isupper ()) {
                    int el_start = i;
                    i++;
                    while (i < len && s[i].islower ()) i++;
                    out_sb.append (s.substring (el_start, i - el_start));

                    if (i < len && s[i].isdigit ()) {
                        int d_start = i;
                        while (i < len && s[i].isdigit ()) i++;
                        string digits = s.substring (d_start, i - d_start);
                        out_sb.append (use_unicode_digits ? to_unicode_subscript (digits) : @"~$digits~");
                    }
                    continue;
                }

                if (s[i] == ')') {
                    out_sb.append (")");
                    i++;
                    if (i < len && s[i].isdigit ()) {
                        int d_start = i;
                        while (i < len && s[i].isdigit ()) i++;
                        string digits = s.substring (d_start, i - d_start);
                        out_sb.append (use_unicode_digits ? to_unicode_subscript (digits) : @"~$digits~");
                    }
                    continue;
                }

                if (s[i] == '*') {
                    out_sb.append ("·");
                    i++;
                    continue;
                }

                out_sb.append_c (s[i]);
                i++;
            }

            try {
                var ws_rx = new GLib.Regex ("  +");
                return ws_rx.replace (out_sb.str, -1, 0, " ").strip ();
            } catch (GLib.RegexError e) {
                return out_sb.str.strip ();
            }
        }

        private static string extract_bracket_conditions_markdown (string s, ref int i) {
            string above = "";
            string below = "";
            int len = s.length;
            if (i < len && s[i] == '[') {
                int c1 = find_matching_delimiter (s, i, '[', ']');
                if (c1 > i) {
                    above = s.substring (i + 1, c1 - i - 1).replace ("h*nu", "hν").replace ("Delta", "Δ");
                    i = c1 + 1;
                    if (i < len && s[i] == '[') {
                        int c2 = find_matching_delimiter (s, i, '[', ']');
                        if (c2 > i) {
                            below = s.substring (i + 1, c2 - i - 1);
                            i = c2 + 1;
                        }
                    }
                }
            }
            if (above != "" && below != "") return @"$above / $below";
            return above;
        }

        /**
         * Convert natural mathematics into Markdown (~sub~ / ^sup^) or Unicode notation.
         *
         * @param input Natural mathematical expression.
         * @param use_unicode_digits True for Unicode superscripts/subscripts, false for Pandoc (~sub~, ^sup^).
         * @return Formatted Markdown string.
         */
        public static string natural_math_to_markdown (string input, bool use_unicode_digits) {
            string s = input.strip ();
            if (s.length == 0) return "";

            s = s.replace ("+-", "±");
            s = s.replace ("-+", "∓");
            s = s.replace ("!=", "≠");
            s = s.replace ("<=", "≤");
            s = s.replace (">=", "≥");
            s = s.replace ("~=", "≈");
            s = s.replace ("==", "≡");
            s = s.replace ("<=>", "⇔");
            s = s.replace ("=>", "⇒");
            s = s.replace ("->", "→");
            s = s.replace ("*", "·");
            s = s.replace ("sqrt(", "√(");
            s = s.replace ("cbrt(", "∛(");

            string[,] greek_unicode = {
                { "infinity", "∞" }, { "inf", "∞" },
                { "alpha", "α" }, { "beta", "β" }, { "gamma", "γ" }, { "delta", "δ" },
                { "epsilon", "ε" }, { "theta", "θ" }, { "lambda", "λ" }, { "mu", "μ" },
                { "pi", "π" }, { "sigma", "σ" }, { "tau", "τ" }, { "phi", "φ" },
                { "omega", "ω" }, { "Gamma", "Γ" }, { "Delta", "Δ" }, { "Theta", "Θ" },
                { "Lambda", "Λ" }, { "Pi", "Π" }, { "Sigma", "Σ" }, { "Omega", "Ω" },
                { "nabla", "∇" }, { "partial", "∂" }, { "int", "∫" }, { "sum", "∑" }, { "prod", "∏" }
            };

            try {
                for (int i = 0; i < greek_unicode.length[0]; i++) {
                    string word = greek_unicode[i, 0];
                    string sym = greek_unicode[i, 1];
                    var rx = new GLib.Regex (@"\\b$word\\b");
                    s = rx.replace (s, -1, 0, sym);
                }

                // Convert ^(...) and _(...)
                var exp_grp = new GLib.Regex ("\\^\\(([^\\)]+)\\)");
                s = exp_grp.replace_eval (s, -1, 0, 0, (mi, res) => {
                    string val = mi.fetch (1);
                    res.append (use_unicode_digits ? to_unicode_superscript (val) : @"^$val^");
                    return false;
                });

                var sub_grp = new GLib.Regex ("_\\(([^\\)]+)\\)");
                s = sub_grp.replace_eval (s, -1, 0, 0, (mi, res) => {
                    string val = mi.fetch (1);
                    res.append (use_unicode_digits ? to_unicode_subscript (val) : @"~$val~");
                    return false;
                });

                var exp_simple = new GLib.Regex ("\\^([+-]?[a-zA-Z0-9]+)");
                s = exp_simple.replace_eval (s, -1, 0, 0, (mi, res) => {
                    string val = mi.fetch (1);
                    res.append (use_unicode_digits ? to_unicode_superscript (val) : @"^$val^");
                    return false;
                });

                var sub_simple = new GLib.Regex ("_([a-zA-Z0-9]+)");
                s = sub_simple.replace_eval (s, -1, 0, 0, (mi, res) => {
                    string val = mi.fetch (1);
                    res.append (use_unicode_digits ? to_unicode_subscript (val) : @"~$val~");
                    return false;
                });
            } catch (GLib.RegexError e) {}

            return s;
        }

        private static string to_unicode_subscript (string s) {
            var sb = new GLib.StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                switch (s[i]) {
                    case '0': sb.append ("₀"); break;
                    case '1': sb.append ("₁"); break;
                    case '2': sb.append ("₂"); break;
                    case '3': sb.append ("₃"); break;
                    case '4': sb.append ("₄"); break;
                    case '5': sb.append ("₅"); break;
                    case '6': sb.append ("₆"); break;
                    case '7': sb.append ("₇"); break;
                    case '8': sb.append ("₈"); break;
                    case '9': sb.append ("₉"); break;
                    case '+': sb.append ("₊"); break;
                    case '-': sb.append ("₋"); break;
                    case '=': sb.append ("₌"); break;
                    case 'i': sb.append ("ᵢ"); break;
                    case 'n': sb.append ("ₙ"); break;
                    default: sb.append_c (s[i]); break;
                }
            }
            return sb.str;
        }

        private static string to_unicode_superscript (string s) {
            var sb = new GLib.StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                switch (s[i]) {
                    case '0': sb.append ("⁰"); break;
                    case '1': sb.append ("¹"); break;
                    case '2': sb.append ("²"); break;
                    case '3': sb.append ("³"); break;
                    case '4': sb.append ("⁴"); break;
                    case '5': sb.append ("⁵"); break;
                    case '6': sb.append ("⁶"); break;
                    case '7': sb.append ("⁷"); break;
                    case '8': sb.append ("⁸"); break;
                    case '9': sb.append ("⁹"); break;
                    case '+': sb.append ("⁺"); break;
                    case '-': sb.append ("⁻"); break;
                    case '=': sb.append ("⁼"); break;
                    case 'n': sb.append ("ⁿ"); break;
                    case 'i': sb.append ("ⁱ"); break;
                    default: sb.append_c (s[i]); break;
                }
            }
            return sb.str;
        }

        // =====================================================================
        // OFFLINE LATEX / MHCHEM TO RICH HTML RENDERER (For Live Previews)
        // =====================================================================

        /**
         * Render a LaTeX math or chemical expression into styled HTML for WebKitGTK preview.
         * Operates 100% offline with zero network calls.
         *
         * @param latex_or_natural Input LaTeX or natural expression.
         * @param display_block    True to wrap the result in a display block card, false for inline.
         * @return Safe HTML fragment representing the visual equation or chemical reaction.
         */
        public static string render_latex_to_html (string latex_or_natural, bool display_block = false) {
            string s = strip_outer_delimiters (latex_or_natural);
            if (s.length == 0) return "";

            // Handle \begin{equation} ... \end{equation}
            s = s.replace ("\\begin{equation}", "").replace ("\\end{equation}", "").strip ();

            // Handle \ce{...} blocks by converting to standard LaTeX first
            int ce_idx = s.index_of ("\\ce{");
            while (ce_idx >= 0) {
                int open_b = ce_idx + 3;
                int close_b = find_matching_delimiter (s, open_b, '{', '}');
                if (close_b < 0) break;
                string inner_ce = s.substring (open_b + 1, close_b - open_b - 1);
                string conv_ce = natural_chem_to_latex (inner_ce);
                s = s.substring (0, ce_idx) + conv_ce + s.substring (close_b + 1);
                ce_idx = s.index_of ("\\ce{");
            }

            // Convert pmatrix / bmatrix environments
            s = render_matrix_environments_html (s);

            // Convert \frac{a}{b} and \binom{n}{k}
            s = render_two_brace_cmd_html (s, "\\frac", "<span class=\"math-frac\"><span class=\"math-num\">", "</span><span class=\"math-den\">", "</span></span>");
            s = render_two_brace_cmd_html (s, "\\binom", "<span class=\"math-binom\">(<span class=\"math-frac\"><span class=\"math-num\" style=\"border-bottom:none;\">", "</span><span class=\"math-den\">", "</span></span>)</span>");
            s = render_two_brace_cmd_html (s, "\\overset", "<span class=\"chem-arrow-stack\"><span class=\"chem-cond-above\">", "</span><span class=\"chem-arrow-main\">", "</span></span>");
            s = render_two_brace_cmd_html (s, "\\underset", "<span class=\"chem-arrow-stack\"><span class=\"chem-cond-below\">", "</span><span class=\"chem-arrow-main\">", "</span></span>");

            // Convert \xrightarrow[below]{above} and \xrightarrow{above}
            s = render_xrightarrow_html (s);

            // Convert \sqrt[n]{x} and \sqrt{x}
            s = render_sqrt_html (s);

            // Convert \text{...}, \bar{...}, \hat{...}, \vec{...}
            s = render_one_brace_cmd_html (s, "\\text", "<span class=\"math-text\">", "</span>");
            s = render_one_brace_cmd_html (s, "\\mathrm", "<span class=\"math-text\">", "</span>");
            s = render_one_brace_cmd_html (s, "\\bar", "<span style=\"text-decoration: overline;\">", "</span>");
            s = render_one_brace_cmd_html (s, "\\hat", "", "&#770;");
            s = render_one_brace_cmd_html (s, "\\vec", "", "&#8407;");

            // Convert superscripts ^{...} and subscripts _{...}
            s = render_one_brace_cmd_html (s, "^", "<sup>", "</sup>");
            s = render_one_brace_cmd_html (s, "_", "<sub>", "</sub>");

            // Replace LaTeX symbols with Unicode symbols
            string[,] sym_map = {
                { "\\rightleftharpoons", "⇌" },
                { "\\leftrightarrow", "↔" },
                { "\\Leftrightarrow", "⇔" },
                { "\\iff", "⟺" },
                { "\\implies", "⟹" },
                { "\\Rightarrow", "⇒" },
                { "\\rightarrow", "→" },
                { "\\leftarrow", "←" },
                { "\\downarrow", "↓" },
                { "\\uparrow", "↑" },
                { "\\to", "→" },
                { "\\pm", "±" },
                { "\\mp", "∓" },
                { "\\times", "×" },
                { "\\cdot", "·" },
                { "\\div", "÷" },
                { "\\neq", "≠" },
                { "\\leq", "≤" },
                { "\\geq", "≥" },
                { "\\approx", "≈" },
                { "\\equiv", "≡" },
                { "\\propto", "∝" },
                { "\\infty", "∞" },
                { "\\nabla", "∇" },
                { "\\partial", "∂" },
                { "\\forall", "∀" },
                { "\\exists", "∃" },
                { "\\notin", "∉" },
                { "\\in", "∈" },
                { "\\subseteq", "⊆" },
                { "\\subset", "⊂" },
                { "\\cup", "∪" },
                { "\\cap", "∩" },
                { "\\int", "<span class=\"math-big-op\">∫</span>" },
                { "\\sum", "<span class=\"math-big-op\">∑</span>" },
                { "\\prod", "<span class=\"math-big-op\">∏</span>" },
                { "\\lim", "<span class=\"math-func\">lim</span>" },
                { "\\sin", "<span class=\"math-func\">sin</span>" },
                { "\\cos", "<span class=\"math-func\">cos</span>" },
                { "\\tan", "<span class=\"math-func\">tan</span>" },
                { "\\log", "<span class=\"math-func\">log</span>" },
                { "\\ln", "<span class=\"math-func\">ln</span>" },
                { "\\exp", "<span class=\"math-func\">exp</span>" },
                { "\\min", "<span class=\"math-func\">min</span>" },
                { "\\max", "<span class=\"math-func\">max</span>" },
                { "\\det", "<span class=\"math-func\">det</span>" },
                { "\\alpha", "α" }, { "\\beta", "β" }, { "\\gamma", "γ" }, { "\\delta", "δ" },
                { "\\varepsilon", "ε" }, { "\\epsilon", "ϵ" }, { "\\zeta", "ζ" }, { "\\eta", "η" },
                { "\\theta", "θ" }, { "\\iota", "ι" }, { "\\kappa", "κ" }, { "\\lambda", "λ" },
                { "\\mu", "μ" }, { "\\nu", "ν" }, { "\\xi", "ξ" }, { "\\pi", "π" },
                { "\\rho", "ρ" }, { "\\sigma", "σ" }, { "\\tau", "τ" }, { "\\upsilon", "υ" },
                { "\\varphi", "φ" }, { "\\phi", "ϕ" }, { "\\chi", "χ" }, { "\\psi", "ψ" },
                { "\\omega", "ω" }, { "\\Gamma", "Γ" }, { "\\Delta", "Δ" }, { "\\Theta", "Θ" },
                { "\\Lambda", "Λ" }, { "\\Xi", "Ξ" }, { "\\Pi", "Π" }, { "\\Sigma", "Σ" },
                { "\\Phi", "Φ" }, { "\\Psi", "Ψ" }, { "\\Omega", "Ω" },
                { "\\left|", "|" }, { "\\right|", "|" },
                { "\\left(", "(" }, { "\\right)", ")" },
                { "\\left[", "[" }, { "\\right]", "]" },
                { "\\,", " " }
            };

            for (int i = 0; i < sym_map.length[0]; i++) {
                s = s.replace (sym_map[i, 0], sym_map[i, 1]);
            }

            // Simple single-character ^x and _x remaining
            try {
                var rem_sup = new GLib.Regex ("\\^([a-zA-Z0-9+-])");
                s = rem_sup.replace (s, -1, 0, "<sup>\\1</sup>");
                var rem_sub = new GLib.Regex ("_([a-zA-Z0-9+-])");
                s = rem_sub.replace (s, -1, 0, "<sub>\\1</sub>");
            } catch (GLib.RegexError e) {}

            if (display_block) {
                return @"<div class=\"math-display-card\">$s</div>";
            }
            return s;
        }

        private static string render_matrix_environments_html (string input) {
            string s = input;
            string[] envs = { "pmatrix", "bmatrix", "matrix" };
            foreach (string env in envs) {
                string start_tag = @"\\begin{$env}";
                string end_tag = @"\\end{$env}";
                int idx = s.index_of (start_tag);
                while (idx >= 0) {
                    int end_idx = s.index_of (end_tag, idx);
                    if (end_idx < 0) break;
                    string inner = s.substring (idx + start_tag.length, end_idx - idx - start_tag.length).strip ();
                    string[] rows = inner.split ("\\\\");
                    var tbl = new GLib.StringBuilder ("<span class=\"math-matrix-wrap\"><span class=\"math-matrix-delim\">[</span><table class=\"math-matrix\">");
                    foreach (string r in rows) {
                        if (r.strip () == "") continue;
                        tbl.append ("<tr>");
                        string[] cells = r.split ("&");
                        foreach (string c in cells) {
                            tbl.append_printf ("<td>%s</td>", render_latex_to_html (c.strip ()));
                        }
                        tbl.append ("</tr>");
                    }
                    tbl.append ("</table><span class=\"math-matrix-delim\">]</span></span>");
                    s = s.substring (0, idx) + tbl.str + s.substring (end_idx + end_tag.length);
                    idx = s.index_of (start_tag);
                }
            }
            return s;
        }

        private static string render_two_brace_cmd_html (
            string input,
            string cmd,
            string open_html,
            string mid_html,
            string close_html
        ) {
            string s = input;
            string token = cmd + "{";
            int idx = s.index_of (token);
            while (idx >= 0) {
                int b1_open = idx + cmd.length;
                int b1_close = find_matching_delimiter (s, b1_open, '{', '}');
                if (b1_close < 0 || b1_close + 1 >= s.length || s[b1_close + 1] != '{') break;
                int b2_open = b1_close + 1;
                int b2_close = find_matching_delimiter (s, b2_open, '{', '}');
                if (b2_close < 0) break;

                string arg1 = render_latex_to_html (s.substring (b1_open + 1, b1_close - b1_open - 1));
                string arg2 = render_latex_to_html (s.substring (b2_open + 1, b2_close - b2_open - 1));
                string html = open_html + arg1 + mid_html + arg2 + close_html;
                s = s.substring (0, idx) + html + s.substring (b2_close + 1);
                idx = s.index_of (token);
            }
            return s;
        }

        private static string render_one_brace_cmd_html (
            string input,
            string cmd,
            string open_html,
            string close_html
        ) {
            string s = input;
            string token = cmd + "{";
            int idx = s.index_of (token);
            while (idx >= 0) {
                int b_open = idx + cmd.length;
                int b_close = find_matching_delimiter (s, b_open, '{', '}');
                if (b_close < 0) break;
                string arg = render_latex_to_html (s.substring (b_open + 1, b_close - b_open - 1));
                string html = open_html + arg + close_html;
                s = s.substring (0, idx) + html + s.substring (b_close + 1);
                idx = s.index_of (token);
            }
            return s;
        }

        private static string render_xrightarrow_html (string input) {
            string s = input;
            int idx = s.index_of ("\\xrightarrow");
            while (idx >= 0) {
                int pos = idx + 12;
                string below = "";
                if (pos < s.length && s[pos] == '[') {
                    int c_br = find_matching_delimiter (s, pos, '[', ']');
                    if (c_br > pos) {
                        below = render_latex_to_html (s.substring (pos + 1, c_br - pos - 1));
                        pos = c_br + 1;
                    }
                }
                if (pos < s.length && s[pos] == '{') {
                    int c_b = find_matching_delimiter (s, pos, '{', '}');
                    if (c_b > pos) {
                        string above = render_latex_to_html (s.substring (pos + 1, c_b - pos - 1));
                        string html = @"<span class=\"chem-arrow-stack\"><span class=\"chem-cond-above\">$above</span><span class=\"chem-arrow-main\">⟶</span>";
                        if (below != "") {
                            html += @"<span class=\"chem-cond-below\">$below</span>";
                        }
                        html += "</span>";
                        s = s.substring (0, idx) + html + s.substring (c_b + 1);
                        idx = s.index_of ("\\xrightarrow");
                        continue;
                    }
                }
                break;
            }
            return s;
        }

        private static string render_sqrt_html (string input) {
            string s = input;
            int idx = s.index_of ("\\sqrt");
            while (idx >= 0) {
                int pos = idx + 5;
                string root_idx = "";
                if (pos < s.length && s[pos] == '[') {
                    int c_br = find_matching_delimiter (s, pos, '[', ']');
                    if (c_br > pos) {
                        root_idx = render_latex_to_html (s.substring (pos + 1, c_br - pos - 1));
                        pos = c_br + 1;
                    }
                }
                if (pos < s.length && s[pos] == '{') {
                    int c_b = find_matching_delimiter (s, pos, '{', '}');
                    if (c_b > pos) {
                        string inner = render_latex_to_html (s.substring (pos + 1, c_b - pos - 1));
                        string idx_sup = root_idx != "" ? @"<sup class=\"math-root-idx\">$root_idx</sup>" : "";
                        string html = @"$idx_sup<span class=\"math-sqrt\">√<span class=\"math-radicand\">$inner</span></span>";
                        s = s.substring (0, idx) + html + s.substring (c_b + 1);
                        idx = s.index_of ("\\sqrt");
                        continue;
                    }
                }
                break;
            }
            return s;
        }

        /**
         * Return the shared CSS rules required to style mathematical and chemical HTML blocks.
         *
         * @return CSS stylesheet fragment string.
         */
        public static string get_math_chem_css () {
            return """
  .math-display-card {
    margin: 14px 0;
    padding: 14px 20px;
    border-radius: 8px;
    background: rgba(56, 189, 248, 0.06);
    border-left: 3px solid #3584e4;
    text-align: center;
    font-family: 'Cambria Math', 'Latin Modern Math', 'STIX Two Math', 'DejaVu Serif', Georgia, serif;
    font-size: 1.18em;
    overflow-x: auto;
  }
  .math-inline {
    font-family: 'Cambria Math', 'Latin Modern Math', 'STIX Two Math', 'DejaVu Serif', Georgia, serif;
    font-size: 1.05em;
    padding: 0 2px;
  }
  .math-frac {
    display: inline-flex;
    flex-direction: column;
    vertical-align: middle;
    text-align: center;
    padding: 0 4px;
    font-size: 0.92em;
  }
  .math-num {
    border-bottom: 1.5px solid currentColor;
    padding: 0 4px 2px 4px;
    line-height: 1.1;
  }
  .math-den {
    padding: 2px 4px 0 4px;
    line-height: 1.1;
  }
  .math-sqrt {
    display: inline-flex;
    align-items: center;
    vertical-align: middle;
  }
  .math-radicand {
    border-top: 1.5px solid currentColor;
    padding: 1px 3px 0 2px;
    margin-left: 1px;
  }
  .math-root-idx {
    font-size: 0.65em;
    margin-right: -2px;
    vertical-align: super;
  }
  .math-big-op {
    font-size: 1.35em;
    vertical-align: middle;
    padding: 0 2px;
  }
  .math-func {
    font-style: normal;
    font-weight: 500;
    padding-right: 2px;
  }
  .math-text {
    font-family: 'Inter', 'Cantarell', system-ui, sans-serif;
    font-style: normal;
  }
  .chem-arrow-stack {
    display: inline-flex;
    flex-direction: column;
    align-items: center;
    vertical-align: middle;
    margin: 0 6px;
    line-height: 1.0;
  }
  .chem-cond-above, .chem-cond-below {
    font-size: 0.72em;
    font-family: 'Inter', 'Cantarell', sans-serif;
    opacity: 0.88;
    padding: 0 4px;
  }
  .chem-arrow-main {
    font-size: 1.25em;
    line-height: 0.9;
  }
  .math-matrix-wrap {
    display: inline-flex;
    align-items: center;
    vertical-align: middle;
    margin: 0 4px;
  }
  .math-matrix-delim {
    font-size: 1.8em;
    font-weight: 300;
    line-height: 1;
  }
  .math-matrix {
    border-collapse: collapse;
    display: inline-table;
    vertical-align: middle;
  }
  .math-matrix td {
    padding: 2px 8px;
    text-align: center;
  }
""";
        }

        // =====================================================================
        // DELIMITER BALANCING HELPERS
        // =====================================================================

        private static int find_matching_delimiter (string s, int open_idx, char open_ch, char close_ch) {
            int depth = 0;
            for (int i = open_idx; i < s.length; i++) {
                if (s[i] == open_ch) depth++;
                else if (s[i] == close_ch) {
                    depth--;
                    if (depth == 0) return i;
                }
            }
            return -1;
        }

        private static int find_matching_delimiter_backward (string s, int close_idx, char open_ch, char close_ch) {
            int depth = 0;
            for (int i = close_idx; i >= 0; i--) {
                if (s[i] == close_ch) depth++;
                else if (s[i] == open_ch) {
                    depth--;
                    if (depth == 0) return i;
                }
            }
            return -1;
        }

        private static int find_top_level_comma (string s) {
            int depth = 0;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '(' || c == '[' || c == '{') depth++;
                else if (c == ')' || c == ']' || c == '}') depth--;
                else if (c == ',' && depth == 0) return i;
            }
            return -1;
        }
    }
}
