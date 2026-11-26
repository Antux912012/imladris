// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

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
        private static GLib.Regex? pmid_regex = null;
        private static GLib.Regex? arxiv_regex = null;
        private static GLib.Regex? non_alnum_regex = null;
        private static GLib.Regex? doi_field_regex = null;

        public DoiBibService () {
            session = new Soup.Session () {
                timeout = 10,
                user_agent = "Imladris/0.40.0 (https://github.com/Antux912012/imladris)"
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
         * Extracts a numeric PubMed ID (PMID) from raw text, `PMID:...`, or `pubmed.ncbi.nlm.nih.gov/<id>`.
         */
        public static string? extract_pmid (string raw_input) {
            string trimmed = raw_input.strip ();
            if (trimmed.length == 0 || extract_doi (trimmed) != null) return null;

            try {
                if (pmid_regex == null) {
                    pmid_regex = new GLib.Regex ("(?:^|pmid\\s*:?\\s*|pubmed\\.ncbi\\.nlm\\.nih\\.gov/)(\\d{5,9})(?:[/\\s]|$)", GLib.RegexCompileFlags.CASELESS);
                }
                GLib.MatchInfo mi;
                if (pmid_regex.match (trimmed, 0, out mi)) {
                    return mi.fetch (1);
                }
            } catch (GLib.RegexError e) {}
            return null;
        }

        /**
         * Extracts an arXiv identifier (e.g. `arXiv:2301.07041`, `https://arxiv.org/abs/2301.07041`, or `2301.07041`).
         */
        public static string? extract_arxiv_id (string raw_input) {
            string trimmed = raw_input.strip ();
            if (trimmed.length == 0 || extract_doi (trimmed) != null) return null;

            try {
                if (arxiv_regex == null) {
                    arxiv_regex = new GLib.Regex ("(?:arxiv\\s*:\\s*|arxiv\\.org/(?:abs|pdf)/)?((?:\\d{4}\\.\\d{4,5}|[a-z-]+(?:\\.[a-z-]+)?/\\d{7})(?:v\\d+)?)(?:\\.pdf)?(?:\\s|$)", GLib.RegexCompileFlags.CASELESS);
                }
                GLib.MatchInfo mi;
                if (arxiv_regex.match (trimmed, 0, out mi)) {
                    return mi.fetch (1);
                }
            } catch (GLib.RegexError e) {}
            return null;
        }

        /**
         * Resolves a DOI/URL, arXiv ID, or PubMed PMID into a BibTeX entry.
         */
        public async string fetch_bibtex_from_identifier_async (string raw_input) throws GLib.Error {
            if (extract_doi (raw_input) != null) {
                return yield fetch_bibtex_from_doi_async (raw_input);
            }
            string? arxiv_id = extract_arxiv_id (raw_input);
            if (arxiv_id != null) {
                return yield fetch_bibtex_from_arxiv_async (arxiv_id);
            }
            string? pmid = extract_pmid (raw_input);
            if (pmid != null) {
                return yield fetch_bibtex_from_pmid_async (pmid);
            }
            throw new GLib.IOError.INVALID_ARGUMENT ("Invalid identifier. Enter a DOI (10.xxxx/yyyy), doi.org URL, PubMed PMID, or arXiv ID (e.g. arXiv:2301.07041).");
        }

        public async string fetch_bibtex_from_arxiv_async (string arxiv_id) throws GLib.Error {
            string escaped_id = GLib.Uri.escape_string (arxiv_id, "", false);
            string url = @"https://export.arxiv.org/api/query?id_list=$escaped_id";
            var msg = new Soup.Message ("GET", url);
            msg.request_headers.append ("Accept", "application/atom+xml");
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code == 200 && bytes != null) {
                string body = Core.PlatformUtils.bytes_to_string (bytes);
                string? bib = arxiv_atom_to_bibtex (body, arxiv_id);
                if (bib != null && bib.strip ().length > 0) {
                    return bib;
                }
            }
            throw new GLib.IOError.FAILED (@"Could not resolve arXiv ID '$arxiv_id' (HTTP $(msg.status_code)).");
        }

        private static GLib.Regex? cached_arxiv_entry_reg = null;
        private static GLib.Regex? cached_arxiv_title_reg = null;
        private static GLib.Regex? cached_arxiv_ws_reg = null;
        private static GLib.Regex? cached_arxiv_pub_reg = null;
        private static GLib.Regex? cached_arxiv_auth_reg = null;

        public static string? arxiv_atom_to_bibtex (string atom_xml, string arxiv_id) {
            try {
                if (cached_arxiv_entry_reg == null) cached_arxiv_entry_reg = new GLib.Regex ("<entry>([\\s\\S]*?)</entry>");
                if (cached_arxiv_title_reg == null) cached_arxiv_title_reg = new GLib.Regex ("<title>([\\s\\S]*?)</title>");
                if (cached_arxiv_ws_reg == null) cached_arxiv_ws_reg = new GLib.Regex ("\\s+");
                if (cached_arxiv_pub_reg == null) cached_arxiv_pub_reg = new GLib.Regex ("<published>(\\d{4})");
                if (cached_arxiv_auth_reg == null) cached_arxiv_auth_reg = new GLib.Regex ("<author>\\s*<name>([\\s\\S]*?)</name>");

                GLib.MatchInfo entry_mi;
                if (!cached_arxiv_entry_reg.match (atom_xml, 0, out entry_mi)) return null;
                string entry = entry_mi.fetch (1);

                string title = "";
                GLib.MatchInfo title_mi;
                if (cached_arxiv_title_reg.match (entry, 0, out title_mi)) {
                    title = unescape_xml_entities (title_mi.fetch (1).replace ("\n", " ").replace ("\r", "")).strip ();
                    title = cached_arxiv_ws_reg.replace (title, -1, 0, " ");
                }
                if (title == "") return null;

                string year = "n.d.";
                GLib.MatchInfo pub_mi;
                if (cached_arxiv_pub_reg.match (entry, 0, out pub_mi)) {
                    year = pub_mi.fetch (1);
                }

                var authors = new GLib.GenericArray<string> ();
                string first_family = "arxiv";
                GLib.MatchInfo auth_mi;
                if (cached_arxiv_auth_reg.match (entry, 0, out auth_mi)) {
                    do {
                        string full_name = unescape_xml_entities (auth_mi.fetch (1)).strip ();
                        if (full_name == "") continue;
                        if (authors.length == 0) {
                            string[] parts = full_name.split (" ");
                            first_family = parts.length > 0 ? parts[parts.length - 1] : "arxiv";
                        }
                        authors.add (full_name);
                    } while (auth_mi.next ());
                }

                string authors_bib = "";
                if (authors.length > 0) {
                    string[] arr = new string[authors.length];
                    for (int i = 0; i < authors.length; i++) arr[i] = authors[i];
                    authors_bib = string.joinv (" and ", arr);
                }

                string citekey = build_citekey (first_family, year, title);
                var sb = new GLib.StringBuilder ();
                sb.append_printf ("@misc{%s,\n", citekey);
                if (authors_bib != "") sb.append_printf ("  author = {%s},\n", escape_bib_value (authors_bib));
                sb.append_printf ("  title = {{%s}},\n", escape_bib_value (title));
                sb.append_printf ("  year = {%s},\n", year);
                sb.append_printf ("  eprint = {%s},\n", arxiv_id);
                sb.append ("  archivePrefix = {arXiv},\n");
                sb.append_printf ("  url = {https://arxiv.org/abs/%s}\n", arxiv_id);
                sb.append ("}");
                return sb.str;
            } catch (GLib.RegexError e) {
                return null;
            }
        }

        private static string unescape_xml_entities (string s) {
            return s.replace ("&amp;", "&")
                    .replace ("&lt;", "<")
                    .replace ("&gt;", ">")
                    .replace ("&quot;", "\"")
                    .replace ("&apos;", "'");
        }

        public async string fetch_bibtex_from_pmid_async (string pmid) throws GLib.Error {
            string url = @"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=$pmid&retmode=json";
            var msg = new Soup.Message ("GET", url);
            msg.request_headers.append ("Accept", "application/json");
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code == 200 && bytes != null) {
                string body = Core.PlatformUtils.bytes_to_string (bytes);
                string? bib = pubmed_json_to_bibtex (body, pmid);
                if (bib != null && bib.strip ().length > 0) {
                    return bib;
                }
            }
            throw new GLib.IOError.FAILED (@"Could not resolve PubMed PMID '$pmid' (HTTP $(msg.status_code)).");
        }

        public static string? pubmed_json_to_bibtex (string json_body, string pmid) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_body);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;
                var root_obj = root.get_object ();
                if (!root_obj.has_member ("result")) return null;
                var res_obj = root_obj.get_object_member ("result");
                if (!res_obj.has_member (pmid)) return null;
                var art = res_obj.get_object_member (pmid);

                string title = art.has_member ("title") ? (art.get_string_member ("title") ?? "").strip () : "";
                if (title.has_suffix (".")) title = title.substring (0, title.length - 1).strip ();
                string journal = art.has_member ("fulljournalname") ? (art.get_string_member ("fulljournalname") ?? "") :
                                 (art.has_member ("source") ? (art.get_string_member ("source") ?? "") : "");
                string pubdate = art.has_member ("pubdate") ? (art.get_string_member ("pubdate") ?? "") : "";
                string year = pubdate.length >= 4 ? pubdate.substring (0, 4) : "n.d.";
                string volume = art.has_member ("volume") ? (art.get_string_member ("volume") ?? "") : "";
                string issue = art.has_member ("issue") ? (art.get_string_member ("issue") ?? "") : "";
                string pages = art.has_member ("pages") ? (art.get_string_member ("pages") ?? "") : "";

                var authors_list = new StringBuilder ();
                string first_author = "pmid";
                if (art.has_member ("authors") && art.get_member ("authors").get_node_type () == Json.NodeType.ARRAY) {
                    var arr = art.get_array_member ("authors");
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var aobj = arr.get_object_element (i);
                        string name = aobj.has_member ("name") ? (aobj.get_string_member ("name") ?? "") : "";
                        if (name == "") continue;
                        if (i == 0) {
                            string[] np = name.split (" ");
                            first_author = np.length > 0 ? np[0].down () : "pmid";
                        } else {
                            authors_list.append (" and ");
                        }
                        authors_list.append (name);
                    }
                }

                string doi_val = "";
                if (art.has_member ("articleids") && art.get_member ("articleids").get_node_type () == Json.NodeType.ARRAY) {
                    var ids = art.get_array_member ("articleids");
                    for (uint i = 0; i < ids.get_length (); i++) {
                        var idobj = ids.get_object_element (i);
                        if ((idobj.get_string_member ("idtype") ?? "") == "doi") {
                            doi_val = idobj.get_string_member ("value") ?? "";
                            break;
                        }
                    }
                }

                string safe_author = sanitize_key_token (first_author);
                if (safe_author.length == 0) safe_author = "author";
                string cite_key = @"$(safe_author)$(year)_pmid$(pmid)";
                var sb = new StringBuilder ();
                sb.append_printf ("@article{%s,\n", cite_key);
                if (authors_list.len > 0) sb.append_printf ("  author = {%s},\n", escape_bib_value (authors_list.str));
                if (title.length > 0) sb.append_printf ("  title = {%s},\n", escape_bib_value (title));
                if (journal.length > 0) sb.append_printf ("  journal = {%s},\n", escape_bib_value (journal));
                sb.append_printf ("  year = {%s},\n", year);
                if (volume.length > 0) sb.append_printf ("  volume = {%s},\n", volume);
                if (issue.length > 0) sb.append_printf ("  number = {%s},\n", issue);
                if (pages.length > 0) sb.append_printf ("  pages = {%s},\n", pages);
                if (doi_val.length > 0) sb.append_printf ("  doi = {%s},\n", doi_val);
                sb.append_printf ("  pmid = {%s}\n}", pmid);
                return sb.str;
            } catch (GLib.Error e) {
                return null;
            }
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
            string normalized = "\n" + bib_content.replace ("\r\n", "\n");
            string[] chunks = normalized.split ("\n@");
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
                case "report":
                case "working-paper":       return "techreport";
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

        private static string transliterate_latin (string raw) {
            var sb = new GLib.StringBuilder ();
            int idx = 0;
            unichar ch;
            while (raw.get_next_char (ref idx, out ch)) {
                switch (ch) {
                    case 'à': case 'á': case 'â': case 'ã': case 'ä': case 'å': case 'ā': case 'ă': case 'ą':
                        sb.append_c ('a'); break;
                    case 'À': case 'Á': case 'Â': case 'Ã': case 'Ä': case 'Å': case 'Ā': case 'Ă': case 'Ą':
                        sb.append_c ('A'); break;
                    case 'è': case 'é': case 'ê': case 'ë': case 'ē': case 'ĕ': case 'ė': case 'ę': case 'ě':
                        sb.append_c ('e'); break;
                    case 'È': case 'É': case 'Ê': case 'Ë': case 'Ē': case 'Ĕ': case 'Ė': case 'Ę': case 'Ě':
                        sb.append_c ('E'); break;
                    case 'ì': case 'í': case 'î': case 'ï': case 'ĩ': case 'ī': case 'ĭ': case 'į': case 'ı':
                        sb.append_c ('i'); break;
                    case 'Ì': case 'Í': case 'Î': case 'Ï': case 'Ĩ': case 'Ī': case 'Ĭ': case 'Į': case 'İ':
                        sb.append_c ('I'); break;
                    case 'ò': case 'ó': case 'ô': case 'õ': case 'ö': case 'ø': case 'ō': case 'ŏ': case 'ő':
                        sb.append_c ('o'); break;
                    case 'Ò': case 'Ó': case 'Ô': case 'Õ': case 'Ö': case 'Ø': case 'Ō': case 'Ŏ': case 'Ő':
                        sb.append_c ('O'); break;
                    case 'ù': case 'ú': case 'û': case 'ü': case 'ũ': case 'ū': case 'ŭ': case 'ů': case 'ű': case 'ų':
                        sb.append_c ('u'); break;
                    case 'Ù': case 'Ú': case 'Û': case 'Ü': case 'Ũ': case 'Ū': case 'Ŭ': case 'Ů': case 'Ű': case 'Ų':
                        sb.append_c ('U'); break;
                    case 'ñ': case 'ń': case 'ņ': case 'ň':
                        sb.append_c ('n'); break;
                    case 'Ñ': case 'Ń': case 'Ņ': case 'Ň':
                        sb.append_c ('N'); break;
                    case 'ç': case 'ć': case 'ĉ': case 'ċ': case 'č':
                        sb.append_c ('c'); break;
                    case 'Ç': case 'Ć': case 'Ĉ': case 'Ċ': case 'Č':
                        sb.append_c ('C'); break;
                    case 'ý': case 'ÿ': case 'ŷ':
                        sb.append_c ('y'); break;
                    case 'Ý': case 'Ÿ': case 'Ŷ':
                        sb.append_c ('Y'); break;
                    case 'ž': case 'ź': case 'ż':
                        sb.append_c ('z'); break;
                    case 'Ž': case 'Ź': case 'Ż':
                        sb.append_c ('Z'); break;
                    case 'š': case 'ś': case 'ŝ': case 'ş':
                        sb.append_c ('s'); break;
                    case 'Š': case 'Ś': case 'Ŝ': case 'Ş':
                        sb.append_c ('S'); break;
                    case 'ř': case 'ŕ': case 'ŗ':
                        sb.append_c ('r'); break;
                    case 'Ř': case 'Ŕ': case 'Ŗ':
                        sb.append_c ('R'); break;
                    case 'ł': case 'ĺ': case 'ļ': case 'ľ':
                        sb.append_c ('l'); break;
                    case 'Ł': case 'Ĺ': case 'Ļ': case 'Ľ':
                        sb.append_c ('L'); break;
                    case 'ď': case 'đ':
                        sb.append_c ('d'); break;
                    case 'Ď': case 'Đ':
                        sb.append_c ('D'); break;
                    case 'ť': case 'ţ': case 'ŧ':
                        sb.append_c ('t'); break;
                    case 'Ť': case 'Ţ': case 'Ŧ':
                        sb.append_c ('T'); break;
                    case 'ß':
                        sb.append ("ss"); break;
                    case 'æ':
                        sb.append ("ae"); break;
                    case 'Æ':
                        sb.append ("AE"); break;
                    case 'œ':
                        sb.append ("oe"); break;
                    case 'Œ':
                        sb.append ("OE"); break;
                    default:
                        sb.append_unichar (ch); break;
                }
            }
            return sb.str;
        }

        private static string sanitize_key_token (string raw) {
            string ascii = transliterate_latin (raw);
            try {
                if (non_alnum_regex == null) {
                    non_alnum_regex = new GLib.Regex ("[^A-Za-z0-9]");
                }
                return non_alnum_regex.replace (ascii, -1, 0, "");
            } catch (GLib.RegexError e) {
                return ascii;
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

            var sb = new GLib.StringBuilder ();
            bool escaped = false;
            for (int i = 0; i < cleaned.length; i++) {
                char c = cleaned[i];
                if (escaped) {
                    sb.append_c (c);
                    escaped = false;
                    continue;
                }
                if (c == '\\') {
                    sb.append_c (c);
                    escaped = true;
                    continue;
                }
                if (c == '&' || c == '%' || c == '$' || c == '#' || c == '_') {
                    sb.append_c ('\\');
                }
                sb.append_c (c);
            }
            return sb.str.strip ();
        }
    }
}
