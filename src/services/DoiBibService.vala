// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Gee;
using Soup;
using Json;

namespace Imladris.Services {

    public class DoiBibService : GLib.Object {

        private static DoiBibService? _instance = null;

        public static DoiBibService get_default () {
            if (_instance == null) {
                _instance = new DoiBibService ();
            }
            return _instance;
        }

        private Soup.Session session;
        private static GLib.Regex? doi_regex = null;
        private static GLib.Regex? non_alnum_regex = null;
        private static GLib.Regex? doi_field_regex = null;

        public DoiBibService () {
            session = new Soup.Session () {
                timeout = 10,
                user_agent = "Imladris/0.24.2 (https://github.com/Antux912012/imladris)"
            };
        }

        /**
         * Extracts and normalizes a DOI from raw text, `doi:...`, or `https://doi.org/...` URLs.
         * Returns null if no valid DOI is found.
         */
        public static string? extract_doi (string raw_input) {
            string trimmed = raw_input.strip ();
            if (trimmed.length == 0) return null;

            try {
                if (doi_regex == null) {
                    doi_regex = new GLib.Regex ("(10\\.\\d{4,9}/[-._;()/:A-Za-z0-9]+)");
                }
                GLib.MatchInfo mi;
                if (doi_regex.match (trimmed, 0, out mi)) {
                    string doi = mi.fetch (1);
                    while (doi.has_suffix (".") || doi.has_suffix (",") || doi.has_suffix (";")) {
                        doi = doi.substring (0, doi.length - 1);
                    }
                    return doi;
                }
            } catch (GLib.RegexError e) {}
            return null;
        }

        /**
         * Fetches BibTeX metadata for a DOI or DOI URL.
         * Tier 1: Crossref REST API (/works/<doi>) -> deterministic BibTeX formatting.
         * Tier 2: doi.org content negotiation (Accept: application/x-bibtex).
         */
        public async string fetch_bibtex_from_doi_async (string raw_input) throws GLib.Error {
            string? doi = extract_doi (raw_input);
            if (doi == null || doi.length == 0) {
                throw new GLib.IOError.INVALID_ARGUMENT ("Invalid DOI or DOI URL. Expected format: 10.xxxx/yyyy or https://doi.org/10.xxxx/yyyy");
            }

            string encoded_doi = GLib.Uri.escape_string (doi, "/", false);

            // Tier 1: Crossref REST JSON API
            try {
                string cr_url = @"https://api.crossref.org/works/$encoded_doi";
                var msg = new Soup.Message ("GET", cr_url);
                msg.request_headers.append ("Accept", "application/json");
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 200 && bytes != null) {
                    string body = Core.PlatformUtils.bytes_to_string (bytes);
                    string? bib = crossref_json_to_bibtex (body, doi);
                    if (bib != null && bib.strip ().length > 0) {
                        return bib;
                    }
                }
            } catch (GLib.Error e) {
                GLib.debug ("Crossref lookup failed for %s: %s", doi, e.message);
            }

            // Tier 2: doi.org BibTeX content negotiation
            var doi_msg = new Soup.Message ("GET", @"https://doi.org/$encoded_doi");
            doi_msg.request_headers.append ("Accept", "application/x-bibtex");
            var doi_bytes = yield session.send_and_read_async (doi_msg, Priority.DEFAULT, null);
            if (doi_msg.status_code >= 200 && doi_msg.status_code < 300 && doi_bytes != null) {
                string raw_bib = Core.PlatformUtils.bytes_to_string (doi_bytes).strip ();
                if (raw_bib.has_prefix ("@")) {
                    return raw_bib;
                }
            }

            throw new GLib.IOError.FAILED (@"Could not resolve DOI '$doi' (HTTP $(doi_msg.status_code)). Check internet connectivity or DOI spelling.");
        }

