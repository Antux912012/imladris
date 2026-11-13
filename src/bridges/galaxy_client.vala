// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Manages communication with Galaxy Project REST APIs and OS Keyring.
 *
 * Architectural Position:
 * Core network bridge in Imladris. Connects cloud bioinformatics histories from Galaxy
 * instances directly to local data structures and Quarto source injection.
 * Downstream consumers: Imladris.GalaxyPanel, Imladris.UI.PreferencesDialog.
 * Upstream dependencies: libsoup-3.0, json-glib-1.0, libsecret-1, gio-2.0.
 *
 * Concurrency Constraints:
 * Runs asynchronous network I/O through Soup.Session.send_and_read_async. Completes
 * all callbacks on the GLib MainContext thread. Never blocks the GTK UI frame loop.
 */

using GLib;
using Soup;
using Json;
using Secret;

namespace Imladris {

    /**
     * Typed error domain for Galaxy REST API and communication failures.
     */
    public errordomain GalaxyError {
        UNAUTHORIZED,
        NOT_FOUND,
        SERVER_ERROR,
        NETWORK_ERROR,
        INVALID_DATA
    }

    /**
     * Represents authenticated Galaxy user identity.
     */
    public class GalaxyUser : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string username { get; construct set; default = ""; }
        public string email { get; construct set; default = ""; }
        public double total_disk_usage { get; construct set; default = 0.0; }

        /**
         * Constructs a GalaxyUser identity object.
         */
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
     * Asynchronous REST and Secret Service client for the Galaxy bioinformatics platform.
     */
    public class GalaxyClient : GLib.Object {
        private static GalaxyClient? instance = null;
        private static Secret.Schema? secret_schema = null;

        private Soup.Session session;
        private string _server_url = "https://usegalaxy.eu";
        private string _api_key = "";
        private bool _is_authenticated = false;
        private string _current_user_identity = "";
        private GLib.Settings? settings = null;

        /**
         * Base URL of the target Galaxy instance.
         */
        public string server_url {
            get { return _server_url; }
            set {
                string trimmed = value.strip ();
                while (trimmed.has_suffix ("/")) {
                    trimmed = trimmed.substring (0, trimmed.length - 1);
                }
                if (trimmed.length == 0) {
                    _server_url = "https://usegalaxy.eu";
                } else {
                    _server_url = trimmed;
                }

                GLib.Environment.set_variable ("GALAXY_SERVER_URL", _server_url, true);

                if (settings != null) {
                    settings.set_string ("galaxy-server-url", _server_url);
                }
            }
        }

        /**
         * Cached Galaxy API Key stored in volatile memory.
         */
        public string api_key {
            get { return _api_key; }
            set {
                _api_key = value.strip ();
                if (_api_key.length > 0) {
                    GLib.Environment.set_variable ("GALAXY_API_KEY", _api_key, true);
                }
            }
        }

        /**
         * Current authentication status flag.
         */
        public bool is_authenticated {
            get { return _is_authenticated; }
            private set {
                if (_is_authenticated != value) {
                    _is_authenticated = value;
                    authenticated_changed (value);
                }
            }
        }

        /**
         * Username or email of the active authenticated user.
         */
        public string current_user_identity {
            get { return _current_user_identity; }
            private set { _current_user_identity = value; }
        }

        public signal void authenticated_changed (bool auth_state);
        public signal void histories_loaded (GLib.GenericArray<GalaxyHistory> list);
        public signal void datasets_loaded (string history_id, GLib.GenericArray<GalaxyDataset> list);
        public signal void error_occurred (string error_message);

        /**
         * Returns Secret.Schema definition for storing Galaxy API keys in OS Keyring.
         *
         * @return Libsecret schema for org.ardatech.Imladris.GalaxyApiKey.
         */
        public static Secret.Schema get_secret_schema () {
            if (secret_schema == null) {
                secret_schema = new Secret.Schema (
                    "org.ardatech.Imladris.GalaxyApiKey",
                    Secret.SchemaFlags.NONE,
                    "server_url", Secret.SchemaAttributeType.STRING
                );
            }
            return secret_schema;
        }

