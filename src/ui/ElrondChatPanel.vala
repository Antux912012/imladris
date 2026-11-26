// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.AI;

namespace Imladris.UI {

    public class ElrondChatSession : GLib.Object {
        public string title { owned get; set; default = "New Chat"; }
        public Gee.ArrayList<ElrondChatTurn> turns { get; private set; }

        public ElrondChatSession (string title = "New Chat") {
            this.title = title;
            this.turns = new Gee.ArrayList<ElrondChatTurn> ();
        }
    }

    /**
     * ElrondChatPanel
     *
     * Native GTK4 / Libadwaita Elrond AI Side Panel with Adw.ToolbarView root,
     * searchable session popover, Adw.StatusPage empty state, smart auto-scroll,
     * tactile ElrondComposer, throttled 30ms streaming Markdown, collapsible
     * reasoning row, and native GtkSource.View code blocks.
     */
    public class ElrondChatPanel : Adw.Bin {

        private static bool css_loaded = false;
        private static GLib.Regex? cached_bold_rx = null;
        private static GLib.Regex? cached_code_rx = null;

        private Adw.ToolbarView toolbar_view;
        private Gtk.MenuButton session_btn;
        private Gtk.SearchEntry session_search;
        private Gtk.ListBox session_list;
        private Gtk.Popover session_popover;

        private Gtk.Stack content_stack;
        private Gtk.ScrolledWindow scroller;
        private Gtk.Box message_list;
        private Gtk.Button scroll_bottom_btn;
        private ElrondComposer composer;

        private unowned DocumentPage doc_page;
        private unowned PersistentPanelRegistry panel_reg;
        private unowned Window? parent_window;

        private Cancellable? cancellable = null;
        private Gee.ArrayList<ElrondChatSession> sessions = new Gee.ArrayList<ElrondChatSession> ();
        private ElrondChatSession active_session;
        private bool is_busy = false;
        private bool auto_scroll_paused = false;
        private uint scroll_idle_id = 0;
        private uint stream_throttle_id = 0;

        public override void dispose () {
            if (scroll_idle_id != 0) {
                GLib.Source.remove (scroll_idle_id);
                scroll_idle_id = 0;
            }
            if (stream_throttle_id != 0) {
                GLib.Source.remove (stream_throttle_id);
                stream_throttle_id = 0;
            }
            if (cancellable != null) {
                cancellable.cancel ();
                cancellable = null;
            }
            base.dispose ();
        }

        public ElrondChatPanel (DocumentPage page, PersistentPanelRegistry reg, Window? win) {
            this.doc_page = page;
            this.panel_reg = reg;
            this.parent_window = win;
            this.hexpand = true;
            this.vexpand = true;
            this.add_css_class ("elrond-chat-panel");

            ensure_css_loaded ();

            active_session = new ElrondChatSession ("Current Session");
            sessions.add (active_session);

            toolbar_view = new Adw.ToolbarView ();
            toolbar_view.add_top_bar (build_top_bar ());
            toolbar_view.set_content (build_center_stack ());

            composer = new ElrondComposer ();
            composer.attach_context (new ElrondContextItem (
                ElrondContextKind.ACTIVE_FILE, "active-file", "Active Document"
            ));
            composer.attach_context (new ElrondContextItem (
                ElrondContextKind.ACTIVE_SELECTION, "selection", "Active Selection"
            ));
            composer.send_requested.connect ((text) => {
                submit_prompt_async.begin (text);
            });
            composer.stop_requested.connect (() => {
                if (cancellable != null && !cancellable.is_cancelled ()) {
                    cancellable.cancel ();
                }
            });
            composer.open_settings_requested.connect (open_ai_settings);
            composer.context_changed.connect (refresh_context_meter);

            toolbar_view.add_bottom_bar (composer);
            this.set_child (toolbar_view);

            refresh_context_meter ();
        }

