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
                    string txt = (string) bytes.get_data ();
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

            // Tier 1A: Try Better BibTeX JSON-RPC first (Best for Quarto / R Markdown)
            try {
                var bbt_results = yield search_better_bibtex_async (trimmed);
                if (bbt_results.size > 0) {
                    return bbt_results;
                }
            } catch (GLib.Error e) {
                // Fall through
            }

            // Tier 1B: Try Native Zotero 7+ Local API
            try {
                var native_results = yield search_native_zotero_async (trimmed);
                if (native_results.size > 0) {
                    return native_results;
                }
            } catch (GLib.Error e) {
                // Fall through
            }

            // Tier 2: Offline Fallback using references.bib content
            if (fallback_bib_content != null && fallback_bib_content.length > 0) {
                return search_offline_bib (trimmed, fallback_bib_content);
            }

            return new Gee.ArrayList<CitationItem> ();
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

            string resp_str = (string) bytes.get_data ();
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
                            if (item_obj.has_member ("citekey")) {
                                citekey = item_obj.get_string_member ("citekey");
                            } else if (item_obj.has_member ("citation-key")) {
                                citekey = item_obj.get_string_member ("citation-key");
                            }

                            string title = item_obj.has_member ("title") ? item_obj.get_string_member ("title") : "Untitled";
                            string authors = "";
                            if (item_obj.has_member ("author")) {
                                var auth_node = item_obj.get_member ("author");
                                if (auth_node.get_node_type () == Json.NodeType.ARRAY) {
                                    var auth_arr = auth_node.get_array ();
                                    var auth_list = new Gee.ArrayList<string> ();
                                    for (uint a = 0; a < auth_arr.get_length (); a++) {
                                        var a_obj = auth_arr.get_object_element (a);
                                        if (a_obj.has_member ("family")) {
                                            auth_list.add (a_obj.get_string_member ("family"));
                                        } else if (a_obj.has_member ("literal")) {
                                            auth_list.add (a_obj.get_string_member ("literal"));
                                        }
                                    }
                                    authors = string.joinv (", ", auth_list.to_array ());
                                }
                            }
                            if (authors == "") authors = "Unknown Author";

                            string year = "n.d.";
                            if (item_obj.has_member ("issued")) {
                                var iss_node = item_obj.get_member ("issued");
                                if (iss_node.get_node_type () == Json.NodeType.OBJECT) {
                                    var iss_obj = iss_node.get_object ();
                                    if (iss_obj.has_member ("date-parts")) {
                                        var dp = iss_obj.get_array_member ("date-parts");
                                        if (dp.get_length () > 0) {
                                            var row0 = dp.get_array_element (0);
                                            if (row0.get_length () > 0) {
                                                year = row0.get_int_element (0).to_string ();
                                            }
                                        }
                                    }
                                }
                            }

                            string? abs_text = item_obj.has_member ("abstract") ? item_obj.get_string_member ("abstract") : null;
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

            string resp_str = (string) bytes.get_data ();
            var parser = new Json.Parser ();
            parser.load_from_data (resp_str, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                return results;
            }

            var arr = root.get_array ();
            for (uint i = 0; i < arr.get_length (); i++) {
                var el = arr.get_object_element (i);
                if (!el.has_member ("data")) continue;
                var data = el.get_object_member ("data");
                string title = data.has_member ("title") ? data.get_string_member ("title") : "";
                if (title == "") continue;

                var auth_list = new Gee.ArrayList<string> ();
                string first_author = "anon";
                if (data.has_member ("creators")) {
                    var creators = data.get_array_member ("creators");
                    for (uint c = 0; c < creators.get_length (); c++) {
                        var c_obj = creators.get_object_element (c);
                        string name = "";
                        if (c_obj.has_member ("lastName")) name = c_obj.get_string_member ("lastName");
                        else if (c_obj.has_member ("name")) name = c_obj.get_string_member ("name");
                        if (name != "") {
                            auth_list.add (name);
                            if (c == 0) first_author = name;
                        }
                    }
                }
                string authors = auth_list.size > 0 ? string.joinv (", ", auth_list.to_array ()) : "Unknown Author";

                string date_str = data.has_member ("date") ? data.get_string_member ("date") : "";
                string year = "nd";
                try {
                    var reg_year = new Regex ("\\b(19|20)\\d{2}\\b");
                    MatchInfo mi;
                    if (reg_year.match (date_str, 0, out mi)) {
                        year = mi.fetch (0);
                    }
                } catch (RegexError e) {}

                // Construct deterministic fallback citation key
                string sanitized_author = first_author.down ().replace (" ", "");
                var sb = new StringBuilder ();
                for (int ci = 0; ci < sanitized_author.length; ci++) {
                    unichar ch = sanitized_author[ci];
                    if (ch.isalnum ()) sb.append_unichar (ch);
                }
                string citekey = @"$(sb.str)$year";
                string? abs_text = data.has_member ("abstractNote") ? data.get_string_member ("abstractNote") : null;
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
                    string str = ((string) bytes.get_data ()).strip ();
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

            string resp_str = (string) bytes.get_data ();
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
                var yaml_reg = new Regex ("^---\\r?\\n([\\s\\S]*?)\\r?\\n---");
                MatchInfo mi;
                if (!yaml_reg.match (document_text, 0, out mi)) {
                    return @"---\nbibliography: $bib_filename\n---\n\n$document_text";
                }

                string yaml_content = mi.fetch (1);
                var bib_check = new Regex ("^bibliography\\s*:", RegexCompileFlags.MULTILINE);
                if (bib_check.match (yaml_content)) {
                    return document_text;
                }

                string updated_yaml = @"---\n$yaml_content\nbibliography: $bib_filename\n---";
                return yaml_reg.replace_literal (document_text, document_text.length, 0, updated_yaml);
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
                var entry_reg = new Regex ("@([a-zA-Z]+)\\s*\\{\\s*([^,\\s]+)\\s*,([\\s\\S]*?)(?=\\n@[a-zA-Z]+\\s*\\{|\\s*$)");
                MatchInfo mi;
                string lower_q = query.down ();

                if (entry_reg.match (bib_content, 0, out mi)) {
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
                    bib_file.load_contents (null, out data, null);
                    existing_bib = (string) data;
                } catch (GLib.Error e) {}
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
            try {
                var reg = new Regex (@"$field_name\\s*=\\s*(?:\\{([\\s\\S]*?)\\}|\"([\\s\\S]*?)\"|(\\d+))", RegexCompileFlags.CASELESS);
                MatchInfo mi;
                if (reg.match (entry_body, 0, out mi)) {
                    for (int g = 1; g <= 3; g++) {
                        string val = mi.fetch (g);
                        if (val != "") return val.strip ();
                    }
                }
            } catch (RegexError e) {}
            return null;
        }
    }
}
