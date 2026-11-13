// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Manages persistent R and Python background processes.
 *
 * Architectural Position:
 * Kernel execution provider. Maintains long-running interactive subprocesses for
 * data inspection, plotting, and variable persistence across document views.
 * Downstream consumers: Imladris.UI.DataGridViewer, Imladris.EnvironmentPanel.
 * Upstream dependencies: gio-2.0, glib-2.0.
 *
 * Concurrency Constraints:
 * Serializes command evaluations using asynchronous FIFO queues. Eliminates
 * G_IO_ERROR_PENDING stream collision exceptions when multiple UI subsystems query data.
 */

using GLib;

namespace Imladris.Services {

    public class PersistentSessionManager : GLib.Object {

        private static PersistentSessionManager? _instance = null;

        public static PersistentSessionManager get_default () {
            if (_instance == null) {
                _instance = new PersistentSessionManager ();
            }
            return _instance;
        }

        private string _current_working_dir = "";
        public string current_working_dir { get { return _current_working_dir; } }
        public ProjectType active_project_type { get; private set; default = ProjectType.STANDARD; }

        public signal void working_directory_changed (string new_dir);
        public signal void session_output_received (string engine, string output, bool is_error);
        public signal void plot_generated (string plot_file_path);

        private GLib.Subprocess? r_process = null;
        private GLib.DataOutputStream? r_stdin = null;
        private GLib.DataInputStream? r_stdout = null;

        private GLib.Subprocess? py_process = null;
        private GLib.DataOutputStream? py_stdin = null;
        private GLib.DataInputStream? py_stdout = null;

        private bool r_initialized = false;
        private bool py_initialized = false;

        // Async FIFO Queues for Serialized Stream Reads
        private class SourceFuncWrapper {
            public GLib.SourceFunc cb;
            public SourceFuncWrapper (owned GLib.SourceFunc c) {
                this.cb = (owned) c;
            }
        }

        private bool r_busy = false;
        private GLib.Queue<SourceFuncWrapper> r_wait_queue = new GLib.Queue<SourceFuncWrapper> ();

        private bool py_busy = false;
        private GLib.Queue<SourceFuncWrapper> py_wait_queue = new GLib.Queue<SourceFuncWrapper> ();

        public PersistentSessionManager () {
            this._current_working_dir = GLib.Environment.get_current_dir ();
        }

        private async void lock_r () {
            if (!r_busy) {
                r_busy = true;
                return;
            }
            r_wait_queue.push_tail (new SourceFuncWrapper (lock_r.callback));
            yield;
        }

        private void unlock_r () {
            var next = r_wait_queue.pop_head ();
            if (next != null) {
                GLib.Idle.add ((owned) next.cb);
            } else {
                r_busy = false;
            }
        }

        private async void lock_py () {
            if (!py_busy) {
                py_busy = true;
                return;
            }
            py_wait_queue.push_tail (new SourceFuncWrapper (lock_py.callback));
            yield;
        }

        private void unlock_py () {
            var next = py_wait_queue.pop_head ();
            if (next != null) {
                GLib.Idle.add ((owned) next.cb);
            } else {
                py_busy = false;
            }
        }

        /**
         * Pillar 5: Automatic Working Directory (pwd) Synchronization
         * Updates process working directory, sets R working directory, sets Python working directory,
         * and notifies the Files quadrant and integrated terminal.
         */
        public void set_working_directory (string dir_path, ProjectType ptype = ProjectType.STANDARD) {
            if (!GLib.FileUtils.test (dir_path, GLib.FileTest.IS_DIR)) return;

            this._current_working_dir = dir_path;
            this.active_project_type = ptype;

            if (GLib.Environment.set_current_dir (dir_path) != 0) {
                GLib.warning ("Failed to change process current dir to %s", dir_path);
            }

            // Sync R session
            if (r_initialized && r_stdin != null) {
                try {
                    string escaped = dir_path.replace ("\\", "/").replace ("\"", "\\\"");
                    r_stdin.put_string (@"setwd(\"$escaped\"); invisible()\n", null);
                    r_stdin.flush ();
                } catch (GLib.Error e) {
                    // Session may have terminated
                }
            }

            // Sync Python session
            if (py_initialized && py_stdin != null) {
                try {
                    string escaped = dir_path.replace ("\\", "/").replace ("\"", "\\\"");
                    py_stdin.put_string (@"import os; os.chdir(\"$escaped\")\n", null);
                    py_stdin.flush ();
                } catch (GLib.Error e) {
                    // Session may have terminated
                }
            }

            working_directory_changed (dir_path);
        }

