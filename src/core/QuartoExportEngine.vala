// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Multi-format Quarto compiler and self-healing TeX provisioner.
 * Architecture: Central export pipeline executing revealjs, beamer, typst, and html compilations.
 * Concurrency: Fully asynchronous GLib.Subprocess execution on background thread with main context reporting.
 */

using GLib;

namespace Imladris.Core {

    public enum ScientificOutputFormat {
        HTML_MANUSCRIPT,
        PDF_MANUSCRIPT,
        REVEALJS_SLIDES,
        BEAMER_PDF_SLIDES,
        TYPST_POSTER_PDF;

        public string to_quarto_flag () {
            switch (this) {
                case HTML_MANUSCRIPT:   return "html";
                case PDF_MANUSCRIPT:    return "pdf";
                case REVEALJS_SLIDES:   return "revealjs";
                case BEAMER_PDF_SLIDES: return "beamer";
                case TYPST_POSTER_PDF:  return "typst";
                default:                return "html";
            }
        }

        public string to_display_label () {
            switch (this) {
                case HTML_MANUSCRIPT:   return "Manuscript (HTML)";
                case PDF_MANUSCRIPT:    return "Article / Report (PDF)";
                case REVEALJS_SLIDES:   return "Interactive Slides (RevealJS)";
                case BEAMER_PDF_SLIDES: return "Conference Slides (Beamer PDF)";
                case TYPST_POSTER_PDF:  return "Symposium Poster (Typst/PDF)";
                default:                return "Manuscript (HTML)";
            }
        }

        public string get_extension () {
            switch (this) {
                case PDF_MANUSCRIPT:
                case BEAMER_PDF_SLIDES:
                case TYPST_POSTER_PDF:
                    return ".pdf";
                case HTML_MANUSCRIPT:
                case REVEALJS_SLIDES:
                default:
                    return ".html";
            }
        }
    }

    public errordomain ExportError {
        QUARTO_MISSING,
        TEX_ENGINE_MISSING,
        TINYTEX_INSTALL_FAILED,
        RENDER_FAILED
    }

    public class QuartoExportEngine : GLib.Object {

        public signal void compilation_progress (string status_line);
        public signal void export_succeeded (string output_file_path, ScientificOutputFormat format);
        public signal void tex_healing_started ();

        public QuartoExportEngine () {}

        /**
         * Renders a Quarto (.qmd) document asynchronously to the specified scientific format.
         * Detects missing TeX or Beamer packages, triggers self-healing TinyTeX installation,
         * and retries compilation before failing.
         */
        public async string render_document_async (string qmd_path, ScientificOutputFormat format) throws GLib.Error {
            if (!GLib.FileUtils.test (qmd_path, GLib.FileTest.EXISTS)) {
                throw new GLib.IOError.NOT_FOUND (@"Source document not found at $qmd_path");
            }

            string working_dir = GLib.Path.get_dirname (qmd_path);
            string base_name = GLib.Path.get_basename (qmd_path);
            int dot_idx = base_name.last_index_of (".");
            string root_name = (dot_idx > 0) ? base_name.substring (0, dot_idx) : base_name;
            string expected_output = GLib.Path.build_filename (working_dir, root_name + format.get_extension ());

            compilation_progress (@"▶ Starting $(format.to_display_label ()) compilation for $base_name...");

            string? resolved_quarto_check = null;
            string? env_prefix_check = null;
            if (Core.PlatformUtils.resolve_runtime ("quarto", working_dir, out resolved_quarto_check, out env_prefix_check) == Core.RuntimeSource.MISSING) {
                throw new ExportError.QUARTO_MISSING ("Quarto CLI was not found in the project, managed toolchain, or system PATH.");
            }

            string exec_log = "";
            bool success = yield execute_quarto_render_pass (qmd_path, format, working_dir, out exec_log);

            if (!success && (format == ScientificOutputFormat.BEAMER_PDF_SLIDES || format == ScientificOutputFormat.PDF_MANUSCRIPT)) {
                bool needs_tex = exec_log.contains ("No LaTeX installation found") ||
                                 exec_log.contains ("xelatex not found") ||
                                 exec_log.contains ("pdflatex not found") ||
                                 exec_log.contains ("lualatex not found") ||
                                 exec_log.contains ("LaTeX Error") ||
                                 exec_log.contains ("beamer.cls") ||
                                 exec_log.contains ("tlmgr") ||
                                 exec_log.contains ("tinytex");

                if (needs_tex) {
                    tex_healing_started ();
                    compilation_progress ("[Imladris TeX Healer] Missing LaTeX packages detected. Provisioning isolated TinyTeX runtime...");
                    yield heal_tinytex_runtime (working_dir);
                    compilation_progress ("▶ TinyTeX provisioned. Retrying PDF compilation...");
                    success = yield execute_quarto_render_pass (qmd_path, format, working_dir, out exec_log);
                }
            }

            if (!success) {
                compilation_progress (@"✖ Render failed: $exec_log");
                throw new ExportError.RENDER_FAILED (@"Quarto render failed: $exec_log");
            }

            if (!GLib.FileUtils.test (expected_output, GLib.FileTest.EXISTS)) {
                string missing_msg = @"Quarto exited without creating $(GLib.Path.get_basename (expected_output))";
                compilation_progress (@"✖ Render failed: $missing_msg");
                throw new ExportError.RENDER_FAILED (missing_msg);
            }

            compilation_progress (@"✔ Successfully generated: $(GLib.Path.get_basename (expected_output))");
            export_succeeded (expected_output, format);
            return expected_output;
        }

