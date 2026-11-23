// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Single Responsibility: Manages Model Context Protocol (MCP) JSON-RPC requests,
 * D-Bus forwarding to an active GUI session, and headless file/build operations.
 *
 * Concurrency Constraints:
 * Reads standard input on a background thread. Dispatches in-process GTK/buffer
 * operations onto the GLib default MainContext; runs D-Bus proxy calls and
 * headless file operations without blocking the GUI main loop.
 */

using GLib;
using Json;
using Imladris.Core;
using Imladris.Runners;
using Imladris.Services;

namespace Imladris {

    [CCode (cname = "realpath", cheader_filename = "stdlib.h")]
    internal extern string? mcp_c_realpath (string path, char* resolved_path = null);

    public interface McpHost : GLib.Object {
        public abstract string get_open_tabs_json ();
        public abstract string get_active_document_json ();
        public abstract bool insert_text_in_active (string text);
        public abstract bool insert_code_chunk_in_active (string engine, string options);
        public abstract string trigger_render_from_mcp (string format);
        public abstract string execute_command_from_mcp (string[] parts);
    }

    [DBus (name = "io.github.Antux912012.Imladris.McpBridge")]
    public interface McpDbusProxy : GLib.Object {
        public abstract string get_open_tabs () throws GLib.DBusError, GLib.IOError;
        public abstract string get_active_document () throws GLib.DBusError, GLib.IOError;
        public abstract bool insert_text (string text) throws GLib.DBusError, GLib.IOError;
        public abstract bool insert_code_chunk (string engine, string options) throws GLib.DBusError, GLib.IOError;
        public abstract string render_document (string format) throws GLib.DBusError, GLib.IOError;
    }

    [DBus (name = "io.github.Antux912012.Imladris.McpBridge")]
    public class McpDbusBridge : GLib.Object {
        private unowned Gtk.Application app;

        public McpDbusBridge (Gtk.Application app) {
            this.app = app;
        }

        private McpHost? get_host () {
            return app.active_window as McpHost;
        }

        public string get_open_tabs () throws GLib.DBusError, GLib.IOError {
            var host = get_host ();
            if (host == null) {
                return "{\"error\":\"No active Imladris window.\"}";
            }
            return host.get_open_tabs_json ();
        }

        public string get_active_document () throws GLib.DBusError, GLib.IOError {
            var host = get_host ();
            if (host == null) {
                return "{\"error\":\"No active Imladris window.\"}";
            }
            return host.get_active_document_json ();
        }

        public bool insert_text (string text) throws GLib.DBusError, GLib.IOError {
            if (GLib.Environment.get_variable ("IMLADRIS_MCP_READONLY") == "1") {
                McpServer.append_audit_log ("dbus.insert_text", "", "Security Error: read-only");
                return false;
            }
            var host = get_host ();
            if (host == null) return false;
            bool ok = host.insert_text_in_active (text);
            McpServer.append_audit_log ("dbus.insert_text", "", ok ? "ok" : "error");
            return ok;
        }

        public bool insert_code_chunk (string engine, string options) throws GLib.DBusError, GLib.IOError {
            if (GLib.Environment.get_variable ("IMLADRIS_MCP_READONLY") == "1") {
                McpServer.append_audit_log ("dbus.insert_code_chunk", "", "Security Error: read-only");
                return false;
            }
            var host = get_host ();
            if (host == null) return false;
            bool ok = host.insert_code_chunk_in_active (engine, options);
            McpServer.append_audit_log ("dbus.insert_code_chunk", "", ok ? "ok" : "error");
            return ok;
        }

        public string render_document (string format) throws GLib.DBusError, GLib.IOError {
            if (GLib.Environment.get_variable ("IMLADRIS_MCP_READONLY") == "1") {
                McpServer.append_audit_log ("dbus.render_document", "", "Security Error: read-only");
                return "Security Error: Tool 'render_document' is blocked in read-only mode (IMLADRIS_MCP_READONLY=1).";
            }
            var host = get_host ();
            if (host == null) {
                return "Error: No active Imladris window.";
            }
            string res = host.trigger_render_from_mcp (format);
            McpServer.append_audit_log ("dbus.render_document", "", res);
            return res;
        }
    }

