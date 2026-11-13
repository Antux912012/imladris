// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris.Tests {

    public static int main (string[] args) {
        GLib.Test.init (ref args);

        GLib.Test.add_func ("/data_models/document_format", test_document_format);
        GLib.Test.add_func ("/data_models/project_type", test_project_type);
        GLib.Test.add_func ("/mallorn/manifest_generation_and_parsing", test_manifest_roundtrip);
        GL_Test_scaffolding_and_archive ();
        GLib.Test.add_func ("/sandbox/r_and_py_sandboxes", test_sandbox_controllers);
        GLib.Test.add_func ("/sandbox/export_rstudio_jupyter", test_sandbox_exports);
        GLib.Test.add_func ("/sandbox/restore_environment", test_sandbox_restore);
        GLib.Test.add_func ("/sessions/persistent_session_and_pwd_sync", test_persistent_session_and_pwd_sync);
        GLib.Test.add_func ("/export/odt_and_odp_pipeline", test_export_pipeline_odt_odp);
        GLib.Test.add_func ("/export/qmd_pdf_html_odt_rtf", test_export_qmd_pdf_html_odt_rtf);
        GLib.Test.add_func ("/export/html_css_latex_render", test_html_css_latex_render);
        GLib.Test.add_func ("/sessions/python_and_r_repl_execution", test_persistent_python_and_r_repl);
        GLib.Test.add_func ("/chunks/chunk_parser", test_chunk_parser);
        GLib.Test.add_func ("/execution/repl_bridge_and_chunk_engine", test_repl_bridge_and_chunk_engine);
        GLib.Test.add_func ("/core/platform_utils", test_platform_utils);
        GLib.Test.add_func ("/core/toolchain_manager", test_toolchain_manager);
        GLib.Test.add_func ("/core/runtime_resolution_tiers", test_runtime_resolution_tiers);
        GLib.Test.add_func ("/sessions/host_r_session", test_host_r_session);
        GLib.Test.add_func ("/media/image_and_video_processing", test_media_processing);
        GLib.Test.add_func ("/mallorn/rproj_creation_and_scaffolding", test_rproj_creation);
        GLib.Test.add_func ("/notebook/jupyter_nbformat_parity", test_notebook_serializer_parity);
        GLib.Test.add_func ("/math_chem/natural_math_and_chemistry_engine", test_math_chem_engine);
        GLib.Test.add_func ("/mermaid/visual_flow_and_mindmap_engine", test_mermaid_flow_engine);
        GLib.Test.add_func ("/editor/vscode_polyglot_intellisense", test_vscode_polyglot_intellisense);

        return GLib.Test.run ();
    }

    private static void GL_Test_scaffolding_and_archive () {
        GLib.Test.add_func ("/mallorn/scaffold_and_pack_unpack", test_scaffold_pack_unpack);
    }

    private static void test_document_format () {
        assert (DocumentFormat.MD.get_extension () == ".md");
        assert (DocumentFormat.HTML.get_extension () == ".html");
        assert (DocumentFormat.RSCRIPT.get_extension () == ".R");
        assert (DocumentFormat.RMD.get_extension () == ".Rmd");
        assert (DocumentFormat.QMD.get_extension () == ".qmd");
        assert (DocumentFormat.IPYNB.get_extension () == ".ipynb");
        assert (DocumentFormat.PYSCRIPT.get_extension () == ".py");

        assert (DocumentFormat.from_filename ("report.qmd") == DocumentFormat.QMD);
        assert (DocumentFormat.from_filename ("analysis.Rmd") == DocumentFormat.RMD);
        assert (DocumentFormat.from_filename ("notebook.ipynb") == DocumentFormat.IPYNB);
        assert (DocumentFormat.from_filename ("script.R") == DocumentFormat.RSCRIPT);
        assert (DocumentFormat.from_filename ("app.py") == DocumentFormat.PYSCRIPT);
        assert (DocumentFormat.from_filename ("index.html") == DocumentFormat.HTML);
        assert (DocumentFormat.from_filename ("README.md") == DocumentFormat.MD);

        assert (DocumentFormat.QMD.is_computational_notebook ());
        assert (DocumentFormat.RMD.is_computational_notebook ());
        assert (DocumentFormat.IPYNB.is_computational_notebook ());
        assert (!DocumentFormat.MD.is_computational_notebook ());
    }

    private static void test_project_type () {
        assert (ProjectType.STANDARD.to_string () == "Standard");
        assert (ProjectType.SANDBOXED.to_string () == "Sandboxed");
        assert (ProjectType.from_string ("sandboxed") == ProjectType.SANDBOXED);
        assert (ProjectType.from_string ("Standard") == ProjectType.STANDARD);

        assert (ProjectType.SANDBOXED.get_badge_label () == "[Sandboxed - Reproducible]");
        assert (ProjectType.STANDARD.get_badge_label () == "[System Libraries - Non-Portable]");
    }

    private static void test_manifest_roundtrip () {
        var cfg = new ProjectConfig () {
            project_name = "QuantumAnalysis",
            author = "Ada Lovelace",
            project_type = ProjectType.SANDBOXED,
            format = DocumentFormat.QMD,
            imladris_version = "1.0"
        };

        string dcf = MallornManager.generate_rproj_manifest (cfg);
        assert (dcf.contains ("Version: 1.0"));
        assert (dcf.contains ("RestoreWorkspace: Default"));
        assert (dcf.contains ("ImladrisProjectType: Sandboxed"));
        assert (dcf.contains ("ImladrisPrimaryFormat: Qmd"));
        assert (dcf.contains ("ImladrisProjectName: QuantumAnalysis"));
        assert (dcf.contains ("ImladrisAuthor: Ada Lovelace"));
        assert (dcf.contains ("ImladrisSandboxed: true"));

        var parsed = MallornManager.parse_manifest (dcf);
        assert (parsed.project_name == "QuantumAnalysis");
        assert (parsed.author == "Ada Lovelace");
        assert (parsed.project_type == ProjectType.SANDBOXED);
        assert (parsed.format == DocumentFormat.QMD);
        assert (parsed.sandboxed == true);
    }

    private static void test_scaffold_pack_unpack () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), @"test_imladris_$(GLib.Random.next_int ())");
        string proj_dir = Path.build_filename (tmp_dir, "My_Test_Project");

        var cfg = new ProjectConfig () {
            project_name = "My_Test_Project",
            author = "Test Suite",
            project_type = ProjectType.STANDARD,
            format = DocumentFormat.QMD,
            custom_project_dir = proj_dir
        };

        try {
            File main_doc = ProjectScaffolder.create_project (cfg);
            assert (main_doc.query_exists ());
            assert (FileUtils.test (Path.build_filename (proj_dir, "My_Test_Project.qmd"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (proj_dir, "My_Test_Project.mallorn"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (proj_dir, "My_Test_Project.Rproj"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (proj_dir, ".mallorn.json"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (proj_dir, "imladris.toml"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (proj_dir, "bibliography", "references.bib"), FileTest.EXISTS));

            // Pack archive
            string archive_path = Path.build_filename (tmp_dir, "bundle.mallorn");
            MallornManager.pack_mallorn_archive (proj_dir, archive_path);
            assert (FileUtils.test (archive_path, FileTest.EXISTS));

            // Unpack archive to target_unpacked
            string unpack_dir = Path.build_filename (tmp_dir, "unpacked_proj");
            var unpacked_cfg = MallornManager.unpack_mallorn_archive (archive_path, unpack_dir);

            assert (FileUtils.test (Path.build_filename (unpack_dir, "My_Test_Project.mallorn"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (unpack_dir, "My_Test_Project.Rproj"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (unpack_dir, "My_Test_Project.qmd"), FileTest.EXISTS));
            assert (unpacked_cfg.project_name == "My_Test_Project");
            assert (unpacked_cfg.format == DocumentFormat.QMD);

        } catch (GLib.Error e) {
            GLib.error ("Scaffold & pack failed: %s", e.message);
        }
    }

    private static void test_sandbox_controllers () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), @"test_sandbox_$(GLib.Random.next_int ())");
        try {
            // Test R Sandbox initialization
            Services.SandboxController.init_r_sandbox (tmp_dir);
            assert (FileUtils.test (Path.build_filename (tmp_dir, ".Rprofile"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (tmp_dir, "renv", "activate.R"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (tmp_dir, "renv.lock"), FileTest.EXISTS));
            assert (Services.SandboxController.is_r_sandbox_active (tmp_dir));

            // Test Py Sandbox initialization
            Services.SandboxController.init_py_sandbox (tmp_dir);
            assert (FileUtils.test (Path.build_filename (tmp_dir, "requirements.txt"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (tmp_dir, ".venv", "share", "jupyter", "kernels", "imladris-sandbox", "kernel.json"), FileTest.EXISTS));
            assert (Services.SandboxController.detect_project_type (tmp_dir) == ProjectType.SANDBOXED);

        } catch (GLib.Error e) {
            GLib.error ("Sandbox test failed: %s", e.message);
        }
    }

    private static void test_sandbox_exports () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), @"test_export_$(GLib.Random.next_int ())");
        string src_dir = Path.build_filename (tmp_dir, "source");
        string rstudio_export_dir = Path.build_filename (tmp_dir, "export_rstudio");
        string jupyter_export_dir = Path.build_filename (tmp_dir, "export_jupyter");

        try {
            var cfg = new ProjectConfig () {
                project_name = "ExportBio",
                author = "Darwin",
                project_type = ProjectType.SANDBOXED,
                format = DocumentFormat.RMD,
                custom_project_dir = src_dir
            };
            ProjectScaffolder.create_project (cfg);

            // Export for RStudio
            Services.SandboxController.export_for_rstudio (src_dir, rstudio_export_dir);
            assert (FileUtils.test (Path.build_filename (rstudio_export_dir, "ExportBio.Rproj"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (rstudio_export_dir, ".Rprofile"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (rstudio_export_dir, "renv", "activate.R"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (rstudio_export_dir, "renv.lock"), FileTest.EXISTS));

            // Export for Jupyter
            Services.SandboxController.export_for_jupyter (src_dir, jupyter_export_dir);
            assert (FileUtils.test (Path.build_filename (jupyter_export_dir, "requirements.txt"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (jupyter_export_dir, "environment.yml"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (jupyter_export_dir, "setup_environment.sh"), FileTest.EXISTS));

        } catch (GLib.Error e) {
            GLib.error ("Export test failed: %s", e.message);
        }
    }

    private static void test_export_pipeline_odt_odp () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), @"test_export_pipeline_$(GLib.Random.next_int ())");
        DirUtils.create_with_parents (tmp_dir, 0755);

        string sample_md = Path.build_filename (tmp_dir, "document.md");
        string out_odt = Path.build_filename (tmp_dir, "output.odt");
        string out_odp = Path.build_filename (tmp_dir, "output.odp");

        try {
            FileUtils.set_contents (sample_md, "# Sample Title\n\nThis is paragraph one.\n\n## Slide 2\n- Bullet point A\n- Bullet point B\n");

            Services.ExportService.export_to_odt (sample_md, out_odt);
            assert (FileUtils.test (out_odt, FileTest.EXISTS));

            Services.ExportService.export_to_odp (sample_md, out_odp);
            assert (FileUtils.test (out_odp, FileTest.EXISTS));

            // Verify both are valid non-empty files (at least > 200 bytes)
            File f_odt = File.new_for_path (out_odt);
            var info_odt = f_odt.query_info ("standard::size", FileQueryInfoFlags.NONE);
            assert (info_odt.get_size () > 200);

            File f_odp = File.new_for_path (out_odp);
            var info_odp = f_odp.query_info ("standard::size", FileQueryInfoFlags.NONE);
            assert (info_odp.get_size () > 200);
        } catch (GLib.Error e) {
            GLib.error ("ODT/ODP Export test failed: %s", e.message);
        }
    }

    private static void test_sandbox_restore () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), "imladris_test_restore_" + Random.next_int ().to_string ());
        DirUtils.create_with_parents (tmp_dir, 0755);

        try {
            Services.SandboxController.init_r_sandbox (tmp_dir);
            Services.SandboxController.init_py_sandbox (tmp_dir);

            // Execute restore_environment and ensure it executes without crashing
            Services.SandboxController.restore_environment (tmp_dir);

            // Verify .Rprofile and requirements.txt still intact
            assert (FileUtils.test (Path.build_filename (tmp_dir, ".Rprofile"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (tmp_dir, "requirements.txt"), FileTest.EXISTS));
        } catch (GLib.Error e) {
            GLib.error ("Sandbox restore test failed: %s", e.message);
        }
    }

    private static void test_persistent_session_and_pwd_sync () {
        var sm = Services.PersistentSessionManager.get_default ();
        assert (sm != null);

        string target_dir = Environment.get_tmp_dir ();
        bool signal_received = false;
        string received_dir = "";

        ulong handler_id = sm.working_directory_changed.connect ((new_dir) => {
            signal_received = true;
            received_dir = new_dir;
        });

        sm.set_working_directory (target_dir, ProjectType.SANDBOXED);

        assert (signal_received);
        assert (received_dir == target_dir);
        assert (sm.current_working_dir == target_dir);
        assert (sm.active_project_type == ProjectType.SANDBOXED);

        sm.disconnect (handler_id);
    }

    private static void test_chunk_parser () {
        string doc = """# Sample Document

Here is an intro paragraph.

```{r}
#| label: setup
x <- 1:10
plot(x)
```

And some text in between.

```python
import numpy as np
print(np.mean([1, 2, 3]))
```
""";
        var chunks = Core.ChunkParser.parse_chunks (doc);
        assert (chunks.size == 2);
        assert (chunks[0].language == "r");
        assert (chunks[0].code.contains ("x <- 1:10"));
        assert (chunks[0].start_line == 4);
        assert (chunks[0].end_line == 8);

        assert (chunks[1].language == "python");
        assert (chunks[1].code.contains ("import numpy as np"));
        assert (chunks[1].start_line == 12);
        assert (chunks[1].end_line == 15);

        var ch_at_line_6 = Core.ChunkParser.find_chunk_at_line (doc, 6);
        assert (ch_at_line_6 != null);
        assert (ch_at_line_6.language == "r");

        var ch_at_line_13 = Core.ChunkParser.find_chunk_at_line (doc, 13);
        assert (ch_at_line_13 != null);
        assert (ch_at_line_13.language == "python");

        var ch_outside = Core.ChunkParser.find_chunk_at_line (doc, 2);
        assert (ch_outside == null);

        // Test comma-delimited headers, labels, and eval: false
        string complex_doc = """# Clinical Manuscript
```{r, table1_demographics, echo=FALSE, eval=FALSE}
summary(mtcars)
```

```{python py_sim, eval: false}
#| eval: false
print("eval false via hash-pipe")
```

```{r, label="valid_eval"}
#| eval: true
x <- 42
```
""";
        var comp_chunks = Core.ChunkParser.parse_chunks (complex_doc);
        assert (comp_chunks.size == 3);
        assert (comp_chunks[0].language == "r");
        assert (comp_chunks[0].chunk_label == "table1_demographics");
        assert (!comp_chunks[0].eval_enabled);

        assert (comp_chunks[1].language == "python");
        assert (comp_chunks[1].chunk_label == "py_sim");
        assert (!comp_chunks[1].eval_enabled);

        assert (comp_chunks[2].language == "r");
        assert (comp_chunks[2].eval_enabled);

        // Test Elbereth biostatistical normal quantile math
        double z_975 = Bridges.Elbereth.ClinicalBiostatsPopover.normal_quantile (0.975);
        assert (GLib.Math.fabs (z_975 - 1.95996) < 0.001);
        double cdf_0 = Bridges.Elbereth.ClinicalBiostatsPopover.normal_cdf (0.0);
        assert (GLib.Math.fabs (cdf_0 - 0.5) < 0.0001);
    }

    private static void test_repl_bridge_and_chunk_engine () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), "imladris_repl_test_" + Random.next_int ().to_string ());
        DirUtils.create_with_parents (tmp_dir, 0755);

        var py_bridge = new Execution.ReplBridge (Execution.LanguageRuntime.PYTHON, tmp_dir);
        var r_bridge = new Execution.ReplBridge (Execution.LanguageRuntime.R, tmp_dir);

        var loop = new MainLoop ();
        bool test_passed = false;

        py_bridge.start.begin ((obj, res) => {
            try {
                py_bridge.start.end (res);

                var engine = new Execution.ChunkExecutionEngine (tmp_dir, r_bridge, py_bridge);
                string test_code = "a = 21\nb = 2\nprint('Computed Result:', a * b)";

                engine.execute_chunk.begin (Execution.LanguageRuntime.PYTHON, test_code, "test1", (obj2, res2) => {
                    try {
                        var chunk_res = engine.execute_chunk.end (res2);
                        assert (chunk_res.stdout.contains ("Computed Result: 42"));

                        if (Gtk.init_check ()) {
                            var widget = new UI.InlineChunkOutputWidget (10);
                            widget.set_output (chunk_res.stdout, chunk_res.plot_path, 1);
                        }

                        py_bridge.stop ();
                        test_passed = true;
                    } catch (GLib.Error e) {
                        GLib.warning ("Chunk execution test failed: %s", e.message);
                    }
                    loop.quit ();
                });

            } catch (GLib.Error e) {
                GLib.warning ("ReplBridge start failed: %s", e.message);
                loop.quit ();
            }
        });

        // Safety timeout
        Timeout.add_seconds (15, () => {
            if (!test_passed) {
                py_bridge.stop ();
                loop.quit ();
            }
            return Source.REMOVE;
        });

        loop.run ();
        assert (test_passed);
    }

    private static void test_platform_utils () {
        // 1. Shared cache directory creation
        string cache_plots = Core.PlatformUtils.get_shared_cache_dir ("plots");
        assert (cache_plots.length > 0);
        assert (FileUtils.test (cache_plots, FileTest.IS_DIR));

        string cache_tmp = Core.PlatformUtils.get_shared_cache_dir ("tmp");
        assert (cache_tmp.length > 0);
        assert (FileUtils.test (cache_tmp, FileTest.IS_DIR));

        // 2. Host command wrapping
        string[] cmd = { "R", "--interactive" };
        string[] wrapped = Core.PlatformUtils.build_host_command (cmd, "/test/path");
        if (Core.PlatformUtils.is_flatpak ()) {
            assert (wrapped[0] == "flatpak-spawn");
            assert (wrapped[1] == "--host");
            assert (wrapped[2] == "--watch-bus");
            assert (wrapped[3] == "--directory=/test/path");
            assert (wrapped[4] == "R");
            assert (wrapped[5] == "--interactive");
        } else {
            assert (wrapped.length == 2);
            assert (wrapped[0] == "R");
            assert (wrapped[1] == "--interactive");
        }

        // 3. Program availability check
        assert (Core.PlatformUtils.is_program_available ("sh"));
        assert (!Core.PlatformUtils.is_program_available ("__non_existent_binary_xyz_123__"));
    }

    private static void test_toolchain_manager () {
        var tm = Core.ToolchainManager.get_default ();
        assert (tm != null);
        assert (tm.base_dir.length > 0);
        assert (tm.bin_dir.length > 0);
        assert (tm.mamba_bin.length > 0);
        assert (tm.mamba_root.length > 0);
        assert (tm.default_env.length > 0);

        string arch = Core.ToolchainManager.get_platform_arch ();
        assert (arch == "linux-64" || arch == "linux-aarch64");

        // Test Rprofile.site configuration writing
        string dummy_env = Path.build_filename (Environment.get_tmp_dir (), @"test_env_$(GLib.Random.next_int ())");
        tm.configure_rprofile_site (dummy_env);

        string rprofile_path = Path.build_filename (dummy_env, "lib", "R", "etc", "Rprofile.site");
        assert (FileUtils.test (rprofile_path, FileTest.EXISTS));

        string content;
        try {
            FileUtils.get_contents (rprofile_path, out content);
            assert (content.contains ("Managed by Imladris Toolchain Manager"));
            assert (content.contains ("https://cloud.r-project.org"));
            assert (content.contains ("Ncpus"));
        } catch (GLib.Error e) {
            assert_not_reached ();
        }
    }

    private static void test_runtime_resolution_tiers () {
        string dummy_proj = Path.build_filename (Environment.get_tmp_dir (), @"test_proj_$(GLib.Random.next_int ())");
        string env_bin_dir = Path.build_filename (dummy_proj, ".imladris-env", "bin");
        DirUtils.create_with_parents (env_bin_dir, 0755);

        string dummy_exe = Path.build_filename (env_bin_dir, "custom_r_engine");
        try {
            FileUtils.set_contents (dummy_exe, "#!/bin/sh\necho custom\n");
            FileUtils.chmod (dummy_exe, 0755);
        } catch (GLib.Error e) {
            assert_not_reached ();
        }

        // Test Tier 1: Project sandbox resolution
        string? resolved_path = null;
        string? env_prefix = null;
        var source = Core.PlatformUtils.resolve_runtime ("custom_r_engine", dummy_proj, out resolved_path, out env_prefix);
        assert (source == Core.RuntimeSource.PROJECT_SANDBOX);
        assert (resolved_path == dummy_exe);
        assert (env_prefix == Path.build_filename (dummy_proj, ".imladris-env"));

        // Test Tier 4: Missing binary resolution
        string? missing_path = null;
        string? missing_env = null;
        var missing_source = Core.PlatformUtils.resolve_runtime ("__missing_binary_404__", dummy_proj, out missing_path, out missing_env);
        assert (missing_source == Core.RuntimeSource.MISSING);
        assert (missing_path == null);
        assert (missing_env == null);

        // Test environment configuration injection
        var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.NONE);
        Core.PlatformUtils.configure_managed_env (launcher, env_prefix);
    }

    private static void test_host_r_session () {
        if (!Core.PlatformUtils.is_r_available ()) {
            GLib.Test.message ("R is not available in test runner; skipping host R session test.");
            return;
        }

        var sm = Services.PersistentSessionManager.get_default ();
        var loop = new MainLoop ();
        bool test_passed = false;

        string? plot_file = null;
        sm.execute_r.begin ("host_val <- 21 * 2; cat('R_RESULT:', host_val, '\\n');", (obj, res) => {
            string output = sm.execute_r.end (res, out plot_file);
            assert (output.contains ("R_RESULT: 42"));

            // Check persistence across calls
            sm.execute_r.begin ("cat('PERSIST_TEST:', host_val + 8, '\\n');", (obj2, res2) => {
                string? p2 = null;
                string output2 = sm.execute_r.end (res2, out p2);
                assert (output2.contains ("PERSIST_TEST: 50"));
                test_passed = true;
                loop.quit ();
            });
        });

        Timeout.add_seconds (15, () => {
            if (!test_passed) {
                loop.quit ();
            }
            return Source.REMOVE;
        });

        loop.run ();
        assert (test_passed);
    }

    private static void test_media_processing () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), @"test_media_$(GLib.Random.next_int ())");
        string proj_dir = Path.build_filename (tmp_dir, "my_sandboxed_project");
        string ext_dir = Path.build_filename (tmp_dir, "external_downloads");
        string ext_img = Path.build_filename (ext_dir, "statistical_plot.png");
        string ext_vid = Path.build_filename (ext_dir, "simulation_run.mp4");
        string doc_qmd = Path.build_filename (proj_dir, "report.qmd");
        string doc_md = Path.build_filename (proj_dir, "notes.md");
        string expected_img_dest = Path.build_filename (proj_dir, "img", "statistical_plot.png");
        string expected_vid_dest = Path.build_filename (proj_dir, "img", "simulation_run.mp4");
        string ext_dir2 = Path.build_filename (tmp_dir, "external_downloads_2");
        string ext_img2 = Path.build_filename (ext_dir2, "statistical_plot.png");
        string expected_collision_dest = Path.build_filename (proj_dir, "img", "statistical_plot_1.png");

        try {
            DirUtils.create_with_parents (proj_dir, 0755);
            DirUtils.create_with_parents (ext_dir, 0755);
            DirUtils.create_with_parents (ext_dir2, 0755);

            FileUtils.set_contents (ext_img, "DUMMY_PNG_DATA");
            FileUtils.set_contents (ext_vid, "DUMMY_MP4_DATA");
            FileUtils.set_contents (doc_qmd, "# Report\n");
            FileUtils.set_contents (doc_md, "# Notes\n");

            // 1. External image into sandboxed project -> copied to /img and linked
            string img_snippet = Services.MediaHelper.process_and_link_media (
                ext_img,
                proj_dir,
                true, // is_sandboxed
                doc_qmd,
                false // is_video
            );

            assert (FileUtils.test (expected_img_dest, FileTest.EXISTS));
            assert (img_snippet == "![Statistical plot](img/statistical_plot.png)\n");

            // 2. External video into sandboxed project (.qmd Quarto shortcode)
            string vid_qmd_snippet = Services.MediaHelper.process_and_link_media (
                ext_vid,
                proj_dir,
                true,
                doc_qmd,
                true // is_video
            );

            assert (FileUtils.test (expected_vid_dest, FileTest.EXISTS));
            assert (vid_qmd_snippet == "{{< video img/simulation_run.mp4 >}}\n");

            // 3. External video into Markdown (.md HTML5 video tag)
            string vid_md_snippet = Services.MediaHelper.process_and_link_media (
                ext_vid,
                proj_dir,
                true,
                doc_md,
                true
            );
            assert (vid_md_snippet == "<video src=\"img/simulation_run.mp4\" controls width=\"100%\"></video>\n");

            // 4. File collision resolution when copying different external file with same name
            FileUtils.set_contents (ext_img2, "DIFFERENT_CONTENT_FOR_COLLISION_TESTING");

            string collision_snippet = Services.MediaHelper.process_and_link_media (
                ext_img2,
                proj_dir,
                true,
                doc_qmd,
                false
            );
            assert (FileUtils.test (expected_collision_dest, FileTest.EXISTS));
            assert (collision_snippet == "![Statistical plot 1](img/statistical_plot_1.png)\n");

            // 5. Custom caption override
            string custom_caption_snippet = Services.MediaHelper.process_and_link_media (
                expected_img_dest,
                proj_dir,
                true,
                doc_qmd,
                false,
                "Figure 1: Gene Expression Correlation"
            );
            assert (custom_caption_snippet == "![Figure 1: Gene Expression Correlation](img/statistical_plot.png)\n");
        } catch (Error e) {
            assert_not_reached ();
        }

        // Clean up
        FileUtils.remove (expected_collision_dest);
        FileUtils.remove (expected_img_dest);
        FileUtils.remove (expected_vid_dest);
        FileUtils.remove (doc_qmd);
        FileUtils.remove (doc_md);
        FileUtils.remove (ext_img);
        FileUtils.remove (ext_img2);
        FileUtils.remove (ext_vid);
        DirUtils.remove (Path.build_filename (proj_dir, "img"));
        DirUtils.remove (proj_dir);
        DirUtils.remove (ext_dir);
        DirUtils.remove (ext_dir2);
        DirUtils.remove (tmp_dir);
    }

    /**
     * Test RStudio project file creation and directory scaffolding.
     *
     * This test validates that MallornManager creates valid .Rproj files
     * and directory structures for computational workflows.
     */
    private static void test_rproj_creation () {
        string tmp_dir = Path.build_filename (Environment.get_tmp_dir (), @"test_rproj_$(GLib.Random.next_int ())");
        try {
            DirUtils.create_with_parents (tmp_dir, 0755);

            // 1. Test direct .Rproj file creation with default configuration
            var default_cfg = new ProjectConfig () {
                project_name = "DirectProject",
                author = "Lead Researcher",
                format = DocumentFormat.RSCRIPT,
                sandboxed = false
            };

            MallornManager.create_rproj_file (tmp_dir, "DirectProject", default_cfg);
            string rproj_path = Path.build_filename (tmp_dir, "DirectProject.Rproj");
            assert (FileUtils.test (rproj_path, FileTest.EXISTS));

            string rproj_content;
            FileUtils.get_contents (rproj_path, out rproj_content);
            assert (rproj_content.contains ("Version: 1.0"));
            assert (rproj_content.contains ("RestoreWorkspace: Default"));
            assert (rproj_content.contains ("SaveWorkspace: Default"));
            assert (rproj_content.contains ("AlwaysSaveHistory: Default"));
            assert (rproj_content.contains ("EnableCodeIndexing: Yes"));
            assert (rproj_content.contains ("Encoding: UTF-8"));
            assert (rproj_content.contains ("RnwWeave: knitr"));
            assert (rproj_content.contains ("LaTeX: pdfLaTeX"));
            assert (rproj_content.contains ("AutoAppendNewline: Yes"));
            assert (rproj_content.contains ("StripTrailingWhitespace: Yes"));
            assert (rproj_content.contains ("ImladrisProjectName: DirectProject"));
            assert (rproj_content.contains ("ImladrisAuthor: Lead Researcher"));

            // 2. Test full RStudio project scaffolding (Standard mode)
            string std_proj_name = "ClinicalTrial";
            File std_rproj_file = MallornManager.create_rproj_project (tmp_dir, std_proj_name, DocumentFormat.RSCRIPT, false);
            string std_dir = std_rproj_file.get_parent ().get_path ();

            assert (FileUtils.test (std_dir, FileTest.IS_DIR));
            assert (FileUtils.test (Path.build_filename (std_dir, @"$std_proj_name.Rproj"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (std_dir, ".Rprofile"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (std_dir, "data"), FileTest.IS_DIR));
            assert (FileUtils.test (Path.build_filename (std_dir, "scripts"), FileTest.IS_DIR));
            assert (FileUtils.test (Path.build_filename (std_dir, ".mallorn.json"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (std_dir, "imladris.toml"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (std_dir, "main.R"), FileTest.EXISTS));

            string std_rprofile_content;
            FileUtils.get_contents (Path.build_filename (std_dir, ".Rprofile"), out std_rprofile_content);
            assert (std_rprofile_content.contains ("options(repos = c(CRAN = \"https://cloud.r-project.org/\"))"));

            // 3. Test full RStudio project scaffolding (Sandboxed mode)
            string proj_name = "GenomicsStudy";
            File rproj_file = MallornManager.create_rproj_project (tmp_dir, proj_name, DocumentFormat.QMD, true);
            string scaffolded_dir = rproj_file.get_parent ().get_path ();

            assert (FileUtils.test (scaffolded_dir, FileTest.IS_DIR));
            assert (FileUtils.test (Path.build_filename (scaffolded_dir, @"$proj_name.Rproj"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (scaffolded_dir, ".Rprofile"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (scaffolded_dir, "data"), FileTest.IS_DIR));
            assert (FileUtils.test (Path.build_filename (scaffolded_dir, "scripts"), FileTest.IS_DIR));
            assert (FileUtils.test (Path.build_filename (scaffolded_dir, ".mallorn.json"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (scaffolded_dir, "imladris.toml"), FileTest.EXISTS));
            assert (FileUtils.test (Path.build_filename (scaffolded_dir, "analysis.qmd"), FileTest.EXISTS));
            assert (Services.SandboxController.is_r_sandbox_active (scaffolded_dir));

            // 4. Test project configuration reading from scaffolded DCF manifest
            string manifest_file = Path.build_filename (scaffolded_dir, @"$proj_name.Rproj");
            string manifest_text;
            FileUtils.get_contents (manifest_file, out manifest_text);
            var loaded_cfg = MallornManager.parse_manifest (manifest_text);
            assert (loaded_cfg != null);
            assert (loaded_cfg.project_name == proj_name);
            assert (loaded_cfg.sandboxed == true);
            assert (loaded_cfg.format == DocumentFormat.QMD);

        } catch (GLib.Error e) {
            GLib.error ("Rproj creation test failed: %s", e.message);
        }
    }

    /**
     * Test Jupyter Notebook nbformat 4.5 serialization and deserialization parity.
     *
     * This test validates cell ID preservation, tags, execution counts,
     * kernel specifications, and round-trip conversion without data loss.
     */
    private static void test_notebook_serializer_parity () {
        try {
            // 1. Verify default starter templates
            string py_template = Core.NotebookSerializer.get_default_ipynb_markdown_template ("python");
            assert (py_template.contains ("title:"));
            assert (py_template.contains ("kernelspec:"));
            assert (py_template.contains ("Python 3"));
            assert (py_template.contains ("name: python3"));
            assert (py_template.contains ("```{python}"));

            string r_template = Core.NotebookSerializer.get_default_ipynb_markdown_template ("r");
            assert (r_template.contains ("title:"));
            assert (r_template.contains ("name: ir"));
            assert (r_template.contains ("```{r}"));

            // 2. Test Markdown to IPYNB JSON serialization
            string input_markdown =
                "---\n" +
                "title: \"Gene Expression Analysis\"\n" +
                "jupyter:\n" +
                "  kernelspec:\n" +
                "    display_name: \"Python 3 (ipykernel)\"\n" +
                "    language: python\n" +
                "    name: python3\n" +
                "---\n" +
                "\n" +
                "# Section 1: Overview\n" +
                "\n" +
                "This cell contains markdown documentation text.\n" +
                "\n" +
                "```{python}\n" +
                "#| cell_id: cell_0001\n" +
                "#| execution_count: 42\n" +
                "#| tags: [parameters, export]\n" +
                "import numpy as np\n" +
                "x = np.linspace(0, 10, 100)\n" +
                "```\n" +
                "\n" +
                "```{r}\n" +
                "#| cell_id: cell_0002\n" +
                "#| execution_count: 7\n" +
                "library(ggplot2)\n" +
                "```\n";

            string generated_ipynb = Core.NotebookSerializer.markdown_to_ipynb (input_markdown);
            assert (generated_ipynb.contains ("\"nbformat\""));
            assert (generated_ipynb.contains ("\"nbformat_minor\""));
            assert (generated_ipynb.contains ("\"cell_0001\""));
            assert (generated_ipynb.contains ("\"parameters\""));
            assert (generated_ipynb.contains ("\"export\""));
            assert (generated_ipynb.contains ("\"cell_0002\""));

            // Parse generated JSON with Json.Parser to inspect DOM structure
            var parser = new Json.Parser ();
            parser.load_from_data (generated_ipynb);
            var root = parser.get_root ().get_object ();

            assert (root.has_member ("cells"));
            assert (root.has_member ("metadata"));
            assert (root.get_int_member ("nbformat") == 4);
            assert (root.get_int_member ("nbformat_minor") == 5);

            var cells = root.get_array_member ("cells");
            assert (cells.get_length () == 3);

            // Cell 0: Markdown
            var cell0 = cells.get_object_element (0);
            assert (cell0.get_string_member ("cell_type") == "markdown");
            assert (cell0.has_member ("id"));
            assert (cell0.get_string_member ("id").length >= 8);

            // Cell 1: Python Code
            var cell1 = cells.get_object_element (1);
            assert (cell1.get_string_member ("cell_type") == "code");
            assert (cell1.get_string_member ("id") == "cell_0001");
            assert (cell1.get_int_member ("execution_count") == 42);

            var cell1_meta = cell1.get_object_member ("metadata");
            assert (cell1_meta.has_member ("tags"));
            var tags = cell1_meta.get_array_member ("tags");
            assert (tags.get_length () == 2);
            assert (tags.get_string_element (0) == "parameters");
            assert (tags.get_string_element (1) == "export");

            // Cell 2: R Code
            var cell2 = cells.get_object_element (2);
            assert (cell2.get_string_member ("cell_type") == "code");
            assert (cell2.get_string_member ("id") == "cell_0002");
            assert (cell2.get_int_member ("execution_count") == 7);

            // 3. Test round-trip: IPYNB JSON to Markdown deserialization
            string converted_md = Core.NotebookSerializer.ipynb_to_markdown (generated_ipynb);
            assert (converted_md.contains ("# Section 1: Overview"));
            assert (converted_md.contains ("```{python}"));
            assert (converted_md.contains ("#| cell_id: cell_0001"));
            assert (converted_md.contains ("#| execution_count: 42"));
            assert (converted_md.contains ("#| tags: [\"parameters\", \"export\"]"));
            assert (converted_md.contains ("x = np.linspace(0, 10, 100)"));
            assert (converted_md.contains ("```{r}"));
            assert (converted_md.contains ("#| cell_id: cell_0002"));
            assert (converted_md.contains ("#| execution_count: 7"));

            // 4. Test secondary round-trip (idempotency check)
            string round_trip_ipynb = Core.NotebookSerializer.markdown_to_ipynb (converted_md);
            var parser2 = new Json.Parser ();
            parser2.load_from_data (round_trip_ipynb);
            var root2 = parser2.get_root ().get_object ();
            var cells2 = root2.get_array_member ("cells");
            assert (cells2.get_length () == 3);

            var round_cell1 = cells2.get_object_element (1);
            assert (round_cell1.get_string_member ("id") == "cell_0001");
            assert (round_cell1.get_int_member ("execution_count") == 42);

        } catch (GLib.Error e) {
            GLib.error ("Notebook serializer parity test failed: %s", e.message);
        }
    }

    /**
     * Test the Natural Math & Chemical Reaction Engine and live document preview adapter.
     *
     * Verifies mode auto-detection, natural math to LaTeX/Markdown conversion,
     * natural chemical reaction to LaTeX/mhchem/Markdown/Unicode conversion,
     * offline HTML rendering, and DocumentAdapter rendering of math and chemistry.
     */
    private static void test_math_chem_engine () {
        // 1. Mode Auto-Detection
        assert (Core.MathChemEngine.detect_mode ("6CO2(g) + 6H2O(l) ->[h*nu] C6H12O6(aq) + 6O2(g)") == Core.FormulaMode.CHEMISTRY);
        assert (Core.MathChemEngine.detect_mode ("CH3COOH + H2O <=> CH3COO^- + H3O^+") == Core.FormulaMode.CHEMISTRY);
        assert (Core.MathChemEngine.detect_mode ("H2SO4") == Core.FormulaMode.CHEMISTRY);
        assert (Core.MathChemEngine.detect_mode ("(-b +- sqrt(b^2 - 4*a*c)) / (2*a)") == Core.FormulaMode.MATH);
        assert (Core.MathChemEngine.detect_mode ("int(0, inf) e^(-x^2) dx = sqrt(pi)/2") == Core.FormulaMode.MATH);

        // 2. Natural Math to LaTeX Display & Inline
        string quad_latex = Core.MathChemEngine.natural_math_to_latex ("(-b +- sqrt(b^2 - 4*a*c)) / (2*a)");
        assert (quad_latex.contains ("\\frac{"));
        assert (quad_latex.contains ("\\pm"));
        assert (quad_latex.contains ("\\sqrt{"));

        string int_latex = Core.MathChemEngine.natural_math_to_latex ("int(0, inf) e^(-x^2) dx = sqrt(pi)/2");
        assert (int_latex.contains ("\\int_{0}^{\\infty}"));
        assert (int_latex.contains ("\\pi"));

        string sum_latex = Core.MathChemEngine.natural_math_to_latex ("sum(i=1, n) x_i");
        assert (sum_latex.contains ("\\sum_{i=1}^{n}"));

        string mat_latex = Core.MathChemEngine.natural_math_to_latex ("matrix([a, b], [c, d])");
        assert (mat_latex.contains ("\\begin{pmatrix}"));
        assert (mat_latex.contains ("a & b \\\\ c & d"));
        assert (mat_latex.contains ("\\end{pmatrix}"));

        string display_block = Core.MathChemEngine.convert (
            "frac(a, b)",
            Core.FormulaMode.MATH,
            Core.FormulaOutputFormat.LATEX_DISPLAY
        );
        assert (display_block.has_prefix ("$$\n"));
        assert (display_block.contains ("\\frac{a}{b}"));
        assert (display_block.has_suffix ("\n$$"));

        // 3. Natural Chemistry to LaTeX, mhchem (\ce{...}), Markdown Sub/Sup, and Unicode
        string photo_input = "6CO2(g) + 6H2O(l) ->[h*nu][chlorophyll] C6H12O6(aq) + 6O2(g)";
        string photo_latex = Core.MathChemEngine.natural_chem_to_latex (photo_input);
        assert (photo_latex.contains ("\\text{CO}_{2}_{\\text{(g)}}"));
        assert (photo_latex.contains ("\\xrightarrow[\\text{chlorophyll}]{h\\nu}"));
        assert (photo_latex.contains ("\\text{C}_{6}\\text{H}_{12}\\text{O}_{6}_{\\text{(aq)}}"));

        string mhchem_out = Core.MathChemEngine.convert (
            "CH3COOH(aq) + H2O(l) <=> CH3COO^-(aq) + H3O^+(aq)",
            Core.FormulaMode.CHEMISTRY,
            Core.FormulaOutputFormat.LATEX_MHCHEM
        );
        assert (mhchem_out.has_prefix ("$$\\ce{"));
        assert (mhchem_out.has_suffix ("}$$"));

        string md_sub_sup = Core.MathChemEngine.convert (
            "2H2(g) + O2(g) -> 2H2O(l)",
            Core.FormulaMode.CHEMISTRY,
            Core.FormulaOutputFormat.MARKDOWN_SUBSUP
        );
        assert (md_sub_sup.contains ("2H~2~(g)"));
        assert (md_sub_sup.contains ("2H~2~O(l)"));
        assert (md_sub_sup.contains ("→"));

        string md_unicode = Core.MathChemEngine.convert (
            "SO4^2- + 2H^+ -> H2SO4",
            Core.FormulaMode.CHEMISTRY,
            Core.FormulaOutputFormat.MARKDOWN_UNICODE
        );
        assert (md_unicode.contains ("SO₄²⁻"));
        assert (md_unicode.contains ("H₂SO₄"));

        // 4. Offline HTML Rendering & DocumentAdapter integration
        string html_preview = Core.MathChemEngine.render_latex_to_html (photo_latex, true);
        assert (html_preview.contains ("math-display-card"));
        assert (html_preview.contains ("chem-arrow-stack"));

        string doc_md = "# Reaction Notes\n\n$$\n\\frac{a}{b}\n$$\n\nInline water H~2~O and ion SO~4~^2-^ plus $\\alpha + \\beta$.\n\n| Reagent | Molarity |\n|---|---|\n| NaCl | 1.0 M |\n";
        string doc_html = Adapters.DocumentAdapter.render_html (doc_md, DocumentFormat.QMD);
        assert (doc_html.contains ("math-display-card"));
        assert (doc_html.contains ("math-frac"));
        assert (doc_html.contains ("<sub>2</sub>"));
        assert (doc_html.contains ("<sup>2-</sup>"));
        assert (doc_html.contains ("<table"));
        assert (doc_html.contains ("NaCl"));

        // 5. Verify preset library completeness
        var presets = Core.MathChemEngine.get_presets ();
        assert (presets.size >= 12);
    }

    /**
     * Test the Visual Flow & Mindmap Engine (MermaidFlowEngine).
     *
     * Verifies flowchart serialization, mindmap hierarchical indentation,
     * sequence diagram generation, two-way Mermaid code parsing, SVG export,
     * and Quarto chunk formatting.
     */
    private static void test_mermaid_flow_engine () {
        var nodes = new Gee.ArrayList<Core.MermaidNode> ();
        var edges = new Gee.ArrayList<Core.MermaidEdge> ();

        var n1 = new Core.MermaidNode ("N1", "Raw Reads (FASTQ)", Core.MermaidNodeShape.PARALLELOGRAM, 150, 100);
        n1.palette = Core.MermaidNodePalette.TEAL;
        var n2 = new Core.MermaidNode ("N2", "Quality Pass?", Core.MermaidNodeShape.DIAMOND, 150, 220);
        n2.palette = Core.MermaidNodePalette.AMBER;
        var n3 = new Core.MermaidNode ("N3", "DESeq2 Model", Core.MermaidNodeShape.DATABASE, 150, 340);
        n3.subgraph_title = "Statistical Compute";

        nodes.add (n1);
        nodes.add (n2);
        nodes.add (n3);

        edges.add (new Core.MermaidEdge ("E1", "N1", "N2", "", Core.MermaidEdgeStyle.SOLID_ARROW));
        edges.add (new Core.MermaidEdge ("E2", "N2", "N3", "p < 0.05", Core.MermaidEdgeStyle.THICK_ARROW));

        // 1. Flowchart generation with shapes, subgraphs, edge labels, and semantic styles
        string fc_code = Core.MermaidFlowEngine.generate_mermaid_code (
            Core.MermaidDiagramKind.FLOWCHART,
            Core.MermaidFlowDirection.TOP_DOWN,
            nodes,
            edges
        );
        assert (fc_code.has_prefix ("flowchart TD"));
        assert (fc_code.contains ("N1[/\"Raw Reads (FASTQ)\"/]"));
        assert (fc_code.contains ("N2{\"Quality Pass?\"}"));
        assert (fc_code.contains ("subgraph SG1 [\"Statistical Compute\"]"));
        assert (fc_code.contains ("N3[(\"DESeq2 Model\")]"));
        assert (fc_code.contains ("N2 ==>|\"p < 0.05\"| N3"));
        assert (fc_code.contains ("style N1 fill:#ccfbf1"));

        // 2. Quarto executable chunk formatting with label and caption
        string qmd_chunk = Core.MermaidFlowEngine.format_for_document (
            fc_code,
            Core.MermaidTargetFormat.QUARTO_CHUNK,
            "rnaseq-flow",
            "RNA-Seq Differential Expression Pipeline"
        );
        assert (qmd_chunk.contains ("```{mermaid}"));
        assert (qmd_chunk.contains ("#| label: fig-rnaseq-flow"));
        assert (qmd_chunk.contains ("#| fig-cap: \"RNA-Seq Differential Expression Pipeline\""));

        // 3. Two-way round-trip parsing from Quarto Mermaid chunk back to visual nodes & edges
        Core.MermaidDiagramKind parsed_kind;
        Core.MermaidFlowDirection parsed_dir;
        Gee.ArrayList<Core.MermaidNode> parsed_nodes;
        Gee.ArrayList<Core.MermaidEdge> parsed_edges;

        Core.MermaidFlowEngine.parse_mermaid_code (
            qmd_chunk,
            out parsed_kind,
            out parsed_dir,
            out parsed_nodes,
            out parsed_edges
        );
        assert (parsed_kind == Core.MermaidDiagramKind.FLOWCHART);
        assert (parsed_dir == Core.MermaidFlowDirection.TOP_DOWN);
        assert (parsed_nodes.size == 3);
        assert (parsed_edges.size == 2);
        assert (parsed_edges[1].label == "p < 0.05");
        assert (parsed_edges[1].style == Core.MermaidEdgeStyle.THICK_ARROW);

        // 4. Mindmap generation and round-trip parsing
        string mindmap_code = Core.MermaidFlowEngine.generate_mermaid_code (
            Core.MermaidDiagramKind.MINDMAP,
            Core.MermaidFlowDirection.TOP_DOWN,
            nodes,
            edges
        );
        assert (mindmap_code.has_prefix ("mindmap"));
        assert (mindmap_code.contains ("Raw Reads (FASTQ)"));
        assert (mindmap_code.contains ("    N2{{Quality Pass?}}"));

        // 5. Vector SVG export
        string svg = Core.MermaidFlowEngine.export_to_svg (nodes, edges);
        assert (svg.has_prefix ("<?xml version=\"1.0\""));
        assert (svg.contains ("<svg "));
        assert (svg.contains ("DESeq2 Model"));

        // 6. Presets validation
        var mermaid_presets = Core.MermaidFlowEngine.get_presets ();
        assert (mermaid_presets.size >= 7);
    }

    private static void test_vscode_polyglot_intellisense () {
        string sample_qmd = """---
title: "Clinical Trial"
---

# Introduction
Let $\alpha = 0.05$.

```{r}
#| echo: true
clinical_cohort <- read.csv("patients.csv")
clinical_cohort$patient_age <- 65
ggplot(mtcars, aes(x = mpg, y = hp))
```

```{python}
import pandas as pd
df_omics = pd.read_csv("counts.tsv")
```
""";

        // 1. YAML Frontmatter context detection & completion
        var yaml_ctx = Editor.CodeIntelliSenseEngine.detect_context (sample_qmd, 1, "ti");
        assert (yaml_ctx == Editor.IntelliSenseContext.YAML_FRONTMATTER);
        var yaml_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 1, "ti");
        assert (yaml_items.size > 0);
        assert (yaml_items[0].label == "title:");

        // 2. LaTeX Math macro completion
        var latex_ctx = Editor.CodeIntelliSenseEngine.detect_context (sample_qmd, 5, "Let $\\alp");
        assert (latex_ctx == Editor.IntelliSenseContext.LATEX_MATH_CHEM);
        var latex_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 5, "Let $\\alp");
        assert (latex_items.size > 0);
        assert (latex_items[0].label == "\\alpha");

        // 3. Quarto '#|' Hash-Pipe option completion
        var opt_ctx = Editor.CodeIntelliSenseEngine.detect_context (sample_qmd, 8, "#| warn");
        assert (opt_ctx == Editor.IntelliSenseContext.QUARTO_HASH_PIPE);
        var opt_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 8, "#| warn");
        assert (opt_items.size > 0);
        assert (opt_items[0].insert_text == "warning: false");

        // 4. R DataFrame '$' Column completion (built-in mtcars + buffer-discovered clinical_cohort$patient_age)
        var r_cols = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 10, "mtcars$mp");
        assert (r_cols.size > 0);
        assert (r_cols[0].insert_text == "mtcars$mpg");

        var user_cols = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 10, "clinical_cohort$pat");
        assert (user_cols.size > 0);
        assert (user_cols[0].insert_text == "clinical_cohort$patient_age");

        // 5. R Namespace '::' completion
        var ns_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 10, "survival::cox");
        assert (ns_items.size > 0);
        assert (ns_items[0].label == "survival::coxph");

        // 6. Python dot-member completion & buffer variable discovery
        var py_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 16, "pd.read_c");
        assert (py_items.size > 0);
        assert (py_items[0].label == "pd.read_csv");

        var py_var_items = Editor.CodeIntelliSenseEngine.query_completions (sample_qmd, 16, "df_om");
        assert (py_var_items.size > 0);
        assert (py_var_items[0].label == "df_omics");

        // 7. Fuzzy Match Scoring
        assert (Editor.CodeIntelliSenseEngine.compute_match_score ("read_csv", "rdcsv") > 0);
        assert (Editor.CodeIntelliSenseEngine.compute_match_score ("differential_expression", "diffexp") > 0);
        assert (Editor.CodeIntelliSenseEngine.compute_match_score ("ggplot", "ggp") > 50);
        assert (Editor.CodeIntelliSenseEngine.compute_match_score ("hello", "xyz") == 0);
    }

    static void test_export_qmd_pdf_html_odt_rtf () {
        assert (Core.ScientificOutputFormat.PDF_MANUSCRIPT.to_quarto_flag () == "pdf");
        assert (Core.ScientificOutputFormat.PDF_MANUSCRIPT.get_extension () == ".pdf");

        string tmp_dir = GLib.Path.build_filename (GLib.Environment.get_tmp_dir (), "imladris_test_export_formats");
        GLib.DirUtils.create_with_parents (tmp_dir, 0755);

        string qmd_content = "---\ntitle: \"Clinical Trial Report\"\nauthor: \"Dr. Elrond\"\n---\n\n# Summary\n\nResult with `p < 0.05`.\n\n```{r}\nsummary(cars)\n```\n";
        string fake_unsaved_qmd = GLib.Path.build_filename (tmp_dir, "unsaved_report.qmd");
        string html_out = GLib.Path.build_filename (tmp_dir, "out.html");
        string odt_out = GLib.Path.build_filename (tmp_dir, "out.odt");
        string rtf_out = GLib.Path.build_filename (tmp_dir, "out.rtf");

        try {
            Services.ExportService.export_to_html (fake_unsaved_qmd, html_out, qmd_content);
            assert (GLib.FileUtils.test (html_out, GLib.FileTest.EXISTS));
            string html_data;
            GLib.FileUtils.get_contents (html_out, out html_data);
            assert (html_data.contains ("Clinical Trial Report"));

            Services.ExportService.export_to_odt (fake_unsaved_qmd, odt_out, qmd_content);
            assert (GLib.FileUtils.test (odt_out, GLib.FileTest.EXISTS));

            Services.ExportService.export_to_rtf (fake_unsaved_qmd, rtf_out, qmd_content);
            assert (GLib.FileUtils.test (rtf_out, GLib.FileTest.EXISTS));
            string rtf_data;
            GLib.FileUtils.get_contents (rtf_out, out rtf_data);
            assert (rtf_data.has_prefix ("{\\rtf1"));
            assert (rtf_data.contains ("Clinical Trial Report"));
        } catch (GLib.Error e) {
            assert_not_reached ();
        } finally {
            GLib.FileUtils.remove (html_out);
            GLib.FileUtils.remove (odt_out);
            GLib.FileUtils.remove (rtf_out);
            GLib.DirUtils.remove (tmp_dir);
        }
    }

    static void test_html_css_latex_render () {
        string raw_html = "<!DOCTYPE html><html><head><style>body { color: #123; content: \"$not_math$\"; }</style></head><body><p>Inline $\\alpha$ and display:</p>$$E = mc^2$$</body></html>";
        string rendered = Adapters.DocumentAdapter.render_html_with_latex (raw_html);
        assert ("content: \"$not_math$\"" in rendered);
        assert (".math-display-card" in rendered);
        assert (!("$$E = mc^2$$" in rendered));
    }

    static void test_persistent_python_and_r_repl () {
        var mgr = Services.PersistentSessionManager.get_default ();
        var loop = new GLib.MainLoop ();
        bool done = false;

        Idle.add (() => {
            run_repl_checks.begin (mgr, () => {
                done = true;
                loop.quit ();
            });
            return false;
        });

        uint timeout_id = Timeout.add_seconds (15, () => {
            assert_not_reached ();
        });
        while (!done) {
            loop.run ();
        }
        Source.remove (timeout_id);
        mgr.restart_all_sessions ();
    }

    static async void run_repl_checks (Services.PersistentSessionManager mgr) {
        if (Core.PlatformUtils.is_program_available ("python3")) {
            string? p1 = null;
            yield mgr.execute_python ("x_val = 40\ntry:\n    y_val = 2\nexcept Exception:\n    y_val = 0", out p1);
            string? p2 = null;
            string out2 = yield mgr.execute_python ("print(x_val + y_val)", out p2);
            assert (out2.strip () == "42");
            string? p3 = null;
            string out3 = yield mgr.execute_python ("x = (", out p3);
            assert (out3.contains ("SyntaxError"));
        }

        if (Core.PlatformUtils.is_program_available ("R")) {
            string? r1 = null;
            yield mgr.execute_r ("imladris_x <- 21", out r1);
            string? r2 = null;
            string rout2 = yield mgr.execute_r ("imladris_x * 2", out r2);
            assert (rout2.contains ("42"));
            string? r3 = null;
            string rout3 = yield mgr.execute_r ("x <- (", out r3);
            assert (rout3.contains ("Error:"));
        }
    }
}
