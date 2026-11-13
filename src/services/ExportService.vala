// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Services {

    public class ExportService : GLib.Object {

        private static bool run_tool_process (string tool_name, string[] sub_args, string working_dir) {
            string unused_log;
            return run_tool_process_with_output (tool_name, sub_args, working_dir, out unused_log);
        }

        private static bool run_tool_process_with_output (string tool_name, string[] sub_args, string working_dir, out string output_log) {
            output_log = "";
            string? resolved_path = null;
            string? env_prefix = null;
            var source = Core.PlatformUtils.resolve_runtime (tool_name, working_dir, out resolved_path, out env_prefix);
            if (source == Core.RuntimeSource.MISSING) {
                return false;
            }

            try {
                var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);
                Core.PlatformUtils.inject_galaxy_credentials (launcher);
                launcher.set_cwd (working_dir);

                string[] full_raw = new string[1 + sub_args.length];
                full_raw[0] = (resolved_path != null) ? resolved_path : tool_name;
                for (int i = 0; i < sub_args.length; i++) full_raw[i + 1] = sub_args[i];

                string[] argv;
                if (source == Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                    string[] host_raw = new string[1 + sub_args.length];
                    host_raw[0] = tool_name;
                    for (int i = 0; i < sub_args.length; i++) host_raw[i + 1] = sub_args[i];
                    argv = Core.PlatformUtils.build_host_command (host_raw, working_dir);
                } else if (source == Core.RuntimeSource.MANAGED_GLOBAL || source == Core.RuntimeSource.PROJECT_SANDBOX) {
                    Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                    argv = full_raw;
                } else {
                    argv = full_raw;
                }

                var proc = launcher.spawnv (argv);
                string? stdout_buf = null;
                proc.communicate_utf8 (null, null, out stdout_buf, null);
                output_log = stdout_buf ?? "";
                return proc.get_successful ();
            } catch (GLib.Error e) {
                output_log = e.message;
                return false;
            }
        }

        private static string materialize_input (string input_path, string? raw_buffer_fallback, out string? temp_file) throws GLib.Error {
            temp_file = null;
            if (GLib.FileUtils.test (input_path, GLib.FileTest.EXISTS) || raw_buffer_fallback == null) {
                return input_path;
            }
            string base_name = GLib.Path.get_basename (input_path);
            int dot_idx = base_name.last_index_of_char ('.');
            string ext = (dot_idx >= 0) ? base_name.substring (dot_idx) : ".md";
            temp_file = GLib.Path.build_filename (
                Core.PlatformUtils.get_shared_cache_dir ("tmp"),
                @"imladris_export_$(GLib.Random.next_int ())$(ext)"
            );
            string payload = raw_buffer_fallback;
            if (ext.down () == ".ipynb") {
                payload = Adapters.DocumentAdapter.save_from_editor_buffer (raw_buffer_fallback, DocumentFormat.IPYNB);
            }
            GLib.FileUtils.set_contents (temp_file, payload);
            return temp_file;
        }

        private static bool move_quarto_output_if_needed (string src_dir, string out_file, string output_path) {
            if (GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                return true;
            }
            string candidate = GLib.Path.build_filename (src_dir, out_file);
            if (GLib.FileUtils.test (candidate, GLib.FileTest.EXISTS)) {
                try {
                    var src_f = GLib.File.new_for_path (candidate);
                    var dst_f = GLib.File.new_for_path (output_path);
                    src_f.move (dst_f, GLib.FileCopyFlags.OVERWRITE, null, null);
                    return true;
                } catch (GLib.Error e) {
                    GLib.warning ("Failed to move Quarto output from %s to %s: %s", candidate, output_path, e.message);
                }
            }
            return false;
        }

        /**
         * Exports a source document (.md, .Rmd, .Qmd, .ipynb) to OpenDocument Text (.odt).
         * Automatically selects quarto, Rscript (rmarkdown), or pandoc based on extension,
         * falling back to the built-in OASIS OpenDocument Text ZIP packager if CLI tools
         * are unavailable on the host.
         */
        public static void export_to_odt (string input_path, string output_path, string? raw_buffer_fallback = null) throws GLib.Error {
            var fmt = DocumentFormat.from_filename (input_path);
            bool cli_succeeded = false;

            string out_file = GLib.Path.get_basename (output_path);
            ensure_parent_dir (output_path);

            string? temp_src = null;
            string actual_input = materialize_input (input_path, raw_buffer_fallback, out temp_src);
            string src_dir = GLib.Path.get_dirname (actual_input);
            string pandoc_from = (fmt == DocumentFormat.IPYNB) ? "ipynb" : ((fmt == DocumentFormat.HTML) ? "html" : "markdown");

            try {
                if ((fmt == DocumentFormat.QMD || fmt == DocumentFormat.IPYNB) &&
                    Core.PlatformUtils.is_program_available ("quarto", src_dir)) {
                    cli_succeeded = run_tool_process ("quarto", { "render", actual_input, "--to", "odt", "--output", out_file }, src_dir)
                                    && move_quarto_output_if_needed (src_dir, out_file, output_path);
                } else if (fmt == DocumentFormat.RMD &&
                           Core.PlatformUtils.is_program_available ("Rscript", src_dir)) {
                    string r_expr = "if (requireNamespace('rmarkdown', quietly=TRUE)) rmarkdown::render('%s', output_format = 'odt_document', output_file = '%s', quiet = TRUE) else stop('no rmarkdown')".printf (
                        actual_input.replace ("'", "\\'"),
                        output_path.replace ("'", "\\'")
                    );
                    cli_succeeded = run_tool_process ("Rscript", { "-e", r_expr }, src_dir);
                }

                if (!cli_succeeded && Core.PlatformUtils.is_program_available ("pandoc", src_dir)) {
                    cli_succeeded = run_tool_process ("pandoc", { actual_input, "-f", pandoc_from, "-t", "odt", "-o", output_path, "--standalone" }, src_dir);
                }
            } finally {
                if (temp_src != null && GLib.FileUtils.test (temp_src, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (temp_src);
                }
            }

            if (!cli_succeeded || !GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                string source_text = read_source_or_fallback (input_path, raw_buffer_fallback);
                build_oasis_odt_container (source_text, output_path);
            }
        }

        /**
         * Exports a source document (.md, .Rmd, .Qmd, .ipynb) to OpenDocument Presentation (.odp).
         * Primary bridge: Quarto/Pandoc -> intermediate .pptx -> LibreOffice headless (--convert-to odp).
         * Fallback: Native OASIS application/vnd.oasis.opendocument.presentation ZIP container builder.
         */
        public static void export_to_odp (string input_path, string output_path, string? raw_buffer_fallback = null) throws GLib.Error {
            var fmt = DocumentFormat.from_filename (input_path);
            bool bridge_succeeded = false;

            string out_dir = GLib.Path.get_dirname (output_path);
            ensure_parent_dir (output_path);

            string? temp_src = null;
            string actual_input = materialize_input (input_path, raw_buffer_fallback, out temp_src);
            string src_dir = GLib.Path.get_dirname (actual_input);
            string pandoc_from = (fmt == DocumentFormat.IPYNB) ? "ipynb" : ((fmt == DocumentFormat.HTML) ? "html" : "markdown");

            try {
                string? soffice_bin = Core.PlatformUtils.find_program ("soffice", src_dir)
                    ?? Core.PlatformUtils.find_program ("libreoffice", src_dir);

                if (soffice_bin != null) {
                    string tmp_pptx = GLib.Path.build_filename (
                        Core.PlatformUtils.get_shared_cache_dir ("tmp"),
                        @"imladris_slides_$(GLib.Random.next_int ()).pptx"
                    );
                    bool pptx_ready = false;

                    if ((fmt == DocumentFormat.QMD || fmt == DocumentFormat.IPYNB) &&
                        Core.PlatformUtils.is_program_available ("quarto", src_dir)) {
                        string tmp_pptx_name = GLib.Path.get_basename (tmp_pptx);
                        pptx_ready = run_tool_process ("quarto", { "render", actual_input, "--to", "pptx", "--output", tmp_pptx_name }, src_dir)
                                     && move_quarto_output_if_needed (src_dir, tmp_pptx_name, tmp_pptx);
                    }

                    if (!pptx_ready && Core.PlatformUtils.is_program_available ("pandoc", src_dir)) {
                        pptx_ready = run_tool_process ("pandoc", { actual_input, "-f", pandoc_from, "-t", "pptx", "-o", tmp_pptx, "--standalone" }, src_dir)
                                     && GLib.FileUtils.test (tmp_pptx, GLib.FileTest.EXISTS);
                    }

                    if (pptx_ready) {
                        bridge_succeeded = convert_with_libreoffice (soffice_bin, tmp_pptx, "odp", out_dir, output_path);
                    }

                    if (GLib.FileUtils.test (tmp_pptx, GLib.FileTest.EXISTS)) {
                        GLib.FileUtils.remove (tmp_pptx);
                    }
                }
            } finally {
                if (temp_src != null && GLib.FileUtils.test (temp_src, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (temp_src);
                }
            }

            if (!bridge_succeeded || !GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                string source_text = read_source_or_fallback (input_path, raw_buffer_fallback);
                build_oasis_odp_container (source_text, output_path);
            }
        }

        /**
         * Exports a document to standalone HTML using Pandoc (or Quarto/RMarkdown for notebooks),
         * with fallback to the high-fidelity internal DocumentAdapter HTML generator.
         */
        public static void export_to_html (string input_path, string output_path, string? raw_buffer_fallback = null) throws GLib.Error {
            var fmt = DocumentFormat.from_filename (input_path);
            bool cli_succeeded = false;

            string out_file = GLib.Path.get_basename (output_path);
            ensure_parent_dir (output_path);

            if (fmt == DocumentFormat.HTML) {
                string source_html = raw_buffer_fallback ?? "";
                if (source_html == "" && GLib.FileUtils.test (input_path, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.get_contents (input_path, out source_html);
                }
                string rendered = Adapters.DocumentAdapter.render_html_with_latex (source_html);
                GLib.FileUtils.set_contents (output_path, rendered);
                return;
            }

            string? temp_src = null;
            string actual_input = materialize_input (input_path, raw_buffer_fallback, out temp_src);
            string src_dir = GLib.Path.get_dirname (actual_input);
            string pandoc_from = (fmt == DocumentFormat.IPYNB) ? "ipynb" : ((fmt == DocumentFormat.HTML) ? "html" : "markdown");

            try {
                if ((fmt == DocumentFormat.QMD || fmt == DocumentFormat.IPYNB) &&
                    Core.PlatformUtils.is_program_available ("quarto", src_dir)) {
                    cli_succeeded = run_tool_process ("quarto", { "render", actual_input, "--to", "html", "--output", out_file }, src_dir)
                                    && move_quarto_output_if_needed (src_dir, out_file, output_path);
                } else if (fmt == DocumentFormat.RMD &&
                           Core.PlatformUtils.is_program_available ("Rscript", src_dir)) {
                    string r_expr = "if (requireNamespace('rmarkdown', quietly=TRUE)) rmarkdown::render('%s', output_format = 'html_document', output_file = '%s', quiet = TRUE) else stop('no rmarkdown')".printf (
                        actual_input.replace ("'", "\\'"),
                        output_path.replace ("'", "\\'")
                    );
                    cli_succeeded = run_tool_process ("Rscript", { "-e", r_expr }, src_dir);
                }

                if (!cli_succeeded && Core.PlatformUtils.is_program_available ("pandoc", src_dir)) {
                    cli_succeeded = run_tool_process ("pandoc", { actual_input, "-f", pandoc_from, "-t", "html5", "--standalone", "--embed-resources", "-o", output_path }, src_dir);
                    if (!cli_succeeded) {
                        cli_succeeded = run_tool_process ("pandoc", { actual_input, "-f", pandoc_from, "-t", "html5", "--standalone", "-o", output_path }, src_dir);
                    }
                }
            } finally {
                if (temp_src != null && GLib.FileUtils.test (temp_src, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (temp_src);
                }
            }

            if (!cli_succeeded || !GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                string source_text = read_source_or_fallback (input_path, raw_buffer_fallback);
                string body_html = Adapters.DocumentAdapter.render_html (source_text, fmt);
                string doc_title = GLib.Path.get_basename (input_path);
                string html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s</title>
  <style>
    body {
      font-family: 'Inter', system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      line-height: 1.6;
      color: #1e293b;
      background: #ffffff;
      max-width: 860px;
      margin: 0 auto;
      padding: 40px 24px;
    }
    h1, h2, h3, h4 { color: #0f172a; margin-top: 1.5em; margin-bottom: 0.5em; font-weight: 700; }
    h1 { font-size: 2.25rem; border-bottom: 1px solid #e2e8f0; padding-bottom: 0.3em; }
    h2 { font-size: 1.75rem; border-bottom: 1px solid #f1f5f9; padding-bottom: 0.2em; }
    p, li { font-size: 1.05rem; }
    pre {
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 16px;
      overflow-x: auto;
      font-family: 'JetBrains Mono', 'Fira Code', monospace;
      font-size: 0.92rem;
    }
    code { font-family: monospace; background: #f1f5f9; padding: 2px 6px; border-radius: 4px; }
    pre code { background: transparent; padding: 0; }
    .badge { display: inline-block; background: #e0f2fe; color: #0284c7; padding: 2px 8px; border-radius: 4px; font-weight: 600; font-size: 0.8rem; }
    .code-chunk-card { background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; margin: 16px 0; overflow: hidden; }
    .code-chunk-header { background: #e2e8f0; padding: 6px 12px; font-size: 12px; font-weight: 600; color: #475569; }
    blockquote { border-left: 4px solid #38bdf8; margin: 16px 0; padding-left: 16px; color: #64748b; }
    table { border-collapse: collapse; width: 100%%; margin: 20px 0; }
    th, td { border: 1px solid #cbd5e1; padding: 8px 12px; text-align: left; }
    th { background: #f1f5f9; font-weight: 600; }
    %s
  </style>
</head>
<body>
%s
</body>
</html>""".printf (doc_title, Core.MathChemEngine.get_math_chem_css (), body_html);

                GLib.FileUtils.set_contents (output_path, html);
            }
        }

        /**
         * Exports a document to PDF using Quarto/RMarkdown, Pandoc (with typst/latex/weasyprint engine),
         * or headless LibreOffice via intermediate ODT.
         */
        public static void export_to_pdf (string input_path, string output_path, string? raw_buffer_fallback = null) throws GLib.Error {
            var fmt = DocumentFormat.from_filename (input_path);
            bool cli_succeeded = false;

            string out_dir = GLib.Path.get_dirname (output_path);
            string out_file = GLib.Path.get_basename (output_path);
            ensure_parent_dir (output_path);

            string? temp_src = null;
            string actual_input = materialize_input (input_path, raw_buffer_fallback, out temp_src);
            string src_dir = GLib.Path.get_dirname (actual_input);
            string pandoc_from = (fmt == DocumentFormat.IPYNB) ? "ipynb" : ((fmt == DocumentFormat.HTML) ? "html" : "markdown");

            try {
                // Stage 1: Try Quarto / RMarkdown direct PDF render if notebook
                if ((fmt == DocumentFormat.QMD || fmt == DocumentFormat.IPYNB) &&
                    Core.PlatformUtils.is_program_available ("quarto", src_dir)) {
                    string quarto_log = "";
                    cli_succeeded = run_tool_process_with_output ("quarto", { "render", actual_input, "--to", "pdf", "--output", out_file }, src_dir, out quarto_log)
                                    && move_quarto_output_if_needed (src_dir, out_file, output_path);

                    if (!cli_succeeded) {
                        bool needs_tex = quarto_log.contains ("No LaTeX installation found") ||
                                         quarto_log.contains ("xelatex not found") ||
                                         quarto_log.contains ("pdflatex not found") ||
                                         quarto_log.contains ("lualatex not found") ||
                                         quarto_log.contains ("LaTeX Error") ||
                                         quarto_log.contains ("tlmgr") ||
                                         quarto_log.contains ("tinytex");
                        if (needs_tex) {
                            string tt_log = "";
                            if (run_tool_process_with_output ("quarto", { "install", "tinytex", "--no-prompt" }, src_dir, out tt_log)) {
                                cli_succeeded = run_tool_process_with_output ("quarto", { "render", actual_input, "--to", "pdf", "--output", out_file }, src_dir, out quarto_log)
                                                && move_quarto_output_if_needed (src_dir, out_file, output_path);
                            }
                        }

                        // If LaTeX/TinyTeX still failed (e.g. offline), try Quarto's built-in Typst PDF backend
                        if (!cli_succeeded && Core.PlatformUtils.is_program_available ("typst", src_dir)) {
                            string typst_log = "";
                            cli_succeeded = run_tool_process_with_output ("quarto", { "render", actual_input, "--to", "typst", "--output", out_file }, src_dir, out typst_log)
                                            && move_quarto_output_if_needed (src_dir, out_file, output_path);
                        }

                        if (!cli_succeeded && quarto_log != "") {
                            GLib.warning ("Quarto PDF render failed: %s", quarto_log);
                        }
                    }
                } else if (fmt == DocumentFormat.RMD &&
                           Core.PlatformUtils.is_program_available ("Rscript", src_dir)) {
                    string r_expr = "if (requireNamespace('rmarkdown', quietly=TRUE)) rmarkdown::render('%s', output_format = 'pdf_document', output_file = '%s', quiet = TRUE) else stop('no rmarkdown')".printf (
                        actual_input.replace ("'", "\\'"),
                        output_path.replace ("'", "\\'")
                    );
                    cli_succeeded = run_tool_process ("Rscript", { "-e", r_expr }, src_dir);
                }

                // Stage 2: Try Pandoc with detected PDF engines
                if (!cli_succeeded && Core.PlatformUtils.is_program_available ("pandoc", src_dir)) {
                    string[] pdf_engines = { "typst", "weasyprint", "xelatex", "pdflatex", "lualatex", "wkhtmltopdf" };
                    string? detected_engine = null;
                    foreach (var eng in pdf_engines) {
                        if (Core.PlatformUtils.is_program_available (eng, src_dir)) {
                            detected_engine = eng;
                            break;
                        }
                    }

                    if (detected_engine != null) {
                        cli_succeeded = run_tool_process ("pandoc", { actual_input, "-f", pandoc_from, @"--pdf-engine=$detected_engine", "--standalone", "-o", output_path }, src_dir);
                    } else {
                        cli_succeeded = run_tool_process ("pandoc", { actual_input, "-f", pandoc_from, "--standalone", "-o", output_path }, src_dir);
                    }
                }

                // Stage 3: High-fidelity LibreOffice headless fallback via intermediate ODT
                if (!cli_succeeded || !GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                    string? soffice_bin = Core.PlatformUtils.find_program ("soffice", src_dir)
                        ?? Core.PlatformUtils.find_program ("libreoffice", src_dir);

                    if (soffice_bin != null) {
                        string tmp_odt = GLib.Path.build_filename (
                            Core.PlatformUtils.get_shared_cache_dir ("tmp"),
                            @"imladris_pdf_$(GLib.Random.next_int ()).odt"
                        );
                        export_to_odt (actual_input, tmp_odt, raw_buffer_fallback);
                        if (GLib.FileUtils.test (tmp_odt, GLib.FileTest.EXISTS)) {
                            cli_succeeded = convert_with_libreoffice (soffice_bin, tmp_odt, "pdf", out_dir, output_path);
                            GLib.FileUtils.remove (tmp_odt);
                        }
                    }
                }
            } finally {
                if (temp_src != null && GLib.FileUtils.test (temp_src, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (temp_src);
                }
            }

            if (!cli_succeeded || !GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                throw new GLib.IOError.FAILED (
                    "PDF export requires Quarto (with TinyTeX or Typst), Pandoc (with typst/weasyprint/pdflatex), or LibreOffice. Run Data Science Toolchain Manager or install pandoc/typst."
                );
            }
        }

        /**
         * Exports a source document (.md, .Rmd, .qmd, .ipynb) to Rich Text Format (.rtf).
         * Uses Pandoc or LibreOffice (via intermediate ODT), falling back to the built-in
         * native RTF 1.0 generator so RTF export always succeeds offline.
         */
        public static void export_to_rtf (string input_path, string output_path, string? raw_buffer_fallback = null) throws GLib.Error {
            var fmt = DocumentFormat.from_filename (input_path);
            bool cli_succeeded = false;

            string out_dir = GLib.Path.get_dirname (output_path);
            ensure_parent_dir (output_path);

            string? temp_src = null;
            string actual_input = materialize_input (input_path, raw_buffer_fallback, out temp_src);
            string src_dir = GLib.Path.get_dirname (actual_input);
            string pandoc_from = (fmt == DocumentFormat.IPYNB) ? "ipynb" : ((fmt == DocumentFormat.HTML) ? "html" : "markdown");

            try {
                if (Core.PlatformUtils.is_program_available ("pandoc", src_dir)) {
                    cli_succeeded = run_tool_process ("pandoc", { actual_input, "-f", pandoc_from, "-t", "rtf", "--standalone", "-o", output_path }, src_dir);
                }

                if (!cli_succeeded || !GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                    string? soffice_bin = Core.PlatformUtils.find_program ("soffice", src_dir)
                        ?? Core.PlatformUtils.find_program ("libreoffice", src_dir);

                    if (soffice_bin != null) {
                        string tmp_odt = GLib.Path.build_filename (
                            Core.PlatformUtils.get_shared_cache_dir ("tmp"),
                            @"imladris_rtf_$(GLib.Random.next_int ()).odt"
                        );
                        export_to_odt (actual_input, tmp_odt, raw_buffer_fallback);
                        if (GLib.FileUtils.test (tmp_odt, GLib.FileTest.EXISTS)) {
                            cli_succeeded = convert_with_libreoffice (soffice_bin, tmp_odt, "rtf", out_dir, output_path);
                            GLib.FileUtils.remove (tmp_odt);
                        }
                    }
                }
            } finally {
                if (temp_src != null && GLib.FileUtils.test (temp_src, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (temp_src);
                }
            }

            if (!cli_succeeded || !GLib.FileUtils.test (output_path, GLib.FileTest.EXISTS)) {
                string source_text = read_source_or_fallback (input_path, raw_buffer_fallback);
                build_native_rtf_document (source_text, output_path);
            }
        }

        private static ExportService? _instance = null;

        public static ExportService get_default () {
            if (_instance == null) {
                _instance = new ExportService ();
            }
            return _instance;
        }

        public async bool export_document_async (string input_path, string output_path, string format_target, string? raw_buffer = null) {
            string ext_label = format_target.up ();
            string src_path = input_path;

            string raw_text = raw_buffer != null ? raw_buffer : read_source_or_fallback (input_path, null);
            bool ok = false;
            string err_msg = "";

            GLib.SourceFunc callback = export_document_async.callback;
            new GLib.Thread<void*> ("imladris-export-worker", () => {
                try {
                    string target = format_target.down ();
                    if (target == "odp") {
                        export_to_odp (src_path, output_path, raw_text);
                    } else if (target == "html" || target == "htm") {
                        export_to_html (src_path, output_path, raw_text);
                    } else if (target == "pdf") {
                        export_to_pdf (src_path, output_path, raw_text);
                    } else if (target == "rtf") {
                        export_to_rtf (src_path, output_path, raw_text);
                    } else {
                        export_to_odt (src_path, output_path, raw_text);
                    }
                    ok = true;
                } catch (GLib.Error e) {
                    err_msg = e.message;
                }
                GLib.Idle.add ((owned) callback);
                return null;
            });
            yield;

            if (!ok && err_msg != "") {
                GLib.warning ("Export to %s failed: %s", ext_label, err_msg);
            }
            return ok;
        }

        private static void ensure_parent_dir (string file_path) throws GLib.Error {
            string? parent = GLib.Path.get_dirname (file_path);
            if (parent != null && parent != "") {
                var dir = GLib.File.new_for_path (parent);
                if (!dir.query_exists ()) {
                    dir.make_directory_with_parents (null);
                }
            }
        }

        private static string read_source_or_fallback (string input_path, string? fallback) {
            if (GLib.FileUtils.test (input_path, GLib.FileTest.EXISTS)) {
                try {
                    string content;
                    GLib.FileUtils.get_contents (input_path, out content);
                    var fmt = DocumentFormat.from_filename (input_path);
                    return Adapters.DocumentAdapter.load_to_editor_buffer (content, fmt);
                } catch (GLib.FileError e) {
                    // Use fallback
                }
            }
            return fallback ?? "";
        }

        /**
         * Standards-compliant OASIS OpenDocument Text (.odt) ZIP container generator.
         */
        private static void build_oasis_odt_container (string markdown_source, string output_path) throws GLib.Error {
            Core.FrontmatterData? meta;
            string body;
            Core.FrontmatterParser.split_frontmatter (markdown_source, out meta, out body);

            var body_xml = new GLib.StringBuilder ();
            if (meta != null && meta.title != null && meta.title.strip () != "") {
                body_xml.append_printf (
                    "<text:h text:style-name=\"Heading_20_1\" text:outline-level=\"1\">%s</text:h>\n",
                    GLib.Markup.escape_text (meta.title.strip ())
                );
            }

            foreach (string raw_line in body.split ("\n")) {
                string line = raw_line.strip ();
                if (line == "") continue;
                if (line.has_prefix ("### ")) {
                    body_xml.append_printf (
                        "<text:h text:style-name=\"Heading_20_3\" text:outline-level=\"3\">%s</text:h>\n",
                        GLib.Markup.escape_text (line.substring (4))
                    );
                } else if (line.has_prefix ("## ")) {
                    body_xml.append_printf (
                        "<text:h text:style-name=\"Heading_20_2\" text:outline-level=\"2\">%s</text:h>\n",
                        GLib.Markup.escape_text (line.substring (3))
                    );
                } else if (line.has_prefix ("# ")) {
                    body_xml.append_printf (
                        "<text:h text:style-name=\"Heading_20_1\" text:outline-level=\"1\">%s</text:h>\n",
                        GLib.Markup.escape_text (line.substring (2))
                    );
                } else {
                    body_xml.append_printf (
                        "<text:p text:style-name=\"Standard\">%s</text:p>\n",
                        GLib.Markup.escape_text (raw_line)
                    );
                }
            }

            string content_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  office:version="1.2">
  <office:body>
    <office:text>
%s    </office:text>
  </office:body>
</office:document-content>
""".printf (body_xml.str);

            package_oasis_zip (
                "application/vnd.oasis.opendocument.text",
                content_xml,
                output_path
            );
        }

        /**
         * Standards-compliant OASIS OpenDocument Presentation (.odp) ZIP container generator.
         */
        private static void build_oasis_odp_container (string markdown_source, string output_path) throws GLib.Error {
            Core.FrontmatterData? meta;
            string body;
            Core.FrontmatterParser.split_frontmatter (markdown_source, out meta, out body);

            var pages_xml = new GLib.StringBuilder ();
            int slide_num = 0;

            string[] lines = body.split ("\n");
            string current_title = (meta != null && meta.title != null && meta.title.strip () != "")
                ? meta.title.strip ()
                : "Slide 1";
            var current_bullets = new GLib.StringBuilder ();

            foreach (string raw_line in lines) {
                string trimmed = raw_line.strip ();
                if (trimmed == "---" || trimmed.has_prefix ("# ") || trimmed.has_prefix ("## ")) {
                    if (slide_num > 0 || current_bullets.len > 0) {
                        slide_num++;
                        append_odp_slide (pages_xml, slide_num, current_title, current_bullets.str);
                        current_bullets.truncate (0);
                    }
                    if (trimmed.has_prefix ("## ")) {
                        current_title = trimmed.substring (3).strip ();
                    } else if (trimmed.has_prefix ("# ")) {
                        current_title = trimmed.substring (2).strip ();
                    } else {
                        current_title = @"Slide $(slide_num + 1)";
                    }
                    continue;
                }
                if (trimmed != "") {
                    string clean_item = (trimmed.has_prefix ("- ") || trimmed.has_prefix ("* "))
                        ? trimmed.substring (2).strip ()
                        : trimmed;
                    current_bullets.append_printf (
                        "          <text:p>%s</text:p>\n",
                        GLib.Markup.escape_text (clean_item)
                    );
                }
            }

            slide_num++;
            append_odp_slide (pages_xml, slide_num, current_title, current_bullets.str);

            string content_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
  xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
  office:version="1.2">
  <office:body>
    <office:presentation>
%s    </office:presentation>
  </office:body>
</office:document-content>
""".printf (pages_xml.str);

            package_oasis_zip (
                "application/vnd.oasis.opendocument.presentation",
                content_xml,
                output_path
            );
        }

        private static void append_odp_slide (GLib.StringBuilder sb, int index, string title, string body_paragraphs) {
            sb.append_printf ("      <draw:page draw:name=\"page%d\" draw:master-page-name=\"Default\">\n", index);
            sb.append ("        <draw:frame presentation:class=\"title\" svg:x=\"2cm\" svg:y=\"1.5cm\" svg:width=\"24cm\" svg:height=\"3cm\">\n");
            sb.append ("          <draw:text-box>\n");
            sb.append_printf ("            <text:p>%s</text:p>\n", GLib.Markup.escape_text (title));
            sb.append ("          </draw:text-box>\n");
            sb.append ("        </draw:frame>\n");
            sb.append ("        <draw:frame presentation:class=\"outline\" svg:x=\"2cm\" svg:y=\"5cm\" svg:width=\"24cm\" svg:height=\"12cm\">\n");
            sb.append ("          <draw:text-box>\n");
            sb.append (body_paragraphs);
            sb.append ("          </draw:text-box>\n");
            sb.append ("        </draw:frame>\n");
            sb.append ("      </draw:page>\n");
        }

        private static bool convert_with_libreoffice (string soffice_bin, string input_file, string target_ext, string out_dir, string output_path) {
            try {
                string[] raw_lo_argv = { soffice_bin, "--headless", "--convert-to", target_ext, input_file, "--outdir", out_dir };
                string[] lo_argv = Core.PlatformUtils.build_host_command (raw_lo_argv, out_dir);
                var lo_proc = new GLib.Subprocess.newv (lo_argv, GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE);
                if (lo_proc.wait_check ()) {
                    string converted_name = GLib.Path.get_basename (input_file);
                    int dot_idx = converted_name.last_index_of_char ('.');
                    if (dot_idx > 0) {
                        converted_name = converted_name.substring (0, dot_idx) + "." + target_ext;
                    } else {
                        converted_name = converted_name + "." + target_ext;
                    }
                    string converted_path = GLib.Path.build_filename (out_dir, converted_name);
                    if (GLib.FileUtils.test (converted_path, GLib.FileTest.EXISTS)) {
                        var src_f = GLib.File.new_for_path (converted_path);
                        var dst_f = GLib.File.new_for_path (output_path);
                        src_f.move (dst_f, GLib.FileCopyFlags.OVERWRITE, null, null);
                        return true;
                    }
                }
            } catch (GLib.Error e) {
                GLib.debug ("LibreOffice conversion to %s failed: %s", target_ext, e.message);
            }
            return false;
        }

        private static void package_oasis_zip (string mimetype, string content_xml, string output_path) throws GLib.Error {
            string styles_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  office:version="1.2">
  <office:styles/>
  <office:master-styles>
    <style:master-page style:name="Default"/>
  </office:master-styles>
</office:document-styles>
""";

            string manifest_xml = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="%s"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>
""".printf (mimetype);

            string py_packer = """import json, sys, zipfile
payload = json.load(sys.stdin)
with zipfile.ZipFile(payload['out_path'], 'w') as zf:
    zf.writestr('mimetype', payload['mime'], compress_type=zipfile.ZIP_STORED)
    zf.writestr('content.xml', payload['content_xml'], compress_type=zipfile.ZIP_DEFLATED)
    zf.writestr('styles.xml', payload['styles_xml'], compress_type=zipfile.ZIP_DEFLATED)
    zf.writestr('META-INF/manifest.xml', payload['manifest_xml'], compress_type=zipfile.ZIP_DEFLATED)
""";

            var jb = new Json.Builder ();
            jb.begin_object ();
            jb.set_member_name ("out_path"); jb.add_string_value (output_path);
            jb.set_member_name ("mime"); jb.add_string_value (mimetype);
            jb.set_member_name ("content_xml"); jb.add_string_value (content_xml);
            jb.set_member_name ("styles_xml"); jb.add_string_value (styles_xml);
            jb.set_member_name ("manifest_xml"); jb.add_string_value (manifest_xml);
            jb.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (jb.get_root ());
            string stdin_json = gen.to_data (null);

            string[] argv = { "python3", "-c", py_packer };
            var proc = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDIN_PIPE | GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE);
            proc.communicate_utf8 (stdin_json, null, null, null);
            if (!proc.get_successful ()) {
                throw new IOError.FAILED ("Failed to package OASIS ZIP archive");
            }
        }

        /**
         * Standards-compliant RTF 1.0 generator fallback when Pandoc/LibreOffice are absent.
         */
        private static void build_native_rtf_document (string markdown_source, string output_path) throws GLib.Error {
            Core.FrontmatterData? meta;
            string body;
            Core.FrontmatterParser.split_frontmatter (markdown_source, out meta, out body);

            var rtf = new GLib.StringBuilder ();
            rtf.append ("{\\rtf1\\ansi\\ansicpg1252\\deff0\\nouicompat\n");
            rtf.append ("{\\fonttbl{\\f0\\fswiss\\fcharset0 Liberation Sans;}{\\f1\\fmodern\\fcharset0 Liberation Mono;}}\n");
            rtf.append ("\\viewkind4\\uc1\\pard\\sa160\\sl276\\slmult1\\f0\\fs22\n");

            if (meta != null && meta.title != null && meta.title.strip () != "") {
                rtf.append_printf ("\\pard\\sa200\\b\\fs36 %s\\b0\\fs22\\par\n", escape_rtf_text (meta.title.strip ()));
            }
            if (meta != null && meta.author != null && meta.author.strip () != "") {
                rtf.append_printf ("\\pard\\sa160\\i %s\\i0\\par\n", escape_rtf_text (meta.author.strip ()));
            }

            bool in_code = false;
            foreach (string raw_line in body.split ("\n")) {
                string trimmed = raw_line.strip ();
                if (trimmed.has_prefix ("```")) {
                    in_code = !in_code;
                    continue;
                }
                if (in_code) {
                    rtf.append_printf ("\\pard\\sa40\\f1\\fs20 %s\\f0\\fs22\\par\n", escape_rtf_text (raw_line));
                    continue;
                }
                if (trimmed == "") {
                    continue;
                }
                if (trimmed.has_prefix ("### ")) {
                    rtf.append_printf ("\\pard\\sa120\\b\\fs26 %s\\b0\\fs22\\par\n", escape_rtf_text (trimmed.substring (4)));
                } else if (trimmed.has_prefix ("## ")) {
                    rtf.append_printf ("\\pard\\sa140\\b\\fs30 %s\\b0\\fs22\\par\n", escape_rtf_text (trimmed.substring (3)));
                } else if (trimmed.has_prefix ("# ")) {
                    rtf.append_printf ("\\pard\\sa180\\b\\fs34 %s\\b0\\fs22\\par\n", escape_rtf_text (trimmed.substring (2)));
                } else {
                    rtf.append_printf ("\\pard\\sa120 %s\\par\n", escape_rtf_text (raw_line));
                }
            }

            rtf.append ("}\n");
            GLib.FileUtils.set_contents (output_path, rtf.str);
        }

        private static string escape_rtf_text (string text) {
            var sb = new GLib.StringBuilder ();
            int idx = 0;
            unichar c;
            while (text.get_next_char (ref idx, out c)) {
                if (c == '\\' || c == '{' || c == '}') {
                    sb.append_c ('\\');
                    sb.append_unichar (c);
                } else if (c < 128) {
                    sb.append_unichar (c);
                } else if (c <= 32767) {
                    sb.append_printf ("\\u%d?", (int) c);
                } else {
                    sb.append_printf ("\\u%d?", (int) c - 65536);
                }
            }
            return sb.str;
        }
    }
}
