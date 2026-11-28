// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Soup;
using Json;

namespace Imladris.Services {

    public class ManualDescriptor : GLib.Object {
        public string id { get; set; default = ""; }
        public string title { get; set; default = ""; }
        public string track { get; set; default = ""; }
        public string version { get; set; default = "1.0.0"; }
        public string filename { get; set; default = ""; }
        public string remote_url { get; set; default = ""; }
        public string canonical_url { get; set; default = ""; }
        public string sha256 { get; set; default = ""; }
        public Gee.ArrayList<string> keywords { get; owned set; }

        public ManualDescriptor () {
            keywords = new Gee.ArrayList<string> ();
        }
    }

    /**
     * Phase 6: GitHub-Hosted & Offline-First Documentation Hub Client.
     * Fetches manuals-manifest.json via libsoup-3.0 with ETag validation,
     * verifies SHA-256 checksums, caches manuals in ~/.cache/imladris/docs/,
     * and falls back seamlessly to bundled local manuals when offline or air-gapped.
     */
    public class DocsRepositoryClient : GLib.Object {
        private static DocsRepositoryClient? _default = null;

        public string manifest_url {
            get; set;
            default = "https://raw.githubusercontent.com/Antux912012/imladris/main/docs/manuals/manuals-manifest.json";
        }
        public string cache_dir { get; private set; }
        public Gee.ArrayList<ManualDescriptor> manuals { get; private set; }
        private Gee.HashMap<string, string> etags;
        private Soup.Session session;
        private string? extra_local_docs_dir = null;

        public signal void catalog_updated ();

        public static DocsRepositoryClient get_default () {
            if (_default == null) {
                _default = new DocsRepositoryClient ();
            }
            return _default;
        }

        public DocsRepositoryClient (string? custom_cache_dir = null, string? local_docs_dir = null) {
            this.cache_dir = custom_cache_dir ?? GLib.Path.build_filename (
                GLib.Environment.get_user_cache_dir (), "imladris", "docs"
            );
            this.extra_local_docs_dir = local_docs_dir;
            GLib.DirUtils.create_with_parents (this.cache_dir, 0755);

            this.manuals = new Gee.ArrayList<ManualDescriptor> ();
            this.etags = new Gee.HashMap<string, string> ();
            this.session = new Soup.Session () {
                timeout = 8,
                user_agent = "Imladris-HelpHub/1.0"
            };

            load_etags ();
            seed_cache_from_local_bundle_if_needed ();
            load_cached_manifest ();
        }

        private string etags_file_path () {
            return GLib.Path.build_filename (cache_dir, "etags.json");
        }

        private void load_etags () {
            string p = etags_file_path ();
            if (!GLib.FileUtils.test (p, GLib.FileTest.EXISTS)) return;
            try {
                string raw;
                GLib.FileUtils.get_contents (p, out raw);
                var parser = new Json.Parser ();
                parser.load_from_data (raw, -1);
                var obj = parser.get_root ().get_object ();
                foreach (string k in obj.get_members ()) {
                    etags.set (k, obj.get_string_member (k));
                }
            } catch (GLib.Error e) {}
        }

        private void save_etags () {
            try {
                var b = new Json.Builder ();
                b.begin_object ();
                foreach (var entry in etags.entries) {
                    b.set_member_name (entry.key);
                    b.add_string_value (entry.value);
                }
                b.end_object ();
                var gen = new Json.Generator ();
                gen.set_root (b.get_root ());
                GLib.FileUtils.set_contents (etags_file_path (), gen.to_data (null));
            } catch (GLib.Error e) {}
        }

        private Gee.ArrayList<string> candidate_local_dirs () {
            var dirs = new Gee.ArrayList<string> ();
            if (extra_local_docs_dir != null) {
                if (extra_local_docs_dir != "") {
                    dirs.add (extra_local_docs_dir);
                }
                return dirs;
            }
            dirs.add (GLib.Path.build_filename (GLib.Environment.get_current_dir (), "docs", "manuals"));
            foreach (string sys_dir in GLib.Environment.get_system_data_dirs ()) {
                dirs.add (GLib.Path.build_filename (sys_dir, "imladris", "manuals"));
            }
            dirs.add ("/app/share/imladris/manuals");
            dirs.add ("/usr/share/imladris/manuals");
            return dirs;
        }

