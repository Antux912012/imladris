// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Single Responsibility: Asynchronous REST client for self-hosted Imladris on Web instances.
 *
 * Compatible with imladris-on-web Fastify API:
 *   GET  /health
 *   POST /api/auth/login | /api/auth/register | /api/auth/logout | GET /api/auth/me
 *   GET  /api/workspaces | POST /api/workspaces | POST /api/workspaces/:id/invites
 *   POST /api/workspaces/:id/files | GET /api/workspaces/:id/files/content
 *   POST /api/workspaces/:id/revisions | GET /api/workspaces/:id/snapshots
 */

using GLib;
using Soup;
using Json;
using Secret;

namespace Imladris.Bridges.WebSync {

    public class WebSyncClient : GLib.Object {
        private static WebSyncClient? instance = null;

        private Soup.Session session;
        private Soup.CookieJar cookie_jar;
        private string _instance_url = "http://localhost:8787";
        private string _session_cookie = "";
        private WebUser? _current_user = null;
        private bool _is_online = false;

        public string instance_url {
            get { return _instance_url; }
            set {
                string trimmed = value.strip ();
                while (trimmed.has_suffix ("/")) {
                    trimmed = trimmed.substring (0, trimmed.length - 1);
                }
                if (trimmed.length == 0) {
                    _instance_url = "http://localhost:8787";
                } else {
                    _instance_url = trimmed;
                }
                save_config_metadata ();
            }
        }

        public WebUser? current_user {
            get { return _current_user; }
        }

        public bool is_authenticated {
            get { return _current_user != null && _session_cookie.length > 0; }
        }

        public bool is_online {
            get { return _is_online; }
            private set {
                if (_is_online != value) {
                    _is_online = value;
                    online_state_changed (value);
                }
            }
        }

        public signal void auth_state_changed (bool authenticated, WebUser? user);
        public signal void online_state_changed (bool online);

        private static Secret.Schema? _web_secret_schema = null;

        public static Secret.Schema get_secret_schema () {
            if (_web_secret_schema == null) {
                _web_secret_schema = new Secret.Schema (
                    "io.github.Antux912012.Imladris.WebSyncSession",
                    Secret.SchemaFlags.NONE,
                    "instance_url", Secret.SchemaAttributeType.STRING
                );
            }
            return _web_secret_schema;
        }

        public static WebSyncClient get_default () {
            if (instance == null) {
                instance = new WebSyncClient ();
            }
            return instance;
        }

        public WebSyncClient () {
            this.session = new Soup.Session () {
                timeout = 18,
                user_agent = "Imladris-Desktop/0.43 (GTK4; Vala)"
            };
            this.cookie_jar = new Soup.CookieJar ();
            this.session.add_feature (cookie_jar);

            load_config_metadata ();
            load_saved_session_token ();
        }

        private string get_config_dir () {
            string dir = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "imladris");
            GLib.DirUtils.create_with_parents (dir, 0755);
            return dir;
        }

        private string get_config_path () {
            return GLib.Path.build_filename (get_config_dir (), "web-sync.json");
        }

        private string get_fallback_token_path () {
            return GLib.Path.build_filename (get_config_dir (), ".web-sync-token");
        }

        private void save_config_metadata () {
            try {
                var b = new Json.Builder ();
                b.begin_object ();
                b.set_member_name ("instanceUrl");
                b.add_string_value (_instance_url);
                if (_current_user != null) {
                    b.set_member_name ("user");
                    b.begin_object ();
                    b.set_member_name ("id");
                    b.add_string_value (_current_user.id);
                    b.set_member_name ("email");
                    b.add_string_value (_current_user.email);
                    b.set_member_name ("displayName");
                    b.add_string_value (_current_user.display_name);
                    b.set_member_name ("avatarColor");
                    b.add_string_value (_current_user.avatar_color);
                    b.end_object ();
                }
                b.end_object ();

                var gen = new Json.Generator ();
                gen.set_root (b.get_root ());
                gen.pretty = true;
                GLib.FileUtils.set_contents (get_config_path (), gen.to_data (null));
            } catch (GLib.Error e) {
                GLib.debug ("WebSyncClient: failed to save config metadata: %s", e.message);
            }
        }

