// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Imladris.Core;
using Imladris.Editor;
using Imladris.Runners;
using Imladris.Services;
using Imladris.UI;

namespace Imladris.Tests {

    private static string _test_tmp_root;

    private static void setup_isolated_xdg () {
        try {
            _test_tmp_root = GLib.DirUtils.make_tmp ("imladris-exec-sec-test-XXXXXX");
            GLib.Environment.set_variable ("XDG_CONFIG_HOME", GLib.Path.build_filename (_test_tmp_root, "config"), true);
            GLib.Environment.set_variable ("XDG_DATA_HOME", GLib.Path.build_filename (_test_tmp_root, "data"), true);
            GLib.Environment.set_variable ("XDG_CACHE_HOME", GLib.Path.build_filename (_test_tmp_root, "cache"), true);
            GLib.Environment.set_variable ("GSETTINGS_BACKEND", "memory", true);
        } catch (GLib.Error e) {
            error ("Failed to create isolated temp dir: %s", e.message);
        }
    }

    private static void test_latex_log_diagnostics () {
        string sample_log = """
This is pdfTeX, Version 3.141592653
! Undefined control sequence.
l.42 \badmacro
              {arg}
! LaTeX Error: File `nonexistent.sty' not found.
l.3 \usepackage{nonexistent}
""";
        var diags = new Gee.ArrayList<LatexDiagnostic> ();
        LatexBuildRunner.parse_diagnostics_from_log (sample_log, "/tmp/paper.tex", diags);
        assert (diags.size >= 2);
        assert (diags.get (0).line == 42);
        assert (diags.get (0).message.contains ("Undefined control sequence"));
        assert (diags.get (1).line == 3);
        assert (diags.get (1).message.contains ("nonexistent.sty"));
    }

    private static void test_typescript_diagnostics_and_ansi () {
        string ansi_raw = "\x1b[31merror TS2322:\x1b[0m Type 'string' is not assignable to type 'number'.";
        string clean = TypeScriptRunner.strip_ansi (ansi_raw);
        assert (!clean.contains ("\x1b["));
        assert (clean.contains ("error TS2322:"));

        string tsc_out = "src/main.ts(12,5): error TS2322: Type 'string' is not assignable to type 'number'.\n";
        var diags = new Gee.ArrayList<TsDiagnostic> ();
        TypeScriptRunner.parse_tsc_diagnostics (tsc_out, diags);
        assert (diags.size == 1);
        assert (diags.get (0).file == "src/main.ts");
        assert (diags.get (0).line == 12);
        assert (diags.get (0).column == 5);
        assert (diags.get (0).code == "TS2322");
    }

    private static void test_intellisense_ts_latex_and_python_backticks () {
        string ts_code = "interface Sample { id: number; }\nfunction computeMean(vals: number[]): number { return 0; }\ncomp";
        var ts_ctx = CodeIntelliSenseEngine.detect_context (ts_code, 2, "comp", "ts");
        assert (ts_ctx == IntelliSenseContext.TYPESCRIPT_CODE);

        var ts_items = CodeIntelliSenseEngine.query_completions (ts_code, 2, "comp", "ts");
        bool found_fn = false;
        foreach (var it in ts_items) {
            if (it.label == "computeMean") found_fn = true;
        }
        assert (found_fn);

        string tex_code = "\\documentclass{article}\n\\begin{document}\n\\sec";
        var tex_ctx = CodeIntelliSenseEngine.detect_context (tex_code, 2, "\\sec", "tex");
        assert (tex_ctx == IntelliSenseContext.LATEX_MATH_CHEM);
        var tex_items = CodeIntelliSenseEngine.query_completions (tex_code, 2, "\\sec", "tex");
        bool found_sec = false;
        foreach (var it in tex_items) {
            if (it.label == "\\section") found_sec = true;
        }
        assert (found_sec);

        // Pure Python script containing triple backticks inside a docstring must still scan symbols
        string py_script = "doc = \"\"\"\n```python\nexample\n```\n\"\"\"\ndef analyze_cohort(df):\n    return df\n";
        Gee.HashMap<string, Gee.ArrayList<string>> cols;
        var syms = CodeIntelliSenseEngine.scan_buffer_symbols (py_script, IntelliSenseContext.PYTHON_CODE, out cols, "pyscript");
        bool found_py_fn = false;
        foreach (var s in syms) {
            if (s.label == "analyze_cohort") found_py_fn = true;
        }
        assert (found_py_fn);

        // Quarto #| options must not double-prefix #|
        string qmd = "```{r}\n#| ec\n```";
        var q_items = CodeIntelliSenseEngine.query_completions (qmd, 1, "#| ec", "qmd");
        assert (q_items.size > 0);
        assert (!q_items.get (0).insert_text.has_prefix ("#|"));
    }

