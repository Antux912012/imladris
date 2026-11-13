// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using Imladris.Core.Layout;
using Imladris.UI;

namespace Imladris {

    public class DocumentPage : Gtk.Box {

        public GtkSource.View source_view { get; private set; }
        public GtkSource.Buffer source_buffer { get; private set; }
        public Gtk.TextView console_view { get; private set; }
        public WebKit.WebView web_view { get; private set; }
        public Gtk.Stack right_stack { get; private set; }
        public Gtk.Revealer console_revealer { get; private set; }
        public string doc_type { get; private set; }

        public AssistantPanel? assistant_panel { get; private set; default = null; }
        public GLib.File? file_location { get; set; default = null; }
        public string current_project_dir {
            owned get {
                if (file_location != null) {
                    var parent = file_location.get_parent ();
                    if (parent != null) {
                        return (string) parent.get_path ();
                    }
                }
                return "";
            }
        }
        private Window? parent_window;
        private uint update_debounce_id = 0;

        // Apostrophe Shell Containers
        public Gtk.Paned paned { get; private set; }
        public Gtk.Box apostrophe_editor_host { get; private set; }
        public Gtk.Box apostrophe_preview_host { get; private set; }
        public Gtk.ScrolledWindow editor_scroller { get; private set; }
        public Gtk.Box right_box { get; private set; }
        public string doc_id { get; private set; }
        public string initial_title { get; private set; default = ""; }
        private bool pending_preview_refresh = false;
        private string? pending_preview_uri = null;

        // Phase 1.1.3 Portal Registry & 4-Quadrant RStudio Docking Grid
        public RStudioDockLayoutState dock_layout_state { get; private set; }
        public PersistentPanelRegistry panel_registry { get; private set; }
        public RStudioDockGrid rstudio_dock_grid { get; private set; }
        public ProjectType project_type { get; set; default = ProjectType.STANDARD; }
        private Services.LayoutMode current_layout_mode = Services.LayoutMode.APOSTROPHE;
        private ulong ai_settings_handler_id = 0;
        private ulong theme_changed_handler_id = 0;
        private ulong dark_notify_handler_id = 0;
        private ulong physics_changed_handler_id = 0;

        public DocumentFormat get_document_format () {
            if (file_location != null) {
                return DocumentFormat.from_filename (file_location.get_basename ());
            }
            if (initial_title.contains (".")) {
                return DocumentFormat.from_filename (initial_title);
            }
            return DocumentFormat.from_short_code (doc_type);
        }

        private Gee.HashMap<string, Gtk.TextMark> chunk_marks = new Gee.HashMap<string, Gtk.TextMark> ();
        private Gee.HashMap<string, UI.InlineChunkOutputWidget> inline_chunk_widgets = new Gee.HashMap<string, UI.InlineChunkOutputWidget> ();

        /**
         * Pillar 11: Embeds an inline output card directly below the executed chunk.
         * Uses persistent Gtk.TextMark tracking to survive line insertions above the chunk.
         */
        public void display_inline_chunk_output (int end_line, string text_output, string? plot_path, int count, double elapsed_ms = -1.0) {
            string? matched_key = null;
            foreach (var entry in chunk_marks.entries) {
                Gtk.TextIter mark_iter;
                source_buffer.get_iter_at_mark (out mark_iter, entry.value);
                int mark_line = mark_iter.get_line ();
                if (mark_line == end_line || mark_line == end_line + 1) {
                    matched_key = entry.key;
                    break;
                }
            }

            UI.InlineChunkOutputWidget? widget = null;
            if (matched_key != null) {
                widget = inline_chunk_widgets.get (matched_key);
            }

            if (widget == null) {
                Gtk.TextIter iter;
                source_buffer.get_iter_at_line (out iter, end_line);
                iter.forward_to_line_end ();

                source_buffer.insert (ref iter, "\n", 1);
                var anchor = source_buffer.create_child_anchor (iter);
                widget = new UI.InlineChunkOutputWidget (end_line);
                source_view.add_child_at_anchor (widget, anchor);

                string key = GLib.Uuid.string_random ();
                var mark = source_buffer.create_mark (null, iter, false);
                chunk_marks.set (key, mark);
                inline_chunk_widgets.set (key, widget);
            }

            widget.set_output (text_output, plot_path, count, elapsed_ms);
        }

        public void clear_inline_chunk_outputs () {
            foreach (var w in inline_chunk_widgets.values) {
                if (w != null && w.get_parent () != null) {
                    w.unparent ();
                }
            }
            foreach (var mark in chunk_marks.values) {
                if (mark != null) {
                    source_buffer.delete_mark (mark);
                }
            }
            inline_chunk_widgets.clear ();
            chunk_marks.clear ();
        }

        public signal void stats_changed (int words, int lines, string lang_badge);

        public DocumentPage (string title, string lang_id, Window? win = null) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.doc_type = lang_id;
            this.initial_title = title;
            this.parent_window = win;
            this.doc_id = GLib.Uuid.string_random ();

            // 1. Setup GtkSource.Buffer with Syntax Highlighting + Rich TextTags
            var lang_manager = GtkSource.LanguageManager.get_default ();
            var fmt = DocumentFormat.from_filename (title);
            string syntax_code = fmt.to_syntax_lang ();
            var language = lang_manager.get_language (syntax_code);
            if (language == null && lang_id.length > 0) {
                language = lang_manager.get_language (lang_id == "rmd" ? "markdown" : lang_id);
            }
            source_buffer = new GtkSource.Buffer.with_language (language);
            source_buffer.highlight_syntax = true;

