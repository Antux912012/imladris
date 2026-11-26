// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Single Responsibility: Deterministic, non-AI polyglot symbol indexing, context detection,
 * and fuzzy completion ranking engine (VS Code + RStudio parity).
 *
 * Architectural Position:
 * Core editor intelligence layer. Parses active document buffers, resolves language contexts
 * via ChunkParser, and ranks standard library, bioinformatics, biostatistics, Quarto, Markdown,
 * HTML, LaTeX, Bash, TypeScript, and user-defined symbols.
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
        HTML_CODE,
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
        LATEX_MACRO,
        TAG,
        REFERENCE;

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
                case TAG:
                    return "text-x-generic-symbolic";
                case REFERENCE:
                    return "insert-link-symbolic";
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
        private static ArrayList<IntelliSenseItem>? py_df_methods = null;
        private static ArrayList<IntelliSenseItem>? ts_catalog = null;
        private static ArrayList<IntelliSenseItem>? bash_catalog = null;
        private static ArrayList<IntelliSenseItem>? md_catalog = null;
        private static ArrayList<IntelliSenseItem>? html_catalog = null;
        private static ArrayList<IntelliSenseItem>? quarto_opt_catalog = null;
        private static ArrayList<IntelliSenseItem>? yaml_catalog = null;
        private static ArrayList<IntelliSenseItem>? latex_catalog = null;
        private static ArrayList<string>? r_packages = null;
        private static ArrayList<string>? py_modules = null;
        private static HashMap<string, string>? builtin_df_columns = null;
        private static HashMap<string, string>? r_function_args = null;
        private static GLib.Regex? cached_hp_rx = null;
        private static GLib.Regex? cached_id_rx = null;
        private static GLib.Regex? cached_r_dollar_rx = null;
        private static GLib.Regex? cached_py_col_rx = null;
        private static GLib.Regex? cached_html_tag_rx = null;

        private static void ensure_catalogs_initialized () {
            if (r_catalog != null) {
                return;
            }

            r_catalog = new ArrayList<IntelliSenseItem> ();
            py_catalog = new ArrayList<IntelliSenseItem> ();
            py_df_methods = new ArrayList<IntelliSenseItem> ();
            ts_catalog = new ArrayList<IntelliSenseItem> ();
            bash_catalog = new ArrayList<IntelliSenseItem> ();
            md_catalog = new ArrayList<IntelliSenseItem> ();
            html_catalog = new ArrayList<IntelliSenseItem> ();
            quarto_opt_catalog = new ArrayList<IntelliSenseItem> ();
            yaml_catalog = new ArrayList<IntelliSenseItem> ();
            latex_catalog = new ArrayList<IntelliSenseItem> ();
            r_packages = new ArrayList<string> ();
            py_modules = new ArrayList<string> ();
            builtin_df_columns = new HashMap<string, string> ();
            r_function_args = new HashMap<string, string> ();

            // Built-in R dataset columns for instant '$' completion
            builtin_df_columns.set ("mtcars", "mpg,cyl,disp,hp,drat,wt,qsec,vs,am,gear,carb");
            builtin_df_columns.set ("iris", "Sepal.Length,Sepal.Width,Petal.Length,Petal.Width,Species");
            builtin_df_columns.set ("ToothGrowth", "len,supp,dose");
            builtin_df_columns.set ("PlantGrowth", "weight,group");
            builtin_df_columns.set ("airquality", "Ozone,Solar.R,Wind,Temp,Month,Day");
            builtin_df_columns.set ("diamonds", "carat,cut,color,clarity,depth,table,price,x,y,z");
            builtin_df_columns.set ("penguins", "species,island,bill_length_mm,bill_depth_mm,flipper_length_mm,body_mass_g,sex,year");
            builtin_df_columns.set ("clinical_df", "USUBJID,ARM,AGE,SEX,AVAL,EVENT,CNSR,BMK1");
            builtin_df_columns.set ("deseq2_res", "gene_symbol,baseMean,log2FoldChange,lfcSE,stat,pvalue,padj");

            // R Named Function Parameters (RStudio-style argument completion inside fn(...))
            r_function_args.set ("ggplot", "data,mapping");
            r_function_args.set ("aes", "x,y,color,colour,fill,size,shape,alpha,linetype,group,label");
            r_function_args.set ("geom_point", "mapping,data,alpha,size,shape,color,position,na.rm");
            r_function_args.set ("geom_line", "mapping,data,linewidth,linetype,color,alpha,na.rm");
            r_function_args.set ("geom_bar", "mapping,data,stat,position,width,fill,color,na.rm");
            r_function_args.set ("geom_col", "mapping,data,position,width,fill,color,na.rm");
            r_function_args.set ("geom_boxplot", "mapping,data,width,outlier.shape,fill,color,alpha,na.rm");
            r_function_args.set ("geom_histogram", "mapping,data,bins,binwidth,fill,color,alpha,position");
            r_function_args.set ("geom_smooth", "mapping,data,method,formula,se,level,color,fill,linetype");
            r_function_args.set ("labs", "title,subtitle,caption,tag,x,y,color,fill,size,shape");
            r_function_args.set ("ggsave", "filename,plot,device,width,height,units,dpi,bg");
            r_function_args.set ("facet_wrap", "facets,nrow,ncol,scales,labeller");
            r_function_args.set ("facet_grid", "rows,cols,scales,space,labeller");
            r_function_args.set ("lm", "formula,data,subset,weights,na.action,method");
            r_function_args.set ("glm", "formula,family,data,weights,subset,na.action");
            r_function_args.set ("t.test", "x,y,alternative,mu,paired,var.equal,conf.level");
            r_function_args.set ("wilcox.test", "x,y,alternative,mu,paired,exact,correct,conf.int,conf.level");
            r_function_args.set ("cor.test", "x,y,alternative,method,exact,conf.level");
            r_function_args.set ("cor", "x,y,use,method");
            r_function_args.set ("mean", "x,trim,na.rm");
            r_function_args.set ("median", "x,na.rm");
            r_function_args.set ("sd", "x,na.rm");
            r_function_args.set ("var", "x,y,na.rm,use");
            r_function_args.set ("sum", "na.rm");
            r_function_args.set ("min", "na.rm");
            r_function_args.set ("max", "na.rm");
            r_function_args.set ("quantile", "x,probs,na.rm,names,type");
            r_function_args.set ("read.csv", "file,header,sep,quote,dec,fill,stringsAsFactors,na.strings,check.names");
            r_function_args.set ("read.delim", "file,header,sep,quote,dec,fill,stringsAsFactors,na.strings");
            r_function_args.set ("write.csv", "x,file,row.names,quote,na");
            r_function_args.set ("read_csv", "file,col_names,col_types,na,skip,n_max,show_col_types");
            r_function_args.set ("write_csv", "x,file,na,append,col_names");
            r_function_args.set ("p.adjust", "p,method,n");
            r_function_args.set ("prcomp", "x,retx,center,scale.,tol,rank.");
            r_function_args.set ("head", "x,n");
            r_function_args.set ("tail", "x,n");
            r_function_args.set ("seq", "from,to,by,length.out,along.with");
            r_function_args.set ("sample", "x,size,replace,prob");
            r_function_args.set ("round", "x,digits");
            r_function_args.set ("paste", "sep,collapse");
            r_function_args.set ("paste0", "collapse");
            r_function_args.set ("pivot_longer", "data,cols,names_to,values_to,names_prefix,values_drop_na");
            r_function_args.set ("pivot_wider", "data,id_cols,names_from,values_from,values_fill,values_fn");
            r_function_args.set ("left_join", "x,y,by,copy,suffix,keep,na_matches");
            r_function_args.set ("inner_join", "x,y,by,copy,suffix");
            r_function_args.set ("full_join", "x,y,by,copy,suffix");
            r_function_args.set ("survfit", "formula,data,weights,subset,na.action,conf.int,conf.type");
            r_function_args.set ("coxph", "formula,data,weights,subset,na.action,ties,robust");
            r_function_args.set ("tbl_summary", "data,by,label,statistic,digits,type,missing,missing_text");
            r_function_args.set ("results", "object,contrast,name,lfcThreshold,altHypothesis,alpha,pAdjustMethod");

            // Common R Packages for library(...) / require(...)
            string[] r_pkgs = {
                "tidyverse", "ggplot2", "dplyr", "tidyr", "readr", "stringr", "purrr", "tibble",
                "forcats", "lubridate", "data.table", "survival", "survminer", "gtsummary", "broom",
                "lme4", "nlme", "mgcv", "MASS", "car", "emmeans", "pROC", "caret", "tidymodels",
                "randomForest", "xgboost", "glmnet", "DESeq2", "edgeR", "limma", "Seurat",
                "SingleCellExperiment", "SummarizedExperiment", "Biostrings", "GenomicRanges",
                "clusterProfiler", "EnhancedVolcano", "ComplexHeatmap", "pheatmap", "patchwork",
                "cowplot", "scales", "RColorBrewer", "viridis", "ggrepel", "ggpubr", "knitr",
                "rmarkdown", "gt", "flextable", "kableExtra", "shiny", "plotly", "bio3d",
                "vegan", "ape", "sf", "palmerpenguins", "janitor", "here", "readxl", "haven"
            };
            foreach (string pkg in r_pkgs) {
                r_packages.add (pkg);
            }

            // Common Python Modules for import / from ...
            string[] py_mods = {
                "pandas", "numpy", "matplotlib", "matplotlib.pyplot", "seaborn", "scipy", "scipy.stats",
                "sklearn", "sklearn.model_selection", "sklearn.metrics", "sklearn.preprocessing",
                "statsmodels.api", "lifelines", "Bio", "anndata", "scanpy", "torch", "polars",
                "plotly.express", "plotly.graph_objects", "os", "sys", "pathlib", "json", "csv",
                "re", "math", "statistics", "datetime", "collections", "itertools", "functools",
                "typing", "dataclasses", "subprocess", "argparse", "io", "glob", "shutil", "time"
            };
            foreach (string mod in py_mods) {
                py_modules.add (mod);
            }

            // R Keywords & Base / Stats / Biostatistics / Tidyverse / Bioconductor Catalog
            add_r ("function", "function() {\n  \n}", "keyword", "Define an R function [base]", IntelliSenseSymbolKind.KEYWORD, 6);
            add_r ("if", "if () {\n  \n}", "keyword", "Conditional branch [base]", IntelliSenseSymbolKind.KEYWORD, 7);
            add_r ("else", "else {\n  \n}", "keyword", "Alternative branch [base]", IntelliSenseSymbolKind.KEYWORD, 2);
            add_r ("for", "for (i in ) {\n  \n}", "keyword", "For loop iteration [base]", IntelliSenseSymbolKind.KEYWORD, 7);
            add_r ("while", "while () {\n  \n}", "keyword", "While loop [base]", IntelliSenseSymbolKind.KEYWORD, 7);
            add_r ("return", "return()", "(value)", "Return value from function [base]", IntelliSenseSymbolKind.KEYWORD, 1);
            add_r ("TRUE", "TRUE", "logical", "Logical true constant [base]", IntelliSenseSymbolKind.KEYWORD, 0);
            add_r ("FALSE", "FALSE", "logical", "Logical false constant [base]", IntelliSenseSymbolKind.KEYWORD, 0);
            add_r ("NULL", "NULL", "null", "Empty/null R object [base]", IntelliSenseSymbolKind.KEYWORD, 0);
            add_r ("NA", "NA", "logical", "Missing value constant [base]", IntelliSenseSymbolKind.KEYWORD, 0);

            add_r ("c", "c()", "(...)", "Combine values into a vector or list [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("library", "library()", "(package)", "Load and attach R package [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("require", "require()", "(package)", "Load and attach R package returning logical [base]", IntelliSenseSymbolKind.FUNCTION, 1);
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
            add_r ("mean", "mean(, na.rm = TRUE)", "(x, trim = 0, na.rm = FALSE)", "Arithmetic mean [base]", IntelliSenseSymbolKind.FUNCTION, 14);
            add_r ("median", "median(, na.rm = TRUE)", "(x, na.rm = FALSE)", "Sample median [stats]", IntelliSenseSymbolKind.FUNCTION, 14);
            add_r ("sd", "sd(, na.rm = TRUE)", "(x, na.rm = FALSE)", "Sample standard deviation [stats]", IntelliSenseSymbolKind.FUNCTION, 14);
            add_r ("var", "var(, na.rm = TRUE)", "(x, y = NULL, na.rm = FALSE)", "Sample variance [stats]", IntelliSenseSymbolKind.FUNCTION, 14);
            add_r ("sum", "sum(, na.rm = TRUE)", "(..., na.rm = FALSE)", "Sum of vector elements [base]", IntelliSenseSymbolKind.FUNCTION, 14);
            add_r ("min", "min(, na.rm = TRUE)", "(..., na.rm = FALSE)", "Minimum value [base]", IntelliSenseSymbolKind.FUNCTION, 14);
            add_r ("max", "max(, na.rm = TRUE)", "(..., na.rm = FALSE)", "Maximum value [base]", IntelliSenseSymbolKind.FUNCTION, 14);
            add_r ("quantile", "quantile(, probs = c(0.25, 0.5, 0.75), na.rm = TRUE)", "(x, probs, na.rm = FALSE)", "Sample quantiles [stats]", IntelliSenseSymbolKind.FUNCTION, 42);
            add_r ("length", "length()", "(x)", "Length of an object [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("nrow", "nrow()", "(x)", "Number of rows [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("ncol", "ncol()", "(x)", "Number of columns [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("dim", "dim()", "(x)", "Dimensions of an object [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("names", "names()", "(x)", "Names of an object [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("colnames", "colnames()", "(x)", "Column names of matrix/data.frame [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("rownames", "rownames()", "(x)", "Row names of matrix/data.frame [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("rbind", "rbind()", "(...)", "Combine R objects by rows [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("cbind", "cbind()", "(...)", "Combine R objects by columns [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("merge", "merge(, , by = \"\")", "(x, y, by = intersect(names(x), names(y)))", "Merge two data.frames [base]", IntelliSenseSymbolKind.FUNCTION, 12);
            add_r ("subset", "subset(, )", "(x, subset, select)", "Subset vectors, matrices, or data frames [base]", IntelliSenseSymbolKind.FUNCTION, 3);
            add_r ("ifelse", "ifelse(, , )", "(test, yes, no)", "Vectorized conditional element selection [base]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("apply", "apply(, 2, )", "(X, MARGIN, FUN)", "Apply function over array margins [base]", IntelliSenseSymbolKind.FUNCTION, 6);
            add_r ("lapply", "lapply(, function(x) )", "(X, FUN)", "Apply function over list or vector [base]", IntelliSenseSymbolKind.FUNCTION, 15);
            add_r ("sapply", "sapply(, function(x) )", "(X, FUN)", "Apply function and simplify to vector/matrix [base]", IntelliSenseSymbolKind.FUNCTION, 15);
            add_r ("tapply", "tapply(, , )", "(X, INDEX, FUN)", "Apply function over ragged array [base]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("aggregate", "aggregate( ~ , data = , FUN = mean)", "(formula, data, FUN)", "Compute summary statistics of data subsets [stats]", IntelliSenseSymbolKind.FUNCTION, 24);
            add_r ("table", "table()", "(...)", "Cross tabulation and table creation [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("prop.table", "prop.table()", "(x, margin = NULL)", "Express table entries as proportions [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("factor", "factor()", "(x, levels, labels)", "Encode a vector as a factor [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("as.numeric", "as.numeric()", "(x)", "Coerce to numeric vector [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("as.character", "as.character()", "(x)", "Coerce to character vector [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("as.factor", "as.factor()", "(x)", "Coerce to factor [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("as.data.frame", "as.data.frame()", "(x)", "Coerce to data.frame [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("is.na", "is.na()", "(x)", "Detect missing values [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("is.null", "is.null()", "(x)", "Test whether object is NULL [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("na.omit", "na.omit()", "(object)", "Remove rows with missing values [stats]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("complete.cases", "complete.cases()", "(...)", "Logical vector of complete cases [stats]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("which", "which()", "(x)", "Indices where logical vector is TRUE [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("unique", "unique()", "(x)", "Extract unique elements [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("duplicated", "duplicated()", "(x)", "Determine duplicate elements [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("order", "order()", "(..., decreasing = FALSE)", "Ordering permutation [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("sort", "sort()", "(x, decreasing = FALSE)", "Sort a vector or factor [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("grep", "grep(\"\", )", "(pattern, x, ignore.case = FALSE)", "Pattern matching indices [base]", IntelliSenseSymbolKind.FUNCTION, 4);
            add_r ("grepl", "grepl(\"\", )", "(pattern, x, ignore.case = FALSE)", "Logical pattern matching [base]", IntelliSenseSymbolKind.FUNCTION, 4);
            add_r ("gsub", "gsub(\"\", \"\", )", "(pattern, replacement, x)", "Replace all regex matches [base]", IntelliSenseSymbolKind.FUNCTION, 8);
            add_r ("paste", "paste(, sep = \" \")", "(..., sep = \" \", collapse = NULL)", "Concatenate strings with separator [base]", IntelliSenseSymbolKind.FUNCTION, 11);
            add_r ("paste0", "paste0()", "(..., collapse = NULL)", "Concatenate strings with no separator [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("sprintf", "sprintf(\"\", )", "(fmt, ...)", "C-style formatted string [base]", IntelliSenseSymbolKind.FUNCTION, 4);
            add_r ("cat", "cat(, \"\\n\")", "(..., sep = \" \")", "Concatenate and print [base]", IntelliSenseSymbolKind.FUNCTION, 7);
            add_r ("print", "print()", "(x, ...)", "Print object [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("seq", "seq(from = 1, to = 10, by = 1)", "(from, to, by, length.out)", "Sequence generation [base]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("rep", "rep(, times = )", "(x, times, each)", "Replicate elements of vectors [base]", IntelliSenseSymbolKind.FUNCTION, 11);
            add_r ("sample", "sample(, size = , replace = FALSE)", "(x, size, replace = FALSE)", "Random sample and permutations [base]", IntelliSenseSymbolKind.FUNCTION, 27);
            add_r ("round", "round(, digits = 2)", "(x, digits = 0)", "Round numeric values [base]", IntelliSenseSymbolKind.FUNCTION, 13);
            add_r ("log2", "log2()", "(x)", "Base-2 logarithm [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("log10", "log10()", "(x)", "Base-10 logarithm [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("scale", "scale()", "(x, center = TRUE, scale = TRUE)", "Center and scale numeric matrix [base]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("set.seed", "set.seed(42)", "(seed)", "Initialize reproducible PRNG state [base]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("plot", "plot(, )", "(x, y, type = \"p\", main = \"\")", "Generic X-Y plotting [graphics]", IntelliSenseSymbolKind.FUNCTION, 3);
            add_r ("hist", "hist()", "(x, breaks = \"Sturges\", main = \"\")", "Histogram [graphics]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("boxplot", "boxplot( ~ , data = )", "(formula, data)", "Box-and-whisker plot [graphics]", IntelliSenseSymbolKind.FUNCTION, 11);

            // R Stats & Clinical Biostatistics
            add_r ("lm", "lm( ~ , data = )", "(formula, data)", "Fit Linear Models [stats]", IntelliSenseSymbolKind.FUNCTION, 11);
            add_r ("glm", "glm( ~ , family = binomial, data = )", "(formula, family, data)", "Fit Generalized Linear Models [stats]", IntelliSenseSymbolKind.FUNCTION, 31);
            add_r ("t.test", "t.test(, , alternative = \"two.sided\")", "(x, y, alternative = \"two.sided\")", "Student's t-Test [stats]", IntelliSenseSymbolKind.FUNCTION, 29);
            add_r ("wilcox.test", "wilcox.test(, , exact = FALSE)", "(x, y, exact = FALSE)", "Mann-Whitney-Wilcoxon Rank Sum Test [stats]", IntelliSenseSymbolKind.FUNCTION, 17);
            add_r ("chisq.test", "chisq.test()", "(x, y = NULL)", "Pearson's Chi-squared Test [stats]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("fisher.test", "fisher.test()", "(x, y = NULL)", "Fisher's Exact Test for Count Data [stats]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("cor", "cor(, , use = \"complete.obs\")", "(x, y = NULL, method = \"pearson\")", "Correlation coefficient [stats]", IntelliSenseSymbolKind.FUNCTION, 25);
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
            add_r ("geom_bar", "geom_bar()", "(mapping, data, stat = \"count\")", "Bar chart layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("geom_col", "geom_col()", "(mapping, data, position = \"stack\")", "Column bar chart from values [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("geom_boxplot", "geom_boxplot(width = 0.5)", "(mapping, data, width)", "Box-and-whiskers plot layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_violin", "geom_violin(trim = FALSE)", "(mapping, data, trim)", "Violin density plot layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_histogram", "geom_histogram(bins = 30)", "(mapping, data, bins)", "Histogram distribution layer [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_density", "geom_density(alpha = 0.4)", "(mapping, data, alpha)", "Smoothed kernel density estimate [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_smooth", "geom_smooth(method = \"lm\", se = TRUE)", "(mapping, data, method, se)", "Smoothed conditional means [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_vline", "geom_vline(xintercept = 0, linetype = \"dashed\")", "(xintercept, linetype)", "Vertical reference line [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("geom_hline", "geom_hline(yintercept = 0, linetype = \"dashed\")", "(yintercept, linetype)", "Horizontal reference line [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("facet_wrap", "facet_wrap(~ )", "(facets, nrow, ncol, scales)", "Wrap a 1d ribbon of panels into 2d [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("facet_grid", "facet_grid( ~ )", "(rows, cols, scales)", "Lay out panels in a grid [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 4);
            add_r ("theme_minimal", "theme_minimal()", "(base_size = 11)", "Minimalist publication theme [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("theme_bw", "theme_bw()", "(base_size = 11)", "Black-and-white publication theme [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("theme_classic", "theme_classic()", "(base_size = 11)", "Classic theme without gridlines [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 0);
            add_r ("theme", "theme()", "(...)", "Modify components of a ggplot2 theme [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("labs", "labs(title = \"\", x = \"\", y = \"\")", "(title, subtitle, x, y, caption)", "Modify axis, legend, and plot labels [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 18);
            add_r ("ggsave", "ggsave(\"\", width = 7, height = 5, dpi = 300)", "(filename, plot, width, height, dpi)", "Save a ggplot to file [ggplot2]", IntelliSenseSymbolKind.FUNCTION, 34);
            add_r ("filter", "filter()", "(.data, ...)", "Subset rows using column values [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("mutate", "mutate()", "(.data, ...)", "Create, modify, and delete columns [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("select", "select()", "(.data, ...)", "Keep or drop columns using their names [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("group_by", "group_by()", "(.data, ...)", "Group by one or more variables [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("summarise", "summarise()", "(.data, ...)", "Summarise each group to one row [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("summarize", "summarize()", "(.data, ...)", "Summarise each group to one row [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("arrange", "arrange()", "(.data, ...)", "Order rows using column values [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("count", "count()", "(x, ..., sort = TRUE)", "Count observations by group [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("rename", "rename()", "(.data, ...)", "Rename columns [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("distinct", "distinct()", "(.data, ..., .keep_all = FALSE)", "Keep only unique rows [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("pull", "pull()", "(.data, var = -1)", "Extract a single column as a vector [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("case_when", "case_when(\n   ~ ,\n  .default = \n)", "(..., .default = NULL)", "General vectorized if-else [dplyr]", IntelliSenseSymbolKind.FUNCTION, 19);
            add_r ("if_else", "if_else(, , )", "(condition, true, false)", "Type-strict vectorized if-else [dplyr]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("across", "across(, )", "(.cols, .fns)", "Apply function across multiple columns [dplyr]", IntelliSenseSymbolKind.FUNCTION, 3);
            add_r ("bind_rows", "bind_rows()", "(...)", "Bind multiple data frames by row [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("left_join", "left_join(, by = \"\")", "(x, y, by = NULL)", "Mutating left join of two tables [dplyr]", IntelliSenseSymbolKind.FUNCTION, 2);
            add_r ("inner_join", "inner_join(, by = \"\")", "(x, y, by = NULL)", "Mutating inner join of two tables [dplyr]", IntelliSenseSymbolKind.FUNCTION, 2);
            add_r ("full_join", "full_join(, by = \"\")", "(x, y, by = NULL)", "Mutating full join of two tables [dplyr]", IntelliSenseSymbolKind.FUNCTION, 2);
            add_r ("glimpse", "glimpse()", "(x)", "Get a glimpse of your data [dplyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("pivot_longer", "pivot_longer(cols = , names_to = \"name\", values_to = \"value\")", "(data, cols, names_to, values_to)", "Pivot data from wide to long [tidyr]", IntelliSenseSymbolKind.FUNCTION, 40);
            add_r ("pivot_wider", "pivot_wider(names_from = , values_from = )", "(data, names_from, values_from)", "Pivot data from long to wide [tidyr]", IntelliSenseSymbolKind.FUNCTION, 16);
            add_r ("drop_na", "drop_na()", "(data, ...)", "Drop rows containing missing values [tidyr]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("read_csv", "read_csv(\"\")", "(file, col_names = TRUE)", "Read CSV into tibble [readr]", IntelliSenseSymbolKind.FUNCTION, 2);
            add_r ("read_tsv", "read_tsv(\"\")", "(file, col_names = TRUE)", "Read TSV into tibble [readr]", IntelliSenseSymbolKind.FUNCTION, 2);
            add_r ("write_csv", "write_csv(, \"\")", "(x, file)", "Write data frame to CSV [readr]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("tibble", "tibble()", "(...)", "Build a tidy tibble data frame [tibble]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("str_detect", "str_detect(, \"\")", "(string, pattern)", "Detect presence of pattern in string [stringr]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("str_replace", "str_replace(, \"\", \"\")", "(string, pattern, replacement)", "Replace matched patterns in string [stringr]", IntelliSenseSymbolKind.FUNCTION, 9);
            add_r ("str_extract", "str_extract(, \"\")", "(string, pattern)", "Extract matching patterns from string [stringr]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("map", "map(, ~ )", "(.x, .f, ...)", "Apply function to each element of list [purrr]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("map_dbl", "map_dbl(, ~ )", "(.x, .f, ...)", "Apply function returning numeric vector [purrr]", IntelliSenseSymbolKind.FUNCTION, 5);
            add_r ("DESeqDataSetFromMatrix", "DESeqDataSetFromMatrix(countData = , colData = , design = ~ )", "(countData, colData, design)", "Build DESeq2 count matrix dataset [DESeq2]", IntelliSenseSymbolKind.FUNCTION, 26);
            add_r ("DESeq", "DESeq()", "(object)", "Differential expression analysis based on Negative Binomial [DESeq2]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_r ("results", "results(, alpha = 0.05)", "(object, contrast, alpha = 0.05)", "Extract DESeq2 differential expression table [DESeq2]", IntelliSenseSymbolKind.FUNCTION, 15);
            add_r ("read.pdb", "bio3d::read.pdb(\"\")", "(file)", "Read Protein Data Bank (PDB) structure [bio3d]", IntelliSenseSymbolKind.FUNCTION, 2);

            // Built-in R Datasets
            add_r ("mtcars", "mtcars", "[32 x 11 data.frame]", "Motor Trend Car Road Tests [datasets]", IntelliSenseSymbolKind.DATAFRAME, 0);
            add_r ("iris", "iris", "[150 x 5 data.frame]", "Edgar Anderson's Iris Data [datasets]", IntelliSenseSymbolKind.DATAFRAME, 0);
            add_r ("airquality", "airquality", "[153 x 6 data.frame]", "New York Air Quality Measurements [datasets]", IntelliSenseSymbolKind.DATAFRAME, 0);
            add_r ("ToothGrowth", "ToothGrowth", "[60 x 3 data.frame]", "Effect of Vitamin C on Tooth Growth [datasets]", IntelliSenseSymbolKind.DATAFRAME, 0);

            // Python Built-in & Scientific Data Science / Bioinformatics Catalog
            add_py ("import", "import ", "keyword", "Import a Python module", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("from", "from  import ", "keyword", "Import specific attributes from a module", IntelliSenseSymbolKind.KEYWORD, 8);
            add_py ("def", "def ():\n    ", "keyword", "Define a Python function", IntelliSenseSymbolKind.KEYWORD, 7);
            add_py ("class", "class :\n    ", "keyword", "Define a Python class", IntelliSenseSymbolKind.KEYWORD, 6);
            add_py ("if", "if :\n    ", "keyword", "Conditional branch", IntelliSenseSymbolKind.KEYWORD, 6);
            add_py ("elif", "elif :\n    ", "keyword", "Else-if conditional branch", IntelliSenseSymbolKind.KEYWORD, 6);
            add_py ("else", "else:\n    ", "keyword", "Alternative branch", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("for", "for  in :\n    ", "keyword", "For loop iteration", IntelliSenseSymbolKind.KEYWORD, 10);
            add_py ("while", "while :\n    ", "keyword", "While loop", IntelliSenseSymbolKind.KEYWORD, 6);
            add_py ("with", "with  as :\n    ", "keyword", "Context manager block", IntelliSenseSymbolKind.KEYWORD, 10);
            add_py ("try", "try:\n    \nexcept Exception as e:\n    ", "keyword", "Exception handling block", IntelliSenseSymbolKind.KEYWORD, 28);
            add_py ("return", "return ", "keyword", "Return value from function", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("lambda", "lambda x: ", "keyword", "Anonymous inline function", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("True", "True", "bool", "Boolean true constant", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("False", "False", "bool", "Boolean false constant", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("None", "None", "NoneType", "Null object constant", IntelliSenseSymbolKind.KEYWORD, 0);
            add_py ("print", "print()", "(*values, sep=' ', end='\\n')", "Print values to standard output [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("len", "len()", "(obj) -> int", "Return number of items in container [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("range", "range()", "(start, stop[, step])", "Immutable sequence of numbers [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("enumerate", "enumerate()", "(iterable, start=0)", "Return enumerate object yielding (index, value) [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("zip", "zip()", "(*iterables)", "Iterate over several iterables in parallel [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("sorted", "sorted()", "(iterable, key=None, reverse=False)", "Return a new sorted list [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("sum", "sum()", "(iterable, start=0)", "Sum items of an iterable [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("min", "min()", "(iterable, *[, key])", "Return smallest item [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("max", "max()", "(iterable, *[, key])", "Return largest item [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("round", "round(, 2)", "(number, ndigits=None)", "Round number to given precision [builtins]", IntelliSenseSymbolKind.FUNCTION, 4);
            add_py ("isinstance", "isinstance(, )", "(obj, class_or_tuple)", "Check object type [builtins]", IntelliSenseSymbolKind.FUNCTION, 3);
            add_py ("open", "open(\"\", \"r\", encoding=\"utf-8\")", "(file, mode='r', encoding=None)", "Open file and return stream [builtins]", IntelliSenseSymbolKind.FUNCTION, 24);
            add_py ("dict", "dict()", "(**kwargs)", "Create a dictionary [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("list", "list()", "(iterable)", "Create a list [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
            add_py ("set", "set()", "(iterable)", "Create a set of unique elements [builtins]", IntelliSenseSymbolKind.FUNCTION, 1);
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
            add_py ("pd.read_excel", "pd.read_excel(\"\")", "(io, sheet_name=0)", "Read Excel file into DataFrame [pandas]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("pd.DataFrame", "pd.DataFrame()", "(data=None, columns=None)", "Two-dimensional tabular data structure [pandas]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("pd.Series", "pd.Series()", "(data=None, index=None)", "One-dimensional labeled array [pandas]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("pd.concat", "pd.concat([], axis=0)", "(objs, axis=0, ignore_index=False)", "Concatenate pandas objects along an axis [pandas]", IntelliSenseSymbolKind.METHOD, 10);
            add_py ("pd.merge", "pd.merge(, , on=\"\")", "(left, right, how='inner', on=None)", "Merge DataFrame or named Series objects [pandas]", IntelliSenseSymbolKind.METHOD, 9);
            add_py ("pd.pivot_table", "pd.pivot_table(, values=\"\", index=\"\", aggfunc=\"mean\")", "(data, values, index, columns)", "Create spreadsheet-style pivot table [pandas]", IntelliSenseSymbolKind.METHOD, 38);
            add_py ("np.array", "np.array([])", "(object, dtype=None)", "Create an N-dimensional NumPy array [numpy]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("np.linspace", "np.linspace(0.0, 1.0, 100)", "(start, stop, num=50)", "Return evenly spaced numbers over interval [numpy]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("np.arange", "np.arange(0, 10, 1)", "(start, stop, step)", "Return evenly spaced values within interval [numpy]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("np.zeros", "np.zeros(())", "(shape, dtype=float)", "Return new array filled with zeros [numpy]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("np.ones", "np.ones(())", "(shape, dtype=float)", "Return new array filled with ones [numpy]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("np.mean", "np.mean()", "(a, axis=None)", "Compute arithmetic mean along specified axis [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.median", "np.median()", "(a, axis=None)", "Compute median along specified axis [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.std", "np.std()", "(a, axis=None, ddof=0)", "Compute standard deviation along axis [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.log2", "np.log2()", "(x)", "Base-2 logarithm of x (Fold-Change) [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.log10", "np.log10()", "(x)", "Base-10 logarithm of x (-log10 P-value) [numpy]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("np.clip", "np.clip(, 1e-300, 1.0)", "(a, a_min, a_max)", "Clip (limit) values in an array [numpy]", IntelliSenseSymbolKind.METHOD, 14);
            add_py ("np.where", "np.where(, , )", "(condition, x, y)", "Return elements chosen from x or y [numpy]", IntelliSenseSymbolKind.METHOD, 5);
            add_py ("plt.figure", "plt.figure(figsize=(7, 5))", "(figsize=(width, height), dpi=100)", "Create a new figure [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.subplots", "fig, ax = plt.subplots(figsize=(7, 5))", "(nrows=1, ncols=1, figsize=None)", "Create a figure and a set of subplots [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.plot", "plt.plot(, )", "(x, y, label=None)", "Plot y versus x as lines or markers [matplotlib]", IntelliSenseSymbolKind.METHOD, 3);
            add_py ("plt.scatter", "plt.scatter(, , alpha=0.8)", "(x, y, s=None, c=None, alpha=None)", "Scatter plot of y vs. x [matplotlib]", IntelliSenseSymbolKind.METHOD, 14);
            add_py ("plt.hist", "plt.hist(, bins=30)", "(x, bins=None)", "Compute and plot a histogram [matplotlib]", IntelliSenseSymbolKind.METHOD, 10);
            add_py ("plt.axvline", "plt.axvline(0.0, linestyle=\"--\", color=\"#475569\")", "(x=0, ymin=0, ymax=1, ls='--')", "Add a vertical line across the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.axhline", "plt.axhline(0.0, linestyle=\"--\", color=\"#475569\")", "(y=0, xmin=0, xmax=1, ls='--')", "Add a horizontal line across the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.xlabel", "plt.xlabel(\"\")", "(xlabel)", "Set the label for the x-axis [matplotlib]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("plt.ylabel", "plt.ylabel(\"\")", "(ylabel)", "Set the label for the y-axis [matplotlib]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("plt.title", "plt.title(\"\")", "(label)", "Set a title for the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 2);
            add_py ("plt.legend", "plt.legend()", "(loc='best')", "Place a legend on the Axes [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.tight_layout", "plt.tight_layout()", "()", "Adjust padding between and around subplots [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("plt.savefig", "plt.savefig(\"\", dpi=300, bbox_inches=\"tight\")", "(fname, dpi=None, bbox_inches=None)", "Save the current figure [matplotlib]", IntelliSenseSymbolKind.METHOD, 32);
            add_py ("plt.show", "plt.show()", "()", "Display all open figures [matplotlib]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("sns.scatterplot", "sns.scatterplot(data=, x=\"\", y=\"\")", "(data, x, y, hue=None)", "Draw a scatter plot [seaborn]", IntelliSenseSymbolKind.METHOD, 13);
            add_py ("sns.lineplot", "sns.lineplot(data=, x=\"\", y=\"\")", "(data, x, y, hue=None)", "Draw a line plot with confidence intervals [seaborn]", IntelliSenseSymbolKind.METHOD, 13);
            add_py ("sns.boxplot", "sns.boxplot(data=, x=\"\", y=\"\")", "(data, x, y, hue=None)", "Draw a box plot [seaborn]", IntelliSenseSymbolKind.METHOD, 13);
            add_py ("sns.violinplot", "sns.violinplot(data=, x=\"\", y=\"\")", "(data, x, y, hue=None)", "Draw a violin plot [seaborn]", IntelliSenseSymbolKind.METHOD, 13);
            add_py ("sns.histplot", "sns.histplot(data=, x=\"\", kde=True)", "(data, x, bins='auto', kde=False)", "Plot univariate or bivariate histograms [seaborn]", IntelliSenseSymbolKind.METHOD, 17);
            add_py ("sns.heatmap", "sns.heatmap(, annot=True, cmap=\"viridis\")", "(data, annot=None, cmap=None)", "Plot rectangular data as a color-encoded matrix [seaborn]", IntelliSenseSymbolKind.METHOD, 29);
            add_py ("sns.set_theme", "sns.set_theme(style=\"whitegrid\")", "(context='notebook', style='darkgrid')", "Set visual theme for seaborn plots [seaborn]", IntelliSenseSymbolKind.METHOD, 0);
            add_py ("stats.ttest_ind", "stats.ttest_ind(, , equal_var=False)", "(a, b, equal_var=True)", "Two-sample Welch/Student t-test [scipy.stats]", IntelliSenseSymbolKind.METHOD, 20);
            add_py ("stats.mannwhitneyu", "stats.mannwhitneyu(, )", "(x, y, alternative='two-sided')", "Mann-Whitney U rank test [scipy.stats]", IntelliSenseSymbolKind.METHOD, 3);
            add_py ("stats.fisher_exact", "stats.fisher_exact()", "(table, alternative='two-sided')", "Fisher exact test on 2x2 contingency table [scipy.stats]", IntelliSenseSymbolKind.METHOD, 1);
            add_py ("stats.pearsonr", "stats.pearsonr(, )", "(x, y)", "Pearson correlation coefficient and p-value [scipy.stats]", IntelliSenseSymbolKind.METHOD, 3);
            add_py ("stats.spearmanr", "stats.spearmanr(, )", "(a, b)", "Spearman rank-order correlation [scipy.stats]", IntelliSenseSymbolKind.METHOD, 3);
            add_py ("stats.norm.ppf", "stats.norm.ppf(0.975)", "(q, loc=0, scale=1)", "Normal distribution percent point (quantile) [scipy.stats]", IntelliSenseSymbolKind.METHOD, 1);

            // Python pandas DataFrame instance methods (for df.<method>)
            add_py_df ("head", "head(5)", "(n=5)", "Return the first n rows [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("tail", "tail(5)", "(n=5)", "Return the last n rows [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("info", "info()", "()", "Print concise summary of a DataFrame [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("describe", "describe()", "(percentiles=None, include=None)", "Generate descriptive statistics [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("shape", "shape", "(rows, cols)", "Return tuple representing dimensionality [DataFrame]", IntelliSenseSymbolKind.VARIABLE, 0);
            add_py_df ("columns", "columns", "Index", "Column labels of the DataFrame [DataFrame]", IntelliSenseSymbolKind.VARIABLE, 0);
            add_py_df ("dtypes", "dtypes", "Series", "Data types of each column [DataFrame]", IntelliSenseSymbolKind.VARIABLE, 0);
            add_py_df ("index", "index", "Index", "Row index labels of the DataFrame [DataFrame]", IntelliSenseSymbolKind.VARIABLE, 0);
            add_py_df ("groupby", "groupby(\"\")", "(by, as_index=True)", "Group DataFrame using a mapper or column [DataFrame]", IntelliSenseSymbolKind.METHOD, 2);
            add_py_df ("agg", "agg()", "(func, axis=0)", "Aggregate using one or more operations [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("sort_values", "sort_values(by=\"\", ascending=True)", "(by, ascending=True)", "Sort by values along either axis [DataFrame]", IntelliSenseSymbolKind.METHOD, 18);
            add_py_df ("value_counts", "value_counts()", "(subset=None, normalize=False)", "Count unique rows or values [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("dropna", "dropna()", "(axis=0, how='any', subset=None)", "Remove missing values [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("fillna", "fillna()", "(value=None, method=None)", "Fill NA/NaN values [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("isna", "isna()", "()", "Detect missing values [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("merge", "merge(, on=\"\", how=\"left\")", "(right, how='inner', on=None)", "Merge DataFrame with another DataFrame [DataFrame]", IntelliSenseSymbolKind.METHOD, 20);
            add_py_df ("rename", "rename(columns={\"\": \"\"})", "(columns=None, index=None)", "Rename columns or index labels [DataFrame]", IntelliSenseSymbolKind.METHOD, 6);
            add_py_df ("drop", "drop(columns=[\"\"])", "(labels=None, axis=0, columns=None)", "Drop specified labels from rows or columns [DataFrame]", IntelliSenseSymbolKind.METHOD, 3);
            add_py_df ("assign", "assign()", "(**kwargs)", "Assign new columns to a DataFrame [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("query", "query(\"\")", "(expr, inplace=False)", "Query columns with a boolean expression [DataFrame]", IntelliSenseSymbolKind.METHOD, 2);
            add_py_df ("loc", "loc[]", "[row_indexer, col_indexer]", "Access rows and columns by label(s) [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("iloc", "iloc[]", "[row_idx, col_idx]", "Purely integer-location based indexing [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("apply", "apply(lambda x: )", "(func, axis=0)", "Apply a function along an axis [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("reset_index", "reset_index(drop=True)", "(drop=False)", "Reset the index of the DataFrame [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("set_index", "set_index(\"\")", "(keys, drop=True)", "Set the DataFrame index using columns [DataFrame]", IntelliSenseSymbolKind.METHOD, 2);
            add_py_df ("to_csv", "to_csv(\"\", index=False)", "(path_or_buf, index=True)", "Write DataFrame to CSV file [DataFrame]", IntelliSenseSymbolKind.METHOD, 15);
            add_py_df ("to_markdown", "to_markdown(index=False)", "(index=True)", "Print DataFrame in Markdown-friendly format [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("corr", "corr(numeric_only=True)", "(method='pearson', numeric_only=False)", "Compute pairwise correlation of columns [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("plot", "plot()", "(kind='line')", "Make plots of Series or DataFrame [DataFrame]", IntelliSenseSymbolKind.METHOD, 1);
            add_py_df ("drop_duplicates", "drop_duplicates()", "(subset=None, keep='first')", "Return DataFrame with duplicate rows removed [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);
            add_py_df ("copy", "copy()", "(deep=True)", "Make a copy of this object's indices and data [DataFrame]", IntelliSenseSymbolKind.METHOD, 0);

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
            add_quarto_opt ("fig-align", "fig-align: center", "string", "Figure alignment (default, left, right, center)");
            add_quarto_opt ("tbl-cap", "tbl-cap: \"\"", "string", "Table caption text for cross-referenced tables", 1);
            add_quarto_opt ("cache: true", "cache: true", "boolean", "Cache chunk computation results on disk");
            add_quarto_opt ("code-fold: true", "code-fold: true", "boolean", "Collapse code into an interactive <details> block");
            add_quarto_opt ("code-summary", "code-summary: \"Show code\"", "string", "Summary label for folded code block", 1);

            // Quarto / R Markdown YAML Frontmatter Keys
            yaml_catalog.add (new IntelliSenseItem ("title:", "title: \"\"", "string", "Document main title", IntelliSenseSymbolKind.OPTION, 1));
            yaml_catalog.add (new IntelliSenseItem ("subtitle:", "subtitle: \"\"", "string", "Document subtitle", IntelliSenseSymbolKind.OPTION, 1));
            yaml_catalog.add (new IntelliSenseItem ("author:", "author: \"\"", "string", "Document primary author", IntelliSenseSymbolKind.OPTION, 1));
            yaml_catalog.add (new IntelliSenseItem ("date: today", "date: today", "date", "Dynamic ISO publication date", IntelliSenseSymbolKind.OPTION, 0));
            yaml_catalog.add (new IntelliSenseItem ("abstract:", "abstract: |\n  ", "block", "Document abstract summary", IntelliSenseSymbolKind.OPTION, 0));
            yaml_catalog.add (new IntelliSenseItem ("format: html", "format:\n  html:\n    toc: true\n    code-fold: show", "block", "Quarto HTML output configuration", IntelliSenseSymbolKind.SNIPPET, 0));
            yaml_catalog.add (new IntelliSenseItem ("format: pdf", "format:\n  pdf:\n    toc: true\n    number-sections: true", "block", "Quarto PDF/LaTeX output configuration", IntelliSenseSymbolKind.SNIPPET, 0));
            yaml_catalog.add (new IntelliSenseItem ("format: docx", "format:\n  docx:\n    toc: true\n    number-sections: true", "block", "Quarto Word (DOCX) output configuration", IntelliSenseSymbolKind.SNIPPET, 0));
            yaml_catalog.add (new IntelliSenseItem ("bibliography:", "bibliography: references.bib", "path", "BibTeX citation database file", IntelliSenseSymbolKind.OPTION, 0));
            yaml_catalog.add (new IntelliSenseItem ("csl:", "csl: nature.csl", "path", "Citation Style Language (CSL) formatting file", IntelliSenseSymbolKind.OPTION, 0));
            yaml_catalog.add (new IntelliSenseItem ("execute:", "execute:\n  echo: true\n  warning: false\n  message: false", "block", "Global chunk execution defaults", IntelliSenseSymbolKind.SNIPPET, 0));
            yaml_catalog.add (new IntelliSenseItem ("toc: true", "toc: true", "boolean", "Generate table of contents", IntelliSenseSymbolKind.OPTION, 0));
            yaml_catalog.add (new IntelliSenseItem ("number-sections: true", "number-sections: true", "boolean", "Automatically number document headings", IntelliSenseSymbolKind.OPTION, 0));

            // Markdown & Quarto Writing Snippets
            add_md (":::callout-note", "::: {.callout-note}\n## Note\n\n:::", "Quarto Callout", "Insert a Quarto Note callout block", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md (":::callout-tip", "::: {.callout-tip}\n## Tip\n\n:::", "Quarto Callout", "Insert a Quarto Tip callout block", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md (":::callout-warning", "::: {.callout-warning}\n## Warning\n\n:::", "Quarto Callout", "Insert a Quarto Warning callout block", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md (":::callout-important", "::: {.callout-important}\n## Important\n\n:::", "Quarto Callout", "Insert a Quarto Important callout block", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md (":::callout-caution", "::: {.callout-caution}\n## Caution\n\n:::", "Quarto Callout", "Insert a Quarto Caution callout block", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md (":::columns", ":::: {.columns}\n\n::: {.column width=\"50%\"}\n\n:::\n\n::: {.column width=\"50%\"}\n\n:::\n\n::::", "Quarto Layout", "Two-column side-by-side layout", IntelliSenseSymbolKind.SNIPPET, 36);
            add_md (":::panel-tabset", "::: {.panel-tabset}\n## Tab 1\n\n## Tab 2\n\n:::", "Quarto Layout", "Interactive tabbed content panel", IntelliSenseSymbolKind.SNIPPET, 15);
            add_md ("table", "| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |", "Markdown Table", "Insert a 3x2 Markdown table (or Ctrl+Alt+T for custom)", IntelliSenseSymbolKind.SNIPPET, 20);
            add_md ("link", "[](https://)", "Markdown Link", "Insert a hyperlink [text](url)", IntelliSenseSymbolKind.SNIPPET, 11);
            add_md ("image", "![](path/to/image.png){#fig-label width=\"80%\"}", "Markdown Figure", "Insert a figure with caption and cross-reference label", IntelliSenseSymbolKind.SNIPPET, 44);
            add_md ("footnote", "[^1]\n\n[^1]: ", "Footnote", "Insert a Markdown footnote reference and definition", IntelliSenseSymbolKind.SNIPPET, 0);
            add_md ("math-block", "$$\n\n$$ {#eq-label}", "Display Math", "Insert a numbered display LaTeX equation block", IntelliSenseSymbolKind.SNIPPET, 15);
            add_md ("$$", "$$\n\n$$", "Display Math", "Insert a display LaTeX math block", IntelliSenseSymbolKind.SNIPPET, 3);
            add_md ("chunk-r", "```{r}\n#| label: fig-\n#| echo: true\n\n```", "Quarto R Chunk", "Insert an executable R code chunk with options", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md ("chunk-python", "```{python}\n#| label: fig-\n#| echo: true\n\n```", "Quarto Python Chunk", "Insert an executable Python code chunk with options", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md ("chunk-bash", "```{bash}\n\n```", "Quarto Bash Chunk", "Insert a shell script code chunk", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md ("mermaid", "```{mermaid}\nflowchart LR\n  A[Start] --> B[End]\n```", "Mermaid Diagram", "Insert a Mermaid flowchart diagram", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md ("task-list", "- [ ] ", "Checklist", "Insert a GitHub/Quarto task list item", IntelliSenseSymbolKind.SNIPPET, 0);
            add_md ("blockquote", "> ", "Quote", "Insert a blockquote line", IntelliSenseSymbolKind.SNIPPET, 0);
            add_md ("details", "<details>\n<summary>Click to expand</summary>\n\n</details>", "Collapsible", "Insert a collapsible disclosure block", IntelliSenseSymbolKind.SNIPPET, 11);
            add_md ("pagebreak", "{{< pagebreak >}}", "Quarto Shortcode", "Insert a page break for PDF/DOCX rendering", IntelliSenseSymbolKind.SNIPPET, 0);
            add_md ("include", "{{< include _section.qmd >}}", "Quarto Shortcode", "Include another Quarto/Markdown file", IntelliSenseSymbolKind.SNIPPET, 4);
            add_md ("kbd", "{{< kbd Ctrl+S >}}", "Quarto Shortcode", "Render a keyboard shortcut badge", IntelliSenseSymbolKind.SNIPPET, 4);

            // HTML5 Tag Catalog (for .html files and inline HTML inside Markdown)
            add_html ("<div", "<div></div>", "HTML container", "Generic block-level container", 6);
            add_html ("<span", "<span></span>", "HTML inline", "Generic inline container", 7);
            add_html ("<p", "<p></p>", "HTML paragraph", "Paragraph element", 4);
            add_html ("<section", "<section>\n  \n</section>", "HTML section", "Thematic document section", 11);
            add_html ("<article", "<article>\n  \n</article>", "HTML article", "Self-contained composition", 11);
            add_html ("<header", "<header>\n  \n</header>", "HTML header", "Introductory header content", 10);
            add_html ("<footer", "<footer>\n  \n</footer>", "HTML footer", "Document or section footer", 10);
            add_html ("<main", "<main>\n  \n</main>", "HTML main", "Dominant page content", 8);
            add_html ("<nav", "<nav>\n  \n</nav>", "HTML nav", "Navigation links container", 7);
            add_html ("<h1", "<h1></h1>", "HTML heading", "Level 1 heading", 5);
            add_html ("<h2", "<h2></h2>", "HTML heading", "Level 2 heading", 5);
            add_html ("<h3", "<h3></h3>", "HTML heading", "Level 3 heading", 5);
            add_html ("<h4", "<h4></h4>", "HTML heading", "Level 4 heading", 5);
            add_html ("<a", "<a href=\"\"></a>", "HTML link", "Hyperlink anchor element", 6);
            add_html ("<img", "<img src=\"\" alt=\"\" />", "HTML image", "Embedded image element", 11);
            add_html ("<ul", "<ul>\n  <li></li>\n</ul>", "HTML list", "Unordered bulleted list", 11);
            add_html ("<ol", "<ol>\n  <li></li>\n</ol>", "HTML list", "Ordered numbered list", 11);
            add_html ("<li", "<li></li>", "HTML item", "List item element", 5);
            add_html ("<table", "<table>\n  <thead>\n    <tr><th></th></tr>\n  </thead>\n  <tbody>\n    <tr><td></td></tr>\n  </tbody>\n</table>", "HTML table", "Structured data table", 69);
            add_html ("<thead", "<thead>\n  \n</thead>", "HTML table", "Table header group", 9);
            add_html ("<tbody", "<tbody>\n  \n</tbody>", "HTML table", "Table body group", 9);
            add_html ("<tr", "<tr></tr>", "HTML table", "Table row element", 5);
            add_html ("<th", "<th></th>", "HTML table", "Table header cell", 5);
            add_html ("<td", "<td></td>", "HTML table", "Table data cell", 5);
            add_html ("<figure", "<figure>\n  \n  <figcaption></figcaption>\n</figure>", "HTML figure", "Self-contained figure with caption", 39);
            add_html ("<figcaption", "<figcaption></figcaption>", "HTML figure", "Caption for a figure element", 13);
            add_html ("<details", "<details>\n  <summary></summary>\n  \n</details>", "HTML widget", "Collapsible disclosure widget", 24);
            add_html ("<summary", "<summary></summary>", "HTML widget", "Summary heading for <details>", 10);
            add_html ("<pre", "<pre><code></code></pre>", "HTML code", "Preformatted code block", 13);
            add_html ("<code", "<code></code>", "HTML code", "Inline code fragment", 7);
            add_html ("<blockquote", "<blockquote>\n  \n</blockquote>", "HTML quote", "Extended quotation block", 14);
            add_html ("<strong", "<strong></strong>", "HTML inline", "Strong importance (bold)", 9);
            add_html ("<em", "<em></em>", "HTML inline", "Stress emphasis (italic)", 5);
            add_html ("<br", "<br />", "HTML break", "Line break", 0);
            add_html ("<hr", "<hr />", "HTML rule", "Thematic horizontal divider", 0);
            add_html ("<style", "<style>\n  \n</style>", "HTML CSS", "Embedded stylesheet block", 9);
            add_html ("<script", "<script>\n  \n</script>", "HTML JS", "Embedded script block", 10);
            add_html ("<button", "<button type=\"button\"></button>", "HTML form", "Clickable button element", 9);
            add_html ("<input", "<input type=\"text\" />", "HTML form", "Form input control", 4);

            // Bash / Scientific Shell Catalog
            add_bash ("echo", "echo \"\"", "(text)", "Print line of text to stdout", IntelliSenseSymbolKind.FUNCTION, 1);
            add_bash ("cd", "cd ", "(dir)", "Change working directory", IntelliSenseSymbolKind.KEYWORD, 0);
            add_bash ("ls", "ls -la ", "([options] [path])", "List directory contents", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("mkdir", "mkdir -p ", "(dir)", "Create directories recursively", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("cp", "cp -r ", "(src dst)", "Copy files and directories", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("mv", "mv ", "(src dst)", "Move or rename files", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("rm", "rm -rf ", "(path)", "Remove files or directories", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("grep", "grep -rn \"\" ", "(pattern path)", "Search text using patterns", IntelliSenseSymbolKind.FUNCTION, 2);
            add_bash ("awk", "awk -F'\\t' '{print $1}' ", "(program file)", "Pattern scanning and text processing", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("sed", "sed -E 's///g' ", "(script file)", "Stream editor for filtering/transforming text", IntelliSenseSymbolKind.FUNCTION, 4);
            add_bash ("find", "find . -name \"\"", "(path -name pattern)", "Search for files in directory hierarchy", IntelliSenseSymbolKind.FUNCTION, 1);
            add_bash ("head", "head -n 20 ", "(file)", "Output first lines of file", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("tail", "tail -n 20 ", "(file)", "Output last lines of file", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("sort", "sort -u ", "(file)", "Sort lines of text files", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("wc", "wc -l ", "(file)", "Count lines, words, and bytes", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("tar", "tar -xzvf ", "(archive.tar.gz)", "Extract or create tar archive", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("curl", "curl -fsSL \"\"", "(url)", "Transfer data from or to a URL", IntelliSenseSymbolKind.FUNCTION, 1);
            add_bash ("chmod", "chmod +x ", "(file)", "Change file permissions", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("export", "export VAR=\"\"", "keyword", "Set environment variable", IntelliSenseSymbolKind.KEYWORD, 1);
            add_bash ("for", "for f in *.csv; do\n  echo \"$f\"\ndone", "keyword", "Shell for loop", IntelliSenseSymbolKind.KEYWORD, 0);
            add_bash ("if", "if [ -f \"\" ]; then\n  \nfi", "keyword", "Shell conditional block", IntelliSenseSymbolKind.KEYWORD, 14);
            add_bash ("quarto", "quarto render ", "(file.qmd)", "Render Quarto scientific document", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("Rscript", "Rscript ", "(script.R)", "Execute R script from CLI", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("python3", "python3 ", "(script.py)", "Execute Python 3 script from CLI", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("git", "git status", "(subcommand)", "Git version control command", IntelliSenseSymbolKind.FUNCTION, 0);
            add_bash ("samtools", "samtools view -bS ", "(subcommand)", "SAM/BAM/CRAM bioinformatics utilities", IntelliSenseSymbolKind.FUNCTION, 0);

            // LaTeX Biostatistics & mhchem Macros
            add_latex ("\\alpha", "\\alpha", "α", "Greek lowercase alpha (Type I error rate)", 0);
            add_latex ("\\beta", "\\beta", "β", "Greek lowercase beta (Type II error / regression coeff)", 0);
            add_latex ("\\gamma", "\\gamma", "γ", "Greek lowercase gamma", 0);
            add_latex ("\\delta", "\\delta", "δ", "Greek lowercase delta (Effect size)", 0);
            add_latex ("\\Delta", "\\Delta", "Δ", "Greek uppercase Delta (Difference operator)", 0);
            add_latex ("\\epsilon", "\\epsilon", "ε", "Greek lowercase epsilon (Residual error)", 0);
            add_latex ("\\theta", "\\theta", "θ", "Greek lowercase theta (Parameter)", 0);
            add_latex ("\\lambda", "\\lambda", "λ", "Greek lowercase lambda (Hazard rate / eigenvalue)", 0);
            add_latex ("\\mu", "\\mu", "μ", "Greek lowercase mu (Population mean)", 0);
            add_latex ("\\pi", "\\pi", "π", "Greek lowercase pi", 0);
            add_latex ("\\rho", "\\rho", "ρ", "Greek lowercase rho (Correlation)", 0);
            add_latex ("\\sigma", "\\sigma", "σ", "Greek lowercase sigma (Standard deviation)", 0);
            add_latex ("\\Sigma", "\\Sigma", "Σ", "Greek uppercase Sigma (Covariance matrix)", 0);
            add_latex ("\\tau", "\\tau", "τ", "Greek lowercase tau", 0);
            add_latex ("\\omega", "\\omega", "ω", "Greek lowercase omega", 0);
            add_latex ("\\chi^2", "\\chi^2", "χ²", "Chi-squared test statistic", 0);
            add_latex ("\\infty", "\\infty", "∞", "Infinity symbol", 0);
            add_latex ("\\partial", "\\partial", "∂", "Partial derivative operator", 0);
            add_latex ("\\nabla", "\\nabla", "∇", "Gradient / Nabla operator", 0);
            add_latex ("\\frac", "\\frac{}{}", "\\frac{num}{den}", "Mathematical fraction", 3);
            add_latex ("\\sqrt", "\\sqrt{}", "\\sqrt{radicand}", "Square root radical", 1);
            add_latex ("\\sum", "\\sum_{i=1}^{n}", "∑_{i=1}^{n}", "Summation operator with bounds", 0);
            add_latex ("\\prod", "\\prod_{i=1}^{n}", "∏_{i=1}^{n}", "Product operator with bounds", 0);
            add_latex ("\\int", "\\int_{a}^{b}", "∫_{a}^{b}", "Definite integral with bounds", 0);
            add_latex ("\\lim", "\\lim_{n \\to \\infty}", "lim", "Limit operator", 0);
            add_latex ("\\log", "\\log", "log", "Logarithm operator", 0);
            add_latex ("\\exp", "\\exp()", "exp", "Exponential operator", 1);
            add_latex ("\\hat", "\\hat{}", "\\hat{θ}", "Estimator hat accent", 1);
            add_latex ("\\bar", "\\bar{}", "\\bar{x}", "Sample mean overbar accent", 1);
            add_latex ("\\tilde", "\\tilde{}", "\\tilde{x}", "Tilde accent", 1);
            add_latex ("\\vec", "\\vec{}", "\\vec{v}", "Vector arrow accent", 1);
            add_latex ("\\text", "\\text{}", "\\text{...}", "Upright text inside math mode", 1);
            add_latex ("\\mathbf", "\\mathbf{}", "\\mathbf{X}", "Boldface matrix/vector symbol", 1);
            add_latex ("\\mathbb", "\\mathbb{R}", "ℝ", "Blackboard bold set symbol", 1);
            add_latex ("\\mathcal{N}", "\\mathcal{N}(\\mu, \\sigma^2)", "N(μ, σ²)", "Normal (Gaussian) distribution", 0);
            add_latex ("\\ce", "\\ce{}", "\\ce{H2O}", "mhchem chemical formula or reaction equation", 1);
            add_latex ("\\pm", "\\pm", "±", "Plus-or-minus sign", 0);
            add_latex ("\\times", "\\times", "×", "Multiplication cross", 0);
            add_latex ("\\cdot", "\\cdot", "·", "Center dot multiplication", 0);
            add_latex ("\\leq", "\\leq", "≤", "Less than or equal to", 0);
            add_latex ("\\geq", "\\geq", "≥", "Greater than or equal to", 0);
            add_latex ("\\neq", "\\neq", "≠", "Not equal to", 0);
            add_latex ("\\approx", "\\approx", "≈", "Approximately equal to", 0);
            add_latex ("\\sim", "\\sim", "∼", "Distributed as / tilde relation", 0);
            add_latex ("\\in", "\\in", "∈", "Element of set", 0);
            add_latex ("\\rightarrow", "\\rightarrow", "→", "Right arrow", 0);
            add_latex ("\\Rightarrow", "\\Rightarrow", "⇒", "Implies arrow", 0);
            add_latex ("\\left(", "\\left(  \\right)", "(...)", "Auto-sized parentheses", 9);
            add_latex ("\\documentclass", "\\documentclass{article}", "LaTeX", "Document class declaration", 1);
            add_latex ("\\usepackage", "\\usepackage{}", "LaTeX", "Import LaTeX package", 1);
            add_latex ("\\begin{document}", "\\begin{document}\n\n\\end{document}", "env", "Document body environment", 15);
            add_latex ("\\begin{equation}", "\\begin{equation}\n\n\\end{equation}", "env", "Numbered equation environment", 15);
            add_latex ("\\begin{align}", "\\begin{align}\n\n\\end{align}", "env", "Aligned multi-line equations", 12);
            add_latex ("\\begin{pmatrix}", "\\begin{pmatrix}\n  a & b \\\\\n  c & d\n\\end{pmatrix}", "env", "Parenthesized matrix", 14);
            add_latex ("\\begin{figure}", "\\begin{figure}[htbp]\n  \\centering\n  \\caption{}\n\\end{figure}", "env", "Floating figure environment", 13);
            add_latex ("\\begin{table}", "\\begin{table}[htbp]\n  \\centering\n  \\caption{}\n\\end{table}", "env", "Floating table environment", 12);
            add_latex ("\\begin{itemize}", "\\begin{itemize}\n  \\item \n\\end{itemize}", "env", "Bulleted list environment", 14);
            add_latex ("\\section", "\\section{}", "LaTeX", "Top-level section heading", 1);
            add_latex ("\\subsection", "\\subsection{}", "LaTeX", "Subsection heading", 1);
            add_latex ("\\subsubsection", "\\subsubsection{}", "LaTeX", "Subsubsection heading", 1);
            add_latex ("\\textbf", "\\textbf{}", "LaTeX", "Bold text", 1);
            add_latex ("\\textit", "\\textit{}", "LaTeX", "Italic text", 1);
            add_latex ("\\cite", "\\cite{}", "LaTeX", "Bibliography citation", 1);
            add_latex ("\\ref", "\\ref{}", "LaTeX", "Cross-reference label", 1);
            add_latex ("\\label", "\\label{}", "LaTeX", "Define cross-reference label", 1);

            // TypeScript & JavaScript Scientific/App Catalog
            add_ts ("const", "const ", "keyword", "Block-scoped constant declaration", IntelliSenseSymbolKind.KEYWORD, 0);
            add_ts ("let", "let ", "keyword", "Block-scoped variable declaration", IntelliSenseSymbolKind.KEYWORD, 0);
            add_ts ("function", "function name() {\n  \n}", "keyword", "Function declaration", IntelliSenseSymbolKind.KEYWORD, 4);
            add_ts ("async function", "async function name() {\n  \n}", "keyword", "Async function returning Promise", IntelliSenseSymbolKind.KEYWORD, 4);
            add_ts ("interface", "interface Name {\n  \n}", "type", "TypeScript interface definition", IntelliSenseSymbolKind.KEYWORD, 4);
            add_ts ("type", "type Name = ", "type", "TypeScript type alias", IntelliSenseSymbolKind.KEYWORD, 0);
            add_ts ("enum", "enum Name {\n  \n}", "type", "TypeScript enum definition", IntelliSenseSymbolKind.KEYWORD, 4);
            add_ts ("export", "export ", "keyword", "Export module binding", IntelliSenseSymbolKind.KEYWORD, 0);
            add_ts ("import", "import {  } from \"\";", "keyword", "ES module import", IntelliSenseSymbolKind.KEYWORD, 10);
            add_ts ("return", "return ", "keyword", "Return value from function", IntelliSenseSymbolKind.KEYWORD, 0);
            add_ts ("console.log", "console.log()", "(...data: any[]): void", "Print to stdout", IntelliSenseSymbolKind.FUNCTION, 1);
            add_ts ("console.error", "console.error()", "(...data: any[]): void", "Print to stderr", IntelliSenseSymbolKind.FUNCTION, 1);
            add_ts ("Promise.all", "Promise.all([])", "(values: Iterable<Promise<T>>)", "Await all promises concurrently", IntelliSenseSymbolKind.FUNCTION, 2);
            add_ts ("JSON.stringify", "JSON.stringify()", "(value, replacer?, space?)", "Serialize value to JSON string", IntelliSenseSymbolKind.FUNCTION, 1);
            add_ts ("JSON.parse", "JSON.parse()", "(text: string)", "Parse JSON string", IntelliSenseSymbolKind.FUNCTION, 1);
            add_ts ("fetch", "fetch(\"\")", "(input: RequestInfo): Promise<Response>", "Perform HTTP request", IntelliSenseSymbolKind.FUNCTION, 2);
            add_ts ("Array.from", "Array.from()", "(iterable)", "Create Array from iterable", IntelliSenseSymbolKind.FUNCTION, 1);
            add_ts ("Map", "new Map<>()", "Map<K, V>", "Key-value collection", IntelliSenseSymbolKind.FUNCTION, 3);
            add_ts ("Set", "new Set<>()", "Set<T>", "Unique value collection", IntelliSenseSymbolKind.FUNCTION, 3);
            add_ts ("Record", "Record<string, unknown>", "utility type", "Object key-value type", IntelliSenseSymbolKind.KEYWORD, 0);
            add_ts ("Partial", "Partial<>", "utility type", "Make all properties optional", IntelliSenseSymbolKind.KEYWORD, 1);
        }

        private static void add_r (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            r_catalog.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_py (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            py_catalog.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_py_df (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            py_df_methods.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_ts (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            ts_catalog.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_bash (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            bash_catalog.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_md (string label, string insert, string sig, string detail, IntelliSenseSymbolKind kind, int backtrack) {
            md_catalog.add (new IntelliSenseItem (label, insert, sig, detail, kind, backtrack));
        }

        private static void add_html (string label, string insert, string sig, string detail, int backtrack) {
            html_catalog.add (new IntelliSenseItem (label, insert, sig, detail, IntelliSenseSymbolKind.TAG, backtrack));
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
                if (chunk.language == "ts" || chunk.language == "typescript") {
                    return IntelliSenseContext.TYPESCRIPT_CODE;
                }
            }

            // 3. Dedicated script/document files (.R, .py, .ts, .tex, .html)
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
            if (lower_type == "tex" || lower_type == "latex") {
                return IntelliSenseContext.LATEX_MATH_CHEM;
            }
            if (lower_type == "html" || lower_type == "htm") {
                return IntelliSenseContext.HTML_CODE;
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

            // 5. Check LaTeX command prefix (\alpha, \frac, \begin{eq, etc.)
            int last_backslash = line_prefix.last_index_of ("\\");
            if (last_backslash >= 0) {
                string after_bs = line_prefix.substring (last_backslash + 1);
                bool valid_latex = true;
                for (int i = 0; i < after_bs.length; i++) {
                    char ch = after_bs[i];
                    if (!(ch.isalpha () || ch == '{' || ch == '^' || ch == '(')) {
                        valid_latex = false;
                        break;
                    }
                }
                if (valid_latex) {
                    return IntelliSenseContext.LATEX_MATH_CHEM;
                }
            }

            // 6. Check inline HTML tag prefix inside Markdown/Quarto (<div, </sec, etc.)
            int last_lt = line_prefix.last_index_of ("<");
            if (last_lt >= 0) {
                string after_lt = line_prefix.substring (last_lt + 1);
                if (!after_lt.contains (">") && !after_lt.contains (" ")) {
                    bool valid_tag = true;
                    for (int i = 0; i < after_lt.length; i++) {
                        char ch = after_lt[i];
                        if (!(ch.isalnum () || ch == '/' || ch == '-')) {
                            valid_tag = false;
                            break;
                        }
                    }
                    if (valid_tag) {
                        return IntelliSenseContext.HTML_CODE;
                    }
                }
            }

            return IntelliSenseContext.MARKDOWN_PROSE;
        }

        /**
         * Context-aware extraction of the active token immediately preceding the cursor.
         */
        public static string extract_active_token_for_context (string line_prefix, IntelliSenseContext ctx) {
            int len = line_prefix.length;
            if (len == 0) {
                return "";
            }

            if (ctx == IntelliSenseContext.LATEX_MATH_CHEM) {
                int start = len;
                while (start > 0) {
                    char c = line_prefix[start - 1];
                    if (c == '\\') {
                        start--;
                        break;
                    }
                    if (c.isalnum () || c == '_' || c == '^' || c == '{' || c == '(') {
                        start--;
                    } else {
                        break;
                    }
                }
                return line_prefix.substring (start);
            }

            if (ctx == IntelliSenseContext.HTML_CODE) {
                int start = len;
                while (start > 0) {
                    char c = line_prefix[start - 1];
                    if (c == '<') {
                        start--;
                        break;
                    }
                    if (c.isalnum () || c == '/' || c == '-' || c == '_') {
                        start--;
                    } else {
                        break;
                    }
                }
                return line_prefix.substring (start);
            }

            if (ctx == IntelliSenseContext.R_CODE) {
                int start = len;
                while (start > 0) {
                    char c = line_prefix[start - 1];
                    if (c.isalnum () || c == '_' || c == '.' || c == '$' || c == ':') {
                        start--;
                    } else {
                        break;
                    }
                }
                return line_prefix.substring (start);
            }

            if (ctx == IntelliSenseContext.PYTHON_CODE || ctx == IntelliSenseContext.TYPESCRIPT_CODE) {
                int start = len;
                while (start > 0) {
                    char c = line_prefix[start - 1];
                    if (c.isalnum () || c == '_' || c == '.') {
                        start--;
                    } else {
                        break;
                    }
                }
                return line_prefix.substring (start);
            }

            if (ctx == IntelliSenseContext.MARKDOWN_PROSE) {
                int start = len;
                while (start > 0) {
                    char c = line_prefix[start - 1];
                    if (c == '@') {
                        start--;
                        break;
                    }
                    if (c.isalnum () || c == '_' || c == '-' || c == ':' || c == '$') {
                        start--;
                    } else {
                        break;
                    }
                }
                return line_prefix.substring (start);
            }

            if (ctx == IntelliSenseContext.BASH_CODE) {
                int start = len;
                while (start > 0) {
                    char c = line_prefix[start - 1];
                    if (c.isalnum () || c == '_' || c == '-' || c == '.' || c == '/' || c == '$') {
                        start--;
                    } else {
                        break;
                    }
                }
                return line_prefix.substring (start);
            }

            // YAML_FRONTMATTER / QUARTO_HASH_PIPE / CHUNK_FENCE_HEADER
            return extract_active_token (line_prefix);
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
                if (c == '\\') {
                    start--;
                    break;
                }
                if (c.isalnum () || c == '_' || c == '.' || c == '$' || c == ':' || c == '-') {
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
         * Scans document for Quarto/Markdown cross-reference labels (#| label: fig-x, {#sec-y}, etc.).
         */
        public static ArrayList<IntelliSenseItem> scan_cross_references (string document_text) {
            var refs = new ArrayList<IntelliSenseItem> ();
            var seen = new HashSet<string> ();
            try {
                // 1. Quarto hash-pipe labels: #| label: fig-volcano
                if (cached_hp_rx == null) {
                    cached_hp_rx = new GLib.Regex ("^\\s*#\\|\\s*label:\\s*([a-zA-Z0-9_-]+)", GLib.RegexCompileFlags.MULTILINE);
                }
                GLib.MatchInfo mi;
                if (cached_hp_rx.match (document_text, 0, out mi)) {
                    do {
                        string lbl = mi.fetch (1).strip ();
                        if (lbl.length > 0 && !seen.contains (lbl)) {
                            seen.add (lbl);
                            refs.add (new IntelliSenseItem (
                                "@" + lbl,
                                "@" + lbl,
                                "cross-ref",
                                @"Cross-reference to chunk label '$lbl'",
                                IntelliSenseSymbolKind.REFERENCE,
                                0
                            ));
                        }
                    } while (mi.next ());
                }

                // 2. Pandoc/Quarto explicit IDs: {#fig-foo}, {#tbl-bar}, {#sec-intro}, {#eq-model}
                if (cached_id_rx == null) {
                    cached_id_rx = new GLib.Regex ("\\{#((?:fig|tbl|sec|eq|lst|thm|lem|cor|prp|cnj|def|exm|exr)-[a-zA-Z0-9_-]+)");
                }
                GLib.MatchInfo mi2;
                if (cached_id_rx.match (document_text, 0, out mi2)) {
                    do {
                        string lbl = mi2.fetch (1).strip ();
                        if (lbl.length > 0 && !seen.contains (lbl)) {
                            seen.add (lbl);
                            refs.add (new IntelliSenseItem (
                                "@" + lbl,
                                "@" + lbl,
                                "cross-ref",
                                @"Cross-reference to '#$lbl'",
                                IntelliSenseSymbolKind.REFERENCE,
                                0
                            ));
                        }
                    } while (mi2.next ());
                }
            } catch (GLib.RegexError e) {}
            return refs;
        }

        /**
         * Scans the active document buffer for user-defined variables, functions, and DataFrame columns.
         */
        public static ArrayList<IntelliSenseItem> scan_buffer_symbols (
            string document_text,
            IntelliSenseContext ctx,
            out HashMap<string, ArrayList<string>> discovered_columns,
            string doc_type = "markdown"
        ) {
            var symbols = new ArrayList<IntelliSenseItem> ();
            discovered_columns = new HashMap<string, ArrayList<string>> ();
            if (ctx == IntelliSenseContext.TYPESCRIPT_CODE) {
                string json_str = Core.NativeCore.analyze_typescript_symbols_json (document_text);
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_data (json_str, -1);
                    var root = parser.get_root ();
                    if (root != null && root.get_node_type () == Json.NodeType.ARRAY) {
                        var arr = root.get_array ();
                        var seen_ts = new HashSet<string> ();
                        for (uint i = 0; i < arr.get_length (); i++) {
                            var obj = arr.get_object_element (i);
                            string name = obj.has_member ("name") ? (obj.get_string_member ("name") ?? "") : "";
                            string kind_str = obj.has_member ("kind") ? (obj.get_string_member ("kind") ?? "symbol") : "symbol";
                            if (name.length > 0 && !seen_ts.contains (name)) {
                                seen_ts.add (name);
                                var sym_kind = (kind_str == "function" || kind_str == "method" || kind_str == "class")
                                    ? IntelliSenseSymbolKind.FUNCTION
                                    : IntelliSenseSymbolKind.VARIABLE;
                                string ins = (kind_str == "function" || kind_str == "method") ? name + "()" : name;
                                int bt = (kind_str == "function" || kind_str == "method") ? 1 : 0;
                                symbols.add (new IntelliSenseItem (name, ins, kind_str, "TypeScript symbol in document", sym_kind, bt));
                            }
                        }
                    }
                } catch (GLib.Error e) {}
                return symbols;
            }

            if (ctx != IntelliSenseContext.R_CODE && ctx != IntelliSenseContext.PYTHON_CODE) {
                return symbols;
            }

            var seen = new HashSet<string> ();
            string lower_dt = doc_type.down ();
            bool is_pure_script = (lower_dt == "r" || lower_dt == "rscript" || lower_dt == "python" || lower_dt == "python3" || lower_dt == "pyscript" || lower_dt == "ts" || lower_dt == "typescript");
            bool has_fences = !is_pure_script && document_text.contains ("```");
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

                // 1. Detect R assignments: var_name <- ... or var_name = ... plus any df$col usage
                if (ctx == IntelliSenseContext.R_CODE) {
                    // Discover df$col anywhere in line
                    scan_r_dollar_columns (line, discovered_columns);

                    string? assign_lhs = null;
                    string? assign_rhs = null;
                    if (line.contains ("<-")) {
                        string[] parts = line.split ("<-", 2);
                        assign_lhs = parts[0].strip ();
                        assign_rhs = parts.length > 1 ? parts[1].strip () : "";
                    } else if (line.contains ("=") && !line.contains ("==") && !line.contains ("!=") && !line.contains ("<=") && !line.contains (">=")) {
                        int eq_idx = line.index_of ("=");
                        string before_eq = line.substring (0, eq_idx);
                        // Only treat '=' as assignment if not inside a function call's parentheses
                        if (!before_eq.contains ("(")) {
                            assign_lhs = before_eq.strip ();
                            assign_rhs = line.substring (eq_idx + 1).strip ();
                        }
                    }

                    if (assign_lhs != null && assign_rhs != null) {
                        if (assign_lhs.contains ("$")) {
                            string[] df_parts = assign_lhs.split ("$", 2);
                            string df_name = sanitize_identifier (df_parts[0]);
                            string col_name = sanitize_identifier (df_parts[1]);
                            if (df_name.length > 0 && col_name.length > 0) {
                                add_discovered_column (discovered_columns, df_name, col_name);
                            }
                        } else {
                            string ident = sanitize_identifier (assign_lhs);
                            if (ident.length >= 2 && !seen.contains (ident)) {
                                seen.add (ident);
                                if (assign_rhs.has_prefix ("function")) {
                                    symbols.add (new IntelliSenseItem (ident, ident + "()", "(...)", "User function defined in document", IntelliSenseSymbolKind.FUNCTION, 1));
                                } else if (assign_rhs.contains ("read.") || assign_rhs.contains ("read_") || assign_rhs.contains ("data.frame") || assign_rhs.contains ("tibble")) {
                                    symbols.add (new IntelliSenseItem (ident, ident, "data.frame", "DataFrame defined in document", IntelliSenseSymbolKind.DATAFRAME, 0));
                                } else {
                                    symbols.add (new IntelliSenseItem (ident, ident, "object", "Variable defined in document", IntelliSenseSymbolKind.VARIABLE, 0));
                                }
                            }
                        }
                    }
                }

                // 2. Detect Python def / class / assignments / df['col'] columns
                if (ctx == IntelliSenseContext.PYTHON_CODE) {
                    scan_python_df_columns (line, discovered_columns);

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
                                symbols.add (new IntelliSenseItem (cls_name, cls_name, "class", "Python class defined in document", IntelliSenseSymbolKind.FUNCTION, 0));
                            }
                        }
                    } else if (line.contains ("=") && !line.contains ("==") && !line.contains ("!=") && !line.contains ("<=") && !line.contains (">=")) {
                        string[] parts = line.split ("=", 2);
                        string ident = sanitize_identifier (parts[0]);
                        string rhs = parts.length > 1 ? parts[1].strip () : "";
                        if (ident.length >= 2 && !seen.contains (ident) && !ident.contains ("(")) {
                            seen.add (ident);
                            bool is_df = rhs.contains ("read_csv") || rhs.contains ("read_table") || rhs.contains ("read_excel") || rhs.contains ("DataFrame");
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

        private static void scan_r_dollar_columns (string line, HashMap<string, ArrayList<string>> map) {
            if (!line.contains ("$")) return;
            try {
                if (cached_r_dollar_rx == null) {
                    cached_r_dollar_rx = new GLib.Regex ("\\b([a-zA-Z_][a-zA-Z0-9_.]*)\\$([a-zA-Z_][a-zA-Z0-9_.]*)");
                }
                GLib.MatchInfo mi;
                if (cached_r_dollar_rx.match (line, 0, out mi)) {
                    do {
                        string df_name = mi.fetch (1);
                        string col_name = mi.fetch (2);
                        if (df_name.length > 0 && col_name.length > 0) {
                            add_discovered_column (map, df_name, col_name);
                        }
                    } while (mi.next ());
                }
            } catch (GLib.RegexError e) {}
        }

        private static void scan_python_df_columns (string line, HashMap<string, ArrayList<string>> map) {
            if (!line.contains ("[")) return;
            try {
                if (cached_py_col_rx == null) {
                    cached_py_col_rx = new GLib.Regex ("\\b([a-zA-Z_][a-zA-Z0-9_]*)\\[['\"]([a-zA-Z_][a-zA-Z0-9_]*)['\"]\\]");
                }
                GLib.MatchInfo mi;
                if (cached_py_col_rx.match (line, 0, out mi)) {
                    do {
                        string df_name = mi.fetch (1);
                        string col_name = mi.fetch (2);
                        if (df_name.length > 0 && col_name.length > 0) {
                            add_discovered_column (map, df_name, col_name);
                        }
                    } while (mi.next ());
                }
            } catch (GLib.RegexError e) {}
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
         * Finds the innermost enclosing function call name on the current line (e.g. "ggplot(" -> "ggplot").
         */
        private static string? detect_enclosing_function_call (string line_prefix) {
            int depth = 0;
            for (int i = line_prefix.length - 1; i >= 0; i--) {
                char c = line_prefix[i];
                if (c == ')') {
                    depth++;
                } else if (c == '(') {
                    if (depth == 0) {
                        int end_fn = i;
                        while (end_fn > 0 && line_prefix[end_fn - 1] == ' ') {
                            end_fn--;
                        }
                        int start_fn = end_fn;
                        while (start_fn > 0) {
                            char fc = line_prefix[start_fn - 1];
                            if (fc.isalnum () || fc == '_' || fc == '.') {
                                start_fn--;
                            } else {
                                break;
                            }
                        }
                        if (end_fn > start_fn) {
                            return line_prefix.substring (start_fn, end_fn - start_fn);
                        }
                        return null;
                    }
                    depth--;
                }
            }
            return null;
        }

        /**
         * Detects the nearest unclosed HTML tag before the cursor for '</' smart closing tag completion.
         */
        private static string? find_nearest_unclosed_html_tag (string document_text, int cursor_line, string line_prefix) {
            string[] lines = document_text.split ("\n");
            var sb = new StringBuilder ();
            int max_line = int.min (cursor_line, lines.length - 1);
            for (int i = 0; i < max_line; i++) {
                sb.append (lines[i]);
                sb.append ("\n");
            }
            int last_lt = line_prefix.last_index_of ("<");
            if (last_lt > 0) {
                sb.append (line_prefix.substring (0, last_lt));
            }

            var stack = new ArrayList<string> ();
            try {
                if (cached_html_tag_rx == null) {
                    cached_html_tag_rx = new GLib.Regex ("<(/?)([a-zA-Z][a-zA-Z0-9-]*)\\b[^>]*?(/?)>");
                }
                GLib.MatchInfo mi;
                if (cached_html_tag_rx.match (sb.str, 0, out mi)) {
                    do {
                        bool is_close = (mi.fetch (1) == "/");
                        string tag = mi.fetch (2).down ();
                        bool is_self = (mi.fetch (3) == "/");
                        if (is_self || tag == "br" || tag == "hr" || tag == "img" || tag == "input" || tag == "meta" || tag == "link") {
                            continue;
                        }
                        if (is_close) {
                            for (int idx = stack.size - 1; idx >= 0; idx--) {
                                if (stack.get (idx) == tag) {
                                    stack.remove_at (idx);
                                    break;
                                }
                            }
                        } else {
                            stack.add (tag);
                        }
                    } while (mi.next ());
                }
            } catch (GLib.RegexError e) {}

            if (stack.size > 0) {
                return stack.get (stack.size - 1);
            }
            return null;
        }

        /**
         * Primary entry point: Returns ranked completion items for the current cursor state.
         */
        public static ArrayList<IntelliSenseItem> query_completions (
            string document_text,
            int cursor_line,
            string line_prefix,
            string doc_type = "markdown",
            bool manual_trigger = false,
            IntelliSenseContext? precomputed_ctx = null
        ) {
            ensure_catalogs_initialized ();
            var results = new ArrayList<IntelliSenseItem> ();
            var ctx = precomputed_ctx ?? detect_context (document_text, cursor_line, line_prefix, doc_type);
            string token = extract_active_token_for_context (line_prefix, ctx);

            // 1. Chunk Fence Header Context (```{r}, ```{python}, etc.)
            if (ctx == IntelliSenseContext.CHUNK_FENCE_HEADER) {
                string fence_query = line_prefix.strip ();
                var fence_items = new ArrayList<IntelliSenseItem> ();
                fence_items.add (new IntelliSenseItem ("```{r}", "```{r}\n\n```", "Quarto R Chunk", "Insert executable R code chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                fence_items.add (new IntelliSenseItem ("```{python}", "```{python}\n\n```", "Quarto Python Chunk", "Insert executable Python code chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                fence_items.add (new IntelliSenseItem ("```{bash}", "```{bash}\n\n```", "Quarto Bash Chunk", "Insert executable Shell code chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                fence_items.add (new IntelliSenseItem ("```{mermaid}", "```{mermaid}\nflowchart LR\n  A[Start] --> B[End]\n```", "Mermaid Diagram", "Insert Mermaid flowchart chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                fence_items.add (new IntelliSenseItem ("```{ojs}", "```{ojs}\n\n```", "Observable JS", "Insert interactive Observable JS chunk", IntelliSenseSymbolKind.SNIPPET, 4));
                fence_items.add (new IntelliSenseItem ("```typescript", "```typescript\n\n```", "TypeScript Block", "Insert TypeScript fenced code block", IntelliSenseSymbolKind.SNIPPET, 4));

                foreach (var fi in fence_items) {
                    int sc = compute_match_score (fi.label, fence_query);
                    if (sc > 0) {
                        results.add (clone_with_score (fi, sc));
                    }
                }
                sort_by_score (results);
                return results;
            }

            // 2. Quarto '#|' Hash-Pipe Option Context
            if (ctx == IntelliSenseContext.QUARTO_HASH_PIPE) {
                string opt_query = line_prefix.strip ().substring (2).strip ();
                foreach (var item in quarto_opt_catalog) {
                    int sc = compute_match_score (item.label, opt_query);
                    if (sc > 0) {
                        results.add (clone_with_score (item, sc));
                    }
                }
                sort_by_score (results);
                return results;
            }

            // 3. YAML Frontmatter Context
            if (ctx == IntelliSenseContext.YAML_FRONTMATTER) {
                if (token.length == 0 && !manual_trigger) {
                    return results;
                }
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
                } else if (!manual_trigger && math_query.length == 0) {
                    return results;
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

            // 5. HTML Tag Context (.html documents and inline HTML in Markdown)
            if (ctx == IntelliSenseContext.HTML_CODE) {
                if (token.has_prefix ("</")) {
                    string? unclosed = find_nearest_unclosed_html_tag (document_text, cursor_line, line_prefix);
                    if (unclosed != null) {
                        string close_tag = @"</$unclosed>";
                        int sc = compute_match_score (close_tag, token);
                        if (sc > 0) {
                            results.add (new IntelliSenseItem (
                                close_tag,
                                close_tag,
                                "closing tag",
                                @"Close open <$unclosed> element",
                                IntelliSenseSymbolKind.TAG,
                                0
                            ) { score = sc + 300 });
                        }
                    }
                }
                if (token.has_prefix ("<") || manual_trigger) {
                    string q = token.has_prefix ("</") ? "<" + token.substring (2) : token;
                    foreach (var item in html_catalog) {
                        int sc = compute_match_score (item.label, q);
                        if (sc > 0) {
                            results.add (clone_with_score (item, sc));
                        }
                    }
                }
                sort_by_score (results);
                return results;
            }

            // 6. Markdown / Quarto Prose Writing Context
            if (ctx == IntelliSenseContext.MARKDOWN_PROSE) {
                // 6a. Cross-references on '@' (@fig-..., @tbl-..., @sec-..., @eq-...)
                if (token.has_prefix ("@")) {
                    var xrefs = scan_cross_references (document_text);
                    foreach (var xr in xrefs) {
                        int sc = compute_match_score (xr.label, token);
                        if (sc > 0) {
                            results.add (clone_with_score (xr, sc + 200));
                        }
                    }
                    sort_by_score (results);
                    return results;
                }

                // 6b. Quarto callouts (:::) or display math ($$) or writing snippets
                string trimmed_lp = line_prefix.strip ();
                bool special_md_trigger = trimmed_lp.has_prefix ("::")
                    || token.has_prefix ("$$")
                    || token.has_prefix ("::");

                if (manual_trigger || special_md_trigger || token.length >= 2) {
                    string md_query = trimmed_lp.has_prefix ("::") ? trimmed_lp : token;
                    foreach (var item in md_catalog) {
                        int sc = compute_match_score (item.label, md_query);
                        // For regular prose words (not special triggers or Ctrl+Space), require prefix match so normal English prose isn't spammed
                        if (sc > 0 && (manual_trigger || special_md_trigger || item.label.down ().has_prefix (md_query.down ()))) {
                            results.add (clone_with_score (item, sc));
                        }
                    }
                }
                sort_by_score (results);
                return results;
            }

            HashMap<string, ArrayList<string>> discovered_cols;
            var buffer_symbols = scan_buffer_symbols (document_text, ctx, out discovered_cols, doc_type);

            // 7. R Code Context (including df$col, pkg::fn, library(pkg), and fn(arg = ) RStudio parity)
            if (ctx == IntelliSenseContext.R_CODE) {
                // 7a. R DataFrame '$' Column Accessor (e.g., mtcars$mp or clinical_df$)
                if (token.contains ("$")) {
                    string[] parts = token.split ("$", 2);
                    string df_name = parts[0];
                    string col_prefix = parts.length > 1 ? parts[1] : "";
                    var seen_cols = new HashSet<string> ();

                    if (builtin_df_columns.has_key (df_name)) {
                        foreach (string col in builtin_df_columns.get (df_name).split (",")) {
                            int sc = compute_match_score (col, col_prefix);
                            if (sc > 0 && !seen_cols.contains (col)) {
                                seen_cols.add (col);
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
                            if (sc > 0 && !seen_cols.contains (col)) {
                                seen_cols.add (col);
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

                // 7b. R Package Namespace Accessor (e.g., dplyr::, survival::, ggplot2::, stats::)
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

                // 7c. R library(...) / require(...) package completions
                string? enclosing_fn = detect_enclosing_function_call (line_prefix);
                if (enclosing_fn == "library" || enclosing_fn == "require" || enclosing_fn == "requireNamespace") {
                    foreach (string pkg in r_packages) {
                        int sc = compute_match_score (pkg, token);
                        if (sc > 0) {
                            results.add (new IntelliSenseItem (
                                pkg,
                                pkg,
                                "R package",
                                @"CRAN / Bioconductor package '$pkg'",
                                IntelliSenseSymbolKind.MODULE,
                                0
                            ) { score = sc + 250 });
                        }
                    }
                    sort_by_score (results);
                    return results;
                }

                // 7d. R Named Function Parameter Completions inside fn(...)
                if (enclosing_fn != null && r_function_args.has_key (enclosing_fn)) {
                    string args_csv = r_function_args.get (enclosing_fn);
                    foreach (string arg in args_csv.split (",")) {
                        int sc = compute_match_score (arg, token);
                        if (sc > 0) {
                            results.add (new IntelliSenseItem (
                                arg + " =",
                                arg + " = ",
                                @"parameter of $enclosing_fn()",
                                @"Named argument for $enclosing_fn()",
                                IntelliSenseSymbolKind.OPTION,
                                0
                            ) { score = sc + 220 });
                        }
                    }
                }

                // 7e. Standard R Functions + Live Buffer Symbols
                if (token.length == 0 && !manual_trigger && results.size == 0) {
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

            // 8. Python Code Context
            if (ctx == IntelliSenseContext.PYTHON_CODE) {
                string stripped_lp = line_prefix.strip ();

                // 8a. Python 'import ' / 'from ' module completion
                if (stripped_lp.has_prefix ("import ") || (stripped_lp.has_prefix ("from ") && !stripped_lp.contains (" import "))) {
                    foreach (string mod in py_modules) {
                        int sc = compute_match_score (mod, token);
                        if (sc > 0) {
                            results.add (new IntelliSenseItem (
                                mod,
                                mod,
                                "module",
                                @"Python module '$mod'",
                                IntelliSenseSymbolKind.MODULE,
                                0
                            ) { score = sc + 250 });
                        }
                    }
                    sort_by_score (results);
                    return results;
                }

                // 8b. Python dot-member completions: pd.*, np.*, plt.*, sns.*, stats.*, or <df_var>.*
                if (token.contains (".")) {
                    int dot_idx = token.index_of (".");
                    string obj_name = token.substring (0, dot_idx);
                    string member_prefix = token.substring (dot_idx + 1);

                    // Match catalog dot-methods (pd.*, np.*, plt.*, sns.*, stats.*)
                    foreach (var item in py_catalog) {
                        if (item.label.has_prefix (obj_name + ".")) {
                            int sc = compute_match_score (item.label, token);
                            if (sc > 0) {
                                results.add (clone_with_score (item, sc + 150));
                            }
                        }
                    }

                    // If object is a discovered DataFrame or commonly named DataFrame, offer DataFrame methods & discovered columns
                    bool is_known_df = (obj_name == "df" || obj_name.has_prefix ("df_") || obj_name.has_suffix ("_df") || discovered_cols.has_key (obj_name));
                    if (!is_known_df) {
                        foreach (var sym in buffer_symbols) {
                            if (sym.label == obj_name && sym.kind == IntelliSenseSymbolKind.DATAFRAME) {
                                is_known_df = true;
                                break;
                            }
                        }
                    }
                    if (is_known_df) {
                        if (discovered_cols.has_key (obj_name)) {
                            foreach (string col in discovered_cols.get (obj_name)) {
                                int sc = compute_match_score (col, member_prefix);
                                if (sc > 0) {
                                    results.add (new IntelliSenseItem (
                                        obj_name + "." + col,
                                        obj_name + "." + col,
                                        "column",
                                        @"Column of $obj_name DataFrame",
                                        IntelliSenseSymbolKind.COLUMN,
                                        0
                                    ) { score = sc + 230 });
                                }
                            }
                        }
                        foreach (var dfm in py_df_methods) {
                            int sc = compute_match_score (dfm.label, member_prefix);
                            if (sc > 0) {
                                results.add (new IntelliSenseItem (
                                    obj_name + "." + dfm.label,
                                    obj_name + "." + dfm.insert_text,
                                    dfm.signature,
                                    dfm.detail,
                                    dfm.kind,
                                    dfm.cursor_backtrack
                                ) { score = sc + 180 });
                            }
                        }
                    }

                    sort_by_score (results);
                    return results;
                }

                if (token.length == 0 && !manual_trigger) {
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

            // 9. Bash / Shell Code Context
            if (ctx == IntelliSenseContext.BASH_CODE) {
                if (token.length == 0 && !manual_trigger) {
                    return results;
                }
                foreach (var item in bash_catalog) {
                    int sc = compute_match_score (item.label, token);
                    if (sc > 0) {
                        results.add (clone_with_score (item, sc));
                    }
                }
                sort_by_score (results);
                return results;
            }

            // 10. TypeScript / JavaScript Code Context
            if (ctx == IntelliSenseContext.TYPESCRIPT_CODE) {
                if (token.length == 0 && !manual_trigger) {
                    return results;
                }
                foreach (var sym in buffer_symbols) {
                    int sc = compute_match_score (sym.label, token);
                    if (sc > 0) {
                        results.add (clone_with_score (sym, sc + 50));
                    }
                }
                foreach (var item in ts_catalog) {
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

        /**
         * Returns the static pandas DataFrame methods catalog for external live-environment merging.
         */
        public static ArrayList<IntelliSenseItem> get_python_df_methods () {
            ensure_catalogs_initialized ();
            return py_df_methods;
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
