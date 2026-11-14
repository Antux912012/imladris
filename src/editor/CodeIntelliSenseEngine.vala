// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Deterministic, non-AI polyglot symbol indexing, context detection,
 * and fuzzy completion ranking engine.
 *
 * Architectural Position:
 * Core editor intelligence layer. Parses active document buffers, resolves language contexts
 * via ChunkParser, and ranks standard library, bioinformatics, biostatistics, Quarto, LaTeX,
 * and user-defined symbols.
 *
 * Concurrency Constraints:
 * Pure in-memory computation safe to run synchronously or inside async completion tasks on the
 * GLib MainContext thread.
 */

using GLib;
using Gee;
using Imladris.Core;

namespace Imladris.Editor {

    public enum IntelliSenseContext {
        MARKDOWN_PROSE,
        YAML_FRONTMATTER,
        CHUNK_FENCE_HEADER,
        QUARTO_HASH_PIPE,
        LATEX_MATH_CHEM,
        R_CODE,
        PYTHON_CODE,
        BASH_CODE,
        TYPESCRIPT_CODE
    }

    public enum IntelliSenseSymbolKind {
        FUNCTION,
        METHOD,
        VARIABLE,
        DATAFRAME,
        COLUMN,
        MODULE,
        KEYWORD,
        OPTION,
        SNIPPET,
        LATEX_MACRO;

        public string to_icon_name () {
            switch (this) {
                case FUNCTION:
                case METHOD:
                    return "system-run-symbolic";
                case VARIABLE:
                case COLUMN:
                    return "view-list-symbolic";
                case DATAFRAME:
                    return "x-office-spreadsheet-symbolic";
                case MODULE:
                    return "package-x-generic-symbolic";
                case KEYWORD:
                    return "format-text-bold-symbolic";
                case OPTION:
                    return "emblem-system-symbolic";
                case LATEX_MACRO:
                    return "accessories-calculator-symbolic";
                case SNIPPET:
                default:
                    return "insert-text-symbolic";
            }
        }
    }

    public class IntelliSenseItem : GLib.Object {
        public string label { get; set; }
        public string insert_text { get; set; }
        public string signature { get; set; }
        public string detail { get; set; }
        public IntelliSenseSymbolKind kind { get; set; }
        public int cursor_backtrack { get; set; default = 0; }
        public int score { get; set; default = 0; }

        public IntelliSenseItem (
            string label,
            string insert_text,
            string signature,
            string detail,
            IntelliSenseSymbolKind kind,
            int cursor_backtrack = 0
        ) {
            this.label = label;
            this.insert_text = insert_text;
            this.signature = signature;
            this.detail = detail;
            this.kind = kind;
            this.cursor_backtrack = cursor_backtrack;
        }
    }

    public class CodeIntelliSenseEngine : GLib.Object {

        private static ArrayList<IntelliSenseItem>? r_catalog = null;
        private static ArrayList<IntelliSenseItem>? py_catalog = null;
        private static ArrayList<IntelliSenseItem>? quarto_opt_catalog = null;
        private static ArrayList<IntelliSenseItem>? yaml_catalog = null;
        private static ArrayList<IntelliSenseItem>? latex_catalog = null;
        private static HashMap<string, string>? builtin_df_columns = null;