            update_style_scheme ();

            theme_changed_handler_id = Core.SettingsManager.get_default ().theme_changed.connect ((t) => {
                update_style_scheme ();
                refresh_live_preview ();
            });

            dark_notify_handler_id = Adw.StyleManager.get_default ().notify["dark"].connect (() => {
                if (Core.SettingsManager.get_default ().app_theme == Core.AppTheme.SYSTEM) {
                    update_style_scheme ();
                    refresh_live_preview ();
                }
            });

            setup_text_tags ();
            populate_starter_template (title, lang_id);

            source_view = new GtkSource.View.with_buffer (source_buffer) {
                show_line_numbers = true,
                highlight_current_line = true,
                auto_indent = true,
                indent_width = 2,
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                top_margin = 32,
                bottom_margin = 32,
                left_margin = 48,
                right_margin = 48,
                monospace = true
            };

            setup_completion ();
            setup_cell_execution_shortcut ();

            var editor_context_menu = new GLib.Menu ();
            editor_context_menu.append ("Write with Elrond Assistance (AI)", "app.elrond_assist");
            editor_context_menu.append ("Math & Chemical Reaction Studio...", "app.math_chem_editor");
            source_view.extra_menu = editor_context_menu;

            editor_scroller = new Gtk.ScrolledWindow () {
                child = source_view,
                hexpand = true,
                vexpand = true
            };

            // 2. Shared WebKitGTK 6.0 & Console Instances (Kept alive in PersistentPanelRegistry)
            web_view = UI.WebViewFactory.create ();
            var settings = web_view.get_settings ();
            settings.enable_developer_extras = true;
            settings.enable_javascript = true;
            settings.allow_file_access_from_file_urls = true;
            settings.allow_universal_access_from_file_urls = true;
            settings.enable_spatial_navigation = false;

            int web_process_crashes = 0;
            web_view.web_process_terminated.connect ((reason) => {
                web_process_crashes++;
                GLib.warning ("WebKit WebProcess terminated (reason: %d, count: %d)", (int) reason, web_process_crashes);
                if (web_process_crashes <= 2) {
                    var s = web_view.get_settings ();
                    s.hardware_acceleration_policy = WebKit.HardwareAccelerationPolicy.NEVER;
                    GLib.Idle.add (() => {
                        refresh_live_preview ();
                        return GLib.Source.REMOVE;
                    });
                } else {
                    string fallback = "<!DOCTYPE html><html><body style='font-family:system-ui,sans-serif;padding:24px;color:#b91c1c;background:#fef2f2;'><h3>Live Preview WebProcess Crashed</h3><p>WebKitGTK WebProcess terminated repeatedly. Try disabling Hardware Acceleration in Preferences → Workspace.</p></body></html>";
                    web_view.load_html (fallback, "file:///");
                }
            });

            web_view.load_failed.connect ((load_event, failing_uri, err) => {
                GLib.warning ("WebKit load_failed (%s): %s", failing_uri, err.message);
                string err_html = "<!DOCTYPE html><html><body style='font-family:system-ui,sans-serif;padding:24px;color:#991b1b;background:#fef2f2;'><h3>Preview Load Failed</h3><p><code>%s</code></p><p>%s</p></body></html>".printf (
                    GLib.Markup.escape_text (failing_uri),
                    GLib.Markup.escape_text (err.message)
                );
                web_view.load_html (err_html, "file:///");
                return true;
            });

            // Flush deferred preview loads once GTK4 realizes and maps the WebView with a valid allocation
            web_view.map.connect (() => {
                if (pending_preview_uri != null || pending_preview_refresh) {
                    GLib.Idle.add (() => {
                        if (!web_view.get_mapped ()) return GLib.Source.REMOVE;
                        if (pending_preview_uri != null) {
                            string target_uri = pending_preview_uri;
                            pending_preview_uri = null;
                            pending_preview_refresh = false;
                            web_view.load_uri (target_uri);
                        } else if (pending_preview_refresh) {
                            pending_preview_refresh = false;
                            refresh_live_preview ();
                        }
                        return GLib.Source.REMOVE;
                    });
                }
            });

            console_view = new Gtk.TextView () {
                editable = false,
                monospace = true,
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                top_margin = 12,
                bottom_margin = 12,
                left_margin = 12,
                right_margin = 12
            };

            // 3. Initialize PersistentPanelRegistry & RStudioDockGrid
            dock_layout_state = new RStudioDockLayoutState ();
            dock_layout_state.load_from_disk ();

            panel_registry = new PersistentPanelRegistry (this, parent_window);
            rstudio_dock_grid = new RStudioDockGrid (dock_layout_state, panel_registry, parent_window);

            // 4. Build Apostrophe Shell (Single-Pane / Clean Split Writer View)
            paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                hexpand = true,
                vexpand = true,
                position = 600,
                resize_start_child = true,
                resize_end_child = true,
                shrink_start_child = true,
                shrink_end_child = true
            };

