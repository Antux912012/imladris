// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Sqlite;

namespace Imladris.Qual {

    public errordomain QualDbError {
        OPEN_FAILED,
        MIGRATION_FAILED,
        QUERY_FAILED,
        IMMUTABILITY_VIOLATION
    }

    /**
     * ALCOA+ Immutable Audit Logger Middleware.
     * Writes append-only audit records inside the caller's active SQLite transaction.
     */
    public class AuditLogger : GLib.Object {

        public static void record (
            Sqlite.Database db,
            string user_id,
            string action,
            string target_table,
            string target_id,
            string? previous_json,
            string? new_json,
            string? rationale = null
        ) throws QualDbError {
            string sql = """
                INSERT INTO audit_log (
                    timestamp_utc, user_id, action, target_table, target_id,
                    previous_json, new_json, rationale
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);
            """;
            Sqlite.Statement stmt;
            int rc = db.prepare_v2 (sql, sql.length, out stmt);
            if (rc != Sqlite.OK) {
                throw new QualDbError.QUERY_FAILED (@"Audit prepare failed: $(db.errmsg ())");
            }
            string ts = QualSpan.now_iso8601_utc ();
            string actor = (user_id.strip () != "") ? user_id.strip () : "system";
            stmt.bind_text (1, ts);
            stmt.bind_text (2, actor);
            stmt.bind_text (3, action);
            stmt.bind_text (4, target_table);
            stmt.bind_text (5, target_id);
            if (previous_json != null) stmt.bind_text (6, previous_json); else stmt.bind_null (6);
            if (new_json != null) stmt.bind_text (7, new_json); else stmt.bind_null (7);
            if (rationale != null && rationale != "") stmt.bind_text (8, rationale); else stmt.bind_null (8);

            rc = stmt.step ();
            if (rc != Sqlite.DONE) {
                throw new QualDbError.QUERY_FAILED (@"Audit write failed: $(db.errmsg ())");
            }
        }
    }

    /**
     * Per-workspace SQLite3 sidecar (.imladris-qual.db) with WAL mode,
     * schema migration, SDV SHA-256 verification, and 100% ALCOA+ audit trail coverage.
     */
    public class QualDatabase : GLib.Object {
        public const int CURRENT_SCHEMA_VERSION = 2;

        public string db_path { get; private set; }
        private Sqlite.Database? db = null;

        public signal void database_changed ();

        public QualDatabase (string workspace_or_db_path) throws QualDbError {
            if (workspace_or_db_path.has_suffix (".db") || workspace_or_db_path.has_suffix (".sqlite")) {
                this.db_path = workspace_or_db_path;
                string parent = GLib.Path.get_dirname (this.db_path);
                if (parent != "" && parent != ".") {
                    GLib.DirUtils.create_with_parents (parent, 0755);
                }
            } else {
                GLib.DirUtils.create_with_parents (workspace_or_db_path, 0755);
                this.db_path = GLib.Path.build_filename (workspace_or_db_path, ".imladris-qual.db");
            }

            Sqlite.Database opened;
            int rc = Sqlite.Database.open_v2 (
                this.db_path,
                out opened,
                Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE | Sqlite.OPEN_FULLMUTEX,
                null
            );
            if (rc != Sqlite.OK) {
                throw new QualDbError.OPEN_FAILED (@"Cannot open SQLite DB at $(this.db_path): $(rc)");
            }
            this.db = (owned) opened;
            exec_raw ("PRAGMA journal_mode=WAL;");
            exec_raw ("PRAGMA synchronous=NORMAL;");
            exec_raw ("PRAGMA foreign_keys=ON;");
            migrate_schema ();
        }

        private void exec_raw (string sql) throws QualDbError {
            string? errmsg = null;
            int rc = db.exec (sql, null, out errmsg);
            if (rc != Sqlite.OK) {
                string msg = errmsg ?? db.errmsg ();
                if (msg.contains ("immutable")) {
                    throw new QualDbError.IMMUTABILITY_VIOLATION (msg);
                }
                throw new QualDbError.QUERY_FAILED (msg);
            }
        }