        private static void ensure_catalogs_initialized () {
            if (r_catalog != null) {
                return;
            }

            r_catalog = new ArrayList<IntelliSenseItem> ();
            py_catalog = new ArrayList<IntelliSenseItem> ();
            quarto_opt_catalog = new ArrayList<IntelliSenseItem> ();
            yaml_catalog = new ArrayList<IntelliSenseItem> ();
            latex_catalog = new ArrayList<IntelliSenseItem> ();
            builtin_df_columns = new HashMap<string, string> ();

            // Built-in R dataset columns for instant '$' completion
            builtin_df_columns.set ("mtcars", "mpg,cyl,disp,hp,drat,wt,qsec,vs,am,gear,carb");
            builtin_df_columns.set ("iris", "Sepal.Length,Sepal.Width,Petal.Length,Petal.Width,Species");
            builtin_df_columns.set ("ToothGrowth", "len,supp,dose");
            builtin_df_columns.set ("PlantGrowth", "weight,group");
            builtin_df_columns.set ("airquality", "Ozone,Solar.R,Wind,Temp,Month,Day");
            builtin_df_columns.set ("clinical_df", "USUBJID,ARM,AGE,SEX,AVAL,EVENT,CNSR,BMK1");
            builtin_df_columns.set ("deseq2_res", "gene_symbol,baseMean,log2FoldChange,lfcSE,stat,pvalue,padj");

            // R Keywords & Base / Stats / Biostatistics / Tidyverse / Bioconductor Catalog
            add_r ("library", "library()", "(package)", "Load and attach R package [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("requireNamespace", "requireNamespace(\"\", quietly = TRUE)", "(package, quietly = TRUE)", "Check if namespace is installed [base]", IntelliSenseSymbolKind.FUNCTION, 18);
            add_r ("read.csv", "read.csv(\"\")", "(file, header = TRUE)", "Read comma-separated file [utils]", IntelliSenseSymbolKind.FUNCTION, 2);
            add_r ("read.delim", "read.delim(\"\", stringsAsFactors = FALSE)", "(file, sep = \"\\t\")", "Read tab-delimited bioinformatics table [utils]", IntelliSenseSymbolKind.FUNCTION, 28);
            add_r ("write.csv", "write.csv(, file = \"\", row.names = FALSE)", "(x, file, row.names = FALSE)", "Write data.frame to CSV [utils]", IntelliSenseSymbolKind.FUNCTION, 29);
            add_r ("summary", "summary()", "(object)", "Object summary statistics [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("View", "View()", "(x)", "Open DataFrame in Imladris DataGridViewer [utils]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("head", "head(, n = 6)", "(x, n = 6)", "Return first rows of object [utils]", IntelliSenseSymbolKind.FUNCTION, 8);
            add_r ("tail", "tail(, n = 6)", "(x, n = 6)", "Return last rows of object [utils]", IntelliSenseSymbolKind.FUNCTION, 8);
            add_r ("str", "str()", "(object)", "Compactly display internal structure [utils]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("data.frame", "data.frame()", "(...)", "Construct a data.frame [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("ifelse", "ifelse(, , )", "(test, yes, no)", "Vectorized conditional element selection [base]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("lapply", "lapply(, function(x) )", "(X, FUN)", "Apply function over list or vector [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("sapply", "sapply(, function(x) )", "(X, FUN)", "Apply function and simplify to vector/matrix [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("set.seed", "set.seed(42)", "(seed)", "Initialize reproducible PRNG state [base]", IntelliSenseSymbolKind.FUNCTION, 0);

            // R Stats & Clinical Biostatistics
            add_r ("lm", "lm( ~ , data = )", "(formula, data)", "Fit Linear Models [stats]", IntelliSenseSymbolKind.FUNCTION, 11);
            add_r ("glm", "glm( ~ , family = binomial, data = )", "(formula, family, data)", "Fit Generalized Linear Models [stats]", IntelliSenseSymbolKind.FUNCTION, 31);
            add_r ("t.test", "t.test(, , alternative = \"two.sided\")", "(x, y, alternative = \"two.sided\")", "Student's t-Test [stats]", IntelliSenseSymbolKind.FUNCTION, 29);
            add_r ("wilcox.test", "wilcox.test(, , exact = FALSE)", "(x, y, exact = FALSE)", "Mann-Whitney-Wilcoxon Rank Sum Test [stats]", IntelliSenseSymbolKind.FUNCTION, 17);
            add_r ("chisq.test", "chisq.test()", "(x, y = NULL)", "Pearson's Chi-squared Test [stats]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("fisher.test", "fisher.test()", "(x, y = NULL)", "Fisher's Exact Test for Count Data [stats]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("cor.test", "cor.test(, , method = \"pearson\")", "(x, y, method = \"pearson\")", "Correlation test (Pearson/Spearman) [stats]", IntelliSenseSymbolKind.FUNCTION, 22);
            add_r ("aov", "aov( ~ , data = )", "(formula, data)", "Analysis of Variance (ANOVA) [stats]", IntelliSenseSymbolKind.FUNCTION, 11);
            add_r ("p.adjust", "p.adjust(, method = \"BH\")", "(p, method = \"BH\")", "Adjust P-values for Multiple Comparisons (FDR) [stats]", IntelliSenseSymbolKind.FUNCTION, 16);
            add_r ("prcomp", "prcomp(, scale. = TRUE)", "(x, scale. = TRUE)", "Principal Components Analysis (PCA) [stats]", IntelliSenseSymbolKind.FUNCTION, 15);
            add_r ("power.t.test", "power.t.test(delta = 0.5, sd = 1.0, sig.level = 0.05, power = 0.80)", "(n, delta, sd, sig.level, power)", "Power calculation for two-sample t-test [stats]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("power.prop.test", "power.prop.test(p1 = 0.30, p2 = 0.50, sig.level = 0.05, power = 0.80)", "(n, p1, p2, sig.level, power)", "Power calculation for two-sample proportions [stats]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("qnorm", "qnorm(0.975)", "(p, mean = 0, sd = 1)", "Normal distribution quantile function [stats]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("rnorm", "rnorm(100, mean = 0, sd = 1)", "(n, mean = 0, sd = 1)", "Generate normal random deviates [stats]", IntelliSenseSymbolKind.FUNCTION, 1);

            // R Survival / CDISC / Tidyverse / ggplot2 / DESeq2
            add_r ("Surv", "Surv(time = , event = )", "(time, event)", "Create a Survival Object [survival]", IntelliSenseSymbolKind.FUNCTION, 10);
            add_r ("survfit", "survfit(Surv(time, event) ~ , data = )", "(formula, data)", "Compute Kaplan-Meier Survival Curve [survival]", IntelliSenseSymbolKind.FUNCTION, 9);
            add_r ("coxph", "coxph(Surv(time, event) ~ , data = )", "(formula, data)", "Fit Cox Proportional Hazards Regression [survival]", IntelliSenseSymbolKind.FUNCTION, 9);
            add_r ("survdiff", "survdiff(Surv(time, event) ~ , data = )", "(formula, data)", "Log-Rank Test Survival Curve Comparison [survival]", IntelliSenseSymbolKind.FUNCTION, 9);
            add_r ("tbl_summary", "tbl_summary(by = , missing = \"ifany\")", "(data, by, statistic)", "CDISC Table 1 Baseline Demographics [gtsummary]", IntelliSenseSymbolKind.FUNCTION, 20);
            add_r ("ggplot", "ggplot(, aes(x = , y = ))", "(data, mapping = aes())", "Create a new ggplot2 graphic [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 17);
            add_r ("aes", "aes(x = , y = , color = )", "(x, y, color, fill)", "Construct aesthetic mappings [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 16);
            add_r ("geom_point", "geom_point(alpha = 0.8, size = 2)", "(mapping, data, alpha, size)", "Scatterplot points layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_line", "geom_line(linewidth = 1)", "(mapping, data, linewidth)", "Connected line layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_boxplot", "geom_boxplot(width = 0.5)", "(mapping, data, width)", "Box-and-whiskers plot layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_violin", "geom_violin(trim = FALSE)", "(mapping, data, trim)", "Violin density plot layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_histogram", "geom_histogram(bins = 30)", "(mapping, data, bins)", "Histogram distribution layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_vline", "geom_vline(xintercept = 0, linetype = \"dashed\")", "(xintercept, linetype)", "Vertical reference line [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_hline", "geom_hline(yintercept = 0, linetype = \"dashed\")", "(yintercept, linetype)", "Horizontal reference line [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("theme_minimal", "theme_minimal()", "(base_size = 11)", "Minimalist publication theme [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("labs", "labs(title = \"\", x = \"\", y = \"\")", "(title, subtitle, x, y, caption)", "Modify axis, legend, and plot labels [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 18);
            add_r ("filter", "filter()", "(.data, ...)", "Subset rows using column values [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("mutate", "mutate()", "(.data, ...)", "Create, modify, and delete columns [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("select", "select()", "(.data, ...)", "Keep or drop columns using their names [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("group_by", "group_by()", "(.data, ...)", "Group by one or more variables [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("summarise", "summarise()", "(.data, ...)", "Summarise each group to one row [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("arrange", "arrange()", "(.data, ...)", "Order rows using column values [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("left_join", "left_join(, by = \"\")", "(x, y, by = NULL)", "Mutating left join of two tables [dplyr]", IntelliSenseSymbolKind.FUNCTION, 2);
            add_r ("pivot_longer", "pivot_longer(cols = , names_to = \"name\", values_to = \"value\")", "(data, cols, names_to, values_to)", "Pivot data from wide to long [tidyr]", IntelliSenseSymbolKind.FUNCTION, 40);
            add_r ("pivot_wider", "pivot_wider(names_from = , values_from = )", "(data, names_from, values_from)", "Pivot data from long to wide [tidyr]", IntelliSenseSymbolKind.FUNCTION, 16);
            add_r ("DESeqDataSetFromMatrix", "DESeqDataSetFromMatrix(countData = , colData = , design = ~ )", "(countData, colData, design)", "Build DESeq2 count matrix dataset [DESeq2]", IntelliSenseSymbolKind.FUNCTION, 26);
            add_r ("DESeq", "DESeq()", "(object)", "Differential expression analysis based on Negative Binomial [DESeq2]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("results", "results(, alpha = 0.05)", "(object, contrast, alpha = 0.05)", "Extract DESeq2 differential expression table [DESeq2]", IntelliSenseSymbolKind.FUNCTION, 15);
            add_r ("read.pdb", "bio3d::read.pdb(\"\")", "(file)", "Read Protein Data Bank (PDB) structure [bio3d]", IntelliSenseSymbolKind.FUNCTION, 2);

            // Built-in R Datasets
            add_r ("mtcars", "mtcars", "[32 x 11 data.frame]", "Motor Trend Car Road Tests [datasets]", IntelliSenseSymbolKind.DATAFRAME, 0);
            add_r ("iris", "iris", "[150 x 5 data.frame]", "Edgar Anderson's Iris Data [datasets]", IntelliSenseSymbolKind.DATAFRAME, 0);

            // Python Built-in & Scientific Data Science / Bioinformatics Catalog
            add_py ("import", "import ", "keyword", "Import a Python module", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("from", "from  import ", "keyword", "Import specific attributes from a module", IntelliSenseSymbolKind.KEYWORD, 8);
            add_py ("def", "def ():\n    ", "keyword", "Define a Python function", IntelliSenseSymbolKind.KEYWORD, 7);
            add_py ("class", "class :\n    ", "keyword", "Define a Python class", IntelliSenseSymbolKind.KEYWORD, 6);
            add_py ("print", "print()", "(*values, sep=' ', end='\\n')", "Print values to standard output [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("len", "len()", "(obj) -> int", "Return number of items in container [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("range", "range()", "(start, stop[, step])", "Immutable sequence of numbers [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("enumerate", "enumerate()", "(iterable, start=0)", "Return enumerate object yielding (index, value) [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("zip", "zip()", "(*iterables)", "Iterate over several iterables in parallel [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("pandas", "import pandas as pd", "module", "Import pandas DataFrame library as pd", IntelliSenseSymbolKind.MODULE, 0);
            add_py ("numpy", "import numpy as np", "module", "Import NumPy array computing library as np", IntelliSenseSymbolKind.MODULE, 0);
            add_py ("matplotlib", "import matplotlib.pyplot as plt", "module", "Import Matplotlib plotting interface as plt", IntelliSenseSymbolKind.MODULE, 0);
            add_py ("seaborn", "import seaborn as sns", "module", "Import Seaborn statistical visualization library", IntelliSenseSymbolKind.MODULE, 0);
            add_py ("scipy.stats", "from scipy import stats", "module", "Import SciPy statistical functions", IntelliSenseSymbolKind.MODULE, 0);
            add_py ("lifelines", "from lifelines import KaplanMeierFitter, CoxPHFitter", "module", "Import Lifelines survival analysis models", IntelliSenseSymbolKind.MODULE, 0);
            add_py ("Biopython", "from Bio import SeqIO", "module", "Import Biopython sequence I/O interface", IntelliSenseSymbolKind.MODULE, 0);

            // Python Dot-Member Catalog (pd.*, np.*, plt.*, stats.*, sns.*)
            add_py ("pd.read_csv", "pd.read_csv(\"\")", "(filepath_or_buffer, sep=',')", "Read comma-separated file into DataFrame [pandas]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("pd.read_table", "pd.read_table(\"\", sep=\"\\t\")", "(filepath_or_buffer, sep='\\t')", "Read tab-delimited bioinformatics file [pandas]", IntelliSenseSymbolKind.METHOD, 12);
            add_py ("pd.DataFrame", "pd.DataFrame()", "(data=None, columns=None)", "Two-dimensional tabular data structure [pandas]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("pd.concat", "pd.concat([], axis=0)", "(objs, axis=0, ignore_index=False)", "Concatenate pandas objects along an axis [pandas]", IntelliSenseSymbolKind.METHOD, 10);
            add_py ("pd.merge", "pd.merge(, , on=\"\")", "(left, right, how='inner', on=None)", "Merge DataFrame or named Series objects [pandas]", IntelliSenseSymbolKind.METHOD, 9);
            add_py ("np.array", "np.array([])", "(object, dtype=None)", "Create an N-dimensional NumPy array [numpy]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("np.linspace", "np.linspace(0.0, 1.0, 100)", "(start, stop, num=50)", "Return evenly spaced numbers over interval [numpy]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("np.arange", "np.arange(0, 10, 1)", "(start, stop, step)", "Return evenly spaced values within interval [numpy]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("np.mean", "np.mean()", "(a, axis=None)", "Compute arithmetic mean along specified axis [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.std", "np.std()", "(a, axis=None, ddof=0)", "Compute standard deviation along axis [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.log2", "np.log2()", "(x)", "Base-2 logarithm of x (Fold-Change) [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.log10", "np.log10()", "(x)", "Base-10 logarithm of x (-log10 P-value) [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.clip", "np.clip(, 1e-300, 1.0)", "(a, a_min, a_max)", "Clip (limit) values in an array [numpy]", IntelliSenseSymbolKind.METHOD, 14);
            add_py ("plt.figure", "plt.figure(figsize=(7, 5))", "(figsize=(width, height), dpi=100)", "Create a new figure [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.subplots", "fig, ax = plt.subplots(figsize=(7, 5))", "(nrows=1, ncols=1, figsize=None)", "Create a figure and a set of subplots [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.plot", "plt.plot(, )", "(x, y, label=None)", "Plot y versus x as lines or markers [matplotlib]", IntelliSenseSymbolKind.METHOD, 3);
            add_py ("plt.scatter", "plt.scatter(, , alpha=0.8)", "(x, y, s=None, c=None, alpha=None)", "Scatter plot of y vs. x [matplotlib]", IntelliSenseSymbolKind.METHOD, 14);
            add_py ("plt.axvline", "plt.axvline(0.0, linestyle=\"--\", color=\"#475569\")", "(x=0, ymin=0, ymax=1, ls='--')", "Add a vertical line across the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.axhline", "plt.axhline(0.0, linestyle=\"--\", color=\"#475569\")", "(y=0, xmin=0, xmax=1, ls='--')", "Add a horizontal line across the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.xlabel", "plt.xlabel(\"\")", "(xlabel)", "Set the label for the x-axis [matplotlib]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("plt.ylabel", "plt.ylabel(\"\")", "(ylabel)", "Set the label for the y-axis [matplotlib]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("plt.title", "plt.title(\"\")", "(label)", "Set a title for the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("plt.tight_layout", "plt.tight_layout()", "()", "Adjust padding between and around subplots [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.show", "plt.show()", "()", "Display all open figures [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("stats.ttest_ind", "stats.ttest_ind(, , equal_var=False)", "(a, b, equal_var=True)", "Two-sample Welch/Student t-test [scipy.stats]", IntelliSenseSymbolKind.METHOD, 20);
            add_py ("stats.mannwhitneyu", "stats.mannwhitneyu(, )", "(x, y, alternative='two-sided')", "Mann-Whitney U rank test [scipy.stats]", IntelliSenseSymbolKind.METHOD, 3);
            add_py ("stats.fisher_exact", "stats.fisher_exact()", "(table, alternative='two-sided')", "Fisher exact test on 2x2 contingency table [scipy.stats]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("stats.norm.ppf", "stats.norm.ppf(0.975)", "(q, loc=0, scale=1)", "Normal distribution percent point (quantile) [scipy.stats]", IntelliSenseSymbolKind.METHOD, 1);

            // Quarto / R Markdown '#|' Hash-Pipe Chunk Options
            add_quarto_opt ("echo: true", "echo: true", "boolean", "Include chunk source code in rendered output");
            add_quarto_opt ("echo: false", "echo: false", "boolean", "Hide chunk source code in rendered output");
            add_quarto_opt ("eval: true", "eval: true", "boolean", "Evaluate code chunk during execution");
            add_quarto_opt ("eval: false", "eval: false", "boolean", "Skip evaluating code chunk during batch runs");
            add_quarto_opt ("warning: false", "warning: false", "boolean", "Suppress warning messages in output");
            add_quarto_opt ("message: false", "message: false", "boolean", "Suppress diagnostic/package startup messages");
            add_quarto_opt ("include: false", "include: false", "boolean", "Prevent code and results from appearing in output");
            add_quarto_opt ("output: asis", "output: asis", "string", "Treat output as raw Markdown/LaTeX");
            add_quarto_opt ("label", "label: fig-", "string", "Unique chunk identifier for cross-referencing");
            add_quarto_opt ("fig-cap", "fig-cap: \"\"", "string", "Figure caption text for publication output", 1);
            add_quarto_opt ("fig-width", "fig-width: 8", "number", "Figure width in inches");
            add_quarto_opt ("fig-height", "fig-height: 5", "number", "Figure height in inches");
            add_quarto_opt ("fig-dpi", "fig-dpi: 300", "number", "Figure resolution in dots per inch (DPI)");
            add_quarto_opt ("tbl-cap", "tbl-cap: \"\"", "string", "Table caption text for cross-referenced tables", 1);
            add_quarto_opt ("cache: true", "cache: true", "boolean", "Cache chunk computation results on disk");
            add_quarto_opt ("code-fold: true", "code-fold: true", "boolean", "Collapse code into an interactive <details> block");

            // Quarto / R Markdown YAML Frontmatter Keys
            yaml_catalog.add (new IntelliSenseItem ("title:", "title: \"\"", "string", "Document main title", IntelliSenseSymbolKind.OPTION, 1));
            yaml_catalog.add (new IntelliSenseItem ("subtitle:", "subtitle: \"\"", "string", "Document subtitle", IntelliSenseSymbolKind.OPTION, 1));
            yaml_catalog.add (new IntelliSenseItem ("author:", "author: \"\"", "string", "Document primary author", IntelliSenseSymbolKind.OPTION, 1));
            yaml_catalog.add (new IntelliSenseItem ("date: today", "date: today", "date", "Dynamic ISO publication date", IntelliSenseSymbolKind.OPTION, 0));
            yaml_catalog.add (new IntelliSenseItem ("format: html", "format:\n  html:\n    toc: true\n    code-fold: show", "block", "Quarto HTML output configuration", IntelliSenseSymbolKind.SNIPPET, 0));
            yaml_catalog.add (new IntelliSenseItem ("format: pdf", "format:\n  pdf:\n    toc: true\n    number-sections: true", "block", "Quarto PDF/LaTeX output configuration", IntelliSenseSymbolKind.SNIPPET, 0));
            yaml_catalog.add (new IntelliSenseItem ("bibliography:", "bibliography: references.bib", "path", "BibTeX citation database file", IntelliSenseSymbolKind.OPTION, 0));
            yaml_catalog.add (new IntelliSenseItem ("execute:", "execute:\n  echo: true\n  warning: false\n  message: false", "block", "Global chunk execution defaults", IntelliSenseSymbolKind.SNIPPET, 0));

            // LaTeX Biostatistics & mhchem Macros
            add_latex ("\\alpha", "\\alpha", "α", "Greek lowercase alpha (Type I error rate)", 0);
            add_latex ("\\beta", "\\beta", "β", "Greek lowercase beta (Type II error / regression coeff)", 0);
            add_latex ("\\gamma", "\\gamma", "γ", "Greek lowercase gamma", 0);
            add_latex ("\\delta", "\\delta", "δ", "Greek lowercase delta (Effect size)", 0);
            add_latex ("\\Delta", "\\Delta", "Δ", "Greek uppercase Delta (Difference operator)", 0);
            add_latex ("\\lambda", "\\lambda", "λ", "Greek lowercase lambda (Hazard rate / eigenvalue)", 0);
            add_latex ("\\mu", "\\mu", "μ", "Greek lowercase mu (Population mean)", 0);
            add_latex ("\\sigma", "\\sigma", "σ", "Greek lowercase sigma (Standard deviation)", 0);
            add_latex ("\\chi^2", "\\chi^2", "χ²", "Chi-squared test statistic", 0);
            add_latex ("\\frac", "\\frac{}{}", "\\frac{num}{den}", "Mathematical fraction", 3);
            add_latex ("\\sqrt", "\\sqrt{}", "\\sqrt{radicand}", "Square root radical", 1);
            add_latex ("\\sum", "\\sum_{i=1}^{n}", "∑_{i=1}^{n}", "Summation operator with bounds", 0);
            add_latex ("\\prod", "\\prod_{i=1}^{n}", "∏_{i=1}^{n}", "Product operator with bounds", 0);
            add_latex ("\\int", "\\int_{a}^{b}", "∫_{a}^{b}", "Definite integral with bounds", 0);
            add_latex ("\\hat", "\\hat{}", "\\hat{θ}", "Estimator hat accent", 1);
            add_latex ("\\bar", "\\bar{}", "\\bar{x}", "Sample mean overbar accent", 1);
            add_latex ("\\text", "\\text{}", "\\text{...}", "Upright text inside math mode", 1);
            add_latex ("\\mathbf", "\\mathbf{}", "\\mathbf{X}", "Boldface matrix/vector symbol", 1);
            add_latex ("\\mathcal{N}", "\\mathcal{N}(\\mu, \\sigma^2)", "N(μ, σ²)", "Normal (Gaussian) distribution", 0);
            add_latex ("\\ce", "\\ce{}", "\\ce{H2O}", "mhchem chemical formula or reaction equation", 1);
            add_latex ("\\pm", "\\pm", "±", "Plus-or-minus sign", 0);
            add_latex ("\\leq", "\\leq", "≤", "Less than or equal to", 0);
            add_latex ("\\geq", "\\geq", "≥", "Greater than or equal to", 0);
            add_latex ("\\neq", "\\neq", "≠", "Not equal to", 0);
            add_latex ("\\approx", "\\approx", "≈", "Approximately equal to", 0);
            add_latex ("\\sim", "\\sim", "∼", "Distributed as / tilde relation", 0);
        }

        private static void add_r (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            r_catalog.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_py (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            py_catalog.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_quarto_opt (string label, string insert, string sig, string detail, int backtrack = 0) {
            quarto_opt_catalog.add (new IntelliSenseItem (label, insert, sig, detail, IntelliSenseSymbolKind.OPTION, backtrack));
        }

        private static void add_latex (string label, string insert, string sig, string detail, int backtrack) {
            latex_catalog.add (new IntelliSenseItem (label, insert, sig, detail, IntelliSenseSymbolKind.LATEX_MACRO, backtrack));
        }

        /**
         * Determines the active syntactic context at the given cursor line and line prefix.
         */
        public static IntelliSenseContext detect_context (string document_text, int cursor_line, string line_prefix, string doc_type = "markdown") {
            string trimmed_prefix = line_prefix.strip ();

            // 1. Check if cursor is on a chunk fence line (```{r} or ```)
            if (trimmed_prefix.has_prefix ("```")) {
                return IntelliSenseContext.CHUNK_FENCE_HEADER;
            }

            // 2. Check if cursor is inside a fenced code chunk via ChunkParser
            var chunk = ChunkParser.find_chunk_at_line (document_text, cursor_line);
            if (chunk != null) {
                if (trimmed_prefix.has_prefix ("#|")) {
                    return IntelliSenseContext.QUARTO_HASH_PIPE;
                }
                if (chunk.language == "r") {
                    return IntelliSenseContext.R_CODE;
                }
                if (chunk.language == "python") {
                    return IntelliSenseContext.PYTHON_CODE;
                }
                if (chunk.language == "bash") {
                    return IntelliSenseContext.BASH_CODE;
                }
            }

            // 3. Dedicated script files (.R, .py, .ts)
            string lower_type = doc_type.down ();
            if (lower_type == "r" || lower_type == "rscript") {
                return IntelliSenseContext.R_CODE;
            }
            if (lower_type == "python" || lower_type == "python3" || lower_type == "pyscript" || lower_type == "ipynb") {
                return IntelliSenseContext.PYTHON_CODE;
            }
            if (lower_type == "typescript" || lower_type == "ts" || lower_type == "javascript") {
                return IntelliSenseContext.TYPESCRIPT_CODE;
            }

            // 4. Check YAML frontmatter at top of document
            string[] lines = document_text.split ("\n");
            if (lines.length > 0 && lines[0].strip () == "---" && cursor_line > 0) {
                int closing_yaml = -1;
                for (int i = 1; i < lines.length && i < 60; i++) {
                    if (lines[i].strip () == "---") {
                        closing_yaml = i;
                        break;
                    }
                }
                if (closing_yaml == -1 || cursor_line < closing_yaml) {
                    return IntelliSenseContext.YAML_FRONTMATTER;
                }
            }

            // 5. Check LaTeX command prefix (\alpha, \frac, etc.)
            int last_backslash = line_prefix.last_index_of ("\\");
            if (last_backslash >= 0) {
                string after_bs = line_prefix.substring (last_backslash + 1);
                bool all_alpha = true;
                for (int i = 0; i < after_bs.length; i++) {
                    if (!after_bs[i].isalpha ()) {
                        all_alpha = false;
                        break;
                    }
                }
                if (all_alpha) {
                    return IntelliSenseContext.LATEX_MATH_CHEM;
                }
            }

            return IntelliSenseContext.MARKDOWN_PROSE;
        }

        /**
         * Extracts the current word/token prefix being typed right before the cursor.
         */
        public static string extract_active_token (string line_prefix) {
            int len = line_prefix.length;
            if (len == 0) {
                return "";
            }
            int start = len;
            while (start > 0) {
                char c = line_prefix[start - 1];
                if (c.isalnum () || c == '_' || c == '.' || c == '$' || c == ':' || c == '\\' || c == '-') {
                    start--;
                } else {
                    break;
                }
            }
            return line_prefix.substring (start);
        }

        /**
         * Computes a VS Code-style fuzzy match score (> 0 if matched, 0 if no match).
         */
        public static int compute_match_score (string candidate, string query) {
            if (query.length == 0) {
                return 100;
            }
            string cand_low = candidate.down ();
            string q_low = query.down ();

            if (candidate == query) {
                return 1200;
            }
            if (candidate.has_prefix (query)) {
                return 1050 - (candidate.length - query.length);
            }
            if (cand_low.has_prefix (q_low)) {
                return 900 - (candidate.length - query.length);
            }
            if (cand_low.contains (q_low)) {
                return 650 - cand_low.index_of (q_low) * 5;
            }

            // Ordered character subsequence match (e.g. "ggp" -> "geom_point", "rcsv" -> "read.csv")
            int q_idx = 0;
            int bonus = 0;
            for (int i = 0; i < cand_low.length && q_idx < q_low.length; i++) {
                if (cand_low[i] == q_low[q_idx]) {
                    if (i == 0 || cand_low[i - 1] == '_' || cand_low[i - 1] == '.' || cand_low[i - 1] == '-') {
                        bonus += 25;
                    }
                    q_idx++;
                }
            }
            if (q_idx == q_low.length) {
                return 350 + bonus - candidate.length;
            }
            return 0;
        }

        /**
         * Scans the active document buffer for user-defined variables, functions, and DataFrame columns.
         */
        public static ArrayList<IntelliSenseItem> scan_buffer_symbols (string document_text, IntelliSenseContext ctx, out HashMap<string, ArrayList<string>> discovered_columns) {
            var symbols = new ArrayList<IntelliSenseItem> ();
            discovered_columns = new HashMap<string, ArrayList<string>> ();
            if (ctx != IntelliSenseContext.R_CODE && ctx != IntelliSenseContext.PYTHON_CODE) {
                return symbols;
            }

            var seen = new HashSet<string> ();
            bool has_fences = document_text.contains ("```");
            string active_fence_lang = "";
            bool in_fence = false;

            string[] lines = document_text.split ("\n");
            foreach (string raw_line in lines) {
                string line = raw_line.strip ();
                if (line.has_prefix ("```")) {
                    if (!in_fence) {
                        in_fence = true;
                        string header = line.substring (3).strip ().down ();
                        if (header.has_prefix ("{")) {
                            int close = header.index_of ("}");
                            if (close > 1) header = header.substring (1, close - 1).strip ();
                        }
                        string[] hparts = header.split_set (" ,", 2);
                        active_fence_lang = hparts.length > 0 ? hparts[0].strip () : "";
                    } else {
                        in_fence = false;
                        active_fence_lang = "";
                    }
                    continue;
                }

                if (has_fences) {
                    if (!in_fence) continue;
                    if (ctx == IntelliSenseContext.R_CODE && active_fence_lang != "r") continue;
                    if (ctx == IntelliSenseContext.PYTHON_CODE && active_fence_lang != "python" && active_fence_lang != "py") continue;
                }

                if (line.length == 0 || line.has_prefix ("#")) {
                    continue;
                }

                // 1. Detect R assignments: var_name <- ...
                if (ctx == IntelliSenseContext.R_CODE && line.contains ("<-")) {
                    string[] parts = line.split ("<-", 2);
                    string lhs = parts[0].strip ();
                    string rhs = parts.length > 1 ? parts[1].strip () : "";

                    // Check for df$col <- ... assignment
                    if (lhs.contains ("$")) {
                        string[] df_parts = lhs.split ("$", 2);
                        string df_name = sanitize_identifier (df_parts[0]);
                        string col_name = sanitize_identifier (df_parts[1]);
                        if (df_name.length > 0 && col_name.length > 0) {
                            add_discovered_column (discovered_columns, df_name, col_name);
                        }
                    } else {
                        string ident = sanitize_identifier (lhs);
                        if (ident.length >= 2 && !seen.contains (ident)) {
                            seen.add (ident);
                            if (rhs.has_prefix ("function")) {
                                symbols.add (new IntelliSenseItem (ident, ident + "()", "(...)", "User function defined in document", IntelliSenseSymbolKind.FUNCTION, 1));
                            } else if (rhs.contains ("read.") || rhs.contains ("data.frame") || rhs.contains ("tibble")) {
                                symbols.add (new IntelliSenseItem (ident, ident, "data.frame", "DataFrame defined in document", IntelliSenseSymbolKind.DATAFRAME, 0));
                            } else {
                                symbols.add (new IntelliSenseItem (ident, ident, "object", "Variable defined in document", IntelliSenseSymbolKind.VARIABLE, 0));
                            }
                        }
                    }
                }

                // 2. Detect Python def / class / assignments
                if (ctx == IntelliSenseContext.PYTHON_CODE) {
                    if (line.has_prefix ("def ") && line.contains ("(")) {
                        int open_p = line.index_of ("(");
                        string fn_name = sanitize_identifier (line.substring (4, open_p - 4));
                        if (fn_name.length >= 2 && !seen.contains (fn_name)) {
                            seen.add (fn_name);
                            symbols.add (new IntelliSenseItem (fn_name, fn_name + "()", "(...)", "Python function defined in document", IntelliSenseSymbolKind.FUNCTION, 1));
                        }
                    } else if (line.has_prefix ("class ") && (line.contains (":") || line.contains ("("))) {
                        int end_idx = line.contains ("(") ? line.index_of ("(") : line.index_of (":");
                        if (end_idx > 6) {
                            string cls_name = sanitize_identifier (line.substring (6, end_idx - 6));
                            if (cls_name.length >= 2 && !seen.contains (cls_name)) {
                                seen.add (cls_name);
                                symbols.add (new IntelliSenseItem (cls_name, cls_name, "class", "Python class defined in document", IntelliSenseSymbolKind.FUNCTION, 1));
                            }
                        }
                    } else if (line.contains ("=") && !line.contains ("==") && !line.contains ("!=") && !line.contains ("<=") && !line.contains (">=")) {
                        string[] parts = line.split ("=", 2);
                        string ident = sanitize_identifier (parts[0]);
                        string rhs = parts.length > 1 ? parts[1].strip () : "";
                        if (ident.length >= 2 && !seen.contains (ident) && !ident.contains ("(")) {
                            seen.add (ident);
                            bool is_df = rhs.contains ("read_csv") || rhs.contains ("read_table") || rhs.contains ("DataFrame");
                            symbols.add (new IntelliSenseItem (
                                ident,
                                ident,
                                is_df ? "DataFrame" : "variable",
                                "Symbol defined in document",
                                is_df ? IntelliSenseSymbolKind.DATAFRAME : IntelliSenseSymbolKind.VARIABLE,
                                0
                            ));
                        }
                    }
                }
            }

            return symbols;
        }

        private static void add_discovered_column (HashMap<string, ArrayList<string>> map, string df, string col) {
            var list = map.get (df);
            if (list == null) {
                list = new ArrayList<string> ();
                map.set (df, list);
            }
            if (!list.contains (col)) {
                list.add (col);
            }
        }

        private static string sanitize_identifier (string raw) {
            string s = raw.strip ();
            if (s.has_prefix ("const ") || s.has_prefix ("let ") || s.has_prefix ("var ")) {
                int sp = s.index_of (" ");
                s = s.substring (sp + 1).strip ();
            }
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (!(c.isalnum () || c == '_' || c == '.')) {
                    return "";
                }
            }
            return s;
        }

        /**
         * Primary entry point: Returns ranked completion items for the current cursor state.
         */
        public static ArrayList<IntelliSenseItem> query_completions (
            string document_text,
            int cursor_line,
            string line_prefix,
            string doc_type = "markdown"
        ) {
            ensure_catalogs_initialized ();
            var results = new ArrayList<IntelliSenseItem> ();
            var ctx = detect_context (document_text, cursor_line, line_prefix, doc_type);
            string token = extract_active_token (line_prefix);

            // 1. Chunk Fence Header Context (```{r}, ```{python}, etc.)
            if (ctx == IntelliSenseContext.CHUNK_FENCE_HEADER) {
                results.add (new IntelliSenseItem ("```{r}", "```{r}\n\n```", "Quarto R Chunk", "Insert executable R code chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                results.add (new IntelliSenseItem ("```{python}", "```{python}\n\n```", "Quarto Python Chunk", "Insert executable Python code chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                results.add (new IntelliSenseItem ("```{bash}", "```{bash}\n\n```", "Quarto Bash Chunk", "Insert executable Shell code chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                results.add (new IntelliSenseItem ("```{mermaid}", "```{mermaid}\nflowchart LR\n  A[Start] --> B[End]\n```", "Mermaid Diagram", "Insert Mermaid flowchart chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                return results;
            }

            // 2. Quarto '#|' Hash-Pipe Option Context
            if (ctx == IntelliSenseContext.QUARTO_HASH_PIPE) {
                string opt_query = line_prefix.strip ().substring (2).strip ();
                foreach (var item in quarto_opt_catalog) {
                    int sc = compute_match_score (item.label, opt_query);
                    if (sc > 0) {
                        var copy = clone_with_score (item, sc);
                        results.add (copy);
                    }
                }
                sort_by_score (results);
                return results;
            }

            // 3. YAML Frontmatter Context
            if (ctx == IntelliSenseContext.YAML_FRONTMATTER) {
                foreach (var item in yaml_catalog) {
                    int sc = compute_match_score (item.label, token);
                    if (sc > 0) {
                        results.add (clone_with_score (item, sc));
                    }
                }
                sort_by_score (results);
                return results;
            }

            // 4. LaTeX Math & Chemistry Macro Context (\alpha, \frac, \ce)
            if (ctx == IntelliSenseContext.LATEX_MATH_CHEM) {
                string math_query = token;
                if (math_query.contains ("\\")) {
                    math_query = math_query.substring (math_query.last_index_of ("\\"));
                }
                foreach (var item in latex_catalog) {
                    int sc = compute_match_score (item.label, math_query);
                    if (sc > 0) {
                        results.add (clone_with_score (item, sc));
                    }
                }
                sort_by_score (results);
                return results;
            }

            HashMap<string, ArrayList<string>> discovered_cols;
            var buffer_symbols = scan_buffer_symbols (document_text, ctx, out discovered_cols);

            // 5. R Code Context (including df$col and pkg::fn triggers)
            if (ctx == IntelliSenseContext.R_CODE) {
                // 5a. R DataFrame '$' Column Accessor (e.g., mtcars$mp or clinical_df$)
                if (token.contains ("$")) {
                    string[] parts = token.split ("$", 2);
                    string df_name = parts[0];
                    string col_prefix = parts.length > 1 ? parts[1] : "";

                    if (builtin_df_columns.has_key (df_name)) {
                        foreach (string col in builtin_df_columns.get (df_name).split (",")) {
                            int sc = compute_match_score (col, col_prefix);
                            if (sc > 0) {
                                results.add (new IntelliSenseItem (
                                    df_name + "$" + col,
                                    df_name + "$" + col,
                                    "column",
                                    @"Column of $df_name DataFrame",
                                    IntelliSenseSymbolKind.COLUMN,
                                    0
                                ) { score = sc + 200 });
                            }
                        }
                    }
                    if (discovered_cols.has_key (df_name)) {
                        foreach (string col in discovered_cols.get (df_name)) {
                            int sc = compute_match_score (col, col_prefix);
                            if (sc > 0) {
                                results.add (new IntelliSenseItem (
                                    df_name + "$" + col,
                                    df_name + "$" + col,
                                    "column",
                                    @"Discovered column of $df_name",
                                    IntelliSenseSymbolKind.COLUMN,
                                    0
                                ) { score = sc + 200 });
                            }
                        }
                    }
                    sort_by_score (results);
                    return results;
                }

                // 5b. R Package Namespace Accessor (e.g., dplyr::, survival::, ggplot2::, stats::)
                if (token.contains ("::")) {
                    string[] parts = token.split ("::", 2);
                    string pkg_name = parts[0];
                    string fn_prefix = parts.length > 1 ? parts[1] : "";
                    string pkg_tag = @"[$pkg_name]";

                    foreach (var item in r_catalog) {
                        if (item.detail.contains (pkg_tag)) {
                            int sc = compute_match_score (item.label, fn_prefix);
                            if (sc > 0) {
                                string ins = item.insert_text.has_prefix (pkg_name + "::")
                                    ? item.insert_text
                                    : @"$pkg_name::$(item.insert_text)";
                                results.add (new IntelliSenseItem (
                                    @"$pkg_name::$(item.label)",
                                    ins,
                                    item.signature,
                                    item.detail,
                                    item.kind,
                                    item.cursor_backtrack
                                ) { score = sc + 200 });
                            }
                        }
                    }
                    sort_by_score (results);
                    return results;
                }

                // 5c. Standard R Functions + Live Buffer Symbols
                if (token.length == 0) {
                    return results;
                }
                foreach (var sym in buffer_symbols) {
                    int sc = compute_match_score (sym.label, token);
                    if (sc > 0) {
                        results.add (clone_with_score (sym, sc + 50));
                    }
                }
                foreach (var item in r_catalog) {
                    int sc = compute_match_score (item.label, token);
                    if (sc > 0) {
                        results.add (clone_with_score (item, sc));
                    }
                }
                sort_by_score (results);
                return results;
            }

            // 6. Python Code Context
            if (ctx == IntelliSenseContext.PYTHON_CODE) {
                if (token.length == 0) {
                    return results;
                }
                foreach (var sym in buffer_symbols) {
                    int sc = compute_match_score (sym.label, token);
                    if (sc > 0) {
                        results.add (clone_with_score (sym, sc + 50));
                    }
                }
                foreach (var item in py_catalog) {
                    int sc = compute_match_score (item.label, token);
                    if (sc > 0) {
                        results.add (clone_with_score (item, sc));
                    }
                }
                sort_by_score (results);
                return results;
            }

            return results;
        }

        private static IntelliSenseItem clone_with_score (IntelliSenseItem src, int score) {
            var copy = new IntelliSenseItem (
                src.label,
                src.insert_text,
                src.signature,
                src.detail,
                src.kind,
                src.cursor_backtrack
            );
            copy.score = score;
            return copy;
        }

        private static void sort_by_score (ArrayList<IntelliSenseItem> list) {
            list.sort ((a, b) => {
                if (a.score != b.score) {
                    return b.score - a.score;
                }
                return strcmp (a.label, b.label);
            });
        }
    }
}