        private static void ensure_css_loaded () {
            if (css_loaded) return;
            css_loaded = true;
            var display = Gdk.Display.get_default ();
            if (display == null) return;
            var provider = new Gtk.CssProvider ();
            provider.load_from_resource ("/org/imladris/app/elrond-chat.css");
            Core.SettingsManager.add_css_provider_for_display (
                display,
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        private Adw.HeaderBar build_top_bar () {
            var header = new Adw.HeaderBar () {
                show_end_title_buttons = false,
                show_start_title_buttons = false
            };
            header.add_css_class ("flat");

            // Left: Searchable Session Title Dropdown
            session_popover = new Gtk.Popover ();
            var pop_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8,
                width_request = 240
            };
            session_search = new Gtk.SearchEntry () {
                placeholder_text = "Search sessions…"
            };
            session_search.search_changed.connect (rebuild_session_list);
            pop_box.append (session_search);

            session_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                css_classes = { "boxed-list" }
            };
            var pop_scroll = new Gtk.ScrolledWindow () {
                child = session_list,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                max_content_height = 220,
                propagate_natural_height = true
            };
            pop_box.append (pop_scroll);
            session_popover.set_child (pop_box);

            session_btn = new Gtk.MenuButton () {
                label = active_session.title,
                popover = session_popover,
                css_classes = { "flat" },
                tooltip_text = "Switch chat session"
            };
            header.pack_start (session_btn);

            // Right: New Chat + Elrond Settings
            var btn_new = new Gtk.Button.from_icon_name ("list-add-symbolic") {
                tooltip_text = "New Chat",
                css_classes = { "flat" }
            };
            btn_new.clicked.connect (start_new_chat);
            header.pack_end (btn_new);

            var btn_settings = new Gtk.Button.from_icon_name ("emblem-system-symbolic") {
                tooltip_text = "Elrond Settings",
                css_classes = { "flat" }
            };
            btn_settings.clicked.connect (open_ai_settings);
            header.pack_end (btn_settings);

            rebuild_session_list ();
            return header;
        }

        private Gtk.Stack build_center_stack () {
            content_stack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                transition_duration = 150,
                hexpand = true,
                vexpand = true
            };

            // Page 1: Empty State (Adw.StatusPage)
            var status_page = new Adw.StatusPage () {
                icon_name = "ai-elrond",
                title = "Elrond AI",
                description = "Zero-configuration scientific copilot for R, Python, and Quarto"
            };

            var starters_box = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                row_spacing = 8,
                column_spacing = 8,
                halign = Gtk.Align.CENTER,
                max_children_per_line = 3
            };
            string[] starters = {
                "Explain Selection",
                "Debug Active Chunk",
                "Improve Quarto Prose"
            };
            foreach (string s in starters) {
                string prompt_text = s;
                var pill = new Gtk.Button.with_label (prompt_text) {
                    css_classes = { "pill" }
                };
                pill.clicked.connect (() => {
                    if (prompt_text == "Explain Selection") {
                        composer.attach_context (new ElrondContextItem (
                            ElrondContextKind.ACTIVE_SELECTION, "selection", "Active Selection"
                        ));
                    } else if (prompt_text == "Debug Active Chunk") {
                        composer.attach_context (new ElrondContextItem (
                            ElrondContextKind.LAST_ERROR, "last-error", "Last Console Error"
                        ));
                    }
                    submit_external_prompt (prompt_text);
                });
                starters_box.append (pill);
            }
            status_page.set_child (starters_box);
            content_stack.add_named (status_page, "empty");

            // Page 2: Chat Stream + Smart Auto-Scroll Overlay
            var overlay = new Gtk.Overlay ();