    private static void test_intellisense_vscode_rstudio_writing_parity () {
        // 1. Context-aware token extraction must NOT swallow '$' before '\alpha' or '-' before R identifiers
        assert (CodeIntelliSenseEngine.extract_active_token_for_context ("Let $\\alp", IntelliSenseContext.LATEX_MATH_CHEM) == "\\alp");
        assert (CodeIntelliSenseEngine.extract_active_token_for_context ("x-mea", IntelliSenseContext.R_CODE) == "mea");
        assert (CodeIntelliSenseEngine.extract_active_token_for_context ("mtcars$mp", IntelliSenseContext.R_CODE) == "mtcars$mp");
        assert (CodeIntelliSenseEngine.extract_active_token_for_context ("hello <div", IntelliSenseContext.HTML_CODE) == "<div");
        assert (CodeIntelliSenseEngine.extract_active_token_for_context ("See @fig-vo", IntelliSenseContext.MARKDOWN_PROSE) == "@fig-vo");

        // 2. Markdown prose writing snippets and Quarto cross-references (@fig-*, @sec-*)
        string qmd_doc = "# Methods {#sec-methods}\n\nSee @fig-\n\n:::call\n\n```{r}\n#| label: fig-volcano\nlibrary(ggp\nmy_model = lm(mpg ~ wt, data = mtcars)\nggplot(mtcars, ma\n```\n\n```{python}\nimport pan\ndf_bio = pd.read_csv('a.csv')\nx = df_bio['gene_id']\ndf_bio.hea\n```\n\n```{bash}\nquar\n```\n";

        var xref_items = CodeIntelliSenseEngine.query_completions (qmd_doc, 2, "See @fig-", "qmd");
        bool found_fig_ref = false;
        foreach (var it in xref_items) {
            if (it.label == "@fig-volcano") found_fig_ref = true;
        }
        assert (found_fig_ref);

        var sec_items = CodeIntelliSenseEngine.query_completions (qmd_doc, 2, "See @sec-", "qmd");
        bool found_sec_ref = false;
        foreach (var it in sec_items) {
            if (it.label == "@sec-methods") found_sec_ref = true;
        }
        assert (found_sec_ref);

        var callout_items = CodeIntelliSenseEngine.query_completions (qmd_doc, 4, ":::call", "qmd");
        bool found_callout = false;
        foreach (var it in callout_items) {
            if (it.label == ":::callout-note") found_callout = true;
        }
        assert (found_callout);

        // Ctrl+Space (manual_trigger = true) on empty line in Markdown prose returns writing snippets
        var md_manual = CodeIntelliSenseEngine.query_completions (qmd_doc, 3, "", "qmd", true);
        assert (md_manual.size > 5);

        // 3. HTML tag completion + smart closing tag completion
        string html_doc = "<div>\n  <p>Hello\n  </";
        assert (CodeIntelliSenseEngine.detect_context (html_doc, 2, "  </", "html") == IntelliSenseContext.HTML_CODE);
        var close_items = CodeIntelliSenseEngine.query_completions (html_doc, 2, "  </", "html");
        assert (close_items.size > 0);
        assert (close_items.get (0).label == "</p>");

        var inline_html = CodeIntelliSenseEngine.query_completions ("Text <tab", 0, "Text <tab", "markdown");
        bool found_table_tag = false;
        foreach (var it in inline_html) {
            if (it.label == "<table") found_table_tag = true;
        }
        assert (found_table_tag);

        // 4. RStudio parity: library() package completion, named function args, '=' assignment, Ctrl+Space
        var r_pkg_items = CodeIntelliSenseEngine.query_completions (qmd_doc, 8, "library(ggp", "qmd");
        bool found_ggplot2_pkg = false;
        foreach (var it in r_pkg_items) {
            if (it.label == "ggplot2") found_ggplot2_pkg = true;
        }
        assert (found_ggplot2_pkg);

        var r_arg_items = CodeIntelliSenseEngine.query_completions (qmd_doc, 10, "ggplot(mtcars, ma", "qmd");
        bool found_mapping_arg = false;
        foreach (var it in r_arg_items) {
            if (it.label == "mapping =") found_mapping_arg = true;
        }
        assert (found_mapping_arg);

        var r_eq_var = CodeIntelliSenseEngine.query_completions (qmd_doc, 10, "my_mo", "qmd");
        bool found_my_model = false;
        foreach (var it in r_eq_var) {
            if (it.label == "my_model") found_my_model = true;
        }
        assert (found_my_model);

        var r_manual = CodeIntelliSenseEngine.query_completions (qmd_doc, 10, "", "qmd", true);
        assert (r_manual.size > 10);

        // 5. VS Code parity in Python: import modules, DataFrame methods & discovered columns, Ctrl+Space
        var py_imp = CodeIntelliSenseEngine.query_completions (qmd_doc, 14, "import pan", "qmd");
        bool found_pandas_mod = false;
        foreach (var it in py_imp) {
            if (it.label == "pandas") found_pandas_mod = true;
        }
        assert (found_pandas_mod);

        var py_df_m = CodeIntelliSenseEngine.query_completions (qmd_doc, 17, "df_bio.hea", "qmd");
        bool found_df_head = false;
        foreach (var it in py_df_m) {
            if (it.label == "df_bio.head") found_df_head = true;
        }
        assert (found_df_head);

        var py_df_col = CodeIntelliSenseEngine.query_completions (qmd_doc, 17, "df_bio.ge", "qmd");
        bool found_gene_id = false;
        foreach (var it in py_df_col) {
            if (it.label == "df_bio.gene_id") found_gene_id = true;
        }
        assert (found_gene_id);

        // 6. Bash chunk completions
        var bash_items = CodeIntelliSenseEngine.query_completions (qmd_doc, 21, "quar", "qmd");
        bool found_quarto_cmd = false;
        foreach (var it in bash_items) {
            if (it.label == "quarto") found_quarto_cmd = true;
        }
        assert (found_quarto_cmd);
    }

