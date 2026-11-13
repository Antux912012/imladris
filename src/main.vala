// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris {
    public static int main (string[] args) {
        // Ensure WebKitGTK 6.0 WebProcess runs reliably without nested bwrap
        // namespace aborts or Wayland/Flatpak DMA-BUF/EGL buffer-sharing blanks.
        GLib.Environment.set_variable ("WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS", "1", true);
        GLib.Environment.set_variable ("WEBKIT_DISABLE_DMABUF_RENDERER", "1", false);

        if ("--mcp-server" in args) {
            var loop = new GLib.MainLoop ();
            McpServer.run_stdio_server_async.begin (null);
            loop.run ();
            return 0;
        }

        // Configure GTK4 GSK Hardware Acceleration (OpenGL / Vulkan / Cairo) before Display init
        if (GLib.Environment.get_variable ("GSK_RENDERER") == null) {
            bool hw_accel = true;
            int gpu_backend = 0; // 0 = Auto (OpenGL NGL), 1 = OpenGL, 2 = Vulkan, 3 = Cairo Software

            string ini_path = GLib.Path.build_filename (
                GLib.Environment.get_user_config_dir (), "imladris", "settings.ini"
            );
            if (GLib.FileUtils.test (ini_path, GLib.FileTest.EXISTS)) {
                try {
                    var kf = new GLib.KeyFile ();
                    kf.load_from_file (ini_path, GLib.KeyFileFlags.NONE);
                    if (kf.has_key ("Hardware", "hw_acceleration")) {
                        hw_accel = kf.get_boolean ("Hardware", "hw_acceleration");
                    }
                    if (kf.has_key ("Hardware", "gpu_backend")) {
                        gpu_backend = kf.get_integer ("Hardware", "gpu_backend");
                    }
                } catch (GLib.Error e) {}
            }

            if (!hw_accel || gpu_backend == 3) {
                GLib.Environment.set_variable ("GSK_RENDERER", "cairo", true);
                GLib.Environment.set_variable ("WEBKIT_DISABLE_DMABUF_RENDERER", "1", true);
            } else if (gpu_backend == 2) {
                GLib.Environment.set_variable ("GSK_RENDERER", "vulkan", true);
            } else if (gpu_backend == 1) {
                uint minor = Gtk.get_minor_version ();
                string gl_renderer = (minor >= 14 && minor < 18) ? "ngl" : "gl";
                GLib.Environment.set_variable ("GSK_RENDERER", gl_renderer, true);
            }
            // When gpu_backend == 0 (Auto) and hw_accel == true, let GTK4 pick its native default renderer.
        }

        GtkSource.init ();
        var app = new Application ();
        return app.run (args);
    }
}
