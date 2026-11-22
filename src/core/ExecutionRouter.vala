// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gee;

namespace Imladris.Core {

    public enum KernelOption {
        AUTO = 0,
        QUARTO = 1,
        R = 2,
        PYTHON = 3;

        public string to_string_id () {
            switch (this) {
                case QUARTO: return "quarto";
                case R: return "r";
                case PYTHON: return "python";
                default: return "auto";
            }
        }

        public static KernelOption from_string_id (string id) {
            switch (id.down ()) {
                case "quarto": return QUARTO;
                case "r": return R;
                case "python": return PYTHON;
                default: return AUTO;
            }
        }

        public string get_display_name () {
            switch (this) {
                case QUARTO: return "Quarto";
                case R: return "R Kernel";
                case PYTHON: return "Python Kernel";
                default: return "Auto (By Document)";
            }
        }
    }

    /**
     * Layer 3: ExecutionRouter
     *
     * Maps each discovered environment type (uv, Conda/Mamba, venv, Host R/renv,
     * Quarto) and user-selected kernel to a deterministic launch command passed
     * through `HostBridge`.
     */
    public class ExecutionRouter : GLib.Object {

        public static string[] build_python_command (
            EnvDiscoveryResult? probe,
            string[] python_args,
            string? project_dir = null,
            DiscoveredEnv? selected_env = null,
            out string[] env_vars = null
        ) {
            var ev = new GenericArray<string> ();
            var cmd = new GenericArray<string> ();

            if (selected_env != null && selected_env.kind == DiscoveredEnvKind.CONDA_MAMBA) {
                string conda_exe = (probe != null && probe.conda_bin != null) ? probe.conda_bin : "conda";
                cmd.add (conda_exe);
                cmd.add ("run");
                cmd.add ("--no-capture-output");
                cmd.add ("-p");
                cmd.add (selected_env.path);
                cmd.add ("python");
            } else if (selected_env != null && selected_env.kind == DiscoveredEnvKind.VENV) {
                cmd.add (GLib.Path.build_filename (selected_env.path, "bin", "python"));
                ev.add ("VIRTUAL_ENV=" + selected_env.path);
            } else if (selected_env != null && selected_env.kind == DiscoveredEnvKind.UV_PROJECT &&
                       probe != null && probe.uv_path != null && project_dir != null && project_dir.length > 0) {
                cmd.add (probe.uv_path);
                cmd.add ("run");
                cmd.add ("--project");
                cmd.add (project_dir);
                cmd.add ("python");
            } else if (probe != null && probe.uv_path != null &&
                       (probe.has_uv_lock || probe.has_pyproject) &&
                       project_dir != null && project_dir.length > 0) {
                cmd.add (probe.uv_path);
                cmd.add ("run");
                cmd.add ("--project");
                cmd.add (project_dir);
                cmd.add ("python");
            } else if (probe != null && probe.project_venv_path != null && probe.project_venv_path.length > 0) {
                cmd.add (GLib.Path.build_filename (probe.project_venv_path, "bin", "python"));
                ev.add ("VIRTUAL_ENV=" + probe.project_venv_path);
            } else if (probe != null && probe.host_python_path != null && probe.host_python_path.length > 0) {
                cmd.add (probe.host_python_path);
            } else {
                cmd.add ("python3");
            }

            foreach (string a in python_args) {
                cmd.add (a);
            }

            env_vars = array_from_generic (ev);
            return array_from_generic (cmd);
        }

        public static string[] build_r_command (
            EnvDiscoveryResult? probe,
            string[] r_args,
            string? project_dir = null,
            DiscoveredEnv? selected_env = null,
            bool interactive_r = false,
            out string[] env_vars = null
        ) {
            var ev = new GenericArray<string> ();
            var cmd = new GenericArray<string> ();
            string exe_name = interactive_r ? "R" : "Rscript";

            if (selected_env != null && selected_env.kind == DiscoveredEnvKind.CONDA_MAMBA) {
                string conda_exe = (probe != null && probe.conda_bin != null) ? probe.conda_bin : "conda";
                cmd.add (conda_exe);
                cmd.add ("run");
                cmd.add ("--no-capture-output");
                cmd.add ("-p");
                cmd.add (selected_env.path);
                cmd.add (exe_name);
            } else if (probe != null && probe.latest_r_path != null && probe.latest_r_path.length > 0) {
                if (interactive_r) {
                    string r_dir = GLib.Path.get_dirname (probe.latest_r_path);
                    cmd.add (GLib.Path.build_filename (r_dir, "R"));
                } else {
                    cmd.add (probe.latest_r_path);
                }
            } else {
                cmd.add (exe_name);
            }

            foreach (string a in r_args) {
                cmd.add (a);
            }

            env_vars = array_from_generic (ev);
            return array_from_generic (cmd);
        }

        public static string[] build_quarto_command (
            EnvDiscoveryResult? probe,
            string[] quarto_args,
            string? project_dir = null,
            DiscoveredEnv? python_env = null,
            out string[] env_vars = null
        ) {
            var ev = new GenericArray<string> ();
            var cmd = new GenericArray<string> ();

            if (probe != null && probe.quarto_path != null && probe.quarto_path.length > 0) {
                cmd.add (probe.quarto_path);
            } else {
                cmd.add ("quarto");
            }

            string? py_bin = null;
            if (python_env != null && python_env.kind == DiscoveredEnvKind.VENV) {
                py_bin = GLib.Path.build_filename (python_env.path, "bin", "python");
            } else if (python_env != null && python_env.kind == DiscoveredEnvKind.CONDA_MAMBA) {
                py_bin = GLib.Path.build_filename (python_env.path, "bin", "python");
            } else if (probe != null && probe.project_venv_path != null && probe.project_venv_path.length > 0) {
                py_bin = GLib.Path.build_filename (probe.project_venv_path, "bin", "python");
            } else if (probe != null && probe.host_python_path != null && probe.host_python_path.length > 0) {
                py_bin = probe.host_python_path;
            }

            if (py_bin != null && py_bin.length > 0) {
                ev.add ("QUARTO_PYTHON=" + py_bin);
                ev.add ("RETICULATE_PYTHON=" + py_bin);
            }

            if (probe != null && probe.latest_r_path != null && probe.latest_r_path.length > 0) {
                string r_dir = GLib.Path.get_dirname (probe.latest_r_path);
                ev.add ("QUARTO_R=" + GLib.Path.build_filename (r_dir, "R"));
            }

            foreach (string a in quarto_args) {
                cmd.add (a);
            }

            env_vars = array_from_generic (ev);
            return array_from_generic (cmd);
        }

        public static string[] route_and_wrap (
            string[] raw_cmd,
            string? project_dir = null,
            string[]? env_vars = null,
            bool? force_flatpak = null
        ) {
            return HostBridge.wrap_command (raw_cmd, project_dir, env_vars, force_flatpak);
        }

        private static string[] array_from_generic (GenericArray<string> arr) {
            string[] res = new string[arr.length];
            for (int i = 0; i < arr.length; i++) {
                res[i] = arr[i];
            }
            return res;
        }
    }
}
