// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;

namespace Imladris.UI {

    public enum ElrondContextKind {
        ACTIVE_FILE,
        ACTIVE_SELECTION,
        DATAFRAMES,
        LAST_ERROR,
        CUSTOM_FILE
    }

    public class ElrondContextItem : GLib.Object {
        public ElrondContextKind kind { get; set; }
        public string id { owned get; set; default = ""; }
        public string label { owned get; set; default = ""; }
        public string detail { owned get; set; default = ""; }

        public ElrondContextItem (ElrondContextKind kind, string id, string label, string detail = "") {
            this.kind = kind;
            this.id = id;
            this.label = label;
            this.detail = detail;
        }
    }

    /**
     * ElrondCodeBlock
     * Native syntax-highlighted code block powered by read-only GtkSource.View
     * synced to Imladris's active color scheme, with Copy, Insert at Cursor,
     * Apply to Selection, and Expand controls.
     */
    public class ElrondCodeBlock : Gtk.Box {
        private string code_text;
        private Gtk.ScrolledWindow scroller;
        private Gtk.Button? expand_btn = null;
        private bool expanded = false;

        public signal void insert_at_cursor_requested (string code, string lang);
        public signal void apply_to_selection_requested (string code);
        public signal void copy_requested (string code);

        public ElrondCodeBlock (string code, string lang) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.code_text = code;
            this.add_css_class ("elrond-code-block");
            this.margin_top = 4;
            this.margin_bottom = 4;

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            header.add_css_class ("elrond-code-header");

            var lang_lbl = new Gtk.Label (lang.up ()) {
                css_classes = { "dim-label", "caption", "monospace" },
                xalign = 0
            };
            header.append (lang_lbl);
            header.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            var btn_copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy code"
            };
            btn_copy.add_css_class ("flat");
            btn_copy.clicked.connect (() => {
                copy_requested (this.code_text);
            });
            header.append (btn_copy);

            var btn_insert = new Gtk.Button.from_icon_name ("insert-text-symbolic") {
                tooltip_text = "Insert at Cursor"
            };
            btn_insert.add_css_class ("flat");
            btn_insert.clicked.connect (() => {
                insert_at_cursor_requested (this.code_text, lang);
            });
            header.append (btn_insert);

            var btn_apply = new Gtk.Button.from_icon_name ("edit-find-replace-symbolic") {
                tooltip_text = "Apply to Selection"
            };
            btn_apply.add_css_class ("flat");
            btn_apply.clicked.connect (() => {
                apply_to_selection_requested (this.code_text);
            });
            header.append (btn_apply);

            this.append (header);

            var buf = new GtkSource.Buffer (null);
            buf.text = code;
            buf.highlight_syntax = true;

            var lm = GtkSource.LanguageManager.get_default ();
            string mapped_lang = map_language_id (lang);
            var src_lang = lm.get_language (mapped_lang);
            if (src_lang != null) {
                buf.language = src_lang;
            }
            apply_active_scheme (buf);

            var view = new GtkSource.View.with_buffer (buf) {
                editable = false,
                cursor_visible = false,
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                monospace = true,
                show_line_numbers = false,
                highlight_current_line = false,
                top_margin = 6,
                bottom_margin = 6,
                left_margin = 8,
                right_margin = 8
            };
            view.add_css_class ("elrond-code-view");

            int line_count = code.split ("\n").length;
            bool is_long = line_count > 14;

