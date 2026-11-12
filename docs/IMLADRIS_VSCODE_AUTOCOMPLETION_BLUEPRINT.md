<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# IMLADRIS FEATURE SPECIFICATION & BUILDING PLAN: VS CODE-GRADE POLYGLOT AUTO-COMPLETION (NON-AI INTELLISENSE)

**Document ID:** `IMLADRIS-INTELLISENSE-PLAN-2026-003`  
**Target Model:** Gemini 3.8-Flash-Medium  
**Target Codebase:** Imladris Scientific Workbench (`v0.20.0` -> `v0.21.0`)  
**Stack:** Vala, GTK4, Libadwaita (`libadwaita-1`), `gtksourceview-5`, `gee-0.8`  
**Compliance Standards:** ASD-STE100 (Simplified Technical English), REUSE 3.3, Zero External Dependencies, 100% Offline & Non-AI Deterministic Execution  

---

## 1. ARCHITECTURAL OBJECTIVE

Implement a **deterministic, zero-latency, non-AI auto-completion and IntelliSense subsystem** modeled after **Visual Studio Code** and **Posit RStudio / Positron**. The feature operates 100% offline with zero LLM or network dependencies and provides:

1. **Context-Aware Polyglot Symbol & Signature Completion (`CodeIntelliSenseEngine` + `CodeIntelliSenseProvider`):**
   - Automatically detects the cursor's exact syntactic zone inside `.qmd`, `.Rmd`, `.ipynb`, `.R`, `.py`, `.ts`, `.html`, and `.md` buffers:
     - **R Code Context (`R_CODE`):** Completes `base`, `stats`, `utils`, `dplyr`, `tidyr`, `ggplot2`, `readr`, `survival`, `gtsummary`, `DESeq2`, and `bio3d` functions with parameter signatures.
     - **R Namespace & DataFrame Member Triggers (`::` and `$`):** Typing `dplyr::`, `ggplot2::`, `survival::`, or `stats::` filters strictly to that package's exported symbols. Typing `mtcars$` or `<df_name>$` completes DataFrame column names scanned from both built-in datasets and the active document buffer.
     - **Python Code Context (`PYTHON_CODE`):** Completes Python keywords, built-ins, and scientific dot-members (`pd.`, `np.`, `plt.`, `sns.`, `scipy.stats.`, `Bio.`).
     - **Live Buffer & REPL Environment Symbol Indexing:** Dynamically extracts variables (`<-`, `=`), function definitions (`function(...)`, `def ...`), classes (`class ...`), and DataFrame columns from the current editor buffer, and merges them with live session objects cached in `EnvironmentController`.
     - **Quarto / R Markdown Hash-Pipe Options (`#| `):** Triggering after `#|` suggests Quarto chunk options (`echo: true`, `eval: false`, `warning: false`, `fig-cap: ""`, `fig-width: 8`, `label: ""`, `cache: true`).
     - **Fence Header & YAML Frontmatter Completion:** Suggests ```` ```{r} ````, ```` ```{python} ````, ```` ```{bash} ````, ```` ```{mermaid} ```` on fence lines and Quarto YAML keys inside `---` frontmatter blocks.
     - **LaTeX Biostatistics & `mhchem` Macros (`\`):** Triggering on `\` suggests LaTeX math and chemistry commands (`\alpha`, `\beta`, `\frac{}{}`, `\sqrt{}`, `\sum_{i=1}^{n}`, `\int_{a}^{b}`, `\ce{}`).
2. **VS Code-Style Fuzzy Prefix & Subsequence Ranking:**
   - Ranks exact prefix matches (`1000`), case-insensitive prefix matches (`850`), snake_case / camelCase word-boundary matches (`650`), and ordered character subsequence matches (`450`).
3. **Smart Cursor Placement & Bracket/Quote Auto-Pairing (`BracketAutoPairController`):**
   - Selecting a function or LaTeX macro with arguments (e.g., `ggplot()` or `\frac{}{}`) places the cursor inside the parentheses/braces automatically.
   - Typing `(`, `[`, `{`, `"`, `'`, or `` ` `` auto-inserts the closing delimiter (or wraps the active text selection) and skips over existing closing delimiters when typed.
   - Pressing `Ctrl+Space` explicitly opens the completion popup at any cursor position.

---

## 2. ARCHITECTURE & MODULE TREE

```text
src/
├── core/
│   └── SettingsManager.vala                # [MODIFY] Add code_intellisense_enabled & auto_close_brackets settings
├── editor/
│   ├── CitationCompletionProvider.vala     # [EXISTING] Zotero @citekey completion
│   ├── CodeIntelliSenseEngine.vala         # [NEW] Context detector, symbol catalog, AST/buffer scanner & fuzzy ranker
│   └── CodeIntelliSenseProvider.vala       # [NEW] GtkSource.CompletionProvider + BracketAutoPairController
├── ui/
│   ├── EnvironmentController.vala          # [MODIFY] Expose get_cached_variables() for live REPL object completion
│   └── PreferencesDialog.vala              # [MODIFY] Add Editor Auto-Completion & Bracket Auto-Pair switches
└── DocumentPage.vala                       # [MODIFY] Wire CodeIntelliSenseProvider & BracketAutoPairController
tests/
└── test_mallorn_sandbox.vala               # [MODIFY] Add deterministic unit tests for CodeIntelliSenseEngine
```

### Data-Flow Diagram
```text
[User Keystroke / Ctrl+Space in GtkSource.View]
       │
       ├──► [BracketAutoPairController (Gtk.EventControllerKey)]
       │       ├── Auto-pairs (), [], {}, "", '', `` or wraps active selection
       │       └── Triggers source_view.show_completion() on Ctrl+Space / '.', '$', ':', '\', '#'
       │
       └──► [CodeIntelliSenseProvider : GtkSource.CompletionProvider (Priority = 25)]
               │
               ▼
       [CodeIntelliSenseEngine.query_completions(buffer_text, cursor_line, line_prefix, doc_type, env_vars)]
               ├── 1. detect_context() ──► R_CODE | PYTHON_CODE | QUARTO_HASH_PIPE | LATEX_MATH_CHEM | YAML | MARKDOWN
               ├── 2. extract_trigger_token() ──► prefix, namespace_prefix ("dplyr::"), member_object ("mtcars$", "pd.")
               ├── 3. Match Curated Standard Library & Scientific Catalog
               ├── 4. Scan Active Buffer Assignments, Functions & DataFrame Columns (df$col)
               ├── 5. Merge Active REPL Session Objects from EnvironmentController.get_cached_variables()
               └── 6. Score & Sort via VS Code Prefix/Camel/Subsequence Ranker ──► GLib.ListStore<IntelliSenseProposal>
```

---

## 3. WORK PACKAGES FOR GEMINI 3.8-FLASH-MEDIUM

> [!IMPORTANT]
> **EXECUTION DIRECTIVE:**
> Execute Work Packages `WP-01` through `WP-04` in order. Every file and edit below is complete, self-contained, and adheres to **ASD-STE100** and **REUSE 3.3**.

---

### WP-01: Create `src/editor/CodeIntelliSenseEngine.vala`

Create the pure-Vala, deterministic symbol resolution and fuzzy-ranking engine in `src/editor/CodeIntelliSenseEngine.vala`. This class has zero UI widget dependencies so it can be linked directly into both the main `imladris` binary and the automated unit test suites.

#### Complete Source for `src/editor/CodeIntelliSenseEngine.vala`
```vala
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
        private static HashMap<string, string[]>? builtin_df_columns = null;

        private static void ensure_catalogs_initialized () {
            if (r_catalog != null) {
                return;
            }

            r_catalog = new ArrayList<IntelliSenseItem> ();
            py_catalog = new ArrayList<IntelliSenseItem> ();
            quarto_opt_catalog = new ArrayList<IntelliSenseItem> ();
            yaml_catalog = new ArrayList<IntelliSenseItem> ();
            latex_catalog = new ArrayList<IntelliSenseItem> ();
            builtin_df_columns = new HashMap<string, string[]> ();

            // Built-in R dataset columns for instant '$' completion
            builtin_df_columns.set ("mtcars", { "mpg", "cyl", "disp", "hp", "drat", "wt", "qsec", "vs", "am", "gear", "carb" });
            builtin_df_columns.set ("iris", { "Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width", "Species" });
            builtin_df_columns.set ("ToothGrowth", { "len", "supp", "dose" });
            builtin_df_columns.set ("PlantGrowth", { "weight", "group" });
            builtin_df_columns.set ("airquality", { "Ozone", "Solar.R", "Wind", "Temp", "Month", "Day" });
            builtin_df_columns.set ("clinical_df", { "USUBJID", "ARM", "AGE", "SEX", "AVAL", "EVENT", "CNSR", "BMK1" });
            builtin_df_columns.set ("deseq2_res", { "gene_symbol", "baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj" });

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
            add_py ("plt.axvline", "plt.axvline(0.0, linestyle=\"--\", color=\"#475569\")", "(x=0, ymin=0, ymax=1, ls='--_')", "Add a vertical line across the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
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
            add_quarto_opt ("label:", "label: fig-", "string", "Unique chunk identifier for cross-referencing");
            add_quarto_opt ("fig-cap:", "fig-cap: \"\"", "string", "Figure caption text for publication output", 1);
            add_quarto_opt ("fig-width:", "fig-width: 8", "number", "Figure width in inches");
            add_quarto_opt ("fig-height:", "fig-height: 5", "number", "Figure height in inches");
            add_quarto_opt ("fig-dpi:", "fig-dpi: 300", "number", "Figure resolution in dots per inch (DPI)");
            add_quarto_opt ("tbl-cap:", "tbl-cap: \"\"", "string", "Table caption text for cross-referenced tables", 1);
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
            if ( candidate.has_prefix (query)) {
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
            var seen = new HashSet<string> ();

            string[] lines = document_text.split ("\n");
            foreach (string raw_line in lines) {
                string line = raw_line.strip ();
                if (line.length == 0 || line.has_prefix ("#")) {
                    continue;
                }

                // 1. Detect R assignments: var_name <- ...
                if (line.contains ("<-")) {
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
                if (line.has_prefix ("def ") && line.contains ("(")) {
                    int open_p = line.index_of ("(");
                    string fn_name = sanitize_identifier (line.substring (4, open_p - 4));
                    if (fn_name.length >= 2 && !seen.contains (fn_name)) {
                        seen.add (fn_name);
                        symbols.add (new IntelliSenseItem (fn_name, fn_name + "()", "(...)", "Python function defined in document", IntelliSenseSymbolKind.FUNCTION, 1));
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
                foreach (var item in latex_catalog) {
                    int sc = compute_match_score (item.label, token);
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
                        foreach (string col in builtin_df_columns.get (df_name)) {
                            int sc = compute_match_score (col, col_prefix);
                            if (sc > 0) {
                                results.add (new IntelliSenseItem (
                                    @"$df_name$$col",
                                    @"$df_name$$col",
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
                                    @"$df_name$$col",
                                    @"$df_name$$col",
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
```

---

### WP-02: Create `src/editor/CodeIntelliSenseProvider.vala` (GTKSourceView 5 Provider + VS Code Bracket Auto-Pairing)

Create `src/editor/CodeIntelliSenseProvider.vala` implementing `GtkSource.CompletionProvider` and `BracketAutoPairController`.

#### Complete Source for `src/editor/CodeIntelliSenseProvider.vala`
```vala
// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: GtkSourceView 5 VS Code-style completion provider and
 * automatic bracket/quote pairing controller.
 *
 * Architectural Position:
 * Bridges CodeIntelliSenseEngine and EnvironmentController to GtkSource.View.
 *
 * Concurrency Constraints:
 * Runs exclusively on the GTK4 MainContext thread.
 */

using GLib;
using Gtk;
using GtkSource;
using Gee;
using Imladris.Core;
using Imladris.UI;

namespace Imladris.Editor {

    public class IntelliSenseProposal : GLib.Object, GtkSource.CompletionProposal {
        public IntelliSenseItem item { get; set; }

        public IntelliSenseProposal (IntelliSenseItem item) {
            this.item = item;
        }
    }

    public class CodeIntelliSenseProvider : GLib.Object, GtkSource.CompletionProvider {

        private weak DocumentPage? doc_page;

        public CodeIntelliSenseProvider (DocumentPage? page = null) {
            this.doc_page = page;
        }

        public string? get_title () {
            return "IntelliSense";
        }

        public int get_priority (GtkSource.CompletionContext context) {
            return 25;
        }

        public bool is_trigger (Gtk.TextIter iter, unichar ch) {
            if (!SettingsManager.get_default ().code_intellisense_enabled) {
                return false;
            }
            return ch.isalnum () || ch == '.' || ch == '$' || ch == ':' || ch == '\\' || ch == '|' || ch == '{' || ch == '_';
        }

        public bool key_activates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal, uint keyval, Gdk.ModifierType state) {
            return keyval == Gdk.Key.Tab || keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter;
        }

        public GenericArray<GtkSource.CompletionProposal>? list_alternates (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            return null;
        }

        public void refilter (GtkSource.CompletionContext context, GLib.ListModel model) {
            // Re-populated cleanly via populate_async on keystrokes
        }

        public void display (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal, GtkSource.CompletionCell cell) {
            var p = proposal as IntelliSenseProposal;
            if (p == null) {
                return;
            }

            switch (cell.get_column ()) {
                case GtkSource.CompletionColumn.ICON:
                    cell.set_icon_name (p.item.kind.to_icon_name ());
                    break;
                case GtkSource.CompletionColumn.TYPED_TEXT:
                    cell.set_text (p.item.label);
                    break;
                case GtkSource.CompletionColumn.AFTER:
                    cell.set_text (" " + p.item.signature);
                    break;
                case GtkSource.CompletionColumn.DETAILS:
                    cell.set_text (p.item.detail);
                    break;
                default:
                    break;
            }
        }

        public void activate (GtkSource.CompletionContext context, GtkSource.CompletionProposal proposal) {
            var p = proposal as IntelliSenseProposal;
            if (p == null) {
                return;
            }

            Gtk.TextIter cursor_iter;
            context.get_bounds (null, out cursor_iter);
            var buffer = context.get_buffer ();

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            buffer.begin_user_action ();

            if (line_prefix.strip ().has_prefix ("#|") && p.item.kind == IntelliSenseSymbolKind.OPTION) {
                int pipe_idx = line_prefix.index_of ("#|");
                Gtk.TextIter replace_start = line_start;
                replace_start.forward_chars (pipe_idx);
                buffer.delete (ref replace_start, ref cursor_iter);
                string replacement = "#| " + p.item.insert_text;
                buffer.insert (ref replace_start, replacement, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            } else if (line_prefix.strip ().has_prefix ("```") && p.item.kind == IntelliSenseSymbolKind.SNIPPET) {
                int fence_idx = line_prefix.index_of ("```");
                Gtk.TextIter replace_start = line_start;
                replace_start.forward_chars (fence_idx);
                buffer.delete (ref replace_start, ref cursor_iter);
                buffer.insert (ref replace_start, p.item.insert_text, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            } else {
                string token = CodeIntelliSenseEngine.extract_active_token (line_prefix);
                Gtk.TextIter replace_start = cursor_iter;
                if (token.length > 0) {
                    replace_start.backward_chars (token.char_count ());
                    buffer.delete (ref replace_start, ref cursor_iter);
                }
                buffer.insert (ref replace_start, p.item.insert_text, -1);
                if (p.item.cursor_backtrack > 0) {
                    replace_start.backward_chars (p.item.cursor_backtrack);
                    buffer.place_cursor (replace_start);
                }
            }

            buffer.end_user_action ();
        }

        public async GLib.ListModel populate_async (GtkSource.CompletionContext context, GLib.Cancellable? cancellable) throws GLib.Error {
            var store = new GLib.ListStore (typeof (IntelliSenseProposal));
            if (!SettingsManager.get_default ().code_intellisense_enabled) {
                return store;
            }

            Gtk.TextIter cursor_iter;
            context.get_bounds (null, out cursor_iter);
            var buffer = context.get_buffer ();

            Gtk.TextIter line_start = cursor_iter;
            line_start.set_line_offset (0);
            string line_prefix = buffer.get_text (line_start, cursor_iter, false);

            Gtk.TextIter doc_start, doc_end;
            buffer.get_bounds (out doc_start, out doc_end);
            string full_text = buffer.get_text (doc_start, doc_end, false);

            string doc_type = doc_page != null ? doc_page.doc_type : "markdown";
            int cursor_line = cursor_iter.get_line ();

            var items = CodeIntelliSenseEngine.query_completions (
                full_text,
                cursor_line,
                line_prefix,
                doc_type
            );

            // Merge live REPL session variables from EnvironmentController when in R or Python context
            var ctx = CodeIntelliSenseEngine.detect_context (full_text, cursor_line, line_prefix, doc_type);
            if ((ctx == IntelliSenseContext.R_CODE || ctx == IntelliSenseContext.PYTHON_CODE) && doc_page != null && doc_page.panel_registry != null) {
                string token = CodeIntelliSenseEngine.extract_active_token (line_prefix);
                if (token.length > 0 && !token.contains ("$") && !token.contains ("::")) {
                    var env_vars = doc_page.panel_registry.environment_controller.get_cached_variables ();
                    foreach (var ev in env_vars) {
                        int sc = CodeIntelliSenseEngine.compute_match_score (ev.name, token);
                        if (sc > 0) {
                            var kind = ev.is_dataframe ? IntelliSenseSymbolKind.DATAFRAME : IntelliSenseSymbolKind.VARIABLE;
                            var env_item = new IntelliSenseItem (
                                ev.name,
                                ev.name,
                                ev.var_type,
                                @"Active REPL Object ($(ev.dimensions))",
                                kind,
                                0
                            ) { score = sc + 100 };
                            store.append (new IntelliSenseProposal (env_item));
                        }
                    }
                }
            }

            int max_items = 25;
            int added = 0;
            foreach (var item in items) {
                if (added >= max_items) {
                    break;
                }
                store.append (new IntelliSenseProposal (item));
                added++;
            }

            return store;
        }
    }

    /**
     * Implements VS Code-style automatic bracket/quote closing, selection wrapping,
     * overtype skip-over, and Ctrl+Space manual completion invocation.
     */
    public class BracketAutoPairController : GLib.Object {

        public static void attach (GtkSource.View view, GtkSource.Buffer buffer) {
            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);

            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                // 1. Ctrl+Space: Trigger Completion Popup Explicitly (VS Code standard shortcut)
                if (keyval == Gdk.Key.space && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    view.show_completion ();
                    return true;
                }

                if (!SettingsManager.get_default ().auto_close_brackets) {
                    return false;
                }

                // Ignore when Ctrl or Alt is held
                if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) != 0) {
                    return false;
                }

                unichar ch = Gdk.keyval_to_unicode (keyval);
                if (ch == 0) {
                    return false;
                }

                string? open_str = null;
                string? close_str = null;
                bool is_quote = false;

                switch (ch) {
                    case '(':
                        open_str = "("; close_str = ")"; break;
                    case '[':
                        open_str = "["; close_str = "]"; break;
                    case '{':
                        open_str = "{"; close_str = "}"; break;
                    case '"':
                        open_str = "\""; close_str = "\""; is_quote = true; break;
                    case '\'':
                        open_str = "'"; close_str = "'"; is_quote = true; break;
                    case '`':
                        open_str = "`"; close_str = "`"; is_quote = true; break;
                    default:
                        break;
                }

                // 2. Overtype skip-over when typing closing bracket or quote already at cursor
                if (ch == ')' || ch == ']' || ch == '}' || is_quote) {
                    Gtk.TextIter s_sel, e_sel;
                    if (!buffer.get_selection_bounds (out s_sel, out e_sel)) {
                        Gtk.TextIter cur;
                        buffer.get_iter_at_mark (out cur, buffer.get_insert ());
                        if (cur.get_char () == ch) {
                            cur.forward_char ();
                            buffer.place_cursor (cur);
                            return true;
                        }
                    }
                }

                if (open_str == null || close_str == null) {
                    return false;
                }

                // 3. Selection Wrapping: If text is selected, wrap selection in open_str ... close_str
                Gtk.TextIter sel_start, sel_end;
                if (buffer.get_selection_bounds (out sel_start, out sel_end)) {
                    string selected_text = buffer.get_text (sel_start, sel_end, false);
                    string wrapped = open_str + selected_text + close_str;
                    buffer.begin_user_action ();
                    buffer.delete (ref sel_start, ref sel_end);
                    buffer.insert (ref sel_start, wrapped, -1);
                    buffer.end_user_action ();
                    return true;
                }

                // 4. Auto-Close Pair Insertion
                Gtk.TextIter cursor;
                buffer.get_iter_at_mark (out cursor, buffer.get_insert ());

                // Avoid auto-closing single quote inside words/contractions (e.g. don't)
                if (ch == '\'') {
                    Gtk.TextIter prev = cursor;
                    if (prev.backward_char () && prev.get_char ().isalnum ()) {
                        return false;
                    }
                }

                buffer.begin_user_action ();
                buffer.insert (ref cursor, open_str + close_str, -1);
                cursor.backward_char ();
                buffer.place_cursor (cursor);
                buffer.end_user_action ();

                if (ch == '{') {
                    view.show_completion ();
                }
                return true;
            });

            view.add_controller (key_ctrl);
        }
    }
}
```

---

### WP-03: Wire Settings, `EnvironmentController`, `DocumentPage`, `PreferencesDialog`, and `meson.build`

#### 3.1 Update [src/core/SettingsManager.vala](file:///home/antonio/Projects/imladris/src/core/SettingsManager.vala)
Add two boolean properties to `SettingsManager`:
```vala
public bool code_intellisense_enabled { get; set; default = true; }
public bool auto_close_brackets { get; set; default = true; }
```

#### 3.2 Update [src/ui/EnvironmentController.vala](file:///home/antonio/Projects/imladris/src/ui/EnvironmentController.vala)
Add a public read-only accessor so `CodeIntelliSenseProvider` can query live R/Python session variables in $O(1)$ time:
```vala
public Gee.ArrayList<EnvVariableItem> get_cached_variables () {
    return last_items;
}
```

#### 3.3 Update `setup_completion ()` in [src/DocumentPage.vala](file:///home/antonio/Projects/imladris/src/DocumentPage.vala#L776-L794)
Replace `setup_completion ()` in `src/DocumentPage.vala` with:
```vala
        private void setup_completion () {
            var completion = source_view.get_completion ();
            completion.select_on_show = true;
            completion.show_icons = true;
            completion.remember_info_visibility = true;

            var intellisense_provider = new Editor.CodeIntelliSenseProvider (this);
            completion.add_provider (intellisense_provider);

            var citation_provider = new Editor.CitationCompletionProvider (this);
            completion.add_provider (citation_provider);

            var ai_provider = new AI.AiCompletionProvider ();
            completion.add_provider (ai_provider);

            var words_provider = new GtkSource.CompletionWords ("Document Vocabulary");
            words_provider.register (source_buffer);
            words_provider.minimum_word_size = 2;
            words_provider.priority = 10;
            completion.add_provider (words_provider);

            var snippets_provider = new GtkSource.CompletionSnippets ();
            snippets_provider.priority = 20;
            completion.add_provider (snippets_provider);

            Editor.BracketAutoPairController.attach (source_view, source_buffer);
        }
