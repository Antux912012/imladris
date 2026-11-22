// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gee;
using Json;

namespace Imladris.Core {

    public enum DiscoveredEnvKind {
        UV_PROJECT,
        VENV,
        CONDA_MAMBA,
        PIXI,
        HOST_R,
        RENV,
        HOST_PYTHON,
        QUARTO;

        public string to_string_id () {
            switch (this) {
                case UV_PROJECT: return "uv";
                case VENV: return "venv";
                case CONDA_MAMBA: return "conda";
                case PIXI: return "pixi";
                case HOST_R: return "r";
                case RENV: return "renv";
                case QUARTO: return "quarto";
                case HOST_PYTHON:
                default: return "python";
            }
        }
    }

    public class DiscoveredEnv : GLib.Object {
        public DiscoveredEnvKind kind { get; set; }
        public string name { owned get; set; default = ""; }
        public string path { owned get; set; default = ""; }
        public string project_dir { owned get; set; default = ""; }
        public string version { owned get; set; default = ""; }
        public string kernel_type { owned get; set; default = "python"; }

        public DiscoveredEnv (
            DiscoveredEnvKind kind,
            string name,
            string path,
            string version = "",
            string kernel_type = "python",
            string project_dir = ""
        ) {
            this.kind = kind;
            this.name = name;
            this.path = path;
            this.version = version;
            this.kernel_type = kernel_type;
            this.project_dir = project_dir;
        }

        public string display_label () {
            if (version.length > 0) {
                return "%s (%s)".printf (name, version);
            }
            return name;
        }
    }

    public class EnvDiscoveryResult : GLib.Object {
        public string workspace_dir { owned get; set; default = ""; }
        public Gee.ArrayList<DiscoveredEnv> environments { get; private set; }
        public string? latest_r_path { owned get; set; default = null; }
        public string latest_r_version { owned get; set; default = ""; }
        public string? quarto_path { owned get; set; default = null; }
        public string quarto_version { owned get; set; default = ""; }
        public string? uv_path { owned get; set; default = null; }
        public string? conda_bin { owned get; set; default = null; }
        public string? host_python_path { owned get; set; default = null; }
        public string? project_venv_path { owned get; set; default = null; }
        public bool has_renv { get; set; default = false; }
        public bool has_pyproject { get; set; default = false; }
        public bool has_uv_lock { get; set; default = false; }
        public bool has_pixi { get; set; default = false; }
        public int64 probed_at_unix { get; set; default = 0; }

        public EnvDiscoveryResult () {
            environments = new Gee.ArrayList<DiscoveredEnv> ();
        }
    }

    /**
     * Layer 2: EnvDiscovery
     *
     * Runs a single-shot POSIX shell probe on the host via `HostBridge` to
     * discover project-local environments (.venv, renv, pyproject.toml, pixi.toml),
     * uv, Conda/Mamba, Host R (including rig multi-version R installs),
     * Quarto, and Host Python, then caches the parsed result in memory.
     */
    public class EnvDiscovery : GLib.Object {
        private static EnvDiscovery? _instance = null;
        private Gee.HashMap<string, EnvDiscoveryResult> cache = new Gee.HashMap<string, EnvDiscoveryResult> ();

        public signal void environments_updated (EnvDiscoveryResult result);

        public static EnvDiscovery get_default () {
            if (_instance == null) {
                _instance = new EnvDiscovery ();
            }
            return _instance;
        }

        public EnvDiscoveryResult? get_cached (string? workspace_dir = null) {
            string key = normalize_ws (workspace_dir);
            return cache.has_key (key) ? cache.get (key) : null;
        }

        public void clear_cache () {
            cache.clear ();
        }

        private static string normalize_ws (string? workspace_dir) {
            if (workspace_dir == null) {
                return "";
            }
            return workspace_dir.strip ();
        }

