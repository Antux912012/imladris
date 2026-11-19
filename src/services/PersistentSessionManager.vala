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

    public delegate void OutputLineFunc (string engine, string line, bool is_error);

    public class PersistentSessionManager : GLib.Object {

        private static PersistentSessionManager? _instance = null;
        private static Gee.HashMap<string, PersistentSessionManager>? _pool = null;
        private static Gee.HashMap<string, int>? _pool_refs = null;

        public static PersistentSessionManager get_default () {
            if (_instance == null) {
                _instance = new PersistentSessionManager ();
            }
            return _instance;
        }

        public static PersistentSessionManager for_key (string session_key) {
            string norm = session_key.strip ();
            if (norm == "") return get_default ();
            if (_pool == null) {
                _pool = new Gee.HashMap<string, PersistentSessionManager> ();
                _pool_refs = new Gee.HashMap<string, int> ();
            }
            if (!_pool.has_key (norm)) {
                var mgr = new PersistentSessionManager ();
                if (GLib.FileUtils.test (norm, GLib.FileTest.IS_DIR)) {
                    mgr._current_working_dir = norm;
                }
                _pool.set (norm, mgr);
                _pool_refs.set (norm, 1);
            } else {
                _pool_refs.set (norm, _pool_refs.get (norm) + 1);
            }
            return _pool.get (norm);
        }

        /**
         * Returns an existing pooled session without incrementing its reference count,
         * or falls back to the default session if not yet pooled.
         */
        public static PersistentSessionManager peek_for_key (string session_key) {
            string norm = session_key.strip ();
            if (norm == "" || _pool == null || !_pool.has_key (norm)) {
                return get_default ();
            }
            return _pool.get (norm);
        }

        public static void release_session (string session_key) {
            string norm = session_key.strip ();
            if (_pool == null || !_pool.has_key (norm)) return;
            int cnt = _pool_refs.get (norm) - 1;
            if (cnt <= 0) {
                _pool.get (norm).shutdown_all ();
                _pool.unset (norm);
                _pool_refs.unset (norm);
            } else {
                _pool_refs.set (norm, cnt);
            }
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

        ~PersistentSessionManager () {
            shutdown_all ();
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

            // Route working directory updates through locked 4-field protocol calls
            if (r_initialized && r_process != null) {
                string hex_dir = Core.PlatformUtils.encode_hex (dir_path.data);
                string r_chdir = "local({ .h <- '%s'; .idx <- seq.int(1L, nchar(.h), by = 2L); .d <- rawToChar(as.raw(strtoi(substring(.h, .idx, .idx + 1L), 16L))); Encoding(.d) <- 'UTF-8'; setwd(.d) })".printf (hex_dir);
                execute_r_with_options.begin (r_chdir, null, null, 10000, false, (obj, res) => {
                    string? p;
                    execute_r_with_options.end (res, out p);
                });
            }

            if (py_initialized && py_process != null) {
                string b64_dir = GLib.Base64.encode (dir_path.data);
                string py_chdir = "import os, base64; os.chdir(base64.b64decode('%s').decode('utf-8'))".printf (b64_dir);
                execute_python_with_options.begin (py_chdir, null, null, 10000, false, (obj, res) => {
                    string? p;
                    execute_python_with_options.end (res, out p);
                });
            }

            working_directory_changed (dir_path);
        }

        /**
         * Pillar 4: Shared State & Bidirectional Execution Session
         * Evaluates code in the persistent R session. Variables, functions, and imports
         * remain alive across calls.
         */
        public async string execute_r (string code, out string? generated_plot) {
            return yield execute_r_with_options (code, null, null, 60000, true, out generated_plot);
        }

        public async string execute_r_with_options (
            string code,
            OutputLineFunc? on_output,
            GLib.Cancellable? cancellable,
            int timeout_ms,
            bool emit_global_signals,
            out string? generated_plot
        ) {
            yield lock_r ();
            try {
                return yield execute_r_internal (code, on_output, cancellable, timeout_ms, emit_global_signals, out generated_plot);
            } finally {
                unlock_r ();
            }
        }

        private async string execute_r_internal (
            string code,
            OutputLineFunc? on_output,
            GLib.Cancellable? cancellable,
            int timeout_ms,
            bool emit_global_signals,
            out string? generated_plot
        ) {
            generated_plot = null;
            ensure_r_session ();

            if (r_stdin == null || r_stdout == null) {
                return "✖ R interpreter (R/Rscript) is not available. Click 'Install Toolchain' to install R automatically.";
            }

            string plot_dir = Core.PlatformUtils.get_shared_cache_dir ("plots");
            string plot_id = GLib.Uuid.string_random ().replace ("-", "");
            string plot_file = GLib.Path.build_filename (plot_dir, @"plot_$(plot_id).png");

            string sentinel = @"__IMLADRIS_R_DONE_$(plot_id)__";
            string hex_code = Core.PlatformUtils.encode_hex (code.data);
            string payload = @"$(sentinel)|1|$(hex_code)|$(plot_file.replace ("\\", "/"))\n";

            var exec_cancel = new GLib.Cancellable ();
            ulong fwd_hid = 0;
            if (cancellable != null) {
                fwd_hid = cancellable.connect (() => {
                    exec_cancel.cancel ();
                    if (r_process != null) r_process.send_signal (2);
                });
            }
            bool timed_out = false;
            uint timeout_id = 0;
            if (timeout_ms > 0) {
                timeout_id = GLib.Timeout.add ((uint) timeout_ms, () => {
                    timed_out = true;
                    exec_cancel.cancel ();
                    if (r_process != null) r_process.send_signal (2);
                    timeout_id = 0;
                    return GLib.Source.REMOVE;
                });
            }

            try {
                size_t written;
                yield r_stdin.write_all_async (payload.data, GLib.Priority.DEFAULT, exec_cancel, out written);
                yield r_stdin.flush_async (GLib.Priority.DEFAULT, exec_cancel);

                var output_sb = new GLib.StringBuilder ();
                string? line = null;
                while (true) {
                    line = yield r_stdout.read_line_async (GLib.Priority.DEFAULT, exec_cancel);
                    if (line == null) {
                        r_initialized = false;
                        break;
                    }
                    if (line.contains (sentinel)) break;
                    output_sb.append (line + "\n");
                    if (on_output != null) on_output ("r", line, false);
                    if (emit_global_signals) session_output_received ("r", line, false);
                }

                if (GLib.FileUtils.test (plot_file, GLib.FileTest.EXISTS)) {
                    var f = GLib.File.new_for_path (plot_file);
                    try {
                        var info = f.query_info (GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
                        if (info.get_size () > 100) {
                            generated_plot = plot_file;
                            if (emit_global_signals) plot_generated (plot_file);
                        }
                    } catch (GLib.Error e) {}
                }

                return output_sb.str.strip ();
            } catch (GLib.Error e) {
                if (timed_out) {
                    return @"✖ R execution timed out after $(timeout_ms / 1000)s (sent SIGINT).";
                }
                if (e is GLib.IOError.CANCELLED) {
                    return "✖ R execution interrupted.";
                }
                r_initialized = false;
                return @"✖ R evaluation error: $(e.message)";
            } finally {
                if (timeout_id != 0) GLib.Source.remove (timeout_id);
                if (cancellable != null && fwd_hid != 0) cancellable.disconnect (fwd_hid);
            }
        }

        /**
         * Pillar 4: Shared State & Bidirectional Execution Session
         * Evaluates code in the persistent Python REPL. Variables, dataframes, and imports
         * remain alive in the workspace.
         */
        public async string execute_python (string code, out string? generated_plot) {
            return yield execute_python_with_options (code, null, null, 60000, true, out generated_plot);
        }

        public async string execute_python_with_options (
            string code,
            OutputLineFunc? on_output,
            GLib.Cancellable? cancellable,
            int timeout_ms,
            bool emit_global_signals,
            out string? generated_plot
        ) {
            yield lock_py ();
            try {
                return yield execute_python_internal (code, on_output, cancellable, timeout_ms, emit_global_signals, out generated_plot);
            } finally {
                unlock_py ();
            }
        }

        private async string execute_python_internal (
            string code,
            OutputLineFunc? on_output,
            GLib.Cancellable? cancellable,
            int timeout_ms,
            bool emit_global_signals,
            out string? generated_plot
        ) {
            generated_plot = null;
            ensure_python_session ();

            if (py_stdin == null || py_stdout == null) {
                return "✖ Python 3 interpreter is not available. Click 'Install Toolchain' to install Python automatically.";
            }

            string plot_dir = Core.PlatformUtils.get_shared_cache_dir ("plots");
            string plot_id = GLib.Uuid.string_random ().replace ("-", "");
            string plot_file = GLib.Path.build_filename (plot_dir, @"plot_$(plot_id).png");

            string b64_code = GLib.Base64.encode (code.data);
            string sentinel = @"__IMLADRIS_PY_DONE_$(plot_id)__";
            string payload = @"$(sentinel)|1|$(b64_code)|$(plot_file)\n";

            var exec_cancel = new GLib.Cancellable ();
            ulong fwd_hid = 0;
            if (cancellable != null) {
                fwd_hid = cancellable.connect (() => {
                    exec_cancel.cancel ();
                    if (py_process != null) py_process.send_signal (2);
                });
            }
            bool timed_out = false;
            uint timeout_id = 0;
            if (timeout_ms > 0) {
                timeout_id = GLib.Timeout.add ((uint) timeout_ms, () => {
                    timed_out = true;
                    exec_cancel.cancel ();
                    if (py_process != null) py_process.send_signal (2);
                    timeout_id = 0;
                    return GLib.Source.REMOVE;
                });
            }

            try {
                size_t written;
                yield py_stdin.write_all_async (payload.data, GLib.Priority.DEFAULT, exec_cancel, out written);
                yield py_stdin.flush_async (GLib.Priority.DEFAULT, exec_cancel);

                var output_sb = new GLib.StringBuilder ();
                string? line = null;
                while (true) {
                    line = yield py_stdout.read_line_async (GLib.Priority.DEFAULT, exec_cancel);
                    if (line == null) {
                        py_initialized = false;
                        break;
                    }
                    if (line.contains (sentinel)) break;
                    output_sb.append (line + "\n");
                    if (on_output != null) on_output ("python", line, false);
                    if (emit_global_signals) session_output_received ("python", line, false);
                }

                if (GLib.FileUtils.test (plot_file, GLib.FileTest.EXISTS)) {
                    var f = GLib.File.new_for_path (plot_file);
                    try {
                        var info = f.query_info (GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
                        if (info.get_size () > 100) {
                            generated_plot = plot_file;
                            if (emit_global_signals) plot_generated (plot_file);
                        }
                    } catch (GLib.Error e) {}
                }

                return output_sb.str.strip ();
            } catch (GLib.Error e) {
                if (timed_out) {
                    return @"✖ Python execution timed out after $(timeout_ms / 1000)s (sent SIGINT).";
                }
                if (e is GLib.IOError.CANCELLED) {
                    return "✖ Python execution interrupted.";
                }
                py_initialized = false;
                return @"✖ Python evaluation error: $(e.message)";
            } finally {
                if (timeout_id != 0) GLib.Source.remove (timeout_id);
                if (cancellable != null && fwd_hid != 0) cancellable.disconnect (fwd_hid);
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
            if (r_process != null && r_initialized) {
                r_process.send_signal (2); // SIGINT
            }
            if (py_process != null && py_initialized) {
                py_process.send_signal (2); // SIGINT
            }
        }

        private void ensure_r_session () {
            if (r_initialized && r_process != null) return;
            r_initialized = false;

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

                string r_driver = "options(width = 120, warn = 1); .imladris_env <- globalenv(); .imladris_con <- file('stdin', open = 'r'); while (length(.line <- readLines(.imladris_con, n = 1L, warn = FALSE)) > 0L) { if (!nzchar(.line)) next; .parts <- strsplit(.line, '|', fixed = TRUE)[[1L]]; if (length(.parts) < 4L) next; .sentinel <- .parts[1L]; .has_plot <- (.parts[2L] == '1'); .hex <- .parts[3L]; .plot_file <- paste(.parts[4L:length(.parts)], collapse = '|'); .code <- if (nzchar(.hex)) { .idx <- seq.int(1L, nchar(.hex), by = 2L); .s <- rawToChar(as.raw(strtoi(substring(.hex, .idx, .idx + 1L), 16L))); Encoding(.s) <- 'UTF-8'; .s } else ''; .drew_plot <- FALSE; tryCatch({ .exprs <- parse(text = .code); if (.has_plot) { grDevices::png(.plot_file, width = 800, height = 500, res = 120); grDevices::dev.control(displaylist = 'enable') }; tryCatch({ for (.e in .exprs) { .res <- withVisible(eval(.e, envir = .imladris_env)); if (.res$visible) print(.res$value) }; if (.has_plot && grDevices::dev.cur() > 1L) { .rec <- tryCatch(grDevices::recordPlot(), error = function(e) NULL); .drew_plot <- (!is.null(.rec) && length(.rec[[1L]]) > 0L) } }, finally = { if (.has_plot && grDevices::dev.cur() > 1L) grDevices::dev.off(); if (.has_plot && !.drew_plot && file.exists(.plot_file)) unlink(.plot_file) }) }, interrupt = function(e) { cat('Execution interrupted.\\n') }, error = function(e) { cat(sprintf('Error: %s\\n', conditionMessage(e))) }); flush.console(); cat(sprintf('\\n%s\\n', .sentinel)); flush.console() }";

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
                var spawned_r = r_process;
                spawned_r.wait_async.begin (null, (obj, res) => {
                    try { spawned_r.wait_async.end (res); } catch (GLib.Error e) {}
                    if (r_process == spawned_r) {
                        r_initialized = false;
                        r_process = null;
                    }
                });
            } catch (GLib.Error e) {
                r_initialized = false;
                GLib.warning ("Failed to launch persistent R session: %s", e.message);
            }
        }

        private void ensure_python_session () {
            if (py_initialized && py_process != null) return;
            py_initialized = false;

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
import os, sys, base64, traceback
os.environ.setdefault('MPLBACKEND', 'Agg')
try:
    import matplotlib
    matplotlib.use('Agg')
except Exception:
    pass
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
        if 'matplotlib.pyplot' in sys.modules:
            sys.modules['matplotlib.pyplot'].close('all')
        _src = base64.b64decode(_b64).decode('utf-8')
        _code = compile(_src, '<imladris-cell>', 'exec')
        exec(_code, _imladris_ns)
        if _has_plot == '1' and 'matplotlib.pyplot' in sys.modules:
            _plt = sys.modules['matplotlib.pyplot']
            if _plt.get_fignums():
                _plt.savefig(_plot_path, dpi=120, bbox_inches='tight')
    except KeyboardInterrupt:
        print('Execution interrupted.')
    except Exception:
        traceback.print_exc(file=sys.stdout)
    finally:
        if 'matplotlib.pyplot' in sys.modules:
            try:
                sys.modules['matplotlib.pyplot'].close('all')
            except Exception:
                pass
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
                var spawned_py = py_process;
                spawned_py.wait_async.begin (null, (obj, res) => {
                    try { spawned_py.wait_async.end (res); } catch (GLib.Error e) {}
                    if (py_process == spawned_py) {
                        py_initialized = false;
                        py_process = null;
                    }
                });
            } catch (GLib.Error e) {
                py_initialized = false;
                GLib.warning ("Failed to launch persistent Python session: %s", e.message);
            }
        }

        private void terminate_r () {
            if (r_process != null || r_stdin != null || r_stdout != null) {
                if (r_stdin != null) {
                    try { r_stdin.close (null); } catch (GLib.Error e) {}
                }
                if (r_stdout != null) {
                    try { r_stdout.close (null); } catch (GLib.Error e) {}
                }
                if (r_process != null) {
                    r_process.force_exit ();
                }
                r_process = null;
                r_stdin = null;
                r_stdout = null;
                r_initialized = false;
            }
        }

        private void terminate_python () {
            if (py_process != null || py_stdin != null || py_stdout != null) {
                if (py_stdin != null) {
                    try { py_stdin.close (null); } catch (GLib.Error e) {}
                }
                if (py_stdout != null) {
                    try { py_stdout.close (null); } catch (GLib.Error e) {}
                }
                if (py_process != null) {
                    py_process.force_exit ();
                }
                py_process = null;
                py_stdin = null;
                py_stdout = null;
                py_initialized = false;
            }
        }
    }
}
