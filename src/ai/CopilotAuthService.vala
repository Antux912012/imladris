// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Soup;
using Json;
using Secret;

namespace Imladris.AI {

    public class CopilotDeviceCodeInfo : GLib.Object {
        public string device_code { get; set; default = ""; }
        public string user_code { get; set; default = ""; }
        public string verification_uri { get; set; default = "https://github.com/login/device"; }
        public int expires_in { get; set; default = 900; }
        public int interval { get; set; default = 5; }
    }

    public class CopilotAuthService : GLib.Object {

        public const string COPILOT_CLIENT_ID = "Iv1.b507a08c87ecfe98";
        public const string EDITOR_VERSION = "vscode/1.85.1";
        public const string EDITOR_PLUGIN_VERSION = "copilot-chat/0.12.0";

        private static CopilotAuthService? _instance = null;

        public static CopilotAuthService get_default () {
            if (_instance == null) {
                _instance = new CopilotAuthService ();
            }
            return _instance;
        }

        private Soup.Session session;
        private string? cached_oauth_token = null;
        private string? cached_session_token = null;
        private int64 session_expires_at = 0;
        private string cached_username = "";

        public signal void auth_state_changed (bool signed_in, string username);

        private static Secret.Schema get_secret_schema () {
            return new Secret.Schema (
                "io.github.Antux912012.Imladris.Copilot",
                Secret.SchemaFlags.NONE,
                "account", Secret.SchemaAttributeType.STRING
            );
        }

        private CopilotAuthService () {
            session = new Soup.Session () {
                timeout = 30
            };
        }

        public bool is_signed_in () {
            return get_oauth_token () != "";
        }

        public string get_username () {
            return cached_username;
        }

        public async void load_stored_token_async () {
            try {
                string? tok = yield Secret.password_lookup (
                    get_secret_schema (),
                    null,
                    "account", "github_copilot_oauth"
                );
                if (tok != null && tok.strip ().length > 0) {
                    cached_oauth_token = tok.strip ();
                    yield refresh_username_async ();
                    auth_state_changed (true, cached_username);
                    return;
                }
            } catch (GLib.Error e) {
                GLib.debug ("Secret service unavailable for Copilot token lookup: %s", e.message);
            }

            // Fallback: check user-private 0600 token file if Secret Service is absent
            string fallback = get_fallback_token_path ();
            if (GLib.FileUtils.test (fallback, GLib.FileTest.EXISTS)) {
                try {
                    string content;
                    GLib.FileUtils.get_contents (fallback, out content);
                    if (content.strip ().length > 0) {
                        cached_oauth_token = content.strip ();
                        yield refresh_username_async ();
                        auth_state_changed (true, cached_username);
                    }
                } catch (GLib.Error e) {}
            }
        }

        public string get_oauth_token () {
            if (cached_oauth_token != null && cached_oauth_token.length > 0) {
                return cached_oauth_token;
            }
            string? env_tok = GLib.Environment.get_variable ("GITHUB_COPILOT_TOKEN");
            if (env_tok != null && env_tok.strip ().length > 0) {
                return env_tok.strip ();
            }
            return "";
        }

        public async void store_oauth_token_async (string token) {
            cached_oauth_token = token.strip ();
            cached_session_token = null;
            session_expires_at = 0;

            bool stored_in_keyring = false;
            try {
                stored_in_keyring = yield Secret.password_store (
                    get_secret_schema (),
                    Secret.COLLECTION_DEFAULT,
                    "Imladris GitHub Copilot Token",
                    cached_oauth_token,
                    null,
                    "account", "github_copilot_oauth"
                );
            } catch (GLib.Error e) {
                GLib.debug ("Secret service unavailable for Copilot store: %s", e.message);
            }

            if (!stored_in_keyring) {
                try {
                    string path = get_fallback_token_path ();
                    GLib.FileUtils.set_contents (path, cached_oauth_token);
                    GLib.FileUtils.chmod (path, 0600);
                } catch (GLib.Error e) {}
            }

            yield refresh_username_async ();
            auth_state_changed (true, cached_username);
        }