    private static void test_recovery_sanitized_id_and_purge () {
        var rec_svc = RecoveryService.get_default ();
        string evil_id = "../../etc/passwd";
        var loop = new MainLoop ();
        rec_svc.snapshot_async.begin (evil_id, "/tmp/demo.qmd", "qmd", "# Hello\nWorld", 1, 3, true, (o, r) => {
            rec_svc.snapshot_async.end (r);
            loop.quit ();
        });
        loop.run ();

        var recs = rec_svc.check_recoverable_sessions ();
        bool found = false;
        foreach (var r in recs) {
            if (r.doc_id == evil_id) {
                found = true;
                assert (r.is_dirty == true);
                assert (r.cursor_line == 1);
                assert (r.cursor_offset == 3);
            }
        }
        assert (found);

        rec_svc.purge_document_cache (evil_id);
        var after = rec_svc.check_recoverable_sessions ();
        foreach (var r in after) {
            assert (r.doc_id != evil_id);
        }
    }

    private static void test_mallorn_rejects_symlinks () {
        string tar_bin = GLib.Environment.find_program_in_path ("tar") ?? "";
        if (tar_bin == "") return;

        string work = GLib.Path.build_filename (_test_tmp_root, "mallorn_sym");
        GLib.DirUtils.create_with_parents (work, 0755);
        string src_dir = GLib.Path.build_filename (work, "src");
        GLib.DirUtils.create_with_parents (src_dir, 0755);
        try {
            GLib.FileUtils.set_contents (GLib.Path.build_filename (src_dir, "note.md"), "ok\n");
            GLib.FileUtils.symlink ("/etc/passwd", GLib.Path.build_filename (src_dir, "leak.txt"));
            string archive = GLib.Path.build_filename (work, "evil.mallorn");
            var proc = new GLib.Subprocess.newv (
                { tar_bin, "-C", src_dir, "--zstd", "-cf", archive, "." },
                GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE
            );
            if (!proc.wait_check ()) return;

            string unpack_dir = GLib.Path.build_filename (work, "out");
            bool rejected = false;
            try {
                MallornManager.unpack_mallorn_archive (archive, unpack_dir);
            } catch (GLib.Error e) {
                rejected = true;
            }
            assert (rejected);
        } catch (GLib.Error e) {
            error ("Unexpected setup error: %s", e.message);
        }
    }