        private async bool execute_quarto_render_pass (string qmd_path, ScientificOutputFormat format, string working_dir, out string log_accumulator) {
            log_accumulator = "";
            string? resolved_quarto = null;
            string? env_prefix = null;
            var source = Core.PlatformUtils.resolve_runtime ("quarto", working_dir, out resolved_quarto, out env_prefix);

            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);
            Core.PlatformUtils.inject_galaxy_credentials (launcher);
            launcher.set_cwd (working_dir);

            string target_flag = format.to_quarto_flag ();
            string[] raw_args = { (resolved_quarto != null) ? resolved_quarto : "quarto", "render", qmd_path, "--to", target_flag };

            string[] argv;
            if (source == Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                string[] host_cmd = { "quarto", "render", qmd_path, "--to", target_flag };
                argv = Core.PlatformUtils.build_host_command (host_cmd, working_dir);
            } else {
                Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                argv = raw_args;
            }

            try {
                var proc = launcher.spawnv (argv);
                var dis = new GLib.DataInputStream (proc.get_stdout_pipe ());
                try {
                    string? line = null;
                    var sb = new GLib.StringBuilder ();

                    while ((line = yield dis.read_line_async (GLib.Priority.DEFAULT, null)) != null) {
                        sb.append (line).append ("\n");
                        compilation_progress (line);
                    }

                    yield proc.wait_async (null);
                    log_accumulator = sb.str;
                    return proc.get_successful ();
                } finally {
                    try { dis.close (); } catch (GLib.Error e) {}
                }
            } catch (GLib.Error e) {
                log_accumulator = e.message;
                return false;
            }
        }

        private async void heal_tinytex_runtime (string working_dir) throws GLib.Error {
            string? resolved_quarto = null;
            string? env_prefix = null;
            var source = Core.PlatformUtils.resolve_runtime ("quarto", working_dir, out resolved_quarto, out env_prefix);

            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);
            launcher.set_cwd (working_dir);

            string[] raw_args = { (resolved_quarto != null) ? resolved_quarto : "quarto", "install", "tinytex", "--no-prompt" };
            string[] argv;
            if (source == Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                string[] host_cmd = { "quarto", "install", "tinytex", "--no-prompt" };
                argv = Core.PlatformUtils.build_host_command (host_cmd, working_dir);
            } else if (source == Core.RuntimeSource.MANAGED_GLOBAL || source == Core.RuntimeSource.PROJECT_SANDBOX) {
                Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                argv = raw_args;
            } else {
                argv = raw_args;
            }

            try {
                var proc = launcher.spawnv (argv);
                var dis = new GLib.DataInputStream (proc.get_stdout_pipe ());
                try {
                    string? line = null;

                    while ((line = yield dis.read_line_async (GLib.Priority.DEFAULT, null)) != null) {
                        compilation_progress (@"[TinyTeX] $line");
                    }

                    yield proc.wait_async (null);
                } finally {
                    try { dis.close (); } catch (GLib.Error e) {}
                }
                if (!proc.get_successful ()) {
                    throw new ExportError.TINYTEX_INSTALL_FAILED ("quarto install tinytex command failed with non-zero exit code");
                }
            } catch (GLib.Error e) {
                throw new ExportError.TINYTEX_INSTALL_FAILED (@"TinyTeX automated installation failed: $(e.message)");
            }
        }
    }
}