        /**
         * Returns singleton instance of GalaxyClient.
         *
         * @return Shared GalaxyClient reference.
         */
        public static GalaxyClient get_default () {
            if (instance == null) {
                instance = new GalaxyClient ();
            }
            return instance;
        }

        /**
         * Constructs a new GalaxyClient instance.
         */
        public GalaxyClient () {
            this.session = new Soup.Session () {
                timeout = 25,
                user_agent = "Imladris-Workbench/1.0 (GTK4; Vala)"
            };

            init_settings ();
            load_initial_configuration ();
        }

        /**
         * Connects GSettings schema if available on the system.
         */
        private void init_settings () {
            var default_source = GLib.SettingsSchemaSource.get_default ();
            if (default_source != null) {
                var schema = default_source.lookup ("io.github.Antux912012.Imladris", true);
                if (schema != null && schema.has_key ("galaxy-server-url")) {
                    this.settings = new GLib.Settings ("io.github.Antux912012.Imladris");
                }
            }
        }

        /**
         * Loads initial server URL and API key from environment, GSettings, or Keyring.
         */
        private void load_initial_configuration () {
            // 1. Server URL resolution
            string? env_url = GLib.Environment.get_variable ("GALAXY_SERVER_URL");
            if (env_url != null && env_url.strip ().length > 0) {
                this.server_url = env_url;
            } else if (settings != null) {
                string saved_url = settings.get_string ("galaxy-server-url");
                if (saved_url.strip ().length > 0) {
                    this.server_url = saved_url;
                }
            }

            // 2. API Key resolution from environment
            string? env_key = GLib.Environment.get_variable ("GALAXY_API_KEY");
            if (env_key != null && env_key.strip ().length > 0) {
                this.api_key = env_key;
            } else if (GLib.Environment.get_variable ("DBUS_SESSION_BUS_ADDRESS") != null) {
                // Asynchronously attempt to load from Secret Service when session bus exists
                load_api_key_async.begin (this.server_url, (obj, res) => {
                    try {
                        string? retrieved_key = load_api_key_async.end (res);
                        if (retrieved_key != null && retrieved_key.length > 0) {
                            this.api_key = retrieved_key;
                        }
                    } catch (GLib.Error e) {
                        // Secret service may be absent in non-interactive environment
                    }
                });
            }
        }

        /**
         * Persists credentials to OS Keyring and local settings.
         *
         * @param target_server_url Remote Galaxy server address.
         * @param target_api_key Sensitive user API authentication token.
         */
        public async void save_credentials_async (string target_server_url, string target_api_key) throws GLib.Error {
            this.server_url = target_server_url;
            this.api_key = target_api_key;

            string label = @"Galaxy API Key for $(this.server_url)";
            yield Secret.password_store (
                get_secret_schema (),
                Secret.COLLECTION_DEFAULT,
                label,
                this.api_key,
                null,
                "server_url", this.server_url
            );
        }

        /**
         * Retrieves stored API key for a specific Galaxy server from the OS Keyring.
         *
         * @param target_server_url Remote Galaxy server address.
         * @return API key token string or null if not found.
         */
        public async string? load_api_key_async (string target_server_url) throws GLib.Error {
            string normalized = target_server_url.strip ();
            while (normalized.has_suffix ("/")) {
                normalized = normalized.substring (0, normalized.length - 1);
            }

            string? env_key = GLib.Environment.get_variable ("GALAXY_API_KEY");
            if (env_key != null && env_key.strip ().length > 0) {
                this.api_key = env_key.strip ();
                return this.api_key;
            }

            string? stored_key = yield Secret.password_lookup (
                get_secret_schema (),
                null,
                "server_url", normalized
            );

            if (stored_key != null && stored_key.length > 0) {
                this.api_key = stored_key;
                return stored_key;
            }

            return null;
        }