        /**
         * Converts a Crossref /works/<doi> JSON payload into a clean BibTeX entry.
         */
        public static string? crossref_json_to_bibtex (string json_body, string fallback_doi = "") {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_body, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;

                var root_obj = root.get_object ();
                Json.Object msg_obj = root_obj;
                if (root_obj.has_member ("message") && !root_obj.get_null_member ("message")) {
                    var m_node = root_obj.get_member ("message");
                    if (m_node.get_node_type () == Json.NodeType.OBJECT) {
                        msg_obj = m_node.get_object ();
                    }
                }

                string cr_type = get_json_str (msg_obj, "type") ?? "article";
                string bib_type = map_crossref_type (cr_type);
                string doi = get_json_str (msg_obj, "DOI") ?? fallback_doi;
                string title = get_json_first_str (msg_obj, "title") ?? "Untitled";
                string container = get_json_first_str (msg_obj, "container-title") ?? "";
                string volume = get_json_str (msg_obj, "volume") ?? "";
                string issue = get_json_str (msg_obj, "issue") ?? "";
                string page = get_json_str (msg_obj, "page") ?? "";
                string publisher = get_json_str (msg_obj, "publisher") ?? "";
                string url = get_json_str (msg_obj, "URL") ?? (doi != "" ? @"https://doi.org/$doi" : "");
                string year = extract_crossref_year (msg_obj);

                string first_family = "ref";
                string authors_bib = format_crossref_authors (msg_obj, out first_family);
                string citekey = build_citekey (first_family, year, title);

                var sb = new GLib.StringBuilder ();
                sb.append_printf ("@%s{%s,\n", bib_type, citekey);
                if (authors_bib != "") {
                    sb.append_printf ("  author = {%s},\n", escape_bib_value (authors_bib));
                }
                sb.append_printf ("  title = {{%s}},\n", escape_bib_value (title));
                if (container != "") {
                    string venue_field = (bib_type == "inproceedings") ? "booktitle" : "journal";
                    sb.append_printf ("  %s = {%s},\n", venue_field, escape_bib_value (container));
                }
                if (year != "") {
                    sb.append_printf ("  year = {%s},\n", year);
                }
                if (volume != "") {
                    sb.append_printf ("  volume = {%s},\n", escape_bib_value (volume));
                }
                if (issue != "") {
                    sb.append_printf ("  number = {%s},\n", escape_bib_value (issue));
                }
                if (page != "") {
                    sb.append_printf ("  pages = {%s},\n", escape_bib_value (page.replace ("-", "--")));
                }
                if (publisher != "" && bib_type != "article") {
                    sb.append_printf ("  publisher = {%s},\n", escape_bib_value (publisher));
                }
                if (doi != "") {
                    sb.append_printf ("  doi = {%s},\n", doi);
                }
                if (url != "") {
                    sb.append_printf ("  url = {%s}\n", url);
                }
                sb.append ("}");
                return sb.str;
            } catch (GLib.Error e) {
                return null;
            }
        }

        /**
         * Creates an empty .bib file with header if it does not yet exist.
         */
        public async void ensure_bib_file_exists_async (string bib_path) throws GLib.Error {
            var f = GLib.File.new_for_path (bib_path);
            if (f.query_exists ()) return;

            string? parent = GLib.Path.get_dirname (bib_path);
            if (parent != null && parent != "") {
                GLib.DirUtils.create_with_parents (parent, 0755);
            }
            string header = "% BibTeX Bibliography managed by Imladris\n";
            var stream = yield f.replace_async (null, false, FileCreateFlags.NONE, Priority.DEFAULT);
            yield stream.write_all_async (header.data, Priority.DEFAULT, null, null);
            yield stream.close_async (Priority.DEFAULT);
        }

        /**
         * Appends a BibTeX entry to `bib_path` (creating the file if needed),
         * deduplicating by DOI or citekey. Outputs the final citekey used.
         */
        public async void append_entry_to_bib_file_async (string bib_path, string bibtex_entry, out string final_citekey) throws GLib.Error {
            final_citekey = extract_citekey (bibtex_entry) ?? "ref";
            yield ensure_bib_file_exists_async (bib_path);

            var f = GLib.File.new_for_path (bib_path);
            uint8[] data;
            yield f.load_contents_async (null, out data, null);
            string existing = Core.PlatformUtils.data_to_string (data);

            string? new_doi = extract_bib_doi (bibtex_entry);
            if (new_doi != null && new_doi != "") {
                string? existing_key = find_citekey_by_doi (existing, new_doi);
                if (existing_key != null) {
                    final_citekey = existing_key;
                    return;
                }
            }

            string candidate_key = final_citekey;
            int suffix_num = 2;
            while (bib_has_citekey (existing, candidate_key)) {
                if (new_doi == null && existing.contains (bibtex_entry.strip ())) {
                    final_citekey = candidate_key;
                    return;
                }
                candidate_key = @"$(final_citekey)$(suffix_num)";
                suffix_num++;
            }

            string entry_to_write = bibtex_entry.strip ();
            if (candidate_key != final_citekey) {
                entry_to_write = replace_citekey (entry_to_write, candidate_key);
                final_citekey = candidate_key;
            }

            var sb = new GLib.StringBuilder ();
            sb.append (existing.chomp ());
            if (sb.len > 0) sb.append ("\n\n");
            sb.append (entry_to_write);
            sb.append ("\n");

            var stream = yield f.replace_async (null, false, FileCreateFlags.NONE, Priority.DEFAULT);
            yield stream.write_all_async (sb.str.data, Priority.DEFAULT, null, null);
            yield stream.close_async (Priority.DEFAULT);
        }

        public static string? extract_citekey (string bib_entry) {
            int brace = bib_entry.index_of_char ('{');
            if (brace < 0) return null;
            int comma = bib_entry.index_of_char (',', brace + 1);
            if (comma < 0) return null;
            return bib_entry.substring (brace + 1, comma - brace - 1).strip ();
        }

        private static string replace_citekey (string bib_entry, string new_key) {
            int brace = bib_entry.index_of_char ('{');
            int comma = (brace >= 0) ? bib_entry.index_of_char (',', brace + 1) : -1;
            if (brace < 0 || comma < 0) return bib_entry;
            return bib_entry.substring (0, brace + 1) + new_key + bib_entry.substring (comma);
        }

        private static string? extract_bib_doi (string bib_entry) {
            try {
                if (doi_field_regex == null) {
                    doi_field_regex = new GLib.Regex ("doi\\s*=\\s*[\\{\"]([^\\}\"]+)[\\}\"]", GLib.RegexCompileFlags.CASELESS);
                }
                GLib.MatchInfo mi;
                if (doi_field_regex.match (bib_entry, 0, out mi)) {
                    return mi.fetch (1).strip ().down ();
                }
            } catch (GLib.RegexError e) {}
            return null;
        }

        private static bool bib_has_citekey (string bib_content, string key) {
            try {
                string escaped = GLib.Regex.escape_string (key);
                var reg = new GLib.Regex (@"^\\s*@[a-zA-Z]+\\s*\\{\\s*$(escaped)\\s*,", GLib.RegexCompileFlags.MULTILINE);
                return reg.match (bib_content);
            } catch (GLib.RegexError e) {
                return bib_content.contains (@"{$key,");
            }
        }

        private static string? find_citekey_by_doi (string bib_content, string target_doi) {
            string lower_target = target_doi.strip ().down ();
            string[] chunks = bib_content.split ("@");
            foreach (string raw_chunk in chunks) {
                string chunk = "@" + raw_chunk.strip ();
                if (chunk.length < 3) continue;
                string? doi = extract_bib_doi (chunk);
                if (doi != null && doi == lower_target) {
                    return extract_citekey (chunk);
                }
            }
            return null;
        }

        private static string map_crossref_type (string cr_type) {
            switch (cr_type) {
                case "journal-article":     return "article";
                case "proceedings-article": return "inproceedings";
                case "book":                return "book";
                case "book-chapter":        return "incollection";
                case "posted-content":      return "misc";
                default:                    return "article";
            }
        }

        private static string? get_json_str (Json.Object obj, string member) {
            if (!obj.has_member (member) || obj.get_null_member (member)) return null;
            var node = obj.get_member (member);
            if (node.get_node_type () != Json.NodeType.VALUE) return null;
            return node.get_string ();
        }

        private static string? get_json_first_str (Json.Object obj, string member) {
            if (!obj.has_member (member) || obj.get_null_member (member)) return null;
            var node = obj.get_member (member);
            if (node.get_node_type () != Json.NodeType.ARRAY) return null;
            var arr = node.get_array ();
            if (arr.get_length () == 0) return null;
            var el = arr.get_element (0);
            return (el.get_node_type () == Json.NodeType.VALUE) ? el.get_string () : null;
        }

        private static string extract_crossref_year (Json.Object msg_obj) {
            string[] date_keys = { "published-print", "published-online", "issued", "created" };
            foreach (string key in date_keys) {
                if (!msg_obj.has_member (key) || msg_obj.get_null_member (key)) continue;
                var d_node = msg_obj.get_member (key);
                if (d_node.get_node_type () != Json.NodeType.OBJECT) continue;
                var d_obj = d_node.get_object ();
                if (!d_obj.has_member ("date-parts") || d_obj.get_null_member ("date-parts")) continue;
                var dp_node = d_obj.get_member ("date-parts");
                if (dp_node.get_node_type () != Json.NodeType.ARRAY) continue;
                var outer = dp_node.get_array ();
                if (outer.get_length () == 0) continue;
                var inner_node = outer.get_element (0);
                if (inner_node.get_node_type () != Json.NodeType.ARRAY) continue;
                var inner = inner_node.get_array ();
                if (inner.get_length () > 0) {
                    int64 yr = inner.get_int_element (0);
                    if (yr > 0) return yr.to_string ();
                }
            }
            return "n.d.";
        }

        private static string format_crossref_authors (Json.Object msg_obj, out string first_family) {
            first_family = "ref";
            if (!msg_obj.has_member ("author") || msg_obj.get_null_member ("author")) return "";
            var a_node = msg_obj.get_member ("author");
            if (a_node.get_node_type () != Json.NodeType.ARRAY) return "";
            var arr = a_node.get_array ();
            var parts = new GLib.GenericArray<string> ();
            for (uint i = 0; i < arr.get_length (); i++) {
                var el = arr.get_element (i);
                if (el.get_node_type () != Json.NodeType.OBJECT) continue;
                var a_obj = el.get_object ();
                string family = get_json_str (a_obj, "family") ?? "";
                string given = get_json_str (a_obj, "given") ?? "";
                string name = get_json_str (a_obj, "name") ?? "";
                if (family != "") {
                    if (i == 0) first_family = family;
                    parts.add (given != "" ? @"$family, $given" : family);
                } else if (name != "") {
                    if (i == 0) first_family = name;
                    parts.add (name);
                }
            }
            if (parts.length == 0) return "";
            string[] out_arr = new string[parts.length];
            for (int i = 0; i < parts.length; i++) out_arr[i] = parts[i];
            return string.joinv (" and ", out_arr);
        }

        private static string build_citekey (string family, string year, string title) {
            string clean_fam = sanitize_key_token (family);
            if (clean_fam == "") clean_fam = "ref";
            string clean_yr = sanitize_key_token (year);
            string first_word = "";
            foreach (string w in title.split (" ")) {
                string cw = sanitize_key_token (w);
                if (cw.length >= 4) {
                    first_word = cw;
                    break;
                }
            }
            return @"$(clean_fam.down ())$(clean_yr)$(first_word.down ())";
        }

        private static string sanitize_key_token (string raw) {
            try {
                if (non_alnum_regex == null) {
                    non_alnum_regex = new GLib.Regex ("[^A-Za-z0-9]");
                }
                return non_alnum_regex.replace (raw, -1, 0, "");
            } catch (GLib.RegexError e) {
                return raw;
            }
        }

        private static GLib.Regex? jats_tag_regex = null;

        private static string escape_bib_value (string val) {
            string cleaned = val.replace ("\n", " ").replace ("\r", "");
            try {
                if (jats_tag_regex == null) {
                    jats_tag_regex = new GLib.Regex ("<[^>]+>");
                }
                cleaned = jats_tag_regex.replace (cleaned, -1, 0, "");
            } catch (GLib.RegexError e) {}
            return cleaned.strip ();
        }
    }
}