    private static void test_platform_venv_and_package_validation () {
        string proj = GLib.Path.build_filename (_test_tmp_root, "py_proj");
        string venv_bin = GLib.Path.build_filename (proj, ".venv", "bin");
        GLib.DirUtils.create_with_parents (venv_bin, 0755);
        string fake_pytest = GLib.Path.build_filename (venv_bin, "pytest");
        try {
            GLib.FileUtils.set_contents (fake_pytest, "#!/bin/sh\nexit 0\n");
            GLib.FileUtils.chmod (fake_pytest, 0755);
        } catch (GLib.Error e) {
            error ("Failed to create fake venv binary: %s", e.message);
        }

        string? resolved = null;
        string? env_pfx = null;
        var src = PlatformUtils.resolve_runtime ("pytest", proj, out resolved, out env_pfx);
        assert (src == RuntimeSource.PROJECT_SANDBOX);
        assert (resolved == fake_pytest);

        assert (PackagesRibbonBar.is_valid_r_package_spec ("ggplot2"));
        assert (PackagesRibbonBar.is_valid_r_package_spec ("tidyverse/dplyr"));
        assert (!PackagesRibbonBar.is_valid_r_package_spec ("foo\"); system(\"id\") #"));
        assert (!PackagesRibbonBar.is_valid_r_package_spec ("../bad"));
    }

    private static void test_export_service_error_propagation () {
        var svc = ExportService.get_default ();
        string bad_in = GLib.Path.build_filename (_test_tmp_root, "nonexistent_dir", "missing.qmd");
        string bad_out = GLib.Path.build_filename (_test_tmp_root, "out.pdf");
        var loop = new MainLoop ();
        bool ok = true;
        GLib.Test.expect_message (null, GLib.LogLevelFlags.LEVEL_WARNING, "*Export to PDF failed*");
        svc.export_document_async.begin (bad_in, bad_out, "pdf", null, (o, r) => {
            ok = svc.export_document_async.end (r);
            loop.quit ();
        });
        loop.run ();
        GLib.Test.assert_expected_messages ();
        // Must not report fake success when source does not exist and no PDF was created
        if (GLib.FileUtils.test (bad_out, GLib.FileTest.EXISTS)) {
            GLib.FileUtils.remove (bad_out);
        }
        assert (!ok);
        assert (svc.last_error_message != "");
    }