        private void load_config_metadata () {
            string path = get_config_path ();
            if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) return;
            try {
                string raw;
                GLib.FileUtils.get_contents (path, out raw);
                var parser = new Json.Parser ();
                parser.load_from_data (raw, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return;
                var obj = root.get_object ();
                if (obj.has_member ("instanceUrl")) {
                    string u = obj.get_string_member ("instanceUrl").strip ();
                    if (u.length > 0) _instance_url = u;
                }
                if (obj.has_member ("user") && !obj.get_null_member ("user")) {
                    var uo = obj.get_object_member ("user");
                    _current_user = new WebUser (
                        uo.has_member ("id") ? uo.get_string_member ("id") : "",
                        uo.has_member ("email") ? uo.get_string_member ("email") : "",
                        uo.has_member ("displayName") ? uo.get_string_member ("displayName") : "",
                        uo.has_member ("avatarColor") ? uo.get_string_member ("avatarColor") : "#3584e4"
                    );
                }
            } catch (GLib.Error e) {
                GLib.debug ("WebSyncClient: failed to load config metadata: %s", e.message);
            }
        }

        private void persist_session_token (string token) {
            _session_cookie = token;
            if (GLib.Environment.get_variable ("DBUS_SESSION_BUS_ADDRESS") != null) {
                Secret.password_store.begin (
                    get_secret_schema (),
                    Secret.COLLECTION_DEFAULT,
                    @"Imladris on Web Session ($(_instance_url))",
                    token,
                    null,
                    (obj, res) => {
                        try {
                            Secret.password_store.end (res);
                        } catch (GLib.Error e) {
                            write_fallback_token (token);
                        }
                    },
                    "instance_url", _instance_url
                );
            } else {
                write_fallback_token (token);
            }
        }

        private void write_fallback_token (string token) {
            try {
                string fpath = get_fallback_token_path ();
                GLib.FileUtils.set_contents (fpath, token);
                GLib.FileUtils.chmod (fpath, 0600);
            } catch (GLib.Error e) {
                GLib.debug ("WebSyncClient: failed to save fallback session token: %s", e.message);
            }
        }

        private void clear_persisted_token () {
            _session_cookie = "";
            string fpath = get_fallback_token_path ();
            if (GLib.FileUtils.test (fpath, GLib.FileTest.EXISTS)) {
                GLib.FileUtils.unlink (fpath);
            }
            if (GLib.Environment.get_variable ("DBUS_SESSION_BUS_ADDRESS") != null) {
                Secret.password_clear.begin (
                    get_secret_schema (),
                    null,
                    (obj, res) => {
                        try { Secret.password_clear.end (res); } catch (GLib.Error e) {}
                    },
                    "instance_url", _instance_url
                );
            }
        }

        private void load_saved_session_token () {
            string fpath = get_fallback_token_path ();
            if (GLib.FileUtils.test (fpath, GLib.FileTest.EXISTS)) {
                try {
                    string tok;
                    GLib.FileUtils.get_contents (fpath, out tok);
                    if (tok.strip ().length > 0) {
                        _session_cookie = tok.strip ();
                    }
                } catch (GLib.Error e) {}
            }
            if (_session_cookie.length == 0 && GLib.Environment.get_variable ("DBUS_SESSION_BUS_ADDRESS") != null) {
                Secret.password_lookup.begin (
                    get_secret_schema (),
                    null,
                    (obj, res) => {
                        try {
                            string? tok = Secret.password_lookup.end (res);
                            if (tok != null && tok.strip ().length > 0) {
                                _session_cookie = tok.strip ();
                                if (_current_user != null) {
                                    auth_state_changed (true, _current_user);
                                }
                            }
                        } catch (GLib.Error e) {}
                    },
                    "instance_url", _instance_url
                );
            }
        }

        private void guard_governance () throws WebSyncError {
            if (Core.SettingsManager.get_default ().airgapped_mode) {
                throw new WebSyncError.AIRGAPPED_BLOCKED (
                    "Air-Gapped Mode is enabled. Network sync to Imladris on Web is disabled by policy."
                );
            }
        }

