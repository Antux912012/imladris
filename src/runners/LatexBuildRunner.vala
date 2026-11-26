/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: Apache-2.0
 */

using GLib;

namespace Imladris.Runners {

    public class LatexDiagnostic : GLib.Object {
        public string file { get; set; default = ""; }
        public int line { get; set; default = 1; }
        public string severity { get; set; default = "error"; }
        public string message { get; set; default = ""; }
    }

    public class LatexBuildResult : GLib.Object {
        public bool success { get; set; default = false; }
        public string pdf_path { get; set; default = ""; }
        public string log_text { get; set; default = ""; }
        public string stdout_stderr { get; set; default = ""; }
        public string engine_used { get; set; default = ""; }
        public Gee.ArrayList<LatexDiagnostic> diagnostics { get; private set; default = new Gee.ArrayList<LatexDiagnostic> (); }
    }

    public class LatexBuildRunner : GLib.Object {

        public static string? find_tex_engine (string? working_dir = null, string? preferred = null) {
            string[] candidates = (preferred != null && preferred != "")
                ? new string[] { preferred, "latexmk", "xelatex", "lualatex", "pdflatex", "tectonic" }
                : new string[] { "latexmk", "xelatex", "lualatex", "pdflatex", "tectonic" };

            foreach (string cand in candidates) {
                string? resolved = null;
                string? env_prefix = null;
                var src = Core.PlatformUtils.resolve_runtime (cand, working_dir, out resolved, out env_prefix);
                if (src != Core.RuntimeSource.MISSING) {
                    return cand;
                }
            }
            return null;
        }

        private static async int run_tex_cmd (
            string cmd,
            string[] args,
            string work_dir,
            GLib.Cancellable? cancellable,
            out string combined_output
        ) {
            combined_output = "";
            string? resolved = null;
            string? env_prefix = null;
            var src = Core.PlatformUtils.resolve_runtime (cmd, work_dir, out resolved, out env_prefix);
            if (src == Core.RuntimeSource.MISSING) {
                combined_output = @"TeX binary '$(cmd)' not found.";
                return 127;
            }

            var full_list = new Gee.ArrayList<string> ();
            full_list.add ((src == Core.RuntimeSource.HOST_FLATPAK_SPAWN || resolved == null) ? cmd : resolved);
            foreach (var a in args) full_list.add (a);

            string[] raw_argv = new string[full_list.size];
            for (int i = 0; i < full_list.size; i++) raw_argv[i] = full_list[i];

            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                launcher.set_cwd (work_dir);
                string[] argv;
                if (src == Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                    argv = Core.PlatformUtils.build_host_command (raw_argv, work_dir);
                } else {
                    Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                    argv = raw_argv;
                }

                var proc = launcher.spawnv (argv);
                string? out_str = null;
                yield proc.communicate_utf8_async (null, cancellable, out out_str, null);
                combined_output = out_str ?? "";
                return proc.get_if_exited () ? proc.get_exit_status () : 1;
            } catch (GLib.Error e) {
                combined_output = e.message;
                return 1;
            }
        }