    private static void test_builtin_pdf_odt_rtf_export () {
        string report_md = """---
title: "Clinical Trial Interim Report"
author: "Imladris Test Suite"
date: "2026-11-18"
---

# Executive Summary

This report verifies **out-of-the-box** export with *inline formatting* and `inline_code()`.

> Key finding: built-in export requires no external CLI tools.

- Endpoint 1: Passed
- Endpoint 2: Passed

```python
def summarize(n):
    return n * 2
```
""";
        string src_path = GLib.Path.build_filename (_test_tmp_root, "report.qmd");
        string pdf_out = GLib.Path.build_filename (_test_tmp_root, "report.pdf");
        string odt_out = GLib.Path.build_filename (_test_tmp_root, "report.odt");
        string rtf_out = GLib.Path.build_filename (_test_tmp_root, "report.rtf");

        try {
            GLib.FileUtils.set_contents (src_path, report_md);

            // Force built-in engines directly & via ExportService
            ExportService.export_to_pdf (src_path, pdf_out, report_md);
            assert (GLib.FileUtils.test (pdf_out, GLib.FileTest.EXISTS));
            uint8[] pdf_bytes;
            GLib.FileUtils.get_data (pdf_out, out pdf_bytes);
            assert (pdf_bytes.length > 200);
            assert (pdf_bytes[0] == '%' && pdf_bytes[1] == 'P' && pdf_bytes[2] == 'D' && pdf_bytes[3] == 'F');

            ExportService.export_to_odt (src_path, odt_out, report_md);
            assert (GLib.FileUtils.test (odt_out, GLib.FileTest.EXISTS));
            uint8[] odt_bytes;
            GLib.FileUtils.get_data (odt_out, out odt_bytes);
            assert (odt_bytes.length > 200);
            assert (odt_bytes[0] == 'P' && odt_bytes[1] == 'K');

            ExportService.export_to_rtf (src_path, rtf_out, report_md);
            assert (GLib.FileUtils.test (rtf_out, GLib.FileTest.EXISTS));
            string rtf_text;
            GLib.FileUtils.get_contents (rtf_out, out rtf_text);
            assert (rtf_text.has_prefix ("{\\rtf1"));
            assert (rtf_text.contains ("Clinical Trial Interim Report"));
            assert (rtf_text.contains ("\\bullet"));
        } catch (GLib.Error e) {
            error ("Built-in export failed: %s", e.message);
        }
    }

    private static void test_rtf_and_all_formats_html_pdf () {
        string sample_rtf = """{\rtf1\ansi\ansicpg1252\deff0
{\fonttbl{\f0\fswiss Liberation Sans;}}
\pard {\b Bold Heading}\par
\pard Plain paragraph from RTF.\par
}""";
        string rtf_src = GLib.Path.build_filename (_test_tmp_root, "notes.rtf");
        string rtf_html = GLib.Path.build_filename (_test_tmp_root, "notes_rtf.html");
        string rtf_pdf = GLib.Path.build_filename (_test_tmp_root, "notes_rtf.pdf");
        string rtf_copy = GLib.Path.build_filename (_test_tmp_root, "notes_copy.rtf");

        string rmd_src = GLib.Path.build_filename (_test_tmp_root, "analysis.Rmd");
        string rmd_html = GLib.Path.build_filename (_test_tmp_root, "analysis_rmd.html");
        string rmd_pdf = GLib.Path.build_filename (_test_tmp_root, "analysis_rmd.pdf");

        try {
            GLib.FileUtils.set_contents (rtf_src, sample_rtf);
            ExportService.export_to_html (rtf_src, rtf_html, sample_rtf);
            assert (GLib.FileUtils.test (rtf_html, GLib.FileTest.EXISTS));
            string html_out;
            GLib.FileUtils.get_contents (rtf_html, out html_out);
            assert (html_out.contains ("Bold Heading"));
            assert (html_out.contains ("Plain paragraph from RTF."));

            ExportService.export_to_pdf (rtf_src, rtf_pdf, sample_rtf);
            assert (GLib.FileUtils.test (rtf_pdf, GLib.FileTest.EXISTS));
            uint8[] rtf_pdf_bytes;
            GLib.FileUtils.get_data (rtf_pdf, out rtf_pdf_bytes);
            assert (rtf_pdf_bytes.length > 200);
            assert (rtf_pdf_bytes[0] == '%' && rtf_pdf_bytes[1] == 'P' && rtf_pdf_bytes[2] == 'D' && rtf_pdf_bytes[3] == 'F');

            ExportService.export_to_rtf (rtf_src, rtf_copy, sample_rtf);
            string rtf_copy_text;
            GLib.FileUtils.get_contents (rtf_copy, out rtf_copy_text);
            assert (rtf_copy_text.contains ("Bold Heading"));

            string rmd_content = "# R Markdown Report\n\nSummary text.\n";
            GLib.FileUtils.set_contents (rmd_src, rmd_content);
            ExportService.export_to_html (rmd_src, rmd_html, rmd_content);
            assert (GLib.FileUtils.test (rmd_html, GLib.FileTest.EXISTS));
            ExportService.export_to_pdf (rmd_src, rmd_pdf, rmd_content);
            assert (GLib.FileUtils.test (rmd_pdf, GLib.FileTest.EXISTS));
        } catch (GLib.Error e) {
            error ("RTF/Rmd export failed: %s", e.message);
        }
    }