        public async EnvDiscoveryResult discover_async (
            string? workspace_dir = null,
            bool force_rescan = false,
            Cancellable? cancellable = null
        ) {
            string ws = normalize_ws (workspace_dir);
            if (!force_rescan && cache.has_key (ws)) {
                return cache.get (ws);
            }

            string raw_json = "";
            try {
                string script = build_probe_script ();
                raw_json = yield HostBridge.run_capture_async (
                    { "/bin/sh", "-c", script, "_", ws },
                    ws.length > 0 ? ws : null,
                    null,
                    cancellable
                );
            } catch (GLib.Error e) {
                GLib.debug ("EnvDiscovery host probe failed: %s", e.message);
            }

            var result = parse_probe_json (raw_json, ws);
            cache.set (ws, result);
            environments_updated (result);
            return result;
        }

        public static string build_probe_script () {
            return """
WS="$1"
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }

VENV_PATH=""
HAS_RENV="false"
HAS_PYPROJECT="false"
HAS_UV_LOCK="false"
HAS_PIXI="false"
if [ -n "$WS" ] && [ -d "$WS" ]; then
  if [ -x "$WS/.venv/bin/python" ]; then VENV_PATH="$WS/.venv";
  elif [ -x "$WS/venv/bin/python" ]; then VENV_PATH="$WS/venv"; fi
  [ -f "$WS/renv/activate.R" ] && HAS_RENV="true"
  [ -f "$WS/pyproject.toml" ] && HAS_PYPROJECT="true"
  [ -f "$WS/uv.lock" ] && HAS_UV_LOCK="true"
  [ -f "$WS/pixi.toml" ] && HAS_PIXI="true"
fi

UV_BIN=""
if command -v uv >/dev/null 2>&1; then UV_BIN=$(command -v uv);
elif [ -x "$HOME/.local/bin/uv" ]; then UV_BIN="$HOME/.local/bin/uv"; fi

CONDA_BIN=""
for cb in conda mamba micromamba; do
  if command -v "$cb" >/dev/null 2>&1; then CONDA_BIN=$(command -v "$cb"); break; fi
done

QUARTO_BIN=""
QUARTO_VER=""
for qb in "$(command -v quarto 2>/dev/null)" /usr/local/bin/quarto /usr/bin/quarto "$HOME/.local/bin/quarto" /opt/quarto/bin/quarto; do
  if [ -n "$qb" ] && [ -x "$qb" ]; then
    QUARTO_BIN="$qb"
    QUARTO_VER=$("$qb" --version 2>/dev/null | head -n1)
    break
  fi
done

PY_BIN=""
for pb in "$(command -v python3 2>/dev/null)" /usr/bin/python3; do
  if [ -n "$pb" ] && [ -x "$pb" ]; then PY_BIN="$pb"; break; fi
done

printf '{'
printf '"workspace":"%s",' "$(esc "$WS")"
printf '"project":{"venv":"%s","renv":%s,"pyproject":%s,"uv_lock":%s,"pixi":%s},' "$(esc "$VENV_PATH")" "$HAS_RENV" "$HAS_PYPROJECT" "$HAS_UV_LOCK" "$HAS_PIXI"
printf '"uv":{"bin":"%s"},' "$(esc "$UV_BIN")"
printf '"conda_bin":"%s",' "$(esc "$CONDA_BIN")"
printf '"quarto":{"bin":"%s","version":"%s"},' "$(esc "$QUARTO_BIN")" "$(esc "$QUARTO_VER")"
printf '"python":{"bin":"%s"},' "$(esc "$PY_BIN")"

printf '"conda":['
FIRST_CONDA=1
if [ -f "$HOME/.conda/environments.txt" ]; then
  while IFS= read -r ep; do
    [ -n "$ep" ] && [ -d "$ep" ] || continue
    [ "$FIRST_CONDA" -eq 0 ] && printf ','
    FIRST_CONDA=0
    printf '"%s"' "$(esc "$ep")"
  done < "$HOME/.conda/environments.txt"
fi
if [ "$FIRST_CONDA" -eq 1 ] && [ -n "$CONDA_BIN" ]; then
  case "$(basename "$CONDA_BIN")" in
    micromamba) CONDA_LIST=$("$CONDA_BIN" env list 2>/dev/null | awk '/^\s*[^#]/ && NF>=2 {print $NF}') ;;
    *) CONDA_LIST=$("$CONDA_BIN" info --envs 2>/dev/null | awk '/^\s*[^#]/ && NF>=2 {print $NF}') ;;
  esac
  for ep in $CONDA_LIST; do
    [ -d "$ep" ] || continue
    [ "$FIRST_CONDA" -eq 0 ] && printf ','
    FIRST_CONDA=0
    printf '"%s"' "$(esc "$ep")"
  done
fi
printf '],'

printf '"r":['
FIRST_R=1
SEEN_R=""
for rb in "$(command -v Rscript 2>/dev/null)" /usr/bin/Rscript /usr/local/bin/Rscript /opt/R/*/bin/Rscript; do
  [ -n "$rb" ] && [ -x "$rb" ] || continue
  case ":$SEEN_R:" in *":$rb:"*) continue ;; esac
  SEEN_R="$SEEN_R:$rb"
  RV=$("$rb" --version 2>&1 | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -n1)
  [ "$FIRST_R" -eq 0 ] && printf ','
  FIRST_R=0
  printf '{"path":"%s","version":"%s"}' "$(esc "$rb")" "$(esc "$RV")"
done
printf ']'
printf '}\n'
""";
        }