        /**
         * Pillar 4: Shared State & Bidirectional Execution Session
         * Evaluates code in the persistent R session. Variables, functions, and imports
         * remain alive across calls.
         */
        public async string execute_r (string code, out string? generated_plot) {
            yield lock_r ();
            try {
                return yield execute_r_internal (code, out generated_plot);
            } finally {
                unlock_r ();
            }
        }

        private static string encode_hex (uint8[] data) {
            var sb = new GLib.StringBuilder ();
            for (int i = 0; i < data.length; i++) {
                sb.append_printf ("%02x", data[i]);
            }
            return sb.str;
        }

        private async string execute_r_internal (string code, out string? generated_plot) {
            generated_plot = null;
            ensure_r_session ();

            if (r_stdin == null || r_stdout == null) {
                return "✖ R interpreter (R/Rscript) is not available. Click 'Install Toolchain' to install R automatically.";
            }

            string plot_dir = Core.PlatformUtils.get_shared_cache_dir ("plots");
            string plot_id = GLib.Uuid.string_random ().replace ("-", "");
            string plot_file = GLib.Path.build_filename (plot_dir, @"plot_$(plot_id).png");

            bool has_plot = code.contains ("plot(") || code.contains ("plot (") ||
                            code.contains ("ggplot") || code.contains ("qplot") ||
                            code.contains ("hist(") || code.contains ("barplot(") ||
                            code.contains ("boxplot(") || code.contains ("pairs(") ||
                            code.contains ("heatmap(") || code.contains ("pheatmap(") ||
                            code.contains ("image(") || code.contains ("matplot(") ||
                            code.contains ("qqnorm(") || code.contains ("curve(") ||
                            code.contains ("xyplot(") || code.contains ("bwplot(") ||
                            code.contains ("dotchart(") || code.contains ("pie(") ||
                            code.contains ("print(");

            string sentinel = @"__IMLADRIS_R_DONE_$(plot_id)__";
            string hex_code = encode_hex (code.data);
            string payload = @"$(sentinel)|$(has_plot ? "1" : "0")|$(hex_code)|$(plot_file.replace ("\\", "/"))\n";

            try {
                r_stdin.put_string (payload, null);
                r_stdin.flush ();

                var output_sb = new GLib.StringBuilder ();
                string? line = null;
                while (true) {
                    line = yield r_stdout.read_line_async (GLib.Priority.DEFAULT, null);
                    if (line == null) {
                        r_initialized = false;
                        break;
                    }
                    if (line.contains (sentinel)) break;
                    output_sb.append (line + "\n");
                    session_output_received ("r", line, false);
                }

                if (has_plot && GLib.FileUtils.test (plot_file, GLib.FileTest.EXISTS)) {
                    var f = GLib.File.new_for_path (plot_file);
                    try {
                        var info = f.query_info (GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
                        if (info.get_size () > 100) {
                            generated_plot = plot_file;
                            plot_generated (plot_file);
                        }
                    } catch (GLib.Error e) {}
                }

                return output_sb.str.strip ();
            } catch (GLib.Error e) {
                r_initialized = false;
                return @"✖ R evaluation error: $(e.message)";
            }
        }

        /**
         * Pillar 4: Shared State & Bidirectional Execution Session
         * Evaluates code in the persistent Python REPL. Variables, dataframes, and imports
         * remain alive in the workspace.
         */
        public async string execute_python (string code, out string? generated_plot) {
            yield lock_py ();
            try {
                return yield execute_python_internal (code, out generated_plot);
            } finally {
                unlock_py ();
            }
        }

        private async string execute_python_internal (string code, out string? generated_plot) {
            generated_plot = null;
            ensure_python_session ();

            if (py_stdin == null || py_stdout == null) {
                return "✖ Python 3 interpreter is not available. Click 'Install Toolchain' to install Python automatically.";
            }

            string plot_dir = Core.PlatformUtils.get_shared_cache_dir ("plots");
            string plot_id = GLib.Uuid.string_random ().replace ("-", "");
            string plot_file = GLib.Path.build_filename (plot_dir, @"plot_$(plot_id).png");

            bool has_plot = code.contains ("plt.") || code.contains ("matplotlib") ||
                            code.contains (".plot(") || code.contains ("sns.") ||
                            code.contains ("seaborn");

            string b64_code = GLib.Base64.encode (code.data);
            string sentinel = @"__IMLADRIS_PY_DONE_$(plot_id)__";
            string payload = @"$(sentinel)|$(has_plot ? "1" : "0")|$(b64_code)|$(plot_file)\n";

            try {
                py_stdin.put_string (payload, null);
                py_stdin.flush ();

                var output_sb = new GLib.StringBuilder ();
                string? line = null;
                while (true) {
                    line = yield py_stdout.read_line_async (GLib.Priority.DEFAULT, null);
                    if (line == null) {
                        py_initialized = false;
                        break;
                    }
                    if (line.contains (sentinel)) break;
                    output_sb.append (line + "\n");
                    session_output_received ("python", line, false);
                }

                if (has_plot && GLib.FileUtils.test (plot_file, GLib.FileTest.EXISTS)) {
                    var f = GLib.File.new_for_path (plot_file);
                    try {
                        var info = f.query_info (GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
                        if (info.get_size () > 100) {
                            generated_plot = plot_file;
                            plot_generated (plot_file);
                        }
                    } catch (GLib.Error e) {}
                }

                return output_sb.str.strip ();
            } catch (GLib.Error e) {
                py_initialized = false;
                return @"✖ Python evaluation error: $(e.message)";
            }
        }

        public void restart_all_sessions () {
            terminate_r ();
            terminate_python ();
        }

        public void shutdown_all () {
            terminate_r ();
            terminate_python ();
        }

        public void interrupt_active_execution () {
            if (r_process != null) {
                r_process.send_signal (2); // SIGINT
            }
            if (py_process != null) {
                py_process.send_signal (2); // SIGINT
            }
        }

        private void ensure_r_session () {
            if (r_initialized && r_process != null) return;

            string? cwd = (current_working_dir != "" && GLib.FileUtils.test (current_working_dir, GLib.FileTest.IS_DIR))
                ? current_working_dir : null;

            string? resolved_path = null;
            string? env_prefix = null;
            var source = Core.PlatformUtils.resolve_runtime ("R", cwd, out resolved_path, out env_prefix);
            if (source == Core.RuntimeSource.MISSING) {
                source = Core.PlatformUtils.resolve_runtime ("Rscript", cwd, out resolved_path, out env_prefix);
            }

            if (source == Core.RuntimeSource.MISSING) {
                r_initialized = false;
                return;
            }

            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDIN_PIPE | GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                if (cwd != null) {
                    launcher.set_cwd (cwd);
                }

                string r_driver = "options(width = 120, warn = 1); .imladris_env <- globalenv(); .imladris_con <- file('stdin', open = 'r'); while (length(.line <- readLines(.imladris_con, n = 1L, warn = FALSE)) > 0L) { if (!nzchar(.line)) next; .parts <- strsplit(.line, '|', fixed = TRUE)[[1L]]; if (length(.parts) < 4L) next; .sentinel <- .parts[1L]; .has_plot <- (.parts[2L] == '1'); .hex <- .parts[3L]; .plot_file <- paste(.parts[4L:length(.parts)], collapse = '|'); .code <- if (nzchar(.hex)) { .idx <- seq.int(1L, nchar(.hex), by = 2L); .s <- rawToChar(as.raw(strtoi(substring(.hex, .idx, .idx + 1L), 16L))); Encoding(.s) <- 'UTF-8'; .s } else ''; tryCatch({ .exprs <- parse(text = .code); if (.has_plot) grDevices::png(.plot_file, width = 800, height = 500, res = 120); tryCatch({ for (.e in .exprs) { .res <- withVisible(eval(.e, envir = .imladris_env)); if (.res$visible) print(.res$value) } }, finally = { if (.has_plot && grDevices::dev.cur() > 1L) grDevices::dev.off() }) }, error = function(e) { cat(sprintf('Error: %s\\n', conditionMessage(e))) }); flush.console(); cat(sprintf('\\n%s\\n', .sentinel)); flush.console() }";

                string[] raw_argv = {
                    (resolved_path != null) ? resolved_path : "R",
                    "--slave",
                    "--no-restore",
                    "--no-save",
                    "-e",
                    r_driver
                };

                string[] argv;
                if (source == Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                    argv = Core.PlatformUtils.build_host_command ({ "R", "--slave", "--no-restore", "--no-save", "-e", r_driver }, cwd);
                } else {
                    Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                    argv = raw_argv;
                }

                r_process = launcher.spawnv (argv);
                r_stdin = new GLib.DataOutputStream (r_process.get_stdin_pipe ());
                r_stdout = new GLib.DataInputStream (r_process.get_stdout_pipe ());
                r_initialized = true;
            } catch (GLib.Error e) {
                r_initialized = false;
                GLib.warning ("Failed to launch persistent R session: %s", e.message);
            }
        }

        private void ensure_python_session () {
            if (py_initialized && py_process != null) return;

            string? cwd = (current_working_dir != "" && GLib.FileUtils.test (current_working_dir, GLib.FileTest.IS_DIR))
                ? current_working_dir : null;

            string? resolved_path = null;
            string? env_prefix = null;
            var source = Core.PlatformUtils.resolve_runtime ("python3", cwd, out resolved_path, out env_prefix);
            if (source == Core.RuntimeSource.MISSING) {
                source = Core.PlatformUtils.resolve_runtime ("python", cwd, out resolved_path, out env_prefix);
            }

            if (source == Core.RuntimeSource.MISSING) {
                py_initialized = false;
                return;
            }

            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDIN_PIPE | GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                if (cwd != null) {
                    launcher.set_cwd (cwd);
                }

                string py_driver = """
import sys, base64, traceback
_imladris_ns = {'__name__': '__main__'}
for _raw in sys.stdin:
    _raw = _raw.strip()
    if not _raw:
        continue
    _parts = _raw.split('|', 3)
    if len(_parts) != 4:
        continue
    _sentinel, _has_plot, _b64, _plot_path = _parts
    try:
        _src = base64.b64decode(_b64).decode('utf-8')
        _code = compile(_src, '<imladris-cell>', 'exec')
        _has_mpl = False
        if _has_plot == '1':
            try:
                import matplotlib
                matplotlib.use('Agg')
                import matplotlib.pyplot as plt
                _has_mpl = True
            except Exception:
                _has_mpl = False
        exec(_code, _imladris_ns)
        if _has_mpl and plt.get_fignums():
            plt.savefig(_plot_path, dpi=120, bbox_inches='tight')
            plt.close('all')
    except Exception:
        traceback.print_exc(file=sys.stdout)
    sys.stdout.flush()
    sys.stderr.flush()
    print(_sentinel, flush=True)
""";

                string[] raw_argv = {
                    (resolved_path != null) ? resolved_path : "python3",
                    "-u",
                    "-c",
                    py_driver
                };

                string[] argv;
                if (source == Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                    argv = Core.PlatformUtils.build_host_command ({ "python3", "-u", "-c", py_driver }, cwd);
                } else {
                    Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                    argv = raw_argv;
                }

                py_process = launcher.spawnv (argv);
                py_stdin = new GLib.DataOutputStream (py_process.get_stdin_pipe ());
                py_stdout = new GLib.DataInputStream (py_process.get_stdout_pipe ());
                py_initialized = true;
            } catch (GLib.Error e) {
                py_initialized = false;
                GLib.warning ("Failed to launch persistent Python session: %s", e.message);
            }
        }

        private void terminate_r () {
            if (r_process != null) {
                try {
                    if (r_stdin != null) {
                        r_stdin.put_string ("q(save = 'no')\n", null);
                        r_stdin.close (null);
                    }
                    if (r_stdout != null) {
                        r_stdout.close (null);
                    }
                    r_process.force_exit ();
                } catch (GLib.Error e) {}
                r_process = null;
                r_stdin = null;
                r_stdout = null;
                r_initialized = false;
            }
        }

        private void terminate_python () {
            if (py_process != null) {
                try {
                    if (py_stdin != null) {
                        py_stdin.put_string ("exit()\n", null);
                        py_stdin.close (null);
                    }
                    if (py_stdout != null) {
                        py_stdout.close (null);
                    }
                    py_process.force_exit ();
                } catch (GLib.Error e) {}
                py_process = null;
                py_stdin = null;
                py_stdout = null;
                py_initialized = false;
            }
        }
    }
}
