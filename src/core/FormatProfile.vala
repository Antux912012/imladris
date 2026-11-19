/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;

namespace Imladris.Core {

    public enum CitationStyle {
        NONE,
        PANDOC_AT,
        LATEX_CITE
    }

    public enum RibbonRunMode {
        HIDDEN,
        NOTEBOOK_CHUNKS,
        LATEX_COMPILE,
        TYPESCRIPT_RUNNER,
        SCRIPT_RUNNER
    }

    public enum RibbonHomeMode {
        MARKDOWN_PROSE,
        LATEX_PROSE,
        HTML_TAGS,
        CODE_EDITING
    }

    public enum HeaderActionKind {
        NONE,
        QUARTO_RENDER,
        RMD_KNIT,
        IPYNB_EXPORT,
        MD_EXPORT,
        LATEX_BUILD,
        TS_RUN_CHECK,
        HTML_PREVIEW,
        SCRIPT_RUN
    }

    /**
     * Central capability descriptor for every supported document format.
     * Drives HeaderBar controls, Ribbon tabs/groups, layout defaults, comments,
     * citations, and execution/export routing without scattered format checks.
     */
    public class FormatProfile : GLib.Object {
        public DocumentFormat format { get; construct; }
        public bool supports_chunks { get; construct; }
        public bool supports_prose_ribbon { get; construct; }
        public bool supports_latex_ribbon { get; construct; }
        public bool supports_ts_actions { get; construct; }
        public bool supports_html_actions { get; construct; }
        public bool supports_quarto_render { get; construct; }
        public bool supports_latex_build { get; construct; }
        public bool supports_live_preview { get; construct; }
        public bool supports_publish_tab { get; construct; }
        public bool supports_packages_tab { get; construct; }
        public bool supports_shiny_detection { get; construct; }
        public bool default_rstudio_layout { get; construct; }
        public string default_kernel { get; construct; }
        public string line_comment_prefix { get; construct; }
        public string block_comment_open { get; construct; }
        public string block_comment_close { get; construct; }
        public CitationStyle citation_style { get; construct; }
        public RibbonRunMode ribbon_run_mode { get; construct; }
        public RibbonHomeMode ribbon_home_mode { get; construct; }
        public HeaderActionKind header_action_kind { get; construct; }
        public string primary_action_label { get; construct; }
        public string primary_action_tooltip { get; construct; }
        public string primary_action_icon { get; construct; }
        public string short_badge { get; construct; }

        private string[] _export_targets;

        public FormatProfile (
            DocumentFormat format,
            bool supports_chunks,
            bool supports_prose_ribbon,
            bool supports_latex_ribbon,
            bool supports_ts_actions,
            bool supports_html_actions,
            bool supports_quarto_render,
            bool supports_latex_build,
            bool supports_live_preview,
            bool supports_publish_tab,
            bool supports_packages_tab,
            bool supports_shiny_detection,
            bool default_rstudio_layout,
            string default_kernel,
            string line_comment_prefix,
            string block_comment_open,
            string block_comment_close,
            CitationStyle citation_style,
            RibbonRunMode ribbon_run_mode,
            RibbonHomeMode ribbon_home_mode,
            HeaderActionKind header_action_kind,
            string primary_action_label,
            string primary_action_tooltip,
            string primary_action_icon,
            string short_badge,
            string[] export_targets
        ) {
            Object (
                format: format,
                supports_chunks: supports_chunks,
                supports_prose_ribbon: supports_prose_ribbon,
                supports_latex_ribbon: supports_latex_ribbon,
                supports_ts_actions: supports_ts_actions,
                supports_html_actions: supports_html_actions,
                supports_quarto_render: supports_quarto_render,
                supports_latex_build: supports_latex_build,
                supports_live_preview: supports_live_preview,
                supports_publish_tab: supports_publish_tab,
                supports_packages_tab: supports_packages_tab,
                supports_shiny_detection: supports_shiny_detection,
                default_rstudio_layout: default_rstudio_layout,
                default_kernel: default_kernel,
                line_comment_prefix: line_comment_prefix,
                block_comment_open: block_comment_open,
                block_comment_close: block_comment_close,
                citation_style: citation_style,
                ribbon_run_mode: ribbon_run_mode,
                ribbon_home_mode: ribbon_home_mode,
                header_action_kind: header_action_kind,
                primary_action_label: primary_action_label,
                primary_action_tooltip: primary_action_tooltip,
                primary_action_icon: primary_action_icon,
                short_badge: short_badge
            );
            this._export_targets = export_targets;
        }

