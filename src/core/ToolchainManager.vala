// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris.Core {

    [CCode (cname = "imladris_toolchain_get_arch", cheader_filename = "toolchain_native.h")]
    internal extern unowned string imladris_toolchain_get_arch ();

    [CCode (cname = "imladris_toolchain_get_dir_usage", cheader_filename = "toolchain_native.h")]
    internal extern int64 imladris_toolchain_get_dir_usage (string path, bool deduplicate_hardlinks);

    [CCode (cname = "imladris_toolchain_get_free_space", cheader_filename = "toolchain_native.h")]
    internal extern int64 imladris_toolchain_get_free_space (string path);

    [CCode (cname = "imladris_toolchain_detect_pkg_version", cheader_filename = "toolchain_native.h")]
    internal extern string? imladris_toolchain_detect_pkg_version (string env_prefix, string pkg_name);

    [CCode (cname = "imladris_toolchain_list_python_envs", cheader_filename = "toolchain_native.h", array_length = false, array_null_terminated = true)]
    internal extern string[] imladris_toolchain_list_python_envs (string mamba_root);

    public enum ToolchainComponent {
        PYTHON,
        R,
        R_TIDYVERSE,
        LATEX,
        HTML_CSS,
        TYPESCRIPT,
        QUARTO;

        public string to_display_name () {
            switch (this) {
                case PYTHON: return "Python";
                case R: return "R";
                case R_TIDYVERSE: return "R Tidyverse & RMarkdown";
                case LATEX: return "LaTeX (Tectonic)";
                case HTML_CSS: return "HTML / CSS";
                case TYPESCRIPT: return "TypeScript";
                case QUARTO: return "Quarto";
                default: return "Unknown";
            }
        }
    }

    public class PythonEnvInfo : GLib.Object {
        public string name { get; set; default = ""; }
        public string path { get; set; default = ""; }
        public string version { get; set; default = ""; }
        public bool is_active { get; set; default = false; }
    }

    public class ToolchainInstallRequest : GLib.Object {
        public bool install_python { get; set; default = true; }
        public string python_version { get; set; default = "3.12"; }
        public bool install_r { get; set; default = true; }
        public string r_version { get; set; default = "4.4"; }
        public bool install_tidyverse { get; set; default = true; }
        public bool install_latex { get; set; default = true; }
        public bool install_html_css { get; set; default = true; }
        public bool install_typescript { get; set; default = true; }
        public bool install_quarto { get; set; default = true; }
    }

    public class ToolchainManager : GLib.Object {

        private static ToolchainManager? _instance = null;

        public static ToolchainManager get_default () {
            if (_instance == null) {
                _instance = new ToolchainManager ();
            }
            return _instance;
        }

        public static string[] get_supported_python_versions () {
            return { "3.12", "3.11", "3.10", "3.9" };
        }

        public static string[] get_supported_r_versions () {
            return { "4.4", "4.3" };
        }

        public signal void progress_changed (string step, double fraction, string detail);
        public signal void log_output (string line);
        public signal void location_changed (string path);
        public signal void active_python_changed (string env_path);

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

        private string _active_python_env;
        public string active_python_env { get { return _active_python_env; } }

        private string _state_file;
        public string state_file { get { return _state_file; } }

        public ToolchainManager () {
            _base_dir = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "imladris", "toolchains");
            load_configured_base_dir ();
            update_paths ();
            load_active_python_env ();
        }

        private void update_paths () {
            _bin_dir = GLib.Path.build_filename (_base_dir, "bin");
            _mamba_bin = GLib.Path.build_filename (_bin_dir, "micromamba");
            _mamba_root = GLib.Path.build_filename (_base_dir, "mamba_root");
            _default_env = GLib.Path.build_filename (_mamba_root, "envs", "base-ds");
            _active_python_env = _default_env;
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

        private void load_active_python_env () {
            if (!GLib.FileUtils.test (_state_file, GLib.FileTest.EXISTS)) {
                return;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (_state_file);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("active_python_env")) {
                        string? saved = obj.get_string_member ("active_python_env");
                        if (saved != null && saved.length > 0 &&
                            GLib.FileUtils.test (GLib.Path.build_filename (saved, "bin", "python3"), GLib.FileTest.IS_EXECUTABLE)) {
                            _active_python_env = saved;
                        }
                    }
                }
            } catch (GLib.Error e) {
                warning ("Could not read active Python environment from state: %s", e.message);
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
            load_active_python_env ();
            location_changed (_base_dir);
        }

        /**
         * Returns the platform architecture string expected by micromamba APIs
         * using the native C uname(2) syscall.
         */
        public static string get_platform_arch () {
            return imladris_toolchain_get_arch ();
        }

        public bool is_micromamba_installed () {
            return GLib.FileUtils.test (mamba_bin, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool is_base_environment_installed () {
            return has_r () || has_python () || has_quarto () || has_typescript () ||
                has_html_css () || has_latex () || has_completed_setup_state ();
        }

        public bool has_r () {
            string r_path = GLib.Path.build_filename (default_env, "bin", "R");
            return GLib.FileUtils.test (r_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_python () {
            if (GLib.FileUtils.test (GLib.Path.build_filename (active_python_env, "bin", "python3"), GLib.FileTest.IS_EXECUTABLE)) {
                return true;
            }
            string py_path = GLib.Path.build_filename (default_env, "bin", "python3");
            return GLib.FileUtils.test (py_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_quarto () {
            string q_path = GLib.Path.build_filename (default_env, "bin", "quarto");
            return GLib.FileUtils.test (q_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_typescript () {
            string node_path = GLib.Path.build_filename (default_env, "bin", "node");
            string tsc_path = GLib.Path.build_filename (default_env, "bin", "tsc");
            return GLib.FileUtils.test (node_path, GLib.FileTest.IS_EXECUTABLE) &&
                GLib.FileUtils.test (tsc_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_node_typescript () {
            return has_typescript ();
        }

        public bool has_html_css () {
            string tidy_path = GLib.Path.build_filename (default_env, "bin", "tidy");
            string node_path = GLib.Path.build_filename (default_env, "bin", "node");
            return GLib.FileUtils.test (tidy_path, GLib.FileTest.IS_EXECUTABLE) &&
                GLib.FileUtils.test (node_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_latex () {
            string tex_path = GLib.Path.build_filename (default_env, "bin", "tectonic");
            return GLib.FileUtils.test (tex_path, GLib.FileTest.IS_EXECUTABLE);
        }

        public bool has_tectonic () {
            return has_latex ();
        }

        /**
         * Fast C conda-meta/*.json version lookup without spawning any subprocess.
         */
        public string? get_component_version (ToolchainComponent comp) {
            switch (comp) {
                case ToolchainComponent.PYTHON:
                    string? v = imladris_toolchain_detect_pkg_version (active_python_env, "python");
                    return v ?? imladris_toolchain_detect_pkg_version (default_env, "python");
                case ToolchainComponent.R:
                    return imladris_toolchain_detect_pkg_version (default_env, "r-base");
                case ToolchainComponent.R_TIDYVERSE:
                    return imladris_toolchain_detect_pkg_version (default_env, "r-tidyverse");
                case ToolchainComponent.LATEX:
                    return imladris_toolchain_detect_pkg_version (default_env, "tectonic");
                case ToolchainComponent.HTML_CSS:
                    return imladris_toolchain_detect_pkg_version (default_env, "tidy-html5");
                case ToolchainComponent.TYPESCRIPT:
                    return imladris_toolchain_detect_pkg_version (default_env, "typescript");
                case ToolchainComponent.QUARTO:
                    return imladris_toolchain_detect_pkg_version (default_env, "quarto");
                default:
                    return null;
            }
        }

        public Gee.ArrayList<PythonEnvInfo> list_installed_python_envs () {
            var list = new Gee.ArrayList<PythonEnvInfo> ();
            string[] paths = imladris_toolchain_list_python_envs (mamba_root);
            foreach (string env_path in paths) {
                var info = new PythonEnvInfo ();
                info.path = env_path;
                info.name = GLib.Path.get_basename (env_path);
                info.version = imladris_toolchain_detect_pkg_version (env_path, "python") ?? "unknown";
                info.is_active = (env_path == _active_python_env);
                list.add (info);
            }
            return list;
        }

        public bool set_active_python_env (string env_path) {
            string py_bin = GLib.Path.build_filename (env_path, "bin", "python3");
            if (!GLib.FileUtils.test (py_bin, GLib.FileTest.IS_EXECUTABLE)) {
                return false;
            }
            _active_python_env = env_path;
            save_state ();
            active_python_changed (_active_python_env);
            return true;
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

        public bool mark_setup_dismissed () {
            return save_state ();
        }

        /**
         * Ensures the micromamba binary exists at $XDG_DATA_HOME/imladris/toolchains/bin/micromamba.
         * Downloads and extracts the official static binary if absent.
         */
        public async bool ensure_micromamba_async (GLib.Cancellable? cancellable = null) {
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

            string? tmp_dir = GLib.DirUtils.mkdtemp (Path.build_filename (Environment.get_tmp_dir (), "imladris-mamba-XXXXXX"));
            if (tmp_dir == null) {
                log_output ("✖ Failed to create temporary download directory.");
                return false;
            }
            GLib.FileUtils.chmod (tmp_dir, 0700);
            string tmp_tar = Path.build_filename (tmp_dir, "micromamba.tar.bz2");
            ulong cancel_id = 0;
            try {
                string[] dl_argv = { "curl", "-fsSL", "-o", tmp_tar, url };
                var dl_proc = new GLib.Subprocess.newv (dl_argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                if (cancellable != null) {
                    cancel_id = cancellable.cancelled.connect (() => { dl_proc.force_exit (); });
                }
                var dl_err = new GLib.DataInputStream (dl_proc.get_stderr_pipe ());
                read_stream_to_log.begin (dl_err);
                yield dl_proc.wait_check_async (cancellable);

                uint8[] tar_bytes;
                GLib.FileUtils.get_data (tmp_tar, out tar_bytes);
                if (tar_bytes.length == 0) {
                    throw new GLib.IOError.FAILED ("Downloaded micromamba archive is empty.");
                }
                string sha256 = GLib.Checksum.compute_for_data (GLib.ChecksumType.SHA256, tar_bytes);
                log_output (@"✔ Downloaded micromamba archive (SHA-256: $sha256)");

                string[] tar_argv = { "tar", "-xvjf", tmp_tar, "-C", bin_dir, "--strip-components=1", "bin/micromamba" };
                var proc = new GLib.Subprocess.newv (tar_argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                var stdout_stream = new GLib.DataInputStream (proc.get_stdout_pipe ());
                var stderr_stream = new GLib.DataInputStream (proc.get_stderr_pipe ());

                read_stream_to_log.begin (stdout_stream);
                read_stream_to_log.begin (stderr_stream);

                yield proc.wait_check_async (cancellable);

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
                log_output (@"✖ Micromamba setup failed: $(e.message)");
                return false;
            } finally {
                if (cancellable != null && cancel_id != 0) {
                    cancellable.disconnect (cancel_id);
                    cancel_id = 0;
                }
                if (GLib.FileUtils.test (tmp_tar, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.remove (tmp_tar);
                }
                if (tmp_dir != "" && GLib.FileUtils.test (tmp_dir, GLib.FileTest.IS_DIR)) {
                    GLib.DirUtils.remove (tmp_dir);
                }
            }
        }

        public static void append_packages_for_component (
            GLib.GenericArray<string> pkgs,
            ToolchainComponent comp,
            string python_ver = "3.12",
            string r_ver = "4.4",
            bool for_update = false
        ) {
            switch (comp) {
                case ToolchainComponent.PYTHON:
                    pkgs.add (for_update ? "python" : @"python=$python_ver");
                    pkgs.add ("pip");
                    pkgs.add ("ipykernel");
                    pkgs.add ("jupyter_client");
                    pkgs.add ("uv");
                    pkgs.add ("numpy");
                    pkgs.add ("pandas");
                    pkgs.add ("matplotlib");
                    break;
                case ToolchainComponent.R:
                    pkgs.add (for_update ? "r-base" : @"r-base=$r_ver");
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
                    break;
                case ToolchainComponent.R_TIDYVERSE:
                    pkgs.add ("r-tidyverse");
                    pkgs.add ("r-data.table");
                    break;
                case ToolchainComponent.LATEX:
                    pkgs.add ("tectonic");
                    break;
                case ToolchainComponent.HTML_CSS:
                    pkgs.add ("nodejs");
                    pkgs.add ("tidy-html5");
                    pkgs.add ("weasyprint");
                    break;
                case ToolchainComponent.TYPESCRIPT:
                    pkgs.add ("nodejs");
                    pkgs.add ("typescript");
                    break;
                case ToolchainComponent.QUARTO:
                    pkgs.add ("quarto");
                    pkgs.add ("typst");
                    pkgs.add ("pandoc");
                    break;
            }
        }

        private static void add_unique_packages (GLib.GenericArray<string> target, GLib.GenericArray<string> source) {
            for (int i = 0; i < source.length; i++) {
                string pkg = source[i];
                bool exists = false;
                for (int j = 0; j < target.length; j++) {
                    if (target[j] == pkg) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    target.add (pkg);
                }
            }
        }

        /**
         * Installs or updates selected components using a structured ToolchainInstallRequest.
         * Supports custom Python (3.12, 3.11, 3.10, 3.9) and R (4.4, 4.3) versions.
         */
        public async bool install_components_async (
            ToolchainInstallRequest req,
            GLib.Cancellable? cancellable = null
        ) {
            var raw_pkgs = new GLib.GenericArray<string> ();
            var pkgs = new GLib.GenericArray<string> ();

            if (req.install_python) {
                append_packages_for_component (raw_pkgs, ToolchainComponent.PYTHON, req.python_version, req.r_version, false);
            }
            if (req.install_r) {
                append_packages_for_component (raw_pkgs, ToolchainComponent.R, req.python_version, req.r_version, false);
                if (req.install_tidyverse) {
                    append_packages_for_component (raw_pkgs, ToolchainComponent.R_TIDYVERSE, req.python_version, req.r_version, false);
                }
            }
            if (req.install_quarto) {
                append_packages_for_component (raw_pkgs, ToolchainComponent.QUARTO, req.python_version, req.r_version, false);
            }
            if (req.install_typescript) {
                append_packages_for_component (raw_pkgs, ToolchainComponent.TYPESCRIPT, req.python_version, req.r_version, false);
            }
            if (req.install_html_css) {
                append_packages_for_component (raw_pkgs, ToolchainComponent.HTML_CSS, req.python_version, req.r_version, false);
            }
            if (req.install_latex) {
                append_packages_for_component (raw_pkgs, ToolchainComponent.LATEX, req.python_version, req.r_version, false);
            }

            add_unique_packages (pkgs, raw_pkgs);

            if (pkgs.length == 0) {
                log_output ("ℹ No components selected for installation.");
                if (!save_state ()) {
                    progress_changed ("Could not save toolchain setup state", 0.0, state_file);
                    return false;
                }
                progress_changed ("No toolchain components selected", 1.0, "You can install runtimes later from Tools → Data Science Toolchains.");
                return true;
            }

            bool mamba_ok = yield ensure_micromamba_async (cancellable);
            if (!mamba_ok) {
                log_output ("✖ Aborting environment creation: micromamba binary is missing.");
                return false;
            }

            // Check if base-ds already has a different Python version and user wants another Python version
            bool create_separate_py_env = false;
            if (req.install_python && GLib.FileUtils.test (default_env, GLib.FileTest.IS_DIR)) {
                string? existing_py = imladris_toolchain_detect_pkg_version (default_env, "python");
                if (existing_py != null && !existing_py.has_prefix (req.python_version)) {
                    create_separate_py_env = true;
                    // Remove python-specific packages from base-ds command if base-ds already has R/etc.,
                    // or handle python in dedicated py-<version> env.
                    var non_py_pkgs = new GLib.GenericArray<string> ();
                    var py_only = new GLib.GenericArray<string> ();
                    append_packages_for_component (py_only, ToolchainComponent.PYTHON, req.python_version, req.r_version, false);
                    for (int i = 0; i < pkgs.length; i++) {
                        bool is_py_pkg = false;
                        for (int j = 0; j < py_only.length; j++) {
                            if (pkgs[i] == py_only[j]) {
                                is_py_pkg = true;
                                break;
                            }
                        }
                        if (!is_py_pkg) {
                            non_py_pkgs.add (pkgs[i]);
                        }
                    }
                    pkgs = non_py_pkgs;
                }
            }

            if (pkgs.length > 0) {
                progress_changed ("Resolving conda-forge packages...", 0.35, "Connecting to conda-forge");
                log_output (@"▶ Provisioning base-ds environment with $(pkgs.length) packages from conda-forge...");

                bool env_exists = GLib.FileUtils.test (default_env, GLib.FileTest.IS_DIR);
                var cmd = build_mamba_env_cmd (env_exists ? "install" : "create", "base-ds", false, pkgs);
                bool ok = yield run_micromamba_command_async (cmd, 0.35, create_separate_py_env ? 0.70 : 0.95, "base-ds", cancellable);
                if (!ok) {
                    return false;
                }
            }

            if (create_separate_py_env) {
                bool py_ok = yield install_or_switch_python_version_async (req.python_version, cancellable);
                if (!py_ok) {
                    return false;
                }
            } else if (req.install_python) {
                _active_python_env = _default_env;
                active_python_changed (_active_python_env);
            }

            if (req.install_r && has_r ()) {
                configure_rprofile_site (default_env);
            }

            if (!save_state ()) {
                progress_changed ("Could not save toolchain setup state", 0.0, state_file);
                return false;
            }
            progress_changed ("Toolchain installed successfully", 1.0, "Ready to execute selected runtimes");
            log_output ("✔ Imladris Managed Toolchain provisioned successfully.");
            return true;
        }

        /**
         * Backward-compatible wrapper for creating or updating the base-ds environment.
         */
        public async bool create_or_update_base_environment_async (
            bool install_r = true,
            bool install_python = true,
            bool install_quarto = true,
            bool install_tidyverse = true,
            bool install_node_ts = false,
            bool install_tex = false,
            bool install_html_css = false
        ) {
            var req = new ToolchainInstallRequest ();
            req.install_r = install_r;
            req.install_python = install_python;
            req.install_quarto = install_quarto;
            req.install_tidyverse = install_tidyverse;
            req.install_typescript = install_node_ts;
            req.install_latex = install_tex;
            req.install_html_css = install_html_css;
            return yield install_components_async (req);
        }

        /**
         * Installs or switches to a specific Python version (e.g. "3.10", "3.11", "3.12", "3.9").
         * Reuses cached packages in mamba_root/pkgs via hardlinks.
         */
        public async bool install_or_switch_python_version_async (
            string python_version,
            GLib.Cancellable? cancellable = null
        ) {
            string? base_py_ver = imladris_toolchain_detect_pkg_version (default_env, "python");
            if (base_py_ver != null && base_py_ver.has_prefix (python_version)) {
                log_output (@"✔ Switching active Python to base-ds (Python $base_py_ver).");
                return set_active_python_env (default_env);
            }

            string env_name = @"py-$python_version";
            string target_env = GLib.Path.build_filename (mamba_root, "envs", env_name);

            if (GLib.FileUtils.test (GLib.Path.build_filename (target_env, "bin", "python3"), GLib.FileTest.IS_EXECUTABLE)) {
                log_output (@"✔ Switching active Python to existing $env_name environment.");
                progress_changed (@"Activated Python $python_version", 1.0, target_env);
                return set_active_python_env (target_env);
            }

            bool mamba_ok = yield ensure_micromamba_async (cancellable);
            if (!mamba_ok) {
                return false;
            }

            var pkgs = new GLib.GenericArray<string> ();
            append_packages_for_component (pkgs, ToolchainComponent.PYTHON, python_version, "4.4", false);

            progress_changed (@"Installing Python $python_version...", 0.40, @"Creating $env_name environment");
            log_output (@"▶ Provisioning isolated Python $python_version environment ($env_name)...");

            var cmd = build_mamba_env_cmd ("create", env_name, false, pkgs);
            bool ok = yield run_micromamba_command_async (cmd, 0.40, 0.95, env_name, cancellable);
            if (!ok) {
                return false;
            }

            set_active_python_env (target_env);
            progress_changed (@"Python $python_version ready", 1.0, target_env);
            log_output (@"✔ Python $python_version ($env_name) installed and activated.");
            return true;
        }

        /**
         * Updates installed components in base-ds (and active Python env if separate).
         */
        public async bool update_installed_components_async (
            GLib.GenericArray<ToolchainComponent>? only_components = null,
            GLib.Cancellable? cancellable = null
        ) {
            bool mamba_ok = yield ensure_micromamba_async (cancellable);
            if (!mamba_ok) {
                return false;
            }

            var comps = new GLib.GenericArray<ToolchainComponent> ();
            if (only_components != null && only_components.length > 0) {
                for (int i = 0; i < only_components.length; i++) {
                    comps.add (only_components[i]);
                }
            } else {
                if (has_python ()) comps.add (ToolchainComponent.PYTHON);
                if (has_r ()) {
                    comps.add (ToolchainComponent.R);
                    if (has_tidyverse ()) comps.add (ToolchainComponent.R_TIDYVERSE);
                }
                if (has_latex ()) comps.add (ToolchainComponent.LATEX);
                if (has_html_css ()) comps.add (ToolchainComponent.HTML_CSS);
                if (has_typescript ()) comps.add (ToolchainComponent.TYPESCRIPT);
                if (has_quarto ()) comps.add (ToolchainComponent.QUARTO);
            }

            if (comps.length == 0) {
                log_output ("ℹ No installed toolchain components found to update.");
                return false;
            }

            var raw_pkgs = new GLib.GenericArray<string> ();
            var pkgs = new GLib.GenericArray<string> ();
            bool update_separate_py = false;

            for (int i = 0; i < comps.length; i++) {
                var c = comps[i];
                if (c == ToolchainComponent.PYTHON && _active_python_env != _default_env) {
                    update_separate_py = true;
                } else {
                    append_packages_for_component (raw_pkgs, c, "3.12", "4.4", true);
                }
            }
            add_unique_packages (pkgs, raw_pkgs);

            if (pkgs.length > 0 && GLib.FileUtils.test (default_env, GLib.FileTest.IS_DIR)) {
                progress_changed ("Updating base-ds packages...", 0.35, "Checking conda-forge");
                log_output (@"▶ Updating $(pkgs.length) packages in base-ds...");
                var cmd = build_mamba_env_cmd ("update", "base-ds", false, pkgs);
                bool ok = yield run_micromamba_command_async (cmd, 0.35, update_separate_py ? 0.75 : 0.95, "base-ds", cancellable);
                if (!ok) {
                    return false;
                }
            }

            if (update_separate_py && GLib.FileUtils.test (_active_python_env, GLib.FileTest.IS_DIR)) {
                var py_pkgs = new GLib.GenericArray<string> ();
                append_packages_for_component (py_pkgs, ToolchainComponent.PYTHON, "3.12", "4.4", true);
                string env_name = GLib.Path.get_basename (_active_python_env);
                progress_changed (@"Updating $env_name...", 0.75, "Checking conda-forge");
                log_output (@"▶ Updating Python packages in $env_name...");
                var cmd = build_mamba_env_cmd ("update", env_name, false, py_pkgs);
                bool ok = yield run_micromamba_command_async (cmd, 0.75, 0.95, env_name, cancellable);
                if (!ok) {
                    return false;
                }
            }

            save_state ();
            progress_changed ("All selected components updated", 1.0, "Up to date");
            log_output ("✔ Toolchain update completed successfully.");
            return true;
        }

        private string[] build_mamba_env_cmd (
            string subcmd,
            string env_target,
            bool use_prefix,
            GLib.GenericArray<string> pkgs
        ) {
            var cmd = new GLib.GenericArray<string> ();
            cmd.add (mamba_bin);
            cmd.add (subcmd);
            cmd.add ("-y");
            cmd.add ("-r");
            cmd.add (mamba_root);
            cmd.add (use_prefix ? "-p" : "-n");
            cmd.add (env_target);
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
            return argv;
        }

        private async bool run_micromamba_command_async (
            string[] argv,
            double start_progress,
            double end_progress,
            string env_label,
            GLib.Cancellable? cancellable
        ) {
            try {
                var launcher = new GLib.SubprocessLauncher (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE
                );
                launcher.setenv ("MAMBA_ROOT_PREFIX", mamba_root, true);

                var proc = launcher.spawnv (argv);
                ulong cancel_id = 0;
                if (cancellable != null) {
                    cancel_id = cancellable.cancelled.connect (() => { proc.force_exit (); });
                }

                var stdout_stream = new GLib.DataInputStream (proc.get_stdout_pipe ());
                double progress_val = start_progress;
                double link_threshold = start_progress + (end_progress - start_progress) * 0.90;

                while (true) {
                    string? line = yield stdout_stream.read_line_async (GLib.Priority.DEFAULT, cancellable);
                    if (line == null) break;

                    string trimmed = line.strip ();
                    if (trimmed.length > 0) {
                        log_output (trimmed);

                        if (trimmed.contains ("Downloading") || trimmed.contains ("Extracting")) {
                            if (progress_val < link_threshold) {
                                progress_val += 0.02;
                                if (progress_val > link_threshold) progress_val = link_threshold;
                                progress_changed (@"Downloading and extracting ($env_label)...", progress_val, trimmed);
                            }
                        } else if (trimmed.contains ("Transaction finished") || trimmed.contains ("Linking")) {
                            progress_val = end_progress;
                            progress_changed (@"Linking packages into $env_label...", progress_val, trimmed);
                        }
                    }
                }

                yield proc.wait_check_async (cancellable);
                if (cancellable != null && cancel_id != 0) {
                    cancellable.disconnect (cancel_id);
                }
                return true;
            } catch (GLib.Error e) {
                log_output (@"✖ Micromamba operation failed ($env_label): $(e.message)");
                progress_changed ("Operation failed", 0.0, e.message);
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
            bool include_quarto = false,
            string python_version = "3.12"
        ) {
            if (!is_micromamba_installed ()) {
                bool ok = yield ensure_micromamba_async ();
                if (!ok) return false;
            }

            string sandbox_prefix = GLib.Path.build_filename (project_path, ".imladris-env");
            log_output (@"▶ Initializing project sandbox in $sandbox_prefix...");

            bool env_exists = GLib.FileUtils.test (sandbox_prefix, GLib.FileTest.IS_DIR);
            var pkgs = new GLib.GenericArray<string> ();

            if (include_python) {
                pkgs.add (@"python=$python_version");
                pkgs.add ("ipykernel");
                pkgs.add ("uv");
            }
            if (include_r) {
                pkgs.add ("r-base=4.4");
                pkgs.add ("r-irkernel");
                pkgs.add ("r-pak");
                pkgs.add ("compilers");
                pkgs.add ("make");
                pkgs.add ("pkg-config");
            }
            if (include_quarto) {
                pkgs.add ("quarto");
            }

            var argv = build_mamba_env_cmd (env_exists ? "install" : "create", sandbox_prefix, true, pkgs);
            bool ok = yield run_micromamba_command_async (argv, 0.1, 0.95, ".imladris-env", null);
            if (!ok) {
                return false;
            }

            if (include_r) {
                configure_rprofile_site (sandbox_prefix);
            }

            log_output ("✔ Project sandbox .imladris-env initialized.");
            return true;
        }

        /**
         * Returns disk space occupied by toolchains directory in bytes (with C fts + hardlink deduplication).
         */
        public int64 get_toolchain_disk_usage () {
            return get_toolchain_disk_usage_for (base_dir);
        }

        public int64 get_toolchain_disk_usage_for (string path) {
            return imladris_toolchain_get_dir_usage (path, true);
        }

        public int64 get_available_disk_space_for (string path) {
            return imladris_toolchain_get_free_space (path);
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
            return imladris_toolchain_detect_pkg_version (default_env, "r-tidyverse") != null;
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
                builder.set_member_name ("active_python_env");
                builder.add_string_value (_active_python_env);

                string? active_py_ver = get_component_version (ToolchainComponent.PYTHON);
                if (active_py_ver != null) {
                    builder.set_member_name ("active_python_version");
                    builder.add_string_value (active_py_ver);
                }

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
                builder.set_member_name ("html_css");
                builder.add_boolean_value (has_html_css ());
                builder.set_member_name ("typescript");
                builder.add_boolean_value (has_typescript ());
                builder.set_member_name ("latex");
                builder.add_boolean_value (has_latex ());
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