        private void seed_cache_from_local_bundle_if_needed () {
            string cached_manifest = GLib.Path.build_filename (cache_dir, "manuals-manifest.json");
            foreach (string d in candidate_local_dirs ()) {
                string src_manifest = GLib.Path.build_filename (d, "manuals-manifest.json");
                if (GLib.FileUtils.test (src_manifest, GLib.FileTest.EXISTS)) {
                    if (!GLib.FileUtils.test (cached_manifest, GLib.FileTest.EXISTS)) {
                        copy_file_quiet (src_manifest, cached_manifest);
                    }
                    try {
                        var dir = GLib.Dir.open (d, 0);
                        string? name = null;
                        while ((name = dir.read_name ()) != null) {
                            if (name.has_suffix (".md")) {
                                string dst = GLib.Path.build_filename (cache_dir, name);
                                if (!GLib.FileUtils.test (dst, GLib.FileTest.EXISTS)) {
                                    copy_file_quiet (GLib.Path.build_filename (d, name), dst);
                                }
                            }
                        }
                    } catch (GLib.Error e) {}
                    break;
                }
            }
        }

        private static void copy_file_quiet (string src, string dst) {
            try {
                string txt;
                GLib.FileUtils.get_contents (src, out txt);
                GLib.FileUtils.set_contents (dst, txt);
            } catch (GLib.Error e) {}
        }

        public bool load_cached_manifest () {
            string p = GLib.Path.build_filename (cache_dir, "manuals-manifest.json");
            if (!GLib.FileUtils.test (p, GLib.FileTest.EXISTS)) return false;
            try {
                string raw;
                GLib.FileUtils.get_contents (p, out raw);
                parse_manifest_json (raw);
                return manuals.size > 0;
            } catch (GLib.Error e) {
                return false;
            }
        }

        public void parse_manifest_json (string json_text) throws GLib.Error {
            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new GLib.IOError.INVALID_DATA ("Invalid manuals-manifest.json root");
            }
            var obj = root.get_object ();
            if (!obj.has_member ("manuals")) return;

            manuals.clear ();
            var arr = obj.get_array_member ("manuals");
            for (uint i = 0; i < arr.get_length (); i++) {
                var m = arr.get_object_element (i);
                var d = new ManualDescriptor ();
                if (m.has_member ("id")) d.id = m.get_string_member ("id");
                if (m.has_member ("title")) d.title = m.get_string_member ("title");
                if (m.has_member ("track")) d.track = m.get_string_member ("track");
                if (m.has_member ("version")) d.version = m.get_string_member ("version");
                if (m.has_member ("filename")) d.filename = m.get_string_member ("filename");
                if (m.has_member ("remote_url")) d.remote_url = m.get_string_member ("remote_url");
                if (m.has_member ("canonical_url")) d.canonical_url = m.get_string_member ("canonical_url");
                if (m.has_member ("sha256")) d.sha256 = m.get_string_member ("sha256");
                if (m.has_member ("keywords") && m.get_member ("keywords").get_node_type () == Json.NodeType.ARRAY) {
                    var karr = m.get_array_member ("keywords");
                    for (uint k = 0; k < karr.get_length (); k++) {
                        d.keywords.add (karr.get_string_element (k));
                    }
                }
                if (d.id != "") manuals.add (d);
            }
            catalog_updated ();
        }

        private static string bytes_to_utf8 (GLib.Bytes b) {
            size_t sz = b.get_size ();
            if (sz == 0) return "";
            var sb = new GLib.StringBuilder.sized (sz + 1);
            sb.append_len ((string) b.get_data (), (ssize_t) sz);
            return sb.str;
        }

        /**
         * Refreshes manuals-manifest.json from GitHub using HTTP ETag conditional GET.
         * Returns true if updated or already current (HTTP 304).
         */
        public async bool refresh_manifest_async () {
            var msg = new Soup.Message ("GET", manifest_url);
            if (etags.has_key (manifest_url)) {
                msg.request_headers.append ("If-None-Match", etags.get (manifest_url));
            }
            try {
                var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
                if (msg.status_code == 304) {
                    return true;
                }
                if (msg.status_code == 200 && bytes != null && bytes.get_size () > 0) {
                    string body = bytes_to_utf8 (bytes);
                    parse_manifest_json (body);
                    GLib.FileUtils.set_contents (GLib.Path.build_filename (cache_dir, "manuals-manifest.json"), body);
                    string? new_etag = msg.response_headers.get_one ("ETag");
                    if (new_etag != null && new_etag != "") {
                        etags.set (manifest_url, new_etag);
                        save_etags ();
                    }
                    return true;
                }
            } catch (GLib.Error e) {}
            return manuals.size > 0;
        }

        public ManualDescriptor? find_manual (string manual_id) {
            foreach (var m in manuals) {
                if (m.id == manual_id) return m;
            }
            return null;
        }