    private class SyncCallState {
        public GLib.Mutex mutex = GLib.Mutex ();
        public GLib.Cond cond = GLib.Cond ();
        public bool completed = false;
        public string result = "";
    }

    public class McpServer : GLib.Object {

        public const string MCP_VERSION = "0.42.1";
        public const string DBUS_BUS_NAME = "io.github.Antux912012.Imladris";
        public const string DBUS_OBJECT_PATH = "/io/github/Antux912012/Imladris/McpBridge";

        public static string handle_json_rpc (string request_json, McpHost? host) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (request_json, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid JSON-RPC request\"}}";
                }
                var req = root.get_object ();

                int64 id = 1;
                string? id_str = null;
                if (req.has_member ("id")) {
                    var id_node = req.get_member ("id");
                    if (id_node.get_node_type () == Json.NodeType.VALUE) {
                        if (id_node.get_value_type () == typeof (string)) {
                            id_str = id_node.get_string ();
                        } else {
                            id = id_node.get_int ();
                        }
                    }
                }
                string method = (req.has_member ("method") && req.get_member ("method").get_node_type () == Json.NodeType.VALUE)
                    ? req.get_string_member ("method") : "";

                var builder = new Json.Builder ();
                builder.begin_object ();
                builder.set_member_name ("jsonrpc");
                builder.add_string_value ("2.0");
                builder.set_member_name ("id");
                if (id_str != null) {
                    builder.add_string_value (id_str);
                } else {
                    builder.add_int_value (id);
                }

                if (method == "initialize") {
                    builder.set_member_name ("result");
                    builder.begin_object ();
                    builder.set_member_name ("protocolVersion");
                    builder.add_string_value ("2024-11-05");

                    builder.set_member_name ("capabilities");
                    builder.begin_object ();
                    builder.set_member_name ("tools");
                    builder.begin_object ();
                    builder.end_object ();
                    builder.end_object ();

                    builder.set_member_name ("serverInfo");
                    builder.begin_object ();
                    builder.set_member_name ("name");
                    builder.add_string_value ("imladris-mcp");
                    builder.set_member_name ("version");
                    builder.add_string_value (MCP_VERSION);
                    builder.end_object ();

                    builder.end_object ();
                } else if (method == "tools/list") {
                    builder.set_member_name ("result");
                    builder.begin_object ();
                    builder.set_member_name ("tools");
                    builder.begin_array ();

                    add_tool_definition (builder, "get_active_document",
                        "Retrieve the text content, language, line count and stats of the active tab or a workspace file",
                        "file_path", "Optional path to read headlessly when no GUI tab is targeted");
                    add_tool_definition (builder, "insert_text",
                        "Insert text at cursor in the active document or append/prepend to a workspace file",
                        "text", "The string content to insert",
                        "file_path", "Optional path to edit headlessly",
                        "position", "Optional headless position: 'end' (default) or 'start'");
                    add_tool_definition (builder, "insert_code_chunk",
                        "Insert a computational chunk {r}, {python}, or {ts}",
                        "engine", "r, python, or ts",
                        "options", "Chunk options like 'echo: true'");
                    add_tool_definition (builder, "execute_code",
                        "Asynchronously execute CLI command or script via the execution engine",
                        "command", "CLI command (e.g. 'python3 -c ...' or 'Rscript -e ...')");
                    add_tool_definition (builder, "render_document",
                        "Trigger Quarto/Export render pipeline for HTML or PDF",
                        "format", "Target format: 'html' or 'pdf'",
                        "file_path", "Optional path to render headlessly");
                    add_tool_definition (builder, "compile_latex",
                        "Compile a LaTeX (.tex) file using Imladris's managed Tectonic or system TeX engine",
                        "file_path", "Path to the .tex file to compile",
                        "engine", "Optional TeX engine (defaults to 'tectonic')");
                    add_tool_definition (builder, "get_open_tabs",
                        "List all open document tabs in the active Imladris GUI window");
                    add_tool_definition (builder, "get_environment_summary",
                        "Inspect active managed Python/R environments and offline runtime readiness");

                    builder.end_array ();
                    builder.end_object ();
                } else if (method == "tools/call") {
                    if (!req.has_member ("params") || req.get_member ("params").get_node_type () != Json.NodeType.OBJECT) {
                        builder.set_member_name ("error");
                        builder.begin_object ();
                        builder.set_member_name ("code");
                        builder.add_int_value (-32602);
                        builder.set_member_name ("message");
                        builder.add_string_value ("Missing or invalid params object.");
                        builder.end_object ();
                    } else {
                        var params_obj = req.get_object_member ("params");
                        string tool_name = (params_obj.has_member ("name") && params_obj.get_member ("name").get_node_type () == Json.NodeType.VALUE)
                            ? params_obj.get_string_member ("name") : "";
                        Json.Object? args = (params_obj.has_member ("arguments") && params_obj.get_member ("arguments").get_node_type () == Json.NodeType.OBJECT)
                            ? params_obj.get_object_member ("arguments") : null;

                        string tool_result = dispatch_tool (tool_name, args, host);

                        builder.set_member_name ("result");
                        builder.begin_object ();
                        builder.set_member_name ("content");
                        builder.begin_array ();
                        builder.begin_object ();
                        builder.set_member_name ("type");
                        builder.add_string_value ("text");
                        builder.set_member_name ("text");
                        builder.add_string_value (tool_result);
                        builder.end_object ();
                        builder.end_array ();
                        builder.end_object ();
                    }
                } else {
                    builder.set_member_name ("error");
                    builder.begin_object ();
                    builder.set_member_name ("code");
                    builder.add_int_value (-32601);
                    builder.set_member_name ("message");
                    builder.add_string_value (@"Method '$method' not found.");
                    builder.end_object ();
                }

