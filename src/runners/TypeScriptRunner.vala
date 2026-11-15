/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;

namespace Imladris.Runners {

    public class TsDiagnostic : GLib.Object {
        public string file { get; set; default = ""; }
        public int line { get; set; default = 1; }
        public int column { get; set; default = 1; }
        public string code { get; set; default = ""; }
        public string severity { get; set; default = "error"; }
        public string message { get; set; default = ""; }
    }

    public class TsRunResult : GLib.Object {
        public bool success { get; set; default = false; }
        public int exit_code { get; set; default = 1; }
        public string stdout_text { get; set; default = ""; }
        public string stderr_text { get; set; default = ""; }
        public string runtime_used { get; set; default = ""; }
        public int64 duration_ms { get; set; default = 0; }
        public Gee.ArrayList<TsDiagnostic> diagnostics { get; private set; default = new Gee.ArrayList<TsDiagnostic> (); }
    }

    public class TypeScriptRunner : GLib.Object {

        private static GLib.Regex? ansi_regex = null;
        private static GLib.Regex? tsc_diag_regex = null;

        public static string strip_ansi (string input) {
            try {
                if (ansi_regex == null) {
                    ansi_regex = new GLib.Regex ("\\x1B\\[[0-9;]*[mGKHF]");
                }
                return ansi_regex.replace (input, -1, 0, "");
            } catch (GLib.RegexError e) {
                return input;
            }
        }

        private static string? find_local_bin (string? project_dir, string bin_name) {
            if (project_dir == null || project_dir == "") return null;
            string p = GLib.Path.build_filename (project_dir, "node_modules", ".bin", bin_name);
            if (GLib.FileUtils.test (p, GLib.FileTest.IS_EXECUTABLE)) return p;
            return null;
        }

        public static string? find_ts_runtime (string? project_dir, out string runtime_kind, out Core.RuntimeSource src, out string? env_prefix) {
            runtime_kind = "";
            src = Core.RuntimeSource.MISSING;
            env_prefix = null;

            string? local_tsx = find_local_bin (project_dir, "tsx");
            if (local_tsx != null) {
                runtime_kind = "tsx";
                src = Core.RuntimeSource.PROJECT_SANDBOX;
                return local_tsx;
            }

            string[] order = { "tsx", "node", "deno", "bun" };
            foreach (string cand in order) {
                string? resolved = null;
                string? ep = null;
                var s = Core.PlatformUtils.resolve_runtime (cand, project_dir, out resolved, out ep);
                if (s != Core.RuntimeSource.MISSING) {
                    runtime_kind = cand;
                    src = s;
                    env_prefix = ep;
                    return resolved ?? cand;
                }
            }
            return null;
        }

        public static async TsRunResult run_file_async (
            string ts_path,
            string? project_dir = null,
            GLib.Cancellable? cancellable = null
        ) {
            var res = new TsRunResult ();
            string work_dir = (project_dir != null && project_dir != "") ? project_dir : GLib.Path.get_dirname (ts_path);
            string runtime_kind;
            Core.RuntimeSource src;
            string? env_prefix;
            string? bin = find_ts_runtime (work_dir, out runtime_kind, out src, out env_prefix);

            if (bin == null) {
                res.success = false;
                res.exit_code = 127;
                res.stderr_text = "No TypeScript runtime found (tsx, node >= 22.6, deno, or bun).";
                return res;
            }

            res.runtime_used = runtime_kind;
            string[] raw_argv;
            if (runtime_kind == "deno") {
                raw_argv = { (src == Core.RuntimeSource.HOST_FLATPAK_SPAWN) ? "deno" : bin, "run", "--allow-read", ts_path };
            } else if (runtime_kind == "bun") {
                raw_argv = { (src == Core.RuntimeSource.HOST_FLATPAK_SPAWN) ? "bun" : bin, "run", ts_path };
            } else if (runtime_kind == "node") {
                raw_argv = { (src == Core.RuntimeSource.HOST_FLATPAK_SPAWN) ? "node" : bin, "--experimental-strip-types", ts_path };
            } else {
                raw_argv = { (src == Core.RuntimeSource.HOST_FLATPAK_SPAWN) ? "tsx" : bin, ts_path };
            }

            int64 t0 = GLib.get_monotonic_time ();
            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
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
                string? out_s = null;
                string? err_s = null;
                yield proc.communicate_utf8_async (null, cancellable, out out_s, out err_s);
                res.duration_ms = (GLib.get_monotonic_time () - t0) / 1000;
                res.exit_code = proc.get_if_exited () ? proc.get_exit_status () : 1;
                res.success = (res.exit_code == 0);
                res.stdout_text = strip_ansi (out_s ?? "");
                res.stderr_text = strip_ansi (err_s ?? "");
            } catch (GLib.Error e) {
                res.duration_ms = (GLib.get_monotonic_time () - t0) / 1000;
                res.success = false;
                res.exit_code = 1;
                res.stderr_text = e.message;
            }
            return res;
        }

