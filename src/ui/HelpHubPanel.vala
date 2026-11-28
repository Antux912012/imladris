// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using WebKit;
using Json;
using Imladris.Services;

namespace Imladris.UI {

    /**
     * Phase 6: Integrated Help & Documentation Hub Panel.
     * Embeds Adw.OverlaySplitView (searchable 11-domain catalog sidebar + WebKitGTK 6.0 viewer),
     * Nord Dark / Light CSS injection, WebKit JS-to-Vala snippet insertion bridge,
     * Offline bundle downloader, and Open in External Browser fallback.
     */
    public class HelpHubPanel : Gtk.Box {
        private DocsRepositoryClient client;
        public WebKit.WebView web_view { get; private set; }
        private Adw.OverlaySplitView split_view;
        private Gtk.SearchEntry search_entry;
        private Gtk.ListBox catalog_list;
        private ManualDescriptor? active_manual = null;
        private string active_search_highlight = "";
        private ulong theme_hid = 0;
        private ulong dark_hid = 0;
        private ulong catalog_hid = 0;

        public signal void insert_snippet_requested (string code_snippet);
        public signal void r_topic_lookup_requested (string r_topic);
        public signal void toast_requested (string message);

        public HelpHubPanel () {
            GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.hexpand = true;
            this.vexpand = true;
            this.client = DocsRepositoryClient.get_default ();

            build_ui ();
            populate_sidebar ();

            catalog_hid = client.catalog_updated.connect (populate_sidebar);

            theme_hid = Core.SettingsManager.get_default ().theme_changed.connect ((t) => {
                if (active_manual != null) open_manual_async.begin (active_manual.id);
            });
            dark_hid = Adw.StyleManager.get_default ().notify["dark"].connect (() => {
                if (active_manual != null) open_manual_async.begin (active_manual.id);
            });

            bool initialized = false;
            this.map.connect (() => {
                if (!initialized) {
                    initialized = true;
                    if (client.manuals.size > 0) {
                        open_manual_async.begin (client.manuals[0].id);
                    }
                    client.refresh_manifest_async.begin ();
                }
            });
        }

        public void cleanup () {
            if (catalog_hid != 0) {
                client.disconnect (catalog_hid);
                catalog_hid = 0;
            }
            if (theme_hid != 0) {
                Core.SettingsManager.get_default ().disconnect (theme_hid);
                theme_hid = 0;
            }
            if (dark_hid != 0) {
                Adw.StyleManager.get_default ().disconnect (dark_hid);
                dark_hid = 0;
            }
        }

        private void build_ui () {
            // Toolbar
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6
            };
            bar.add_css_class ("dock-subtoolbar");

            var btn_sidebar = new Gtk.ToggleButton () {
                icon_name = "view-dual-symbolic",
                active = true,
                tooltip_text = "Show / Hide Manuals Catalog"
            };
            btn_sidebar.add_css_class ("flat");
            bar.append (btn_sidebar);

            var btn_back = new Gtk.Button.from_icon_name ("go-previous-symbolic") {
                tooltip_text = "Back"
            };
            btn_back.add_css_class ("flat");
            btn_back.clicked.connect (() => {
                if (web_view.can_go_back ()) web_view.go_back ();
            });
            bar.append (btn_back);

            var btn_fwd = new Gtk.Button.from_icon_name ("go-next-symbolic") {
                tooltip_text = "Forward"
            };
            btn_fwd.add_css_class ("flat");
            btn_fwd.clicked.connect (() => {
                if (web_view.can_go_forward ()) web_view.go_forward ();
            });
            bar.append (btn_fwd);

            search_entry = new Gtk.SearchEntry () {
                placeholder_text = "Search R, CRAN, Python, Galaxy, Cytoscape, Bash, Web (F1)...",
                hexpand = true
            };
            search_entry.search_changed.connect (populate_sidebar);
            search_entry.activate.connect (() => {
                string q = search_entry.text.strip ();
                if (q != "") {
                    lookup_and_jump (q, null);
                }
            });
            bar.append (search_entry);

