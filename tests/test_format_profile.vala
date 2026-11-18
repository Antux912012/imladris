/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;
using Imladris.Core;
using Imladris.Services;

namespace Imladris.Tests {

    private static void test_document_format_detection () {
        assert (DocumentFormat.from_filename ("paper.QMD") == DocumentFormat.QMD);
        assert (DocumentFormat.from_filename ("report.Rmd") == DocumentFormat.RMD);
        assert (DocumentFormat.from_filename ("notebook.IPYNB") == DocumentFormat.IPYNB);
        assert (DocumentFormat.from_filename ("README.MD") == DocumentFormat.MD);
        assert (DocumentFormat.from_filename ("thesis.TEX") == DocumentFormat.TEX);
        assert (DocumentFormat.from_filename ("slides.ltx") == DocumentFormat.TEX);
        assert (DocumentFormat.from_filename ("app.TS") == DocumentFormat.TS);
        assert (DocumentFormat.from_filename ("component.tsx") == DocumentFormat.TS);
        assert (DocumentFormat.from_filename ("index.HTML") == DocumentFormat.HTML);
        assert (DocumentFormat.from_filename ("analysis.R") == DocumentFormat.RSCRIPT);
        assert (DocumentFormat.from_filename ("pipeline.PY") == DocumentFormat.PYSCRIPT);
        assert (DocumentFormat.from_filename ("styles.css") == DocumentFormat.CSS);
        assert (DocumentFormat.from_filename ("refs.bib") == DocumentFormat.BIB);
        assert (DocumentFormat.from_filename ("refs.BIBLIOGRAPHY") == DocumentFormat.BIBLIOGRAPHY);
        assert (DocumentFormat.from_filename ("notes.txt") == DocumentFormat.TXT);
        assert (DocumentFormat.from_filename ("table.csv") == DocumentFormat.CSV);
        assert (DocumentFormat.from_filename ("table.tsv") == DocumentFormat.TSV);
        assert (DocumentFormat.from_filename ("project.Rproj") == DocumentFormat.RPROJ);

        assert (DocumentFormat.TEX.to_syntax_lang () == "latex");
        assert (DocumentFormat.TS.to_syntax_lang () == "typescript");
        assert (DocumentFormat.IPYNB.to_syntax_lang () == "quarto");
        assert (DocumentFormat.QMD.to_syntax_lang () == "quarto");
        assert (DocumentFormat.RMD.to_syntax_lang () == "rmd");
    }

    private static void test_format_profile_capabilities () {
        var qmd = FormatProfile.for_format (DocumentFormat.QMD);
        assert (qmd.supports_chunks);
        assert (qmd.supports_quarto_render);
        assert (qmd.default_rstudio_layout);
        assert (qmd.citation_style == CitationStyle.PANDOC_AT);

        var md = FormatProfile.for_format (DocumentFormat.MD);
        assert (!md.supports_chunks);
        assert (!md.default_rstudio_layout);
        assert (md.ribbon_run_mode == RibbonRunMode.HIDDEN);

        var tex = FormatProfile.for_format (DocumentFormat.TEX);
        assert (!tex.supports_chunks);
        assert (tex.supports_latex_build);
        assert (tex.line_comment_prefix == "% ");
        assert (tex.citation_style == CitationStyle.LATEX_CITE);
        assert (tex.ribbon_run_mode == RibbonRunMode.LATEX_COMPILE);

        var ts = FormatProfile.for_format (DocumentFormat.TS);
        assert (ts.supports_ts_actions);
        assert (ts.default_rstudio_layout);
        assert (ts.line_comment_prefix == "// ");
        assert (ts.citation_style == CitationStyle.NONE);
        assert (ts.ribbon_run_mode == RibbonRunMode.TYPESCRIPT_RUNNER);

        var html = FormatProfile.for_format (DocumentFormat.HTML);
        assert (html.supports_live_preview);
        assert (html.block_comment_open == "<!-- ");
        assert (html.ribbon_run_mode == RibbonRunMode.HIDDEN);

        assert (FormatProfile.for_filename ("notes.txt").ribbon_run_mode == RibbonRunMode.HIDDEN);
        assert (FormatProfile.for_filename ("project.Rproj").line_comment_prefix == "");
    }

    private static void test_workspace_per_doc_isolation () {
        var wsm = WorkspaceStateManager.get_default ();
        assert (wsm.get_layout_for_doc ("doc-md", "notes.md") == LayoutMode.APOSTROPHE);
        assert (wsm.get_layout_for_doc ("doc-ts", "module.ts") == LayoutMode.RSTUDIO);
        assert (wsm.get_layout_for_doc ("doc-tex", "paper.tex") == LayoutMode.APOSTROPHE);

        wsm.set_layout_for_doc ("doc-md", LayoutMode.RSTUDIO, true);
        assert (wsm.get_layout_for_doc ("doc-md", "notes.md") == LayoutMode.RSTUDIO);
        assert (wsm.get_layout_for_doc ("doc-tex", "paper.tex") == LayoutMode.APOSTROPHE);

        wsm.clear_doc_state ("doc-md");
        assert (wsm.get_layout_for_doc ("doc-md", "notes.md") == LayoutMode.APOSTROPHE);
    }

    public static int main (string[] args) {
        Test.init (ref args);
        Test.add_func ("/format/detection", test_document_format_detection);
        Test.add_func ("/format/profile_capabilities", test_format_profile_capabilities);
        Test.add_func ("/format/workspace_per_doc_isolation", test_workspace_per_doc_isolation);
        return Test.run ();
    }
}
