// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Manages communication with Galaxy Project REST APIs.
 *
 * Architectural Position:
 * Core bridge in Imladris. Bridges cloud bioinformatics histories from Galaxy
 * instances directly to local data structures and Quarto source injection.
 * Downstream consumer: Imladris.UI.GalaxyPanel and Imladris.UI.GalaxyAuthDialog.
 * Upstream dependency: Soup 3.0, Json-GLib 1.0, Gee 0.8.
 *
 * Concurrency Constraints:
 * Runs asynchronous network I/O through Soup.Session. Completes all callbacks
 * on the GLib MainContext thread. Never blocks the GTK UI frame loop.
 */

using GLib;
using Gee;
using Soup;
using Json;

namespace Imladris.Bridges {

    /**
     * Enumerates operational execution states of Galaxy datasets.
     */
    public enum GalaxyDatasetState {
        OK,
        RUNNING,
        QUEUED,
        ERROR,
        DISCARDED,
        PAUSED,
        UPLOADING,
        UNKNOWN;

        public string to_id_string () {
            switch (this) {
                case OK: return "ok";
                case RUNNING: return "running";
                case QUEUED: return "queued";
                case ERROR: return "error";
                case DISCARDED: return "discarded";
                case PAUSED: return "paused";
                case UPLOADING: return "upload";
                default: return "unknown";
            }
        }

        public static GalaxyDatasetState from_string (string raw_state) {
            switch (raw_state.down ()) {
                case "ok": return OK;
                case "running": return RUNNING;
                case "queued": return QUEUED;
                case "error": return ERROR;
                case "discarded": return DISCARDED;
                case "paused": return PAUSED;
                case "upload": return UPLOADING;
                default: return UNKNOWN;
            }
        }

        public string get_badge_css_class () {
            switch (this) {
                case OK: return "success";
                case RUNNING: return "accent";
                case QUEUED: return "warning";
                case ERROR: return "error";
                default: return "dim-label";
            }
        }

        public string get_symbolic_icon () {
            switch (this) {
                case OK: return "emblem-ok-symbolic";
                case RUNNING: return "process-working-symbolic";
                case QUEUED: return "appointment-soon-symbolic";
                case ERROR: return "dialog-error-symbolic";
                default: return "dialog-information-symbolic";
            }
        }
    }

    /**
     * Represents a single bioinformatics dataset residing in a Galaxy history.
     */
    public class GalaxyDataset : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string history_id { get; construct set; default = ""; }
        public string name { get; construct set; default = ""; }
        public string extension { get; construct set; default = ""; }
        public GalaxyDatasetState state { get; construct set; default = GalaxyDatasetState.UNKNOWN; }
        public int64 file_size { get; construct set; default = 0; }
        public string download_url { get; construct set; default = ""; }
        public string create_time { get; construct set; default = ""; }
        public string misc_info { get; construct set; default = ""; }

        public GalaxyDataset (
            string id,
            string history_id,
            string name,
            string extension,
            GalaxyDatasetState state,
            int64 file_size,
            string download_url,
            string create_time = "",
            string misc_info = ""
        ) {
            GLib.Object (
                id: id,
                history_id: history_id,
                name: name,
                extension: extension,
                state: state,
                file_size: file_size,
                download_url: download_url,
                create_time: create_time,
                misc_info: misc_info
            );
        }

        /**
         * Sanitizes dataset name into an alphanumeric variable identifier.
         */
        public string get_safe_variable_name () {
            var builder = new StringBuilder ();
            string clean_name = name.down ();
            for (int i = 0; i < clean_name.length; i++) {
                unichar c = clean_name.get_char (i);
                if (c.isalnum ()) {
                    builder.append_unichar (c);
                } else {
                    builder.append_c ('_');
                }
            }
            string res = builder.str.strip ();
            while ("__" in res) {
                res = res.replace ("__", "_");
            }
            if (res.has_prefix ("_")) {
                res = res.substring (1);
            }
            if (res.has_suffix ("_")) {
                res = res.substring (0, res.length - 1);
            }
            return res.length > 0 ? res : "dataset";
        }