        public bool is_cached_offline (ManualDescriptor m) {
            string path = GLib.Path.build_filename (cache_dir, m.filename);
            if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) return false;
            if (m.sha256 == "") return true;
            try {
                string txt;
                GLib.FileUtils.get_contents (path, out txt);
                string digest = GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA256, txt);
                return digest == m.sha256;
            } catch (GLib.Error e) {
                return false;
            }
        }

        /**
         * Loads Markdown content for a manual: checks verified local cache first,
         * fetches via ETag/SHA-256 from GitHub if needed, and falls back to cached/bundled copy offline.
         */
        public async string get_manual_markdown_async (string manual_id, bool force_network_check = false) {
            var m = find_manual (manual_id);
            if (m == null) {
                return @"# Manual Not Found\n\nNo manual registered with ID `$manual_id`.";
            }

            string cached_path = GLib.Path.build_filename (cache_dir, m.filename);
            if (!force_network_check && is_cached_offline (m)) {
                try {
                    string local_txt;
                    GLib.FileUtils.get_contents (cached_path, out local_txt);
                    return local_txt;
                } catch (GLib.Error e) {}
            }

            if (m.remote_url != "") {
                var msg = new Soup.Message ("GET", m.remote_url);
                if (etags.has_key (m.remote_url) && GLib.FileUtils.test (cached_path, GLib.FileTest.EXISTS)) {
                    msg.request_headers.append ("If-None-Match", etags.get (m.remote_url));
                }
                try {
                    var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
                    if (msg.status_code == 304 && is_cached_offline (m)) {
                        string cached_txt;
                        GLib.FileUtils.get_contents (cached_path, out cached_txt);
                        return cached_txt;
                    }
                    if (msg.status_code == 200 && bytes != null && bytes.get_size () > 0) {
                        string body = bytes_to_utf8 (bytes);
                        string actual_sha = GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA256, body);
                        if (m.sha256 == "" || actual_sha == m.sha256) {
                            GLib.FileUtils.set_contents (cached_path, body);
                            string? et = msg.response_headers.get_one ("ETag");
                            if (et != null && et != "") {
                                etags.set (m.remote_url, et);
                                save_etags ();
                            }
                            return body;
                        }
                    }
                } catch (GLib.Error e) {}
            }

            if (GLib.FileUtils.test (cached_path, GLib.FileTest.EXISTS)) {
                try {
                    string fallback_txt;
                    GLib.FileUtils.get_contents (cached_path, out fallback_txt);
                    return fallback_txt;
                } catch (GLib.Error e) {}
            }
            return @"# $(m.title) (Offline)\n\nConnect to GitHub or click **Download All Manuals** to cache `$(m.filename)`.";
        }

        public async int download_all_for_offline_async () {
            yield refresh_manifest_async ();
            int ok_count = 0;
            foreach (var m in manuals) {
                yield get_manual_markdown_async (m.id, true);
                if (is_cached_offline (m)) {
                    ok_count++;
                }
            }
            return ok_count;
        }

        /**
         * Contextual F1 / Right-Click Symbol Lookup across all 11 documentation domains.
         */
        public ManualDescriptor? lookup_symbol (string raw_symbol, string? file_ext_hint = null, bool allow_track_fallback = true) {
            string sym = raw_symbol.strip ().down ();
            if (sym == "") return null;

            // 1. Exact keyword match
            foreach (var m in manuals) {
                foreach (string kw in m.keywords) {
                    if (kw.down () == sym) return m;
                }
            }

            // 2. Substring match in keywords or title
            foreach (var m in manuals) {
                if (m.title.down ().contains (sym) || m.id.down ().contains (sym)) return m;
                foreach (string kw in m.keywords) {
                    if (kw.down ().contains (sym) || sym.contains (kw.down ())) return m;
                }
            }

            // 3. Full-text search across cached manuals
            foreach (var m in manuals) {
                string p = GLib.Path.build_filename (cache_dir, m.filename);
                if (GLib.FileUtils.test (p, GLib.FileTest.EXISTS)) {
                    try {
                        string body;
                        GLib.FileUtils.get_contents (p, out body);
                        if (body.down ().contains (sym)) return m;
                    } catch (GLib.Error e) {}
                }
            }

            if (!allow_track_fallback) return null;

            // 4. Fallback by active editor language hint
            if (file_ext_hint != null) {
                string h = file_ext_hint.down ();
                if (h == "r" || h == "rmd") return find_manual ("r-language");
                if (h == "py" || h == "python" || h == "ipynb") return find_manual ("python-libs");
                if (h == "sh" || h == "bash") return find_manual ("bash-linux");
                if (h == "ts" || h == "typescript") return find_manual ("typescript");
                if (h == "css") return find_manual ("css3");
                if (h == "html") return find_manual ("html5");
                if (h == "qmd" || h == "md") return find_manual ("markdown-quarto");
            }
            return manuals.size > 0 ? manuals[0] : null;
        }
    }
}