            apostrophe_editor_host = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };

            var sm_phys = Core.SettingsManager.get_default ();
            console_revealer = new Gtk.Revealer () {
                transition_type = Gtk.RevealerTransitionType.SLIDE_LEFT,
                transition_duration = sm_phys.animation_physics.get_revealer_duration_ms (),
                reveal_child = true,
                hexpand = true,
                vexpand = true
            };

            right_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true,
                width_request = 260
            };

            var right_header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 8,
                margin_end = 8
            };

            right_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                transition_duration = sm_phys.animation_physics.get_stack_duration_ms (),
                hexpand = true,
                vexpand = true
            };

            physics_changed_handler_id = sm_phys.physics_changed.connect (() => {
                console_revealer.transition_duration = sm_phys.animation_physics.get_revealer_duration_ms ();
                right_stack.transition_duration = sm_phys.animation_physics.get_stack_duration_ms ();
            });

            var stack_switcher = new Gtk.StackSwitcher () {
                stack = right_stack
            };
            right_header.append (stack_switcher);
            right_header.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            var btn_close_panel = new Gtk.Button.from_icon_name ("window-close-symbolic") {
                tooltip_text = "Close Panel",
                valign = Gtk.Align.CENTER
            };
            btn_close_panel.add_css_class ("flat");
            btn_close_panel.clicked.connect (() => {
                console_revealer.reveal_child = false;
            });
            right_header.append (btn_close_panel);

            right_box.append (right_header);

            apostrophe_preview_host = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                hexpand = true,
                vexpand = true
            };
            right_stack.add_titled (apostrophe_preview_host, "preview", "Live Preview");

            if (parent_window != null) {
                assistant_panel = new AssistantPanel (parent_window);
                right_stack.add_titled (assistant_panel, "assistant", "Elrond Assistance");
            }
            right_stack.visible_child_name = "preview";

            right_box.append (right_stack);
            console_revealer.set_child (right_box);

            apply_panel_position ();
            ai_settings_handler_id = Core.SettingsManager.get_default ().ai_settings_changed.connect (apply_panel_position);

            this.append (paned);
            this.append (rstudio_dock_grid);

            // Mount initial layout based on file extension
            var initial_mode = Services.LayoutMode.from_extension (title);
            set_workbench_mode (initial_mode);

            refresh_live_preview ();

            source_buffer.changed.connect (() => {
                if (update_debounce_id != 0) {
                    GLib.Source.remove (update_debounce_id);
                    update_debounce_id = 0;
                }
                update_debounce_id = GLib.Timeout.add (250, () => {
                    update_debounce_id = 0;
                    string doc_text = source_buffer.text;
                    emit_buffer_stats (doc_text);
                    refresh_live_preview (doc_text);
                    panel_registry.refresh_environment_and_outline ();

                    // Non-blocking shadow buffer write for crash resilience
                    int line = 0;
                    int col = 0;
                    Gtk.TextIter insert_iter;
                    source_buffer.get_iter_at_mark (out insert_iter, source_buffer.get_insert ());
                    line = insert_iter.get_line ();
                    col = insert_iter.get_line_offset ();
                    string? path = file_location != null ? file_location.get_path () : null;

                    Services.RecoveryService.get_default ().snapshot_async.begin (
                        doc_id,
                        path,
                        doc_type,
                        doc_text,
                        line,
                        col,
                        true
                    );

                    return GLib.Source.REMOVE;
                });
            });
        }

        public void cleanup () {
            if (ai_settings_handler_id != 0) {
                Core.SettingsManager.get_default ().disconnect (ai_settings_handler_id);
                ai_settings_handler_id = 0;
            }
            if (theme_changed_handler_id != 0) {
                Core.SettingsManager.get_default ().disconnect (theme_changed_handler_id);
                theme_changed_handler_id = 0;
            }
            if (dark_notify_handler_id != 0) {
                Adw.StyleManager.get_default ().disconnect (dark_notify_handler_id);
                dark_notify_handler_id = 0;
            }
            if (physics_changed_handler_id != 0) {
                Core.SettingsManager.get_default ().disconnect (physics_changed_handler_id);
                physics_changed_handler_id = 0;
            }
            if (panel_registry != null) {
                panel_registry.cleanup ();
            }
            if (update_debounce_id != 0) {
                GLib.Source.remove (update_debounce_id);
                update_debounce_id = 0;
            }
            if (source_buffer != null && !source_buffer.get_modified ()) {
                Services.RecoveryService.get_default ().purge_document_cache (doc_id);
            }
        }

        ~DocumentPage () {
            cleanup ();
        }

        private void setup_cell_execution_shortcut () {
            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                    if ((state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                        if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                            panel_registry.execute_active_cell ();
                        } else {
                            panel_registry.execute_current_line_or_selection ();
                        }
                        return true;
                    }
                    if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        Gtk.TextIter iter;
                        source_buffer.get_iter_at_mark (out iter, source_buffer.get_insert ());
                        var chunk = Core.ChunkParser.find_chunk_at_line (source_buffer.text, iter.get_line ());
                        if (chunk != null) {
                            panel_registry.execute_active_cell_and_advance ();
                            return true;
                        }
                    }
                }
                return false;
            });
            source_view.add_controller (key_ctrl);
        }

        /**
         * Transitions seamlessly between Apostrophe Mode (single-pane writer)
         * and RStudio Mode (4-quadrant dock grid) by re-parenting the persistent
         * panel widgets without losing undo/redo stack or cursor focus.
         */
        public void set_workbench_mode (Services.LayoutMode mode) {
            current_layout_mode = mode;

            if (mode == Services.LayoutMode.APOSTROPHE) {
                rstudio_dock_grid.visible = false;
                paned.visible = true;

                panel_registry.notebook_cell_toolbar.visible = false;
                source_view.left_margin = 72;
                source_view.right_margin = 72;

                panel_registry.mount_panel (PanelId.SOURCE_EDITOR, apostrophe_editor_host);
                panel_registry.mount_panel (PanelId.LIVE_PREVIEW, apostrophe_preview_host);
            } else {
                paned.visible = false;
                rstudio_dock_grid.visible = true;

                panel_registry.notebook_cell_toolbar.visible = true;
                source_view.left_margin = 28;
                source_view.right_margin = 28;

                rstudio_dock_grid.refresh_dock_layout ();
            }
        }

        private void setup_text_tags () {
            source_buffer.create_tag ("bold", "weight", Pango.Weight.BOLD);
            source_buffer.create_tag ("italic", "style", Pango.Style.ITALIC);
            source_buffer.create_tag ("underline", "underline", Pango.Underline.SINGLE);
            source_buffer.create_tag ("strike", "strikethrough", true);
            source_buffer.create_tag ("strikethrough", "strikethrough", true);
            source_buffer.create_tag ("code", "family", "monospace");
            source_buffer.create_tag ("h1", "scale", 1.7, "weight", Pango.Weight.BOLD);
            source_buffer.create_tag ("h2", "scale", 1.4, "weight", Pango.Weight.BOLD);
            source_buffer.create_tag ("h3", "scale", 1.2, "weight", Pango.Weight.BOLD);
        }

        private void populate_starter_template (string title, string lang_id) {
            if (lang_id == "markdown" || lang_id == "rmd") {
                source_buffer.text = """---
title: "%s"
format:
  html: default
  pdf: default
---

# Introduction

Write your scientific narrative or documentation here.

```{r}
#| echo: true
#| warning: false
summary(mtcars[, 1:4])
```

```{python}
import sys
print("Python Kernel Ready:", sys.version.split()[0])
```
""".printf (title);
            } else if (lang_id == "typescript") {
                source_buffer.text = """// Imladris TypeScript Module
export interface DataPoint {
  id: number;
  label: string;
  value: number;
}

export function summarize(points: DataPoint[]): number {
  return points.reduce((acc, item) => acc + item.value, 0);
}
""";
            } else if (lang_id == "r") {
                source_buffer.text = """# Imladris R Script Session
# Author: %s
summary(mtcars[, 1:4])
""".printf (GLib.Environment.get_real_name ());
            } else if (lang_id == "python3") {
                source_buffer.text = """#!/usr/bin/env python3
# Imladris Python Script Session
import sys
print("Python Interpreter:", sys.version.split()[0])
""";
            } else if (lang_id == "html") {
                source_buffer.text = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Imladris Live HTML Document</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 2rem; color: #1e293b; }
    h1 { color: #2b73d2; }
  </style>
</head>
<body>
  <h1>Imladris HTML5 Studio</h1>
  <p>Live rendered via <strong>WebKitGTK 6.0</strong>.</p>
</body>
</html>
""";
            }
        }

        private void update_style_scheme () {
            var sm = GtkSource.StyleSchemeManager.get_default ();
            var theme = Core.SettingsManager.get_default ().app_theme;
            bool is_dark = Adw.StyleManager.get_default ().dark;

            GtkSource.StyleScheme? scheme = null;
            if (theme == Core.AppTheme.DARK || (theme == Core.AppTheme.SYSTEM && is_dark)) {
                scheme = sm.get_scheme ("Adwaita-dark") ?? sm.get_scheme ("classic-dark");
            } else if (theme == Core.AppTheme.EYE_FRIENDLY) {
                scheme = sm.get_scheme ("solarized-light") ?? sm.get_scheme ("tango") ?? sm.get_scheme ("Adwaita");
            } else {
                scheme = sm.get_scheme ("Adwaita") ?? sm.get_scheme ("classic");
            }

            if (scheme != null) {
                source_buffer.style_scheme = scheme;
            }
        }

        public void refresh_live_preview (string? preloaded_text = null) {
            bool is_preview_hidden = !web_view.get_mapped () ||
                (current_layout_mode == Services.LayoutMode.APOSTROPHE &&
                 (!console_revealer.reveal_child || right_stack.visible_child_name != "preview"));
            if (is_preview_hidden) {
                pending_preview_refresh = true;
                return;
            }
            pending_preview_refresh = false;
            pending_preview_uri = null;

            string raw = preloaded_text != null ? preloaded_text : source_buffer.text;
            string? base_uri = null;
            if (file_location != null) {
                var parent = file_location.get_parent ();
                base_uri = parent != null ? parent.get_uri () + "/" : file_location.get_uri ();
            } else {
                base_uri = "file:///";
            }

            var fmt = get_document_format ();
            if (doc_type == "html" || fmt == DocumentFormat.HTML) {
                web_view.load_html (Adapters.DocumentAdapter.render_html_with_latex (raw), base_uri);
                return;
            }

            string body_html = Adapters.DocumentAdapter.render_html (raw, fmt);

            var app_theme = Core.SettingsManager.get_default ().app_theme;
            bool is_dark = Adw.StyleManager.get_default ().dark;
            bool use_dark = (app_theme == Core.AppTheme.DARK) || (app_theme == Core.AppTheme.SYSTEM && is_dark);
            bool use_sepia = (app_theme == Core.AppTheme.EYE_FRIENDLY);

            string bg_color = use_dark ? "#1e1e1e" : (use_sepia ? "#faf5ee" : "#ffffff");
            string text_color = use_dark ? "#e2e8f0" : (use_sepia ? "#383431" : "#1e242b");
            string card_bg = use_dark ? "#262626" : (use_sepia ? "#f0e7dc" : "#f8fafc");
            string card_border = use_dark ? "#404040" : (use_sepia ? "#dcd0c2" : "#cbd5e1");
            string header_bg = use_dark ? "#333333" : (use_sepia ? "#e6dcce" : "#e2e8f0");
            string header_color = use_dark ? "#94a3b8" : (use_sepia ? "#5c534b" : "#475569");

            string html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    font-family: 'Inter', 'Cantarell', system-ui, -apple-system, sans-serif;
    line-height: 1.6;
    color: %s;
    background: %s;
    padding: 24px 32px;
    margin: 0;
  }
  .badge {
    display: inline-block;
    background: #e8f0fe;
    color: #1967d2;
    font-weight: 700;
    font-size: 11px;
    padding: 3px 8px;
    border-radius: 4px;
    margin-bottom: 12px;
    text-transform: uppercase;
  }
  .code-chunk-card {
    background: %s;
    border: 1px solid %s;
    border-radius: 8px;
    margin: 16px 0;
    overflow: hidden;
  }
  .code-chunk-header {
    background: %s;
    padding: 6px 12px;
    font-size: 12px;
    font-weight: 600;
    color: %s;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .chunk-opts {
    font-family: monospace;
    font-size: 11px;
    color: #64748b;
  }
  .document-frontmatter-card {
    background: %s;
    border: 1px solid %s;
    border-radius: 8px;
    padding: 16px 20px;
    margin-bottom: 24px;
  }
  .frontmatter-title {
    margin-top: 0;
    color: %s;
  }
  .frontmatter-meta-grid {
    display: flex;
    flex-wrap: wrap;
    gap: 12px 24px;
    font-size: 13px;
    color: %s;
  }
  .frontmatter-label {
    font-weight: 600;
    margin-right: 6px;
  }
  .frontmatter-badge {
    background: #38bdf8;
    color: #0369a1;
    font-weight: 600;
    padding: 2px 6px;
    border-radius: 4px;
  }
  pre {
    background: %s;
    border: 1px solid %s;
    border-radius: 6px;
    padding: 14px;
    overflow-x: auto;
    font-family: 'JetBrains Mono', monospace;
    font-size: 13px;
    white-space: pre-wrap;
    margin: 8px 12px;
  }
  %s
</style>
</head>
<body>
  <div class="badge">WebKitGTK 6.0 Live Preview • %s</div>
  <div id="content">%s</div>
</body>
</html>""".printf (
                text_color, bg_color,
                card_bg, card_border,
                header_bg, header_color,
                card_bg, card_border,
                text_color, header_color,
                card_bg, card_border,
                Core.MathChemEngine.get_math_chem_css (),
                fmt.to_badge_label (), body_html
            );

            web_view.load_html (html, base_uri);
        }

        public void set_split_orientation (Services.SplitMode split) {
            if (current_layout_mode == Services.LayoutMode.RSTUDIO) {
                // In RStudio mode, activate the corresponding panel regardless of which quadrant hosts it
                dock_layout_state.activate_panel (PanelId.LIVE_PREVIEW);
                return;
            }

            switch (split) {
                case Services.SplitMode.EDITOR_ONLY:
                    apostrophe_editor_host.visible = true;
                    console_revealer.visible = false;
                    break;
                case Services.SplitMode.PREVIEW_ONLY:
                    apostrophe_editor_host.visible = false;
                    console_revealer.visible = true;
                    console_revealer.reveal_child = true;
                    right_stack.visible_child_name = "preview";
                    break;
                case Services.SplitMode.HORIZONTAL_SPLIT:
                    apostrophe_editor_host.visible = true;
                    console_revealer.visible = true;
                    console_revealer.reveal_child = true;
                    paned.orientation = Gtk.Orientation.VERTICAL;
                    right_stack.visible_child_name = "preview";
                    int h = paned.get_height ();
                    if (h > 100) {
                        paned.set_position (h / 2);
                    } else {
                        GLib.Idle.add (() => {
                            int cur_h = paned.get_height ();
                            if (cur_h > 100) paned.set_position (cur_h / 2);
                            return GLib.Source.REMOVE;
                        });
                    }
                    break;
                case Services.SplitMode.VERTICAL_SPLIT:
                default:
                    apostrophe_editor_host.visible = true;
                    console_revealer.visible = true;
                    console_revealer.reveal_child = true;
                    paned.orientation = Gtk.Orientation.HORIZONTAL;
                    right_stack.visible_child_name = "preview";
                    int w = paned.get_width ();
                    if (w > 100) {
                        paned.set_position (w / 2);
                    } else {
                        GLib.Idle.add (() => {
                            int cur_w = paned.get_width ();
                            if (cur_w > 100) paned.set_position (cur_w / 2);
                            return GLib.Source.REMOVE;
                        });
                    }
                    break;
            }
        }

        public void show_live_preview (string? uri = null) {
            if (current_layout_mode == Services.LayoutMode.RSTUDIO) {
                dock_layout_state.activate_panel (PanelId.LIVE_PREVIEW);
            } else {
                console_revealer.visible = true;
                console_revealer.reveal_child = true;
                right_stack.visible_child_name = "preview";
                int cur_w = paned.get_width ();
                if (cur_w > 100 && (paned.position > cur_w - 50 || paned.position < 50)) {
                    paned.position = cur_w / 2;
                }
            }
            if (uri != null) {
                if (web_view.get_mapped ()) {
                    pending_preview_uri = null;
                    pending_preview_refresh = false;
                    web_view.load_uri (uri);
                } else {
                    pending_preview_uri = uri;
                    pending_preview_refresh = false;
                }
            } else {
                refresh_live_preview ();
            }
        }

        public void apply_panel_position () {
            var settings = Core.SettingsManager.get_default ();
            var pos = settings.chat_panel_position;

            bool is_currently_left = (paned.get_start_child () == console_revealer);
            if (pos == Core.SidePanelPosition.LEFT && is_currently_left) {
                return;
            }
            if (pos == Core.SidePanelPosition.RIGHT && !is_currently_left && paned.get_end_child () == console_revealer) {
                return;
            }

            paned.set_start_child (null);
            paned.set_end_child (null);

            if (pos == Core.SidePanelPosition.LEFT) {
                console_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_RIGHT;
                paned.set_start_child (console_revealer);
                paned.set_end_child (apostrophe_editor_host);
                paned.position = 480;
            } else {
                console_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_LEFT;
                paned.set_start_child (apostrophe_editor_host);
                paned.set_end_child (console_revealer);
                int total_w = paned.get_width ();
                paned.position = total_w > 500 ? (total_w - 480) : 780;
            }
        }

        public void show_ai_assistant () {
            if (current_layout_mode == Services.LayoutMode.RSTUDIO) {
                set_workbench_mode (Services.LayoutMode.APOSTROPHE);
            }
            apply_panel_position ();
            console_revealer.visible = true;
            console_revealer.reveal_child = true;
            right_stack.visible_child_name = "assistant";
            if (assistant_panel != null) {
                assistant_panel.focus_input ();
            }
        }

        private void setup_completion () {
            var completion = source_view.get_completion ();
            completion.select_on_show = true;
            completion.show_icons = true;
            completion.remember_info_visibility = true;

            var intellisense_provider = new Editor.CodeIntelliSenseProvider (this);
            completion.add_provider (intellisense_provider);

            var citation_provider = new Editor.CitationCompletionProvider (this);
            completion.add_provider (citation_provider);

            var ai_provider = new AI.AiCompletionProvider ();
            completion.add_provider (ai_provider);

            var words_provider = new GtkSource.CompletionWords ("Document Vocabulary");
            words_provider.register (source_buffer);
            words_provider.minimum_word_size = 2;
            words_provider.priority = 10;
            completion.add_provider (words_provider);

            var snippets_provider = new GtkSource.CompletionSnippets ();
            snippets_provider.priority = 20;
            completion.add_provider (snippets_provider);

            Editor.BracketAutoPairController.attach (source_view, source_buffer);
        }

        public string get_selected_text () {
            Gtk.TextIter start, end;
            if (source_buffer.get_selection_bounds (out start, out end)) {
                return source_buffer.get_text (start, end, false);
            }
            return "";
        }

        public void insert_ai_code_at_cursor (string code) {
            string cleaned = code.strip ();
            source_buffer.begin_user_action ();
            Gtk.TextIter start, end;
            if (source_buffer.get_selection_bounds (out start, out end)) {
                source_buffer.delete (ref start, ref end);
                source_buffer.insert (ref start, cleaned, -1);
            } else {
                source_buffer.insert_at_cursor ("\n" + cleaned + "\n", -1);
            }
            source_buffer.end_user_action ();
        }

        public void insert_media_snippet (string snippet) {
            source_buffer.begin_user_action ();
            Gtk.TextIter start, end;
            if (source_buffer.get_selection_bounds (out start, out end)) {
                source_buffer.delete (ref start, ref end);
                source_buffer.insert (ref start, snippet, -1);
            } else {
                source_buffer.insert_at_cursor (snippet, -1);
            }
            source_buffer.end_user_action ();
            refresh_live_preview ();
        }

        public void show_inline_prompt_popover () {
            Gtk.TextIter cursor_iter;
            source_buffer.get_iter_at_mark (out cursor_iter, source_buffer.get_insert ());
            Gdk.Rectangle rect;
            source_view.get_iter_location (cursor_iter, out rect);

            int win_x, win_y;
            source_view.buffer_to_window_coords (Gtk.TextWindowType.WIDGET, rect.x, rect.y, out win_x, out win_y);
            var pointing_rect = Gdk.Rectangle () {
                x = win_x,
                y = win_y,
                width = 1,
                height = rect.height
            };

            var popover = new Gtk.Popover ();
            popover.set_parent (source_view);
            popover.set_pointing_to (pointing_rect);
            popover.has_arrow = true;
            popover.autohide = true;

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 10,
                margin_bottom = 10,
                margin_start = 10,
                margin_end = 10,
                width_request = 440
            };

            string initial_sel = get_selected_text ().strip ();
            bool has_sel = initial_sel.length > 0;

            var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var icon = new Gtk.Image.from_icon_name ("ai-elrond") { pixel_size = 20 };
            var title_lbl = new Gtk.Label ("Elrond Inline Assistance") {
                css_classes = { "heading" },
                hexpand = true,
                xalign = 0.0f
            };
            var ctx_badge = new Gtk.Label (has_sel ? "Replacing selection" : "At cursor") {
                css_classes = { "dim-label", "caption" }
            };
            header_box.append (icon);
            header_box.append (title_lbl);
            header_box.append (ctx_badge);
            content_box.append (header_box);

            var quick_pills = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            var prompt_entry = new Gtk.Entry () {
                placeholder_text = has_sel
                    ? "Ask Elrond how to transform this selection…"
                    : "Ask Elrond to write code, a plot, or prose…",
                hexpand = true
            };

            var spinner = new Adw.Spinner () { visible = false };
            var btn_generate = new Gtk.Button.with_label ("Generate") {
                css_classes = { "suggested-action" }
            };

            var preview_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                visible = false
            };
            var preview_view = new Gtk.TextView () {
                editable = true,
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                monospace = true,
                top_margin = 6,
                bottom_margin = 6,
                left_margin = 8,
                right_margin = 8
            };
            var preview_scroller = new Gtk.ScrolledWindow () {
                child = preview_view,
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                min_content_height = 90,
                max_content_height = 220
            };
            preview_scroller.add_css_class ("card");
            preview_box.append (preview_scroller);

            var preview_actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var btn_copy_inline = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy to clipboard"
            };
            btn_copy_inline.add_css_class ("flat");
            btn_copy_inline.clicked.connect (() => {
                var disp = Gdk.Display.get_default ();
                if (disp != null) {
                    disp.get_clipboard ().set_text (preview_view.buffer.text);
                }
            });
            var btn_regen = new Gtk.Button.with_label ("Regenerate");
            btn_regen.add_css_class ("flat");
            var btn_accept = new Gtk.Button.with_label (has_sel ? "Replace Selection" : "Insert at Cursor") {
                css_classes = { "suggested-action" }
            };
            btn_accept.clicked.connect (() => {
                string out_text = preview_view.buffer.text;
                popover.popdown ();
                insert_ai_code_at_cursor (out_text);
            });
            preview_actions.append (btn_copy_inline);
            preview_actions.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });
            preview_actions.append (btn_regen);
            preview_actions.append (btn_accept);
            preview_box.append (preview_actions);

            var err_lbl = new Gtk.Label ("") {
                xalign = 0.0f,
                wrap = true,
                visible = false,
                css_classes = { "error", "caption" }
            };

            string[] quick_labels = { "Fix & Clean", "Add Comments", "Explain", "R Plot" };
            string[] quick_prompts = {
                "Fix syntax or logic issues and return clean corrected code.",
                "Add concise scientific comments explaining each step.",
                "Explain what this code does concisely as markdown.",
                "Generate a clean Quarto {r} ggplot2 visualization chunk."
            };
            for (int qi = 0; qi < quick_labels.length; qi++) {
                string q_prompt = quick_prompts[qi];
                var q_btn = new Gtk.Button.with_label (quick_labels[qi]);
                q_btn.add_css_class ("pill");
                q_btn.add_css_class ("caption");
                q_btn.clicked.connect (() => {
                    prompt_entry.text = q_prompt;
                    btn_generate.activate ();
                });
                quick_pills.append (q_btn);
            }
            content_box.append (quick_pills);

            var entry_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            entry_row.append (prompt_entry);
            entry_row.append (spinner);
            entry_row.append (btn_generate);
            content_box.append (entry_row);
            content_box.append (err_lbl);
            content_box.append (preview_box);

            SourceFunc execute_generation = () => {
                string prompt = prompt_entry.text.strip ();
                if (prompt.length == 0) return Source.REMOVE;

                prompt_entry.sensitive = false;
                btn_generate.sensitive = false;
                spinner.visible = true;
                err_lbl.visible = false;

                string sel = get_selected_text ();
                string doc_lang = this.doc_type;
                string doc_text = source_buffer.text;
                string full_prompt = prompt + (sel.length > 0 ? "\n[Selected Code]:\n" + sel : "");

                var elrond = Imladris.AI.ElrondEngineController.get_default ();
                if (elrond.is_ready) {
                    elrond.write_with_elrond.begin (doc_lang, doc_text, "", full_prompt, (obj, res) => {
                        spinner.visible = false;
                        prompt_entry.sensitive = true;
                        btn_generate.sensitive = true;
                        try {
                            string generated = elrond.write_with_elrond.end (res).strip ();
                            preview_view.buffer.text = generated;
                            preview_box.visible = true;
                        } catch (Error e) {
                            err_lbl.label = @"Elrond error: $(e.message)";
                            err_lbl.visible = true;
                        }
                    });
                } else {
                    var ai_client = new AiClient ();
                    string sys_prompt = "You are Elrond Assistance (AI), an expert scientific and coding assistant. Generate clean, correct code or statistical functions. Return only the requested code or concise explanation.";
                    ai_client.send_chat_completion_async.begin (sys_prompt, full_prompt, null, (obj, res) => {
                        spinner.visible = false;
                        prompt_entry.sensitive = true;
                        btn_generate.sensitive = true;
                        try {
                            string generated = ai_client.send_chat_completion_async.end (res).strip ();
                            preview_view.buffer.text = generated;
                            preview_box.visible = true;
                        } catch (Error e) {
                            err_lbl.label = @"AI error: $(e.message)";
                            err_lbl.visible = true;
                        }
                    });
                }
                return Source.REMOVE;
            };

            btn_regen.clicked.connect (() => {
                execute_generation ();
            });
            prompt_entry.activate.connect (() => {
                execute_generation ();
            });
            btn_generate.clicked.connect (() => {
                execute_generation ();
            });

            popover.set_child (content_box);
            popover.closed.connect (() => {
                popover.unparent ();
            });
            popover.popup ();
            prompt_entry.grab_focus ();
        }

        public void apply_tag_or_syntax (string tag_name, string md_wrapper) {
            Gtk.TextIter start, end;
            source_buffer.begin_user_action ();
            if (source_buffer.get_selection_bounds (out start, out end)) {
                string selected = source_buffer.get_text (start, end, false);
                if (md_wrapper.length > 0) {
                    string wrapped = md_wrapper + selected + md_wrapper;
                    source_buffer.delete (ref start, ref end);
                    source_buffer.insert (ref start, wrapped, wrapped.length);
                } else if (source_buffer.tag_table.lookup (tag_name) != null) {
                    source_buffer.apply_tag_by_name (tag_name, start, end);
                }
            } else {
                source_buffer.insert_at_cursor (@"$md_wrapper$md_wrapper", -1);
            }
            source_buffer.end_user_action ();
        }

        public void insert_code_chunk (string engine, string options = "") {
            string opt_line = options.length > 0 ? @"#| $options\n" : "";
            string snippet = @"\n```{$engine}\n$opt_line\n```\n";
            source_buffer.insert_at_cursor (snippet, -1);
        }

        /**
         * Jupyter Parity: Inserts a markdown narrative section at cursor.
         */
        public void insert_markdown_cell (string placeholder = "New Section") {
            string snippet = @"\n\n### $placeholder\n\nEnter markdown notes, formulas, or equations here.\n\n";
            source_buffer.insert_at_cursor (snippet, -1);
        }

        /**
         * Jupyter Parity: Inserts a raw text block at cursor.
         */
        public void insert_raw_cell (string content = "") {
            string snippet = @"\n```{raw}\n$content\n```\n";
            source_buffer.insert_at_cursor (snippet, -1);
        }

        public void insert_markdown_table (int rows, int cols) {
            var sb = new GLib.StringBuilder ("\n|");
            for (int c = 1; c <= cols; c++) sb.append (@" Header $c |");
            sb.append ("\n|");
            for (int c = 1; c <= cols; c++) sb.append (" --- |");
            for (int r = 1; r <= rows; r++) {
                sb.append ("\n|");
                for (int c = 1; c <= cols; c++) sb.append (" Cell |");
            }
            sb.append ("\n");
            source_buffer.insert_at_cursor (sb.str, -1);
        }

        public void append_console_log (string text) {
            if (current_layout_mode == Services.LayoutMode.RSTUDIO) {
                dock_layout_state.activate_tab (QuadrantId.Q2_BOTTOM_LEFT, PanelId.CONSOLE);
            }
            Gtk.TextIter end;
            console_view.buffer.get_end_iter (out end);
            console_view.buffer.insert (ref end, text + "\n", -1);
        }

        public void emit_buffer_stats (string? preloaded_text = null) {
            string txt = preloaded_text != null ? preloaded_text : source_buffer.text;
            int words = 0;
            bool in_word = false;
            for (int i = 0; i < txt.length; i++) {
                char c = txt[i];
                if (c == ' ' || c == '\n' || c == '\t' || c == '\r') {
                    in_word = false;
                } else if (!in_word) {
                    in_word = true;
                    words++;
                }
            }
            int lines = source_buffer.get_line_count ();
            stats_changed (words, lines, doc_type.up ());
        }

        public void run_chunks_above () {
            panel_registry.execute_cells_above ();
        }

        public void run_chunks_below () {
            panel_registry.execute_cells_below ();
        }

        public void clear_console () {
            console_view.buffer.text = "";
        }

        public void undo () {
            if (source_buffer.can_undo) {
                source_buffer.undo ();
            }
        }

        public void redo () {
            if (source_buffer.can_redo) {
                source_buffer.redo ();
            }
        }

        public void set_zoom (int percent) {
            web_view.zoom_level = (double) percent / 100.0;
        }

        public void apply_heading (int level) {
            if (level <= 0) return;
            string prefix = string.nfill (level, '#') + " ";
            Gtk.TextIter insert_iter;
            source_buffer.get_iter_at_mark (out insert_iter, source_buffer.get_insert ());
            insert_iter.set_line_offset (0);
            source_buffer.insert (ref insert_iter, prefix, -1);
        }

        public void insert_list_item (string prefix) {
            Gtk.TextIter insert_iter;
            source_buffer.get_iter_at_mark (out insert_iter, source_buffer.get_insert ());
            insert_iter.set_line_offset (0);
            source_buffer.insert (ref insert_iter, prefix, -1);
        }
    }
}
