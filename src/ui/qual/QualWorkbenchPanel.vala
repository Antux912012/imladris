// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Qual;
using Imladris.Bridges.Qual;

namespace Imladris.UI.Qual {

    /**
     * Dockable Qualitative Analysis Workbench Panel.
     * Integrates Adw.OverlaySplitView (CodebookSidebar + ViewStack of EvidenceMatrixView,
     * QualGraphView, CRA Queries & ALCOA+ Audit Log, and Elrond AI Adjudication Queue).
     */
    public class QualWorkbenchPanel : Gtk.Box {
        private unowned DocumentPage doc_page;
        private unowned Window? main_window;
        public QualWorkspaceService service { get; private set; }

        private Adw.OverlaySplitView split_view;
        public CodebookSidebar codebook_sidebar { get; private set; }
        public EvidenceMatrixView matrix_view { get; private set; }
        public QualGraphView graph_view { get; private set; }

        private Gtk.ListBox queries_list;
        private Gtk.ListBox memos_list;
        private Gtk.ListBox audit_list;
        private Gtk.ListBox ai_queue_list;
        private ulong svc_hid = 0;

        public QualWorkbenchPanel (DocumentPage page, Window? win) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.doc_page = page;
            this.main_window = win;
            this.hexpand = true;
            this.vexpand = true;

            string ws_dir = page.current_project_dir;
            if (ws_dir == "" && win != null) ws_dir = win.get_workspace_root ();
            this.service = QualWorkspaceService.for_workspace (ws_dir);

            build_ui ();
            refresh_auxiliary_tabs ();

            svc_hid = service.state_changed.connect (() => {
                matrix_view.refresh ();
                graph_view.on_workspace_state_changed ();
                refresh_auxiliary_tabs ();
                doc_page.apply_blinded_qual_mask (service.blinded_mode, service.current_coder);
            });
        }

        public void sync_workspace_dir (string new_dir) {
            if (new_dir == "" || new_dir == service.workspace_dir) return;
            if (svc_hid != 0) {
                service.disconnect (svc_hid);
                svc_hid = 0;
            }
            service = QualWorkspaceService.for_workspace (new_dir);
            codebook_sidebar.set_service (service);
            matrix_view.set_service (service);
            graph_view.set_service (service);
            svc_hid = service.state_changed.connect (() => {
                matrix_view.refresh ();
                graph_view.on_workspace_state_changed ();
                refresh_auxiliary_tabs ();
                doc_page.apply_blinded_qual_mask (service.blinded_mode, service.current_coder);
            });
            refresh_auxiliary_tabs ();
            doc_page.apply_blinded_qual_mask (service.blinded_mode, service.current_coder);
        }

        public void cleanup () {
            if (svc_hid != 0 && service != null) {
                service.disconnect (svc_hid);
                svc_hid = 0;
            }
            if (codebook_sidebar != null) codebook_sidebar.cleanup ();
        }

        private void build_ui () {
            var top_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6
            };
            top_bar.add_css_class ("dock-subtoolbar");

            var btn_toggle_cb = new Gtk.ToggleButton () {
                icon_name = "view-list-bullet-symbolic",
                active = true,
                tooltip_text = "Show / Hide Codebook Sidebar"
            };
            btn_toggle_cb.add_css_class ("flat");
            top_bar.append (btn_toggle_cb);

