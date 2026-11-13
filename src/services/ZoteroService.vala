// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Gee;
using Soup;
using Json;

namespace Imladris.Services {

    public class CitationItem : GLib.Object {
        public string citekey { get; set; default = ""; }
        public string title { get; set; default = ""; }
        public string authors { get; set; default = ""; }
        public string year { get; set; default = ""; }
        public string? abstract_text { get; set; default = null; }
        public string source { get; set; default = "zotero-local"; }

        public CitationItem (string citekey, string title, string authors, string year, string? abstract_text = null, string source = "zotero-local") {
            this.citekey = citekey;
            this.title = title;
            this.authors = authors;
            this.year = year;
            this.abstract_text = abstract_text;
            this.source = source;
        }
    }

    public class ZoteroService : GLib.Object {
        private static ZoteroService? instance = null;
        private string base_url = "http://127.0.0.1:23119";
        private Soup.Session session;

        public static ZoteroService get_default () {
            if (instance == null) {
                instance = new ZoteroService ();
            }
            return instance;
        }

        private static GLib.Regex? reg_year_cache = null;
        private static GLib.Regex? reg_yaml_cache = null;
        private static GLib.Regex? reg_bib_check_cache = null;
        private static GLib.Regex? reg_entry_cache = null;

        public ZoteroService () {
            session = new Soup.Session () {
                timeout = 2
            };
        }

        /**
         * Checks if the Zotero desktop client is running.
         */
        public async bool is_zotero_running_async () {
            try {
                var msg = new Soup.Message ("GET", @"$base_url/connector/ping");
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 200 && bytes != null) {
                    string txt = Core.PlatformUtils.bytes_to_string (bytes);
                    return "Zotero is running" in txt;
                }
            } catch (GLib.Error e) {
                // Offline
            }
            return false;
        }

        /**
         * Checks if the Better BibTeX (BBT) plugin is active inside Zotero.
         */
        public async bool is_better_bibtex_available_async () {
            try {
                var msg = new Soup.Message ("POST", @"$base_url/better-bibtex/json-rpc");
                msg.request_headers.append ("Content-Type", "application/json");
                string body = "{\"jsonrpc\":\"2.0\",\"method\":\"item.search\",\"params\":[\"\"],\"id\":1}";
                msg.set_request_body_from_bytes ("application/json", new Bytes (body.data));
                yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                return msg.status_code == 200;
            } catch (GLib.Error e) {
                return false;
            }
        }

        /**
         * Searches for citations across Better BibTeX, Native Zotero Local API, or a fallback .bib string.
         */
        public async Gee.ArrayList<CitationItem> search_citations_async (string query, string? fallback_bib_content = null) {
            string trimmed = query.strip ();
            var merged = new Gee.ArrayList<CitationItem> ();
            var seen_keys = new Gee.HashSet<string> ();

            // Tier 1: Local .bib entries (always include parallel to Zotero)
            if (fallback_bib_content != null && fallback_bib_content.length > 0) {
                foreach (var item in search_offline_bib (trimmed, fallback_bib_content)) {
                    if (!seen_keys.contains (item.citekey)) {
                        seen_keys.add (item.citekey);
                        merged.add (item);
                    }
                }
            }

            // Tier 2A: Better BibTeX JSON-RPC
            try {
                var bbt_results = yield search_better_bibtex_async (trimmed);
                foreach (var item in bbt_results) {
                    if (!seen_keys.contains (item.citekey)) {
                        seen_keys.add (item.citekey);
                        merged.add (item);
                    }
                }
                if (bbt_results.size > 0) {
                    return merged;
                }
            } catch (GLib.Error e) {
                // Fall through
            }

            // Tier 2B: Native Zotero 7+ Local API
            try {
                var native_results = yield search_native_zotero_async (trimmed);
                foreach (var item in native_results) {
                    if (!seen_keys.contains (item.citekey)) {
                        seen_keys.add (item.citekey);
                        merged.add (item);
                    }
                }
            } catch (GLib.Error e) {
                // Fall through
            }

            return merged;
        }