```

#### 3.4 Register New Files in [meson.build](file:///home/antonio/Projects/imladris/meson.build)
1. Add `'src/editor/CodeIntelliSenseEngine.vala'` and `'src/editor/CodeIntelliSenseProvider.vala'` to `sources = files(...)`.
2. Add `'src/editor/CodeIntelliSenseEngine.vala'` to `test_sources = files(...)` so `test_mallorn_sandbox` can test it directly.

---

### WP-04: Expand Unit Test Suite (`tests/test_mallorn_sandbox.vala`)

Add a dedicated test function `test_vscode_polyglot_intellisense ()` in [tests/test_mallorn_sandbox.vala](file:///home/antonio/Projects/imladris/tests/test_mallorn_sandbox.vala) and register it in `main ()` with `Test.add_func ("/editor/vscode_polyglot_intellisense", test_vscode_polyglot_intellisense);`:

```vala
    private static void test_vscode_polyglot_intellisense () {
        string sample_qmd = """---
title: "Clinical Trial"
---

# Introduction
Let $\alpha = 0.05$.

```{r}
#| echo: true
clinical_cohort <- read.csv("patients.csv")
clinical_cohort$patient_age <- 65
ggplot(mtcars, aes(x = mpg, y = hp))
```

```{python}
import pandas as pd
df_omics = pd.read_csv("counts.tsv")
```
""";

        // 1. YAML Frontmatter context detection & completion
        var yaml_ctx = Editor.CodeIntelliSenseEngine.detect_context (sample_qmd, 1, "ti");
        assert (yaml_ctx == Editor.IntelliSenseContext.YAML_FRONTMATTER);
        var yaml_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 1, "ti");
        assert (yaml_items.size > 0);
        assert (yaml_items[0].label == "title:");

        // 2. LaTeX Math macro completion
        var latex_ctx = Editor.CodeIntelliSenseEngine.detect_context (sample_qmd, 5, "Let $\\alp");
        assert (latex_ctx == Editor.IntelliSenseContext.LATEX_MATH_CHEM);
        var latex_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 5, "Let $\\alp");
        assert (latex_items.size > 0);
        assert (latex_items[0].label == "\\alpha");

        // 3. Quarto '#|' Hash-Pipe option completion
        var opt_ctx = Editor.CodeIntelliSenseEngine.detect_context (sample_qmd, 8, "#| warn");
        assert (opt_ctx == Editor.IntelliSenseContext.QUARTO_HASH_PIPE);
        var opt_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 8, "#| warn");
        assert (opt_items.size > 0);
        assert (opt_items[0].insert_text == "warning: false");

        // 4. R DataFrame '$' Column completion (built-in mtcars + buffer-discovered clinical_cohort$patient_age)
        var r_cols = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 10, "mtcars$mp");
        assert (r_cols.size > 0);
        assert (r_cols[0].insert_text == "mtcars$mpg");

        var user_cols = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 10, "clinical_cohort$pat");
        assert (user_cols.size > 0);
        assert (user_cols[0].insert_text == "clinical_cohort$patient_age");

        // 5. R Namespace '::' completion
        var ns_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 10, "survival::cox");
        assert (ns_items.size > 0);
        assert (ns_items[0].label == "survival::coxph");

        // 6. Python dot-member completion & buffer variable discovery
        var py_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 16, "pd.read_c");
        assert (py_items.size > 0);
        assert (py_items[0].label == "pd.read_csv");

        var py_var_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 16, "df_om");
        assert (py_var_items.size > 0);
        assert (py_var_items[0].label == "df_omics");
    }
```