    private static void test_mcp_schema_headless_and_security () {
        // 1. tools/list schema includes headless file_path, compile_latex, and get_environment_summary
        string list_req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}";
        string list_resp = McpServer.handle_json_rpc (list_req, null);
        assert (list_resp.contains ("\"compile_latex\""));
        assert (list_resp.contains ("\"get_environment_summary\""));
        assert (list_resp.contains ("\"file_path\""));

        // 2. D-Bus fallback returns actionable error when no GUI window is active (or live tabs JSON if GUI is open)
        string tabs_req = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_open_tabs\"}}";
        string tabs_resp = McpServer.handle_json_rpc (tabs_req, null);
        assert (tabs_resp.contains ("No active Imladris window") || tabs_resp.contains ("\\\"tabs\\\""));

        // 3. Headless path traversal, unset workspace rejection & sensitive directory/rc rejection
        GLib.Environment.unset_variable ("IMLADRIS_MCP_WORKSPACE");
        string? unset_err = null;
        assert (McpServer.validate_headless_path ("/tmp/test.md", false, out unset_err) == null);
        assert (unset_err != null && unset_err.contains ("IMLADRIS_MCP_WORKSPACE"));

        GLib.Environment.set_variable ("IMLADRIS_MCP_WORKSPACE", _test_tmp_root, true);
        string? path_err = null;
        assert (McpServer.validate_headless_path ("/etc/passwd", true, out path_err) == null);
        assert (path_err != null && path_err.contains ("Security Error"));

        string outside_dir = GLib.Path.build_filename (GLib.Environment.get_home_dir (), ".ssh", "id_rsa");
        assert (McpServer.validate_headless_path (outside_dir, false, out path_err) == null);
        string netrc_file = GLib.Path.build_filename (_test_tmp_root, ".netrc");
        assert (McpServer.validate_headless_path (netrc_file, false, out path_err) == null);
        string bashrc_file = GLib.Path.build_filename (_test_tmp_root, ".bashrc");
        assert (McpServer.validate_headless_path (bashrc_file, false, out path_err) == null);

        // 4. Headless insert_text + get_active_document on workspace file
        string ws_file = GLib.Path.build_filename (_test_tmp_root, "mcp_notes.md");
        string ins_req = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"insert_text\",\"arguments\":{\"file_path\":\"" + ws_file.replace ("\\", "\\\\") + "\",\"text\":\"Hello MCP\\n\"}}}";
        string ins_resp = McpServer.handle_json_rpc (ins_req, null);
        assert (ins_resp.contains ("Text inserted into"));

        string read_req = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"get_active_document\",\"arguments\":{\"file_path\":\"" + ws_file.replace ("\\", "\\\\") + "\"}}}";
        string read_resp = McpServer.handle_json_rpc (read_req, null);
        assert (read_resp.contains ("Hello MCP"));