        private void extract_session_cookie (Soup.Message msg) {
            msg.response_headers.foreach ((name, val) => {
                if (name.down () == "set-cookie" && val.contains ("imladris_session=")) {
                    int start = val.index_of ("imladris_session=") + "imladris_session=".length;
                    string rest = val.substring (start);
                    int semi = rest.index_of (";");
                    string tok = (semi >= 0) ? rest.substring (0, semi).strip () : rest.strip ();
                    if (tok.length > 0) {
                        persist_session_token (tok);
                    }
                }
            });
        }

        private async string send_json_request_async (
            string method,
            string endpoint,
            string? json_body = null,
            GLib.Cancellable? cancellable = null
        ) throws GLib.Error {
            guard_governance ();

            string full_url = endpoint.has_prefix ("http")
                ? endpoint
                : @"$(_instance_url)$(endpoint)";

            var msg = new Soup.Message (method, full_url);
            msg.request_headers.append ("Accept", "application/json");
            if (_session_cookie.length > 0) {
                msg.request_headers.replace ("Cookie", @"imladris_session=$(_session_cookie)");
            }
            if (json_body != null) {
                msg.set_request_body_from_bytes ("application/json", new GLib.Bytes (json_body.data));
            }

            GLib.Bytes resp_bytes;
            try {
                resp_bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
            } catch (GLib.Error e) {
                is_online = false;
                throw new WebSyncError.OFFLINE (@"Cannot reach $(_instance_url): $(e.message)");
            }

            extract_session_cookie (msg);
            is_online = true;

            uint status = msg.status_code;
            string body_text = Core.PlatformUtils.bytes_to_string (resp_bytes);

            if (status == 401) {
                throw new WebSyncError.UNAUTHORIZED (extract_error_msg (body_text, "Authentication required"));
            }
            if (status == 403) {
                throw new WebSyncError.FORBIDDEN (extract_error_msg (body_text, "Insufficient workspace permissions"));
            }
            if (status == 404) {
                throw new WebSyncError.NOT_FOUND (extract_error_msg (body_text, "Resource not found"));
            }
            if (status >= 500) {
                throw new WebSyncError.SERVER_ERROR (extract_error_msg (body_text, @"Server error (HTTP $status)"));
            }
            if (status < 200 || status >= 300) {
                throw new WebSyncError.NETWORK_ERROR (extract_error_msg (body_text, @"Request failed (HTTP $status)"));
            }

            return body_text;
        }

