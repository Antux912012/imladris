// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

namespace Imladris {

    public class MallornManager : GLib.Object {

        public const string MALLORN_SPEC_VERSION = "1.0";

        /**
         * Checks if a .mallorn file is a binary archive (.tar.zst or .zip) or a DCF text manifest.
         */
        public static bool is_mallorn_archive (string mallorn_path) {
            try {
                var file = File.new_for_path (mallorn_path);
                if (!file.query_exists ()) return false;
                var dis = new DataInputStream (file.read (null));
                uint8[] header = new uint8[4];
                size_t bytes_read = 0;
                dis.read_all (header, out bytes_read, null);
                bool is_zip = (bytes_read >= 4 && header[0] == 0x50 && header[1] == 0x4b && header[2] == 0x03 && header[3] == 0x04);
                bool is_zstd = (bytes_read >= 4 && header[0] == 0x28 && header[1] == 0xb5 && header[2] == 0x2f && header[3] == 0xfd);
                return is_zip || is_zstd;
            } catch (GLib.Error e) {
                return false;
            }
        }

        /**
         * Generates the 1:1 RStudio-compatible DCF/INI manifest header with
         * extended Imladris* metadata.
         */
        public static string generate_rproj_manifest (ProjectConfig config) {
            var sb = new StringBuilder ();
            sb.append ("Version: 1.0\n");
            sb.append ("RestoreWorkspace: Default\n");
            sb.append ("SaveWorkspace: Default\n");
            sb.append ("AlwaysSaveHistory: Default\n");
            sb.append ("EnableCodeIndexing: Yes\n");
            sb.append ("UseSpacesForTab: Yes\n");
            sb.append ("NumSpacesForTab: 2\n");
            sb.append ("Encoding: UTF-8\n");
            sb.append ("RnwWeave: knitr\n");
            sb.append ("LaTeX: pdfLaTeX\n");
            sb.append ("AutoAppendNewline: Yes\n");
            sb.append ("StripTrailingWhitespace: Yes\n");
            sb.append ("\n");
            sb.append ("# Imladris Extended Metadata\n");
            sb.append_printf ("ImladrisVersion: %s\n", config.imladris_version != "" ? config.imladris_version : MALLORN_SPEC_VERSION);
            sb.append_printf ("ImladrisProjectType: %s\n", config.project_type.to_string ());
            sb.append_printf ("ImladrisPrimaryFormat: %s\n", config.format.get_short_code ());
            if (config.project_name.strip () != "") {
                sb.append_printf ("ImladrisProjectName: %s\n", config.project_name.strip ());
            }
            if (config.author.strip () != "") {
                sb.append_printf ("ImladrisAuthor: %s\n", config.author.strip ());
            }
            sb.append_printf ("ImladrisSandboxed: %s\n", config.sandboxed ? "true" : "false");
            return sb.str;
        }

        /**
         * Creates a standard RStudio .Rproj manifest file in the designated directory.
         *
         * @param target_dir Directory where the .Rproj file will reside.
         * @param project_name Base name of the project.
         * @param config Optional ProjectConfig with metadata overrides.
         * @return File object referencing the created .Rproj file.
         */
        public static File create_rproj_file (string target_dir, string project_name, ProjectConfig? config = null) throws GLib.Error {
            File dir = File.new_for_path (target_dir);
            if (!dir.query_exists ()) {
                dir.make_directory_with_parents (null);
            }

            string clean_name = ProjectScaffolder.sanitize_dirname (project_name);
            var cfg = config != null ? config.clone () : new ProjectConfig () {
                project_name = clean_name,
                format = DocumentFormat.RSCRIPT
            };

            string manifest = generate_rproj_manifest (cfg);
            string rproj_path = Path.build_filename (target_dir, clean_name + ".Rproj");
            FileUtils.set_contents (rproj_path, manifest);

            return File.new_for_path (rproj_path);
        }

