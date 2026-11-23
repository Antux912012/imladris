// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using Imladris.Core.Layout;
using Imladris.UI;

namespace Imladris {

    public class DocumentPage : Gtk.Box {

        public GtkSource.View source_view { get; private set; }
        public GtkSource.Buffer source_buffer { get; private set; }
        public RtfEditorView? rtf_editor { get; private set; default = null; }
        public Gtk.TextView console_view { get; private set; }
        public WebKit.WebView web_view { get; private set; }
        public UI.NativePreviewView native_preview { get; private set; }
        public Gtk.Stack preview_stack { get; private set; }
        private ulong preview_backend_handler_id = 0;
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
        private unowned Window? parent_window;
        private uint update_debounce_id = 0;
        private int web_process_crashes = 0;
        private int deferred_flush_attempts = 0;
        private uint layout_idle_id = 0;

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
        public Services.SplitMode preferred_split_mode { get; set; default = Services.SplitMode.HORIZONTAL_SPLIT; }
        public bool user_layout_override { get; set; default = false; }
        public string raw_ipynb_source { get; set; default = ""; }
        private static bool lang_specs_registered = false;
        private ulong ai_settings_handler_id = 0;
        private ulong theme_changed_handler_id = 0;
        private ulong dark_notify_handler_id = 0;
        private ulong physics_changed_handler_id = 0;
        private double last_preview_scroll_y = 0.0;
        private bool has_loaded_preview = false;
        private uint64 preview_load_generation = 0;
        private string? active_custom_uri = null;
        private uint deferred_flush_id = 0;
        private uint scroll_sync_debounce_id = 0;
        private Gtk.Picture webview_snapshot;
        private bool has_webview_snapshot = false;
        private string? queued_preview_html = null;
        private string? queued_preview_base_uri = null;

        public Services.LayoutMode get_workbench_mode () {
            return current_layout_mode;
        }

        public string get_clean_source_text () {
            if (rtf_editor != null) {
                return rtf_editor.serialize_rtf ();
            }
            return source_buffer.text.replace ("\xef\xbf\xbc", "");
        }

        public void set_initial_content (string text, bool mark_unmodified = true) {
            if (rtf_editor != null) {
                rtf_editor.load_rtf (text);
                if (mark_unmodified) {
                    rtf_editor.buffer.set_modified (false);
                    source_buffer.set_modified (false);
                }
            } else {
                source_buffer.begin_irreversible_action ();
                try {
                    source_buffer.text = text;
                } finally {
                    source_buffer.end_irreversible_action ();
                }
                if (mark_unmodified) {
                    source_buffer.set_modified (false);
                }
            }
            if (update_debounce_id != 0) {
                GLib.Source.remove (update_debounce_id);
                update_debounce_id = 0;
            }
            refresh_live_preview (text);
        }

        private static void ensure_bundled_language_specs () {
            if (lang_specs_registered) return;
            lang_specs_registered = true;

            var lm = GtkSource.LanguageManager.get_default ();
            string cache_specs_dir = GLib.Path.build_filename (
                GLib.Environment.get_user_cache_dir (), "imladris", "language-specs"
            );
            try {
                GLib.DirUtils.create_with_parents (cache_specs_dir, 0755);
                string[] specs = { "quarto.lang", "rmd.lang", "typescript.lang", "latex.lang" };
                foreach (string spec in specs) {
                    string res_path = @"/org/imladris/app/language-specs/$spec";
                    if (GLib.resources_get_info (res_path, GLib.ResourceLookupFlags.NONE, null, null)) {
                        GLib.Bytes bytes = GLib.resources_lookup_data (res_path, GLib.ResourceLookupFlags.NONE);
                        string out_path = GLib.Path.build_filename (cache_specs_dir, spec);
                        GLib.FileUtils.set_data (out_path, bytes.get_data ());
                    }
                }
            } catch (GLib.Error e) {
                GLib.warning ("Could not stage bundled language-specs: %s", e.message);
            }

            string[]? existing = lm.get_search_path ();
            int extra = 0;
            if (existing != null) {
                foreach (string p in existing) {
                    if (p != cache_specs_dir) extra++;
                }
            }
            string[] paths = new string[1 + extra];
            paths[0] = cache_specs_dir;
            int idx = 1;
            if (existing != null) {
                foreach (string p in existing) {
                    if (p != cache_specs_dir) {
                        paths[idx++] = p;
                    }
                }
            }
            lm.set_search_path (paths);
        }

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
        private Gee.HashMap<string, Gtk.TextChildAnchor> chunk_anchors = new Gee.HashMap<string, Gtk.TextChildAnchor> ();
        private Gee.HashMap<string, UI.InlineChunkOutputWidget> inline_chunk_widgets = new Gee.HashMap<string, UI.InlineChunkOutputWidget> ();