                builder.end_object ();
                var generator = new Json.Generator ();
                generator.set_root (builder.get_root ());
                return generator.to_data (null);
            } catch (GLib.Error e) {
                var err_builder = new Json.Builder ();
                err_builder.begin_object ();
                err_builder.set_member_name ("jsonrpc");
                err_builder.add_string_value ("2.0");
                err_builder.set_member_name ("id");
                err_builder.add_null_value ();
                err_builder.set_member_name ("error");
                err_builder.begin_object ();
                err_builder.set_member_name ("code");
                err_builder.add_int_value (-32700);
                err_builder.set_member_name ("message");
                err_builder.add_string_value (e.message);
                err_builder.end_object ();
                err_builder.end_object ();

                var generator = new Json.Generator ();
                generator.set_root (err_builder.get_root ());
                return generator.to_data (null);
            }
        }

        private static void add_tool_definition (
            Json.Builder b,
            string name,
            string desc,
            string? param1 = null,
            string? p1_desc = null,
            string? param2 = null,
            string? p2_desc = null,
            string? param3 = null,
            string? p3_desc = null
        ) {
            b.begin_object ();
            b.set_member_name ("name");
            b.add_string_value (name);
            b.set_member_name ("description");
            b.add_string_value (desc);
            b.set_member_name ("inputSchema");
            b.begin_object ();
            b.set_member_name ("type");
            b.add_string_value ("object");
            b.set_member_name ("properties");
            b.begin_object ();

            string?[] p_names = { param1, param2, param3 };
            string?[] p_descs = { p1_desc, p2_desc, p3_desc };
            for (int i = 0; i < 3; i++) {
                if (p_names[i] != null) {
                    b.set_member_name (p_names[i]);
                    b.begin_object ();
                    b.set_member_name ("type");
                    b.add_string_value ("string");
                    if (p_descs[i] != null) {
                        b.set_member_name ("description");
                        b.add_string_value (p_descs[i]);
                    }
                    b.end_object ();
                }
            }

            b.end_object ();
            b.end_object ();
            b.end_object ();
        }

        private static string dispatch_tool (string name, Json.Object? args, McpHost? host) {
            string file_path = get_opt_string (args, "file_path", "");
            bool is_headless_tool = (file_path != "") &&
                (name == "get_active_document" || name == "insert_text" || name == "render_document");
            bool needs_gui_thread = (host != null) && !is_headless_tool &&
                (name != "compile_latex") && (name != "get_environment_summary");
            string result;
            if (needs_gui_thread) {
                var main_context = GLib.MainContext.default ();
                if (main_context.is_owner ()) {
                    result = execute_tool (name, args, host);
                } else {
                    var state = new SyncCallState ();
                    state.mutex.lock ();
                    main_context.invoke (() => {
                        string r = execute_tool (name, args, host);
                        state.mutex.lock ();
                        state.result = r;
                        state.completed = true;
                        state.cond.signal ();
                        state.mutex.unlock ();
                        return GLib.Source.REMOVE;
                    });
                    int64 deadline = GLib.get_monotonic_time () + 30 * 1000 * 1000;
                    while (!state.completed) {
                        if (!state.cond.wait_until (state.mutex, deadline)) {
                            state.result = "Error: Main thread dispatch timed out.";
                            break;
                        }
                    }
                    result = state.result;
                    state.mutex.unlock ();
                }
            } else {
                result = execute_tool (name, args, host);
            }

            append_audit_log (name, file_path, result);
            return result;
        }

        internal static void append_audit_log (string tool_name, string file_path, string result) {
            bool audit_on = GLib.Environment.get_variable ("IMLADRIS_MCP_AUDIT") == "1" ||
                            GLib.Environment.get_variable ("IMLADRIS_MCP_READONLY") == "1";
            if (!audit_on) {
                return;
            }
            try {
                string log_dir = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "imladris");
                GLib.DirUtils.create_with_parents (log_dir, 0700);
                string log_path = GLib.Path.build_filename (log_dir, "mcp-audit.jsonl");

                // Never log raw file contents or sensitive payloads; log metadata only
                string status = (result.has_prefix ("Error:") || result.has_prefix ("Security Error:")) ? "error" : "ok";
                string ts = new GLib.DateTime.now_utc ().format_iso8601 ();
                var b = new Json.Builder ();
                b.begin_object ();
                b.set_member_name ("timestamp");
                b.add_string_value (ts);
                b.set_member_name ("tool");
                b.add_string_value (tool_name);
                if (file_path != "") {
                    b.set_member_name ("file_path");
                    b.add_string_value (file_path);
                }
                b.set_member_name ("status");
                b.add_string_value (status);
                b.end_object ();

                var gen = new Json.Generator ();
                gen.set_root (b.get_root ());
                string line = gen.to_data (null) + "\n";

                var file = GLib.File.new_for_path (log_path);
                var stream = file.append_to (GLib.FileCreateFlags.PRIVATE);
                stream.write_all (line.data, null);
                stream.close ();
            } catch (GLib.Error e) {
                GLib.debug ("MCP audit log write skipped: %s", e.message);
            }
        }

        private static string get_opt_string (Json.Object? obj, string key, string fallback = "") {
            if (obj == null || !obj.has_member (key)) {
                return fallback;
            }
            var node = obj.get_member (key);
            if (node != null && node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == typeof (string)) {
                return node.get_string () ?? fallback;
            }
            return fallback;
        }

        private static McpDbusProxy? try_connect_dbus_bridge () {
            try {
                return GLib.Bus.get_proxy_sync<McpDbusProxy> (
                    GLib.BusType.SESSION,
                    DBUS_BUS_NAME,
                    DBUS_OBJECT_PATH,
                    GLib.DBusProxyFlags.DO_NOT_AUTO_START
                );
            } catch (GLib.Error e) {
                return null;
            }
        }

        /**
         * Canonicalizes a headless file_path using realpath(), validates against
         * symlink escapes, workspace boundaries, and sensitive dot-directories.
         */
        public static string? validate_headless_path (string raw_path, bool must_exist, out string? error_msg) {
            error_msg = null;
            string trimmed = raw_path.strip ();
            if (trimmed.length == 0) {
                error_msg = "Error: Empty file_path.";
                return null;
            }

            string abs_candidate = GLib.Path.is_absolute (trimmed)
                ? trimmed
                : GLib.Path.build_filename (GLib.Environment.get_current_dir (), trimmed);

            string? resolved = null;
            if (GLib.FileUtils.test (abs_candidate, GLib.FileTest.EXISTS)) {
                resolved = mcp_c_realpath (abs_candidate);
                if (resolved == null) {
                    error_msg = @"Security Error: Cannot resolve canonical path for '$raw_path'.";
                    return null;
                }
            } else {
                if (must_exist) {
                    error_msg = @"Error: File not found: $raw_path";
                    return null;
                }
                if (GLib.FileUtils.test (abs_candidate, GLib.FileTest.IS_SYMLINK)) {
                    error_msg = @"Security Error: Refusing dangling symlink target '$raw_path'.";
                    return null;
                }
                string parent = GLib.Path.get_dirname (abs_candidate);
                string? real_parent = mcp_c_realpath (parent);
                if (real_parent == null) {
                    error_msg = @"Error: Parent directory does not exist for '$raw_path'.";
                    return null;
                }
                resolved = GLib.Path.build_filename (real_parent, GLib.Path.get_basename (abs_candidate));
            }

            string? env_ws = GLib.Environment.get_variable ("IMLADRIS_MCP_WORKSPACE");
            if (env_ws == null || env_ws.strip () == "") {
                error_msg = "Security Error: IMLADRIS_MCP_WORKSPACE must be set for headless file access (refusing default $HOME root).";
                return null;
            }
            string raw_root = env_ws.strip ();
            string? root = mcp_c_realpath (raw_root) ?? raw_root;

            bool inside = (resolved == root) ||
                          (root == "/" ? resolved.has_prefix ("/") : resolved.has_prefix (root + "/"));
            if (!inside) {
                error_msg = @"Security Error: Path '$resolved' is outside permitted workspace root '$root'.";
                return null;
            }

            string[] blocked_segments = {
                "/.ssh/", "/.gnupg/", "/.aws/", "/.config/",
                "/.local/share/keyrings/", "/.local/share/imladris/", "/.local/bin/",
                "/.docker/", "/.kube/", "/.pki/"
            };
            foreach (string seg in blocked_segments) {
                if (resolved.contains (seg) || resolved.has_suffix (seg.substring (0, seg.length - 1))) {
                    error_msg = @"Security Error: Access to sensitive directory '$seg' is blocked.";
                    return null;
                }
            }

            string[] blocked_files = {
                "/.git-credentials", "/.gitconfig", "/.netrc", "/.npmrc", "/.pypirc",
                "/.env", "/.bashrc", "/.bash_profile", "/.bash_login", "/.profile",
                "/.zshrc", "/.zprofile", "/.zshenv"
            };
            foreach (string bf in blocked_files) {
                if (resolved.has_suffix (bf)) {
                    error_msg = @"Security Error: Access to sensitive credential file '$bf' is blocked.";
                    return null;
                }
            }

            return resolved;
        }

        private static string execute_tool (string name, Json.Object? args, McpHost? host) {
            if (GLib.Environment.get_variable ("IMLADRIS_MCP_READONLY") == "1") {
                if (name == "insert_text" || name == "insert_code_chunk" ||
                    name == "execute_code" || name == "render_document" || name == "compile_latex") {
                    return @"Security Error: Tool '$name' is blocked in read-only mode (IMLADRIS_MCP_READONLY=1).";
                }
            }

            string file_path = get_opt_string (args, "file_path", "");

            if (name == "get_environment_summary") {
                var tm = ToolchainManager.get_default ();
                return @"Active Python Env: $(tm.active_python_env)\n\n$(tm.verify_offline_readiness ())";
            }

            if (name == "compile_latex") {
                if (file_path == "") {
                    return "Error: compile_latex requires a 'file_path' argument.";
                }
                string? path_err = null;
                string? safe_path = validate_headless_path (file_path, true, out path_err);
                if (safe_path == null) {
                    return path_err ?? "Security Error: Invalid file_path.";
                }
                string engine = get_opt_string (args, "engine", "tectonic");
                if (engine != "tectonic" && engine != "latexmk" && engine != "pdflatex" &&
                    engine != "xelatex" && engine != "lualatex") {
                    return @"Security Error: Unsupported LaTeX engine '$engine'.";
                }

                string summary = "";
                var thread_ctx = new GLib.MainContext ();
                thread_ctx.push_thread_default ();
                var loop = new GLib.MainLoop (thread_ctx, false);
                LatexBuildRunner.build_async.begin (safe_path, engine, null, (obj, res) => {
                    var build_res = LatexBuildRunner.build_async.end (res);
                    if (build_res.success) {
                        summary = @"✔ Compiled with $(build_res.engine_used): $(build_res.pdf_path.length > 0 ? build_res.pdf_path : safe_path)";
                    } else {
                        summary = @"✖ LaTeX build failed ($(build_res.engine_used)):\n$(build_res.stdout_stderr)";
                    }
                    loop.quit ();
                });
                loop.run ();
                thread_ctx.pop_thread_default ();
                return summary;
            }

            if (name == "get_active_document") {
                if (file_path != "") {
                    string? path_err = null;
                    string? safe_path = validate_headless_path (file_path, true, out path_err);
                    if (safe_path == null) return path_err ?? "Error: Invalid file_path.";
                    try {
                        string content;
                        GLib.FileUtils.get_contents (safe_path, out content);
                        int lines = content.split ("\n").length;
                        return @"File: $safe_path\nLines: $lines\n\nContent:\n$content";
                    } catch (GLib.Error e) {
                        return @"Error reading file: $(e.message)";
                    }
                }
                if (host != null) {
                    return host.get_active_document_json ();
                }
                var proxy = try_connect_dbus_bridge ();
                if (proxy != null) {
                    try {
                        return proxy.get_active_document ();
                    } catch (GLib.Error e) {
                        return @"Error: D-Bus bridge call failed: $(e.message)";
                    }
                }
                return "Error: No active Imladris window. Pass 'file_path' for headless document inspection.";
            }

            if (name == "get_open_tabs") {
                if (host != null) {
                    return host.get_open_tabs_json ();
                }
                var proxy = try_connect_dbus_bridge ();
                if (proxy != null) {
                    try {
                        return proxy.get_open_tabs ();
                    } catch (GLib.Error e) {
                        return @"Error: D-Bus bridge call failed: $(e.message)";
                    }
                }
                return "Error: No active Imladris window.";
            }

            if (name == "insert_text") {
                string txt = get_opt_string (args, "text", "");
                if (file_path != "") {
                    string? path_err = null;
                    string? safe_path = validate_headless_path (file_path, false, out path_err);
                    if (safe_path == null) return path_err ?? "Error: Invalid file_path.";
                    string pos = get_opt_string (args, "position", "end");
                    try {
                        string existing = "";
                        if (GLib.FileUtils.test (safe_path, GLib.FileTest.EXISTS)) {
                            GLib.FileUtils.get_contents (safe_path, out existing);
                        }
                        string updated = (pos == "start") ? (txt + existing) : (existing + txt);
                        GLib.FileUtils.set_contents (safe_path, updated);
                        return @"✔ Text inserted into $safe_path ($pos).";
                    } catch (GLib.Error e) {
                        return @"Error writing file: $(e.message)";
                    }
                }
                if (host != null) {
                    return host.insert_text_in_active (txt)
                        ? "✔ Text inserted successfully at cursor."
                        : "No active document open.";
                }
                var proxy = try_connect_dbus_bridge ();
                if (proxy != null) {
                    try {
                        return proxy.insert_text (txt)
                            ? "✔ Text inserted successfully at cursor."
                            : "No active document open.";
                    } catch (GLib.Error e) {
                        return @"Error: D-Bus bridge call failed: $(e.message)";
                    }
                }
                return "Error: No active Imladris window. Pass 'file_path' for headless editing.";
            }

            if (name == "insert_code_chunk") {
                string engine = get_opt_string (args, "engine", "python");
                string opt = get_opt_string (args, "options", "");
                if (host != null) {
                    return host.insert_code_chunk_in_active (engine, opt)
                        ? @"✔ Code chunk {$engine} inserted successfully."
                        : "No active document open.";
                }
                var proxy = try_connect_dbus_bridge ();
                if (proxy != null) {
                    try {
                        return proxy.insert_code_chunk (engine, opt)
                            ? @"✔ Code chunk {$engine} inserted successfully."
                            : "No active document open.";
                    } catch (GLib.Error e) {
                        return @"Error: D-Bus bridge call failed: $(e.message)";
                    }
                }
                return "Error: No active Imladris window.";
            }

            if (name == "render_document") {
                string fmt = get_opt_string (args, "format", "html");
                if (file_path != "") {
                    string? path_err = null;
                    string? safe_path = validate_headless_path (file_path, true, out path_err);
                    if (safe_path == null) return path_err ?? "Error: Invalid file_path.";
                    try {
                        string content;
                        GLib.FileUtils.get_contents (safe_path, out content);
                        string dot_ext = (fmt == "pdf") ? ".pdf" : ".html";
                        string out_path = safe_path + dot_ext;
                        int last_dot = safe_path.last_index_of (".");
                        int last_slash = safe_path.last_index_of ("/");
                        if (last_dot > last_slash) {
                            out_path = safe_path.substring (0, last_dot) + dot_ext;
                        }
                        string? out_err = null;
                        string? safe_out = validate_headless_path (out_path, false, out out_err);
                        if (safe_out == null) return out_err ?? "Security Error: Invalid output path.";

                        string low_src = safe_path.down ();
                        if ((low_src.has_suffix (".qmd") || low_src.has_suffix (".rmd") || low_src.has_suffix (".ipynb")) &&
                            GLib.Environment.get_variable ("IMLADRIS_MCP_ALLOW_EXEC") != "1") {
                            return "Security Error: Rendering executable notebooks (.qmd/.Rmd/.ipynb) via MCP requires IMLADRIS_MCP_ALLOW_EXEC=1.";
                        }
                        if (fmt == "pdf") {
                            ExportService.export_to_pdf (safe_path, safe_out, content);
                        } else {
                            ExportService.export_to_html (safe_path, safe_out, content);
                        }
                        return @"✔ Rendered $safe_path to $safe_out";
                    } catch (GLib.Error e) {
                        return @"Error rendering document: $(e.message)";
                    }
                }
                if (host != null) {
                    return host.trigger_render_from_mcp (fmt);
                }
                var proxy = try_connect_dbus_bridge ();
                if (proxy != null) {
                    try {
                        return proxy.render_document (fmt);
                    } catch (GLib.Error e) {
                        return @"Error: D-Bus bridge call failed: $(e.message)";
                    }
                }
                return "Error: No active Imladris window. Pass 'file_path' for headless rendering.";
            }

            if (name == "execute_code") {
                if (GLib.Environment.get_variable ("IMLADRIS_MCP_ALLOW_EXEC") != "1") {
                    return "Security Error: MCP execute_code is disabled by default. Set IMLADRIS_MCP_ALLOW_EXEC=1 to opt in.";
                }
                string cmd = get_opt_string (args, "command", "");
                if (cmd.length == 0) return "Error: No command provided.";
                string[] parts;
                try {
                    GLib.Shell.parse_argv (cmd, out parts);
                } catch (GLib.ShellError e) {
                    return @"Error: Invalid command syntax: $(e.message)";
                }
                if (parts.length == 0) return "Error: Empty command.";
                if (parts[0].contains ("/") || parts[0].contains ("\\")) {
                    return @"Security Error: MCP execute_code does not allow path-qualified binaries (got '$(parts[0])').";
                }
                string bin = parts[0];
                if (bin != "Rscript" && bin != "python3" && bin != "quarto" &&
                    bin != "latexmk" && bin != "pdflatex" && bin != "xelatex" && bin != "lualatex" &&
                    bin != "deno" && bin != "tsx" && bin != "bun" && bin != "tsc") {
                    return @"Security Error: MCP execute_code only permits Rscript, python3, quarto, LaTeX, or TypeScript runtimes (got '$bin').";
                }
                if (host != null) {
                    return host.execute_command_from_mcp (parts);
                }
                return "Error: execute_code requires an active Imladris window.";
            }

            return @"Unknown tool: $name";
        }

        public static async void run_stdio_server_async (McpHost? host, GLib.MainLoop? exit_loop = null) {
            new GLib.Thread<void*> ("mcp-stdio-worker", () => {
                string? line = null;
                while ((line = GLib.stdin.read_line ()) != null) {
                    if (line.strip ().length == 0) continue;
                    string resp = handle_json_rpc (line, host);
                    GLib.stdout.printf ("%s\n", resp);
                    GLib.stdout.flush ();
                }
                if (exit_loop != null) {
                    GLib.Idle.add (() => {
                        exit_loop.quit ();
                        return GLib.Source.REMOVE;
                    });
                }
                return null;
            });
        }
    }
}