            var btn_offline = new Gtk.Button.from_icon_name ("folder-download-symbolic") {
                tooltip_text = "Download All 11 Manuals for Offline / Air-Gapped Use"
            };
            btn_offline.add_css_class ("flat");
            btn_offline.clicked.connect (() => {
                download_all_offline_async.begin ();
            });
            bar.append (btn_offline);

            var btn_copy_url = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy Canonical Reference URL"
            };
            btn_copy_url.add_css_class ("flat");
            btn_copy_url.clicked.connect (() => {
                if (active_manual != null && active_manual.canonical_url != "") {
                    this.get_clipboard ().set_text (active_manual.canonical_url);
                    toast_requested (@"Copied $(active_manual.canonical_url)");
                }
            });
            bar.append (btn_copy_url);

            var btn_external = new Gtk.Button.from_icon_name ("web-browser-symbolic") {
                tooltip_text = "Open Canonical Documentation in External Browser"
            };
            btn_external.add_css_class ("flat");
            btn_external.clicked.connect (() => {
                if (active_manual != null && active_manual.canonical_url != "") {
                    try {
                        GLib.AppInfo.launch_default_for_uri (active_manual.canonical_url, null);
                    } catch (GLib.Error e) {}
                }
            });
            bar.append (btn_external);

            this.append (bar);

            // OverlaySplitView: Sidebar Index + WebKitGTK 6.0 Reader
            split_view = new Adw.OverlaySplitView () {
                hexpand = true,
                vexpand = true,
                min_sidebar_width = 195,
                max_sidebar_width = 250,
                show_sidebar = true
            };
            btn_sidebar.bind_property ("active", split_view, "show-sidebar", GLib.BindingFlags.BIDIRECTIONAL);