        private void migrate_schema () throws QualDbError {
            exec_raw ("""
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_utc TEXT NOT NULL
                );
            """);

            int current_ver = 0;
            Sqlite.Statement vstmt;
            if (db.prepare_v2 ("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;", -1, out vstmt) == Sqlite.OK) {
                if (vstmt.step () == Sqlite.ROW) {
                    current_ver = vstmt.column_int (0);
                }
            }

            if (current_ver < 1) {
                exec_raw ("BEGIN IMMEDIATE;");
                try {
                    exec_raw ("""
                        CREATE TABLE IF NOT EXISTS spans (
                            span_id TEXT PRIMARY KEY,
                            file_path TEXT NOT NULL,
                            line_start INTEGER NOT NULL,
                            line_end INTEGER NOT NULL,
                            byte_start INTEGER DEFAULT 0,
                            byte_end INTEGER DEFAULT 0,
                            source_sha256 TEXT NOT NULL,
                            excerpt TEXT NOT NULL,
                            domain TEXT NOT NULL,
                            code_id TEXT NOT NULL,
                            valence TEXT DEFAULT '',
                            entity_id TEXT,
                            coder_id TEXT NOT NULL,
                            confidence TEXT,
                            citation_key TEXT,
                            source_uri TEXT,
                            created_utc TEXT NOT NULL
                        );

                        CREATE INDEX IF NOT EXISTS idx_spans_file ON spans(file_path);
                        CREATE INDEX IF NOT EXISTS idx_spans_code ON spans(code_id);
                        CREATE INDEX IF NOT EXISTS idx_spans_entity ON spans(entity_id);
                        CREATE INDEX IF NOT EXISTS idx_spans_coder ON spans(coder_id);

                        CREATE TABLE IF NOT EXISTS memos (
                            memo_id TEXT PRIMARY KEY,
                            target_id TEXT NOT NULL,
                            author_id TEXT NOT NULL,
                            body TEXT NOT NULL,
                            created_utc TEXT NOT NULL
                        );

                        CREATE INDEX IF NOT EXISTS idx_memos_target ON memos(target_id);

                        CREATE TABLE IF NOT EXISTS network_edges (
                            edge_id TEXT PRIMARY KEY,
                            source_node TEXT NOT NULL,
                            target_node TEXT NOT NULL,
                            relation_type TEXT NOT NULL,
                            weight REAL DEFAULT 1.0,
                            evidence_span_id TEXT REFERENCES spans(span_id) ON DELETE SET NULL
                        );

                        CREATE TABLE IF NOT EXISTS audit_log (
                            log_id INTEGER PRIMARY KEY AUTOINCREMENT,
                            timestamp_utc TEXT NOT NULL,
                            user_id TEXT NOT NULL,
                            action TEXT NOT NULL,
                            target_table TEXT NOT NULL,
                            target_id TEXT NOT NULL,
                            previous_json TEXT,
                            new_json TEXT,
                            rationale TEXT
                        );

                        CREATE TRIGGER IF NOT EXISTS trg_audit_log_no_update
                        BEFORE UPDATE ON audit_log
                        BEGIN
                            SELECT RAISE(ABORT, 'ALCOA+ audit_log is immutable and append-only');
                        END;

                        CREATE TRIGGER IF NOT EXISTS trg_audit_log_no_delete
                        BEFORE DELETE ON audit_log
                        BEGIN
                            SELECT RAISE(ABORT, 'ALCOA+ audit_log is immutable and append-only');
                        END;

                        CREATE TABLE IF NOT EXISTS review_queries (
                            query_id TEXT PRIMARY KEY,
                            span_id TEXT REFERENCES spans(span_id) ON DELETE CASCADE,
                            raised_by TEXT NOT NULL,
                            status TEXT CHECK(status IN ('Open', 'Answered', 'Closed')) NOT NULL,
                            message TEXT NOT NULL,
                            resolution_note TEXT,
                            updated_utc TEXT NOT NULL
                        );
                    """);
                    exec_raw (@"INSERT INTO schema_migrations(version, applied_utc) VALUES (1, '$(QualSpan.now_iso8601_utc ())');");
                    exec_raw ("COMMIT;");
                } catch (QualDbError e) {
                    try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                    throw new QualDbError.MIGRATION_FAILED (e.message);
                }
            }

            if (current_ver < 2) {
                exec_raw ("BEGIN IMMEDIATE;");
                try {
                    exec_raw ("""
                        CREATE TABLE IF NOT EXISTS ai_suggestions (
                            suggestion_id TEXT PRIMARY KEY,
                            file_path TEXT NOT NULL,
                            line_start INTEGER NOT NULL,
                            line_end INTEGER NOT NULL,
                            excerpt TEXT NOT NULL,
                            domain TEXT NOT NULL,
                            suggested_code_id TEXT NOT NULL,
                            entity_id TEXT,
                            confidence TEXT DEFAULT 'moderate',
                            valence TEXT DEFAULT 'neutral',
                            rationale TEXT,
                            status TEXT CHECK(status IN ('Pending Review', 'Approved', 'Rejected')) NOT NULL DEFAULT 'Pending Review',
                            created_utc TEXT NOT NULL
                        );
                    """);
                    exec_raw (@"INSERT INTO schema_migrations(version, applied_utc) VALUES (2, '$(QualSpan.now_iso8601_utc ())');");
                    exec_raw ("COMMIT;");
                } catch (QualDbError e) {
                    try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                    throw new QualDbError.MIGRATION_FAILED (e.message);
                }
            }
        }

        public string get_journal_mode () {
            Sqlite.Statement stmt;
            if (db.prepare_v2 ("PRAGMA journal_mode;", -1, out stmt) == Sqlite.OK) {
                if (stmt.step () == Sqlite.ROW) {
                    return stmt.column_text (0) ?? "";
                }
            }
            return "";
        }

        // =====================================================================
        // SPANS CRUD (100% Audited)
        // =====================================================================
        public QualSpan? get_span (string span_id) {
            string sql = """
                SELECT span_id, file_path, line_start, line_end, byte_start, byte_end,
                       source_sha256, excerpt, domain, code_id, valence, entity_id,
                       coder_id, confidence, citation_key, source_uri, created_utc
                FROM spans WHERE span_id = ?1;
            """;
            Sqlite.Statement stmt;
            if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) return null;
            stmt.bind_text (1, span_id);
            if (stmt.step () == Sqlite.ROW) {
                return row_to_span (stmt);
            }
            return null;
        }