        /**
         * Formats human-readable byte sizes for UI display.
         */
        public string get_formatted_size () {
            if (file_size <= 0) return "0 B";
            if (file_size < 1024) return @"$(file_size) B";
            if (file_size < 1024 * 1024) {
                double kb = (double) file_size / 1024.0;
                return "%.1f KB".printf (kb);
            }
            if (file_size < 1024 * 1024 * 1024) {
                double mb = (double) file_size / (1024.0 * 1024.0);
                return "%.1f MB".printf (mb);
            }
            double gb = (double) file_size / (1024.0 * 1024.0 * 1024.0);
            return "%.2f GB".printf (gb);
        }

        /**
         * Generates reproducible R code block for Quarto documents.
         */
        public string generate_r_quarto_chunk (string server_url) {
            string safe_var = get_safe_variable_name ();
            string resolved_url = download_url.length > 0 ? download_url : @"$(server_url)/api/datasets/$(id)/display";

            return "```{r galaxy_pull_" + id + ", message=FALSE}\n" +
                   "# Imladris Provenance Anchor: Galaxy History `" + history_id + "` Dataset `" + id + "`\n" +
                   "# Server: `" + server_url + "`\n" +
                   "library(httr)\n\n" +
                   "imladris_fetch_dataset <- function(file_url, api_key) {\n" +
                   "  response <- GET(file_url, add_headers(\"X-API-Key\" = api_key))\n" +
                   "  content(response, \"text\", encoding = \"UTF-8\")\n" +
                   "}\n\n" +
                   "# Fetch dataset into local dataframe\n" +
                   "df_" + safe_var + " <- read.delim(\n" +
                   "  text = imladris_fetch_dataset(\"" + resolved_url + "\", Sys.getenv(\"GALAXY_API_KEY\")),\n" +
                   "  header = TRUE,\n" +
                   "  sep = \"\\t\"\n" +
                   ")\n" +
                   "```\n";
        }

