// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Gtk;
using Adw;
using Imladris.Services;

namespace Imladris.UI {

    public class ShinyWindow : Adw.Window {
        private WebKit.WebView web_view;
        private Adw.WindowTitle window_title;
        private Gtk.Button btn_stop;
        private ulong status_handler_id = 0;

        public ShinyWindow (Gtk.Window? parent, string url) {
            Object (transient_for: parent, modal: false);
            this.set_default_size (1024, 768);

            var toolbar_view = new Adw.ToolbarView ();
            this.set_content (toolbar_view);

            var header = new Adw.HeaderBar ();
            window_title = new Adw.WindowTitle ("Shiny Application", url);
            header.set_title_widget (window_title);

            var btn_reload = (Gtk.Button) RibbonFactory.create_compact_button ("view-refresh-symbolic");
            btn_reload.tooltip_text = "Reload Application";
            btn_reload.clicked.connect (() => {
                web_view.reload ();
            });
            header.pack_start (btn_reload);

            var btn_browser = (Gtk.Button) RibbonFactory.create_compact_button ("applications-internet-symbolic", "Browser");
            btn_browser.tooltip_text = "Open in System Browser";
            btn_browser.clicked.connect (() => {
                try {
                    GLib.AppInfo.launch_default_for_uri (url, null);
                } catch (GLib.Error e) {}
            });
            header.pack_start (btn_browser);

            btn_stop = (Gtk.Button) RibbonFactory.create_compact_button ("process-stop-symbolic", "Stop");
            btn_stop.tooltip_text = "Stop Shiny Server";
            btn_stop.add_css_class ("destructive-action");
            btn_stop.clicked.connect (() => {
                ShinyService.get_default ().stop_app ();
            });
            header.pack_end (btn_stop);

            toolbar_view.add_top_bar (header);

            web_view = WebViewFactory.create ();
            web_view.load_uri (url);
            toolbar_view.set_content (web_view);

            status_handler_id = ShinyService.get_default ().status_changed.connect ((st) => {
                if (st == ShinyAppStatus.STOPPED || st == ShinyAppStatus.ERROR) {
                    btn_stop.sensitive = false;
                    window_title.subtitle = "Server Stopped";
                } else if (st == ShinyAppStatus.RUNNING) {
                    btn_stop.sensitive = true;
                }
            });

            this.close_request.connect (() => {
                if (status_handler_id != 0) {
                    ShinyService.get_default ().disconnect (status_handler_id);
                    status_handler_id = 0;
                }
                return false;
            });
        }
    }
}