        public async void sign_out_async () {
            cached_oauth_token = null;
            cached_session_token = null;
            session_expires_at = 0;
            cached_username = "";

            try {
                yield Secret.password_clear (
                    get_secret_schema (),
                    null,
                    "account", "github_copilot_oauth"
                );
            } catch (GLib.Error e) {}

            string fallback = get_fallback_token_path ();
            if (GLib.FileUtils.test (fallback, GLib.FileTest.EXISTS)) {
                GLib.FileUtils.remove (fallback);
            }

            auth_state_changed (false, "");
        }

        private string get_fallback_token_path () {
            string dir = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "imladris");
            GLib.DirUtils.create_with_parents (dir, 0700);
            return GLib.Path.build_filename (dir, ".copilot_token");
        }

        public async CopilotDeviceCodeInfo request_device_code_async (Cancellable? cancellable = null) throws GLib.Error {
            var msg = new Soup.Message ("POST", "https://github.com/login/device/code");
            msg.request_headers.append ("Accept", "application/json");
            string body = @"client_id=$COPILOT_CLIENT_ID&scope=read%3Auser";
            msg.set_request_body_from_bytes ("application/x-www-form-urlencoded", new GLib.Bytes (body.data));

            var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
            if (msg.status_code != 200 || bytes == null) {
                throw new GLib.IOError.FAILED (@"GitHub Device Flow initiation failed (HTTP $(msg.status_code)).");
            }
            string resp = Core.AiConfigManager.bytes_to_string (bytes);
            var info = parse_device_code_json (resp);
            if (info == null) {
                throw new GLib.IOError.INVALID_DATA ("Invalid device code response from GitHub.");
            }
            return info;
        }

        public static CopilotDeviceCodeInfo? parse_device_code_json (string json_str) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_str, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;
                var obj = root.get_object ();
                if (!obj.has_member ("device_code") || !obj.has_member ("user_code")) return null;