            catalog_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE
            };
            catalog_list.add_css_class ("navigation-sidebar");
            catalog_list.row_activated.connect ((row) => {
                string? mid = row.get_data<string> ("manual-id");
                if (mid != null && mid != "") {
                    open_manual_async.begin (mid);
                }
            });

            var side_scroll = new Gtk.ScrolledWindow () {
                child = catalog_list,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            split_view.set_sidebar (side_scroll);

            web_view = WebViewFactory.create ();
            setup_webkit_bridge ();
            split_view.set_content (web_view);

            this.append (split_view);
        }

        private void setup_webkit_bridge () {
            var ucm = web_view.get_user_content_manager ();
            ucm.register_script_message_handler ("imladrisHelpHub", (string) (void*) null);
            ucm.script_message_received["imladrisHelpHub"].connect ((js_val) => {
                try {
                    string json_str = js_val.to_json (0);
                    var p = new Json.Parser ();
                    p.load_from_data (json_str, -1);
                    var root = p.get_root ();
                    if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                        var o = root.get_object ();
                        string act = o.has_member ("action") ? o.get_string_member ("action") : "";
                        if (act == "insert_snippet" && o.has_member ("code")) {
                            string code = o.get_string_member ("code");
                            if (code.strip () != "") {
                                insert_snippet_requested (code);
                            }
                        } else if (act == "open_external" && o.has_member ("url")) {
                            string u = o.get_string_member ("url");
                            if (u.has_prefix ("https://") || u.has_prefix ("http://")) {
                                GLib.AppInfo.launch_default_for_uri (u, null);
                            }
                        }
                    }
                } catch (GLib.Error e) {}
            });

            web_view.decide_policy.connect ((decision, dtype) => {
                if (dtype == WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
                    var nav = decision as WebKit.NavigationPolicyDecision;
                    if (nav != null && nav.get_navigation_action ().is_user_gesture ()) {
                        string? uri = nav.get_navigation_action ().get_request ().get_uri ();
                        if (uri != null && (uri.has_prefix ("http://") || uri.has_prefix ("https://"))) {
                            try { GLib.AppInfo.launch_default_for_uri (uri, null); } catch (GLib.Error e) {}
                            decision.ignore ();
                            return true;
                        }
                    }
                }
                return false;
            });
        }

        private void populate_sidebar () {
            var ch = catalog_list.get_first_child ();
            while (ch != null) {
                var nx = ch.get_next_sibling ();
                catalog_list.remove (ch);
                ch = nx;
            }

            string q = search_entry != null ? search_entry.text.strip ().down () : "";
            string last_track = "";

            foreach (var m in client.manuals) {
                if (q != "") {
                    bool hit = m.title.down ().contains (q) || m.track.down ().contains (q) || m.id.down ().contains (q);
                    if (!hit) {
                        foreach (string kw in m.keywords) {
                            if (kw.down ().contains (q)) { hit = true; break; }
                        }
                    }
                    if (!hit) continue;
                }

                if (m.track != last_track) {
                    last_track = m.track;
                    var hdr_row = new Gtk.ListBoxRow () { selectable = false, activatable = false };
                    var hdr_lbl = new Gtk.Label (last_track) {
                        xalign = 0,
                        margin_top = 8,
                        margin_bottom = 2,
                        margin_start = 8,
                        css_classes = { "caption", "dim-label", "heading" }
                    };
                    hdr_row.set_child (hdr_lbl);
                    catalog_list.append (hdr_row);
                }

                var row = new Gtk.ListBoxRow ();
                row.set_data<string> ("manual-id", m.id);
                var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                    margin_top = 5,
                    margin_bottom = 5,
                    margin_start = 10,
                    margin_end = 8
                };
                var lbl = new Gtk.Label (m.title) {
                    xalign = 0,
                    hexpand = true,
                    ellipsize = Pango.EllipsizeMode.END
                };
                box.append (lbl);
                if (client.is_cached_offline (m)) {
                    var ok_ic = new Gtk.Image.from_icon_name ("emblem-ok-symbolic") {
                        pixel_size = 12,
                        tooltip_text = "Cached locally for offline use",
                        opacity = 0.65
                    };
                    box.append (ok_ic);
                }
                row.set_child (box);
                catalog_list.append (row);
            }
        }

        public async void open_manual_async (string manual_id) {
            var m = client.find_manual (manual_id);
            if (m == null) return;
            active_manual = m;
            string md = yield client.get_manual_markdown_async (manual_id, false);
            string html = render_manual_html (m, md, active_search_highlight);
            active_search_highlight = "";
            web_view.load_html (html, "file:///");
        }

        public void lookup_and_jump (string symbol, string? lang_hint) {
            string clean = symbol.strip ();
            if (clean == "") return;
            search_entry.text = clean;
            bool is_r_query = (lang_hint == "r" || lang_hint == "rmd" || clean.has_prefix ("?"));
            string query_sym = clean.has_prefix ("?") ? clean.substring (1).strip () : clean;
            var hit = client.lookup_symbol (query_sym, lang_hint, !is_r_query);
            if (hit != null) {
                active_search_highlight = query_sym;
                open_manual_async.begin (hit.id);
            } else if (is_r_query && query_sym != "") {
                r_topic_lookup_requested (query_sym);
            }
        }

        public void load_raw_r_help_html (string styled_html) {
            web_view.load_html (styled_html, "file:///");
        }

        private async void download_all_offline_async () {
            int count = yield client.download_all_for_offline_async ();
            populate_sidebar ();
            toast_requested (@"Cached $count manuals in ~/.cache/imladris/docs/ for offline use");
        }

        public static string render_manual_html (ManualDescriptor m, string markdown, string highlight = "") {
            var app_theme = Core.SettingsManager.get_default ().app_theme;
            bool is_dark = Adw.StyleManager.get_default ().dark;
            bool use_dark = (app_theme == Core.AppTheme.DARK) || (app_theme == Core.AppTheme.SYSTEM && is_dark);

            // Nord Dark vs Crisp Light Palette
            string bg = use_dark ? "#2E3440" : "#FFFFFF";
            string fg = use_dark ? "#ECEFF4" : "#1E242B";
            string surface = use_dark ? "#3B4252" : "#F8FAFC";
            string border = use_dark ? "#4C566A" : "#CBD5E1";
            string accent = use_dark ? "#88C0D0" : "#0284C7";
            string muted = use_dark ? "#D8DEE9" : "#475569";

            string body_html = Adapters.DocumentAdapter.render_html (markdown, DocumentFormat.MD);

            return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>%s — Imladris Help Hub</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font-family: 'Inter', 'Cantarell', system-ui, sans-serif;
    background: %s;
    color: %s;
    line-height: 1.62;
    font-size: 13.5px;
    max-width: 76ch;
    margin: 0 auto;
    padding: 20px 24px 40px;
  }
  .manual-meta {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    color: %s;
    border-bottom: 1px solid %s;
    padding-bottom: 8px;
    margin-bottom: 16px;
  }
  h1 { font-size: 1.35rem; line-height: 1.25; margin: 0 0 12px; color: %s; text-wrap: balance; }
  h2 { font-size: 1.08rem; line-height: 1.3; margin: 22px 0 8px; border-bottom: 1px solid %s; padding-bottom: 4px; text-wrap: balance; }
  a { color: %s; text-underline-offset: 2px; }
  a:focus-visible, .insert-snippet-btn:focus-visible {
    outline: 2px solid %s;
    outline-offset: 2px;
  }
  table {
    width: 100%%;
    border-collapse: collapse;
    margin: 12px 0;
    font-size: 12.5px;
    font-variant-numeric: tabular-nums;
  }
  th, td {
    text-align: left;
    padding: 6px 10px;
    border: 1px solid %s;
  }
  th { background: %s; font-weight: 600; }
  code {
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
    background: %s;
    border: 1px solid %s;
    border-radius: 4px;
    padding: 1px 5px;
  }
  .snippet-wrap {
    position: relative;
    margin: 12px 0;
  }
  pre {
    background: %s;
    border: 1px solid %s;
    border-radius: 6px;
    padding: 30px 14px 12px;
    overflow-x: auto;
    margin: 0;
  }
  pre code {
    background: transparent;
    border: none;
    padding: 0;
  }
  .insert-snippet-btn {
    position: absolute;
    top: 6px;
    right: 6px;
    background: %s;
    color: %s;
    border: 1px solid %s;
    border-radius: 4px;
    padding: 3px 8px;
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
  }
  .insert-snippet-btn:hover {
    border-color: %s;
    color: %s;
  }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { transition-duration: 0.01ms !important; animation-duration: 0.01ms !important; }
  }