        /**
         * Synchronous credential persistence method for settings dialogs.
         */
        public void save_credentials (string server, string key) {
            save_credentials_async.begin (server, key, (obj, res) => {
                try {
                    save_credentials_async.end (res);
                } catch (GLib.Error e) {
                    warning ("Failed to save Galaxy credentials to keyring: %s", e.message);
                }
            });
        }

        /**
         * Sends authenticated HTTP GET request to Galaxy server and validates status.
         *
         * @param endpoint Relative API endpoint or full HTTP URL.
         * @param cancellable Optional cancellation object.
         * @return Byte payload of server response.
         * @throws GLib.Error on network, authentication, or protocol failure.
         */
        public async GLib.Bytes send_galaxy_get_async (
            string endpoint,
            GLib.Cancellable? cancellable = null
        ) throws GLib.Error {
            string full_url = endpoint.has_prefix ("http")
                ? endpoint
                : @"$(_server_url)$(endpoint)";

            var msg = new Soup.Message ("GET", full_url);

            if (_api_key.length > 0) {
                msg.request_headers.append ("x-api-key", _api_key);
            }
            msg.request_headers.append ("Accept", "application/json");
            msg.request_headers.append ("User-Agent", "Imladris-Workbench/1.0 (GTK4; Vala)");

            GLib.Bytes bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
            uint status = msg.status_code;

            if (status == 401 || status == 403) {
                this.is_authenticated = false;
                throw new GalaxyError.UNAUTHORIZED ("Galaxy API authentication failed. Verify API key.");
            }

            if (status == 404) {
                throw new GalaxyError.NOT_FOUND (@"Resource not found at: $(full_url)");
            }

            if (status >= 500) {
                throw new GalaxyError.SERVER_ERROR (@"Galaxy server returned HTTP $(status): $(msg.reason_phrase)");
            }

            if (status != 200) {
                throw new GalaxyError.NETWORK_ERROR (@"Galaxy request failed with HTTP $(status): $(msg.reason_phrase)");
            }

            return bytes;
        }

        /**
         * Validates authentication against /api/whoami and returns user identity string.
         *
         * @param cancellable Optional cancellation object.
         * @return Authenticated username or email address string.
         * @throws GLib.Error when authentication or parsing fails.
         */
        public async string verify_connection_async (GLib.Cancellable? cancellable = null) throws GLib.Error {
            var bytes = yield send_galaxy_get_async ("/api/whoami", cancellable);
            string json_text = Core.PlatformUtils.bytes_to_string (bytes);

            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new GalaxyError.INVALID_DATA ("Invalid JSON returned by /api/whoami.");
            }

            var obj = root.get_object ();
            string username = obj.has_member ("username") ? obj.get_string_member ("username") : "";
            string email = obj.has_member ("email") ? obj.get_string_member ("email") : "";

            string identity = (username.length > 0) ? username : email;
            if (identity.length == 0) {
                identity = "Authenticated User";
            }

            this.current_user_identity = identity;
            this.is_authenticated = true;

            return identity;
        }

        /**
         * Backwards-compatible connection test method returning GalaxyUser model.
         */
        public async GalaxyUser test_connection_async (
            string? test_server = null,
            string? test_key = null
        ) throws GLib.Error {
            if (test_server != null && test_server.strip ().length > 0) {
                this.server_url = test_server;
            }
            if (test_key != null) {
                this.api_key = test_key;
            }

            var bytes = yield send_galaxy_get_async ("/api/whoami", null);
            string json_text = Core.PlatformUtils.bytes_to_string (bytes);

            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new GalaxyError.INVALID_DATA ("Invalid JSON returned by /api/whoami.");
            }

            var obj = root.get_object ();
            string u_id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
            string username = obj.has_member ("username") ? obj.get_string_member ("username") : "";
            string email = obj.has_member ("email") ? obj.get_string_member ("email") : "";
            double usage = obj.has_member ("total_disk_usage") ? obj.get_double_member ("total_disk_usage") : 0.0;

            this.current_user_identity = (username.length > 0) ? username : email;
            this.is_authenticated = true;