            message_list = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
                margin_top = 16,
                margin_bottom = 16,
                margin_start = 16,
                margin_end = 16,
                hexpand = true
            };

            scroller = new Gtk.ScrolledWindow () {
                child = message_list,
                hexpand = true,
                vexpand = true,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
            };
            var vadj = scroller.get_vadjustment ();
            if (vadj != null) {
                vadj.value_changed.connect (() => {
                    double dist_from_bottom = vadj.get_upper () - (vadj.get_value () + vadj.get_page_size ());
                    if (dist_from_bottom > 40.0) {
                        auto_scroll_paused = true;
                        scroll_bottom_btn.visible = true;
                    } else {
                        auto_scroll_paused = false;
                        scroll_bottom_btn.visible = false;
                    }
                });
            }
            overlay.set_child (scroller);

            scroll_bottom_btn = new Gtk.Button.from_icon_name ("go-down-symbolic") {
                tooltip_text = "Scroll to bottom",
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.END,
                margin_bottom = 12,
                visible = false,
                css_classes = { "pill", "elrond-scroll-pill" }
            };
            scroll_bottom_btn.clicked.connect (() => {
                auto_scroll_paused = false;
                scroll_bottom_btn.visible = false;
                scroll_to_bottom (true);
            });
            overlay.add_overlay (scroll_bottom_btn);

            content_stack.add_named (overlay, "chat");
            content_stack.set_visible_child_name ("empty");
            return content_stack;
        }

        private void rebuild_session_list () {
            if (session_list == null) return;
            Gtk.Widget? child = session_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                session_list.remove (child);
                child = next;
            }

            string q = session_search != null ? session_search.text.strip ().down () : "";
            foreach (var sess in sessions) {
                if (q.length > 0 && !sess.title.down ().contains (q)) {
                    continue;
                }
                var row_btn = new Gtk.Button.with_label (sess.title) {
                    css_classes = { "flat" },
                    halign = Gtk.Align.FILL
                };
                ElrondChatSession target_sess = sess;
                row_btn.clicked.connect (() => {
                    switch_to_session (target_sess);
                    session_popover.popdown ();
                });
                session_list.append (row_btn);
            }
        }

        private void switch_to_session (ElrondChatSession sess) {
            active_session = sess;
            session_btn.label = sess.title;
            clear_message_widgets ();

            if (sess.turns.size == 0) {
                content_stack.set_visible_child_name ("empty");
                return;
            }

            content_stack.set_visible_child_name ("chat");
            ensure_inline_regexes ();
            foreach (var turn in sess.turns) {
                if (turn.role == "user") {
                    append_user_widget (turn.content);
                } else {
                    var am = append_assistant_widget ("Done", "");
                    am.finish_response (turn.content, cached_code_rx, cached_bold_rx);
                }
            }
            scroll_to_bottom (true);
        }

        private void start_new_chat () {
            if (is_busy && cancellable != null) {
                cancellable.cancel ();
            }
            active_session = new ElrondChatSession (@"Session $(sessions.size + 1)");
            sessions.insert (0, active_session);
            session_btn.label = active_session.title;
            clear_message_widgets ();
            content_stack.set_visible_child_name ("empty");
            rebuild_session_list ();
            refresh_context_meter ();
        }

        public void clear_chat_history () {
            start_new_chat ();
        }

        private void clear_message_widgets () {
            Gtk.Widget? child = message_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                message_list.remove (child);
                child = next;
            }
        }

        private void open_ai_settings () {
            if (parent_window != null) {
                var dlg = new AiSettingsDialog ();
                dlg.closed.connect (() => {
                    composer.refresh_model_pill ();
                });
                dlg.present (parent_window);
            }
        }

        public void focus_input () {
            composer.focus_input ();
        }

        public void submit_external_prompt (string prompt) {
            if (is_busy || prompt.strip ().length == 0) return;
            submit_prompt_async.begin (prompt.strip ());
        }

        private void refresh_context_meter () {
            int chars = 0;
            if (composer.has_context_kind (ElrondContextKind.ACTIVE_SELECTION)) {
                chars += doc_page.get_selected_text ().length;
            }
            if (composer.has_context_kind (ElrondContextKind.ACTIVE_FILE)) {
                chars += int.min (4000, doc_page.get_clean_source_text ().length);
            }
            foreach (var t in active_session.turns) {
                chars += t.content.length;
            }
            composer.update_context_meter (chars, 16000);
        }

        private async void submit_prompt_async (string raw_prompt) {
            if (is_busy) return;
            string prompt = raw_prompt.strip ();
            if (prompt.length == 0) return;

            composer.set_text ("");
            content_stack.set_visible_child_name ("chat");

            if (active_session.turns.size == 0) {
                string short_title = prompt.length > 26 ? prompt.substring (0, 26) + "…" : prompt;
                active_session.title = short_title;
                session_btn.label = short_title;
                rebuild_session_list ();
            }

            append_user_widget (prompt);
            auto_scroll_paused = false;
            scroll_to_bottom (true);

            is_busy = true;
            composer.set_streaming (true);
            cancellable = new Cancellable ();

            string env_summary = "";
            string ctx_summary = "";
            string combined_prompt = assemble_context_prompt (prompt, out env_summary, out ctx_summary);
            string thinking_status = composer.has_context_kind (ElrondContextKind.ACTIVE_FILE)
                ? "Reading active document…" : "Thinking…";

            var assistant_msg = append_assistant_widget (thinking_status, ctx_summary);
            scroll_to_bottom (false);

            try {
                var controller = ElrondEngineController.get_default ();
                var cfg = Core.AiConfigManager.get_default ();
                var active_settings = cfg.get_settings_for (cfg.active_provider);
                bool has_cloud_or_local_api = !cfg.active_provider.requires_api_key () ||
                    (active_settings.api_key != null && active_settings.api_key.strip ().length > 0);
                bool has_failover_backup = cfg.auto_failover_enabled &&
                    cfg.get_free_fallback_candidates (cfg.active_provider).size > 0;

                if (!controller.is_ready && cfg.active_provider.is_free_tier () && !cfg.free_api_consent_accepted) {
                    bool accepted = yield ensure_free_api_consent_async ();
                    if (!accepted) {
                        ensure_inline_regexes ();
                        assistant_msg.finish_response (
                            "*Cancelled: Free-tier cloud AI consent was declined.*",
                            cached_code_rx, cached_bold_rx
                        );
                        return;
                    }
                }

                string response = "";
                if (controller.is_ready) {
                    var stream_sb = new StringBuilder ();
                    bool stream_dirty = false;

                    // Throttle UI updates during streaming to 30ms intervals
                    stream_throttle_id = GLib.Timeout.add (30, () => {
                        if (stream_dirty) {
                            stream_dirty = false;
                            assistant_msg.update_streaming_preview (stream_sb.str);
                            scroll_to_bottom (false);
                        }
                        return GLib.Source.CONTINUE;
                    });

                    try {
                        response = yield controller.write_with_elrond_stream_async (
                            doc_page.doc_type,
                            composer.has_context_kind (ElrondContextKind.ACTIVE_FILE)
                                ? doc_page.get_clean_source_text () : "",
                            env_summary,
                            combined_prompt,
                            active_session.turns,
                            (delta) => {
                                stream_sb.append (delta);
                                stream_dirty = true;
                            },
                            cancellable
                        );
                    } finally {
                        if (stream_throttle_id != 0) {
                            GLib.Source.remove (stream_throttle_id);
                            stream_throttle_id = 0;
                        }
                    }
                } else if (has_cloud_or_local_api || has_failover_backup) {
                    var ai_client = new AiClient ();
                    string sys_prompt = "You are Elrond AI, an expert scientific writing and data science copilot inside Imladris (R, Python, Quarto, LaTeX, Biostats). Give concise, accurate answers with fenced ```r or ```python code blocks when helpful.";
                    response = yield ai_client.send_chat_completion_async (sys_prompt, combined_prompt, cancellable);
                } else {
                    response = yield ElrondEngineController.run_agy_prompt_async (combined_prompt, cancellable);
                }

                ensure_inline_regexes ();
                assistant_msg.finish_response (response, cached_code_rx, cached_bold_rx);

                active_session.turns.add (new ElrondChatTurn ("user", prompt));
                active_session.turns.add (new ElrondChatTurn ("assistant", response));
                while (active_session.turns.size > 16) {
                    active_session.turns.remove_at (0);
                }
            } catch (GLib.Error e) {
                ensure_inline_regexes ();
                if (e is GLib.IOError.CANCELLED) {
                    assistant_msg.finish_response ("*Generation cancelled.*", cached_code_rx, cached_bold_rx);
                } else {
                    assistant_msg.finish_response (
                        @"⚠️ **Elrond Error:** $(e.message)\n\nPlease check your active AI provider or local server in **AI Settings**.",
                        cached_code_rx, cached_bold_rx
                    );
                }
            } finally {
                is_busy = false;
                composer.set_streaming (false);
                composer.refresh_model_pill ();
                refresh_context_meter ();
                scroll_to_bottom (false);
            }
        }

        private string assemble_context_prompt (string prompt, out string env_summary, out string ctx_summary) {
            env_summary = "";
            var context_sb = new GLib.StringBuilder ();
            var summary_parts = new Gee.ArrayList<string> ();

            if (composer.has_context_kind (ElrondContextKind.ACTIVE_SELECTION)) {
                string sel = doc_page.get_selected_text ().strip ();
                if (sel.length > 0) {
                    context_sb.append_printf ("[Selected Text / Code]:\n%s\n\n", sel);
                    summary_parts.add (@"Selection ($(sel.length) chars)");
                }
            }

            if (composer.has_context_kind (ElrondContextKind.ACTIVE_FILE)) {
                string doc_text = doc_page.get_clean_source_text ();
                if (doc_text.length > 6000) {
                    Gtk.TextIter cursor_iter;
                    doc_page.source_buffer.get_iter_at_mark (out cursor_iter, doc_page.source_buffer.get_insert ());
                    int cursor_line = cursor_iter.get_line ();
                    string[] all_lines = doc_text.split ("\n");
                    int start_l = int.max (0, cursor_line - 120);
                    int end_l = int.min (all_lines.length, cursor_line + 120);
                    var win_sb = new GLib.StringBuilder ();
                    if (start_l > 0) win_sb.append_printf ("... [lines 1-%d omitted] ...\n", start_l);
                    for (int li = start_l; li < end_l; li++) {
                        win_sb.append (all_lines[li]).append_c ('\n');
                    }
                    if (end_l < all_lines.length) win_sb.append_printf ("... [lines %d-%d omitted] ...", end_l + 1, all_lines.length);
                    doc_text = win_sb.str;
                    if (doc_text.length > 6000) {
                        doc_text = doc_text.substring (0, 6000) + "\n... [truncated]";
                    }
                }
                context_sb.append_printf ("[Active File Content (%s)]:\n%s\n\n", doc_page.doc_type, doc_text);
                summary_parts.add (@"Active $(doc_page.doc_type) document");
            }

            if (composer.has_context_kind (ElrondContextKind.DATAFRAMES) &&
                panel_reg != null && panel_reg.environment_controller != null) {
                var vars = panel_reg.environment_controller.get_cached_variables ();
                if (vars.size > 0) {
                    var sb_env = new GLib.StringBuilder ();
                    int count = 0;
                    foreach (var v in vars) {
                        if (count > 0) sb_env.append (", ");
                        string col_hint = (v.columns_csv != null && v.columns_csv.length > 0) ? @" cols=[$(v.columns_csv)]" : "";
                        sb_env.append (@"$(v.name) ($(v.var_type): $(v.dimensions)$col_hint)");
                        count++;
                        if (count >= 12) break;
                    }
                    env_summary = sb_env.str;
                    context_sb.append_printf ("[Active Environment Objects]:\n%s\n\n", env_summary);
                    summary_parts.add (@"$count environment object(s)");
                }
            }

            if (composer.has_context_kind (ElrondContextKind.LAST_ERROR)) {
                string console_text = doc_page.console_view.buffer.text;
                if (console_text.contains ("Error") || console_text.contains ("Traceback") || console_text.contains ("✖")) {
                    int start_idx = int.max (0, console_text.length - 1500);
                    while (start_idx > 0 && start_idx < console_text.length && (console_text[start_idx] & 0xC0) == 0x80) {
                        start_idx++;
                    }
                    context_sb.append_printf ("[Recent Console Output]:\n%s\n\n", console_text.substring (start_idx));
                    summary_parts.add ("Console error tail");
                }
            }

            ctx_summary = summary_parts.size > 0
                ? "Context: " + string.joinv (", ", summary_parts.to_array ())
                : "";
            return context_sb.str + "[User Query]:\n" + prompt;
        }

        private void append_user_widget (string text) {
            var msg = new ElrondUserMessage (text);
            msg.copy_requested.connect (copy_to_clipboard);
            msg.edit_requested.connect ((t) => {
                composer.set_text (t);
                composer.focus_input ();
            });
            message_list.append (msg);
        }

        private ElrondAssistantMessage append_assistant_widget (string thinking_status, string ctx_summary) {
            var msg = new ElrondAssistantMessage (thinking_status, ctx_summary);
            msg.copy_markdown_requested.connect (copy_to_clipboard);
            msg.copy_code_requested.connect (copy_to_clipboard);
            msg.insert_code_requested.connect (insert_code_at_cursor);
            msg.apply_code_requested.connect (apply_code_to_selection);
            msg.delete_requested.connect ((target) => {
                message_list.remove (target);
            });
            msg.regenerate_requested.connect (() => {
                if (!is_busy && active_session.turns.size >= 2) {
                    string last_user = active_session.turns.get (active_session.turns.size - 2).content;
                    submit_prompt_async.begin (last_user);
                }
            });
            message_list.append (msg);
            return msg;
        }

        private void copy_to_clipboard (string text) {
            var disp = Gdk.Display.get_default ();
            if (disp != null) {
                disp.get_clipboard ().set_text (text);
                if (parent_window != null) {
                    parent_window.show_toast ("Copied to clipboard");
                }
            }
        }

        private void insert_code_at_cursor (string code, string lang) {
            string to_insert = code;
            string lang_lower = lang.down ();
            string code_engine = "r";
            if (lang_lower == "python" || lang_lower == "py") {
                code_engine = "python";
            } else if (lang_lower == "bash" || lang_lower == "sh" || lang_lower == "zsh") {
                code_engine = "bash";
            }

            var fmt = doc_page.get_document_format ();
            if (fmt == DocumentFormat.QMD || fmt == DocumentFormat.RMD || fmt == DocumentFormat.IPYNB) {
                Gtk.TextIter cur_it;
                doc_page.source_buffer.get_iter_at_mark (out cur_it, doc_page.source_buffer.get_insert ());
                var chunk = Core.ChunkParser.find_chunk_at_line (doc_page.get_clean_source_text (), cur_it.get_line ());
                if (chunk == null && (code_engine == "r" || code_engine == "python" || code_engine == "bash")) {
                    to_insert = "\n```{" + code_engine + "}\n" + code.strip () + "\n```\n";
                }
            }
            doc_page.source_buffer.begin_user_action ();
            try {
                doc_page.source_buffer.insert_at_cursor (to_insert, -1);
            } finally {
                doc_page.source_buffer.end_user_action ();
            }
            if (parent_window != null) {
                parent_window.show_toast_with_action ("Inserted code at cursor", "Undo", "win.undo");
            }
        }

        private void apply_code_to_selection (string code) {
            if (!doc_page.source_buffer.has_selection) {
                if (parent_window != null) {
                    parent_window.show_toast ("Select text or code in the editor first");
                }
                return;
            }
            Gtk.TextIter sel_start, sel_end;
            doc_page.source_buffer.get_selection_bounds (out sel_start, out sel_end);
            string before_text = doc_page.source_buffer.get_text (sel_start, sel_end, false);
            string after_text = code.strip ();

            if (parent_window != null) {
                var mark_start = doc_page.source_buffer.create_mark (null, sel_start, true);
                var mark_end = doc_page.source_buffer.create_mark (null, sel_end, false);
                var dlg = new Adw.AlertDialog (
                    "Preview AI Edit",
                    "Review the proposed replacement before modifying your document:"
                );
                var preview_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                    width_request = 460
                };
                var diff_tv = new Gtk.TextView () {
                    editable = false,
                    monospace = true,
                    wrap_mode = Gtk.WrapMode.WORD_CHAR
                };
                diff_tv.buffer.set_text (@"--- Current Selection ---\n$(before_text)\n\n+++ Proposed Replacement +++\n$(after_text)", -1);
                var sc = new Gtk.ScrolledWindow () {
                    min_content_height = 220,
                    max_content_height = 360,
                    child = diff_tv
                };
                preview_box.append (sc);
                dlg.set_extra_child (preview_box);
                dlg.add_response ("cancel", "Cancel");
                dlg.add_response ("apply", "Apply Edit");
                dlg.set_default_response ("apply");
                dlg.set_response_appearance ("apply", Adw.ResponseAppearance.SUGGESTED);
                dlg.response.connect ((resp) => {
                    if (resp == "apply" && !mark_start.get_deleted () && !mark_end.get_deleted ()) {
                        Gtk.TextIter s2, e2;
                        doc_page.source_buffer.get_iter_at_mark (out s2, mark_start);
                        doc_page.source_buffer.get_iter_at_mark (out e2, mark_end);
                        doc_page.source_buffer.begin_user_action ();
                        try {
                            doc_page.source_buffer.delete (ref s2, ref e2);
                            doc_page.source_buffer.insert (ref s2, after_text, -1);
                        } finally {
                            doc_page.source_buffer.end_user_action ();
                        }
                        parent_window.show_toast_with_action ("Applied AI edit to selection", "Undo", "win.undo");
                    }
                    if (!mark_start.get_deleted ()) doc_page.source_buffer.delete_mark (mark_start);
                    if (!mark_end.get_deleted ()) doc_page.source_buffer.delete_mark (mark_end);
                });
                dlg.present (parent_window);
                return;
            }

            doc_page.source_buffer.begin_user_action ();
            try {
                doc_page.source_buffer.delete (ref sel_start, ref sel_end);
                doc_page.source_buffer.insert (ref sel_start, after_text, -1);
            } finally {
                doc_page.source_buffer.end_user_action ();
            }
        }

        private async bool ensure_free_api_consent_async () {
            var cfg = Core.AiConfigManager.get_default ();
            if (cfg.free_api_consent_accepted) return true;

            var dlg = new Adw.AlertDialog (
                "Free Cloud AI Privacy Notice",
                "You are about to send your prompt and selected document context to a free-tier cloud AI provider (such as Groq, Cerebras, OpenRouter Free, or GitHub Models). Free-tier APIs may have rate limits or provider-specific data retention terms. Do you want to continue?"
            );
            dlg.add_response ("cancel", "Cancel");
            dlg.add_response ("accept", "Use Free API");
            dlg.set_response_appearance ("accept", Adw.ResponseAppearance.SUGGESTED);
            dlg.default_response = "accept";
            dlg.close_response = "cancel";

            string choice = yield dlg.choose (parent_window, null);
            if (choice == "accept") {
                cfg.free_api_consent_accepted = true;
                cfg.save ();
                return true;
            }
            return false;
        }

        private static void ensure_inline_regexes () {
            try {
                if (cached_code_rx == null) cached_code_rx = new GLib.Regex ("`([^`]+?)`");
                if (cached_bold_rx == null) cached_bold_rx = new GLib.Regex ("\\*\\*(.+?)\\*\\*");
            } catch (GLib.RegexError e) {}
        }

        private void scroll_to_bottom (bool force) {
            if (!force && auto_scroll_paused) {
                return;
            }
            if (scroll_idle_id != 0) {
                return;
            }
            scroll_idle_id = GLib.Idle.add (() => {
                scroll_idle_id = 0;
                var vadj = scroller.get_vadjustment ();
                if (vadj != null) {
                    vadj.set_value (vadj.get_upper () - vadj.get_page_size ());
                }
                return GLib.Source.REMOVE;
            });
        }
    }
}