        public static async LatexBuildResult build_async (
            string tex_path,
            string? preferred_engine = null,
            GLib.Cancellable? cancellable = null
        ) {
            var result = new LatexBuildResult ();
            string work_dir = GLib.Path.get_dirname (tex_path);
            string base_name = GLib.Path.get_basename (tex_path);
            string stem = base_name;
            int dot = stem.last_index_of (".");
            if (dot > 0) stem = stem.substring (0, dot);

            string? engine = find_tex_engine (work_dir, preferred_engine);
            if (engine == null) {
                result.success = false;
                result.stdout_stderr = "No LaTeX toolchain found (latexmk, xelatex, lualatex, pdflatex, or tectonic). Install a TeX engine first.";
                var diag = new LatexDiagnostic ();
                diag.file = base_name;
                diag.line = 1;
                diag.severity = "error";
                diag.message = result.stdout_stderr;
                result.diagnostics.add (diag);
                return result;
            }

            result.engine_used = engine;
            string out_log = "";
            int exit_code = 1;

            string tex_src = "";
            try { GLib.FileUtils.get_contents (tex_path, out tex_src); } catch (GLib.Error e) {}

            if (engine == "latexmk") {
                string latexmk_mode = (tex_src.contains ("fontspec") || tex_src.contains ("unicode-math") || tex_src.contains ("\\setmainfont")) ? "-xelatex" : "-pdf";
                exit_code = yield run_tex_cmd (
                    "latexmk",
                    { latexmk_mode, "-interaction=nonstopmode", "-file-line-error", "-synctex=1", base_name },
                    work_dir,
                    cancellable,
                    out out_log
                );
            } else if (engine == "tectonic") {
                exit_code = yield run_tex_cmd (
                    "tectonic",
                    { "--keep-logs", "--synctex", base_name },
                    work_dir,
                    cancellable,
                    out out_log
                );
            } else {
                exit_code = yield run_tex_cmd (
                    engine,
                    { "-interaction=nonstopmode", "-file-line-error", "-synctex=1", base_name },
                    work_dir,
                    cancellable,
                    out out_log
                );
                // Multi-pass bibliography support if requested in source
                if (exit_code == 0 && (tex_src.contains ("\\bibliography{") || tex_src.contains ("\\addbibresource{"))) {
                    string bib_tool = tex_src.contains ("\\addbibresource{") ? "biber" : "bibtex";
                    string bib_out;
                    int bib_rc = yield run_tex_cmd (bib_tool, { stem }, work_dir, cancellable, out bib_out);
                    out_log += "\n" + bib_out;
                    if (bib_rc != 0) {
                        exit_code = bib_rc;
                    } else {
                        string pass2;
                        exit_code = yield run_tex_cmd (
                            engine,
                            { "-interaction=nonstopmode", "-file-line-error", "-synctex=1", base_name },
                            work_dir,
                            cancellable,
                            out pass2
                        );
                        out_log += "\n" + pass2;
                        if (exit_code == 0) {
                            string pass3;
                            exit_code = yield run_tex_cmd (
                                engine,
                                { "-interaction=nonstopmode", "-file-line-error", "-synctex=1", base_name },
                                work_dir,
                                cancellable,
                                out pass3
                            );
                            out_log += "\n" + pass3;
                        }
                    }
                }

                // Additional pass(es) if .log still indicates unresolved references/citations
                string rerun_log_path = GLib.Path.build_filename (work_dir, @"$(stem).log");
                int extra_passes = 0;
                while (exit_code == 0 && extra_passes < 2 && GLib.FileUtils.test (rerun_log_path, GLib.FileTest.EXISTS)) {
                    string log_tmp = "";
                    try { GLib.FileUtils.get_contents (rerun_log_path, out log_tmp); } catch (GLib.Error e) {}
                    if (!log_tmp.contains ("Rerun to get")) {
                        break;
                    }
                    string rerun_out;
                    exit_code = yield run_tex_cmd (
                        engine,
                        { "-interaction=nonstopmode", "-file-line-error", "-synctex=1", base_name },
                        work_dir,
                        cancellable,
                        out rerun_out
                    );
                    out_log += "\n" + rerun_out;
                    extra_passes++;
                }
            }

            result.stdout_stderr = out_log;

            string log_path = GLib.Path.build_filename (work_dir, @"$(stem).log");
            if (GLib.FileUtils.test (log_path, GLib.FileTest.EXISTS)) {
                try {
                    string log_contents;
                    GLib.FileUtils.get_contents (log_path, out log_contents);
                    result.log_text = log_contents;
                    parse_diagnostics_from_log (log_contents, base_name, result.diagnostics);
                } catch (GLib.Error e) {}
            }

            string pdf_path = GLib.Path.build_filename (work_dir, @"$(stem).pdf");
            if (exit_code == 0 && GLib.FileUtils.test (pdf_path, GLib.FileTest.EXISTS)) {
                result.success = true;
                result.pdf_path = pdf_path;
            } else {
                result.success = false;
            }

            return result;
        }

        public static void parse_diagnostics_from_log (string log_text, string fallback_file, Gee.ArrayList<LatexDiagnostic> out_diags) {
            string diag_json = Core.NativeCore.parse_latex_log_json (log_text);
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (diag_json, -1);
                var root = parser.get_root ();
                if (root == null) return;
                Json.Array? arr = null;
                if (root.get_node_type () == Json.NodeType.ARRAY) {
                    arr = root.get_array ();
                } else if (root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("diagnostics") && obj.get_member ("diagnostics").get_node_type () == Json.NodeType.ARRAY) {
                        arr = obj.get_array_member ("diagnostics");
                    }
                }
                if (arr == null) return;
                for (uint i = 0; i < arr.get_length (); i++) {
                    var dobj = arr.get_object_element (i);
                    var d = new LatexDiagnostic ();
                    d.file = dobj.has_member ("file") && dobj.get_string_member ("file") != "" ? dobj.get_string_member ("file") : fallback_file;
                    d.line = dobj.has_member ("line") ? (int) dobj.get_int_member ("line") : 1;
                    d.severity = dobj.has_member ("severity") ? dobj.get_string_member ("severity") : "error";
                    d.message = dobj.has_member ("message") ? dobj.get_string_member ("message") : "";
                    out_diags.add (d);
                }
            } catch (GLib.Error e) {}
        }
    }
}
