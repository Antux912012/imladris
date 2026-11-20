// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris {

    public class ExecutionEngine : Object {

        private static GLib.Subprocess spawn_configured_subprocess (
            string[] argv,
            string? working_dir,
            GLib.SubprocessFlags flags
        ) throws GLib.Error {
            var launcher = new GLib.SubprocessLauncher (flags);
            string prog = argv[0];
            string? resolved_path = null;
            string? env_prefix = null;
            var source = Core.PlatformUtils.resolve_runtime (prog, working_dir, out resolved_path, out env_prefix);

            string[] final_argv;
            if (source == Core.RuntimeSource.HOST_FLATPAK_SPAWN) {
                final_argv = Core.PlatformUtils.build_host_command (argv, working_dir);
            } else if (source == Core.RuntimeSource.MANAGED_GLOBAL || source == Core.RuntimeSource.PROJECT_SANDBOX) {
                Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
                final_argv = new string[argv.length];
                final_argv[0] = (resolved_path != null) ? resolved_path : prog;
                for (int i = 1; i < argv.length; i++) final_argv[i] = argv[i];
            } else {
                final_argv = argv;
            }

            if (working_dir != null && working_dir != "") {
                launcher.set_cwd (working_dir);
            }

            return launcher.spawnv (final_argv);
        }

        private static async bool execute_with_timeout_async (
            string[] argv,
            string? working_dir,
            GLib.Cancellable? cancellable,
            uint timeout_ms,
            out string? output,
            out int exit_status,
            out bool timed_out,
            out string? error_message
        ) {
            output = null;
            exit_status = -1;
            timed_out = false;
            error_message = null;

            var linked_cancellable = new GLib.Cancellable ();
            ulong cancel_hid = 0;
            if (cancellable != null) {
                if (cancellable.is_cancelled ()) {
                    linked_cancellable.cancel ();
                } else {
                    cancel_hid = cancellable.connect (() => {
                        linked_cancellable.cancel ();
                    });
                }
            }

            uint timeout_id = 0;
            bool did_timeout = false;
            GLib.Subprocess? proc = null;
            if (timeout_ms > 0) {
                timeout_id = GLib.Timeout.add (timeout_ms, () => {
                    did_timeout = true;
                    linked_cancellable.cancel ();
                    if (proc != null) {
                        proc.force_exit ();
                    }
                    timeout_id = 0;
                    return false;
                });
            }

            try {
                proc = spawn_configured_subprocess (
                    argv, working_dir, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                yield proc.communicate_utf8_async (null, linked_cancellable, out output, null);
                timed_out = did_timeout;
                if (!did_timeout) {
                    exit_status = proc.get_exit_status ();
                    return proc.get_successful ();
                }
                return false;
            } catch (GLib.Error e) {
                timed_out = did_timeout;
                error_message = e.message;
                return false;
            } finally {
                if (timeout_id != 0) GLib.Source.remove (timeout_id);
                if (cancellable != null && cancel_hid != 0) cancellable.disconnect (cancel_hid);
            }
        }

        /**
         * Asynchronously runs a CLI command (Rscript, python3, deno, tsc, quarto)
         * and streams stdout/stderr to the active DocumentPage's console pane.
         */
        public static async void run_command_async (
            string[] argv,
            DocumentPage page,
            GLib.Cancellable? cancellable = null,
            uint timeout_ms = 120000
        ) {
            if (argv.length == 0) return;
            page.append_console_log (@"▶ Executing: $(string.joinv (" ", argv))");

            string? working_dir = null;
            if (page.current_project_dir != "") {
                working_dir = page.current_project_dir;
            } else if (page.file_location != null && page.file_location.get_parent () != null) {
                working_dir = page.file_location.get_parent ().get_path ();
            }

            string? output;
            int exit_status;
            bool timed_out;
            string? error_message;
            bool ok = yield execute_with_timeout_async (
                argv, working_dir, cancellable, timeout_ms,
                out output, out exit_status, out timed_out, out error_message
            );

            if (timed_out) {
                page.append_console_log (@"✖ Command timed out after $(timeout_ms / 1000)s.");
            } else if (error_message != null) {
                page.append_console_log (@"✖ Execution Notice: $error_message");
            } else if (output != null && output.strip ().length > 0) {
                page.append_console_log (output.strip ());
            } else if (ok) {
                page.append_console_log ("✔ Completed successfully.");
            } else {
                page.append_console_log (@"✖ Command exited with status $exit_status.");
            }
        }

        public static async string capture_command_async (string[] argv, GLib.Cancellable? cancellable = null, uint timeout_ms = 60000) {
            return yield capture_command_in_dir_async (argv, null, cancellable, timeout_ms);
        }

        public static async string capture_command_in_dir_async (
            string[] argv,
            string? working_dir,
            GLib.Cancellable? cancellable = null,
            uint timeout_ms = 60000
        ) {
            if (argv.length == 0) return "";
            string? output;
            int exit_status;
            bool timed_out;
            string? error_message;
            bool ok = yield execute_with_timeout_async (
                argv, working_dir, cancellable, timeout_ms,
                out output, out exit_status, out timed_out, out error_message
            );

            if (timed_out) {
                return @"✖ Command timed out after $(timeout_ms / 1000)s.";
            }
            if (error_message != null) {
                return @"✖ Execution Notice: $error_message";
            }
            if (output != null && output.strip ().length > 0) {
                return output.strip ();
            }
            return ok ? "✔ Completed (no output)." : @"✖ Command exited with status $exit_status.";
        }
    }
}