        /**
         * Searches Zotero via Better BibTeX JSON-RPC endpoint.
         */
        public async Gee.ArrayList<CitationItem> search_better_bibtex_async (string query) throws GLib.Error {
            var results = new Gee.ArrayList<CitationItem> ();
            var msg = new Soup.Message ("POST", @"$base_url/better-bibtex/json-rpc");
            msg.request_headers.append ("Content-Type", "application/json");

            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("jsonrpc");
            builder.add_string_value ("2.0");
            builder.set_member_name ("method");
            builder.add_string_value ("item.search");
            builder.set_member_name ("params");
            builder.begin_array ();
            builder.add_string_value (query);
            builder.end_array ();
            builder.set_member_name ("id");
            builder.add_int_value (1);
            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            string json_payload = generator.to_data (null);

            msg.set_request_body_from_bytes ("application/json", new Bytes (json_payload.data));
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code != 200 || bytes == null) {
                throw new IOError.FAILED (@"BBT HTTP error $(msg.status_code)");
            }

            string resp_str = Core.PlatformUtils.bytes_to_string (bytes);
            var parser = new Json.Parser ();
            parser.load_from_data (resp_str, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new IOError.INVALID_DATA ("Invalid BBT JSON response");
            }

            var root_obj = root.get_object ();
            if (root_obj.has_member ("error")) {
                throw new IOError.FAILED ("BBT returned error");
            }

