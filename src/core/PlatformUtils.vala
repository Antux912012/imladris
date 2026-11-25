// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris.Core {

    public class DistroInfo : GLib.Object {
        public string id { owned get; set; default = "linux"; }
        public string name { owned get; set; default = "Linux"; }
        public string install_cmd { owned get; set; default = "brew install llama.cpp  # or build from https://github.com/ggml-org/llama.cpp"; }
    }

    public enum RuntimeSource {
        PROJECT_SANDBOX,
        MANAGED_GLOBAL,
        FLATPAK_EXTENSION,
        HOST_FLATPAK_SPAWN,
        HOST_NATIVE,
        MISSING;

        public string to_display_string () {
            switch (this) {
                case PROJECT_SANDBOX:
                    return "Project Sandbox (.imladris-env)";
                case MANAGED_GLOBAL:
                    return "Managed Global Toolchain (base-ds)";
                case FLATPAK_EXTENSION:
                    return "Flatpak SDK Extension";
                case HOST_FLATPAK_SPAWN:
                    return "Host System (via Flatpak Portal)";
                case HOST_NATIVE:
                    return "Host System (Native PATH)";
                case MISSING:
                default:
                    return "Missing / Not Installed";
            }
        }
    }

    public class PlatformUtils : GLib.Object {

        private static GLib.HashTable<string, bool> _availability_cache = null;
        private static GLib.HashTable<string, string?> _path_cache = null;
        private static GLib.Mutex _cache_mutex;

        /**
         * Returns true if Imladris is running inside a Flatpak container sandbox.
         */
        public static bool is_flatpak () {
            return HostBridge.is_flatpak ();
        }

        /**
         * Multi-Tier Runtime Resolution Hierarchy:
         * 1. Tier 1: Project-Local Sandbox (<project_dir>/.imladris-env or .venv)
         * 2. Tier 2: Managed Global Toolchain ($XDG_DATA_HOME/imladris/toolchains/mamba_root/envs/base-ds)
         * 3. Tier 3: Host System Fallback (flatpak-spawn --host or native PATH)
         * 4. Tier 4: Missing (not found)
         */
        public static RuntimeSource resolve_runtime (
            string binary_name,
            string? project_dir,
            out string? resolved_path,
            out string? env_prefix
        ) {
            resolved_path = null;
            env_prefix = null;

            // Direct executable path support
            if (binary_name.contains ("/") && GLib.FileUtils.test (binary_name, GLib.FileTest.IS_EXECUTABLE)) {
                resolved_path = binary_name;
                return RuntimeSource.HOST_NATIVE;
            }

            // Tier 1: Project-Local Sandbox
            if (project_dir != null && project_dir != "") {
                string imladris_env_bin = GLib.Path.build_filename (project_dir, ".imladris-env", "bin", binary_name);
                if (GLib.FileUtils.test (imladris_env_bin, GLib.FileTest.IS_EXECUTABLE)) {
                    resolved_path = imladris_env_bin;
                    env_prefix = GLib.Path.build_filename (project_dir, ".imladris-env");
                    return RuntimeSource.PROJECT_SANDBOX;
                }

                // Check Python virtual environment (.venv) for all binaries (python, pip, uv, pytest, ipython, jupyter, etc.)
                string venv_bin = GLib.Path.build_filename (project_dir, ".venv", "bin", binary_name);
                if (GLib.FileUtils.test (venv_bin, GLib.FileTest.IS_EXECUTABLE)) {
                    resolved_path = venv_bin;
                    env_prefix = GLib.Path.build_filename (project_dir, ".venv");
                    return RuntimeSource.PROJECT_SANDBOX;
                }

                // Check Node.js local binaries
                string node_bin = GLib.Path.build_filename (project_dir, "node_modules", ".bin", binary_name);
                if (GLib.FileUtils.test (node_bin, GLib.FileTest.IS_EXECUTABLE)) {
                    resolved_path = node_bin;
                    env_prefix = project_dir;
                    return RuntimeSource.PROJECT_SANDBOX;
                }
            }

            // Tier 2: Managed Global Toolchain
            var tm = ToolchainManager.get_default ();
            if (tm.active_python_env != tm.default_env && is_python_ecosystem_binary (binary_name)) {
                string active_py_bin = GLib.Path.build_filename (tm.active_python_env, "bin", binary_name);
                if (GLib.FileUtils.test (active_py_bin, GLib.FileTest.IS_EXECUTABLE)) {
                    resolved_path = active_py_bin;
                    env_prefix = tm.active_python_env;
                    return RuntimeSource.MANAGED_GLOBAL;
                }
            }

            string managed_bin = GLib.Path.build_filename (tm.default_env, "bin", binary_name);
            if (GLib.FileUtils.test (managed_bin, GLib.FileTest.IS_EXECUTABLE)) {
                resolved_path = managed_bin;
                env_prefix = tm.default_env;
                return RuntimeSource.MANAGED_GLOBAL;
            }

            string data_dir = GLib.Environment.get_user_data_dir ();
            string home_dir = GLib.Environment.get_home_dir ();
            string[] managed_tinytex = {
                GLib.Path.build_filename (data_dir, "TinyTeX", "bin", "x86_64-linux", binary_name),
                GLib.Path.build_filename (data_dir, "TinyTeX", "bin", "aarch64-linux", binary_name),
                GLib.Path.build_filename (home_dir, ".TinyTeX", "bin", "x86_64-linux", binary_name),
                GLib.Path.build_filename (home_dir, ".TinyTeX", "bin", "aarch64-linux", binary_name)
            };
            foreach (string tt_bin in managed_tinytex) {
                if (GLib.FileUtils.test (tt_bin, GLib.FileTest.IS_EXECUTABLE)) {
                    resolved_path = tt_bin;
                    return RuntimeSource.MANAGED_GLOBAL;
                }
            }

            // Tier 2.5: Flatpak SDK Extension /app/toolchain, /app/bin, or /usr/lib/sdk/texlive
            // Strictly in-sandbox: never resolve or spawn host binaries from Flatpak.
            if (is_flatpak ()) {
                string[] ext_bins = {
                    GLib.Path.build_filename ("/app/toolchain/bin", binary_name),
                    GLib.Path.build_filename ("/usr/lib/sdk/texlive/bin/x86_64-linux", binary_name),
                    GLib.Path.build_filename ("/usr/lib/sdk/texlive/bin/aarch64-linux", binary_name),
                    GLib.Path.build_filename ("/app/bin", binary_name)
                };
                foreach (string ext_bin in ext_bins) {
                    if (GLib.FileUtils.test (ext_bin, GLib.FileTest.IS_EXECUTABLE)) {
                        resolved_path = ext_bin;
                        return RuntimeSource.FLATPAK_EXTENSION;
                    }
                }
                return RuntimeSource.MISSING;
            }

            // Tier 3: Native / Container System Environment Fallback
            string? local_path = GLib.Environment.find_program_in_path (binary_name);
            if (local_path != null) {
                resolved_path = local_path;
                return RuntimeSource.HOST_NATIVE;
            }

            // Tier 4: Missing
            return RuntimeSource.MISSING;
        }

        private static bool is_python_ecosystem_binary (string binary_name) {
            switch (binary_name) {
                case "python":
                case "python3":
                case "pip":
                case "pip3":
                case "uv":
                case "ipython":
                case "jupyter":
                case "pytest":
                    return true;
                default:
                    return false;
            }
        }

        /**
         * Injects environment variables for a micromamba / conda-managed prefix.
         * Sets PATH, CONDA_PREFIX, PKG_CONFIG_PATH, R_HOME, QUARTO_PYTHON, and QUARTO_R.
         */
        public static void configure_managed_env (GLib.SubprocessLauncher launcher, string? env_prefix) {
            bool has_prefix = (env_prefix != null && env_prefix != "");
            string? bin_dir = has_prefix ? GLib.Path.build_filename (env_prefix, "bin") : null;
            string? lib_dir = has_prefix ? GLib.Path.build_filename (env_prefix, "lib") : null;
            string? pkg_dir = has_prefix ? GLib.Path.build_filename (lib_dir, "pkgconfig") : null;
            string? r_home = has_prefix ? GLib.Path.build_filename (lib_dir, "R") : null;

            string? current_path = GLib.Environment.get_variable ("PATH");
            var path_parts = new GLib.GenericArray<string> ();
            if (bin_dir != null) {
                path_parts.add (bin_dir);
            }

            string home_dir = GLib.Environment.get_home_dir ();
            string data_dir = GLib.Environment.get_user_data_dir ();
            string[] tinytex_candidates = {
                GLib.Path.build_filename (data_dir, "TinyTeX", "bin", "x86_64-linux"),
                GLib.Path.build_filename (data_dir, "TinyTeX", "bin", "aarch64-linux"),
                GLib.Path.build_filename (home_dir, ".TinyTeX", "bin", "x86_64-linux"),
                GLib.Path.build_filename (home_dir, ".TinyTeX", "bin", "aarch64-linux"),
                GLib.Path.build_filename (home_dir, "TinyTeX", "bin", "x86_64-linux"),
                GLib.Path.build_filename (home_dir, "TinyTeX", "bin", "aarch64-linux")
            };
            foreach (string tt_bin in tinytex_candidates) {
                if (GLib.FileUtils.test (tt_bin, GLib.FileTest.IS_DIR)) {
                    path_parts.add (tt_bin);
                }
            }

            if (current_path != null && current_path != "") {
                path_parts.add (current_path);
            }
            string[] path_arr = new string[path_parts.length];
            for (int i = 0; i < path_parts.length; i++) {
                path_arr[i] = path_parts[i];
            }
            string path_val = string.joinv (":", path_arr);

            launcher.setenv ("PATH", path_val, true);
            if (has_prefix) {
                bool is_venv = GLib.Path.get_basename (env_prefix) == ".venv";
                if (is_venv) {
                    launcher.setenv ("VIRTUAL_ENV", env_prefix, true);
                } else {
                    launcher.setenv ("CONDA_PREFIX", env_prefix, true);
                    if (GLib.FileUtils.test (pkg_dir, GLib.FileTest.IS_DIR)) {
                        launcher.setenv ("PKG_CONFIG_PATH", pkg_dir, true);
                    }
                    if (GLib.FileUtils.test (r_home, GLib.FileTest.IS_DIR)) {
                        launcher.setenv ("R_HOME", r_home, true);
                    }
                    string r_bin = GLib.Path.build_filename (bin_dir, "R");
                    if (GLib.FileUtils.test (r_bin, GLib.FileTest.EXISTS)) {
                        launcher.setenv ("QUARTO_R", r_bin, true);
                    }
                }

                string py_bin = GLib.Path.build_filename (bin_dir, "python3");
                if (GLib.FileUtils.test (py_bin, GLib.FileTest.EXISTS)) {
                    launcher.setenv ("QUARTO_PYTHON", py_bin, true);
                }
            }

            // Override stale conda activate.d Quarto paths (e.g. build-machine QUARTO_DENO_DOM)
            string? quarto_prefix = null;
            if (has_prefix && (
                    GLib.FileUtils.test (GLib.Path.build_filename (env_prefix, "lib", "deno_dom.so"), GLib.FileTest.EXISTS) ||
                    GLib.FileUtils.test (GLib.Path.build_filename (env_prefix, "share", "quarto"), GLib.FileTest.IS_DIR))) {
                quarto_prefix = env_prefix;
            } else {
                string managed_default = ToolchainManager.get_default ().default_env;
                if (GLib.FileUtils.test (managed_default, GLib.FileTest.IS_DIR)) {
                    quarto_prefix = managed_default;
                }
            }

            if (quarto_prefix != null) {
                string deno_dom = GLib.Path.build_filename (quarto_prefix, "lib", "deno_dom.so");
                if (GLib.FileUtils.test (deno_dom, GLib.FileTest.EXISTS)) {
                    launcher.setenv ("QUARTO_DENO_DOM", deno_dom, true);
                }
                string q_share = GLib.Path.build_filename (quarto_prefix, "share", "quarto");
                if (GLib.FileUtils.test (q_share, GLib.FileTest.IS_DIR)) {
                    launcher.setenv ("QUARTO_SHARE_PATH", q_share, true);
                }
                string q_bin = GLib.Path.build_filename (quarto_prefix, "bin");
                if (GLib.FileUtils.test (GLib.Path.build_filename (q_bin, "quarto"), GLib.FileTest.IS_EXECUTABLE)) {
                    launcher.setenv ("QUARTO_BIN_PATH", q_bin, true);
                }
                string deno_bin = GLib.Path.build_filename (q_bin, "deno");
                if (GLib.FileUtils.test (deno_bin, GLib.FileTest.IS_EXECUTABLE)) {
                    launcher.setenv ("QUARTO_DENO", deno_bin, true);
                }
            }

            inject_galaxy_credentials (launcher);
        }

        private static Secret.Schema? _galaxy_secret_schema = null;

        public static Secret.Schema get_galaxy_secret_schema () {
            _cache_mutex.lock ();
            if (_galaxy_secret_schema == null) {
                _galaxy_secret_schema = new Secret.Schema (
                    "io.github.Antux912012.Imladris.GalaxyApiKey",
                    Secret.SchemaFlags.NONE,
                    "server_url", Secret.SchemaAttributeType.STRING
                );
            }
            var schema = _galaxy_secret_schema;
            _cache_mutex.unlock ();
            return schema;
        }

        /**
         * Injects cached Galaxy API credentials into child subprocess environment.
         * Ensures child processes (quarto render, Rscript, python3) access remote
         * Galaxy datasets without hardcoding secrets in manuscripts.
         */
        public static void inject_galaxy_credentials (GLib.SubprocessLauncher launcher) {
            string? cached_key = GLib.Environment.get_variable ("GALAXY_API_KEY");
            string? cached_url = GLib.Environment.get_variable ("GALAXY_SERVER_URL");

            if (cached_key == null || cached_key.length == 0) {
                try {
                    string server = (cached_url != null && cached_url.length > 0) ? cached_url : "https://usegalaxy.eu";
                    cached_key = Secret.password_lookup_sync (
                        get_galaxy_secret_schema (),
                        null,
                        "server_url", server
                    );
                } catch (GLib.Error e) {}
            }

            if (cached_key != null && cached_key.length > 0) {
                launcher.setenv ("GALAXY_API_KEY", cached_key, true);
            }
            if (cached_url != null && cached_url.length > 0) {
                launcher.setenv ("GALAXY_SERVER_URL", cached_url, true);
            }
        }

        /**
         * Checks if a program is available in any tier (Project sandbox, Managed global, or Host).
         */
        public static bool is_program_available (string program, string? project_dir = null) {
            string cache_key = (project_dir != null && project_dir != "") ? @"$program@$project_dir" : program;
            _cache_mutex.lock ();
            init_caches ();
            if (_availability_cache.contains (cache_key)) {
                bool cached = _availability_cache.lookup (cache_key);
                _cache_mutex.unlock ();
                return cached;
            }
            _cache_mutex.unlock ();

            string? resolved = null;
            string? env_pfx = null;
            RuntimeSource src = resolve_runtime (program, project_dir, out resolved, out env_pfx);
            bool available = (src != RuntimeSource.MISSING);

            _cache_mutex.lock ();
            init_caches ();
            _availability_cache.insert (cache_key, available);
            _cache_mutex.unlock ();
            return available;
        }

        /**
         * Returns the resolved binary path for a program according to the 4-tier resolution hierarchy.
         */
        public static string? find_program (string program, string? project_dir = null) {
            string cache_key = (project_dir != null && project_dir != "") ? @"$program@$project_dir" : program;
            _cache_mutex.lock ();
            init_caches ();
            if (_path_cache.contains (cache_key)) {
                string? cached = _path_cache.lookup (cache_key);
                _cache_mutex.unlock ();
                return cached;
            }
            _cache_mutex.unlock ();

            string? resolved = null;
            string? env_pfx = null;
            resolve_runtime (program, project_dir, out resolved, out env_pfx);

            _cache_mutex.lock ();
            init_caches ();
            _path_cache.insert (cache_key, resolved);
            _cache_mutex.unlock ();
            return resolved;
        }

        /**
         * Checks if R or Rscript is available in any tier.
         */
        public static bool is_r_available (string? project_dir = null) {
            return is_program_available ("R", project_dir) || is_program_available ("Rscript", project_dir);
        }

        /**
         * Builds a command that routes through the host system via flatpak-spawn
         * if running inside Flatpak.
         */
        public static string[] build_host_command (string[] argv, string? working_dir = null) {
            return build_host_command_with_env (argv, working_dir, null);
        }

        public static string[] build_host_command_with_env (
            string[] argv,
            string? working_dir = null,
            string[]? env_vars = null
        ) {
            return HostBridge.wrap_command (argv, working_dir, env_vars);
        }

        /**
         * Builds runtime command argv according to the 4-tier hierarchy.
         */
        public static string[] build_runtime_command (
            string binary_name,
            string[] sub_args,
            string? project_dir,
            out RuntimeSource source,
            out string? env_prefix
        ) {
            string? resolved_path = null;
            source = resolve_runtime (binary_name, project_dir, out resolved_path, out env_prefix);

            if (source == RuntimeSource.HOST_FLATPAK_SPAWN) {
                var full_argv = new string[1 + sub_args.length];
                full_argv[0] = binary_name;
                for (int i = 0; i < sub_args.length; i++) {
                    full_argv[i + 1] = sub_args[i];
                }
                return build_host_command (full_argv, project_dir);
            }

            string exe = (resolved_path != null) ? resolved_path : binary_name;
            var result = new string[1 + sub_args.length];
            result[0] = exe;
            for (int i = 0; i < sub_args.length; i++) {
                result[i + 1] = sub_args[i];
            }
            return result;
        }

        /**
         * Returns a host-accessible shared directory for cache, plots, and temporary files.
         * Creates directories with secure 0700 permissions.
         */
        public static string get_shared_cache_dir (string subdir = "") {
            string cache_dir = GLib.Path.build_filename (GLib.Environment.get_user_cache_dir (), "imladris");
            if (subdir != "") {
                cache_dir = GLib.Path.build_filename (cache_dir, subdir);
            }
            GLib.DirUtils.create_with_parents (cache_dir, 0700);
            return cache_dir;
        }

        /**
         * Clears runtime caches when a new toolchain is installed or removed.
         */
        public static void clear_caches () {
            _cache_mutex.lock ();
            if (_availability_cache != null) {
                _availability_cache.remove_all ();
            }
            if (_path_cache != null) {
                _path_cache.remove_all ();
            }
            _cache_mutex.unlock ();
        }

        private static void init_caches () {
            if (_availability_cache == null) {
                _availability_cache = new GLib.HashTable<string, bool> (GLib.str_hash, GLib.str_equal);
            }
            if (_path_cache == null) {
                _path_cache = new GLib.HashTable<string, string?> (GLib.str_hash, GLib.str_equal);
            }
        }

        public static bool check_host_program_available (string program) {
            return resolve_host_program_path (program) != null;
        }

        private static string? resolve_host_program_path (string program) {
            try {
                string[] argv = HostBridge.wrap_command ({ "sh", "-c", "command -v \"$1\"", "_", program }, null, null, true);
                var proc = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string? output = null;
                proc.communicate_utf8 (null, null, out output, null);
                if (output != null && output.strip ().length > 0) {
                    return output.strip ();
                }
            } catch (GLib.Error e) {}
            return null;
        }

        /**
         * Detects the running Linux distribution from /run/host/os-release or /etc/os-release.
         * Returns the identified distro name and the exact package installation command for llama.cpp.
         */
        public static DistroInfo detect_linux_distro () {
            var info = new DistroInfo ();

            string[] candidates = {
                "/run/host/os-release",
                "/run/host/usr/lib/os-release",
                "/etc/os-release",
                "/usr/lib/os-release"
            };

            string? os_release_file = null;
            foreach (var path in candidates) {
                if (GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
                    os_release_file = path;
                    break;
                }
            }

            string raw_id = "";
            string raw_id_like = "";
            string raw_name = "";
            string raw_pretty_name = "";

            if (os_release_file != null) {
                try {
                    string content;
                    GLib.FileUtils.get_contents (os_release_file, out content);
                    string[] lines = content.split ("\n");
                    foreach (var line in lines) {
                        string trimmed = line.strip ();
                        if (trimmed.has_prefix ("ID=")) {
                            raw_id = strip_quotes (trimmed.substring (3));
                        } else if (trimmed.has_prefix ("ID_LIKE=")) {
                            raw_id_like = strip_quotes (trimmed.substring (8));
                        } else if (trimmed.has_prefix ("PRETTY_NAME=")) {
                            raw_pretty_name = strip_quotes (trimmed.substring (12));
                        } else if (trimmed.has_prefix ("NAME=")) {
                            raw_name = strip_quotes (trimmed.substring (5));
                        }
                    }
                } catch (GLib.Error e) {
                    // Fall back to default
                }
            }

            string combined = (raw_id + " " + raw_id_like + " " + raw_name + " " + raw_pretty_name).down ();

            if (combined.contains ("ubuntu") || combined.contains ("debian") || combined.contains ("mint") || combined.contains ("pop") || combined.contains ("elementary") || combined.contains ("zorin")) {
                info.id = "debian";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : "Debian / Ubuntu";
                info.install_cmd = "sudo apt install llama.cpp || sudo apt install llama-cpp";
            } else if (combined.contains ("fedora") || combined.contains ("rhel") || combined.contains ("centos") || combined.contains ("rocky") || combined.contains ("almalinux")) {
                info.id = "fedora";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : "Fedora / RHEL";
                info.install_cmd = "sudo dnf install llama-cpp";
            } else if (combined.contains ("opensuse") || combined.contains ("suse")) {
                info.id = "opensuse";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : "openSUSE";
                info.install_cmd = "sudo zypper install llama-cpp";
            } else if (combined.contains ("omarchy")) {
                info.id = "omarchy";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : "Omarchy";
                info.install_cmd = "omarchy pkg add llama.cpp || yay -S llama.cpp";
            } else if (combined.contains ("arch") || combined.contains ("manjaro") || combined.contains ("endeavouros") || combined.contains ("cachyos") || combined.contains ("artix")) {
                info.id = "arch";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : "Arch Linux";
                info.install_cmd = "sudo pacman -S llama.cpp || yay -S llama.cpp";
            } else if (combined.contains ("solus")) {
                info.id = "solus";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : "Solus";
                info.install_cmd = "sudo eopkg install llama.cpp";
            } else if (combined.contains ("nixos")) {
                info.id = "nixos";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : "NixOS";
                info.install_cmd = "nix-env -iA nixpkgs.llama-cpp";
            } else {
                info.id = "linux";
                info.name = (raw_pretty_name.length > 0) ? raw_pretty_name : (raw_name.length > 0 ? raw_name : "Linux");
                info.install_cmd = "brew install llama.cpp  # or build from https://github.com/ggml-org/llama.cpp";
            }

            return info;
        }

        /**
         * Safely converts GLib.Bytes (which is NOT guaranteed to be NUL-terminated)
         * into a NUL-terminated Vala string, preventing heap buffer over-reads.
         */
        public static string bytes_to_string (GLib.Bytes? bytes) {
            if (bytes == null) return "";
            return data_to_string (bytes.get_data ());
        }

        /**
         * Safely converts a raw uint8[] byte buffer into a NUL-terminated Vala string.
         */
        public static string data_to_string (uint8[]? data) {
            if (data == null || data.length == 0) return "";
            uint8[] buf = new uint8[data.length + 1];
            GLib.Memory.copy (buf, data, data.length);
            buf[data.length] = 0;
            return (string) buf;
        }

        /**
         * Recursively deletes a directory and its contents, closing enumerators cleanly.
         */
        public static void delete_directory_recursive (GLib.File dir) {
            if (!dir.query_exists ()) {
                return;
            }
            try {
                var enumerator = dir.enumerate_children (
                    GLib.FileAttribute.STANDARD_NAME + "," + GLib.FileAttribute.STANDARD_TYPE,
                    GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS
                );
                try {
                    GLib.FileInfo? info = null;
                    while ((info = enumerator.next_file ()) != null) {
                        var child = dir.get_child (info.get_name ());
                        if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                            delete_directory_recursive (child);
                        } else {
                            child.delete ();
                        }
                    }
                } finally {
                    try {
                        enumerator.close ();
                    } catch (GLib.Error e) {
                        // Ignore close errors
                    }
                }
                dir.delete ();
            } catch (GLib.Error e) {
                GLib.debug ("delete_directory_recursive (%s): %s", dir.get_path () ?? "", e.message);
            }
        }

        private static string strip_quotes (string s) {
            string res = s.strip ();
            if (res.has_prefix ("\"") && res.has_suffix ("\"") && res.length >= 2) {
                return res.substring (1, res.length - 2);
            }
            if (res.has_prefix ("'") && res.has_suffix ("'") && res.length >= 2) {
                return res.substring (1, res.length - 2);
            }
            return res;
        }

        /**
         * Encodes raw bytes as lowercase hexadecimal.
         */
        public static string encode_hex (uint8[] data) {
            var sb = new GLib.StringBuilder ();
            for (int i = 0; i < data.length; i++) {
                sb.append_printf ("%02x", data[i]);
            }
            return sb.str;
        }

        /**
         * Escapes a string for safe inclusion inside a double-quoted string literal.
         */
        public static string escape_string_literal (string s) {
            return s.replace ("\\", "\\\\")
                    .replace ("\"", "\\\"")
                    .replace ("\n", "\\n")
                    .replace ("\r", "\\r");
        }

        /**
         * Replaces CR/LF characters with spaces for single-line text contexts.
         */
        public static string strip_newlines (string s) {
            return s.replace ("\r", " ").replace ("\n", " ");
        }

        /**
         * Sanitizes an arbitrary identifier into a lowercase alphanumeric/hyphen chunk label.
         */
        public static string sanitize_chunk_label (string s, string fallback = "chunk") {
            var sb = new GLib.StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c.isalnum () || c == '-') {
                    sb.append_c (c.tolower ());
                } else if (c == '_') {
                    sb.append_c ('-');
                }
            }
            return sb.str.length > 0 ? sb.str : fallback;
        }
    }
}