        public static async TsRunResult run_snippet_async (
            string code,
            string? project_dir = null,
            GLib.Cancellable? cancellable = null
        ) {
            string dir = (project_dir != null && project_dir != "" && GLib.FileUtils.test (project_dir, GLib.FileTest.IS_DIR))
                ? project_dir
                : Core.PlatformUtils.get_shared_cache_dir ("ts-runs");
            string tmp_path = GLib.Path.build_filename (dir, @"imladris_tmp_$(GLib.Uuid.string_random ().replace ("-", "")).ts");
            try {
                GLib.FileUtils.set_contents (tmp_path, code);
                return yield run_file_async (tmp_path, dir, cancellable);
            } catch (GLib.Error e) {
                var err_res = new TsRunResult ();
                err_res.success = false;
                err_res.stderr_text = e.message;
                return err_res;
            } finally {
                if (GLib.FileUtils.test (tmp_path, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (tmp_path);
                }
            }
        }

        public static async TsRunResult typecheck_async (
            string ts_path,
            string? project_dir = null,
            GLib.Cancellable? cancellable = null
        ) {
            var res = new TsRunResult ();
            string work_dir = (project_dir != null && project_dir != "") ? project_dir : GLib.Path.get_dirname (ts_path);
            string? local_tsc = find_local_bin (work_dir, "tsc");
            string? resolved = null;
            string? env_prefix = null;
            var src = (local_tsc != null)
                ? Core.RuntimeSource.PROJECT_SANDBOX
                : Core.PlatformUtils.resolve_runtime ("tsc", work_dir, out resolved, out env_prefix);

            if (src == Core.RuntimeSource.MISSING) {
                res.success = false;
                res.exit_code = 127;
                res.stderr_text = "TypeScript compiler (tsc) not found. Install typescript locally or globally.";
                return res;
            }

            string bin = local_tsc ?? ((src == Core.RuntimeSource.HOST_FLATPAK_SPAWN || resolved == null) ? "tsc" : resolved);
            string tsconfig = GLib.Path.build_filename (work_dir, "tsconfig.json");
            string[] raw_argv = GLib.FileUtils.test (tsconfig, GLib.FileTest.EXISTS)
                ? new string[] { bin, "--noEmit", "--pretty", "false", "-p", tsconfig }
                : new string[] { bin, "--noEmit", "--pretty", "false", ts_path };

            res.runtime_used = "tsc";
            int64 t0 = GLib.get_monotonic_time ();
            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE
                );
                launcher.set_cwd (work_dir);
                string[] argv = (src == Core.RuntimeSource.HOST_FLATPAK_SPAWN)
                    ? Core.PlatformUtils.build_host_command (raw_argv, work_dir)
                    : raw_argv;
                if (src != Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                    Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                }
                var proc = launcher.spawnv (argv);
                string? out_s = null;
                string? err_s = null;
                yield proc.communicate_utf8_async (null, cancellable, out out_s, out err_s);
                res.duration_ms = (GLib.get_monotonic_time () - t0) / 1000;
                res.exit_code = proc.get_if_exited () ? proc.get_exit_status () : 1;
                res.success = (res.exit_code == 0);
                res.stdout_text = strip_ansi (out_s ?? "");
                res.stderr_text = strip_ansi (err_s ?? "");
                parse_tsc_diagnostics (res.stdout_text + "\n" + res.stderr_text, res.diagnostics);
            } catch (GLib.Error e) {
                res.duration_ms = (GLib.get_monotonic_time () - t0) / 1000;
                res.success = false;
                res.exit_code = 1;
                res.stderr_text = e.message;
            }
            return res;
        }

        public static void parse_tsc_diagnostics (string text, Gee.ArrayList<TsDiagnostic> out_diags) {
            try {
                if (tsc_diag_regex == null) {
                    tsc_diag_regex = new GLib.Regex ("^(.+?)\\((\\d+),(\\d+)\\):\\s+(error|warning)\\s+(TS\\d+):\\s+(.+)$");
                }
                foreach (var raw_line in text.split ("\n")) {
                    string line = raw_line.strip ();
                    GLib.MatchInfo mi;
                    if (tsc_diag_regex.match (line, 0, out mi)) {
                        var d = new TsDiagnostic ();
                        d.file = mi.fetch (1);
                        d.line = int.parse (mi.fetch (2));
                        d.column = int.parse (mi.fetch (3));
                        d.severity = mi.fetch (4);
                        d.code = mi.fetch (5);
                        d.message = mi.fetch (6);
                        out_diags.add (d);
                    }
                }
            } catch (GLib.RegexError e) {}
        }
    }
}