        // 5. IMLADRIS_MCP_READONLY=1 blocks mutating tools (including render_document & compile_latex) and writes audit log
        GLib.Environment.set_variable ("IMLADRIS_MCP_READONLY", "1", true);
        string ro_resp = McpServer.handle_json_rpc (ins_req, null);
        assert (ro_resp.contains ("read-only mode"));
        string render_req = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"render_document\",\"arguments\":{\"file_path\":\"" + ws_file.replace ("\\", "\\\\") + "\",\"format\":\"html\"}}}";
        string ro_render_resp = McpServer.handle_json_rpc (render_req, null);
        assert (ro_render_resp.contains ("read-only mode"));
        string tex_req = "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"compile_latex\",\"arguments\":{\"file_path\":\"" + ws_file.replace ("\\", "\\\\") + "\"}}}";
        string ro_tex_resp = McpServer.handle_json_rpc (tex_req, null);
        assert (ro_tex_resp.contains ("read-only mode"));
        string audit_file = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "imladris", "mcp-audit.jsonl");
        assert (GLib.FileUtils.test (audit_file, GLib.FileTest.EXISTS));
        GLib.Environment.unset_variable ("IMLADRIS_MCP_READONLY");
        GLib.Environment.unset_variable ("IMLADRIS_MCP_WORKSPACE");
    }

    private static void test_quarto_env_and_toolchain_profiles () {
        // Verify ToolchainProfile package lists & external conda env discovery
        var qf_pkgs = ToolchainProfile.QUANT_FINANCE.get_packages ();
        bool has_duckdb = false;
        foreach (string p in qf_pkgs) {
            if (p == "duckdb") has_duckdb = true;
        }
        assert (has_duckdb);

        // Create a mock managed conda prefix with deno_dom.so and verify QUARTO_DENO_DOM override
        string mock_env = GLib.Path.build_filename (_test_tmp_root, "mock-base-ds");
        string mock_lib = GLib.Path.build_filename (mock_env, "lib");
        string mock_bin = GLib.Path.build_filename (mock_env, "bin");
        GLib.DirUtils.create_with_parents (mock_lib, 0755);
        GLib.DirUtils.create_with_parents (mock_bin, 0755);
        try {
            GLib.FileUtils.set_contents (GLib.Path.build_filename (mock_lib, "deno_dom.so"), "");
            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE);
            PlatformUtils.configure_managed_env (launcher, mock_env);
            var proc = launcher.spawnv ({ "/usr/bin/env" });
            string env_out = "";
            string env_err = "";
            proc.communicate_utf8 (null, null, out env_out, out env_err);
            assert (env_out.contains ("QUARTO_DENO_DOM=" + GLib.Path.build_filename (mock_lib, "deno_dom.so")));
            string readiness = ToolchainManager.get_default ().verify_offline_readiness ();
            assert (readiness.contains ("tectonic_cache:"));
        } catch (GLib.Error e) {
            error ("Toolchain env test failed: %s", e.message);
        }
    }

    public static int main (string[] args) {
        setup_isolated_xdg ();
        Test.init (ref args);

        Test.add_func ("/runners/latex_log_diagnostics", test_latex_log_diagnostics);
        Test.add_func ("/runners/typescript_diagnostics_and_ansi", test_typescript_diagnostics_and_ansi);
        Test.add_func ("/intellisense/ts_latex_and_python_backticks", test_intellisense_ts_latex_and_python_backticks);
        Test.add_func ("/intellisense/vscode_rstudio_writing_parity", test_intellisense_vscode_rstudio_writing_parity);
        Test.add_func ("/recovery/sanitized_id_and_purge", test_recovery_sanitized_id_and_purge);
        Test.add_func ("/security/mallorn_rejects_symlinks", test_mallorn_rejects_symlinks);
        Test.add_func ("/security/platform_venv_and_package_validation", test_platform_venv_and_package_validation);
        Test.add_func ("/export/error_propagation", test_export_service_error_propagation);
        Test.add_func ("/export/builtin_pdf_odt_rtf", test_builtin_pdf_odt_rtf_export);
        Test.add_func ("/export/rtf_and_all_formats_html_pdf", test_rtf_and_all_formats_html_pdf);
        Test.add_func ("/mcp/schema_headless_and_security", test_mcp_schema_headless_and_security);
        Test.add_func ("/toolchain/quarto_env_and_profiles", test_quarto_env_and_toolchain_profiles);

        int rc = Test.run ();
        if (_test_tmp_root != "") {
            PlatformUtils.delete_directory_recursive (GLib.File.new_for_path (_test_tmp_root));
        }
        return rc;
    }
}