        /**
         * Scaffolds an entire RStudio-compatible project directory structure with .Rproj,
         * .Rprofile, data/ and scripts/ directories, and starter code.
         *
         * @param parent_dir Directory where the project directory will be created.
         * @param project_name Name of the R project.
         * @param primary_format Starting format (RSCRIPT, RMD, or QMD).
         * @param sandboxed Whether to initialize renv isolated package environment.
         * @return File object referencing the created .Rproj file.
         */
        public static File create_rproj_project (
            string parent_dir,
            string project_name,
            DocumentFormat primary_format = DocumentFormat.RSCRIPT,
            bool sandboxed = false
        ) throws GLib.Error {
            string clean_name = ProjectScaffolder.sanitize_dirname (project_name);
            string project_dir = Path.build_filename (parent_dir, clean_name);

            File pdir = File.new_for_path (project_dir);
            if (!pdir.query_exists ()) {
                pdir.make_directory_with_parents (null);
            }

            // Subdirectories: data, scripts, output
            string data_dir = Path.build_filename (project_dir, "data");
            string scripts_dir = Path.build_filename (project_dir, "scripts");
            string output_dir = Path.build_filename (project_dir, "output");

            File.new_for_path (data_dir).make_directory_with_parents (null);
            File.new_for_path (scripts_dir).make_directory_with_parents (null);
            File.new_for_path (output_dir).make_directory_with_parents (null);

            var cfg = new ProjectConfig () {
                project_name = clean_name,
                custom_project_dir = project_dir,
                format = primary_format,
                project_type = sandboxed ? ProjectType.SANDBOXED : ProjectType.STANDARD,
                sandboxed = sandboxed
            };

            // Write 1:1 .Rproj manifest
            File rproj_file = create_rproj_file (project_dir, clean_name, cfg);

            // Write .Rprofile for RStudio environment parity
            string rprofile_path = Path.build_filename (project_dir, ".Rprofile");
            string rprofile_content = """# ==============================================================================
# Rprofile initialized by Imladris for RStudio Parity
# ==============================================================================

options(repos = c(CRAN = "https://cloud.r-project.org/"))
options(stringsAsFactors = FALSE)
message("✔ RStudio project environment initialized for: %s")
""".printf (clean_name);
            FileUtils.set_contents (rprofile_path, rprofile_content);

            // Write starter primary file
            string starter_filename = "main.R";
            if (primary_format == DocumentFormat.RMD) {
                starter_filename = "analysis.Rmd";
            } else if (primary_format == DocumentFormat.QMD) {
                starter_filename = "analysis.qmd";
            } else if (primary_format == DocumentFormat.IPYNB) {
                starter_filename = "notebook.ipynb";
            }

            string starter_path = Path.build_filename (project_dir, starter_filename);
            File starter_file = File.new_for_path (starter_path);
            if (!starter_file.query_exists ()) {
                string template = ProjectScaffolder.build_template (cfg, project_dir, data_dir, "images", "references.bib");
                FileUtils.set_contents (starter_path, template);
            }

            // Sync with .mallorn manifests
            write_project_manifests (project_dir, cfg);

            // If sandboxed, initialize renv and Python .venv (for polyglot QMD/IPYNB)
            if (sandboxed) {
                try {
                    Services.SandboxController.init_r_sandbox (project_dir);
                    if (primary_format == DocumentFormat.QMD || primary_format == DocumentFormat.IPYNB || primary_format == DocumentFormat.PYSCRIPT) {
                        Services.SandboxController.init_py_sandbox (project_dir);
                    }
                    string rprof_curr = "";
                    if (FileUtils.test (rprofile_path, FileTest.EXISTS)) {
                        FileUtils.get_contents (rprofile_path, out rprof_curr);
                    }
                    if (!rprof_curr.contains ("renv/activate.R")) {
                        rprof_curr += "\nif (file.exists(\"renv/activate.R\")) source(\"renv/activate.R\")\n";
                        FileUtils.set_contents (rprofile_path, rprof_curr);
                    }
                } catch (GLib.Error e) {
                    // Non-fatal if host Rscript/python3 unavailable
                }
            }

            return rproj_file;
        }

        /**
         * Parses a .mallorn or .Rproj DCF/INI manifest into a ProjectConfig instance.
         */
        public static ProjectConfig parse_manifest (string content) {
            var config = new ProjectConfig ();
            string[] lines = content.split ("\n");

            foreach (string raw_line in lines) {
                string line = raw_line.strip ();
                if (line.length == 0 || line.has_prefix ("#")) {
                    continue;
                }
                int colon_idx = line.index_of (":");
                if (colon_idx < 0) continue;

                string key = line.substring (0, colon_idx).strip ();
                string val = line.substring (colon_idx + 1).strip ();

                if (key == "ImladrisProjectType") {
                    config.project_type = ProjectType.from_string (val);
                } else if (key == "ImladrisPrimaryFormat") {
                    config.format = DocumentFormat.from_short_code (val);
                } else if (key == "ImladrisProjectName") {
                    config.project_name = val;
                } else if (key == "ImladrisAuthor") {
                    config.author = val;
                } else if (key == "ImladrisVersion") {
                    config.imladris_version = val;
                } else if (key == "ImladrisSandboxed") {
                    config.sandboxed = (val.down () == "true" || val == "1");
                }
            }
            return config;
        }

