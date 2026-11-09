// SPDX-License-Identifier: GPL-3.0-or-later
using GLib;

namespace Imladris.Services {

    public enum ShinyAppStatus {
        STOPPED,
        STARTING,
        RUNNING,
        ERROR;

        public string to_badge_label () {
            switch (this) {
                case STARTING: return "Starting...";
                case RUNNING: return "● Live";
                case ERROR: return "✖ Error";
                case STOPPED:
                default: return "○ Idle";
            }
        }
    }

    public enum ShinyViewerTarget {
        VIEWER_PANE,
        DEDICATED_WINDOW,
        EXTERNAL_BROWSER;

        public string to_label () {
            switch (this) {
                case VIEWER_PANE: return "Viewer Pane (Quadrant 4)";
                case DEDICATED_WINDOW: return "Dedicated Window";
                case EXTERNAL_BROWSER: return "External Web Browser";
                default: return "Viewer Pane";
            }
        }
    }

    /**
     * Pillar: R Shiny Reactive Application Lifecycle Engine.
     * Manages background R Shiny execution, ephemeral port allocation,
     * stdout/stderr interception, and multi-target live view dispatch.
     */
    public class ShinyService : GLib.Object {
        private static ShinyService? instance = null;

        public static ShinyService get_default () {
            if (instance == null) {
                instance = new ShinyService ();
            }
            return instance;
        }

        private static GLib.Regex? s_url_regex = null;

        private static GLib.Regex get_url_regex () {
            if (s_url_regex == null) {
                try {
                    s_url_regex = new GLib.Regex ("Listening on (http://[0-9a-zA-Z.:]+)");
                } catch (GLib.RegexError e) {
                    critical ("Failed to compile shiny URL regex: %s", e.message);
                }
            }
            return s_url_regex;
        }

        private GLib.Subprocess? app_process = null;
        private DataInputStream? stdout_stream = null;
        private DataInputStream? stderr_stream = null;
        private Cancellable? cancellable = null;

        public ShinyAppStatus status { get; private set; default = ShinyAppStatus.STOPPED; }
        public string? active_url { get; private set; default = null; }
        public string? active_app_path { get; private set; default = null; }
        public ShinyViewerTarget current_target { get; set; default = ShinyViewerTarget.VIEWER_PANE; }

        public signal void status_changed (ShinyAppStatus new_status);
        public signal void url_ready (string url);
        public signal void log_received (string message, bool is_error);

        public bool is_shiny_file (string filename, string? content = null) {
            string lower = filename.down ();
            if (lower.has_suffix ("app.r") || lower.has_suffix ("server.r") || lower.has_suffix ("ui.r")) {
                return true;
            }
            if (lower.has_suffix (".r") || lower.has_suffix (".rmd") || lower.has_suffix (".qmd")) {
                if (content != null) {
                    return content.contains ("shinyApp(") ||
                           content.contains ("shinyApp (") ||
                           content.contains ("library(shiny)") ||
                           content.contains ("library(\"shiny\")") ||
                           content.contains ("library('shiny')") ||
                           content.contains ("server: shiny") ||
                           content.contains ("runtime: shiny");
                }
            }
            return false;
        }

        public bool is_shiny_directory (string dir_path) {
            string app_r = GLib.Path.build_filename (dir_path, "app.R");
            string server_r = GLib.Path.build_filename (dir_path, "server.R");
            string ui_r = GLib.Path.build_filename (dir_path, "ui.R");
            return GLib.FileUtils.test (app_r, GLib.FileTest.EXISTS) ||
                   (GLib.FileUtils.test (server_r, GLib.FileTest.EXISTS) && GLib.FileUtils.test (ui_r, GLib.FileTest.EXISTS));
        }