            return new GalaxyUser (u_id, username, email, usage);
        }

        /**
         * Fetches user histories from /api/histories.
         *
         * @param cancellable Optional cancellation object.
         * @return Array of GalaxyHistory domain models.
         * @throws GLib.Error on communication or parsing errors.
         */
        public async GLib.GenericArray<GalaxyHistory> fetch_histories_async (
            GLib.Cancellable? cancellable = null
        ) throws GLib.Error {
            var result = new GLib.GenericArray<GalaxyHistory> ();
            string endpoint = "/api/histories?deleted=false&order=update_time-dsc&limit=50";

            var bytes = yield send_galaxy_get_async (endpoint, cancellable);
            string json_text = Core.PlatformUtils.bytes_to_string (bytes);

            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                histories_loaded (result);
                return result;
            }

            var arr = root.get_array ();
            uint len = arr.get_length ();

            for (uint i = 0; i < len; i++) {
                var node = arr.get_element (i);
                if (node.get_node_type () != Json.NodeType.OBJECT) continue;

                var obj = node.get_object ();
                string h_id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
                string h_name = obj.has_member ("name") ? obj.get_string_member ("name") : "Unnamed History";
                string u_time = obj.has_member ("update_time") ? obj.get_string_member ("update_time") : "";
                bool deleted = obj.has_member ("deleted") ? obj.get_boolean_member ("deleted") : false;

                if (!deleted && h_id.length > 0) {
                    result.add (new GalaxyHistory (h_id, h_name, u_time, deleted));
                }
            }

            histories_loaded (result);
            return result;
        }

        /**
         * Fetches datasets within a specific history from /api/histories/{id}/contents.
         *
         * @param history_id Encoded history identifier.
         * @param cancellable Optional cancellation object.
         * @return Array of GalaxyDataset domain models.
         * @throws GLib.Error on communication or parsing errors.
         */
        public async GLib.GenericArray<GalaxyDataset> fetch_history_datasets_async (
            string history_id,
            GLib.Cancellable? cancellable = null
        ) throws GLib.Error {
            var result = new GLib.GenericArray<GalaxyDataset> ();
            string endpoint = @"/api/histories/$(history_id)/contents?type=file&deleted=false&visible=true";

            var bytes = yield send_galaxy_get_async (endpoint, cancellable);
            string json_text = Core.PlatformUtils.bytes_to_string (bytes);

            var parser = new Json.Parser ();
            parser.load_from_data (json_text, -1);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                datasets_loaded (history_id, result);
                return result;
            }

            var arr = root.get_array ();
            uint len = arr.get_length ();

            for (uint i = 0; i < len; i++) {
                var node = arr.get_element (i);
                if (node.get_node_type () != Json.NodeType.OBJECT) continue;

                var obj = node.get_object ();

                // Check content type
                string content_type = obj.has_member ("history_content_type")
                    ? obj.get_string_member ("history_content_type")
                    : (obj.has_member ("type") ? obj.get_string_member ("type") : "dataset");
                if (content_type != "dataset" && content_type != "file") continue;

                string d_id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
                if (d_id.length == 0) continue;

                int hid = (int) (obj.has_member ("hid") ? obj.get_int_member ("hid") : (i + 1));
                string d_name = obj.has_member ("name") ? obj.get_string_member ("name") : "Unnamed Dataset";

                string d_ext = "tabular";
                if (obj.has_member ("extension")) {
                    d_ext = obj.get_string_member ("extension");
                } else if (obj.has_member ("file_ext")) {
                    d_ext = obj.get_string_member ("file_ext");
                }

                string d_state = obj.has_member ("state") ? obj.get_string_member ("state") : "ok";
                int64 d_size = obj.has_member ("file_size") ? obj.get_int_member ("file_size") : 0;
                string d_url = @"$(_server_url)/api/histories/$(history_id)/contents/$(d_id)/display";

                result.add (new GalaxyDataset (
                    d_id,
                    history_id,
                    hid,
                    d_name,
                    d_ext,
                    d_state,
                    d_size,
                    d_url
                ));
            }

            datasets_loaded (history_id, result);
            return result;
        }
    }
}