        public static int compare_versions (string a, string b) {
            string[] pa = a.split (".");
            string[] pb = b.split (".");
            int max_len = int.max (pa.length, pb.length);
            for (int i = 0; i < max_len; i++) {
                int va = (i < pa.length) ? int.parse (pa[i]) : 0;
                int vb = (i < pb.length) ? int.parse (pb[i]) : 0;
                if (va != vb) {
                    return va > vb ? 1 : -1;
                }
            }
            return 0;
        }

        public static EnvDiscoveryResult parse_probe_json (string json_text, string workspace_dir = "") {
            var res = new EnvDiscoveryResult ();
            res.workspace_dir = workspace_dir;
            res.probed_at_unix = GLib.get_real_time () / 1000000;

            string trimmed = json_text.strip ();
            if (trimmed.length == 0 || !trimmed.has_prefix ("{")) {
                return res;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_data (trimmed, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return res;
                }
                var obj = root.get_object ();

                if (obj.has_member ("project")) {
                    var proj = obj.get_object_member ("project");
                    if (proj != null) {
                        string venv = proj.has_member ("venv") ? (proj.get_string_member ("venv") ?? "") : "";
                        if (venv.length > 0) {
                            res.project_venv_path = venv;
                            res.environments.add (new DiscoveredEnv (
                                DiscoveredEnvKind.VENV,
                                "Project .venv",
                                venv,
                                "",
                                "python",
                                workspace_dir
                            ));
                        }
                        res.has_renv = proj.has_member ("renv") && proj.get_boolean_member ("renv");
                        res.has_pyproject = proj.has_member ("pyproject") && proj.get_boolean_member ("pyproject");
                        res.has_uv_lock = proj.has_member ("uv_lock") && proj.get_boolean_member ("uv_lock");
                        res.has_pixi = proj.has_member ("pixi") && proj.get_boolean_member ("pixi");

                        if (res.has_renv) {
                            res.environments.add (new DiscoveredEnv (
                                DiscoveredEnvKind.RENV,
                                "Project renv",
                                workspace_dir,
                                "",
                                "r",
                                workspace_dir
                            ));
                        }
                        if (res.has_pixi) {
                            res.environments.add (new DiscoveredEnv (
                                DiscoveredEnvKind.PIXI,
                                "Project pixi",
                                workspace_dir,
                                "",
                                "python",
                                workspace_dir
                            ));
                        }
                    }
                }

                if (obj.has_member ("uv")) {
                    var uv_obj = obj.get_object_member ("uv");
                    if (uv_obj != null && uv_obj.has_member ("bin")) {
                        string uv_bin = uv_obj.get_string_member ("bin") ?? "";
                        if (uv_bin.length > 0) {
                            res.uv_path = uv_bin;
                            if (res.has_pyproject || res.has_uv_lock) {
                                res.environments.add (new DiscoveredEnv (
                                    DiscoveredEnvKind.UV_PROJECT,
                                    "uv project",
                                    uv_bin,
                                    "",
                                    "python",
                                    workspace_dir
                                ));
                            }
                        }
                    }
                }

                if (obj.has_member ("conda_bin")) {
                    string cb = obj.get_string_member ("conda_bin") ?? "";
                    if (cb.length > 0) {
                        res.conda_bin = cb;
                    }
                }

                if (obj.has_member ("conda")) {
                    var conda_arr = obj.get_array_member ("conda");
                    if (conda_arr != null) {
                        for (uint i = 0; i < conda_arr.get_length (); i++) {
                            string ep = conda_arr.get_string_element (i) ?? "";
                            if (ep.length > 0) {
                                string name = GLib.Path.get_basename (ep);
                                res.environments.add (new DiscoveredEnv (
                                    DiscoveredEnvKind.CONDA_MAMBA,
                                    @"Conda: $name",
                                    ep,
                                    "",
                                    "python",
                                    workspace_dir
                                ));
                            }
                        }
                    }
                }

                if (obj.has_member ("r")) {
                    var r_arr = obj.get_array_member ("r");
                    if (r_arr != null) {
                        for (uint i = 0; i < r_arr.get_length (); i++) {
                            var r_obj = r_arr.get_object_element (i);
                            if (r_obj == null) {
                                continue;
                            }
                            string r_path = r_obj.has_member ("path") ? (r_obj.get_string_member ("path") ?? "") : "";
                            string r_ver = r_obj.has_member ("version") ? (r_obj.get_string_member ("version") ?? "") : "";
                            if (r_path.length > 0) {
                                res.environments.add (new DiscoveredEnv (
                                    DiscoveredEnvKind.HOST_R,
                                    "Host R",
                                    r_path,
                                    r_ver,
                                    "r",
                                    workspace_dir
                                ));
                                if (res.latest_r_path == null ||
                                    compare_versions (r_ver, res.latest_r_version) > 0) {
                                    res.latest_r_path = r_path;
                                    res.latest_r_version = r_ver;
                                }
                            }
                        }
                    }
                }

                if (obj.has_member ("quarto")) {
                    var q_obj = obj.get_object_member ("quarto");
                    if (q_obj != null) {
                        string q_bin = q_obj.has_member ("bin") ? (q_obj.get_string_member ("bin") ?? "") : "";
                        string q_ver = q_obj.has_member ("version") ? (q_obj.get_string_member ("version") ?? "") : "";
                        if (q_bin.length > 0) {
                            res.quarto_path = q_bin;
                            res.quarto_version = q_ver;
                            res.environments.add (new DiscoveredEnv (
                                DiscoveredEnvKind.QUARTO,
                                "Quarto",
                                q_bin,
                                q_ver,
                                "quarto",
                                workspace_dir
                            ));
                        }
                    }
                }

                if (obj.has_member ("python")) {
                    var py_obj = obj.get_object_member ("python");
                    if (py_obj != null && py_obj.has_member ("bin")) {
                        string py_bin = py_obj.get_string_member ("bin") ?? "";
                        if (py_bin.length > 0) {
                            res.host_python_path = py_bin;
                            res.environments.add (new DiscoveredEnv (
                                DiscoveredEnvKind.HOST_PYTHON,
                                "Host Python",
                                py_bin,
                                "",
                                "python",
                                workspace_dir
                            ));
                        }
                    }
                }
            } catch (GLib.Error e) {
                GLib.warning ("EnvDiscovery failed to parse probe JSON: %s", e.message);
            }

            return res;
        }
    }
}