            var view_stack = new Adw.ViewStack () {
                hexpand = true,
                vexpand = true
            };
            var switcher = new Adw.ViewSwitcher () {
                stack = view_stack,
                policy = Adw.ViewSwitcherPolicy.NARROW
            };
            top_bar.append (switcher);
            top_bar.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { hexpand = true });

            var btn_biostats = new Gtk.Button.with_label ("Biostats & IRR") {
                tooltip_text = "Open Qualitative Biostatistical IRR, Enrichment & Saturation Dashboard"
            };
            btn_biostats.add_css_class ("flat");
            btn_biostats.clicked.connect (open_biostats_dashboard);
            top_bar.append (btn_biostats);

            this.append (top_bar);

            split_view = new Adw.OverlaySplitView () {
                hexpand = true,
                vexpand = true,
                min_sidebar_width = 210,
                max_sidebar_width = 270,
                show_sidebar = true
            };
            btn_toggle_cb.bind_property ("active", split_view, "show-sidebar", GLib.BindingFlags.BIDIRECTIONAL);

            codebook_sidebar = new CodebookSidebar (service);
            codebook_sidebar.apply_code_requested.connect ((code_id) => {
                doc_page.apply_qual_code_to_selection (code_id);
            });
            codebook_sidebar.filter_by_code_requested.connect ((code_id) => {
                matrix_view.set_code_filter (code_id);
            });
            split_view.set_sidebar (codebook_sidebar);

            matrix_view = new EvidenceMatrixView (service, main_window);
            matrix_view.jump_to_span_requested.connect ((fpath, line, span_id) => {
                string? cur_path = doc_page.file_location != null ? doc_page.file_location.get_path () : null;
                if (fpath != "" && cur_path != fpath && main_window != null && GLib.FileUtils.test (fpath, GLib.FileTest.EXISTS)) {
                    main_window.open_file_from_path.begin (fpath, (o, r) => {
                        main_window.open_file_from_path.end (r);
                        var active = main_window.get_active_document ();
                        if (active != null) active.jump_to_line_1based (line);
                    });
                } else {
                    doc_page.jump_to_line_1based (line);
                }
            });
            matrix_view.insert_quarto_table_requested.connect ((md) => {
                if (main_window != null) {
                    main_window.insert_in_active_editor (md);
                    main_window.show_toast ("Inserted Qualitative Evidence Matrix table");
                }
            });

            graph_view = new QualGraphView (service, main_window);
            graph_view.insert_figure_requested.connect ((snippet) => {
                if (main_window != null) {
                    main_window.insert_in_active_editor (snippet);
                    main_window.show_toast ("Inserted qualitative network figure into manuscript");
                }
            });

            view_stack.add_titled_with_icon (matrix_view, "matrix", "Matrix", "view-grid-symbolic");
            view_stack.add_titled_with_icon (graph_view, "network", "Graph", "network-cellular-symbolic");
            view_stack.add_titled_with_icon (build_cra_audit_tab (), "cra", "CRA & Audit", "security-high-symbolic");
            view_stack.add_titled_with_icon (build_ai_adjudication_tab (), "ai", "AI Review", "system-run-symbolic");

            split_view.set_content (view_stack);
            this.append (split_view);
        }

        private Gtk.Widget build_cra_audit_tab () {
            var scroller = new Gtk.ScrolledWindow () { vexpand = true, hexpand = true };
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 10,
                margin_bottom = 14,
                margin_start = 12,
                margin_end = 12
            };

            var q_hdr = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            q_hdr.append (new Gtk.Label ("CRA Queries & Deviations (EDC)") { css_classes = { "heading" }, xalign = 0, hexpand = true });
            var btn_new_q = new Gtk.Button.with_label ("+ Raise Query");
            btn_new_q.add_css_class ("flat");
            btn_new_q.clicked.connect (() => doc_page.prompt_raise_cra_query ());
            q_hdr.append (btn_new_q);
            vbox.append (q_hdr);

            queries_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, css_classes = { "boxed-list" } };
            vbox.append (queries_list);

            var m_hdr = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            m_hdr.append (new Gtk.Label ("Analytical Memos") { css_classes = { "heading" }, xalign = 0, hexpand = true });
            var btn_new_m = new Gtk.Button.with_label ("+ Add Memo");
            btn_new_m.add_css_class ("flat");
            btn_new_m.clicked.connect (() => doc_page.prompt_add_qual_memo ());
            m_hdr.append (btn_new_m);
            vbox.append (m_hdr);

            memos_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, css_classes = { "boxed-list" } };
            vbox.append (memos_list);

            vbox.append (new Gtk.Label ("Immutable ALCOA+ Audit Trail (Append-Only)") { css_classes = { "heading" }, xalign = 0 });
            audit_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, css_classes = { "boxed-list" } };
            vbox.append (audit_list);

            scroller.set_child (vbox);
            return scroller;
        }

        private Gtk.Widget build_ai_adjudication_tab () {
            var scroller = new Gtk.ScrolledWindow () { vexpand = true, hexpand = true };
            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 10) {
                margin_top = 10,
                margin_bottom = 14,
                margin_start = 12,
                margin_end = 12
            };

            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var btn_run_ai = new Gtk.Button.with_label ("Suggest Codes (Elrond AI)") {
                tooltip_text = "Run grammar-constrained Elrond AI coding suggestions (queued in Pending Review)"
            };
            btn_run_ai.add_css_class ("suggested-action");
            btn_run_ai.clicked.connect (() => run_elrond_coding_async.begin ());
            bar.append (btn_run_ai);

            var btn_hook = new Gtk.Button.with_label ("Ingest .qual-hook.json") {
                tooltip_text = "Import quantitative R/Python/Galaxy threshold tags from .qual-hook.json"
            };
            btn_hook.clicked.connect (ingest_workspace_hook);
            bar.append (btn_hook);

            vbox.append (bar);

            var note = new Gtk.Label ("All AI suggestions enter Pending Review and require explicit human approval before writing to spans and audit_log.") {
                xalign = 0,
                wrap = true,
                css_classes = { "caption", "dim-label" }
            };
            vbox.append (note);

            ai_queue_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE, css_classes = { "boxed-list" } };
            vbox.append (ai_queue_list);

            scroller.set_child (vbox);
            return scroller;
        }

        public void refresh_auxiliary_tabs () {
            if (service.db == null) return;

            clear_lb (queries_list);
            var qs = service.db.list_review_queries ();
            if (qs.size == 0) {
                queries_list.append (new Adw.ActionRow () { title = "No open CRA queries", subtitle = "Right-click a coded span to raise an SDV or protocol query." });
            } else {
                foreach (var q in qs) {
                    var r = new Adw.ActionRow () {
                        title = @"[$(q.status)] Span $(q.span_id != "" ? q.span_id : "Document") — by $(q.raised_by)",
                        subtitle = q.message + (q.resolution_note != null ? @" | Resolution: $(q.resolution_note)" : ""),
                        use_markup = false
                    };
                    if (q.status != "Closed") {
                        var btn_close = new Gtk.Button.with_label (q.status == "Open" ? "Answer" : "Close") { valign = Gtk.Align.CENTER };
                        btn_close.add_css_class ("flat");
                        var q_ref = q;
                        btn_close.clicked.connect (() => {
                            q_ref.status = (q_ref.status == "Open") ? "Answered" : "Closed";
                            try { service.db.upsert_review_query (q_ref, service.current_coder, "CRA workflow transition"); } catch (GLib.Error e) {}
                        });
                        r.add_suffix (btn_close);
                    }
                    queries_list.append (r);
                }
            }

            clear_lb (memos_list);
            var memos = service.db.list_memos ();
            if (memos.size == 0) {
                memos_list.append (new Adw.ActionRow () { title = "No analytical memos yet", subtitle = "Attach theoretical or methodological memos to codes, entities, or spans." });
            } else {
                foreach (var m in memos) {
                    memos_list.append (new Adw.ActionRow () {
                        title = @"$(m.target_id) · $(m.author_id) · $(m.created_utc)",
                        subtitle = m.body,
                        use_markup = false
                    });
                }
            }

            clear_lb (audit_list);
            var logs = service.db.list_audit_log (40);
            foreach (var a in logs) {
                audit_list.append (new Adw.ActionRow () {
                    title = @"#$(a.log_id) $(a.action) on $(a.target_table) ($(a.target_id))",
                    subtitle = @"$(a.timestamp_utc) · user: $(a.user_id)" + (a.rationale != null ? @" · $(a.rationale)" : ""),
                    use_markup = false
                });
            }

            clear_lb (ai_queue_list);
            var pending = service.db.list_ai_suggestions ("Pending Review");
            if (pending.size == 0) {
                ai_queue_list.append (new Adw.ActionRow () {
                    title = "No pending AI coding suggestions",
                    subtitle = "Click Suggest Codes (Elrond AI) to analyze the active manuscript."
                });
            } else {
                foreach (var sug in pending) {
                    var r = new Adw.ActionRow () {
                        title = @"$(sug.suggested_code_id) ($(sug.confidence)) — L$(sug.line_start)",
                        subtitle = @"\"$(sug.excerpt)\" — $(sug.rationale)",
                        use_markup = false
                    };
                    var btn_app = new Gtk.Button.with_label ("Approve") { valign = Gtk.Align.CENTER };
                    btn_app.add_css_class ("suggested-action");
                    string sid = sug.suggestion_id;
                    btn_app.clicked.connect (() => adjudicate_item (sid, true));

                    var btn_rej = new Gtk.Button.with_label ("Reject") { valign = Gtk.Align.CENTER };
                    btn_rej.add_css_class ("flat");
                    btn_rej.clicked.connect (() => adjudicate_item (sid, false));

                    r.add_suffix (btn_app);
                    r.add_suffix (btn_rej);
                    ai_queue_list.append (r);
                }
            }
        }

        private void adjudicate_item (string suggestion_id, bool approve) {
            try {
                QualAiSuggestion? target_sug = null;
                if (service.db != null) {
                    foreach (var s in service.db.list_ai_suggestions ("Pending Review")) {
                        if (s.suggestion_id == suggestion_id) {
                            target_sug = s;
                            break;
                        }
                    }
                }
                if (target_sug == null) return;

                string? active_path = doc_page.file_location != null ? doc_page.file_location.get_path () : null;
                bool is_active_doc = (active_path == null && target_sug.file_path == "untitled.qmd") ||
                                     (active_path != null && active_path == target_sug.file_path);

                string cur_text = "";
                if (is_active_doc) {
                    cur_text = doc_page.get_clean_source_text ();
                } else if (target_sug.file_path != "" && GLib.FileUtils.test (target_sug.file_path, GLib.FileTest.EXISTS)) {
                    GLib.FileUtils.get_contents (target_sug.file_path, out cur_text);
                }

                QualSpan? sp = null;
                string updated = ElrondQualCodingBridge.adjudicate_into_document (
                    service,
                    suggestion_id,
                    approve,
                    service.current_coder,
                    cur_text,
                    approve ? "Approved in Human Adjudication Queue" : "Rejected in Human Adjudication Queue",
                    out sp
                );
                if (approve && updated != cur_text) {
                    if (is_active_doc) {
                        doc_page.replace_buffer_preserving_undo (updated);
                    } else if (target_sug.file_path != "" && GLib.FileUtils.test (target_sug.file_path, GLib.FileTest.EXISTS)) {
                        GLib.FileUtils.set_contents (target_sug.file_path, updated);
                    }
                }
                if (main_window != null) {
                    main_window.show_toast (approve ? "Approved AI suggestion & wrote ALCOA+ span" : "Rejected AI suggestion");
                }
            } catch (GLib.Error e) {
                if (main_window != null) main_window.show_toast (@"Adjudication error: $(e.message)");
            }
        }

        private async void run_elrond_coding_async () {
            string doc_text = doc_page.get_clean_source_text ();
            if (doc_text.strip () == "") return;
            string fpath = doc_page.file_location != null ? (doc_page.file_location.get_path () ?? "untitled.qmd") : "untitled.qmd";

            var ai = new AiClient ();
            string sys_p = ElrondQualCodingBridge.build_system_prompt (service.active_profile);
            try {
                string resp = yield ai.send_chat_completion_async (sys_p, doc_text);
                var queued = ElrondQualCodingBridge.parse_and_queue_suggestions (service, resp, fpath);
                if (main_window != null) {
                    main_window.show_toast (@"Queued $(queued.size) Elrond AI coding suggestion(s) in Pending Review");
                }
            } catch (GLib.Error e) {
                if (main_window != null) {
                    main_window.show_toast (@"Elrond AI coding error: $(e.message)");
                }
            }
        }

        private void ingest_workspace_hook () {
            string hook_path = GLib.Path.build_filename (service.workspace_dir, ".qual-hook.json");
            if (!GLib.FileUtils.test (hook_path, GLib.FileTest.EXISTS)) {
                if (main_window != null) {
                    main_window.insert_in_active_editor (ArekyerQualHookBridge.generate_r_hook_snippet ());
                    main_window.show_toast ("No .qual-hook.json found — inserted R hook generator chunk into editor");
                }
                return;
            }
            try {
                string fpath = doc_page.file_location != null ? (doc_page.file_location.get_path () ?? "") : "";
                int n = ArekyerQualHookBridge.ingest_hook_file (service, hook_path, fpath, service.current_coder);
                if (main_window != null) main_window.show_toast (@"Ingested $n quantitative-to-qualitative annotations from .qual-hook.json");
            } catch (GLib.Error e) {
                if (main_window != null) main_window.show_toast (@"Hook ingest failed: $(e.message)");
            }
        }

        public void open_biostats_dashboard () {
            var dlg = new BiostatDashboard (service, main_window);
            dlg.insert_summary_requested.connect ((md) => {
                if (main_window != null) {
                    main_window.insert_in_active_editor (md);
                    main_window.show_toast ("Inserted qualitative biostatistics block into document");
                }
            });
            dlg.present ((Gtk.Widget?) main_window ?? this);
        }

        private static void clear_lb (Gtk.ListBox lb) {
            var ch = lb.get_first_child ();
            while (ch != null) {
                var nx = ch.get_next_sibling ();
                lb.remove (ch);
                ch = nx;
            }
        }
    }
}
