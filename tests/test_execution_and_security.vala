// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

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

    public static int main (string[] args) {
        setup_isolated_xdg ();
        Test.init (ref args);

        Test.add_func ("/runners/latex_log_diagnostics", test_latex_log_diagnostics);
        Test.add_func ("/runners/typescript_diagnostics_and_ansi", test_typescript_diagnostics_and_ansi);
        Test.add_func ("/intellisense/ts_latex_and_python_backticks", test_intellisense_ts_latex_and_python_backticks);
        Test.add_func ("/recovery/sanitized_id_and_purge", test_recovery_sanitized_id_and_purge);
        Test.add_func ("/security/mallorn_rejects_symlinks", test_mallorn_rejects_symlinks);
        Test.add_func ("/security/platform_venv_and_package_validation", test_platform_venv_and_package_validation);
        Test.add_func ("/export/error_propagation", test_export_service_error_propagation);
        Test.add_func ("/export/builtin_pdf_odt_rtf", test_builtin_pdf_odt_rtf_export);

        int rc = Test.run ();
        if (_test_tmp_root != "") {
            PlatformUtils.delete_directory_recursive (GLib.File.new_for_path (_test_tmp_root));
        }
        return rc;
    }
}