</style>
</head>
<body>
  <div class="manual-meta">
    <span>%s · v%s</span>
    <a href="%s">Upstream Reference</a>
  </div>
  <main id="manual-body">%s</main>
  <script>
    (function() {
      document.querySelectorAll('pre').forEach(function(pre) {
        var wrap = document.createElement('div');
        wrap.className = 'snippet-wrap';
        pre.parentNode.insertBefore(wrap, pre);
        wrap.appendChild(pre);
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'insert-snippet-btn';
        btn.setAttribute('aria-label', 'Insert code snippet into active editor');
        btn.textContent = 'Insert into Active Editor';
        btn.addEventListener('click', function() {
          var codeText = pre.innerText || pre.textContent || '';
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.imladrisHelpHub) {
            window.webkit.messageHandlers.imladrisHelpHub.postMessage({
              action: 'insert_snippet',
              code: codeText
            });
            btn.textContent = 'Inserted';
            setTimeout(function() { btn.textContent = 'Insert into Active Editor'; }, 1200);
          }
        });
        wrap.appendChild(btn);
      });
      var q = %s;
      if (q) {
        var headings = document.querySelectorAll('h1, h2, h3, code');
        for (var i = 0; i < headings.length; i++) {
          if ((headings[i].textContent || '').toLowerCase().indexOf(q.toLowerCase()) >= 0) {
            headings[i].scrollIntoView({ block: 'center' });
            break;
          }
        }
      }
    })();
  </script>
</body>
</html>""".printf (
                GLib.Markup.escape_text (m.title),
                bg, fg,
                muted, border,
                fg,
                border,
                accent,
                accent,
                border, surface,
                surface, border,
                surface, border,
                bg, fg, border,
                accent, accent,
                GLib.Markup.escape_text (m.track),
                GLib.Markup.escape_text (m.version),
                GLib.Markup.escape_text (m.canonical_url),
                body_html,
                Json.to_string (new Json.Node.alloc ().init_string (highlight), false)
            );
        }
    }
}