        private QualSpan row_to_span (Sqlite.Statement stmt) {
            var s = new QualSpan ();
            s.span_id = stmt.column_text (0) ?? "";
            s.file_path = stmt.column_text (1) ?? "";
            s.line_start = stmt.column_int (2);
            s.line_end = stmt.column_int (3);
            s.byte_start = stmt.column_int (4);
            s.byte_end = stmt.column_int (5);
            s.source_sha256 = stmt.column_text (6) ?? "";
            s.excerpt = stmt.column_text (7) ?? "";
            s.domain = stmt.column_text (8) ?? "general";
            s.code_id = stmt.column_text (9) ?? "";
            s.valence = stmt.column_text (10) ?? "";
            s.entity_id = stmt.column_type (11) != Sqlite.NULL ? stmt.column_text (11) : null;
            s.coder_id = stmt.column_text (12) ?? "";
            s.confidence = stmt.column_type (13) != Sqlite.NULL ? stmt.column_text (13) : null;
            s.citation_key = stmt.column_type (14) != Sqlite.NULL ? stmt.column_text (14) : null;
            s.source_uri = stmt.column_type (15) != Sqlite.NULL ? stmt.column_text (15) : null;
            s.created_utc = stmt.column_text (16) ?? "";
            return s;
        }

        public void upsert_span (QualSpan span, string user_id, string rationale = "Span indexed") throws QualDbError {
            if (span.span_id == "") span.span_id = QualSpan.generate_short_id ();
            if (span.created_utc == "") span.created_utc = QualSpan.now_iso8601_utc ();

            var existing = get_span (span.span_id);
            string? prev_json = existing != null ? existing.to_json () : null;
            string new_json = span.to_json ();
            if (prev_json != null && prev_json == new_json) {
                return;
            }
            string action = existing == null ? "CREATE_SPAN" : "UPDATE_SPAN";

            exec_raw ("BEGIN IMMEDIATE;");
            try {
                string sql = """
                    INSERT INTO spans (
                        span_id, file_path, line_start, line_end, byte_start, byte_end,
                        source_sha256, excerpt, domain, code_id, valence, entity_id,
                        coder_id, confidence, citation_key, source_uri, created_utc
                    ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
                    ON CONFLICT(span_id) DO UPDATE SET
                        file_path = excluded.file_path,
                        line_start = excluded.line_start,
                        line_end = excluded.line_end,
                        byte_start = excluded.byte_start,
                        byte_end = excluded.byte_end,
                        source_sha256 = excluded.source_sha256,
                        excerpt = excluded.excerpt,
                        domain = excluded.domain,
                        code_id = excluded.code_id,
                        valence = excluded.valence,
                        entity_id = excluded.entity_id,
                        coder_id = excluded.coder_id,
                        confidence = excluded.confidence,
                        citation_key = excluded.citation_key,
                        source_uri = excluded.source_uri;
                """;
                Sqlite.Statement stmt;
                if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }
                bind_span_fields (stmt, span);
                if (stmt.step () != Sqlite.DONE) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }

                AuditLogger.record (db, user_id, action, "spans", span.span_id, prev_json, new_json, rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        private void bind_span_fields (Sqlite.Statement stmt, QualSpan span) {
            stmt.bind_text (1, span.span_id);
            stmt.bind_text (2, span.file_path);
            stmt.bind_int (3, span.line_start);
            stmt.bind_int (4, span.line_end);
            stmt.bind_int (5, span.byte_start);
            stmt.bind_int (6, span.byte_end);
            stmt.bind_text (7, span.source_sha256);
            stmt.bind_text (8, span.excerpt);
            stmt.bind_text (9, span.domain);
            stmt.bind_text (10, span.code_id);
            stmt.bind_text (11, span.valence);
            if (span.entity_id != null && span.entity_id != "") stmt.bind_text (12, span.entity_id); else stmt.bind_null (12);
            stmt.bind_text (13, span.coder_id);
            if (span.confidence != null && span.confidence != "") stmt.bind_text (14, span.confidence); else stmt.bind_null (14);
            if (span.citation_key != null && span.citation_key != "") stmt.bind_text (15, span.citation_key); else stmt.bind_null (15);
            if (span.source_uri != null && span.source_uri != "") stmt.bind_text (16, span.source_uri); else stmt.bind_null (16);
            stmt.bind_text (17, span.created_utc);
        }

        public void delete_span (string span_id, string user_id, string rationale = "Span deleted") throws QualDbError {
            var existing = get_span (span_id);
            if (existing == null) return;
            string prev_json = existing.to_json ();

            exec_raw ("BEGIN IMMEDIATE;");
            try {
                Sqlite.Statement stmt;
                if (db.prepare_v2 ("DELETE FROM spans WHERE span_id = ?1;", -1, out stmt) != Sqlite.OK) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }
                stmt.bind_text (1, span_id);
                if (stmt.step () != Sqlite.DONE) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }
                AuditLogger.record (db, user_id, "DELETE_SPAN", "spans", span_id, prev_json, null, rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        /**
         * Synchronizes all Pandoc {.qual} spans parsed from a document into SQLite in a single
         * batched transaction while auditing every inserted, modified, or removed span.
         */
        public void sync_document_spans (
            string file_path,
            string doc_text,
            string user_id,
            string rationale = "Document span sync"
        ) throws QualDbError {
            var parsed = QualSpanParser.parse_document (doc_text, file_path);
            var existing_list = list_spans (file_path);
            var existing_map = new Gee.HashMap<string, QualSpan> ();
            foreach (var ex in existing_list) {
                existing_map.set (ex.span_id, ex);
            }
            var seen_ids = new Gee.HashSet<string> ();
            bool any_change = false;

            exec_raw ("BEGIN IMMEDIATE;");
            try {
                string up_sql = """
                    INSERT INTO spans (
                        span_id, file_path, line_start, line_end, byte_start, byte_end,
                        source_sha256, excerpt, domain, code_id, valence, entity_id,
                        coder_id, confidence, citation_key, source_uri, created_utc
                    ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
                    ON CONFLICT(span_id) DO UPDATE SET
                        file_path = excluded.file_path,
                        line_start = excluded.line_start,
                        line_end = excluded.line_end,
                        byte_start = excluded.byte_start,
                        byte_end = excluded.byte_end,
                        source_sha256 = excluded.source_sha256,
                        excerpt = excluded.excerpt,
                        domain = excluded.domain,
                        code_id = excluded.code_id,
                        valence = excluded.valence,
                        entity_id = excluded.entity_id,
                        coder_id = excluded.coder_id,
                        confidence = excluded.confidence,
                        citation_key = excluded.citation_key,
                        source_uri = excluded.source_uri;
                """;
                Sqlite.Statement up_stmt;
                if (db.prepare_v2 (up_sql, -1, out up_stmt) != Sqlite.OK) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }

                foreach (var sp in parsed) {
                    seen_ids.add (sp.span_id);
                    var prev = existing_map.get (sp.span_id);
                    if (prev != null) {
                        sp.created_utc = prev.created_utc;
                    }
                    string? prev_json = prev != null ? prev.to_json () : null;
                    string new_json = sp.to_json ();
                    if (prev_json != null && prev_json == new_json) {
                        continue;
                    }
                    up_stmt.reset ();
                    up_stmt.clear_bindings ();
                    bind_span_fields (up_stmt, sp);
                    if (up_stmt.step () != Sqlite.DONE) {
                        throw new QualDbError.QUERY_FAILED (db.errmsg ());
                    }
                    AuditLogger.record (
                        db,
                        user_id,
                        prev == null ? "CREATE_SPAN" : "UPDATE_SPAN",
                        "spans",
                        sp.span_id,
                        prev_json,
                        new_json,
                        rationale
                    );
                    any_change = true;
                }

                Sqlite.Statement del_stmt;
                if (db.prepare_v2 ("DELETE FROM spans WHERE span_id = ?1;", -1, out del_stmt) != Sqlite.OK) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }
                foreach (var ex in existing_list) {
                    if (!seen_ids.contains (ex.span_id)) {
                        del_stmt.reset ();
                        del_stmt.clear_bindings ();
                        del_stmt.bind_text (1, ex.span_id);
                        if (del_stmt.step () != Sqlite.DONE) {
                            throw new QualDbError.QUERY_FAILED (db.errmsg ());
                        }
                        AuditLogger.record (db, user_id, "DELETE_SPAN", "spans", ex.span_id, ex.to_json (), null, rationale);
                        any_change = true;
                    }
                }
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            if (any_change) {
                database_changed ();
            }
        }

        public Gee.ArrayList<QualSpan> list_spans (
            string? file_path = null,
            string? visible_only_to_coder = null,
            string? filter_code_id = null,
            string? filter_confidence = null
        ) {
            var res = new Gee.ArrayList<QualSpan> ();
            var sb = new GLib.StringBuilder ("""
                SELECT span_id, file_path, line_start, line_end, byte_start, byte_end,
                       source_sha256, excerpt, domain, code_id, valence, entity_id,
                       coder_id, confidence, citation_key, source_uri, created_utc
                FROM spans WHERE 1=1
            """);
            if (file_path != null && file_path != "") sb.append (" AND file_path = ?1");
            if (visible_only_to_coder != null && visible_only_to_coder != "") sb.append (" AND coder_id = ?2");
            if (filter_code_id != null && filter_code_id != "") sb.append (" AND code_id = ?3");
            if (filter_confidence != null && filter_confidence != "") sb.append (" AND confidence = ?4");
            sb.append (" ORDER BY file_path ASC, line_start ASC, byte_start ASC;");

            Sqlite.Statement stmt;
            if (db.prepare_v2 (sb.str, -1, out stmt) != Sqlite.OK) return res;
            if (file_path != null && file_path != "") stmt.bind_text (1, file_path);
            if (visible_only_to_coder != null && visible_only_to_coder != "") stmt.bind_text (2, visible_only_to_coder);
            if (filter_code_id != null && filter_code_id != "") stmt.bind_text (3, filter_code_id);
            if (filter_confidence != null && filter_confidence != "") stmt.bind_text (4, filter_confidence);

            while (stmt.step () == Sqlite.ROW) {
                res.add (row_to_span (stmt));
            }
            return res;
        }

        public Gee.HashMap<string, int> get_groundedness_counts (string? visible_only_to_coder = null) {
            var counts = new Gee.HashMap<string, int> ();
            string sql = (visible_only_to_coder != null && visible_only_to_coder != "")
                ? "SELECT code_id, COUNT(*) FROM spans WHERE coder_id = ?1 GROUP BY code_id;"
                : "SELECT code_id, COUNT(*) FROM spans GROUP BY code_id;";
            Sqlite.Statement stmt;
            if (db.prepare_v2 (sql, -1, out stmt) == Sqlite.OK) {
                if (visible_only_to_coder != null && visible_only_to_coder != "") {
                    stmt.bind_text (1, visible_only_to_coder);
                }
                while (stmt.step () == Sqlite.ROW) {
                    string cid = stmt.column_text (0) ?? "";
                    int cnt = stmt.column_int (1);
                    if (cid != "") counts.set (cid, cnt);
                }
            }
            return counts;
        }

        public Gee.HashMap<string, int> get_density_counts () {
            var density = new Gee.HashMap<string, int> ();
            string sql = """
                SELECT node, COUNT(*) FROM (
                    SELECT source_node AS node FROM network_edges
                    UNION ALL
                    SELECT target_node AS node FROM network_edges
                ) GROUP BY node;
            """;
            Sqlite.Statement stmt;
            if (db.prepare_v2 (sql, -1, out stmt) == Sqlite.OK) {
                while (stmt.step () == Sqlite.ROW) {
                    string nid = stmt.column_text (0) ?? "";
                    int cnt = stmt.column_int (1);
                    if (nid != "") density.set (nid, cnt);
                }
            }
            return density;
        }

        // =====================================================================
        // MEMOS CRUD (100% Audited)
        // =====================================================================
        public QualMemo? get_memo (string memo_id) {
            Sqlite.Statement stmt;
            if (db.prepare_v2 ("SELECT memo_id, target_id, author_id, body, created_utc FROM memos WHERE memo_id = ?1;", -1, out stmt) != Sqlite.OK) {
                return null;
            }
            stmt.bind_text (1, memo_id);
            if (stmt.step () == Sqlite.ROW) {
                var m = new QualMemo ();
                m.memo_id = stmt.column_text (0) ?? "";
                m.target_id = stmt.column_text (1) ?? "";
                m.author_id = stmt.column_text (2) ?? "";
                m.body = stmt.column_text (3) ?? "";
                m.created_utc = stmt.column_text (4) ?? "";
                return m;
            }
            return null;
        }

        public void upsert_memo (QualMemo memo, string user_id, string rationale = "Analytical memo saved") throws QualDbError {
            var existing = get_memo (memo.memo_id);
            string? prev_json = existing != null ? existing.to_json () : null;
            string new_json = memo.to_json ();
            string action = existing == null ? "CREATE_MEMO" : "UPDATE_MEMO";

            exec_raw ("BEGIN IMMEDIATE;");
            try {
                string sql = """
                    INSERT INTO memos (memo_id, target_id, author_id, body, created_utc)
                    VALUES (?1, ?2, ?3, ?4, ?5)
                    ON CONFLICT(memo_id) DO UPDATE SET
                        target_id = excluded.target_id,
                        author_id = excluded.author_id,
                        body = excluded.body;
                """;
                Sqlite.Statement stmt;
                if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                stmt.bind_text (1, memo.memo_id);
                stmt.bind_text (2, memo.target_id);
                stmt.bind_text (3, memo.author_id);
                stmt.bind_text (4, memo.body);
                stmt.bind_text (5, memo.created_utc);
                if (stmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                AuditLogger.record (db, user_id, action, "memos", memo.memo_id, prev_json, new_json, rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        public void delete_memo (string memo_id, string user_id, string rationale = "Memo deleted") throws QualDbError {
            var existing = get_memo (memo_id);
            if (existing == null) return;
            exec_raw ("BEGIN IMMEDIATE;");
            try {
                Sqlite.Statement stmt;
                if (db.prepare_v2 ("DELETE FROM memos WHERE memo_id = ?1;", -1, out stmt) != Sqlite.OK) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }
                stmt.bind_text (1, memo_id);
                if (stmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                AuditLogger.record (db, user_id, "DELETE_MEMO", "memos", memo_id, existing.to_json (), null, rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        public Gee.ArrayList<QualMemo> list_memos (string? target_id = null) {
            var res = new Gee.ArrayList<QualMemo> ();
            string sql = (target_id != null && target_id != "")
                ? "SELECT memo_id, target_id, author_id, body, created_utc FROM memos WHERE target_id = ?1 ORDER BY created_utc DESC;"
                : "SELECT memo_id, target_id, author_id, body, created_utc FROM memos ORDER BY created_utc DESC;";
            Sqlite.Statement stmt;
            if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) return res;
            if (target_id != null && target_id != "") stmt.bind_text (1, target_id);
            while (stmt.step () == Sqlite.ROW) {
                var m = new QualMemo ();
                m.memo_id = stmt.column_text (0) ?? "";
                m.target_id = stmt.column_text (1) ?? "";
                m.author_id = stmt.column_text (2) ?? "";
                m.body = stmt.column_text (3) ?? "";
                m.created_utc = stmt.column_text (4) ?? "";
                res.add (m);
            }
            return res;
        }

        // =====================================================================
        // NETWORK EDGES CRUD (100% Audited)
        // =====================================================================
        public QualNetworkEdge? get_edge (string edge_id) {
            Sqlite.Statement stmt;
            if (db.prepare_v2 ("SELECT edge_id, source_node, target_node, relation_type, weight, evidence_span_id FROM network_edges WHERE edge_id = ?1;", -1, out stmt) != Sqlite.OK) {
                return null;
            }
            stmt.bind_text (1, edge_id);
            if (stmt.step () == Sqlite.ROW) {
                var e = new QualNetworkEdge ();
                e.edge_id = stmt.column_text (0) ?? "";
                e.source_node = stmt.column_text (1) ?? "";
                e.target_node = stmt.column_text (2) ?? "";
                e.relation_type = stmt.column_text (3) ?? "co_occurs";
                e.weight = stmt.column_double (4);
                e.evidence_span_id = stmt.column_type (5) != Sqlite.NULL ? stmt.column_text (5) : null;
                return e;
            }
            return null;
        }

        public void upsert_edge (QualNetworkEdge edge, string user_id, string rationale = "Network edge updated") throws QualDbError {
            var existing = get_edge (edge.edge_id);
            string? prev_json = existing != null ? existing.to_json () : null;
            string new_json = edge.to_json ();
            string action = existing == null ? "CREATE_EDGE" : "UPDATE_EDGE";

            exec_raw ("BEGIN IMMEDIATE;");
            try {
                string sql = """
                    INSERT INTO network_edges (edge_id, source_node, target_node, relation_type, weight, evidence_span_id)
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                    ON CONFLICT(edge_id) DO UPDATE SET
                        source_node = excluded.source_node,
                        target_node = excluded.target_node,
                        relation_type = excluded.relation_type,
                        weight = excluded.weight,
                        evidence_span_id = excluded.evidence_span_id;
                """;
                Sqlite.Statement stmt;
                if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                stmt.bind_text (1, edge.edge_id);
                stmt.bind_text (2, edge.source_node);
                stmt.bind_text (3, edge.target_node);
                stmt.bind_text (4, edge.relation_type);
                stmt.bind_double (5, edge.weight);
                if (edge.evidence_span_id != null && edge.evidence_span_id != "") stmt.bind_text (6, edge.evidence_span_id); else stmt.bind_null (6);
                if (stmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                AuditLogger.record (db, user_id, action, "network_edges", edge.edge_id, prev_json, new_json, rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        public void delete_edge (string edge_id, string user_id, string rationale = "Edge deleted") throws QualDbError {
            var existing = get_edge (edge_id);
            if (existing == null) return;
            exec_raw ("BEGIN IMMEDIATE;");
            try {
                Sqlite.Statement stmt;
                if (db.prepare_v2 ("DELETE FROM network_edges WHERE edge_id = ?1;", -1, out stmt) != Sqlite.OK) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }
                stmt.bind_text (1, edge_id);
                if (stmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                AuditLogger.record (db, user_id, "DELETE_EDGE", "network_edges", edge_id, existing.to_json (), null, rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        public Gee.ArrayList<QualNetworkEdge> list_edges () {
            var res = new Gee.ArrayList<QualNetworkEdge> ();
            Sqlite.Statement stmt;
            if (db.prepare_v2 ("SELECT edge_id, source_node, target_node, relation_type, weight, evidence_span_id FROM network_edges;", -1, out stmt) != Sqlite.OK) {
                return res;
            }
            while (stmt.step () == Sqlite.ROW) {
                var e = new QualNetworkEdge ();
                e.edge_id = stmt.column_text (0) ?? "";
                e.source_node = stmt.column_text (1) ?? "";
                e.target_node = stmt.column_text (2) ?? "";
                e.relation_type = stmt.column_text (3) ?? "co_occurs";
                e.weight = stmt.column_double (4);
                e.evidence_span_id = stmt.column_type (5) != Sqlite.NULL ? stmt.column_text (5) : null;
                res.add (e);
            }
            return res;
        }

        // =====================================================================
        // CRA REVIEW QUERIES & AI SUGGESTIONS (100% Audited)
        // =====================================================================
        public QualReviewQuery? get_review_query (string query_id) {
            Sqlite.Statement stmt;
            if (db.prepare_v2 ("SELECT query_id, span_id, raised_by, status, message, resolution_note, updated_utc FROM review_queries WHERE query_id = ?1;", -1, out stmt) != Sqlite.OK) {
                return null;
            }
            stmt.bind_text (1, query_id);
            if (stmt.step () == Sqlite.ROW) {
                var q = new QualReviewQuery ();
                q.query_id = stmt.column_text (0) ?? "";
                q.span_id = stmt.column_text (1) ?? "";
                q.raised_by = stmt.column_text (2) ?? "";
                q.status = stmt.column_text (3) ?? "Open";
                q.message = stmt.column_text (4) ?? "";
                q.resolution_note = stmt.column_type (5) != Sqlite.NULL ? stmt.column_text (5) : null;
                q.updated_utc = stmt.column_text (6) ?? "";
                return q;
            }
            return null;
        }

        public void upsert_review_query (QualReviewQuery q, string user_id, string rationale = "CRA query updated") throws QualDbError {
            q.updated_utc = QualSpan.now_iso8601_utc ();
            var existing = get_review_query (q.query_id);
            string? prev_json = existing != null ? existing.to_json () : null;
            string new_json = q.to_json ();
            string action = existing == null ? "RAISE_CRA_QUERY" : "UPDATE_CRA_QUERY";

            exec_raw ("BEGIN IMMEDIATE;");
            try {
                string sql = """
                    INSERT INTO review_queries (query_id, span_id, raised_by, status, message, resolution_note, updated_utc)
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                    ON CONFLICT(query_id) DO UPDATE SET
                        status = excluded.status,
                        message = excluded.message,
                        resolution_note = excluded.resolution_note,
                        updated_utc = excluded.updated_utc;
                """;
                Sqlite.Statement stmt;
                if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                stmt.bind_text (1, q.query_id);
                if (q.span_id != "") stmt.bind_text (2, q.span_id); else stmt.bind_null (2);
                stmt.bind_text (3, q.raised_by);
                stmt.bind_text (4, q.status);
                stmt.bind_text (5, q.message);
                if (q.resolution_note != null) stmt.bind_text (6, q.resolution_note); else stmt.bind_null (6);
                stmt.bind_text (7, q.updated_utc);
                if (stmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                AuditLogger.record (db, user_id, action, "review_queries", q.query_id, prev_json, new_json, rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        public Gee.ArrayList<QualReviewQuery> list_review_queries (string? span_id = null) {
            var res = new Gee.ArrayList<QualReviewQuery> ();
            string sql = (span_id != null && span_id != "")
                ? "SELECT query_id, span_id, raised_by, status, message, resolution_note, updated_utc FROM review_queries WHERE span_id = ?1 ORDER BY updated_utc DESC;"
                : "SELECT query_id, span_id, raised_by, status, message, resolution_note, updated_utc FROM review_queries ORDER BY updated_utc DESC;";
            Sqlite.Statement stmt;
            if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) return res;
            if (span_id != null && span_id != "") stmt.bind_text (1, span_id);
            while (stmt.step () == Sqlite.ROW) {
                var q = new QualReviewQuery ();
                q.query_id = stmt.column_text (0) ?? "";
                q.span_id = stmt.column_text (1) ?? "";
                q.raised_by = stmt.column_text (2) ?? "";
                q.status = stmt.column_text (3) ?? "Open";
                q.message = stmt.column_text (4) ?? "";
                q.resolution_note = stmt.column_type (5) != Sqlite.NULL ? stmt.column_text (5) : null;
                q.updated_utc = stmt.column_text (6) ?? "";
                res.add (q);
            }
            return res;
        }

        public void queue_ai_suggestion (QualAiSuggestion sug, string user_id = "elrond-ai") throws QualDbError {
            sug.status = "Pending Review";
            exec_raw ("BEGIN IMMEDIATE;");
            try {
                string sql = """
                    INSERT INTO ai_suggestions (
                        suggestion_id, file_path, line_start, line_end, excerpt,
                        domain, suggested_code_id, entity_id, confidence, valence,
                        rationale, status, created_utc
                    ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13);
                """;
                Sqlite.Statement stmt;
                if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                stmt.bind_text (1, sug.suggestion_id);
                stmt.bind_text (2, sug.file_path);
                stmt.bind_int (3, sug.line_start);
                stmt.bind_int (4, sug.line_end);
                stmt.bind_text (5, sug.excerpt);
                stmt.bind_text (6, sug.domain);
                stmt.bind_text (7, sug.suggested_code_id);
                if (sug.entity_id != null && sug.entity_id != "") stmt.bind_text (8, sug.entity_id); else stmt.bind_null (8);
                stmt.bind_text (9, sug.confidence);
                stmt.bind_text (10, sug.valence);
                stmt.bind_text (11, sug.rationale);
                stmt.bind_text (12, sug.status);
                stmt.bind_text (13, sug.created_utc);
                if (stmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                AuditLogger.record (db, user_id, "QUEUE_AI_SUGGESTION", "ai_suggestions", sug.suggestion_id, null, sug.to_json (), sug.rationale);
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
        }

        public Gee.ArrayList<QualAiSuggestion> list_ai_suggestions (string? status_filter = "Pending Review") {
            var res = new Gee.ArrayList<QualAiSuggestion> ();
            string sql = (status_filter != null && status_filter != "")
                ? "SELECT suggestion_id, file_path, line_start, line_end, excerpt, domain, suggested_code_id, entity_id, confidence, valence, rationale, status, created_utc FROM ai_suggestions WHERE status = ?1 ORDER BY created_utc DESC;"
                : "SELECT suggestion_id, file_path, line_start, line_end, excerpt, domain, suggested_code_id, entity_id, confidence, valence, rationale, status, created_utc FROM ai_suggestions ORDER BY created_utc DESC;";
            Sqlite.Statement stmt;
            if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) return res;
            if (status_filter != null && status_filter != "") stmt.bind_text (1, status_filter);
            while (stmt.step () == Sqlite.ROW) {
                var s = new QualAiSuggestion ();
                s.suggestion_id = stmt.column_text (0) ?? "";
                s.file_path = stmt.column_text (1) ?? "";
                s.line_start = stmt.column_int (2);
                s.line_end = stmt.column_int (3);
                s.excerpt = stmt.column_text (4) ?? "";
                s.domain = stmt.column_text (5) ?? "protein";
                s.suggested_code_id = stmt.column_text (6) ?? "";
                s.entity_id = stmt.column_type (7) != Sqlite.NULL ? stmt.column_text (7) : null;
                s.confidence = stmt.column_text (8) ?? "moderate";
                s.valence = stmt.column_text (9) ?? "neutral";
                s.rationale = stmt.column_text (10) ?? "";
                s.status = stmt.column_text (11) ?? "Pending Review";
                s.created_utc = stmt.column_text (12) ?? "";
                res.add (s);
            }
            return res;
        }

        public QualSpan? adjudicate_ai_suggestion (
            string suggestion_id,
            bool approve,
            string human_reviewer_id,
            string doc_text,
            string rationale = "Human adjudication of Elrond AI suggestion",
            QualSpan? prebuilt_span = null
        ) throws QualDbError {
            QualAiSuggestion? target = null;
            foreach (var s in list_ai_suggestions ("Pending Review")) {
                if (s.suggestion_id == suggestion_id) {
                    target = s;
                    break;
                }
            }
            if (target == null || target.status != "Pending Review") return null;

            string prev_json = target.to_json ();
            target.status = approve ? "Approved" : "Rejected";
            string new_json = target.to_json ();

            exec_raw ("BEGIN IMMEDIATE;");
            QualSpan? created_span = null;
            try {
                Sqlite.Statement ustmt;
                if (db.prepare_v2 ("UPDATE ai_suggestions SET status = ?1 WHERE suggestion_id = ?2;", -1, out ustmt) != Sqlite.OK) {
                    throw new QualDbError.QUERY_FAILED (db.errmsg ());
                }
                ustmt.bind_text (1, target.status);
                ustmt.bind_text (2, suggestion_id);
                if (ustmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                AuditLogger.record (
                    db,
                    human_reviewer_id,
                    approve ? "APPROVE_AI_SUGGESTION" : "REJECT_AI_SUGGESTION",
                    "ai_suggestions",
                    suggestion_id,
                    prev_json,
                    new_json,
                    rationale
                );

                if (approve) {
                    QualSpan span;
                    if (prebuilt_span != null) {
                        span = prebuilt_span;
                    } else {
                        span = new QualSpan ();
                        span.span_id = QualSpan.generate_short_id ();
                        span.file_path = target.file_path;
                        span.line_start = target.line_start;
                        span.line_end = target.line_end;
                        span.excerpt = target.excerpt;
                        span.domain = target.domain;
                        span.code_id = target.suggested_code_id;
                        span.entity_id = target.entity_id;
                        span.coder_id = human_reviewer_id;
                        span.confidence = target.confidence;
                        span.valence = target.valence;
                        string slice = QualSpanParser.extract_lines_slice (doc_text, span.line_start, span.line_end);
                        span.source_sha256 = QualSpanParser.compute_sha256 (slice != "" ? slice : span.excerpt);
                    }

                    string sp_sql = """
                        INSERT INTO spans (
                            span_id, file_path, line_start, line_end, byte_start, byte_end,
                            source_sha256, excerpt, domain, code_id, valence, entity_id,
                            coder_id, confidence, citation_key, source_uri, created_utc
                        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17);
                    """;
                    Sqlite.Statement sp_stmt;
                    if (db.prepare_v2 (sp_sql, -1, out sp_stmt) != Sqlite.OK) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                    bind_span_fields (sp_stmt, span);
                    if (sp_stmt.step () != Sqlite.DONE) throw new QualDbError.QUERY_FAILED (db.errmsg ());
                    AuditLogger.record (db, human_reviewer_id, "CREATE_SPAN_FROM_AI", "spans", span.span_id, null, span.to_json (), rationale);
                    created_span = span;
                }
                exec_raw ("COMMIT;");
            } catch (QualDbError e) {
                try { exec_raw ("ROLLBACK;"); } catch (QualDbError re) {}
                throw e;
            }
            database_changed ();
            return created_span;
        }

        // =====================================================================
        // AUDIT TRAIL INSPECTION & IMMUTABILITY VERIFICATION
        // =====================================================================
        public Gee.ArrayList<QualAuditEntry> list_audit_log (int limit = 250) {
            var res = new Gee.ArrayList<QualAuditEntry> ();
            string sql = """
                SELECT log_id, timestamp_utc, user_id, action, target_table, target_id,
                       previous_json, new_json, rationale
                FROM audit_log ORDER BY log_id DESC LIMIT ?1;
            """;
            Sqlite.Statement stmt;
            if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) return res;
            stmt.bind_int (1, limit);
            while (stmt.step () == Sqlite.ROW) {
                var a = new QualAuditEntry ();
                a.log_id = stmt.column_int64 (0);
                a.timestamp_utc = stmt.column_text (1) ?? "";
                a.user_id = stmt.column_text (2) ?? "";
                a.action = stmt.column_text (3) ?? "";
                a.target_table = stmt.column_text (4) ?? "";
                a.target_id = stmt.column_text (5) ?? "";
                a.previous_json = stmt.column_type (6) != Sqlite.NULL ? stmt.column_text (6) : null;
                a.new_json = stmt.column_type (7) != Sqlite.NULL ? stmt.column_text (7) : null;
                a.rationale = stmt.column_type (8) != Sqlite.NULL ? stmt.column_text (8) : null;
                res.add (a);
            }
            return res;
        }

        /**
         * Exposed solely so compliance tests can verify that tampering with audit_log
         * triggers QualDbError.IMMUTABILITY_VIOLATION via SQLite triggers.
         */
        public void attempt_raw_sql_for_audit_test (string sql) throws QualDbError {
            exec_raw (sql);
        }
    }
}