        /**
         * Pillar 11: Embeds an inline output card directly below the executed chunk.
         * Uses persistent Gtk.TextMark tracking to survive line insertions above the chunk,
         * wrapped in irreversible actions so Undo history and modified state are never poisoned.
         */
        public void display_inline_chunk_output (int end_line, string text_output, string? plot_path, int count, double elapsed_ms = -1.0) {
            string? matched_key = null;
            foreach (var entry in chunk_marks.entries) {
                if (entry.value == null || entry.value.get_deleted ()) continue;
                Gtk.TextIter mark_iter;
                source_buffer.get_iter_at_mark (out mark_iter, entry.value);
                int mark_line = mark_iter.get_line ();
                if (mark_line == end_line || mark_line == end_line + 1) {
                    var anc = chunk_anchors.get (entry.key);
                    var w = inline_chunk_widgets.get (entry.key);
                    if (anc != null && !anc.get_deleted () && w != null && w.get_parent () != null) {
                        matched_key = entry.key;
                        break;
                    }
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

                bool was_modified = source_buffer.get_modified ();
                source_buffer.begin_irreversible_action ();
                try {
                    source_buffer.insert (ref iter, "\n", 1);
                    var anchor = source_buffer.create_child_anchor (iter);
                    widget = new UI.InlineChunkOutputWidget (end_line);
                    source_view.add_child_at_anchor (widget, anchor);

                    Gtk.TextIter after_anchor = iter;
                    after_anchor.forward_char ();
                    string key = GLib.Uuid.string_random ();
                    var mark = source_buffer.create_mark (null, after_anchor, false);
                    chunk_marks.set (key, mark);
                    chunk_anchors.set (key, anchor);
                    inline_chunk_widgets.set (key, widget);
                } finally {
                    source_buffer.end_irreversible_action ();
                    if (!was_modified) {
                        source_buffer.set_modified (false);
                    }
                }
            }

            widget.set_output (text_output, plot_path, count, elapsed_ms);
        }

        public void clear_inline_chunk_outputs () {
            foreach (var w in inline_chunk_widgets.values) {
                if (w != null && w.get_parent () != null) {
                    w.unparent ();
                }
            }
            bool was_modified = source_buffer.get_modified ();
            source_buffer.begin_irreversible_action ();
            try {
                foreach (var mark in chunk_marks.values) {
                    if (mark != null && !mark.get_deleted ()) {
                        Gtk.TextIter end_it;
                        source_buffer.get_iter_at_mark (out end_it, mark);
                        Gtk.TextIter start_it = end_it;
                        if (start_it.backward_char () && start_it.get_char () == (unichar) 0xFFFC) {
                            Gtk.TextIter nl_it = start_it;
                            if (nl_it.backward_char () && nl_it.get_char () == '\n') {
                                start_it = nl_it;
                            }
                            source_buffer.delete (ref start_it, ref end_it);
                        }
                        source_buffer.delete_mark (mark);
                    }
                }
            } finally {
                source_buffer.end_irreversible_action ();
                if (!was_modified) {
                    source_buffer.set_modified (false);
                }
            }
            inline_chunk_widgets.clear ();
            chunk_anchors.clear ();
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
            ensure_bundled_language_specs ();
            var lang_manager = GtkSource.LanguageManager.get_default ();
            var fmt = DocumentFormat.from_filename (title);
            string syntax_code = fmt.to_syntax_lang ();
            GtkSource.Language? language = syntax_code.length > 0
                ? lang_manager.get_language (syntax_code)
                : null;
            if (language == null && lang_id.length > 0) {
                language = lang_manager.get_language (lang_id);
            }
            if (language == null) {
                if (syntax_code == "quarto" || syntax_code == "rmd" || syntax_code == "latex") {
                    language = lang_manager.get_language ("markdown");
                } else if (syntax_code == "typescript") {
                    language = lang_manager.get_language ("js");
                }
            }
            source_buffer = (language != null)
                ? new GtkSource.Buffer.with_language (language)
                : new GtkSource.Buffer (null);
            source_buffer.highlight_syntax = (language != null);

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
            editor_context_menu.append ("Insert Table...", "win.insert_table");
            editor_context_menu.append ("Write with Elrond Assistance (AI)", "app.elrond_assist");
            editor_context_menu.append ("Math & Chemical Reaction Studio...", "app.math_chem_editor");
            source_view.extra_menu = editor_context_menu;

            editor_scroller = new Gtk.ScrolledWindow () {
                child = source_view,
                hexpand = true,
                vexpand = true
            };
            if (get_document_format () == DocumentFormat.RTF) {
                rtf_editor = new RtfEditorView ();
                rtf_editor.scroller.vadjustment.value_changed.connect (() => {
                    schedule_preview_scroll_sync ();
                });
                rtf_editor.content_changed.connect (() => {
                    source_buffer.set_modified (true);
                    if (update_debounce_id != 0) {
                        GLib.Source.remove (update_debounce_id);
                        update_debounce_id = 0;
                    }
                    update_debounce_id = GLib.Timeout.add (250, () => {
                        update_debounce_id = 0;
                        string doc_text = get_clean_source_text ();
                        emit_buffer_stats (doc_text);
                        refresh_live_preview (doc_text);
                        panel_registry.refresh_environment_and_outline (doc_text);

                        if (!rtf_editor.buffer.get_modified () && !source_buffer.get_modified ()) {
                            return GLib.Source.REMOVE;
                        }

                        Gtk.TextIter insert_iter;
                        rtf_editor.buffer.get_iter_at_mark (out insert_iter, rtf_editor.buffer.get_insert ());
                        int line = insert_iter.get_line ();
                        int col = insert_iter.get_line_offset ();
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
            populate_starter_template (title, lang_id);
            editor_scroller.vadjustment.value_changed.connect (() => {
                schedule_preview_scroll_sync ();
            });
            source_buffer.notify["cursor-position"].connect (() => {
                if (source_view.has_focus) {
                    schedule_preview_scroll_sync ();
                }
            });

            // 2. Shared WebKitGTK 6.0 & Native Preview Stack (Kept alive in PersistentPanelRegistry)
            web_view = UI.WebViewFactory.create ();
            webview_snapshot = new Gtk.Picture () {
                hexpand = true,
                vexpand = true,
                can_target = false,
                visible = false,
                content_fit = Gtk.ContentFit.FILL
            };
            var web_overlay = new Gtk.Overlay () {
                hexpand = true,
                vexpand = true
            };
            web_overlay.set_child (web_view);
            web_overlay.add_overlay (webview_snapshot);

            native_preview = new UI.NativePreviewView ();
            preview_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                hexpand = true,
                vexpand = true
            };
            preview_stack.add_named (web_overlay, "webkit");
            preview_stack.add_named (native_preview, "native");
            var init_pb = Core.SettingsManager.get_default ().preview_backend;
            preview_stack.visible_child_name = (init_pb == Core.PreviewBackend.WEBKIT_HTML) ? "webkit" : "native";
            preview_backend_handler_id = Core.SettingsManager.get_default ().preview_backend_changed.connect ((new_pb) => {
                preview_stack.visible_child_name = (new_pb == Core.PreviewBackend.WEBKIT_HTML) ? "webkit" : "native";
                refresh_live_preview ();
            });
            var settings = web_view.get_settings ();
            settings.enable_javascript = true;
            settings.enable_spatial_navigation = false;

            // Match Apostrophe's PreviewWebView: open user-clicked external links in system browser
            web_view.decide_policy.connect ((decision, decision_type) => {
                if (decision_type == WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
                    var nav_decision = decision as WebKit.NavigationPolicyDecision;
                    if (nav_decision != null) {
                        var nav_action = nav_decision.get_navigation_action ();
                        if (nav_action != null && nav_action.is_user_gesture ()) {
                            var req = nav_action.get_request ();
                            string? target_uri = req != null ? req.get_uri () : null;
                            if (target_uri != null && (target_uri.has_prefix ("http://") || target_uri.has_prefix ("https://"))) {
                                try {
                                    GLib.AppInfo.launch_default_for_uri (target_uri, null);
                                } catch (GLib.Error e) {
                                    GLib.warning ("Failed to launch external preview URI %s: %s", target_uri, e.message);
                                }
                                decision.ignore ();
                                return true;
                            }
                        }
                    }
                }
                return false;
            });

            web_view.load_changed.connect ((load_event) => {
                if (load_event == WebKit.LoadEvent.STARTED) {
                    if (has_webview_snapshot) {
                        webview_snapshot.visible = true;
                    }
                } else if (load_event == WebKit.LoadEvent.FINISHED) {
                    has_loaded_preview = true;
                    webview_snapshot.visible = false;
                    if (last_preview_scroll_y > 0.0) {
                        int target_y = (int) Math.round (last_preview_scroll_y);
                        web_view.evaluate_javascript.begin (@"window.scrollTo(0, $(target_y));", -1, null, null, null);
                    }
                    // Apostrophe-style queued reload: flush latest edit that arrived mid-load
                    if (queued_preview_html != null) {
                        string next_html = queued_preview_html;
                        string next_base = queued_preview_base_uri ?? "file://localhost/";
                        queued_preview_html = null;
                        queued_preview_base_uri = null;
                        load_html_preserving_scroll (next_html, next_base);
                    }
                }
            });

            web_view.web_process_terminated.connect ((reason) => {
                web_process_crashes++;
                has_loaded_preview = false;
                has_webview_snapshot = false;
                webview_snapshot.visible = false;
                queued_preview_html = null;
                queued_preview_base_uri = null;
                preview_load_generation++;
                GLib.warning ("WebKit WebProcess terminated (reason: %d, count: %d)", (int) reason, web_process_crashes);
                if (web_process_crashes <= 2) {
                    var s = web_view.get_settings ();
                    s.hardware_acceleration_policy = WebKit.HardwareAccelerationPolicy.NEVER;
                    s.enable_webgl = false;
                    GLib.Idle.add (() => {
                        refresh_live_preview ();
                        return GLib.Source.REMOVE;
                    });
                } else {
                    string fallback = "<!DOCTYPE html><html><body style='font-family:system-ui,sans-serif;padding:24px;color:#b91c1c;background:#fef2f2;'><h3>Live Preview WebProcess Crashed</h3><p>WebKitGTK WebProcess terminated repeatedly. Try disabling Hardware Acceleration in Preferences → Workspace.</p></body></html>";
                    web_view.load_html (fallback, "file://localhost/");
                }
            });

            web_view.load_failed.connect ((load_event, failing_uri, err) => {
                webview_snapshot.visible = false;
                if (err is WebKit.NetworkError.CANCELLED || err is GLib.IOError.CANCELLED) {
                    return true;
                }
                GLib.warning ("WebKit load_failed (%s): %s", failing_uri, err.message);
                string err_html = "<!DOCTYPE html><html><body style='font-family:system-ui,sans-serif;padding:24px;color:#991b1b;background:#fef2f2;'><h3>Preview Load Failed</h3><p><code>%s</code></p><p>%s</p></body></html>".printf (
                    GLib.Markup.escape_text (failing_uri),
                    GLib.Markup.escape_text (err.message)
                );
                web_view.load_html (err_html, "file://localhost/");
                return true;
            });

            // Reparenting (Apostrophe <-> RStudio or moving quadrants) unrealizes the WebView in GTK4,
            // which can drop its backing surface; mark it for reload once re-mapped.
            web_view.unrealize.connect (() => {
                has_loaded_preview = false;
                has_webview_snapshot = false;
                webview_snapshot.visible = false;
                queued_preview_html = null;
                queued_preview_base_uri = null;
                preview_load_generation++;
                if (active_custom_uri != null && pending_preview_uri == null) {
                    pending_preview_uri = active_custom_uri;
                } else if (pending_preview_uri == null) {
                    pending_preview_refresh = true;
                }
            });

            // Flush deferred preview loads once GTK4 realizes and maps the WebView with a valid allocation
            web_view.map.connect (() => {
                if (pending_preview_uri != null || pending_preview_refresh) {
                    schedule_deferred_preview_flush ();
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
            dock_layout_state.state_updated.connect (() => {
                if (current_layout_mode == Services.LayoutMode.RSTUDIO) {
                    refresh_pending_preview_if_visible ();
                }
            });

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
            right_stack.notify["visible-child-name"].connect (() => {
                if (right_stack.visible_child_name == "preview") {
                    refresh_pending_preview_if_visible ();
                }
            });
            console_revealer.notify["reveal-child"].connect (() => {
                if (console_revealer.reveal_child) {
                    refresh_pending_preview_if_visible ();
                }
                if (parent_window != null && parent_window.get_active_document () == this) {
                    parent_window.sync_document_ui_toggles (this);
                }
            });
            console_revealer.notify["visible"].connect (() => {
                if (parent_window != null && parent_window.get_active_document () == this) {
                    parent_window.sync_document_ui_toggles (this);
                }
            });
            console_revealer.notify["child-revealed"].connect (() => {
                if (console_revealer.child_revealed && (pending_preview_uri != null || pending_preview_refresh)) {
                    schedule_deferred_preview_flush ();
                }
            });

            right_box.append (right_stack);
            console_revealer.set_child (right_box);

            apply_panel_position ();
            ai_settings_handler_id = Core.SettingsManager.get_default ().ai_settings_changed.connect (apply_panel_position);

            this.append (paned);
            this.append (rstudio_dock_grid);

            // Mount initial layout based on FormatProfile
            var initial_profile = Core.FormatProfile.for_format (get_document_format ());
            var initial_mode = initial_profile.default_rstudio_layout
                ? Services.LayoutMode.RSTUDIO
                : Services.LayoutMode.APOSTROPHE;
            set_workbench_mode (initial_mode);

            refresh_live_preview ();

            source_buffer.changed.connect (() => {
                if (update_debounce_id != 0) {
                    GLib.Source.remove (update_debounce_id);
                    update_debounce_id = 0;
                }
                update_debounce_id = GLib.Timeout.add (250, () => {
                    update_debounce_id = 0;
                    string doc_text = get_clean_source_text ();
                    emit_buffer_stats (doc_text);
                    refresh_live_preview (doc_text);
                    panel_registry.refresh_environment_and_outline (doc_text);

                    if (!source_buffer.get_modified ()) {
                        return GLib.Source.REMOVE;
                    }

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
            if (preview_backend_handler_id != 0) {
                Core.SettingsManager.get_default ().disconnect (preview_backend_handler_id);
                preview_backend_handler_id = 0;
            }
            if (rstudio_dock_grid != null && rstudio_dock_grid.dock_manager != null) {
                rstudio_dock_grid.dock_manager.close_all_undocked ();
            }
            if (panel_registry != null) {
                panel_registry.cleanup ();
            }
            if (update_debounce_id != 0) {
                GLib.Source.remove (update_debounce_id);
                update_debounce_id = 0;
            }
            if (deferred_flush_id != 0) {
                GLib.Source.remove (deferred_flush_id);
                deferred_flush_id = 0;
            }
            deferred_flush_attempts = 0;
            if (layout_idle_id != 0) {
                GLib.Source.remove (layout_idle_id);
                layout_idle_id = 0;
            }
            if (scroll_sync_debounce_id != 0) {
                GLib.Source.remove (scroll_sync_debounce_id);
                scroll_sync_debounce_id = 0;
            }
            if (assistant_panel != null) {
                assistant_panel.cleanup ();
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
                        var chunk = Core.ChunkParser.find_chunk_at_line (get_clean_source_text (), iter.get_line ());
                        if (chunk != null) {
                            panel_registry.execute_active_cell_and_advance ();
                            return true;
                        }
                    }
                } else if ((state & Gdk.ModifierType.ALT_MASK) != 0 &&
                           (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) == 0 &&
                           (keyval == Gdk.Key.minus || keyval == Gdk.Key.KP_Subtract)) {
                    source_buffer.begin_user_action ();
                    source_buffer.delete_selection (true, true);
                    source_buffer.insert_at_cursor (" <- ", -1);
                    source_buffer.end_user_action ();
                    return true;
                } else if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                           (state & Gdk.ModifierType.SHIFT_MASK) != 0 &&
                           (state & Gdk.ModifierType.ALT_MASK) == 0 &&
                           (keyval == Gdk.Key.m || keyval == Gdk.Key.M)) {
                    source_buffer.begin_user_action ();
                    source_buffer.delete_selection (true, true);
                    source_buffer.insert_at_cursor (" |> ", -1);
                    source_buffer.end_user_action ();
                    return true;
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

                var profile = Core.FormatProfile.for_format (get_document_format ());
                panel_registry.notebook_cell_toolbar.visible = profile.supports_chunks;
                source_view.left_margin = 28;
                source_view.right_margin = 28;

                rstudio_dock_grid.refresh_dock_layout ();
            }
            refresh_pending_preview_if_visible ();
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
            var fmt = DocumentFormat.from_filename (title);
            string safe_title = title.replace ("\"", "\\\"");
            string content = "";

            if (fmt == DocumentFormat.QMD || lang_id == "quarto") {
                content = """---
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
""".printf (safe_title);
            } else if (fmt == DocumentFormat.RMD || lang_id == "rmd") {
                content = """---
title: "%s"
output:
  html_document: default
  pdf_document: default
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo = TRUE)
```

# Analysis

Write your R Markdown report here.

```{r}
summary(cars)
```
""".printf (safe_title);
            } else if (fmt == DocumentFormat.MD && lang_id == "markdown") {
                content = """# %s

Start writing in **Markdown**.

- Clean prose without computational chunks
- Supports inline math ($E = mc^2$) and diagrams
- Export to HTML, PDF, ODT, or RTF
""".printf (title);
            } else if (fmt == DocumentFormat.TEX || lang_id == "latex" || lang_id == "tex") {
                content = """\documentclass[11pt]{article}
\usepackage[utf8]{inputenc}
\usepackage{amsmath,amssymb,mhchem,graphicx}

\title{%s}
\author{%s}
\date{\today}

\begin{document}
\maketitle

\section{Introduction}
Write your LaTeX manuscript here. Inline math $\alpha + \beta = \gamma$ and chemistry $\ce{H2O}$.

\begin{equation}
  \int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
\end{equation}

\end{document}
""".printf (title, GLib.Environment.get_real_name ());
            } else if (fmt == DocumentFormat.TS || lang_id == "typescript") {
                content = """// Imladris TypeScript Module
export interface DataPoint {
  id: number;
  label: string;
  value: number;
}

export function summarize(points: DataPoint[]): number {
  return points.reduce((acc, item) => acc + item.value, 0);
}

console.log("Total:", summarize([{ id: 1, label: "A", value: 42 }]));
""";
            } else if (fmt == DocumentFormat.RSCRIPT || lang_id == "r") {
                content = """# Imladris R Script Session
# Author: %s
summary(mtcars[, 1:4])
""".printf (GLib.Environment.get_real_name ());
            } else if (fmt == DocumentFormat.PYSCRIPT || lang_id == "python3") {
                content = """#!/usr/bin/env python3
# Imladris Python Script Session
import sys
print("Python Interpreter:", sys.version.split()[0])
""";
            } else if (fmt == DocumentFormat.CSS || lang_id == "css") {
                content = """/* Imladris Stylesheet */
:root {
  --accent: #3584e4;
}

body {
  font-family: system-ui, sans-serif;
  line-height: 1.6;
}
""";
            } else if (fmt == DocumentFormat.BIB || lang_id == "bibtex") {
                content = """@article{example2026,
  author  = {Author, First and Collaborator, Second},
  title   = {Reproducible Scientific Authoring in Imladris},
  journal = {Journal of Open Science},
  year    = {2026},
  volume  = {1},
  pages   = {1--10}
}
""";
            } else if (fmt == DocumentFormat.RTF || lang_id == "rtf") {
                content = """{\rtf1\ansi\ansicpg1252\deff0\nouicompat
{\fonttbl{\f0\fnil\fcharset0 Sans;}}
\viewkind4\uc1\pard\ql\sa120\sl276\slmult1\f0\fs24
\b\fs32 Untitled Rich Text Document\b0\fs24\par
Start writing formatted text here.\par
}
""";
            } else if (fmt == DocumentFormat.HTML || lang_id == "html") {
                content = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="color-scheme" content="light dark">
  <title>Imladris Live HTML Document</title>
  <style>
    :root { color-scheme: light dark; }
    body { font-family: system-ui, sans-serif; padding: 2rem; line-height: 1.6; }
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
            set_initial_content (content, true);
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
            // Guard calls triggered during early construction (e.g. populate_starter_template)
            if (web_view == null || console_revealer == null || right_stack == null) {
                pending_preview_refresh = true;
                return;
            }
            bool is_layout_hidden = (current_layout_mode == Services.LayoutMode.APOSTROPHE &&
                (!console_revealer.reveal_child || right_stack.visible_child_name != "preview"));
            var pb = Core.SettingsManager.get_default ().preview_backend;
            if (pb != Core.PreviewBackend.WEBKIT_HTML) {
                if (is_layout_hidden) {
                    pending_preview_refresh = true;
                    return;
                }
                pending_preview_refresh = false;
                pending_preview_uri = null;
                active_custom_uri = null;
                string raw_native = preloaded_text != null ? preloaded_text : get_clean_source_text ();
                string? src_fp = file_location != null ? file_location.get_path () : null;
                native_preview.render (raw_native, get_document_format (), pb, src_fp);
                return;
            }
            bool is_unallocated = !web_view.get_mapped () ||
                web_view.get_width () <= 0 ||
                web_view.get_height () <= 0;
            if (is_layout_hidden || is_unallocated) {
                pending_preview_refresh = true;
                if (!is_layout_hidden && web_view.get_mapped ()) {
                    schedule_deferred_preview_flush ();
                }
                return;
            }
            pending_preview_refresh = false;
            pending_preview_uri = null;
            active_custom_uri = null;

            string raw = preloaded_text != null ? preloaded_text : get_clean_source_text ();
            string? base_uri = null;
            if (file_location != null) {
                var parent = file_location.get_parent ();
                base_uri = parent != null ? parent.get_uri () + "/" : file_location.get_uri ();
            } else {
                string cwd = GLib.Environment.get_current_dir ();
                if (cwd != null && cwd.length > 0) {
                    base_uri = GLib.File.new_for_path (cwd).get_uri () + "/";
                } else {
                    base_uri = "file://localhost/";
                }
            }

            var fmt = get_document_format ();
            if (doc_type == "html" || fmt == DocumentFormat.HTML) {
                load_html_preserving_scroll (Adapters.DocumentAdapter.render_html_with_latex (raw), base_uri);
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

            load_html_preserving_scroll (html, base_uri);
        }

        private void schedule_deferred_preview_flush () {
            if (deferred_flush_id != 0) {
                return;
            }
            deferred_flush_id = GLib.Idle.add (() => {
                if (!web_view.get_mapped ()) {
                    deferred_flush_id = 0;
                    deferred_flush_attempts = 0;
                    return GLib.Source.REMOVE;
                }
                if (web_view.get_width () <= 0 || web_view.get_height () <= 0) {
                    deferred_flush_attempts++;
                    if (deferred_flush_attempts >= 12) {
                        deferred_flush_id = 0;
                        deferred_flush_attempts = 0;
                        return GLib.Source.REMOVE;
                    }
                    deferred_flush_id = GLib.Timeout.add (40, () => {
                        deferred_flush_id = 0;
                        if (web_view.get_mapped () && (pending_preview_uri != null || pending_preview_refresh)) {
                            refresh_pending_preview_if_visible ();
                        }
                        return GLib.Source.REMOVE;
                    });
                    return GLib.Source.REMOVE;
                }
                deferred_flush_id = 0;
                deferred_flush_attempts = 0;
                refresh_pending_preview_if_visible ();
                return GLib.Source.REMOVE;
            });
        }

        private void refresh_pending_preview_if_visible () {
            if (!pending_preview_refresh && pending_preview_uri == null) {
                return;
            }
            if (current_layout_mode == Services.LayoutMode.APOSTROPHE &&
                (!console_revealer.reveal_child || right_stack.visible_child_name != "preview")) {
                return;
            }
            var pb = Core.SettingsManager.get_default ().preview_backend;
            if (pb != Core.PreviewBackend.WEBKIT_HTML) {
                if (!native_preview.get_mapped ()) {
                    return;
                }
                pending_preview_refresh = false;
                pending_preview_uri = null;
                refresh_live_preview ();
                return;
            }
            if (!web_view.get_mapped ()) {
                return;
            }
            if (web_view.get_width () <= 0 || web_view.get_height () <= 0) {
                schedule_deferred_preview_flush ();
                return;
            }
            deferred_flush_attempts = 0;
            if (pending_preview_uri != null) {
                string target_uri = pending_preview_uri;
                pending_preview_uri = null;
                pending_preview_refresh = false;
                active_custom_uri = target_uri;
                preview_load_generation++;
                web_view.load_uri (target_uri);
                return;
            }
            refresh_live_preview ();
        }

        private void schedule_preview_scroll_sync () {
            if (!is_live_preview_sync_active ()) {
                return;
            }
            if (scroll_sync_debounce_id != 0) {
                GLib.Source.remove (scroll_sync_debounce_id);
            }
            scroll_sync_debounce_id = GLib.Timeout.add (40, () => {
                scroll_sync_debounce_id = 0;
                sync_preview_scroll_proportional ();
                return GLib.Source.REMOVE;
            });
        }

        private bool is_live_preview_sync_active () {
            if (active_custom_uri != null || !has_loaded_preview || web_view.is_loading || !web_view.get_mapped ()) {
                return false;
            }
            if (web_view.get_width () <= 0 || web_view.get_height () <= 0) {
                return false;
            }
            if (current_layout_mode == Services.LayoutMode.APOSTROPHE) {
                return console_revealer.visible && console_revealer.reveal_child && right_stack.visible_child_name == "preview";
            }
            return true;
        }

        private void sync_preview_scroll_proportional () {
            if (!is_live_preview_sync_active ()) {
                return;
            }
            var vadj = (rtf_editor != null) ? rtf_editor.scroller.vadjustment : editor_scroller.vadjustment;
            double max_scroll = vadj.upper - vadj.page_size;
            double ratio = 0.0;
            if (max_scroll > 1.0) {
                ratio = (vadj.value / max_scroll).clamp (0.0, 1.0);
            }
            char buf[double.DTOSTR_BUF_SIZE];
            string ratio_str = ratio.format (buf, "%.6f");
            string js = @"(function(){ var max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight); var target = Math.round(max * $ratio_str); window.scrollTo({ top: target, behavior: 'smooth' }); })();";
            web_view.evaluate_javascript.begin (js, -1, null, null, null);
        }

        private void load_html_preserving_scroll (string html, string base_uri) {
            if (web_view.is_loading) {
                // Apostrophe-style queueing: let the current load finish, then load the latest edit
                queued_preview_html = html;
                queued_preview_base_uri = base_uri;
                return;
            }
            queued_preview_html = null;
            queued_preview_base_uri = null;
            uint64 gen = ++preview_load_generation;
            if (!has_loaded_preview || !web_view.get_mapped ()) {
                web_view.load_html (html, base_uri);
                return;
            }
            // Capture visible snapshot (Apostrophe pattern) to eliminate white flash during reload
            if (web_view.get_estimated_load_progress () >= 1.0) {
                web_view.get_snapshot.begin (
                    WebKit.SnapshotRegion.VISIBLE,
                    WebKit.SnapshotOptions.NONE,
                    null,
                    (s_obj, s_res) => {
                        try {
                            var tex = web_view.get_snapshot.end (s_res);
                            if (tex != null) {
                                webview_snapshot.set_paintable (tex);
                                has_webview_snapshot = true;
                            }
                        } catch (GLib.Error e) {
                            // Non-fatal: continue without snapshot overlay
                        }
                    }
                );
            }
            web_view.evaluate_javascript.begin ("window.scrollY || 0", -1, null, null, null, (obj, res) => {
                try {
                    var js_val = web_view.evaluate_javascript.end (res);
                    if (js_val != null && js_val.is_number ()) {
                        last_preview_scroll_y = js_val.to_double ();
                    }
                } catch (GLib.Error e) {}
                if (gen != preview_load_generation) {
                    return;
                }
                web_view.load_html (html, base_uri);
            });
        }

        public void set_split_orientation (Services.SplitMode split, bool force_activate_preview = false) {
            preferred_split_mode = split;
            if (current_layout_mode == Services.LayoutMode.RSTUDIO) {
                if (force_activate_preview) {
                    dock_layout_state.activate_panel (PanelId.LIVE_PREVIEW);
                }
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
                        if (layout_idle_id != 0) GLib.Source.remove (layout_idle_id);
                        layout_idle_id = GLib.Idle.add (() => {
                            layout_idle_id = 0;
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
                        if (layout_idle_id != 0) GLib.Source.remove (layout_idle_id);
                        layout_idle_id = GLib.Idle.add (() => {
                            layout_idle_id = 0;
                            int cur_w = paned.get_width ();
                            if (cur_w > 100) paned.set_position (cur_w / 2);
                            return GLib.Source.REMOVE;
                        });
                    }
                    break;
            }
            refresh_pending_preview_if_visible ();
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
                var pb = Core.SettingsManager.get_default ().preview_backend;
                if (pb != Core.PreviewBackend.WEBKIT_HTML) {
                    active_custom_uri = null;
                    pending_preview_uri = null;
                    string? local_path = null;
                    try {
                        local_path = GLib.Filename.from_uri (uri);
                    } catch (GLib.Error e) {}
                    native_preview.render (get_clean_source_text (), get_document_format (), pb, local_path);
                    return;
                }
                active_custom_uri = uri;
                if (web_view.get_mapped () && web_view.get_width () > 0 && web_view.get_height () > 0) {
                    pending_preview_uri = null;
                    pending_preview_refresh = false;
                    preview_load_generation++;
                    web_view.load_uri (uri);
                } else {
                    pending_preview_uri = uri;
                    pending_preview_refresh = false;
                    if (web_view.get_mapped ()) {
                        schedule_deferred_preview_flush ();
                    }
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
            if (current_layout_mode == Services.LayoutMode.RSTUDIO &&
                panel_registry != null &&
                panel_registry.elrond_chat_panel != null) {
                dock_layout_state.activate_panel (Imladris.Core.Layout.PanelId.ELROND_AI);
                panel_registry.elrond_chat_panel.focus_input ();
                return;
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
            completion.page_size = 10;

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
            Gtk.TextBuffer buf = (rtf_editor != null) ? rtf_editor.buffer : (Gtk.TextBuffer) source_buffer;
            Gtk.TextIter start, end;
            if (buf.get_selection_bounds (out start, out end)) {
                return buf.get_text (start, end, false);
            }
            return "";
        }

        public void insert_ai_code_at_cursor (string code) {
            string cleaned = code.strip ();
            Gtk.TextBuffer buf = (rtf_editor != null) ? rtf_editor.buffer : (Gtk.TextBuffer) source_buffer;
            buf.begin_user_action ();
            Gtk.TextIter start, end;
            if (buf.get_selection_bounds (out start, out end)) {
                buf.delete (ref start, ref end);
                buf.insert (ref start, cleaned, -1);
            } else {
                buf.insert_at_cursor ("\n" + cleaned + "\n", -1);
            }
            buf.end_user_action ();
        }

        public void insert_media_snippet (string snippet) {
            Gtk.TextBuffer buf = (rtf_editor != null) ? rtf_editor.buffer : (Gtk.TextBuffer) source_buffer;
            buf.begin_user_action ();
            Gtk.TextIter start, end;
            if (buf.get_selection_bounds (out start, out end)) {
                buf.delete (ref start, ref end);
                buf.insert (ref start, snippet, -1);
            } else {
                buf.insert_at_cursor (snippet, -1);
            }
            buf.end_user_action ();
            refresh_live_preview ();
        }

        public void apply_tag_or_syntax (string tag_name, string md_wrapper) {
            if (rtf_editor != null) {
                rtf_editor.toggle_named_style (tag_name);
                return;
            }
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

        public void show_table_picker_popover () {
            Gtk.TextView target_view = (rtf_editor != null) ? rtf_editor.text_view : (Gtk.TextView) source_view;
            Gtk.TextBuffer target_buf = target_view.buffer;

            var popover = PopoverFactory.create_table_picker_popover ((rows, cols) => {
                insert_markdown_table (rows, cols);
            });
            popover.set_parent (target_view);

            Gtk.TextIter iter;
            target_buf.get_iter_at_mark (out iter, target_buf.get_insert ());
            Gdk.Rectangle buf_rect;
            target_view.get_iter_location (iter, out buf_rect);
            int wx, wy;
            target_view.buffer_to_window_coords (Gtk.TextWindowType.WIDGET, buf_rect.x, buf_rect.y, out wx, out wy);
            int vw = target_view.get_width ();
            int vh = target_view.get_height ();
            if (vw > 0 && vh > 0) {
                Gdk.Rectangle anchor = {
                    wx.clamp (0, vw - 1),
                    wy.clamp (0, vh - 1),
                    1,
                    buf_rect.height > 0 ? buf_rect.height : 16
                };
                popover.set_pointing_to (anchor);
            }

            unowned Gtk.TextView unowned_target = target_view;
            popover.closed.connect ((p) => {
                p.unparent ();
                unowned_target.grab_focus ();
            });
            popover.popup ();
        }

        public void insert_markdown_table (int rows, int cols) {
            int safe_rows = rows.clamp (1, 100);
            int safe_cols = cols.clamp (1, 30);

            if (rtf_editor != null) {
                var sb = new GLib.StringBuilder ("\n");
                for (int c = 1; c <= safe_cols; c++) {
                    if (c > 1) sb.append ("\t");
                    sb.append (@"Header $c");
                }
                for (int r = 1; r <= safe_rows; r++) {
                    sb.append ("\n");
                    for (int c = 1; c <= safe_cols; c++) {
                        if (c > 1) sb.append ("\t");
                        sb.append ("Cell");
                    }
                }
                sb.append ("\n");
                rtf_editor.buffer.begin_user_action ();
                rtf_editor.buffer.insert_at_cursor (sb.str, -1);
                rtf_editor.buffer.end_user_action ();
                return;
            }

            var fmt = get_document_format ();
            var sb = new GLib.StringBuilder ();
            if (fmt == DocumentFormat.HTML) {
                sb.append ("\n<table>\n  <thead>\n    <tr>");
                for (int c = 1; c <= safe_cols; c++) {
                    sb.append (@"<th>Header $c</th>");
                }
                sb.append ("</tr>\n  </thead>\n  <tbody>\n");
                for (int r = 1; r <= safe_rows; r++) {
                    sb.append ("    <tr>");
                    for (int c = 1; c <= safe_cols; c++) {
                        sb.append ("<td>Cell</td>");
                    }
                    sb.append ("</tr>\n");
                }
                sb.append ("  </tbody>\n</table>\n");
            } else if (fmt == DocumentFormat.TEX) {
                string col_spec = "|";
                for (int c = 1; c <= safe_cols; c++) {
                    col_spec += "l|";
                }
                sb.append ("\n\\begin{table}[htbp]\n  \\centering\n");
                sb.append (@"  \\begin{tabular}{$col_spec}\n    \\hline\n    ");
                for (int c = 1; c <= safe_cols; c++) {
                    if (c > 1) sb.append (" & ");
                    sb.append (@"\\textbf{Header $c}");
                }
                sb.append (" \\\\\n    \\hline\n");
                for (int r = 1; r <= safe_rows; r++) {
                    sb.append ("    ");
                    for (int c = 1; c <= safe_cols; c++) {
                        if (c > 1) sb.append (" & ");
                        sb.append ("Cell");
                    }
                    sb.append (" \\\\\n");
                }
                sb.append ("    \\hline\n  \\end{tabular}\n  \\caption{Table caption}\n\\end{table}\n");
            } else {
                sb.append ("\n|");
                for (int c = 1; c <= safe_cols; c++) sb.append (@" Header $c |");
                sb.append ("\n|");
                for (int c = 1; c <= safe_cols; c++) sb.append (" --- |");
                for (int r = 1; r <= safe_rows; r++) {
                    sb.append ("\n|");
                    for (int c = 1; c <= safe_cols; c++) sb.append (" Cell |");
                }
                sb.append ("\n");
            }

            source_buffer.begin_user_action ();
            source_buffer.insert_at_cursor (sb.str, -1);
            source_buffer.end_user_action ();
            refresh_live_preview ();
        }

        public void append_console_log (string text, bool focus_console = false) {
            if (focus_console && current_layout_mode == Services.LayoutMode.RSTUDIO) {
                var q2 = dock_layout_state.quadrants[QuadrantId.Q2_BOTTOM_LEFT];
                if (q2 != null && q2.active_tab != PanelId.CONSOLE) {
                    dock_layout_state.activate_tab (QuadrantId.Q2_BOTTOM_LEFT, PanelId.CONSOLE);
                }
            }
            Gtk.TextIter end;
            console_view.buffer.get_end_iter (out end);
            console_view.buffer.insert (ref end, text + "\n", -1);
        }

        public void emit_buffer_stats (string? preloaded_text = null) {
            string txt = (rtf_editor != null)
                ? rtf_editor.get_plain_text ()
                : (preloaded_text != null ? preloaded_text : get_clean_source_text ());
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
            int lines = (rtf_editor != null) ? rtf_editor.buffer.get_line_count () : source_buffer.get_line_count ();
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
            Gtk.TextBuffer buf = (rtf_editor != null) ? rtf_editor.buffer : (Gtk.TextBuffer) source_buffer;
            if (buf.can_undo) {
                buf.undo ();
            }
        }

        public void redo () {
            Gtk.TextBuffer buf = (rtf_editor != null) ? rtf_editor.buffer : (Gtk.TextBuffer) source_buffer;
            if (buf.can_redo) {
                buf.redo ();
            }
        }

        public void set_zoom (int percent) {
            web_view.zoom_level = (double) percent / 100.0;
            native_preview.set_zoom_percent (percent);
            if (Core.SettingsManager.get_default ().preview_backend != Core.PreviewBackend.WEBKIT_HTML) {
                refresh_live_preview ();
            }
        }

        public void apply_heading (int level) {
            if (level <= 0) return;
            if (rtf_editor != null) {
                int pt = (level == 1) ? 20 : ((level == 2) ? 16 : 14);
                rtf_editor.apply_heading_style (pt);
                return;
            }
            string prefix = string.nfill (level, '#') + " ";
            Gtk.TextIter insert_iter;
            source_buffer.get_iter_at_mark (out insert_iter, source_buffer.get_insert ());
            insert_iter.set_line_offset (0);
            source_buffer.insert (ref insert_iter, prefix, -1);
        }

        public void insert_list_item (string prefix) {
            if (rtf_editor != null) {
                Gtk.TextIter it;
                rtf_editor.buffer.get_iter_at_mark (out it, rtf_editor.buffer.get_insert ());
                it.set_line_offset (0);
                string rtf_prefix = prefix.has_prefix ("- ") ? "• " : prefix;
                rtf_editor.buffer.insert (ref it, rtf_prefix, -1);
                return;
            }
            Gtk.TextIter insert_iter;
            source_buffer.get_iter_at_mark (out insert_iter, source_buffer.get_insert ());
            insert_iter.set_line_offset (0);
            source_buffer.insert (ref insert_iter, prefix, -1);
        }
    }
}
