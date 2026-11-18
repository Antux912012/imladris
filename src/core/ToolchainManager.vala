// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Core {

    public class ToolchainManager : GLib.Object {

        private static ToolchainManager? _instance = null;

        public static ToolchainManager get_default () {
            if (_instance == null) {
                _instance = new ToolchainManager ();
            }
            return _instance;
        }

        public signal void progress_changed (string step, double fraction, string detail);
        public signal void log_output (string line);
        public signal void location_changed (string path);

        private string _base_dir;
        public string base_dir { get { return _base_dir; } }

        private string _bin_dir;
        public string bin_dir { get { return _bin_dir; } }

        private string _mamba_bin;
        public string mamba_bin { get { return _mamba_bin; } }

        private string _mamba_root;
        public string mamba_root { get { return _mamba_root; } }

        private string _default_env;
        public string default_env { get { return _default_env; } }

        private string _state_file;
        public string state_file { get { return _state_file; } }

        public ToolchainManager () {
            _base_dir = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "imladris", "toolchains");
            load_configured_base_dir ();
            update_paths ();
        }

        private void update_paths () {
            _bin_dir = GLib.Path.build_filename (_base_dir, "bin");
            _mamba_bin = GLib.Path.build_filename (_bin_dir, "micromamba");
            _mamba_root = GLib.Path.build_filename (_base_dir, "mamba_root");
            _default_env = GLib.Path.build_filename (_mamba_root, "envs", "base-ds");
            _state_file = GLib.Path.build_filename (_base_dir, "state.json");
        }

        private string get_location_settings_path () {
            return GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "imladris", "toolchain.ini");
        }

        private void load_configured_base_dir () {
            string settings_path = get_location_settings_path ();
            if (!GLib.FileUtils.test (settings_path, GLib.FileTest.EXISTS)) {
                return;
            }
            try {
                string contents;
                GLib.FileUtils.get_contents (settings_path, out contents);
                string configured = contents.strip ();
                if (is_valid_base_dir_path (configured)) {
                    _base_dir = GLib.File.new_for_path (configured).get_path () ?? configured;
                } else {
                    warning ("Ignoring invalid configured toolchain directory: %s", configured);
                }
            } catch (GLib.Error e) {
                warning ("Could not read the configured toolchain directory: %s", e.message);
            }
        }

        public static bool is_valid_base_dir_path (string path) {
            string candidate = path.strip ();
            return candidate.length > 0 && GLib.Path.is_absolute (candidate) && candidate != "/";
        }

        public void set_base_dir (string path) throws GLib.Error {
            string candidate = path.strip ();
            if (!is_valid_base_dir_path (candidate)) {
                throw new GLib.IOError.INVALID_ARGUMENT ("Choose an absolute folder other than the filesystem root.");
            }
            candidate = GLib.File.new_for_path (candidate).get_path () ?? candidate;
            if (GLib.FileUtils.test (candidate, GLib.FileTest.EXISTS) &&
                !GLib.FileUtils.test (candidate, GLib.FileTest.IS_DIR)) {
                throw new GLib.IOError.NOT_DIRECTORY ("The selected toolchain path is not a folder.");
            }

            string writable_parent = candidate;
            while (!GLib.FileUtils.test (writable_parent, GLib.FileTest.EXISTS)) {
                string parent = GLib.Path.get_dirname (writable_parent);
                if (parent == writable_parent) {
                    break;
                }
                writable_parent = parent;
            }
            bool parent_writable = false;
            try {
                var info = GLib.File.new_for_path (writable_parent).query_info (
                    GLib.FileAttribute.ACCESS_CAN_WRITE, GLib.FileQueryInfoFlags.NONE
                );
                parent_writable = info.get_attribute_boolean (GLib.FileAttribute.ACCESS_CAN_WRITE);
            } catch (GLib.Error e) {
                warning ("Could not check toolchain folder permissions: %s", e.message);
            }
            if (!GLib.FileUtils.test (writable_parent, GLib.FileTest.IS_DIR) || !parent_writable) {
                throw new GLib.IOError.PERMISSION_DENIED ("The selected folder or its parent is not writable.");
            }

            string settings_path = get_location_settings_path ();
            GLib.DirUtils.create_with_parents (GLib.Path.get_dirname (settings_path), 0755);
            if (!GLib.FileUtils.set_contents (settings_path, candidate + "\n")) {
                throw new GLib.IOError.FAILED ("Could not save the selected toolchain folder.");
            }
            GLib.FileUtils.chmod (settings_path, 0600);
            _base_dir = candidate;
            update_paths ();
            location_changed (_base_dir);
        }

        private static string? cached_arch = null;

        /**
         * Returns the platform architecture string expected by micromamba APIs.
         */
        public static string get_platform_arch () {
            if (cached_arch != null) {
                return cached_arch;
            }
            try {
                string output;
                GLib.Process.spawn_command_line_sync ("uname -m", out output, null, null);
                string arch = output.strip ();
                if (arch == "aarch64" || arch == "arm64") {
                    cached_arch = "linux-aarch64";
                    return cached_arch;
                }
            } catch (GLib.Error e) {}
            cached_arch = "linux-64";
            return cached_arch;
        }

        public bool is_micromamba_installed () {
            return GLib.FileUtils.test (mamba_bin, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool is_base_environment_installed () {
            return has_r () || has_python () || has_quarto () || has_node_typescript () ||
                has_tectonic () || has_completed_setup_state ();
        }

        public bool has_r () {
            string r_path = GLib.Path.build_filename (default_env, "bin", "R");
            return GLib.FileUtils.test (r_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_python () {
            string py_path = GLib.Path.build_filename (default_env, "bin", "python3");
            return GLib.FileUtils.test (py_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_quarto () {
            string q_path = GLib.Path.build_filename (default_env, "bin", "quarto");
            return GLib.FileUtils.test (q_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_node_typescript () {
            string node_path = GLib.Path.build_filename (default_env, "bin", "node");
            string tsc_path = GLib.Path.build_filename (default_env, "bin", "tsc");
            return GLib.FileUtils.test (node_path, GLib.FileTest.IS_EXECUTABLE) &&
                GLib.FileUtils.test (tsc_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_tectonic () {
            string tex_path = GLib.Path.build_filename (default_env, "bin", "tectonic");
            return GLib.FileUtils.test (tex_path, GLib.FileTest.IS_EXECUTABLE);
        }

        private bool has_completed_setup_state () {
            if (!GLib.FileUtils.test (state_file, GLib.FileTest.EXISTS)) {
                return false;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (state_file);
                var root = parser.get_root ();
                return root != null && root.get_node_type () == Json.NodeType.OBJECT &&
                    root.get_object ().has_member ("setup_complete") &&
                    root.get_object ().get_boolean_member ("setup_complete");
            } catch (GLib.Error e) {
                warning ("Could not read toolchain setup state: %s", e.message);
                return false;
            }
        }

        /**
         * Ensures the micromamba binary exists at $XDG_DATA_HOME/imladris/toolchains/bin/micromamba.
         * Downloads and extracts the official static binary if absent.
         */
        public async bool ensure_micromamba_async () {
            if (is_micromamba_installed ()) {
                return true;
            }

            progress_changed ("Preparing toolchain directory...", 0.05, "Creating directories");
            GLib.DirUtils.create_with_parents (bin_dir, 0755);
            GLib.DirUtils.create_with_parents (mamba_root, 0755);

            string arch = get_platform_arch ();
            string url = @"https://micro.mamba.pm/api/micromamba/$arch/latest";

            log_output (@"▶ Downloading micromamba ($arch) from $url...");
            progress_changed ("Downloading micromamba...", 0.15, url);

            string tmp_tar = Path.build_filename (Environment.get_tmp_dir (), @"imladris-micromamba-$(GLib.Random.next_int ()).tar.bz2");
            try {
                // Download tarball directly without sh -c shell pipeline
                string[] dl_argv = { "curl", "-fsSL", "-o", tmp_tar, url };
                var dl_proc = new GLib.Subprocess.newv (dl_argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                var dl_err = new GLib.DataInputStream (dl_proc.get_stderr_pipe ());
                read_stream_to_log.begin (dl_err);
                yield dl_proc.wait_check_async ();

                // Compute SHA-256 digest of downloaded archive for auditability
                uint8[] tar_bytes;
                GLib.FileUtils.get_data (tmp_tar, out tar_bytes);
                if (tar_bytes.length == 0) {
                    throw new GLib.IOError.FAILED ("Downloaded micromamba archive is empty.");
                }
                string sha256 = GLib.Checksum.compute_for_data (GLib.ChecksumType.SHA256, tar_bytes);
                log_output (@"✔ Downloaded micromamba archive (SHA-256: $sha256)");

                // Extract only bin/micromamba directly with tar (no shell)
                string[] tar_argv = { "tar", "-xvjf", tmp_tar, "-C", bin_dir, "--strip-components=1", "bin/micromamba" };
                var proc = new GLib.Subprocess.newv (tar_argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                var stdout_stream = new GLib.DataInputStream (proc.get_stdout_pipe ());
                var stderr_stream = new GLib.DataInputStream (proc.get_stderr_pipe ());

                // Read output concurrently
                read_stream_to_log.begin (stdout_stream);
                read_stream_to_log.begin (stderr_stream);

                yield proc.wait_check_async ();

                if (is_micromamba_installed ()) {
                    GLib.FileUtils.chmod (mamba_bin, 0755);
                    log_output ("✔ micromamba binary installed successfully: " + mamba_bin);
                    progress_changed ("micromamba engine ready", 0.30, mamba_bin);
                    return true;
                } else {
                    log_output ("✖ micromamba binary not found after extraction.");
                    return false;
                }
            } catch (GLib.Error e) {
                log_output (@"✖ Failed to download or extract micromamba: $(e.message)");
                return false;
            } finally {
                GLib.FileUtils.unlink (tmp_tar);
            }
        }

        /**
         * Installs or updates the shared Data Science environment (base-ds) using micromamba.
         */
        public async bool create_or_update_base_environment_async (
            bool install_r = true,
            bool install_python = true,
            bool install_quarto = true,
            bool install_tidyverse = true,
            bool install_node_ts = false,
            bool install_tex = false
        ) {
            var pkgs = new GLib.GenericArray<string> ();

            if (install_python) {
                pkgs.add ("python=3.12");
                pkgs.add ("pip");
                pkgs.add ("ipykernel");
                pkgs.add ("jupyter_client");
                pkgs.add ("uv");
            }

            if (install_r) {
                pkgs.add ("r-base=4.4");
                pkgs.add ("r-irkernel");
                pkgs.add ("r-remotes");
                pkgs.add ("r-pak");
                pkgs.add ("r-rmarkdown");
                pkgs.add ("r-knitr");
                pkgs.add ("r-shiny");
                pkgs.add ("compilers");
                pkgs.add ("make");
                pkgs.add ("pkg-config");
                pkgs.add ("libcurl");
                pkgs.add ("openssl");
                pkgs.add ("libxml2");

                if (install_tidyverse) {
                    pkgs.add ("r-tidyverse");
                    pkgs.add ("r-data.table");
                }
            }

            if (install_quarto) {
                pkgs.add ("quarto");
                pkgs.add ("typst");
                pkgs.add ("pandoc");
            }

            if (install_node_ts) {
                pkgs.add ("nodejs");
                pkgs.add ("typescript");
            }

            if (install_tex) {
                pkgs.add ("tectonic");
            }

            if (pkgs.length == 0) {
                log_output ("ℹ No components selected for installation.");
                if (!save_state ()) {
                    progress_changed ("Could not save toolchain setup state", 0.0, state_file);
                    return false;
                }
                progress_changed ("No toolchain components selected", 1.0, "You can install runtimes later from Preferences.");
                return true;
            }

            bool mamba_ok = yield ensure_micromamba_async ();
            if (!mamba_ok) {
                log_output ("✖ Aborting environment creation: micromamba binary is missing.");
                return false;
            }

            progress_changed ("Resolving conda-forge packages...", 0.35, "Connecting to conda-forge");
            log_output (@"▶ Provisioning base-ds environment with $(pkgs.length) packages from conda-forge...");

            bool env_exists = GLib.FileUtils.test (default_env, GLib.FileTest.IS_DIR);
            var cmd = new GLib.GenericArray<string> ();
            cmd.add (mamba_bin);
            cmd.add (env_exists ? "install" : "create");
            cmd.add ("-y");
            cmd.add ("-r");
            cmd.add (mamba_root);
            cmd.add ("-n");
            cmd.add ("base-ds");
            cmd.add ("-c");
            cmd.add ("conda-forge");
            cmd.add ("--override-channels");

            for (int i = 0; i < pkgs.length; i++) {
                cmd.add (pkgs[i]);
            }

            string[] argv = new string[cmd.length];
            for (int i = 0; i < cmd.length; i++) {
                argv[i] = cmd[i];
            }

            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                launcher.setenv ("MAMBA_ROOT_PREFIX", mamba_root, true);

                var proc = launcher.spawnv (argv);
                var stdout_stream = new GLib.DataInputStream (proc.get_stdout_pipe ());

                double progress_val = 0.35;
                while (true) {
                    string? line = yield stdout_stream.read_line_async (GLib.Priority.DEFAULT, null);
                    if (line == null) break;

                    string trimmed = line.strip ();
                    if (trimmed.length > 0) {
                        log_output (trimmed);

                        // Parse simple download/extraction progress hints
                        if (trimmed.contains ("Downloading") || trimmed.contains ("Extracting")) {
                            if (progress_val < 0.90) {
                                progress_val += 0.02;
                                progress_changed ("Downloading and extracting packages...", progress_val, trimmed);
                            }
                        } else if (trimmed.contains ("Transaction finished") || trimmed.contains ("Linking")) {
                            progress_val = 0.92;
                            progress_changed ("Linking packages into base-ds environment...", progress_val, trimmed);
                        }
                    }
                }

                yield proc.wait_check_async ();

                // Phase 4: Configure Rprofile.site for seamless CRAN source compilation
                if (install_r && has_r ()) {
                    configure_rprofile_site (default_env);
                }

                if (!save_state ()) {
                    progress_changed ("Could not save toolchain setup state", 0.0, state_file);
                    return false;
                }
                progress_changed ("Toolchain installed successfully", 1.0, "Ready to execute R, Python & Quarto");
                log_output ("✔ Imladris Managed Toolchain (base-ds) provisioned successfully.");
                return true;
            } catch (GLib.Error e) {
                log_output (@"✖ Failed to create base-ds toolchain: $(e.message)");
                progress_changed ("Installation failed", 0.0, e.message);
                return false;
            }
        }

        /**
         * Configures $MAMBA_ROOT_PREFIX/envs/<env>/lib/R/etc/Rprofile.site so standard
         * install.packages() calls automatically use cloud CRAN and multi-core compilation.
         */
        public void configure_rprofile_site (string env_prefix) {
            string etc_dir = GLib.Path.build_filename (env_prefix, "lib", "R", "etc");
            GLib.DirUtils.create_with_parents (etc_dir, 0755);

            string rprofile_path = GLib.Path.build_filename (etc_dir, "Rprofile.site");
            string existing = "";
            if (GLib.FileUtils.test (rprofile_path, GLib.FileTest.EXISTS)) {
                try {
                    GLib.FileUtils.get_contents (rprofile_path, out existing);
                } catch (GLib.Error e) {}
            }

            if (!existing.contains ("Managed by Imladris Toolchain Manager")) {
                string snippet = """

# --- Managed by Imladris Toolchain Manager ---
local({
  r_repos <- getOption("repos")
  if (is.null(r_repos) || identical(r_repos["CRAN"], "@CRAN@")) {
    r_repos["CRAN"] <- "https://cloud.r-project.org"
    options(repos = r_repos)
  }
  # Ensure parallel compilation uses available CPU cores
  options(Ncpus = max(1L, parallel::detectCores() - 1L))
})
""";
                try {
                    GLib.FileUtils.set_contents (rprofile_path, existing + snippet);
                    log_output ("✔ Configured Rprofile.site for automated CRAN package compilation.");
                } catch (GLib.Error e) {
                    log_output (@"✖ Warning: Could not write Rprofile.site: $(e.message)");
                }
            }
        }

        /**
         * Creates an isolated project sandbox prefix at <project_path>/.imladris-env
         * reusing packages already cached in mamba_root/pkgs via hardlinks.
         */
        public async bool create_project_sandbox_async (
            string project_path,
            bool include_r = true,
            bool include_python = true,
            bool include_quarto = false
        ) {
            if (!is_micromamba_installed ()) {
                bool ok = yield ensure_micromamba_async ();
                if (!ok) return false;
            }

            string sandbox_prefix = GLib.Path.build_filename (project_path, ".imladris-env");
            log_output (@"▶ Initializing project sandbox in $sandbox_prefix...");

            bool env_exists = GLib.FileUtils.test (sandbox_prefix, GLib.FileTest.IS_DIR);
            var cmd = new GLib.GenericArray<string> ();
            cmd.add (mamba_bin);
            cmd.add (env_exists ? "install" : "create");
            cmd.add ("-y");
            cmd.add ("-r");
            cmd.add (mamba_root);
            cmd.add ("-p");
            cmd.add (sandbox_prefix);
            cmd.add ("-c");
            cmd.add ("conda-forge");
            cmd.add ("--override-channels");

            if (include_python) {
                cmd.add ("python=3.12");
                cmd.add ("ipykernel");
                cmd.add ("uv");
            }
            if (include_r) {
                cmd.add ("r-base=4.4");
                cmd.add ("r-irkernel");
                cmd.add ("r-pak");
                cmd.add ("compilers");
                cmd.add ("make");
                cmd.add ("pkg-config");
            }
            if (include_quarto) {
                cmd.add ("quarto");
            }

            string[] argv = new string[cmd.length];
            for (int i = 0; i < cmd.length; i++) {
                argv[i] = cmd[i];
            }

            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                launcher.setenv ("MAMBA_ROOT_PREFIX", mamba_root, true);

                var proc = launcher.spawnv (argv);
                var stdout_stream = new GLib.DataInputStream (proc.get_stdout_pipe ());

                while (true) {
                    string? line = yield stdout_stream.read_line_async (GLib.Priority.DEFAULT, null);
                    if (line == null) break;
                    string trimmed = line.strip ();
                    if (trimmed.length > 0) {
                        log_output (trimmed);
                    }
                }

                yield proc.wait_check_async ();

                if (include_r) {
                    configure_rprofile_site (sandbox_prefix);
                }

                log_output ("✔ Project sandbox .imladris-env initialized.");
                return true;
            } catch (GLib.Error e) {
                log_output (@"✖ Failed to scaffold project sandbox: $(e.message)");
                return false;
            }
        }

        /**
         * Returns estimated disk space occupied by toolchains directory in bytes.
         */
        public int64 get_toolchain_disk_usage () {
            return get_toolchain_disk_usage_for (base_dir);
        }

        public int64 get_toolchain_disk_usage_for (string path) {
            if (!GLib.FileUtils.test (path, GLib.FileTest.IS_DIR)) {
                return 0;
            }
            return compute_dir_size (path);
        }

        private int64 compute_dir_size (string path) {
            int64 total = 0;
            try {
                var dir = GLib.Dir.open (path, 0);
                string? name = null;
                while ((name = dir.read_name ()) != null) {
                    string sub = GLib.Path.build_filename (path, name);
                    if (GLib.FileUtils.test (sub, GLib.FileTest.IS_DIR) && !GLib.FileUtils.test (sub, GLib.FileTest.IS_SYMLINK)) {
                        total += compute_dir_size (sub);
                    } else {
                        var file = GLib.File.new_for_path (sub);
                        try {
                            var info = file.query_info (GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                            total += info.get_size ();
                        } catch (GLib.Error e) {}
                    }
                }
            } catch (GLib.Error e) {}
            return total;
        }

        private async void read_stream_to_log (GLib.DataInputStream stream) {
            try {
                while (true) {
                    string? line = yield stream.read_line_async (GLib.Priority.DEFAULT, null);
                    if (line == null) break;
                    string trimmed = line.strip ();
                    if (trimmed.length > 0) {
                        log_output (trimmed);
                    }
                }
            } catch (GLib.Error e) {}
        }

        private bool has_tidyverse () {
            string rscript = GLib.Path.build_filename (default_env, "bin", "Rscript");
            if (!GLib.FileUtils.test (rscript, GLib.FileTest.IS_EXECUTABLE)) {
                return false;
            }
            try {
                string[] argv = {
                    rscript, "-e", "if (!requireNamespace('tidyverse', quietly=TRUE)) quit(status=1)"
                };
                var proc = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.NONE);
                proc.wait_check ();
                return true;
            } catch (GLib.Error e) {
                log_output ("Could not confirm the tidyverse package is installed: " + e.message);
                return false;
            }
        }

        private bool save_state () {
            try {
                GLib.DirUtils.create_with_parents (base_dir, 0755);
                var builder = new Json.Builder ();
                builder.begin_object ();
                builder.set_member_name ("installed_at");
                builder.add_string_value (new GLib.DateTime.now_local ().to_string ());
                builder.set_member_name ("setup_complete");
                builder.add_boolean_value (true);

                builder.set_member_name ("components");
                builder.begin_object ();
                builder.set_member_name ("r");
                builder.add_boolean_value (has_r ());
                builder.set_member_name ("r_tidyverse");
                builder.add_boolean_value (has_tidyverse ());
                builder.set_member_name ("python");
                builder.add_boolean_value (has_python ());
                builder.set_member_name ("quarto");
                builder.add_boolean_value (has_quarto ());
                builder.set_member_name ("node_typescript");
                builder.add_boolean_value (has_node_typescript ());
                builder.set_member_name ("tectonic");
                builder.add_boolean_value (has_tectonic ());
                builder.end_object ();

                builder.end_object ();

                var generator = new Json.Generator ();
                var root = builder.get_root ();
                generator.set_root (root);
                generator.to_file (state_file);
                return true;
            } catch (GLib.Error e) {
                log_output (@"✖ Failed to save toolchain state: $(e.message)");
                return false;
            }
        }
    }
}
