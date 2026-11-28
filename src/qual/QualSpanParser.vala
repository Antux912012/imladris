// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Qual {

    /**
     * Lossless parser and serializer for Pandoc/Quarto {.qual ...} bracketed spans.
     * Preserves surrounding Markdown, Quarto chunks, YAML frontmatter, and citations.
     * Skips fenced code blocks and inline code backticks so source code is never altered.
     */
    public class QualSpanParser : GLib.Object {

        public static string compute_sha256 (string text) {
            return GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA256, text);
        }

        public static string extract_lines_slice (string doc_text, int line_start, int line_end) {
            string[] lines = doc_text.split ("\n");
            if (lines.length == 0) return "";
            int s = (line_start - 1).clamp (0, lines.length - 1);
            int e = (line_end - 1).clamp (s, lines.length - 1);
            var sb = new GLib.StringBuilder ();
            for (int i = s; i <= e; i++) {
                if (i > s) sb.append_c ('\n');
                sb.append (lines[i]);
            }
            return sb.str;
        }

        public static SdvStatus verify_span_sdv (QualSpan span, string doc_text) {
            if (span.source_sha256 == "") return SdvStatus.UNVERIFIED;
            string current_slice = extract_lines_slice (doc_text, span.line_start, span.line_end);
            if (current_slice == "") return SdvStatus.MODIFIED;
            string current_hash = compute_sha256 (current_slice);
            return (current_hash == span.source_sha256) ? SdvStatus.VERIFIED : SdvStatus.MODIFIED;
        }

        private class ProtectedRange {
            public int start;
            public int end;
            public ProtectedRange (int s, int e) {
                this.start = s;
                this.end = e;
            }
        }

        private static Gee.ArrayList<ProtectedRange> find_code_ranges (string doc) {
            var ranges = new Gee.ArrayList<ProtectedRange> ();
            int len = doc.length;
            int i = 0;
            bool at_line_start = true;

            // Protect leading YAML frontmatter (--- ... --- or --- ... ...)
            if (doc.has_prefix ("---\n") || doc.has_prefix ("---\r\n")) {
                int cur_fm = doc.index_of_char ('\n', 0) + 1;
                while (cur_fm < len) {
                    int next_nl = doc.index_of_char ('\n', cur_fm);
                    string ln = (next_nl >= 0 ? doc.substring (cur_fm, next_nl - cur_fm) : doc.substring (cur_fm)).strip ();
                    if (ln == "---" || ln == "...") {
                        int fm_end = (next_nl >= 0) ? next_nl + 1 : len;
                        ranges.add (new ProtectedRange (0, fm_end));
                        i = fm_end;
                        break;
                    }
                    if (next_nl < 0) break;
                    cur_fm = next_nl + 1;
                }
            }

            while (i < len) {
                char c = doc[i];
                if (at_line_start) {
                    int p = i;
                    while (p < len && (doc[p] == ' ' || doc[p] == '\t')) p++;
                    if (p + 2 < len && ((doc[p] == '`' && doc[p + 1] == '`' && doc[p + 2] == '`') ||
                                        (doc[p] == '~' && doc[p + 1] == '~' && doc[p + 2] == '~'))) {
                        char fence_char = doc[p];
                        int fence_len = 0;
                        while (p + fence_len < len && doc[p + fence_len] == fence_char) fence_len++;
                        int fence_start = i;
                        int nl = doc.index_of_char ('\n', p + fence_len);
                        if (nl < 0) {
                            ranges.add (new ProtectedRange (fence_start, len));
                            break;
                        }
                        int cur = nl + 1;
                        int fence_end = len;
                        while (cur < len) {
                            int q = cur;
                            while (q < len && (doc[q] == ' ' || doc[q] == '\t')) q++;
                            int close_cnt = 0;
                            while (q + close_cnt < len && doc[q + close_cnt] == fence_char) close_cnt++;
                            int next_nl = doc.index_of_char ('\n', cur);
                            if (close_cnt >= fence_len) {
                                int after = q + close_cnt;
                                while (after < len && (doc[after] == ' ' || doc[after] == '\t' || doc[after] == '\r')) after++;
                                if (after >= len || doc[after] == '\n') {
                                    fence_end = (next_nl >= 0) ? next_nl + 1 : len;
                                    break;
                                }
                            }
                            if (next_nl < 0) break;
                            cur = next_nl + 1;
                        }
                        ranges.add (new ProtectedRange (fence_start, fence_end));
                        i = fence_end;
                        at_line_start = true;
                        continue;
                    }
                }

                if (c == '`') {
                    int tick_start = i;
                    int tick_len = 0;
                    while (i < len && doc[i] == '`') {
                        tick_len++;
                        i++;
                    }
                    int close_pos = -1;
                    int search = i;
                    while (search < len) {
                        if (doc[search] == '`') {
                            int cnt = 0;
                            int s2 = search;
                            while (s2 < len && doc[s2] == '`') {
                                cnt++;
                                s2++;
                            }
                            if (cnt == tick_len) {
                                close_pos = s2;
                                break;
                            }
                            search = s2;
                            continue;
                        }
                        if (doc[search] == '\n' && search + 1 < len && doc[search + 1] == '\n') {
                            break;
                        }
                        search++;
                    }
                    if (close_pos > 0) {
                        ranges.add (new ProtectedRange (tick_start, close_pos));
                        i = close_pos;
                        at_line_start = false;
                        continue;
                    }
                    continue;
                }

                at_line_start = (c == '\n');
                i++;
            }
            return ranges;
        }

        private static bool is_in_protected_range (int pos, Gee.ArrayList<ProtectedRange> ranges) {
            foreach (var r in ranges) {
                if (pos >= r.start && pos < r.end) return true;
                if (r.start > pos) break;
            }
            return false;
        }

        private static int[] build_line_offsets (string doc) {
            var starts = new Gee.ArrayList<int> ();
            starts.add (0);
            for (int i = 0; i < doc.length; i++) {
                if (doc[i] == '\n') {
                    starts.add (i + 1);
                }
            }
            int[] arr = new int[starts.size];
            for (int i = 0; i < starts.size; i++) arr[i] = starts[i];
            return arr;
        }

        private static int byte_to_line_1based (int byte_offset, int[] line_offsets) {
            int lo = 0;
            int hi = line_offsets.length - 1;
            while (lo <= hi) {
                int mid = (lo + hi) / 2;
                if (line_offsets[mid] <= byte_offset) {
                    lo = mid + 1;
                } else {
                    hi = mid - 1;
                }
            }
            return int.max (1, hi + 1);
        }

        private static bool try_match_span_at (
            string doc,
            int open_bracket_pos,
            out int full_end_pos,
            out string excerpt,
            out string attr_block
        ) {
            full_end_pos = -1;
            excerpt = "";
            attr_block = "";
            int len = doc.length;
            if (open_bracket_pos < 0 || open_bracket_pos >= len || doc[open_bracket_pos] != '[') {
                return false;
            }
            if (open_bracket_pos > 0 && (doc[open_bracket_pos - 1] == '\\' || doc[open_bracket_pos - 1] == '!')) {
                return false;
            }

            int depth = 0;
            int i = open_bracket_pos;
            int close_bracket_pos = -1;
            while (i < len) {
                char c = doc[i];
                if (c == '\\' && i + 1 < len) {
                    i += 2;
                    continue;
                }
                if (c == '[') {
                    depth++;
                } else if (c == ']') {
                    depth--;
                    if (depth == 0) {
                        close_bracket_pos = i;
                        break;
                    }
                }
                i++;
            }
            if (close_bracket_pos < 0 || close_bracket_pos + 1 >= len || doc[close_bracket_pos + 1] != '{') {
                return false;
            }

            int brace_open = close_bracket_pos + 1;
            int j = brace_open + 1;
            bool in_quote = false;
            char quote_char = '"';
            int brace_close = -1;
            while (j < len) {
                char c = doc[j];
                if (in_quote) {
                    if (c == '\\' && j + 1 < len) {
                        j += 2;
                        continue;
                    }
                    if (c == quote_char) {
                        in_quote = false;
                    }
                } else {
                    if (c == '"' || c == '\'') {
                        in_quote = true;
                        quote_char = c;
                    } else if (c == '}') {
                        brace_close = j;
                        break;
                    } else if (c == '\n') {
                        return false;
                    }
                }
                j++;
            }
            if (brace_close < 0) return false;

            string raw_attrs = doc.substring (brace_open + 1, brace_close - brace_open - 1).strip ();
            if (!has_qual_class (raw_attrs)) {
                return false;
            }

            excerpt = doc.substring (open_bracket_pos + 1, close_bracket_pos - open_bracket_pos - 1);
            attr_block = raw_attrs;
            full_end_pos = brace_close + 1;
            return true;
        }

        private static bool has_qual_class (string raw_attrs) {
            int i = 0;
            int len = raw_attrs.length;
            while (i < len) {
                while (i < len && raw_attrs[i].isspace ()) i++;
                if (i >= len) break;
                if (raw_attrs[i] == '.') {
                    int s = i + 1;
                    int e = s;
                    while (e < len && !raw_attrs[e].isspace () && raw_attrs[e] != '=' && raw_attrs[e] != '}') e++;
                    if (raw_attrs.substring (s, e - s) == "qual") {
                        return true;
                    }
                    i = e;
                } else {
                    bool in_q = false;
                    char qc = '"';
                    while (i < len) {
                        char c = raw_attrs[i];
                        if (in_q) {
                            if (c == '\\' && i + 1 < len) { i += 2; continue; }
                            if (c == qc) in_q = false;
                        } else {
                            if (c == '"' || c == '\'') { in_q = true; qc = c; }
                            else if (c.isspace ()) break;
                        }
                        i++;
                    }
                }
            }
            return false;
        }

        private static void parse_attributes (string raw_attrs, QualSpan span) {
            int i = 0;
            int len = raw_attrs.length;
            while (i < len) {
                while (i < len && raw_attrs[i].isspace ()) i++;
                if (i >= len) break;

                if (raw_attrs[i] == '.') {
                    int s = i;
                    while (i < len && !raw_attrs[i].isspace ()) i++;
                    string cls = raw_attrs.substring (s, i - s);
                    if (cls != ".qual") {
                        span.extra_attrs.set ("class:" + cls, "true");
                    }
                    continue;
                }
                if (raw_attrs[i] == '#') {
                    int s = i + 1;
                    i++;
                    while (i < len && !raw_attrs[i].isspace ()) i++;
                    span.span_id = raw_attrs.substring (s, i - s);
                    continue;
                }

                int key_start = i;
                while (i < len && !raw_attrs[i].isspace () && raw_attrs[i] != '=') i++;
                string key = raw_attrs.substring (key_start, i - key_start).strip ();
                while (i < len && raw_attrs[i].isspace ()) i++;
                if (i >= len || raw_attrs[i] != '=') continue;
                i++; // skip '='
                while (i < len && raw_attrs[i].isspace ()) i++;
                if (i >= len) break;

                string val = "";
                if (raw_attrs[i] == '"' || raw_attrs[i] == '\'') {
                    char qc = raw_attrs[i];
                    i++;
                    var vb = new GLib.StringBuilder ();
                    while (i < len) {
                        char c = raw_attrs[i];
                        if (c == '\\' && i + 1 < len) {
                            char next = raw_attrs[i + 1];
                            if (next == qc || next == '\\') {
                                vb.append_c (next);
                                i += 2;
                                continue;
                            }
                        }
                        if (c == qc) {
                            i++;
                            break;
                        }
                        vb.append_c (c);
                        i++;
                    }
                    val = vb.str;
                } else {
                    int vs = i;
                    while (i < len && !raw_attrs[i].isspace ()) i++;
                    val = raw_attrs.substring (vs, i - vs);
                }

                switch (key) {
                    case "id":
                        span.span_id = val;
                        break;
                    case "domain":
                        span.domain = val;
                        break;
                    case "code":
                        span.code_id = val;
                        break;
                    case "valence":
                        span.valence = val;
                        break;
                    case "entity":
                        span.entity_id = val != "" ? val : null;
                        break;
                    case "coder":
                        span.coder_id = val;
                        break;
                    case "confidence":
                        span.confidence = val != "" ? val : null;
                        break;
                    case "ref":
                        span.citation_key = val != "" ? val : null;
                        break;
                    case "uri":
                        span.source_uri = val != "" ? val : null;
                        break;
                    case "created":
                        span.created_utc = val;
                        break;
                    default:
                        if (key != "") {
                            span.extra_attrs.set (key, val);
                        }
                        break;
                }
            }
            if (span.span_id == "") {
                span.span_id = QualSpan.generate_short_id ();
            }
        }

        public static Gee.ArrayList<QualSpan> parse_document (string doc_text, string file_path = "") {
            var spans = new Gee.ArrayList<QualSpan> ();
            if (doc_text.length == 0 || !doc_text.contains (".qual")) {
                return spans;
            }

            var protected_ranges = find_code_ranges (doc_text);
            int[] line_offsets = build_line_offsets (doc_text);
            int len = doc_text.length;
            int i = 0;

            while (i < len) {
                if (doc_text[i] == '[' && !is_in_protected_range (i, protected_ranges)) {
                    int end_pos;
                    string excerpt;
                    string attr_block;
                    if (try_match_span_at (doc_text, i, out end_pos, out excerpt, out attr_block)) {
                        var span = new QualSpan ();
                        span.file_path = file_path;
                        span.byte_start = i;
                        span.byte_end = end_pos;
                        span.excerpt = excerpt;
                        span.line_start = byte_to_line_1based (i, line_offsets);
                        span.line_end = byte_to_line_1based (int.max (i, end_pos - 1), line_offsets);
                        parse_attributes (attr_block, span);
                        string slice = extract_lines_slice (doc_text, span.line_start, span.line_end);
                        span.source_sha256 = compute_sha256 (slice);
                        spans.add (span);
                        i = end_pos;
                        continue;
                    }
                }
                i++;
            }
            return spans;
        }

        private static string escape_attr (string val) {
            return val.replace ("\\", "\\\\").replace ("\"", "\\\"").replace ("\n", " ").replace ("\r", " ");
        }

        public static string serialize_span (QualSpan span) {
            string id = span.span_id != "" ? span.span_id : QualSpan.generate_short_id ();
            var sb = new GLib.StringBuilder ();
            sb.append_c ('[');
            sb.append (span.excerpt);
            sb.append ("]{.qual");
            sb.append_printf (" id=\"%s\"", escape_attr (id));
            if (span.domain != "") {
                sb.append_printf (" domain=\"%s\"", escape_attr (span.domain));
            }
            if (span.code_id != "") {
                sb.append_printf (" code=\"%s\"", escape_attr (span.code_id));
            }
            if (span.valence != "") {
                sb.append_printf (" valence=\"%s\"", escape_attr (span.valence));
            }
            if (span.entity_id != null && span.entity_id != "") {
                sb.append_printf (" entity=\"%s\"", escape_attr (span.entity_id));
            }
            if (span.coder_id != "") {
                sb.append_printf (" coder=\"%s\"", escape_attr (span.coder_id));
            }
            if (span.confidence != null && span.confidence != "") {
                sb.append_printf (" confidence=\"%s\"", escape_attr (span.confidence));
            }
            if (span.citation_key != null && span.citation_key != "") {
                sb.append_printf (" ref=\"%s\"", escape_attr (span.citation_key));
            }
            if (span.source_uri != null && span.source_uri != "") {
                sb.append_printf (" uri=\"%s\"", escape_attr (span.source_uri));
            }
            var extra_keys = new Gee.ArrayList<string> ();
            foreach (var k in span.extra_attrs.keys) extra_keys.add (k);
            extra_keys.sort ();
            foreach (string k in extra_keys) {
                if (k.has_prefix ("class:")) {
                    sb.append_c (' ');
                    sb.append (k.substring (6));
                } else {
                    sb.append_printf (" %s=\"%s\"", k, escape_attr (span.extra_attrs.get (k)));
                }
            }
            sb.append_c ('}');
            return sb.str;
        }

        public static string apply_span_at_offsets (string doc_text, int byte_start, int byte_end, QualSpan span) {
            int s = byte_start.clamp (0, doc_text.length);
            int e = byte_end.clamp (s, doc_text.length);
            span.excerpt = doc_text.substring (s, e - s);
            if (span.span_id == "") {
                span.span_id = QualSpan.generate_short_id ();
            }
            string serialized = serialize_span (span);
            string updated = doc_text.substring (0, s) + serialized + doc_text.substring (e);

            int[] line_offsets = build_line_offsets (updated);
            span.byte_start = s;
            span.byte_end = s + serialized.length;
            span.line_start = byte_to_line_1based (s, line_offsets);
            span.line_end = byte_to_line_1based (int.max (s, span.byte_end - 1), line_offsets);
            span.source_sha256 = compute_sha256 (extract_lines_slice (updated, span.line_start, span.line_end));
            return updated;
        }

        /**
         * Updates an existing span in-place or unwraps it back to plain text when replacement is null.
         */
        public static string update_or_remove_span_by_id (string doc_text, string target_span_id, QualSpan? replacement) {
            var spans = parse_document (doc_text);
            foreach (var sp in spans) {
                if (sp.span_id == target_span_id) {
                    string repl_str = (replacement != null) ? serialize_span (replacement) : sp.excerpt;
                    return doc_text.substring (0, sp.byte_start) + repl_str + doc_text.substring (sp.byte_end);
                }
            }
            return doc_text;
        }

        /**
         * Strips .qual span wrappers while preserving inner prose verbatim.
         * If visible_only_to_coder is non-null, spans belonging to visible_only_to_coder remain intact
         * while all other coders' spans are unwrapped (Blinded Dual-Coding view/preview).
         */
        public static string strip_qual_spans (string doc_text, string? visible_only_to_coder = null) {
            if (!doc_text.contains (".qual")) return doc_text;
            var spans = parse_document (doc_text);
            if (spans.size == 0) return doc_text;

            var sb = new GLib.StringBuilder ();
            int cursor = 0;
            foreach (var sp in spans) {
                sb.append (doc_text.substring (cursor, sp.byte_start - cursor));
                if (visible_only_to_coder != null && sp.coder_id == visible_only_to_coder) {
                    sb.append (doc_text.substring (sp.byte_start, sp.byte_end - sp.byte_start));
                } else {
                    sb.append (sp.excerpt);
                }
                cursor = sp.byte_end;
            }
            sb.append (doc_text.substring (cursor));
            return sb.str;
        }

        public static int find_unannotated_excerpt_offset (string doc_text, string excerpt, int line_start, int line_end) {
            if (doc_text == "" || excerpt == "") return -1;
            var protected_ranges = find_code_ranges (doc_text);
            foreach (var sp in parse_document (doc_text)) {
                protected_ranges.add (new ProtectedRange (sp.byte_start, sp.byte_end));
            }
            protected_ranges.sort ((a, b) => a.start - b.start);

            int[] line_offsets = build_line_offsets (doc_text);
            if (line_offsets.length > 0 && line_start >= 1) {
                int s_line = int.min (line_start, line_offsets.length) - 1;
                int e_line = int.min (int.max (line_start, line_end), line_offsets.length) - 1;
                int search_from = line_offsets[s_line];
                int search_to = (e_line + 1 < line_offsets.length) ? line_offsets[e_line + 1] : doc_text.length;
                int pos = search_from;
                while (pos < search_to) {
                    int hit = doc_text.index_of (excerpt, pos);
                    if (hit < 0 || hit >= search_to) break;
                    if (!is_in_protected_range (hit, protected_ranges)) {
                        return hit;
                    }
                    pos = hit + 1;
                }
            }

            int gpos = 0;
            while (gpos < doc_text.length) {
                int hit = doc_text.index_of (excerpt, gpos);
                if (hit < 0) break;
                if (!is_in_protected_range (hit, protected_ranges)) {
                    return hit;
                }
                gpos = hit + 1;
            }
            return -1;
        }

        /**
         * Formats inline .qual spans as styled HTML badges for WebKitGTK Live Preview.
         */
        public static string render_inline_html_spans (string line, string? blinded_current_user = null) {
            if (!line.contains (".qual")) return GLib.Markup.escape_text (line);
            var spans = parse_document (line);
            if (spans.size == 0) return GLib.Markup.escape_text (line);

            var sb = new GLib.StringBuilder ();
            int cursor = 0;
            foreach (var sp in spans) {
                sb.append (GLib.Markup.escape_text (line.substring (cursor, sp.byte_start - cursor)));
                if (blinded_current_user != null && sp.coder_id != blinded_current_user) {
                    sb.append (GLib.Markup.escape_text (sp.excerpt));
                } else {
                    string code_lbl = GLib.Markup.escape_text (sp.code_id != "" ? sp.code_id : "qual");
                    string coder_lbl = GLib.Markup.escape_text (sp.coder_id != "" ? sp.coder_id : "coder");
                    sb.append_printf (
                        "<mark class=\"qual-inline-mark\" data-span-id=\"%s\" title=\"Code: %s | Coder: %s\">%s <sup class=\"qual-inline-badge\">%s</sup></mark>",
                        GLib.Markup.escape_text (sp.span_id),
                        code_lbl,
                        coder_lbl,
                        GLib.Markup.escape_text (sp.excerpt),
                        code_lbl
                    );
                }
                cursor = sp.byte_end;
            }
            sb.append (GLib.Markup.escape_text (line.substring (cursor)));
            return sb.str;
        }
    }
}