        private static string extract_error_msg (string body_text, string fallback) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (body_text, -1);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("error")) {
                        return obj.get_string_member ("error");
                    }
                }
            } catch (GLib.Error e) {}
            return fallback;
        }

        public async bool probe_health_async (string? target_url = null, GLib.Cancellable? cancellable = null) {
            if (Core.SettingsManager.get_default ().airgapped_mode) {
                is_online = false;
                return false;
            }
            string base_u = (target_url != null && target_url.strip ().length > 0)
                ? target_url.strip ()
                : _instance_url;
            while (base_u.has_suffix ("/")) {
                base_u = base_u.substring (0, base_u.length - 1);
            }
            try {
                string raw = yield send_json_request_async ("GET", @"$base_u/health", null, cancellable);
                var parser = new Json.Parser ();
                parser.load_from_data (raw, -1);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    bool ok = obj.has_member ("ok") && obj.get_boolean_member ("ok");
                    is_online = ok;
                    return ok;
                }
            } catch (GLib.Error e) {
                is_online = false;
            }
            return false;
        }

        public async WebUser login_async (string target_url, string email, string password) throws GLib.Error {
            this.instance_url = target_url;

            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("email");
            b.add_string_value (email.strip ());
            b.set_member_name ("password");
            b.add_string_value (password);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            string raw = yield send_json_request_async ("POST", "/api/auth/login", gen.to_data (null));

            var user = parse_user_response (raw);
            _current_user = user;
            save_config_metadata ();
            auth_state_changed (true, user);
            return user;
        }

        public async WebUser register_async (
            string target_url,
            string email,
            string display_name,
            string password,
            string? invite_token = null
        ) throws GLib.Error {
            this.instance_url = target_url;

            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("email");
            b.add_string_value (email.strip ());
            b.set_member_name ("displayName");
            b.add_string_value (display_name.strip ());
            b.set_member_name ("password");
            b.add_string_value (password);
            if (invite_token != null && invite_token.strip ().length > 0) {
                b.set_member_name ("inviteToken");
                b.add_string_value (invite_token.strip ());
            }
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            string raw = yield send_json_request_async ("POST", "/api/auth/register", gen.to_data (null));

            var user = parse_user_response (raw);
            _current_user = user;
            save_config_metadata ();
            auth_state_changed (true, user);
            return user;
        }

        public async WebUser? verify_session_async () throws GLib.Error {
            string raw = yield send_json_request_async ("GET", "/api/auth/me");
            var user = parse_user_response (raw);
            _current_user = user;
            save_config_metadata ();
            auth_state_changed (true, user);
            return user;
        }

        public async void logout_async () {
            try {
                if (!Core.SettingsManager.get_default ().airgapped_mode) {
                    yield send_json_request_async ("POST", "/api/auth/logout", "{}");
                }
            } catch (GLib.Error e) {}
            _current_user = null;
            clear_persisted_token ();
            save_config_metadata ();
            auth_state_changed (false, null);
        }

        public async Gee.ArrayList<WebWorkspace> list_workspaces_async () throws GLib.Error {
            string raw = yield send_json_request_async ("GET", "/api/workspaces");
            var list = new Gee.ArrayList<WebWorkspace> ();

            var parser = new Json.Parser ();
            parser.load_from_data (raw, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return list;
            var obj = root.get_object ();
            if (!obj.has_member ("workspaces")) return list;
            var arr = obj.get_array_member ("workspaces");
            for (uint i = 0; i < arr.get_length (); i++) {
                var w = arr.get_object_element (i);
                list.add (new WebWorkspace (
                    w.has_member ("id") ? w.get_string_member ("id") : "",
                    w.has_member ("slug") ? w.get_string_member ("slug") : "",
                    w.has_member ("name") ? w.get_string_member ("name") : "Workspace",
                    w.has_member ("role") ? w.get_string_member ("role") : "EDITOR",
                    w.has_member ("kernelMode") ? w.get_string_member ("kernelMode") : "SHARED"
                ));
            }
            return list;
        }

        public async WebWorkspace create_workspace_async (string name, string kernel_mode = "SHARED") throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("name");
            b.add_string_value (name.strip ());
            b.set_member_name ("kernelMode");
            b.add_string_value (kernel_mode);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            string raw = yield send_json_request_async ("POST", "/api/workspaces", gen.to_data (null));

            var parser = new Json.Parser ();
            parser.load_from_data (raw, -1);
            var obj = parser.get_root ().get_object ();
            var w = obj.get_object_member ("workspace");
            return new WebWorkspace (
                w.get_string_member ("id"),
                w.has_member ("slug") ? w.get_string_member ("slug") : "",
                w.get_string_member ("name"),
                w.has_member ("role") ? w.get_string_member ("role") : "OWNER",
                w.has_member ("kernelMode") ? w.get_string_member ("kernelMode") : kernel_mode
            );
        }

        public async string create_invite_url_async (
            string workspace_id,
            string role = "EDITOR",
            int max_uses = 5,
            int expires_hours = 72
        ) throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("role");
            b.add_string_value (role);
            b.set_member_name ("maxUses");
            b.add_int_value (max_uses);
            b.set_member_name ("expiresInHours");
            b.add_int_value (expires_hours);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            string raw = yield send_json_request_async ("POST", @"/api/workspaces/$workspace_id/invites", gen.to_data (null));

            var parser = new Json.Parser ();
            parser.load_from_data (raw, -1);
            var inv = parser.get_root ().get_object ().get_object_member ("invite");
            string token = inv.get_string_member ("token");
            return @"$(_instance_url)/?invite=$token";
        }

        public async void push_file_async (string workspace_id, string rel_path, string content) throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("path");
            b.add_string_value (rel_path);
            b.set_member_name ("content");
            b.add_string_value (content);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            yield send_json_request_async ("POST", @"/api/workspaces/$workspace_id/files", gen.to_data (null));
        }

        public async string pull_file_async (string workspace_id, string rel_path) throws GLib.Error {
            string encoded = GLib.Uri.escape_string (rel_path, null, true);
            string raw = yield send_json_request_async ("GET", @"/api/workspaces/$workspace_id/files/content?path=$encoded");
            var parser = new Json.Parser ();
            parser.load_from_data (raw, -1);
            var obj = parser.get_root ().get_object ();
            return obj.has_member ("content") ? obj.get_string_member ("content") : "";
        }

        public async WebRevision create_revision_async (string workspace_id, string rel_path, string message) throws GLib.Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("path");
            b.add_string_value (rel_path);
            b.set_member_name ("message");
            b.add_string_value (message.strip ());
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            string raw = yield send_json_request_async ("POST", @"/api/workspaces/$workspace_id/revisions", gen.to_data (null));

            var parser = new Json.Parser ();
            parser.load_from_data (raw, -1);
            var rev = parser.get_root ().get_object ().get_object_member ("revision");
            return new WebRevision (
                rev.get_string_member ("id"),
                rev.has_member ("relPath") ? rev.get_string_member ("relPath") : rel_path,
                rev.has_member ("sha256Hash") ? rev.get_string_member ("sha256Hash") : "",
                rev.has_member ("message") && !rev.get_null_member ("message") ? rev.get_string_member ("message") : message,
                rev.has_member ("isCheckpoint") ? rev.get_boolean_member ("isCheckpoint") : true,
                rev.has_member ("updatedByName") && !rev.get_null_member ("updatedByName") ? rev.get_string_member ("updatedByName") : "",
                rev.has_member ("updatedAt") ? rev.get_int_member ("updatedAt") : (GLib.get_real_time () / 1000)
            );
        }

        public async Gee.ArrayList<WebRevision> list_snapshots_async (string workspace_id, string rel_path) throws GLib.Error {
            string encoded = GLib.Uri.escape_string (rel_path, null, true);
            string raw = yield send_json_request_async ("GET", @"/api/workspaces/$workspace_id/snapshots?path=$encoded");
            var list = new Gee.ArrayList<WebRevision> ();

            var parser = new Json.Parser ();
            parser.load_from_data (raw, -1);
            var obj = parser.get_root ().get_object ();
            if (!obj.has_member ("snapshots")) return list;
            var arr = obj.get_array_member ("snapshots");
            for (uint i = 0; i < arr.get_length (); i++) {
                var s = arr.get_object_element (i);
                list.add (new WebRevision (
                    s.has_member ("id") ? s.get_string_member ("id") : "",
                    s.has_member ("relPath") ? s.get_string_member ("relPath") : rel_path,
                    s.has_member ("sha256Hash") ? s.get_string_member ("sha256Hash") : "",
                    (s.has_member ("message") && !s.get_null_member ("message")) ? s.get_string_member ("message") : "(Auto snapshot)",
                    s.has_member ("isCheckpoint") ? s.get_boolean_member ("isCheckpoint") : false,
                    (s.has_member ("updatedByName") && !s.get_null_member ("updatedByName")) ? s.get_string_member ("updatedByName") : "Collaborator",
                    s.has_member ("updatedAt") ? s.get_int_member ("updatedAt") : 0
                ));
            }
            return list;
        }

        private WebUser parse_user_response (string raw) throws WebSyncError {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (raw, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    throw new WebSyncError.INVALID_DATA ("Invalid JSON from Imladris on Web");
                }
                var obj = root.get_object ();
                if (!obj.has_member ("user")) {
                    throw new WebSyncError.INVALID_DATA ("Missing user object in auth response");
                }
                var u = obj.get_object_member ("user");
                return new WebUser (
                    u.has_member ("id") ? u.get_string_member ("id") : "",
                    u.has_member ("email") ? u.get_string_member ("email") : "",
                    u.has_member ("displayName") ? u.get_string_member ("displayName") : "",
                    u.has_member ("avatarColor") ? u.get_string_member ("avatarColor") : "#3584e4"
                );
            } catch (WebSyncError we) {
                throw we;
            } catch (GLib.Error e) {
                throw new WebSyncError.INVALID_DATA (@"Failed to parse auth response: $(e.message)");
            }
        }
    }
}