            scroller = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = is_long ? Gtk.PolicyType.AUTOMATIC : Gtk.PolicyType.NEVER,
                propagate_natural_height = true,
                max_content_height = 320
            };
            scroller.set_child (view);
            this.append (scroller);

            if (is_long) {
                expand_btn = new Gtk.Button.with_label (@"Expand ($line_count lines)") {
                    css_classes = { "flat", "caption" },
                    halign = Gtk.Align.CENTER
                };
                expand_btn.clicked.connect (() => {
                    expanded = !expanded;
                    if (expanded) {
                        scroller.max_content_height = 2000;
                        scroller.vscrollbar_policy = Gtk.PolicyType.NEVER;
                        expand_btn.label = "Collapse";
                    } else {
                        scroller.max_content_height = 320;
                        scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
                        expand_btn.label = @"Expand ($line_count lines)";
                    }
                });
                this.append (expand_btn);
            }
        }

        private static string map_language_id (string lang) {
            string l = lang.down ().strip ();
            if (l == "py") return "python3";
            if (l == "python") return "python3";
            if (l == "r") return "r";
            if (l == "sh" || l == "zsh" || l == "bash") return "sh";
            if (l == "tex" || l == "latex") return "latex";
            if (l == "qmd" || l == "rmd" || l == "md") return "markdown";
            if (l == "js") return "js";
            if (l == "ts") return "typescript";
            return l;
        }

        private static void apply_active_scheme (GtkSource.Buffer buf) {
            var sm = GtkSource.StyleSchemeManager.get_default ();
            var theme = Core.SettingsManager.get_default ().app_theme;
            bool is_dark = Adw.StyleManager.get_default ().dark;
            GtkSource.StyleScheme? scheme = null;

            if (theme == Core.AppTheme.DARK || (theme == Core.AppTheme.SYSTEM && is_dark)) {
                scheme = sm.get_scheme ("nord") ?? sm.get_scheme ("Adwaita-dark") ?? sm.get_scheme ("classic-dark");
            } else if (theme == Core.AppTheme.EYE_FRIENDLY) {
                scheme = sm.get_scheme ("solarized-light") ?? sm.get_scheme ("Adwaita");
            } else {
                scheme = sm.get_scheme ("Adwaita") ?? sm.get_scheme ("classic");
            }

            if (scheme != null) {
                buf.style_scheme = scheme;
            }
        }
    }

    /**
     * ElrondUserMessage
     * Right-aligned user message bubble (max ~85% width) with hover/focus Copy & Edit actions.
     */
    public class ElrondUserMessage : Gtk.Box {
        public string message_text { get; private set; }

        public signal void copy_requested (string text);
        public signal void edit_requested (string text);

        public ElrondUserMessage (string text) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 4);
            this.message_text = text;
            this.halign = Gtk.Align.END;
            this.margin_start = 48;
            this.add_css_class ("elrond-message-row");

            var bubble = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            bubble.add_css_class ("elrond-user-bubble");

            var lbl = new Gtk.Label (text) {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                selectable = true
            };
            bubble.append (lbl);
            this.append (bubble);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) {
                halign = Gtk.Align.END
            };
            actions.add_css_class ("elrond-hover-actions");

            var btn_copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy message",
                css_classes = { "flat", "caption" }
            };
            btn_copy.clicked.connect (() => copy_requested (this.message_text));
            actions.append (btn_copy);

            var btn_edit = new Gtk.Button.from_icon_name ("document-edit-symbolic") {
                tooltip_text = "Edit & resend",
                css_classes = { "flat", "caption" }
            };
            btn_edit.clicked.connect (() => edit_requested (this.message_text));
            actions.append (btn_edit);

            this.append (actions);
        }
    }

    /**
     * ElrondAssistantMessage
     * Full-width assistant response with collapsible thinking/tool expander,
     * throttled streaming Markdown, native ElrondCodeBlock widgets, and hover/focus footer.
     */
    public class ElrondAssistantMessage : Gtk.Box {
        private Gtk.Expander thinking_expander;
        private Gtk.Box thinking_header_box;
        private Adw.Spinner thinking_spinner;
        private Gtk.Image thinking_done_icon;
        private Gtk.Label thinking_label;
        private Gtk.Label thinking_detail_label;

        private Gtk.Box body_box;
        private Gtk.Label? stream_label = null;
        private Gtk.Box footer_box;

        private string raw_markdown = "";
        private int64 start_time_us = 0;

        public signal void copy_markdown_requested (string markdown);
        public signal void regenerate_requested ();
        public signal void delete_requested (ElrondAssistantMessage self_msg);
        public signal void insert_code_requested (string code, string lang);
        public signal void apply_code_requested (string code);
        public signal void copy_code_requested (string code);

        public ElrondAssistantMessage (string thinking_status = "Thinking...", string context_summary = "") {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 8);
            this.hexpand = true;
            this.start_time_us = GLib.get_monotonic_time ();
            this.add_css_class ("elrond-assistant-message");
            this.add_css_class ("elrond-message-row");

            // Collapsible Thinking / Tool Row
            thinking_header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            thinking_spinner = new Adw.Spinner () {
                visible = true
            };
            thinking_done_icon = new Gtk.Image.from_icon_name ("emblem-ok-symbolic") {
                visible = false
            };
            thinking_done_icon.add_css_class ("dim-label");
            thinking_label = new Gtk.Label (thinking_status) {
                css_classes = { "caption", "dim-label" },
                xalign = 0
            };
            thinking_header_box.append (thinking_spinner);
            thinking_header_box.append (thinking_done_icon);
            thinking_header_box.append (thinking_label);

            thinking_detail_label = new Gtk.Label (
                context_summary.length > 0 ? context_summary : "No extra document context attached."
            ) {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                css_classes = { "caption", "dim-label" },
                margin_top = 4,
                margin_start = 4,
                margin_end = 4,
                margin_bottom = 2
            };

            thinking_expander = new Gtk.Expander (null) {
                label_widget = thinking_header_box,
                expanded = false,
                child = thinking_detail_label
            };
            thinking_expander.add_css_class ("elrond-thinking-expander");
            this.append (thinking_expander);

            body_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                hexpand = true
            };
            this.append (body_box);

            stream_label = new Gtk.Label ("") {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                selectable = true,
                visible = false
            };
            body_box.append (stream_label);

            // Hover / focus footer
            footer_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                halign = Gtk.Align.START,
                visible = false
            };
            footer_box.add_css_class ("elrond-hover-actions");

            var btn_copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy Markdown",
                css_classes = { "flat", "caption" }
            };
            btn_copy.clicked.connect (() => copy_markdown_requested (this.raw_markdown));
            footer_box.append (btn_copy);

            var btn_regen = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = "Regenerate response",
                css_classes = { "flat", "caption" }
            };
            btn_regen.clicked.connect (() => regenerate_requested ());
            footer_box.append (btn_regen);

            var btn_del = new Gtk.Button.from_icon_name ("user-trash-symbolic") {
                tooltip_text = "Delete message",
                css_classes = { "flat", "caption" }
            };
            btn_del.clicked.connect (() => delete_requested (this));
            footer_box.append (btn_del);

            this.append (footer_box);
        }

        public void update_streaming_preview (string partial_text) {
            this.raw_markdown = partial_text;
            if (stream_label != null) {
                stream_label.visible = true;
                stream_label.label = partial_text;
            }
        }

        public void finish_response (string full_markdown, GLib.Regex? code_rx, GLib.Regex? bold_rx) {
            this.raw_markdown = full_markdown;
            double elapsed_s = (GLib.get_monotonic_time () - start_time_us) / 1000000.0;
            thinking_spinner.visible = false;
            thinking_done_icon.visible = true;
            thinking_label.label = "Thought for %.1fs".printf (double.max (0.1, elapsed_s));
            thinking_expander.expanded = false;

            if (stream_label != null) {
                body_box.remove (stream_label);
                stream_label = null;
            }

            render_markdown_into_body (full_markdown, code_rx, bold_rx);
            footer_box.visible = true;
        }

        private void render_markdown_into_body (string raw, GLib.Regex? code_rx, GLib.Regex? bold_rx) {
            string[] lines = raw.split ("\n");
            var text_buf = new GLib.StringBuilder ();
            var code_buf = new GLib.StringBuilder ();
            bool in_code = false;
            string code_lang = "r";

            for (int i = 0; i < lines.length; i++) {
                string line = lines[i];
                if (line.has_prefix ("```")) {
                    if (!in_code) {
                        if (text_buf.len > 0) {
                            append_text_segment (text_buf.str.strip (), code_rx, bold_rx);
                            text_buf.truncate (0);
                        }
                        in_code = true;
                        string info = line.substring (3).strip ();
                        code_lang = info.length > 0 ? info : "r";
                    } else {
                        in_code = false;
                        append_code_segment (code_buf.str.strip (), code_lang);
                        code_buf.truncate (0);
                    }
                } else if (in_code) {
                    code_buf.append (line + "\n");
                } else {
                    text_buf.append (line + "\n");
                }
            }

            if (in_code && code_buf.len > 0) {
                append_code_segment (code_buf.str.strip (), code_lang);
            } else if (text_buf.len > 0) {
                append_text_segment (text_buf.str.strip (), code_rx, bold_rx);
            }
        }

        private void append_text_segment (string text, GLib.Regex? code_rx, GLib.Regex? bold_rx) {
            if (text.length == 0) return;
            var lbl = new Gtk.Label (null) {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                selectable = true,
                use_markup = true
            };
            lbl.set_markup (format_inline_pango (text, code_rx, bold_rx));
            body_box.append (lbl);
        }

        private void append_code_segment (string code, string lang) {
            if (code.length == 0) return;
            var block = new ElrondCodeBlock (code, lang);
            block.insert_at_cursor_requested.connect ((c, l) => insert_code_requested (c, l));
            block.apply_to_selection_requested.connect ((c) => apply_code_requested (c));
            block.copy_requested.connect ((c) => copy_code_requested (c));
            body_box.append (block);
        }

        private static string format_inline_pango (string raw, GLib.Regex? code_rx, GLib.Regex? bold_rx) {
            string escaped = GLib.Markup.escape_text (raw);
            try {
                if (code_rx == null || bold_rx == null) {
                    return escaped;
                }
                var code_spans = new Gee.ArrayList<string> ();
                string protected_str = code_rx.replace_eval (escaped, -1, 0, 0, (mi, res) => {
                    string placeholder = @"\x01CODE$(code_spans.size)\x02";
                    code_spans.add ("<tt>" + mi.fetch (1) + "</tt>");
                    res.append (placeholder);
                    return false;
                });
                protected_str = bold_rx.replace (protected_str, -1, 0, "<b>\\1</b>");
                for (int i = 0; i < code_spans.size; i++) {
                    protected_str = protected_str.replace (@"\x01CODE$i\x02", code_spans.get (i));
                }
                if (Pango.parse_markup (protected_str, -1, 0, null, null, null)) {
                    return protected_str;
                }
            } catch (GLib.Error e) {
                return escaped;
            }
            return escaped;
        }
    }

    /**
     * ElrondComposer
     * Tactile floating composer card with removable context chips, auto-growing
     * inline TextView (1-6 lines), @ mention popover, model/hardware pill,
     * context usage meter, and circular Send/Stop action button.
     */
    public class ElrondComposer : Gtk.Box {
        private Gtk.FlowBox context_strip;
        private Gtk.ScrolledWindow input_scroller;
        private Gtk.TextView text_view;
        private Gtk.Button attach_btn;
        private Gtk.MenuButton model_pill;
        private Gtk.Label ctx_meter_lbl;
        private Gtk.Button primary_btn;
        private Gtk.Popover mention_popover;

        private Gee.ArrayList<ElrondContextItem> attached_items = new Gee.ArrayList<ElrondContextItem> ();
        private bool is_streaming = false;

        public signal void send_requested (string text);
        public signal void stop_requested ();
        public signal void open_settings_requested ();
        public signal void context_changed ();

        public ElrondComposer () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.add_css_class ("elrond-composer");
            this.margin_start = 12;
            this.margin_end = 12;
            this.margin_bottom = 12;
            this.margin_top = 4;

            // Row 1: Context Strip
            context_strip = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                row_spacing = 4,
                column_spacing = 6,
                max_children_per_line = 6,
                visible = false
            };
            this.append (context_strip);

            // Row 2: Auto-Growing Input
            input_scroller = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                propagate_natural_height = true,
                min_content_height = 28,
                max_content_height = 140
            };

            text_view = new Gtk.TextView () {
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                accepts_tab = false
            };
            text_view.add_css_class ("inline");
            input_scroller.set_child (text_view);
            this.append (input_scroller);

            // Row 3: Compact Action Footer
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            attach_btn = new Gtk.Button.from_icon_name ("list-add-symbolic") {
                tooltip_text = "Attach file or selection",
                css_classes = { "flat" }
            };
            footer.append (attach_btn);

            model_pill = new Gtk.MenuButton () {
                css_classes = { "flat", "pill", "caption" },
                tooltip_text = "Active model & hardware backend"
            };
            footer.append (model_pill);

            footer.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            ctx_meter_lbl = new Gtk.Label ("0% ctx") {
                css_classes = { "caption", "dim-label" },
                valign = Gtk.Align.CENTER
            };
            footer.append (ctx_meter_lbl);

            primary_btn = new Gtk.Button.from_icon_name ("go-up-symbolic") {
                width_request = 32,
                height_request = 32,
                tooltip_text = "Send (Enter)",
                css_classes = { "circular", "suggested-action" }
            };
            primary_btn.clicked.connect (() => {
                if (is_streaming) {
                    stop_requested ();
                } else {
                    string t = text_view.buffer.text.strip ();
                    if (t.length > 0) {
                        send_requested (t);
                    }
                }
            });
            footer.append (primary_btn);

            this.append (footer);

            // @ mention / context attachment popover
            mention_popover = build_context_popover ();
            mention_popover.set_parent (attach_btn);
            attach_btn.clicked.connect (() => {
                mention_popover.popup ();
            });

            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                    if ((state & Gdk.ModifierType.SHIFT_MASK) == 0) {
                        if (!is_streaming) {
                            string t = text_view.buffer.text.strip ();
                            if (t.length > 0) {
                                send_requested (t);
                            }
                        }
                        return true;
                    }
                } else if (keyval == Gdk.Key.at) {
                    mention_popover.popup ();
                }
                return false;
            });
            text_view.add_controller (key_ctrl);

            text_view.buffer.changed.connect (() => {
                context_changed ();
            });

            setup_model_popover ();
        }

        private Gtk.Popover build_context_popover () {
            var pop = new Gtk.Popover ();
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 6,
                margin_end = 6
            };

            var hdr = new Gtk.Label ("Attach Context") {
                css_classes = { "caption", "dim-label" },
                xalign = 0,
                margin_start = 6
            };
            box.append (hdr);

            add_context_option (box, pop, ElrondContextKind.ACTIVE_FILE, "active-file", "Active Document");
            add_context_option (box, pop, ElrondContextKind.ACTIVE_SELECTION, "selection", "Active Selection");
            add_context_option (box, pop, ElrondContextKind.DATAFRAMES, "dataframes", "Environment Dataframes");
            add_context_option (box, pop, ElrondContextKind.LAST_ERROR, "last-error", "Last Console Error");

            pop.set_child (box);
            return pop;
        }

        private void add_context_option (
            Gtk.Box box,
            Gtk.Popover pop,
            ElrondContextKind kind,
            string id,
            string label
        ) {
            var btn = new Gtk.Button.with_label (label) {
                css_classes = { "flat" },
                halign = Gtk.Align.FILL
            };
            btn.clicked.connect (() => {
                attach_context (new ElrondContextItem (kind, id, label));
                pop.popdown ();
            });
            box.append (btn);
        }

        private void setup_model_popover () {
            var pop = new Gtk.Popover ();
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 6,
                margin_end = 6
            };
            var btn_local = new Gtk.Button.with_label ("Use Local Managed llama.cpp") {
                css_classes = { "flat" }
            };
            btn_local.clicked.connect (() => {
                Core.SettingsManager.get_default ().elrond_mode = Core.ElrondMode.MANAGED_LLAMA;
                pop.popdown ();
                refresh_model_pill ();
            });
            box.append (btn_local);

            var btn_auto = new Gtk.Button.with_label ("Auto-Detect Local AI") {
                css_classes = { "flat" }
            };
            btn_auto.clicked.connect (() => {
                Core.SettingsManager.get_default ().elrond_mode = Core.ElrondMode.AUTO_DETECT;
                pop.popdown ();
                refresh_model_pill ();
            });
            box.append (btn_auto);

            var btn_settings = new Gtk.Button.with_label ("Open AI Settings…") {
                css_classes = { "flat" }
            };
            btn_settings.clicked.connect (() => {
                pop.popdown ();
                open_settings_requested ();
            });
            box.append (btn_settings);

            pop.set_child (box);
            model_pill.popover = pop;
            refresh_model_pill ();
        }

        public void refresh_model_pill () {
            var ctrl = AI.ElrondEngineController.get_default ();
            if (ctrl.is_ready) {
                string model = ctrl.active_model_name.length > 0 ? ctrl.active_model_name : "Elrond Local";
                if (model.length > 18) model = model.substring (0, 18) + "…";
                string backend = "CPU";
                if (ctrl.hardware_probe_result != null &&
                    ctrl.hardware_probe_result.selected_device != null &&
                    Core.SettingsManager.get_default ().elrond_compute_mode != Core.ElrondComputeMode.CPU) {
                    backend = "Vulkan";
                }
                model_pill.label = @"$model · $backend";
            } else {
                var cfg = Core.AiConfigManager.get_default ();
                model_pill.label = cfg.active_provider.get_short_name ();
            }
        }

        public void attach_context (ElrondContextItem item) {
            foreach (var existing in attached_items) {
                if (existing.id == item.id) {
                    return;
                }
            }
            attached_items.add (item);
            rebuild_context_strip ();
            context_changed ();
        }

        public bool has_context_kind (ElrondContextKind kind) {
            foreach (var item in attached_items) {
                if (item.kind == kind) return true;
            }
            return false;
        }

        public Gee.ArrayList<ElrondContextItem> get_attached_items () {
            return attached_items;
        }

        private void rebuild_context_strip () {
            Gtk.Widget? child = context_strip.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                context_strip.remove (child);
                child = next;
            }

            foreach (var item in attached_items) {
                var chip = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                chip.add_css_class ("elrond-context-chip");
                chip.append (new Gtk.Label (item.label) { css_classes = { "caption" } });

                var rm_btn = new Gtk.Button.from_icon_name ("window-close-symbolic") {
                    css_classes = { "flat" },
                    tooltip_text = @"Remove $(item.label)"
                };
                ElrondContextItem target_item = item;
                rm_btn.clicked.connect (() => {
                    attached_items.remove (target_item);
                    rebuild_context_strip ();
                    context_changed ();
                });
                chip.append (rm_btn);
                context_strip.append (chip);
            }

            context_strip.visible = (attached_items.size > 0);
        }

        public void update_context_meter (int estimated_chars, int max_chars = 16000) {
            int total = estimated_chars + text_view.buffer.text.length;
            int pct = ((total * 100) / int.max (1, max_chars)).clamp (0, 100);
            ctx_meter_lbl.label = @"$pct% ctx";
            ctx_meter_lbl.remove_css_class ("elrond-ctx-warn");
            ctx_meter_lbl.remove_css_class ("elrond-ctx-err");
            ctx_meter_lbl.add_css_class ("dim-label");

            if (pct > 90) {
                ctx_meter_lbl.remove_css_class ("dim-label");
                ctx_meter_lbl.add_css_class ("elrond-ctx-err");
            } else if (pct > 75) {
                ctx_meter_lbl.remove_css_class ("dim-label");
                ctx_meter_lbl.add_css_class ("elrond-ctx-warn");
            }
        }

        public void set_streaming (bool streaming) {
            this.is_streaming = streaming;
            if (streaming) {
                primary_btn.icon_name = "media-playback-stop-symbolic";
                primary_btn.tooltip_text = "Stop Generation";
                primary_btn.remove_css_class ("suggested-action");
                primary_btn.add_css_class ("destructive-action");
            } else {
                primary_btn.icon_name = "go-up-symbolic";
                primary_btn.tooltip_text = "Send (Enter)";
                primary_btn.remove_css_class ("destructive-action");
                primary_btn.add_css_class ("suggested-action");
            }
        }

        public void set_text (string text) {
            text_view.buffer.text = text;
        }

        public string get_text () {
            return text_view.buffer.text;
        }

        public void focus_input () {
            text_view.grab_focus ();
        }
    }
}