                var info = new CopilotDeviceCodeInfo ();
                info.device_code = obj.get_string_member ("device_code");
                info.user_code = obj.get_string_member ("user_code");
                if (obj.has_member ("verification_uri")) {
                    info.verification_uri = obj.get_string_member ("verification_uri");
                }
                if (obj.has_member ("expires_in")) {
                    info.expires_in = (int) obj.get_int_member ("expires_in");
                }
                if (obj.has_member ("interval")) {
                    info.interval = (int) obj.get_int_member ("interval");
                }
                return info;
            } catch (GLib.Error e) {
                return null;
            }
        }

        public async string poll_device_token_async (CopilotDeviceCodeInfo info, Cancellable? cancellable = null) throws GLib.Error {
            int delay_sec = int.max (info.interval, 5);
            int64 deadline = GLib.get_real_time () / 1000000 + info.expires_in;

            while ((GLib.get_real_time () / 1000000) < deadline) {
                if (cancellable != null && cancellable.is_cancelled ()) {
                    throw new GLib.IOError.CANCELLED ("GitHub Copilot login cancelled.");
                }

                uint src_id = 0;
                ulong cancel_hid = 0;
                bool resumed = false;
                if (cancellable != null) {
                    cancel_hid = cancellable.cancelled.connect (() => {
                        if (src_id != 0) {
                            GLib.Source.remove (src_id);
                            src_id = 0;
                        }
                        if (!resumed) {
                            resumed = true;
                            poll_device_token_async.callback ();
                        }
                    });
                }
                src_id = Timeout.add_seconds (delay_sec, () => {
                    src_id = 0;
                    if (!resumed) {
                        resumed = true;
                        poll_device_token_async.callback ();
                    }
                    return false;
                });
                yield;
                if (cancel_hid != 0 && cancellable != null) {
                    cancellable.disconnect (cancel_hid);
                }
                if (cancellable != null && cancellable.is_cancelled ()) {
                    throw new GLib.IOError.CANCELLED ("GitHub Copilot login cancelled.");
                }

                var msg = new Soup.Message ("POST", "https://github.com/login/oauth/access_token");
                msg.request_headers.append ("Accept", "application/json");
                string body = @"client_id=$COPILOT_CLIENT_ID&device_code=$(info.device_code)&grant_type=urn:ietf:params:oauth:grant-type:device_code";
                msg.set_request_body_from_bytes ("application/x-www-form-urlencoded", new GLib.Bytes (body.data));

                var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
                if (bytes == null) continue;

                string resp = Core.AiConfigManager.bytes_to_string (bytes);
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data (resp, -1);
                } catch (GLib.Error e) {
                    continue;
                }
                var obj = parser.get_root () != null ? parser.get_root ().get_object () : null;
                if (obj == null) continue;

                if (obj.has_member ("access_token")) {
                    string tok = obj.get_string_member ("access_token");
                    yield store_oauth_token_async (tok);
                    return tok;
                }

                string err = obj.has_member ("error") ? obj.get_string_member ("error") : "";
                if (err == "slow_down") {
                    delay_sec += 5;
                } else if (err == "expired_token" || err == "access_denied") {
                    throw new GLib.IOError.PERMISSION_DENIED (@"GitHub Copilot login failed: $err");
                }
            }
            throw new GLib.IOError.TIMED_OUT ("GitHub Copilot device authorization timed out.");
        }

        public async string get_copilot_session_token_async (bool force_refresh = false, Cancellable? cancellable = null) throws GLib.Error {
            int64 now = GLib.get_real_time () / 1000000;
            if (!force_refresh && cached_session_token != null && now < (session_expires_at - 60)) {
                return cached_session_token;
            }

            string oauth = get_oauth_token ();
            if (oauth.length == 0) {
                throw new GLib.IOError.NOT_INITIALIZED ("GitHub Copilot is not signed in. Sign in from AI Settings.");
            }

            var msg = new Soup.Message ("GET", "https://api.github.com/copilot_internal/v2/token");
            msg.request_headers.append ("Authorization", @"token $oauth");
            msg.request_headers.append ("Accept", "application/json");
            msg.request_headers.append ("User-Agent", "Imladris/0.24.2");
            msg.request_headers.append ("Editor-Version", EDITOR_VERSION);
            msg.request_headers.append ("Editor-Plugin-Version", EDITOR_PLUGIN_VERSION);

            var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, cancellable);
            if (msg.status_code == 401 || msg.status_code == 403 || msg.status_code != 200 || bytes == null) {
                throw new GLib.IOError.PERMISSION_DENIED (@"GitHub Copilot token exchange failed (HTTP $(msg.status_code)). Ensure your GitHub account has an active Copilot subscription.");
            }

            string resp = Core.AiConfigManager.bytes_to_string (bytes);
            string? tok;
            int64 exp;
            if (!parse_copilot_token_json (resp, out tok, out exp) || tok == null) {
                throw new GLib.IOError.INVALID_DATA ("Invalid Copilot session token payload.");
            }

            cached_session_token = tok;
            session_expires_at = exp;
            return tok;
        }

        public static bool parse_copilot_token_json (string json_str, out string? token, out int64 expires_at) {
            token = null;
            expires_at = 0;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_str, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return false;
                var obj = root.get_object ();
                if (!obj.has_member ("token")) return false;
                token = obj.get_string_member ("token");
                expires_at = obj.has_member ("expires_at")
                    ? obj.get_int_member ("expires_at")
                    : ((GLib.get_real_time () / 1000000) + 1500);
                return token != null && token.length > 0;
            } catch (GLib.Error e) {
                return false;
            }
        }

        private async void refresh_username_async () {
            string oauth = get_oauth_token ();
            if (oauth.length == 0) return;
            try {
                var msg = new Soup.Message ("GET", "https://api.github.com/user");
                msg.request_headers.append ("Authorization", @"Bearer $oauth");
                msg.request_headers.append ("Accept", "application/vnd.github+json");
                msg.request_headers.append ("User-Agent", "Imladris/0.24.2");
                var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
                if (msg.status_code == 200 && bytes != null) {
                    var parser = new Json.Parser ();
                    parser.load_from_data (Core.AiConfigManager.bytes_to_string (bytes), -1);
                    var obj = parser.get_root () != null ? parser.get_root ().get_object () : null;
                    if (obj != null && obj.has_member ("login")) {
                        cached_username = obj.get_string_member ("login");
                    }
                }
            } catch (GLib.Error e) {}
        }
    }
}