        public string[] get_export_targets () {
            return _export_targets;
        }

        public static FormatProfile for_format (DocumentFormat fmt) {
            switch (fmt) {
                case DocumentFormat.QMD:
                    return new FormatProfile (
                        DocumentFormat.QMD,
                        true, true, false, false, false, true, false, true, true, true, true, true,
                        "r", "", "<!-- ", " -->",
                        CitationStyle.PANDOC_AT,
                        RibbonRunMode.NOTEBOOK_CHUNKS,
                        RibbonHomeMode.MARKDOWN_PROSE,
                        HeaderActionKind.QUARTO_RENDER,
                        "Render",
                        "Render Quarto Document to Target Format",
                        "system-run-symbolic",
                        "QMD",
                        new string[] { "HTML", "PDF", "RevealJS", "Beamer PDF", "Typst/PDF" }
                    );
                case DocumentFormat.RMD:
                    return new FormatProfile (
                        DocumentFormat.RMD,
                        true, true, false, false, false, false, false, true, true, true, true, true,
                        "r", "", "<!-- ", " -->",
                        CitationStyle.PANDOC_AT,
                        RibbonRunMode.NOTEBOOK_CHUNKS,
                        RibbonHomeMode.MARKDOWN_PROSE,
                        HeaderActionKind.RMD_KNIT,
                        "Knit",
                        "Knit R Markdown Document",
                        "system-run-symbolic",
                        "RMD",
                        new string[] { "HTML", "PDF", "Word", "ODT" }
                    );
                case DocumentFormat.IPYNB:
                    return new FormatProfile (
                        DocumentFormat.IPYNB,
                        true, true, false, false, false, false, false, true, true, true, false, true,
                        "python", "", "<!-- ", " -->",
                        CitationStyle.PANDOC_AT,
                        RibbonRunMode.NOTEBOOK_CHUNKS,
                        RibbonHomeMode.MARKDOWN_PROSE,
                        HeaderActionKind.IPYNB_EXPORT,
                        "Run / Export",
                        "Execute Notebook Cells or Export",
                        "media-playback-start-symbolic",
                        "IPYNB",
                        new string[] { "Execute & Preview", "HTML", "PDF", "Notebook (.ipynb)" }
                    );
                case DocumentFormat.MD:
                    return new FormatProfile (
                        DocumentFormat.MD,
                        false, true, false, false, false, false, false, true, true, false, false, false,
                        "none", "", "<!-- ", " -->",
                        CitationStyle.PANDOC_AT,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.MARKDOWN_PROSE,
                        HeaderActionKind.MD_EXPORT,
                        "Export",
                        "Preview or Export Markdown Document",
                        "document-send-symbolic",
                        "MD",
                        new string[] { "HTML", "PDF", "ODT", "RTF" }
                    );
                case DocumentFormat.TEX:
                    return new FormatProfile (
                        DocumentFormat.TEX,
                        false, false, true, false, false, false, true, true, true, false, false, false,
                        "latex", "% ", "", "",
                        CitationStyle.LATEX_CITE,
                        RibbonRunMode.LATEX_COMPILE,
                        RibbonHomeMode.LATEX_PROSE,
                        HeaderActionKind.LATEX_BUILD,
                        "Compile PDF",
                        "Compile LaTeX Document (latexmk / xelatex / pdflatex)",
                        "system-run-symbolic",
                        "TEX",
                        new string[] { "PDF (latexmk)", "PDF (xelatex)", "PDF (pdflatex)", "HTML (Pandoc)" }
                    );
                case DocumentFormat.TS:
                    return new FormatProfile (
                        DocumentFormat.TS,
                        false, false, false, true, false, false, false, false, false, true, false, true,
                        "typescript", "// ", "/* ", " */",
                        CitationStyle.NONE,
                        RibbonRunMode.TYPESCRIPT_RUNNER,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.TS_RUN_CHECK,
                        "Run TS",
                        "Run or Typecheck TypeScript File",
                        "media-playback-start-symbolic",
                        "TS",
                        new string[] { "Run TypeScript", "Typecheck (tsc --noEmit)" }
                    );
                case DocumentFormat.HTML:
                    return new FormatProfile (
                        DocumentFormat.HTML,
                        false, false, false, false, true, false, false, true, true, false, false, false,
                        "none", "", "<!-- ", " -->",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.HTML_TAGS,
                        HeaderActionKind.HTML_PREVIEW,
                        "Preview",
                        "Refresh HTML Preview or Print to PDF",
                        "text-html-symbolic",
                        "HTML",
                        new string[] { "Refresh Preview", "Print to PDF", "Open in Browser" }
                    );
                case DocumentFormat.RSCRIPT:
                    return new FormatProfile (
                        DocumentFormat.RSCRIPT,
                        false, false, false, false, false, false, false, false, false, true, true, true,
                        "r", "# ", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.SCRIPT_RUNNER,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.SCRIPT_RUN,
                        "Run R",
                        "Execute R Script in Console",
                        "media-playback-start-symbolic",
                        "R",
                        new string[] {}
                    );
                case DocumentFormat.PYSCRIPT:
                    return new FormatProfile (
                        DocumentFormat.PYSCRIPT,
                        false, false, false, false, false, false, false, false, false, true, true, true,
                        "python", "# ", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.SCRIPT_RUNNER,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.SCRIPT_RUN,
                        "Run Python",
                        "Execute Python Script in Console",
                        "media-playback-start-symbolic",
                        "PY",
                        new string[] {}
                    );
                case DocumentFormat.CSS:
                    return new FormatProfile (
                        DocumentFormat.CSS,
                        false, false, false, false, false, false, false, false, false, false, false, false,
                        "none", "", "/* ", " */",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.NONE,
                        "", "", "",
                        "CSS",
                        new string[] {}
                    );
                case DocumentFormat.BIB:
                case DocumentFormat.BIBLIOGRAPHY:
                    return new FormatProfile (
                        fmt,
                        false, false, false, false, false, false, false, false, false, false, false, false,
                        "none", "% ", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.NONE,
                        "", "", "",
                        "BIB",
                        new string[] {}
                    );
                case DocumentFormat.CSV:
                    return new FormatProfile (
                        DocumentFormat.CSV,
                        false, false, false, false, false, false, false, false, false, false, false, false,
                        "none", "", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.NONE,
                        "", "", "",
                        "CSV",
                        new string[] {}
                    );
                case DocumentFormat.TSV:
                    return new FormatProfile (
                        DocumentFormat.TSV,
                        false, false, false, false, false, false, false, false, false, false, false, false,
                        "none", "", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.NONE,
                        "", "", "",
                        "TSV",
                        new string[] {}
                    );
                case DocumentFormat.RTF:
                    return new FormatProfile (
                        DocumentFormat.RTF,
                        false, true, false, false, false, false, false, true, true, false, false, false,
                        "none", "", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.MARKDOWN_PROSE,
                        HeaderActionKind.MD_EXPORT,
                        "Export",
                        "Export Rich Text Document to PDF/HTML/ODT",
                        "document-save-as-symbolic",
                        "RTF",
                        new string[] { "pdf", "html", "odt", "md" }
                    );
                case DocumentFormat.TXT:
                    return new FormatProfile (
                        DocumentFormat.TXT,
                        false, false, false, false, false, false, false, false, false, false, false, false,
                        "none", "", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.NONE,
                        "", "", "",
                        "TXT",
                        new string[] {}
                    );
                case DocumentFormat.RPROJ:
                    return new FormatProfile (
                        DocumentFormat.RPROJ,
                        false, false, false, false, false, false, false, false, false, false, false, false,
                        "none", "", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.NONE,
                        "", "", "",
                        "RPROJ",
                        new string[] {}
                    );
                default:
                    return new FormatProfile (
                        DocumentFormat.BIB,
                        false, false, false, false, false, false, false, false, false, false, false, false,
                        "none", "% ", "", "",
                        CitationStyle.NONE,
                        RibbonRunMode.HIDDEN,
                        RibbonHomeMode.CODE_EDITING,
                        HeaderActionKind.NONE,
                        "", "", "",
                        "BIB",
                        new string[] {}
                    );
            }
        }

        public static FormatProfile for_filename (string filename) {
            return for_format (DocumentFormat.from_filename (filename));
        }
    }
}