        /**
         * Writes <project_name>.mallorn, <project_name>.Rproj (1:1 RStudio parity),
         * .mallorn.json (Imladris workspace state) and imladris.toml in project_dir.
         */
        public static void write_project_manifests (string project_dir, ProjectConfig config) throws GLib.Error {
            File dir = File.new_for_path (project_dir);
            if (!dir.query_exists ()) {
                dir.make_directory_with_parents (null);
            }

            string clean_name = ProjectScaffolder.sanitize_dirname (config.project_name);
            string manifest_content = generate_rproj_manifest (config);

            // 1. Write <project_name>.mallorn
            string mallorn_file_path = Path.build_filename (project_dir, clean_name + ".mallorn");
            FileUtils.set_contents (mallorn_file_path, manifest_content);

            // 2. Write 1:1 <project_name>.Rproj
            string rproj_file_path = Path.build_filename (project_dir, clean_name + ".Rproj");
            FileUtils.set_contents (rproj_file_path, manifest_content);

            // 3. Write .mallorn.json (State, UI layout, metadata)
            string now_iso = new DateTime.now_utc ().format_iso8601 ();
            var json_builder = new Json.Builder ();
            json_builder.begin_object ();
            json_builder.set_member_name ("imladris_version");
            json_builder.add_string_value (config.imladris_version);
            json_builder.set_member_name ("project_name");
            json_builder.add_string_value (config.project_name);
            json_builder.set_member_name ("author");
            json_builder.add_string_value (config.author);
            json_builder.set_member_name ("project_type");
            json_builder.add_string_value (config.project_type.to_string ());
            json_builder.set_member_name ("primary_format");
            json_builder.add_string_value (config.format.get_short_code ());
            json_builder.set_member_name ("sandboxed");
            json_builder.add_boolean_value (config.sandboxed);
            json_builder.set_member_name ("created_at");
            json_builder.add_string_value (now_iso);
            json_builder.set_member_name ("rstudio_compatible");
            json_builder.add_boolean_value (true);
            json_builder.end_object ();

            var json_gen = new Json.Generator ();
            json_gen.set_root (json_builder.get_root ());
            json_gen.pretty = true;
            string json_content = json_gen.to_data (null);
            string json_file_path = Path.build_filename (project_dir, ".mallorn.json");
            FileUtils.set_contents (json_file_path, json_content);

            // 4. Write imladris.toml
            string toml_content = """[project]
name = "%s"
version = "%s"
sandboxed = %s
format = "%s"
author = "%s"
""".printf (
                escape_toml_string (config.project_name),
                escape_toml_string (config.imladris_version),
                config.sandboxed ? "true" : "false",
                escape_toml_string (config.format.get_short_code ()),
                escape_toml_string (config.author)
            );
            string toml_file_path = Path.build_filename (project_dir, "imladris.toml");
            FileUtils.set_contents (toml_file_path, toml_content);
        }

        private static string escape_toml_string (string val) {
            return val.replace ("\\", "\\\\")
                      .replace ("\"", "\\\"")
                      .replace ("\n", "\\n")
                      .replace ("\r", "\\r")
                      .replace ("\t", "\\t");
        }

        /**
         * Ensures <name>.mallorn and <name>.Rproj stay 1:1 synchronized in project_dir.
         */
        public static void sync_rproj_and_mallorn (string project_dir) throws GLib.Error {
            File dir = File.new_for_path (project_dir);
            if (!dir.query_exists ()) return;

            string? mallorn_path = null;
            string? rproj_path = null;

            var enumerator = dir.enumerate_children ("standard::name", FileQueryInfoFlags.NONE, null);
            FileInfo? info = null;
            while ((info = enumerator.next_file (null)) != null) {
                string name = info.get_name ();
                if (name.has_suffix (".mallorn")) {
                    mallorn_path = Path.build_filename (project_dir, name);
                } else if (name.has_suffix (".Rproj")) {
                    rproj_path = Path.build_filename (project_dir, name);
                }
            }

            if (mallorn_path != null && rproj_path == null) {
                string base_no_ext = mallorn_path.substring (0, mallorn_path.length - 8);
                string new_rproj = base_no_ext + ".Rproj";
                string content;
                FileUtils.get_contents (mallorn_path, out content);
                FileUtils.set_contents (new_rproj, content);
            } else if (rproj_path != null && mallorn_path == null) {
                string base_no_ext = rproj_path.substring (0, rproj_path.length - 6);
                string new_mallorn = base_no_ext + ".mallorn";
                string content;
                FileUtils.get_contents (rproj_path, out content);
                FileUtils.set_contents (new_mallorn, content);
            }
        }