            if (root_obj.has_member ("result")) {
                var res_node = root_obj.get_member ("result");
                if (res_node.get_node_type () == Json.NodeType.ARRAY) {
                    var arr = res_node.get_array ();
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var item_node = arr.get_element (i);
                        if (item_node.get_node_type () == Json.NodeType.OBJECT) {
                            var item_obj = item_node.get_object ();
                            string citekey = "";
                            if (item_obj.has_member ("citekey") && !item_obj.get_null_member ("citekey")) {
                                citekey = item_obj.get_string_member ("citekey") ?? "";
                            } else if (item_obj.has_member ("citation-key") && !item_obj.get_null_member ("citation-key")) {
                                citekey = item_obj.get_string_member ("citation-key") ?? "";
                            }

                            string title = (item_obj.has_member ("title") && !item_obj.get_null_member ("title"))
                                ? (item_obj.get_string_member ("title") ?? "Untitled")
                                : "Untitled";
                            string authors = "";
                            if (item_obj.has_member ("author") && !item_obj.get_null_member ("author")) {
                                var auth_node = item_obj.get_member ("author");
                                if (auth_node.get_node_type () == Json.NodeType.ARRAY) {
                                    var auth_arr = auth_node.get_array ();
                                    var auth_list = new Gee.ArrayList<string> ();
                                    for (uint a = 0; a < auth_arr.get_length (); a++) {
                                        var a_node = auth_arr.get_element (a);
                                        if (a_node.get_node_type () != Json.NodeType.OBJECT) continue;
                                        var a_obj = a_node.get_object ();
                                        if (a_obj.has_member ("family") && !a_obj.get_null_member ("family")) {
                                            string? fam = a_obj.get_string_member ("family");
                                            if (fam != null && fam != "") auth_list.add (fam);
                                        } else if (a_obj.has_member ("literal") && !a_obj.get_null_member ("literal")) {
                                            string? lit = a_obj.get_string_member ("literal");
                                            if (lit != null && lit != "") auth_list.add (lit);
                                        }
                                    }
                                    authors = string.joinv (", ", auth_list.to_array ());
                                }
                            }
                            if (authors == "") authors = "Unknown Author";

                            string year = "n.d.";
                            if (item_obj.has_member ("issued") && !item_obj.get_null_member ("issued")) {
                                var iss_node = item_obj.get_member ("issued");
                                if (iss_node.get_node_type () == Json.NodeType.OBJECT) {
                                    var iss_obj = iss_node.get_object ();
                                    if (iss_obj.has_member ("date-parts") && !iss_obj.get_null_member ("date-parts")) {
                                        var dp = iss_obj.get_array_member ("date-parts");
                                        if (dp.get_length () > 0) {
                                            var row0_node = dp.get_element (0);
                                            if (row0_node.get_node_type () == Json.NodeType.ARRAY) {
                                                var row0 = row0_node.get_array ();
                                                if (row0.get_length () > 0) {
                                                    year = row0.get_int_element (0).to_string ();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            string? abs_text = (item_obj.has_member ("abstract") && !item_obj.get_null_member ("abstract"))
                                ? item_obj.get_string_member ("abstract")
                                : null;
                            if (citekey.length > 0) {
                                results.add (new CitationItem (citekey, title, authors, year, abs_text, "better-bibtex"));
                            }
                        }
                    }
                }
            }
            return results;
        }

        /**
         * Searches Zotero's built-in local HTTP API.
         */
        public async Gee.ArrayList<CitationItem> search_native_zotero_async (string query) throws GLib.Error {
            var results = new Gee.ArrayList<CitationItem> ();
            string encoded_q = Uri.escape_string (query, null, false);
            string url = @"$base_url/api/users/0/items?format=json&q=$encoded_q&itemType=-attachment";
            var msg = new Soup.Message ("GET", url);
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code != 200 || bytes == null) {
                throw new IOError.FAILED (@"Native Zotero API error: $(msg.status_code)");
            }

            string resp_str = Core.PlatformUtils.bytes_to_string (bytes);
            var parser = new Json.Parser ();
            parser.load_from_data (resp_str, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                return results;
            }

            var arr = root.get_array ();
            for (uint i = 0; i < arr.get_length (); i++) {
                var el_node = arr.get_element (i);
                if (el_node.get_node_type () != Json.NodeType.OBJECT) continue;
                var el = el_node.get_object ();
                if (!el.has_member ("data") || el.get_null_member ("data")) continue;
                var data = el.get_object_member ("data");
                string title = (data.has_member ("title") && !data.get_null_member ("title"))
                    ? (data.get_string_member ("title") ?? "")
                    : "";
                if (title == "") continue;

                var auth_list = new Gee.ArrayList<string> ();
                string first_author = "anon";
                if (data.has_member ("creators") && !data.get_null_member ("creators")) {
                    var creators_node = data.get_member ("creators");
                    if (creators_node.get_node_type () == Json.NodeType.ARRAY) {
                        var creators = creators_node.get_array ();
                        for (uint c = 0; c < creators.get_length (); c++) {
                            var c_node = creators.get_element (c);
                            if (c_node.get_node_type () != Json.NodeType.OBJECT) continue;
                            var c_obj = c_node.get_object ();
                            string name = "";
                            if (c_obj.has_member ("lastName") && !c_obj.get_null_member ("lastName")) {
                                name = c_obj.get_string_member ("lastName") ?? "";
                            } else if (c_obj.has_member ("name") && !c_obj.get_null_member ("name")) {
                                name = c_obj.get_string_member ("name") ?? "";
                            }
                            if (name != "") {
                                auth_list.add (name);
                                if (c == 0) first_author = name;
                            }
                        }
                    }
                }
                string authors = auth_list.size > 0 ? string.joinv (", ", auth_list.to_array ()) : "Unknown Author";

                string date_str = (data.has_member ("date") && !data.get_null_member ("date"))
                    ? (data.get_string_member ("date") ?? "")
                    : "";
                string year = "nd";
                try {
                    if (reg_year_cache == null) {
                        reg_year_cache = new Regex ("\\b(19|20)\\d{2}\\b");
                    }
                    MatchInfo mi;
                    if (reg_year_cache.match (date_str, 0, out mi)) {
                        year = mi.fetch (0);
                    }
                } catch (RegexError e) {}

                // Construct deterministic fallback citation key
                string sanitized_author = first_author.down ().replace (" ", "");
                var sb = new StringBuilder ();
                int char_idx = 0;
                unichar ch;
                while (sanitized_author.get_next_char (ref char_idx, out ch)) {
                    if (ch.isalnum ()) sb.append_unichar (ch);
                }
                string citekey = @"$(sb.str)$year";
                string? abs_text = (data.has_member ("abstractNote") && !data.get_null_member ("abstractNote"))
                    ? data.get_string_member ("abstractNote")
                    : null;
                results.add (new CitationItem (citekey, title, authors, year, abs_text, "zotero-local"));
            }
            return results;
        }

        /**
         * Opens Zotero's native "Cite As You Write" (CAYW) quick-search bar on the desktop
         * and returns the formatted Pandoc citation string (e.g., "[@turing1950; @shannon1948]").
         */
        public async string? open_native_citation_picker_async () {
            try {
                var custom_session = new Soup.Session () {
                    timeout = 60
                };
                string url = @"$base_url/better-bibtex/cayw?format=pandoc&brackets=1";
                var msg = new Soup.Message ("GET", url);
                var bytes = yield custom_session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 200 && bytes != null) {
                    string str = Core.PlatformUtils.bytes_to_string (bytes).strip ();
                    return str.length > 0 ? str : null;
                }
            } catch (GLib.Error e) {
                // Picker cancelled or unavailable
            }
            return null;
        }

        /**
         * Exports raw BibTeX entries for an array of citation keys.
         */
        public async string export_bibtex_entries_async (string[] citekeys) throws GLib.Error {
            if (citekeys.length == 0) return "";
            var msg = new Soup.Message ("POST", @"$base_url/better-bibtex/json-rpc");
            msg.request_headers.append ("Content-Type", "application/json");

            var builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("jsonrpc");
            builder.add_string_value ("2.0");
            builder.set_member_name ("method");
            builder.add_string_value ("item.export");
            builder.set_member_name ("params");
            builder.begin_array ();
            builder.begin_array ();
            foreach (var key in citekeys) {
                builder.add_string_value (key);
            }
            builder.end_array ();
            builder.add_string_value ("Better BibTeX");
            builder.end_array ();
            builder.set_member_name ("id");
            builder.add_int_value (1);
            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            string json_payload = generator.to_data (null);

            msg.set_request_body_from_bytes ("application/json", new Bytes (json_payload.data));
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code != 200 || bytes == null) {
                throw new IOError.FAILED (@"Failed to export BibTeX: $(msg.status_code)");
            }

            string resp_str = Core.PlatformUtils.bytes_to_string (bytes);
            var parser = new Json.Parser ();
            parser.load_from_data (resp_str, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new IOError.INVALID_DATA ("Invalid JSON response from export");
            }
            var root_obj = root.get_object ();
            if (root_obj.has_member ("result")) {
                var res = root_obj.get_member ("result");
                if (res.get_node_type () == Json.NodeType.VALUE && res.get_value_type () == typeof (string)) {
                    return res.get_string ();
                }
            }
            return "";
        }

        /**
         * Merges newly exported BibTeX entries into an existing references.bib content string.
         */
        public string merge_into_bib_file_content (string existing_bib, string new_entry, string citekey) {
            try {
                string escaped_key = Regex.escape_string (citekey);
                var reg = new Regex (@"@[a-zA-Z]+\\s*\\{\\s*$escaped_key\\s*,", RegexCompileFlags.CASELESS);
                if (reg.match (existing_bib)) {
                    return existing_bib;
                }
            } catch (RegexError e) {}

            string separator = "\n\n";
            if (existing_bib.has_suffix ("\n\n")) {
                separator = "";
            } else if (existing_bib.has_suffix ("\n")) {
                separator = "\n";
            }
            return @"$existing_bib$separator$(new_entry.strip ())\n";
        }

        /**
         * Ensures the YAML frontmatter of a document references the target .bib file.
         */
        public string ensure_yaml_bibliography (string document_text, string bib_filename = "references.bib") {
            try {
                if (reg_yaml_cache == null) {
                    reg_yaml_cache = new Regex ("^---\\r?\\n([\\s\\S]*?)\\r?\\n---");
                }
                MatchInfo mi;
                if (!reg_yaml_cache.match (document_text, 0, out mi)) {
                    return @"---\nbibliography: $bib_filename\n---\n\n$document_text";
                }

                string yaml_content = mi.fetch (1);
                if (reg_bib_check_cache == null) {
                    reg_bib_check_cache = new Regex ("^bibliography\\s*:", RegexCompileFlags.MULTILINE);
                }
                if (reg_bib_check_cache.match (yaml_content)) {
                    return document_text;
                }

                string updated_yaml = @"---\n$yaml_content\nbibliography: $bib_filename\n---";
                return reg_yaml_cache.replace_literal (document_text, document_text.length, 0, updated_yaml);
            } catch (RegexError e) {
                return document_text;
            }
        }

        /**
         * Lightweight offline .bib parser fallback when Zotero is closed.
         */
        public Gee.ArrayList<CitationItem> search_offline_bib (string query, string bib_content) {
            var entries = new Gee.ArrayList<CitationItem> ();
            try {
                if (reg_entry_cache == null) {
                    reg_entry_cache = new Regex ("@([a-zA-Z]+)\\s*\\{\\s*([^,\\s]+)\\s*,([\\s\\S]*?)(?=\\n@[a-zA-Z]+\\s*\\{|\\s*$)");
                }
                MatchInfo mi;
                string lower_q = query.down ();

                if (reg_entry_cache.match (bib_content, 0, out mi)) {
                    while (mi.matches ()) {
                        string citekey = mi.fetch (2).strip ();
                        string body = mi.fetch (3);

                        string title = extract_bib_field (body, "title") ?? "Untitled";
                        string authors = extract_bib_field (body, "author") ?? "Unknown Author";
                        string year = extract_bib_field (body, "year") ?? "n.d.";

                        title = title.replace ("{", "").replace ("}", "");
                        authors = authors.replace ("{", "").replace ("}", "");

                        string searchable = @"$citekey $title $authors $year".down ();
                        if (lower_q == "" || lower_q in searchable) {
                            entries.add (new CitationItem (citekey, title, authors, year, null, "local-bib"));
                        }
                        mi.next ();
                    }
                }
            } catch (RegexError e) {}
            return entries;
        }

        /**
         * Returns the XDG Portal-compatible URI to highlight an item directly inside Zotero.
         */
        public string get_zotero_select_uri (string citekey) {
            return @"zotero://select/items/@$(Uri.escape_string (citekey, null, false))";
        }

        /**
         * Syncs a citation key to the project's references.bib asynchronously in the background.
         */
        public async void sync_citation_to_project_async (string citekey, string project_dir) {
            if (project_dir == "") return;

            string bib_path = GLib.Path.build_filename (project_dir, "references.bib");
            string existing_bib = "";
            var bib_file = GLib.File.new_for_path (bib_path);
            if (bib_file.query_exists ()) {
                try {
                    uint8[] data;
                    yield bib_file.load_contents_async (null, out data, null);
                    existing_bib = Core.PlatformUtils.data_to_string (data);
                } catch (GLib.Error e) {
                    GLib.debug ("sync_citation_to_project_async read failed: %s", e.message);
                }
            }

            try {
                string[] keys = { citekey };
                string bibtex_entry = yield export_bibtex_entries_async (keys);
                if (bibtex_entry.strip ().length > 0) {
                    string merged = merge_into_bib_file_content (existing_bib, bibtex_entry, citekey);
                    if (merged != existing_bib) {
                        var stream = yield bib_file.replace_async (null, false, FileCreateFlags.NONE, Priority.DEFAULT);
                        yield stream.write_all_async (merged.data, Priority.DEFAULT, null, null);
                        yield stream.close_async (Priority.DEFAULT);
                    }
                }
            } catch (GLib.Error e) {
                // If offline or export fails, fail gracefully
            }
        }

        private string? extract_bib_field (string entry_body, string field_name) {
            string lower_body = entry_body.down ();
            string target = field_name.down ();
            int search_pos = 0;

            while (search_pos < lower_body.length) {
                int idx = lower_body.index_of (target, search_pos);
                if (idx < 0) return null;

                // Ensure word boundary before field_name
                if (idx > 0) {
                    char prev = lower_body[idx - 1];
                    if (prev.isalnum () || prev == '_') {
                        search_pos = idx + target.length;
                        continue;
                    }
                }

                int p = idx + target.length;
                while (p < entry_body.length && entry_body[p].isspace ()) p++;
                if (p >= entry_body.length || entry_body[p] != '=') {
                    search_pos = idx + target.length;
                    continue;
                }
                p++;
                while (p < entry_body.length && entry_body[p].isspace ()) p++;
                if (p >= entry_body.length) return null;

                if (entry_body[p] == '{') {
                    int depth = 1;
                    int start = p + 1;
                    p++;
                    while (p < entry_body.length && depth > 0) {
                        if (entry_body[p] == '{') depth++;
                        else if (entry_body[p] == '}') depth--;
                        p++;
                    }
                    int end = (depth == 0) ? p - 1 : p;
                    return entry_body.substring (start, end - start).strip ();
                } else if (entry_body[p] == '"') {
                    int start = p + 1;
                    p++;
                    while (p < entry_body.length && entry_body[p] != '"') p++;
                    return entry_body.substring (start, p - start).strip ();
                } else {
                    int start = p;
                    while (p < entry_body.length && entry_body[p] != ',' && entry_body[p] != '\n' && entry_body[p] != '}') p++;
                    return entry_body.substring (start, p - start).strip ();
                }
            }
            return null;
        }
    }
}
