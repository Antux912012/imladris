// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Core {

    /**
     * Layer 1: HostBridge
     *
     * Single abstraction around GLib.SubprocessLauncher that transparently
     * delegates host execution through `flatpak-spawn --host --watch-bus`
     * when running inside a Flatpak sandbox, while keeping native execution direct.
     */
    public class HostBridge : GLib.Object {

        private static bool? _is_flatpak_cached = null;
        public static bool prefer_host_runtimes { get; set; default = false; }

        /**
         * Detects once at startup whether Imladris is running inside Flatpak.
         */
        public static bool is_flatpak () {
            if (_is_flatpak_cached == null) {
                bool info_exists = FileUtils.test ("/.flatpak-info", FileTest.EXISTS);
                bool env_set = Environment.get_variable ("FLATPAK_ID") != null;
                _is_flatpak_cached = info_exists || env_set;
            }
            return _is_flatpak_cached;
        }

        /**
         * Wraps a command for host execution via `flatpak-spawn --host --watch-bus`
         * when running inside Flatpak (or when `force_flatpak` is true for testing).
         */
        public static string[] wrap_command (
            string[] argv,
            string? project_dir = null,
            string[]? env_vars = null,
            bool? force_flatpak = null
        ) {
            bool use_flatpak = force_flatpak ?? is_flatpak ();
            if (!use_flatpak || argv.length == 0) {
                return argv;
            }

            var cmd = new GenericArray<string> ();
            cmd.add ("flatpak-spawn");
            cmd.add ("--host");
            cmd.add ("--watch-bus");

            if (project_dir != null && project_dir.length > 0 &&
                !project_dir.has_prefix ("/app/") && !project_dir.has_prefix ("/run/build/")) {
                cmd.add ("--directory=" + project_dir);
            }

            if (env_vars != null) {
                foreach (string kv in env_vars) {
                    if (kv != null && kv.contains ("=")) {
                        cmd.add ("--env=" + kv);
                    }
                }
            }

            string[] proxy_vars = {
                "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY",
                "https_proxy", "http_proxy", "no_proxy",
                "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE"
            };
            foreach (string var_name in proxy_vars) {
                string? val = Environment.get_variable (var_name);
                if (val != null && val.length > 0) {
                    cmd.add (@"--env=$var_name=$val");
                }
            }

            cmd.add ("--");
            for (int i = 0; i < argv.length; i++) {
                cmd.add (argv[i]);
            }

            string[] result = new string[cmd.length];
            for (int i = 0; i < cmd.length; i++) {
                result[i] = cmd[i];
            }
            return result;
        }

        /**
         * Spawns a subprocess, routing through `flatpak-spawn --host --watch-bus`
         * inside Flatpak or executing directly on native hosts.
         */
        public static Subprocess spawn (
            string[] argv,
            string? project_dir = null,
            string[]? env_vars = null,
            SubprocessFlags flags = SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        ) throws GLib.Error {
            var launcher = new SubprocessLauncher (flags);
            string[] final_argv;

            if (is_flatpak ()) {
                final_argv = wrap_command (argv, project_dir, env_vars, true);
            } else {
                if (project_dir != null && project_dir.length > 0 &&
                    FileUtils.test (project_dir, FileTest.IS_DIR)) {
                    launcher.set_cwd (project_dir);
                }
                if (env_vars != null) {
                    foreach (string kv in env_vars) {
                        int eq = kv.index_of_char ('=');
                        if (eq > 0) {
                            string k = kv.substring (0, eq);
                            string v = kv.substring (eq + 1);
                            launcher.setenv (k, v, true);
                        }
                    }
                }
                final_argv = argv;
            }

            return launcher.spawnv (final_argv);
        }

        /**
         * Runs a command asynchronously and captures stdout.
         */
        public static async string run_capture_async (
            string[] argv,
            string? project_dir = null,
            string[]? env_vars = null,
            Cancellable? cancellable = null
        ) throws GLib.Error {
            var proc = spawn (
                argv,
                project_dir,
                env_vars,
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
            );
            string stdout_buf;
            string stderr_buf;
            yield proc.communicate_utf8_async (null, cancellable, out stdout_buf, out stderr_buf);
            return stdout_buf ?? "";
        }
    }
}