        /**
         * Packages the workspace as a standard .mallorn exchange archive (.tar.zst or .zip)
         */
        public static void pack_mallorn_archive (string project_dir, string output_path) throws GLib.Error {
            File pdir = File.new_for_path (project_dir);
            if (!pdir.query_exists ()) {
                throw new IOError.NOT_FOUND (@"Project directory not found: $project_dir");
            }

            // Sync manifests before archiving
            sync_rproj_and_mallorn (project_dir);

            // Ensure destination folder exists
            string? out_parent = Path.get_dirname (output_path);
            if (out_parent != null) {
                File op = File.new_for_path (out_parent);
                if (!op.query_exists ()) op.make_directory_with_parents (null);
            }

            // Attempt tar --zstd first (excluding heavy/ephemeral runtime environments)
            bool success = false;
            bool want_zip = output_path.down ().has_suffix (".zip");
            if (!want_zip) {
                try {
                    string[] argv = {
                        "tar", "-C", project_dir,
                        "--exclude=.imladris-env", "--exclude=.venv",
                        "--exclude=renv/library", "--exclude=.git",
                        "--exclude=node_modules",
                        "--zstd", "-cf", output_path, "."
                    };
                    var proc = new Subprocess.newv (argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                    success = proc.wait_check ();
                } catch (GLib.Error e) {
                    success = false;
                }
                if (!success) {
                    throw new IOError.FAILED (@"Failed to pack .mallorn tar.zst archive: $output_path");
                }
            } else {
                // Explicit .zip variant via python3 zipfile
                string py_code = "import zipfile, os, sys\n"
                    + "src, dst = sys.argv[1], sys.argv[2]\n"
                    + "skip = {'.imladris-env', '.venv', '.git', 'node_modules'}\n"
                    + "with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zf:\n"
                    + "    for root, dirs, files in os.walk(src):\n"
                    + "        dirs[:] = [d for d in dirs if d not in skip]\n"
                    + "        if os.path.basename(root) == 'renv' and 'library' in dirs:\n"
                    + "            dirs.remove('library')\n"
                    + "        for f in files:\n"
                    + "            p = os.path.join(root, f)\n"
                    + "            rel = os.path.relpath(p, src)\n"
                    + "            zf.write(p, rel)\n";

                string[] py_argv = { "python3", "-c", py_code, project_dir, output_path };
                var py_proc = new Subprocess.newv (py_argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                py_proc.wait_check ();
            }
        }

        /**
         * Unpacks a .mallorn exchange archive or initializes from a DCF project file,
         * ensuring 1:1 RStudio parity and returning the loaded ProjectConfig.
         */
        public static ProjectConfig unpack_mallorn_archive (string mallorn_path, string target_dir) throws GLib.Error {
            File mfile = File.new_for_path (mallorn_path);
            if (!mfile.query_exists ()) {
                throw new IOError.NOT_FOUND (@"Mallorn path not found: $mallorn_path");
            }

            File tdir = File.new_for_path (target_dir);
            if (!tdir.query_exists ()) {
                tdir.make_directory_with_parents (null);
            }

            // Inspect header bytes
            uint8[] header = new uint8[8];
            size_t bytes_read = 0;
            var dis = new DataInputStream (mfile.read (null));
            dis.read_all (header, out bytes_read, null);

            bool is_zip = (bytes_read >= 4 && header[0] == 0x50 && header[1] == 0x4b && header[2] == 0x03 && header[3] == 0x04);
            bool is_zstd = (bytes_read >= 4 && header[0] == 0x28 && header[1] == 0xb5 && header[2] == 0x2f && header[3] == 0xfd);

            if (is_zstd) {
                // Validate archive member types (reject symlinks/hardlinks/devices) and paths before extraction
                string[] list_argv = { "tar", "--zstd", "-tvf", mallorn_path };
                var list_proc = new Subprocess.newv (list_argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                string list_out, list_err;
                list_proc.communicate_utf8 (null, null, out list_out, out list_err);
                if (!list_proc.get_successful ()) {
                    throw new GLib.IOError.FAILED (@"Failed to inspect .mallorn archive: $list_err");
                }
                foreach (string raw_line in (list_out ?? "").split ("\n")) {
                    string line = raw_line.strip ();
                    if (line.length == 0) continue;
                    char ftype = line[0];
                    if (ftype == 'l' || ftype == 'h' || ftype == 'b' || ftype == 'c' || ftype == 'p') {
                        throw new GLib.IOError.PERMISSION_DENIED (@"Rejected unsafe link/device archive entry: $line");
                    }
                    // Parse `tar -tvf` line: 5 whitespace-separated fields (perms, owner, size, date, time) then member path
                    string trimmed_line = line.strip ();
                    int field_count = 0;
                    int idx = 0;
                    bool in_ws = false;
                    while (idx < trimmed_line.length && field_count < 5) {
                        bool ws = (trimmed_line[idx] == ' ' || trimmed_line[idx] == '\t');
                        if (!ws && !in_ws) {
                            in_ws = false;
                        } else if (ws && !in_ws) {
                            field_count++;
                            in_ws = true;
                        } else if (!ws && in_ws) {
                            in_ws = false;
                        }
                        idx++;
                    }
                    while (idx < trimmed_line.length && (trimmed_line[idx] == ' ' || trimmed_line[idx] == '\t')) {
                        idx++;
                    }
                    string entry = (field_count == 5 && idx < trimmed_line.length) ? trimmed_line.substring (idx) : trimmed_line;
                    string norm = entry.strip ().replace ("\\", "/");
                    if (norm.has_prefix ("/") || norm.has_prefix ("~")) {
                        throw new GLib.IOError.PERMISSION_DENIED (@"Rejected unsafe absolute archive path: $entry");
                    }
                    foreach (string seg in norm.split ("/")) {
                        if (seg == "..") {
                            throw new GLib.IOError.PERMISSION_DENIED (@"Rejected archive path traversal entry: $entry");
                        }
                    }
                }
                string[] argv = { "tar", "-C", target_dir, "--zstd", "-xf", mallorn_path };
                var proc = new Subprocess.newv (argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                proc.wait_check ();
            } else if (is_zip) {
                // Validate zip member paths against traversal / absolute paths before extraction
                string[] check_argv = {
                    "python3", "-c",
                    "import sys, zipfile, os\n" +
                    "with zipfile.ZipFile(sys.argv[1]) as z:\n" +
                    "    for n in z.namelist():\n" +
                    "        p = n.replace('\\\\', '/')\n" +
                    "        if os.path.isabs(p) or p.startswith('~') or '..' in p.split('/'):\n" +
                    "            sys.exit(1)\n",
                    mallorn_path
                };
                var check_proc = new Subprocess.newv (check_argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                if (!check_proc.wait_check ()) {
                    throw new GLib.IOError.PERMISSION_DENIED ("Rejected unsafe zip archive entry containing path traversal or absolute path.");
                }
                string[] argv = { "python3", "-m", "zipfile", "-e", mallorn_path, target_dir };
                var proc = new Subprocess.newv (argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
                proc.wait_check ();
            } else {
                // If it's a plain DCF text file, copy into target_dir
                string content;
                FileUtils.get_contents (mallorn_path, out content);
                string base_filename = mfile.get_basename ();
                FileUtils.set_contents (Path.build_filename (target_dir, base_filename), content);
            }

            // Guarantee 1:1 synchronicity in extracted folder
            sync_rproj_and_mallorn (target_dir);

            // Locate manifest in target_dir to return ProjectConfig
            string? found_manifest = null;
            var enumerator = tdir.enumerate_children ("standard::name", FileQueryInfoFlags.NONE, null);
            FileInfo? info = null;
            while ((info = enumerator.next_file (null)) != null) {
                string name = info.get_name ();
                if (name.has_suffix (".mallorn") || name.has_suffix (".Rproj")) {
                    found_manifest = Path.build_filename (target_dir, name);
                    if (name.has_suffix (".mallorn")) break; // Prefer .mallorn
                }
            }

            if (found_manifest != null) {
                string text;
                FileUtils.get_contents (found_manifest, out text);
                var cfg = parse_manifest (text);
                cfg.custom_project_dir = target_dir;
                return cfg;
            }

            // Fallback default
            var fallback_cfg = new ProjectConfig ();
            fallback_cfg.project_name = tdir.get_basename ();
            fallback_cfg.custom_project_dir = target_dir;
            return fallback_cfg;
        }
    }
}