        /**
         * Generates reproducible Python code block for Quarto documents.
         */
        public string generate_python_quarto_chunk (string server_url) {
            string safe_var = get_safe_variable_name ();
            string resolved_url = download_url.length > 0 ? download_url : @"$(server_url)/api/datasets/$(id)/display";

            return "```{python galaxy_pull_" + id + "}\n" +
                   "# Imladris Provenance Anchor: Galaxy History `" + history_id + "` Dataset `" + id + "`\n" +
                   "# Server: `" + server_url + "`\n" +
                   "import os\n" +
                   "import io\n" +
                   "import requests\n" +
                   "import pandas as pd\n\n" +
                   "api_key = os.environ.get(\"GALAXY_API_KEY\", \"\")\n" +
                   "headers = {\"X-API-Key\": api_key} if api_key else {}\n" +
                   "response = requests.get(\"" + resolved_url + "\", headers=headers)\n" +
                   "response.raise_for_status()\n\n" +
                   "# Fetch dataset into local dataframe\n" +
                   "df_" + safe_var + " = pd.read_csv(io.StringIO(response.text), sep=\"\\t\")\n" +
                   "```\n";
        }
    }

    /**
     * Represents a remote Galaxy History containing bioinformatics datasets.
     */
    public class GalaxyHistory : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string name { get; construct set; default = ""; }
        public bool published { get; construct set; default = false; }
        public bool deleted { get; construct set; default = false; }
        public string update_time { get; construct set; default = ""; }
        public Gee.ArrayList<GalaxyDataset> datasets { get; private set; }
        public bool is_loaded { get; set; default = false; }

        public GalaxyHistory (
            string id,
            string name,
            bool published = false,
            bool deleted = false,
            string update_time = ""
        ) {
            GLib.Object (
                id: id,
                name: name,
                published: published,
                deleted: deleted,
                update_time: update_time
            );
            this.datasets = new Gee.ArrayList<GalaxyDataset> ();
        }
    }

    /**
     * Represents authenticated Galaxy user identity and quota information.
     */
    public class GalaxyUser : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string username { get; construct set; default = ""; }
        public string email { get; construct set; default = ""; }
        public double total_disk_usage { get; construct set; default = 0.0; }

        public GalaxyUser (string id, string username, string email, double total_disk_usage = 0.0) {
            GLib.Object (
                id: id,
                username: username,
                email: email,
                total_disk_usage: total_disk_usage
            );
        }
    }

    /**
     * Native asynchronous client for the Galaxy REST API.
     */
    public class GalaxyClient : GLib.Object {
        private static GalaxyClient? instance = null;

        private Soup.Session session;
        private string _server_url = "https://usegalaxy.eu";
        private string _api_key = "";
        private GalaxyUser? _current_user = null;
        private bool _is_authenticated = false;

        public string server_url {
            get { return _server_url; }
            set {
                string trimmed = value.strip ();
                if (trimmed.has_suffix ("/")) {
                    _server_url = trimmed.substring (0, trimmed.length - 1);
                } else {
                    _server_url = trimmed;
                }
            }
        }

        public string api_key {
            get { return _api_key; }
            set { _api_key = value.strip (); }
        }

        public bool is_authenticated {
            get { return _is_authenticated; }
            private set {
                if (_is_authenticated != value) {
                    _is_authenticated = value;
                    authenticated_changed (value);
                }
            }
        }

        public GalaxyUser? current_user {
            get { return _current_user; }
            private set { _current_user = value; }
        }

        public signal void authenticated_changed (bool auth_state);
        public signal void histories_loaded (Gee.ArrayList<GalaxyHistory> list);
        public signal void datasets_loaded (string history_id, Gee.ArrayList<GalaxyDataset> list);
        public signal void error_occurred (string error_message);

        public static GalaxyClient get_default () {
            if (instance == null) {
                instance = new GalaxyClient ();
            }
            return instance;
        }

        public GalaxyClient () {
            this.session = new Soup.Session () {
                timeout = 15,
                user_agent = "Imladris-Scientific-Workbench/1.0"
            };

            load_credentials ();
        }

        /**
         * Loads server URL and API key from local user configuration.
         */
        public void load_credentials () {
            // Check environment variables first
            string? env_url = Environment.get_variable ("GALAXY_SERVER_URL");
            if (env_url != null && env_url.length > 0) {
                this.server_url = env_url;
            }

            string? env_key = Environment.get_variable ("GALAXY_API_KEY");
            if (env_key != null && env_key.length > 0) {
                this.api_key = env_key;
            }

            // Fallback to local settings file
            string conf_dir = GLib.Path.build_filename (Environment.get_user_config_dir (), "imladris");
            string ini_path = GLib.Path.build_filename (conf_dir, "settings.ini");

            if (FileUtils.test (ini_path, FileTest.EXISTS)) {
                var kf = new KeyFile ();
                try {
                    kf.load_from_file (ini_path, KeyFileFlags.NONE);
                    if (kf.has_key ("Galaxy", "server_url") && (env_url == null || env_url.length == 0)) {
                        this.server_url = kf.get_string ("Galaxy", "server_url");
                    }
                    if (kf.has_key ("Galaxy", "api_key") && (env_key == null || env_key.length == 0)) {
                        this.api_key = kf.get_string ("Galaxy", "api_key");
                    }
                } catch (GLib.Error e) {
                    debug ("Could not read Galaxy settings from ini: %s", e.message);
                }
            }
        }

        /**
         * Persists credentials to local configuration with restrictive permissions.
         */
        public void save_credentials (string server, string key) {
            this.server_url = server;
            this.api_key = key;

            string conf_dir = GLib.Path.build_filename (Environment.get_user_config_dir (), "imladris");
            DirUtils.create_with_parents (conf_dir, 0700);
            string ini_path = GLib.Path.build_filename (conf_dir, "settings.ini");

            var kf = new KeyFile ();
            if (FileUtils.test (ini_path, FileTest.EXISTS)) {
                try {
                    kf.load_from_file (ini_path, KeyFileFlags.NONE);
                } catch (GLib.Error e) {
                    // Start fresh
                }
            }

            kf.set_string ("Galaxy", "server_url", this.server_url);
            kf.set_string ("Galaxy", "api_key", this.api_key);

            try {
                string data = kf.to_data ();
                FileUtils.set_contents (ini_path, data);
                // Restrict permissions to owner read/write (0600)
                FileUtils.chmod (ini_path, 0600);
            } catch (GLib.Error e) {
                warning ("Failed to save Galaxy credentials: %s", e.message);
            }
        }

        /**
         * Sends an authenticated HTTP GET request to the specified endpoint.
         */
        private async Bytes? send_get_request_async (string endpoint, string? custom_key = null) throws GLib.Error {
            string effective_key = custom_key != null ? custom_key : this.api_key;
            string url = endpoint.has_prefix ("http") ? endpoint : @"$(_server_url)$(endpoint)";

            var msg = new Soup.Message ("GET", url);
            if (effective_key.length > 0) {
                msg.request_headers.append ("x-api-key", effective_key);
            }
            msg.request_headers.append ("Accept", "application/json");

            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            uint status = msg.status_code;

            if (status == 401 || status == 403) {
                this.is_authenticated = false;
                throw new GLib.IOError.PERMISSION_DENIED ("Galaxy API authentication failed. Verify API key.");
            }

            if (status != 200) {
                throw new GLib.IOError.FAILED (@"Galaxy server returned HTTP $(status): $(msg.reason_phrase)");
            }

            return bytes;
        }

        /**
         * Tests authentication by requesting user profile data from /api/whoami.
         */
        public async GalaxyUser test_connection_async (string? test_server = null, string? test_key = null) throws GLib.Error {
            string original_server = this._server_url;
            if (test_server != null && test_server.length > 0) {
                this.server_url = test_server;
            }

            try {
                var bytes = yield send_get_request_async ("/api/whoami", test_key);
                if (bytes == null) {
                    throw new GLib.IOError.FAILED ("Received empty response from Galaxy server.");
                }

                string json_text = (string) bytes.get_data ();
                var parser = new Json.Parser ();
                parser.load_from_data (json_text, -1);

                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    throw new GLib.IOError.INVALID_DATA ("Invalid JSON returned by /api/whoami.");
                }

                var obj = root.get_object ();
                string user_id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
                string username = obj.has_member ("username") ? obj.get_string_member ("username") : "";
                string email = obj.has_member ("email") ? obj.get_string_member ("email") : "";
                double disk_usage = obj.has_member ("total_disk_usage") ? obj.get_double_member ("total_disk_usage") : 0.0;

                var user = new GalaxyUser (user_id, username, email, disk_usage);
                this.current_user = user;
                this.is_authenticated = true;

                if (test_key != null) {
                    this.api_key = test_key;
                }

                return user;
            } catch (GLib.Error e) {
                this.is_authenticated = false;
                this._server_url = original_server;
                throw e;
            }
        }

        /**
         * Fetches all active user histories from /api/histories.
         */
        public async Gee.ArrayList<GalaxyHistory> fetch_histories_async () throws GLib.Error {
            var result = new Gee.ArrayList<GalaxyHistory> ();
            var bytes = yield send_get_request_async ("/api/histories");
            if (bytes == null) return result;

            string json_text = (string) bytes.get_data ();
            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                return result;
            }

            var arr = root.get_array ();
            uint len = arr.get_length ();

            for (uint i = 0; i < len; i++) {
                var item_node = arr.get_element (i);
                if (item_node.get_node_type () != Json.NodeType.OBJECT) continue;

                var obj = item_node.get_object ();
                string h_id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
                string h_name = obj.has_member ("name") ? obj.get_string_member ("name") : "Unnamed History";
                bool deleted = obj.has_member ("deleted") ? obj.get_boolean_member ("deleted") : false;
                bool published = obj.has_member ("published") ? obj.get_boolean_member ("published") : false;
                string update_time = obj.has_member ("update_time") ? obj.get_string_member ("update_time") : "";

                if (!deleted) {
                    result.add (new GalaxyHistory (h_id, h_name, published, deleted, update_time));
                }
            }

            histories_loaded (result);
            return result;
        }

        /**
         * Fetches all datasets within a specific history from /api/histories/{id}/contents.
         */
        public async Gee.ArrayList<GalaxyDataset> fetch_datasets_async (string history_id) throws GLib.Error {
            var result = new Gee.ArrayList<GalaxyDataset> ();
            string endpoint = @"/api/histories/$(history_id)/contents";

            var bytes = yield send_get_request_async (endpoint);
            if (bytes == null) return result;

            string json_text = (string) bytes.get_data ();
            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                return result;
            }

            var arr = root.get_array ();
            uint len = arr.get_length ();

            for (uint i = 0; i < len; i++) {
                var item_node = arr.get_element (i);
                if (item_node.get_node_type () != Json.NodeType.OBJECT) continue;

                var obj = item_node.get_object ();

                // Check if element is a dataset (type == "file" or history_content_type == "dataset")
                string content_type = obj.has_member ("history_content_type") ? obj.get_string_member ("history_content_type") : "dataset";
                if (content_type != "dataset") continue;

                string d_id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
                string d_name = obj.has_member ("name") ? obj.get_string_member ("name") : "Unnamed Dataset";
                string d_ext = obj.has_member ("extension") ? obj.get_string_member ("extension") : "";
                string d_raw_state = obj.has_member ("state") ? obj.get_string_member ("state") : "unknown";
                GalaxyDatasetState d_state = GalaxyDatasetState.from_string (d_raw_state);
                int64 d_size = obj.has_member ("file_size") ? obj.get_int_member ("file_size") : 0;
                string d_url = @"$(_server_url)/api/datasets/$(d_id)/display";
                string create_time = obj.has_member ("create_time") ? obj.get_string_member ("create_time") : "";
                string misc_info = obj.has_member ("misc_info") ? obj.get_string_member ("misc_info") : "";

                result.add (new GalaxyDataset (
                    d_id,
                    history_id,
                    d_name,
                    d_ext,
                    d_state,
                    d_size,
                    d_url,
                    create_time,
                    misc_info
                ));
            }

            datasets_loaded (history_id, result);
            return result;
        }

        /**
         * Fetches detailed dataset metadata from /api/datasets/{dataset_id}.
         */
        public async GalaxyDataset? fetch_dataset_metadata_async (string dataset_id) throws GLib.Error {
            string endpoint = @"/api/datasets/$(dataset_id)";
            var bytes = yield send_get_request_async (endpoint);
            if (bytes == null) return null;

            string json_text = (string) bytes.get_data ();
            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                return null;
            }

            var obj = root.get_object ();
            string d_id = obj.has_member ("id") ? obj.get_string_member ("id") : dataset_id;
            string h_id = obj.has_member ("history_id") ? obj.get_string_member ("history_id") : "";
            string d_name = obj.has_member ("name") ? obj.get_string_member ("name") : "Unnamed Dataset";
            string d_ext = obj.has_member ("file_ext") ? obj.get_string_member ("file_ext") : "";
            string d_raw_state = obj.has_member ("state") ? obj.get_string_member ("state") : "unknown";
            GalaxyDatasetState d_state = GalaxyDatasetState.from_string (d_raw_state);
            int64 d_size = obj.has_member ("file_size") ? obj.get_int_member ("file_size") : 0;
            string d_url = @"$(_server_url)/api/datasets/$(d_id)/display";
            string create_time = obj.has_member ("create_time") ? obj.get_string_member ("create_time") : "";
            string misc_info = obj.has_member ("misc_info") ? obj.get_string_member ("misc_info") : "";

            return new GalaxyDataset (
                d_id,
                h_id,
                d_name,
                d_ext,
                d_state,
                d_size,
                d_url,
                create_time,
                misc_info
            );
        }
    }
}