        public async void launch_app_async (string file_or_dir_path, ShinyViewerTarget target = ShinyViewerTarget.VIEWER_PANE) {
            if (status == ShinyAppStatus.RUNNING || status == ShinyAppStatus.STARTING) {
                stop_app ();
                yield Imladris.Execution.Nap.sleep (250);
            }

            this.current_target = target;
            this.active_app_path = file_or_dir_path;
            this.active_url = null;
            this.status = ShinyAppStatus.STARTING;
            status_changed (this.status);

            string target_dir;
            string target_file_or_dir;
            if (GLib.FileUtils.test (file_or_dir_path, GLib.FileTest.IS_DIR)) {
                target_dir = file_or_dir_path;
                target_file_or_dir = file_or_dir_path;
            } else {
                var f = GLib.File.new_for_path (file_or_dir_path);
                var parent = f.get_parent ();
                target_dir = (parent != null) ? parent.get_path () : GLib.Environment.get_current_dir ();
                target_file_or_dir = file_or_dir_path;
            }

            // Assign ephemeral port
            int port = 3838 + (int) (GLib.Random.next_int () % 5000);
            string sanitized_target = target_file_or_dir.replace ("\\", "/");

            // Standard R Shiny execution command
            string r_cmd = """
if (!requireNamespace('shiny', quietly = TRUE)) {
    cat('ERROR: package "shiny" is not installed. Please install shiny using install.packages("shiny").\n', file = stderr())
    quit(status = 1)
}
options(shiny.autoreload = TRUE, shiny.launch.browser = FALSE)
cat('Starting Shiny App on port %d...\n')
shiny::runApp('%s', port = %d, host = '127.0.0.1', launch.browser = FALSE)
""".printf (port, sanitized_target, port);

            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                launcher.set_cwd (target_dir);

                string[] argv;
                if (Core.PlatformUtils.is_flatpak ()) {
                    argv = { "flatpak-spawn", "--host", "R", "--vanilla", "--quiet", "-e", r_cmd };
                } else {
                    argv = { "R", "--vanilla", "--quiet", "-e", r_cmd };
                }

                cancellable = new Cancellable ();
                app_process = launcher.spawnv (argv);
                stdout_stream = new DataInputStream (app_process.get_stdout_pipe ());
                stderr_stream = new DataInputStream (app_process.get_stderr_pipe ());

                read_stream_loop.begin (stdout_stream, false);
                read_stream_loop.begin (stderr_stream, true);

                app_process.wait_async.begin (cancellable, (obj, res) => {
                    this.status = ShinyAppStatus.STOPPED;
                    this.active_url = null;
                    status_changed (this.status);
                    log_received ("Shiny server process ended.", false);
                });

            } catch (GLib.Error e) {
                this.status = ShinyAppStatus.ERROR;
                status_changed (this.status);
                log_received (@"Failed to spawn Shiny server: $(e.message)", true);
            }
        }

        private async void read_stream_loop (DataInputStream? stream, bool is_error) {
            if (stream == null) return;
            try {
                var url_regex = get_url_regex ();
                while (app_process != null) {
                    size_t len;
                    string? line = yield stream.read_line_async (Priority.DEFAULT, cancellable, out len);
                    if (line == null) break;

                    log_received (line, is_error);

                    MatchInfo mi;
                    if (url_regex.match (line, 0, out mi)) {
                        string url = mi.fetch (1).strip ();
                        this.active_url = url;
                        this.status = ShinyAppStatus.RUNNING;
                        status_changed (this.status);
                        url_ready (url);
                    }
                }
            } catch (GLib.Error e) {
                // Stream closed
            }
        }

        public void stop_app () {
            if (cancellable != null) {
                cancellable.cancel ();
                cancellable = null;
            }

            try {
                if (stdout_stream != null) stdout_stream.close (null);
                if (stderr_stream != null) stderr_stream.close (null);
            } catch (GLib.Error e) {}
            stdout_stream = null;
            stderr_stream = null;

            if (app_process != null) {
                app_process.send_signal (2); // SIGINT
                var p = app_process;
                GLib.Timeout.add (500, () => {
                    p.force_exit ();
                    return GLib.Source.REMOVE;
                });
                app_process = null;
            }

            this.status = ShinyAppStatus.STOPPED;
            this.active_url = null;
            status_changed (this.status);
        }
    }
}
