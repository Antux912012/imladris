// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/* PluginManager.vala
 *
 * Copyright 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

using GLib;
using JSC;
using Gee;
using Soup;

namespace Imladris.Plugins {

    [CCode (cname = "realpath", cheader_filename = "stdlib.h")]
    internal extern string? plugin_c_realpath (string path, char* resolved_path = null);

    public interface PluginHostWindow : GLib.Object {
        public abstract void show_toast (string message);
        public abstract string get_active_editor_text ();
        public abstract string get_active_selected_text ();
        public abstract void insert_in_active_editor (string text);
        public abstract void ask_elrond (string prompt);
        public abstract void append_console_log (string text);
        public abstract string[] list_workspace_files (string pattern);
        public abstract string read_workspace_file (string relative_path);
        public abstract void open_workspace_file (string relative_path, int line);
        public abstract string get_workspace_root ();
        public abstract string get_active_file_path ();
        public abstract void show_web_dialog (string title, string html_content, int width, int height);
    }

    public class PluginManifest : GLib.Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string version { get; set; default = "1.0.0"; }
        public string author { get; set; default = "Unknown"; }
        public string description { get; set; default = ""; }
        public string license { get; set; default = "Apache-2.0"; }
        public string icon { get; set; default = "application-x-addon-symbolic"; }
        public ArrayList<string> permissions { get; set; default = new ArrayList<string> (); }

        public bool has_permission (string perm) {
            return permissions.contains (perm);
        }

        public string format_permissions_summary () {
            if (permissions.is_empty) {
                return "None (Safe, isolated UI only)";
            }
            var parts = new ArrayList<string> ();
            foreach (var p in permissions) {
                switch (p) {
                    case "editor":
                        parts.add ("Editor Access");
                        break;
                    case "repl_r":
                        parts.add ("R Console Execution");
                        break;
                    case "repl_python":
                        parts.add ("Python Console Execution");
                        break;
                    case "elrond_ai":
                        parts.add ("Elrond AI Access");
                        break;
                    case "workspace":
                        parts.add ("Workspace Files Access");
                        break;
                    case "export":
                        parts.add ("Export Automation");
                        break;
                    default:
                        parts.add (p);
                        break;
                }
            }
            return string.joinv (", ", parts.to_array ());
        }

        public static bool is_valid_plugin_id (string id) {
            if (id.length == 0 || id.length > 64) return false;
            if (id.contains ("..") || id.contains ("/") || id.contains ("\\")) return false;
            for (int i = 0; i < id.length; i++) {
                char c = id[i];
                if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_')) {
                    return false;
                }
            }
            return true;
        }

        public static PluginManifest? from_json (string json_content) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_content);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return null;
                }
                var obj = root.get_object ();

                var m = new PluginManifest ();
                m.id = (obj.has_member ("id") && obj.get_member ("id").get_node_type () == Json.NodeType.VALUE && obj.get_member ("id").get_value_type () == typeof (string))
                    ? obj.get_string_member ("id").strip () : "";
                m.name = (obj.has_member ("name") && obj.get_member ("name").get_node_type () == Json.NodeType.VALUE && obj.get_member ("name").get_value_type () == typeof (string))
                    ? obj.get_string_member ("name") : m.id;
                m.version = (obj.has_member ("version") && obj.get_member ("version").get_node_type () == Json.NodeType.VALUE && obj.get_member ("version").get_value_type () == typeof (string))
                    ? obj.get_string_member ("version") : "1.0.0";
                m.author = (obj.has_member ("author") && obj.get_member ("author").get_node_type () == Json.NodeType.VALUE && obj.get_member ("author").get_value_type () == typeof (string))
                    ? obj.get_string_member ("author") : "Unknown";
                m.description = (obj.has_member ("description") && obj.get_member ("description").get_node_type () == Json.NodeType.VALUE && obj.get_member ("description").get_value_type () == typeof (string))
                    ? obj.get_string_member ("description") : "";
                m.license = (obj.has_member ("license") && obj.get_member ("license").get_node_type () == Json.NodeType.VALUE && obj.get_member ("license").get_value_type () == typeof (string))
                    ? obj.get_string_member ("license") : "Apache-2.0";
                m.icon = (obj.has_member ("icon") && obj.get_member ("icon").get_node_type () == Json.NodeType.VALUE && obj.get_member ("icon").get_value_type () == typeof (string))
                    ? obj.get_string_member ("icon") : "application-x-addon-symbolic";

                if (obj.has_member ("permissions") && obj.get_member ("permissions").get_node_type () == Json.NodeType.ARRAY) {
                    var perm_arr = obj.get_array_member ("permissions");
                    if (perm_arr != null) {
                        for (uint i = 0; i < perm_arr.get_length (); i++) {
                            var elem = perm_arr.get_element (i);
                            if (elem != null && elem.get_node_type () == Json.NodeType.VALUE && elem.get_value_type () == typeof (string)) {
                                m.permissions.add (elem.get_string ());
                            }
                        }
                    }
                }

                if (!is_valid_plugin_id (m.id)) {
                    debug ("Invalid or unsafe plugin id: '%s'", m.id);
                    return null;
                }
                return m;
            } catch (GLib.Error e) {
                debug ("Failed to parse plugin manifest: %s", e.message);
                return null;
            }
        }
    }

    public class PluginInstance : GLib.Object {
        public PluginManifest manifest { get; construct; }
        public string dir_path { get; construct; }
        public bool is_enabled { get; set; default = false; }
        public JSC.Context? context { get; private set; default = null; }
        public ArrayList<string> registered_buttons { get; private set; }
        public unowned PluginManager manager { get; construct; }

        public PluginInstance (PluginManifest manifest, string dir_path, PluginManager manager) {
            Object (manifest: manifest, dir_path: dir_path, manager: manager);
            this.registered_buttons = new ArrayList<string> ();
        }

        public bool load () {
            if (is_enabled && context != null) return true;

            string main_js_path = Path.build_filename (dir_path, "main.js");
            if (!FileUtils.test (main_js_path, FileTest.EXISTS)) {
                warning ("Plugin [%s] missing main.js at %s", manifest.id, main_js_path);
                return false;
            }

            string script;
            try {
                FileUtils.get_contents (main_js_path, out script);
            } catch (GLib.Error e) {
                warning ("Plugin [%s] could not read main.js: %s", manifest.id, e.message);
                return false;
            }

            // Ensure WebKit2 is initialized before JSC in GUI runs (avoid touching
            // WebKit in headless unit tests where GTK is not initialized).
            if (Gtk.is_initialized ()) {
                WebKit.WebContext.get_default ();
            }

            context = new JSC.Context ();
            context.push_exception_handler ((ctx, ex) => {
                warning ("Plugin [%s] JS exception: %s", manifest.name, ex.to_string ());
                manager.show_toast (@"Plugin '$(manifest.name)' error: $(ex.to_string ())");
            });

            var jsc_class = context.register_class ("NativeHostBridge", null, null, null);

                jsc_class.add_method ("showToast", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (jsc_args != null && jsc_args.length > 0) {
                        string msg = jsc_args.get (0).to_string ();
                        plugin.manager.show_toast (msg);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("addRibbonButton", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (jsc_args != null && jsc_args.length >= 3) {
                        string btn_id = jsc_args.get (0).to_string ();
                        string label = jsc_args.get (1).to_string ();
                        string icon = jsc_args.get (2).to_string ();
                        if (!plugin.registered_buttons.contains (btn_id)) {
                            plugin.registered_buttons.add (btn_id);
                        }
                        plugin.manager.add_ribbon_button (plugin.manifest.id, btn_id, label, icon);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("getText", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("editor")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'editor' permission.");
                        return new JSC.Value.string (plugin.context, "");
                    }
                    string text = plugin.manager.get_active_editor_text ();
                    return new JSC.Value.string (plugin.context, text);
                }, typeof (JSC.Value));

                jsc_class.add_method ("getSelectedText", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("editor")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'editor' permission.");
                        return new JSC.Value.string (plugin.context, "");
                    }
                    string text = plugin.manager.get_active_selected_text ();
                    return new JSC.Value.string (plugin.context, text);
                }, typeof (JSC.Value));

                jsc_class.add_method ("insertAtCursor", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("editor")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'editor' permission.");
                        return new JSC.Value.@null (plugin.context);
                    }
                    if (jsc_args != null && jsc_args.length > 0) {
                        string insert_text = jsc_args.get (0).to_string ();
                        plugin.manager.insert_in_active_editor (insert_text);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("runR", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("repl_r")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'repl_r' permission.");
                        return new JSC.Value.@null (plugin.context);
                    }
                    if (jsc_args != null && jsc_args.length > 0) {
                        string code = jsc_args.get (0).to_string ();
                        plugin.manager.run_r_code (code);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("runPython", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("repl_python")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'repl_python' permission.");
                        return new JSC.Value.@null (plugin.context);
                    }
                    if (jsc_args != null && jsc_args.length > 0) {
                        string code = jsc_args.get (0).to_string ();
                        plugin.manager.run_python_code (code);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("askElrond", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("elrond_ai")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'elrond_ai' permission.");
                        return new JSC.Value.@null (plugin.context);
                    }
                    if (jsc_args != null && jsc_args.length > 0) {
                        string prompt = jsc_args.get (0).to_string ();
                        plugin.manager.ask_elrond (prompt);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("listFiles", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("workspace")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'workspace' permission.");
                        return plugin.context.evaluate ("[]", -1);
                    }
                    string pattern = (jsc_args != null && jsc_args.length > 0) ? jsc_args.get (0).to_string () : "*.md";
                    string[] files = plugin.manager.list_workspace_files (pattern);
                    var builder = new Json.Builder ();
                    builder.begin_array ();
                    foreach (var f in files) {
                        builder.add_string_value (f);
                    }
                    builder.end_array ();
                    var gen = new Json.Generator ();
                    gen.set_root (builder.get_root ());
                    string json_str = gen.to_data (null);
                    return new JSC.Value.from_json (plugin.context, json_str);
                }, typeof (JSC.Value));

                jsc_class.add_method ("readFile", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("workspace")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'workspace' permission.");
                        return new JSC.Value.string (plugin.context, "");
                    }
                    if (jsc_args != null && jsc_args.length > 0) {
                        string rel_path = jsc_args.get (0).to_string ();
                        string content = plugin.manager.read_workspace_file (rel_path);
                        return new JSC.Value.string (plugin.context, content);
                    }
                    return new JSC.Value.string (plugin.context, "");
                }, typeof (JSC.Value));

                jsc_class.add_method ("openFile", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("workspace")) {
                        plugin.manager.show_toast (@"Plugin '$(plugin.manifest.name)' denied: missing 'workspace' permission.");
                        return new JSC.Value.@null (plugin.context);
                    }
                    if (jsc_args != null && jsc_args.length > 0) {
                        string rel_path = jsc_args.get (0).to_string ();
                        int line = (jsc_args.length > 1) ? (int) jsc_args.get (1).to_double () : 1;
                        plugin.manager.open_workspace_file (rel_path, line);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("getWorkspaceRoot", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("workspace")) {
                        return new JSC.Value.string (plugin.context, "");
                    }
                    return new JSC.Value.string (plugin.context, plugin.manager.get_workspace_root ());
                }, typeof (JSC.Value));

                jsc_class.add_method ("getActiveFilePath", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("workspace") && !plugin.manifest.has_permission ("editor")) {
                        return new JSC.Value.string (plugin.context, "");
                    }
                    return new JSC.Value.string (plugin.context, plugin.manager.get_active_file_path ());
                }, typeof (JSC.Value));

                jsc_class.add_method ("showWebDialog", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (!plugin.manifest.has_permission ("ui") && !plugin.manifest.has_permission ("editor")) {
                        return new JSC.Value.@null (plugin.context);
                    }
                    if (jsc_args != null && jsc_args.length >= 2) {
                        string title = jsc_args.get (0).to_string ();
                        string html = jsc_args.get (1).to_string ();
                        int width = (jsc_args.length > 2) ? (int) jsc_args.get (2).to_double () : 950;
                        int height = (jsc_args.length > 3) ? (int) jsc_args.get (3).to_double () : 700;
                        plugin.manager.show_web_dialog (title, html, width, height);
                    }
                    return new JSC.Value.@null (plugin.context);
                }, typeof (JSC.Value));

                jsc_class.add_method ("readAsset", (instance, jsc_args) => {
                    unowned PluginInstance plugin = (PluginInstance) instance;
                    if (jsc_args != null && jsc_args.length > 0) {
                        string asset_rel = jsc_args.get (0).to_string ();
                        if (!asset_rel.has_prefix ("/") && !asset_rel.contains ("..")) {
                            string asset_path = Path.build_filename (plugin.dir_path, asset_rel);
                            string? real_root = plugin_c_realpath (plugin.dir_path);
                            string? real_asset = plugin_c_realpath (asset_path);
                            if (real_root != null && real_asset != null &&
                                real_asset.has_prefix (real_root + "/") &&
                                FileUtils.test (real_asset, FileTest.IS_REGULAR)) {
                                try {
                                    string content;
                                    FileUtils.get_contents (real_asset, out content);
                                    return new JSC.Value.string (plugin.context, content);
                                } catch (GLib.Error e) {
                                    debug ("Error reading plugin asset: %s", e.message);
                                }
                            }
                        }
                    }
                    return new JSC.Value.string (plugin.context, "");
                }, typeof (JSC.Value));

                var host_obj = new JSC.Value.object (context, this, jsc_class);
                context.set_value ("_host", host_obj);

                // Inject declarative imladris bridge
                context.evaluate ("""
                    var imladris = {
                        ui: {
                            showToast: function(msg) { _host.showToast(String(msg)); },
                            addRibbonButton: function(id_or_options, label, icon, callback) {
                                var id, lbl, icn, cb;
                                if (typeof id_or_options === 'object' && id_or_options !== null) {
                                    id = id_or_options.id;
                                    lbl = id_or_options.label;
                                    icn = id_or_options.icon;
                                    cb = id_or_options.onClick || id_or_options.callback;
                                } else {
                                    id = id_or_options;
                                    lbl = label;
                                    icn = icon;
                                    cb = callback;
                                }
                                _host.addRibbonButton(String(id), String(lbl), String(icn));
                                imladris._callbacks = imladris._callbacks || {};
                                imladris._callbacks[id] = cb;
                            },
                            openWebDialog: function(options) {
                                var opts = options || {};
                                _host.showWebDialog(
                                    String(opts.title || "Imladris View"),
                                    String(opts.html || ""),
                                    Number(opts.width || 950),
                                    Number(opts.height || 700)
                                );
                            }
                        },
                        workspace: {
                            listFiles: function(pattern) { return _host.listFiles(pattern || "*.md"); },
                            readFile: function(path) { return _host.readFile(String(path)); },
                            openFile: function(path, line) { return _host.openFile(String(path), Number(line || 1)); },
                            getRoot: function() { return _host.getWorkspaceRoot(); },
                            getActiveFile: function() { return _host.getActiveFilePath(); }
                        },
                        plugin: {
                            readAsset: function(path) { return _host.readAsset(String(path)); }
                        },
                        editor: {
                            getText: function() { return _host.getText(); },
                            getSelectedText: function() { return _host.getSelectedText(); },
                            insertAtCursor: function(text) { _host.insertAtCursor(String(text)); }
                        },
                        repl: {
                            runR: function(code) { return _host.runR(String(code)); },
                            runPython: function(code) { return _host.runPython(String(code)); }
                        },
                        elrond: {
                            ask: function(prompt) { return _host.askElrond(String(prompt)); }
                        }
                    };
                """, -1);

                // Load plugin script
                context.evaluate_with_source_uri (script, -1, main_js_path, 1);
                context.evaluate ("if (typeof onload === 'function') { onload(); }", -1);

                is_enabled = true;
                return true;
        }

        public void trigger_ribbon_button (string button_id) {
            if (context != null && is_enabled) {
                var id_val = new JSC.Value.string (context, button_id);
                context.set_value ("_imladris_tmp_btn_id", id_val);
                context.evaluate ("if (imladris._callbacks && typeof imladris._callbacks[_imladris_tmp_btn_id] === 'function') { imladris._callbacks[_imladris_tmp_btn_id](); } _imladris_tmp_btn_id = undefined;", -1);
            }
        }

        public void unload () {
            if (context != null) {
                context.evaluate ("if (typeof onunload === 'function') { onunload(); }", -1);
            }

            foreach (var btn_id in registered_buttons) {
                manager.remove_ribbon_button (manifest.id, btn_id);
            }
            registered_buttons.clear ();

            context = null;
            is_enabled = false;
        }
    }

    public class PluginManager : GLib.Object {
        private static PluginManager? instance = null;

        public signal void ribbon_button_added (string plugin_id, string button_id, string label, string icon);
        public signal void ribbon_button_removed (string plugin_id, string button_id);
        public signal void toast_requested (string message);
        public signal void plugins_changed ();

        public unowned PluginHostWindow? active_window { get; set; default = null; }
        public Gee.HashMap<string, PluginInstance> plugins { get; private set; }
        public string user_plugins_dir { get; private set; }
        public string state_file_path { get; private set; }

        public string test_editor_text { get; set; default = ""; }
        public string test_last_r_code { get; set; default = ""; }
        public string test_last_python_code { get; set; default = ""; }
        public string test_last_elrond_prompt { get; set; default = ""; }

        private PluginManager () {
            plugins = new Gee.HashMap<string, PluginInstance> ();
            user_plugins_dir = Path.build_filename (Environment.get_user_data_dir (), "imladris", "plugins");
            state_file_path = Path.build_filename (Environment.get_user_config_dir (), "imladris", "plugins_state.json");
        }

        public static PluginManager get_default () {
            if (instance == null) {
                instance = new PluginManager ();
            }
            return instance;
        }

        public void initialize () {
            ensure_directories ();
            seed_default_plugins_if_empty ();
            load_all_plugins ();
        }

        private void ensure_directories () {
            try {
                var dir = File.new_for_path (user_plugins_dir);
                if (!dir.query_exists ()) {
                    dir.make_directory_with_parents ();
                }
                var config_dir = File.new_for_path (Path.get_dirname (state_file_path));
                if (!config_dir.query_exists ()) {
                    config_dir.make_directory_with_parents ();
                }
            } catch (GLib.Error e) {
                warning ("Could not create plugins directory: %s", e.message);
            }
        }

        private void seed_default_plugins_if_empty () {
            string word_counter_dir = Path.build_filename (user_plugins_dir, "word-counter");
            if (!FileUtils.test (word_counter_dir, FileTest.IS_DIR)) {
                try {
                    File.new_for_path (word_counter_dir).make_directory_with_parents ();

                    string manifest_json = """{
  "id": "word-counter",
  "name": "Word & Text Counter",
  "version": "1.0.0",
  "author": "Imladris Community",
  "description": "Calculates words, characters, lines and reading time stats in the active document.",
  "license": "Apache-2.0",
  "icon": "format-text-bold-symbolic",
  "permissions": ["editor"]
}""";
                    FileUtils.set_contents (Path.build_filename (word_counter_dir, "manifest.json"), manifest_json);

                    string main_js = """function onload() {
    imladris.ui.addRibbonButton("calc-stats", "Word Stats", "format-text-bold-symbolic", function() {
        var text = imladris.editor.getText();
        var words = text.trim().length > 0 ? text.trim().split(/\\s+/).length : 0;
        var chars = text.length;
        var lines = text.length > 0 ? text.split("\\n").length : 0;
        var reading_min = Math.max(1, Math.ceil(words / 200));
        imladris.ui.showToast("📊 Stats: " + words + " words | " + chars + " chars | " + lines + " lines (~" + reading_min + " min read)");
    });
}

function onunload() {
}
""";
                    FileUtils.set_contents (Path.build_filename (word_counter_dir, "main.js"), main_js);
                } catch (GLib.Error e) {
                    warning ("Failed to seed word-counter plugin: %s", e.message);
                }
            }

            string timestamp_dir = Path.build_filename (user_plugins_dir, "timestamp-injector");
            if (!FileUtils.test (timestamp_dir, FileTest.IS_DIR)) {
                try {
                    File.new_for_path (timestamp_dir).make_directory_with_parents ();

                    string manifest_json = """{
  "id": "timestamp-injector",
  "name": "Timestamp Injector",
  "version": "1.0.0",
  "author": "Imladris Community",
  "description": "Inserts current ISO timestamp comment at cursor position.",
  "license": "Apache-2.0",
  "icon": "alarm-symbolic",
  "permissions": ["editor"]
}""";
                    FileUtils.set_contents (Path.build_filename (timestamp_dir, "manifest.json"), manifest_json);

                    string main_js = """function onload() {
    imladris.ui.addRibbonButton("insert-time", "Insert Date", "alarm-symbolic", function() {
        var now = new Date();
        var dateStr = "<!-- Updated: " + now.toISOString() + " -->\\n";
        imladris.editor.insertAtCursor(dateStr);
        imladris.ui.showToast("Inserted timestamp at cursor.");
    });
}

function onunload() {
}
""";
                    FileUtils.set_contents (Path.build_filename (timestamp_dir, "main.js"), main_js);
                } catch (GLib.Error e) {
                    warning ("Failed to seed timestamp-injector plugin: %s", e.message);
                }
            }
        }

        public void load_all_plugins () {
            foreach (var existing in plugins.values) {
                if (existing.is_enabled) {
                    existing.unload ();
                }
            }
            plugins.clear ();
            var enabled_set = load_enabled_set ();

            // 1. Scan primary user plugins directory (in Flatpak: ~/.var/app/.../data/imladris/plugins)
            scan_and_load_plugins_dir (user_plugins_dir, enabled_set);

            // 2. Scan host plugins directory (~/.local/share/imladris/plugins) to discover host-installed extensions
            string host_dir = Path.build_filename (Environment.get_home_dir (), ".local", "share", "imladris", "plugins");
            if (host_dir != user_plugins_dir && FileUtils.test (host_dir, FileTest.IS_DIR)) {
                scan_and_load_plugins_dir (host_dir, enabled_set);
            }

            plugins_changed ();
        }

        private void scan_and_load_plugins_dir (string dir_path, ArrayList<string> enabled_set) {
            try {
                var dir = Dir.open (dir_path, 0);
                string? name = null;
                while ((name = dir.read_name ()) != null) {
                    string plugin_dir = Path.build_filename (dir_path, name);
                    if (FileUtils.test (plugin_dir, FileTest.IS_DIR)) {
                        // Do not reload if already loaded from earlier directory
                        string manifest_path = Path.build_filename (plugin_dir, "manifest.json");
                        if (FileUtils.test (manifest_path, FileTest.EXISTS)) {
                            try {
                                string? json = null;
                                FileUtils.get_contents (manifest_path, out json);
                                var m = PluginManifest.from_json (json);
                                if (m != null && m.id != "" && !plugins.has_key (m.id)) {
                                    load_plugin_from_directory (plugin_dir, enabled_set);
                                }
                            } catch (GLib.Error pe) {
                                warning ("Skipping invalid plugin in %s: %s", plugin_dir, pe.message);
                            }
                        }
                    }
                }
            } catch (GLib.Error e) {
                warning ("Error reading plugins dir %s: %s", dir_path, e.message);
            }
        }

        public PluginInstance? load_plugin_from_directory (string plugin_dir, ArrayList<string>? enabled_set = null) {
            string manifest_path = Path.build_filename (plugin_dir, "manifest.json");
            if (!FileUtils.test (manifest_path, FileTest.EXISTS)) return null;

            string json_content;
            try {
                FileUtils.get_contents (manifest_path, out json_content);
            } catch (GLib.Error e) {
                warning ("Could not read manifest at %s: %s", manifest_path, e.message);
                return null;
            }

            var manifest = PluginManifest.from_json (json_content);
            if (manifest == null) return null;

            var instance = new PluginInstance (manifest, plugin_dir, this);
            plugins.set (manifest.id, instance);

            bool should_enable = false;
            if (enabled_set != null) {
                should_enable = enabled_set.contains (manifest.id);
            } else {
                var current_enabled = load_enabled_set ();
                should_enable = current_enabled.contains (manifest.id);
            }

            if (should_enable) {
                instance.load ();
            }

            return instance;
        }

        private ArrayList<string> load_enabled_set () {
            var list = new ArrayList<string> ();
            if (!FileUtils.test (state_file_path, FileTest.EXISTS)) {
                // By default enable word-counter and timestamp-injector
                list.add ("word-counter");
                list.add ("timestamp-injector");
                save_enabled_set (list);
                return list;
            }

            try {
                string content;
                FileUtils.get_contents (state_file_path, out content);
                var parser = new Json.Parser ();
                parser.load_from_data (content);
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("enabled") && obj.get_member ("enabled").get_node_type () == Json.NodeType.ARRAY) {
                        var arr = obj.get_array_member ("enabled");
                        for (uint i = 0; i < arr.get_length (); i++) {
                            string? id_str = arr.get_string_element (i);
                            if (id_str != null) list.add (id_str);
                        }
                    }
                }
            } catch (GLib.Error e) {
                warning ("Error reading plugin state: %s", e.message);
            }
            return list;
        }

        private void save_enabled_set (ArrayList<string> list) {
            try {
                var builder = new Json.Builder ();
                builder.begin_object ();
                builder.set_member_name ("enabled");
                builder.begin_array ();
                foreach (var id in list) {
                    builder.add_string_value (id);
                }
                builder.end_array ();
                builder.end_object ();

                var generator = new Json.Generator ();
                generator.set_root (builder.get_root ());
                generator.set_pretty (true);
                generator.to_file (state_file_path);
            } catch (GLib.Error e) {
                warning ("Could not save plugin state: %s", e.message);
            }
        }

        public void enable_plugin (string plugin_id) {
            if (!plugins.has_key (plugin_id)) return;
            var instance = plugins.get (plugin_id);
            if (!instance.is_enabled) {
                instance.load ();
                var list = load_enabled_set ();
                if (!list.contains (plugin_id)) {
                    list.add (plugin_id);
                    save_enabled_set (list);
                }
                plugins_changed ();
            }
        }

        public void disable_plugin (string plugin_id) {
            if (!plugins.has_key (plugin_id)) return;
            var instance = plugins.get (plugin_id);
            if (instance.is_enabled) {
                instance.unload ();
                var list = load_enabled_set ();
                if (list.contains (plugin_id)) {
                    list.remove (plugin_id);
                    save_enabled_set (list);
                }
                plugins_changed ();
            }
        }

        public bool delete_plugin (string plugin_id) {
            if (!plugins.has_key (plugin_id)) return false;
            var instance = plugins.get (plugin_id);
            if (instance.is_enabled) {
                instance.unload ();
            }
            plugins.unset (plugin_id);

            var list = load_enabled_set ();
            list.remove (plugin_id);
            save_enabled_set (list);

            Core.PlatformUtils.delete_directory_recursive (File.new_for_path (instance.dir_path));

            plugins_changed ();
            return true;
        }

        public void trigger_ribbon_button (string plugin_id, string button_id) {
            if (plugins.has_key (plugin_id)) {
                plugins.get (plugin_id).trigger_ribbon_button (button_id);
            }
        }

        public void show_toast (string message) {
            toast_requested (message);
            if (active_window != null) {
                active_window.show_toast (message);
            }
        }

        public void add_ribbon_button (string plugin_id, string button_id, string label, string icon) {
            ribbon_button_added (plugin_id, button_id, label, icon);
        }

        public void remove_ribbon_button (string plugin_id, string button_id) {
            ribbon_button_removed (plugin_id, button_id);
        }

        public string get_active_editor_text () {
            if (active_window != null) {
                return active_window.get_active_editor_text ();
            }
            return test_editor_text;
        }

        public string get_active_selected_text () {
            if (active_window != null) {
                return active_window.get_active_selected_text ();
            }
            return "";
        }

        public void insert_in_active_editor (string text) {
            if (active_window != null) {
                active_window.insert_in_active_editor (text);
            } else {
                test_editor_text += text;
            }
        }

        public void run_r_code (string code) {
            test_last_r_code = code;
            Services.PersistentSessionManager.get_default ().execute_r.begin (code, (obj, res) => {
                string? plot_file = null;
                string output = Services.PersistentSessionManager.get_default ().execute_r.end (res, out plot_file);
                if (active_window != null) {
                    active_window.append_console_log (@"▶ [Plugin R] $code\n$output");
                }
            });
        }

        public void run_python_code (string code) {
            test_last_python_code = code;
            Services.PersistentSessionManager.get_default ().execute_python.begin (code, (obj, res) => {
                string? plot_file = null;
                string output = Services.PersistentSessionManager.get_default ().execute_python.end (res, out plot_file);
                if (active_window != null) {
                    active_window.append_console_log (@"▶ [Plugin Python] $code\n$output");
                }
            });
        }

        public void ask_elrond (string prompt) {
            test_last_elrond_prompt = prompt;
            if (active_window != null) {
                active_window.ask_elrond (prompt);
            }
        }

        public string[] test_workspace_files = {};
        public Gee.HashMap<string, string> test_workspace_file_contents = new Gee.HashMap<string, string> ();
        public string test_last_opened_file = "";
        public string test_last_web_dialog_title = "";
        public string test_last_web_dialog_html = "";

        public string[] list_workspace_files (string pattern) {
            if (active_window != null) {
                return active_window.list_workspace_files (pattern);
            }
            return test_workspace_files;
        }

        public string read_workspace_file (string relative_path) {
            if (active_window != null) {
                return active_window.read_workspace_file (relative_path);
            }
            if (test_workspace_file_contents.has_key (relative_path)) {
                return test_workspace_file_contents.get (relative_path);
            }
            return "";
        }

        public void open_workspace_file (string relative_path, int line) {
            if (active_window != null) {
                active_window.open_workspace_file (relative_path, line);
            }
            test_last_opened_file = relative_path;
        }

        public string get_workspace_root () {
            if (active_window != null) {
                return active_window.get_workspace_root ();
            }
            return "";
        }

        public string get_active_file_path () {
            if (active_window != null) {
                return active_window.get_active_file_path ();
            }
            return "";
        }

        public void show_web_dialog (string title, string html_content, int width, int height) {
            if (active_window != null) {
                active_window.show_web_dialog (title, html_content, width, height);
            }
            test_last_web_dialog_title = title;
            test_last_web_dialog_html = html_content;
        }

        public async bool import_plugin_archive (string archive_path, Gtk.Window parent_window) throws GLib.Error {
            var src_file = File.new_for_path (archive_path);
            if (!src_file.query_exists ()) {
                throw new IOError.NOT_FOUND (@"Archive file not found: $archive_path");
            }

            string tmp_dir = DirUtils.make_tmp ("imladris_plugin_import_XXXXXX");
            try {
                // Copy source archive into local temp dir first to ensure access across Flatpak document portals
                string local_archive = Path.build_filename (tmp_dir, "archive.zip");
                var dest_file = File.new_for_path (local_archive);
                src_file.copy (dest_file, FileCopyFlags.OVERWRITE);

                // 1. Inspect zip entries for path traversal/symlinks/zip-bombs/duplicate manifests BEFORE extracting
                string inspect_py = "import sys, zipfile, stat\n"
                    + "manifest_data = None\n"
                    + "total_uncompressed = 0\n"
                    + "MAX_BYTES = 50 * 1024 * 1024\n"
                    + "MAX_FILES = 500\n"
                    + "with zipfile.ZipFile(sys.argv[1], 'r') as zf:\n"
                    + "    infos = zf.infolist()\n"
                    + "    if len(infos) > MAX_FILES:\n"
                    + "        raise ValueError('Plugin archive exceeds maximum file count')\n"
                    + "    for zi in infos:\n"
                    + "        name = zi.filename.replace('\\\\', '/')\n"
                    + "        if name.startswith('/') or '..' in name.split('/'):\n"
                    + "            raise ValueError('Unsafe path in plugin archive: ' + zi.filename)\n"
                    + "        mode = (zi.external_attr >> 16) & 0o170000\n"
                    + "        if mode == stat.S_IFLNK:\n"
                    + "            raise ValueError('Symlinks are forbidden in plugin archives: ' + zi.filename)\n"
                    + "        total_uncompressed += zi.file_size\n"
                    + "        if total_uncompressed > MAX_BYTES:\n"
                    + "            raise ValueError('Plugin archive exceeds uncompressed size limit')\n"
                    + "        if name == 'manifest.json' or name.endswith('/manifest.json'):\n"
                    + "            if manifest_data is not None:\n"
                    + "                raise ValueError('Multiple manifest.json entries in plugin archive')\n"
                    + "            manifest_data = zf.read(zi.filename).decode('utf-8')\n"
                    + "if manifest_data is None:\n"
                    + "    raise ValueError('manifest.json not found in plugin archive')\n"
                    + "sys.stdout.write(manifest_data)\n";
                var inspect_proc = new Subprocess.newv (
                    { "python3", "-c", inspect_py, local_archive },
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
                );
                string manifest_json, inspect_err;
                yield inspect_proc.communicate_utf8_async (null, null, out manifest_json, out inspect_err);
                if (!inspect_proc.get_successful ()) {
                    throw new IOError.INVALID_DATA (@"Invalid or unsafe plugin archive: $(inspect_err ?? "verification failed")");
                }

                var manifest = PluginManifest.from_json (manifest_json);
                if (manifest == null || manifest.id == "") {
                    throw new IOError.INVALID_DATA ("Invalid plugin manifest: missing id or corrupted JSON.");
                }

                // Check consent via Adw.AlertDialog BEFORE extracting files
                var alert = new Adw.AlertDialog (
                    @"Install Plugin: $(manifest.name)",
                    @"Author: $(manifest.author)\n" +
                    @"Version: $(manifest.version)\n" +
                    @"License: $(manifest.license)\n\n" +
                    @"Description:\n$(manifest.description)\n\n" +
                    @"Requested Permissions:\n" + format_permissions_list (manifest.permissions)
                );
                alert.add_response ("cancel", "Cancel");
                alert.add_response ("install", "Install & Enable");
                alert.set_response_appearance ("install", Adw.ResponseAppearance.SUGGESTED);
                alert.set_default_response ("install");
                alert.set_close_response ("cancel");

                string response = yield alert.choose (parent_window, null);
                if (response != "install") {
                    Core.PlatformUtils.delete_directory_recursive (File.new_for_path (tmp_dir));
                    return false;
                }

                // Extract using python3 -m zipfile after consent & validation
                string[] argv = { "python3", "-m", "zipfile", "-e", local_archive, tmp_dir };
                var subp = new Subprocess.newv (argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                yield subp.wait_check_async ();

                // Search for manifest.json and main.js, verifying it matches the inspected manifest
                string? found_manifest_path = find_manifest_file (tmp_dir);
                if (found_manifest_path == null) {
                    throw new IOError.INVALID_DATA ("Invalid plugin archive: manifest.json not found in package.");
                }
                string extracted_manifest_json;
                FileUtils.get_contents (found_manifest_path, out extracted_manifest_json);
                if (extracted_manifest_json != manifest_json) {
                    throw new IOError.INVALID_DATA ("Security Error: Extracted manifest.json does not match inspected archive manifest.");
                }

                string plugin_root_extracted = Path.get_dirname (found_manifest_path);
                string main_js_path = Path.build_filename (plugin_root_extracted, "main.js");
                if (!FileUtils.test (main_js_path, FileTest.EXISTS)) {
                    throw new IOError.INVALID_DATA ("Invalid plugin archive: main.js not found alongside manifest.json.");
                }

                // Destination
                string target_dir = Path.build_filename (user_plugins_dir, manifest.id);
                var target_file = File.new_for_path (target_dir);
                if (target_file.query_exists ()) {
                    if (plugins.has_key (manifest.id)) {
                        disable_plugin (manifest.id);
                    }
                    Core.PlatformUtils.delete_directory_recursive (target_file);
                }

                copy_directory_recursive (File.new_for_path (plugin_root_extracted), target_file);
                Core.PlatformUtils.delete_directory_recursive (File.new_for_path (tmp_dir));

                // Load and enable
                var inst = load_plugin_from_directory (target_dir);
                if (inst != null) {
                    enable_plugin (manifest.id);
                    show_toast (@"Plugin '$(manifest.name)' installed and activated!");
                }

                return true;
            } catch (GLib.Error e) {
                Core.PlatformUtils.delete_directory_recursive (File.new_for_path (tmp_dir));
                throw e;
            }
        }

        private static string format_permissions_list (ArrayList<string> permissions) {
            if (permissions.is_empty) return "  • None (Declarative UI only, sandboxed)\n";
            var sb = new StringBuilder ();
            foreach (var p in permissions) {
                switch (p) {
                    case "editor":
                        sb.append ("  • Editor Access (Read and insert buffer text)\n");
                        break;
                    case "repl_r":
                        sb.append ("  • R Console Execution (Run R scripts)\n");
                        break;
                    case "repl_python":
                        sb.append ("  • Python Console Execution (Run Python code)\n");
                        break;
                    case "elrond_ai":
                        sb.append ("  • Elrond AI Access (Send queries to AI engine)\n");
                        break;
                    case "workspace":
                        sb.append ("  • Workspace Access (Read and navigate project files)\n");
                        break;
                    case "export":
                        sb.append ("  • Export Automation (Trigger document exports)\n");
                        break;
                    default:
                        sb.append (@"  • Custom: $p\n");
                        break;
                }
            }
            return sb.str;
        }

        private static string? find_manifest_file (string search_dir) {
            string direct = Path.build_filename (search_dir, "manifest.json");
            if (FileUtils.test (direct, FileTest.EXISTS)) return direct;

            try {
                var dir = Dir.open (search_dir, 0);
                string? name = null;
                while ((name = dir.read_name ()) != null) {
                    string sub = Path.build_filename (search_dir, name);
                    if (FileUtils.test (sub, FileTest.IS_DIR)) {
                        string candidate = Path.build_filename (sub, "manifest.json");
                        if (FileUtils.test (candidate, FileTest.EXISTS)) {
                            return candidate;
                        }
                    }
                }
            } catch (GLib.Error e) {
                // Ignore
            }
            return null;
        }

        public static void copy_directory_recursive (File source, File destination) throws GLib.Error {
            if (!destination.query_exists ()) {
                destination.make_directory_with_parents ();
            }
            var enumerator = source.enumerate_children (
                FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS
            );
            try {
                FileInfo? info = null;
                while ((info = enumerator.next_file ()) != null) {
                    if (info.get_file_type () == FileType.SYMBOLIC_LINK) {
                        continue; // Skip symlinks for package integrity and security
                    }
                    var child_src = source.get_child (info.get_name ());
                    var child_dest = destination.get_child (info.get_name ());
                    if (info.get_file_type () == FileType.DIRECTORY) {
                        copy_directory_recursive (child_src, child_dest);
                    } else {
                        child_src.copy (child_dest, FileCopyFlags.OVERWRITE | FileCopyFlags.NOFOLLOW_SYMLINKS);
                    }
                }
            } finally {
                try { enumerator.close (); } catch (GLib.Error e) {}
            }
        }

        public const string COMMUNITY_RAW_BASE_URL = "https://raw.githubusercontent.com/Antux912012/imladris/main/";
        public const string COMMUNITY_REGISTRY_URL = "https://raw.githubusercontent.com/Antux912012/imladris/main/community-plugins/registry.json";

        private Soup.Session? community_session = null;

        private Soup.Session get_community_session () {
            if (community_session == null) {
                community_session = new Soup.Session () {
                    timeout = 20,
                    user_agent = "Imladris/0.43.1 (https://github.com/Antux912012/imladris)"
                };
            }
            return community_session;
        }

        private string get_registry_cache_path () {
            return Path.build_filename (Environment.get_user_cache_dir (), "imladris", "community_plugins_registry.json");
        }

        private async GLib.Bytes download_https_bytes_async (string url, GLib.Cancellable? cancellable = null) throws GLib.Error {
            if (!url.has_prefix ("https://")) {
                throw new IOError.INVALID_ARGUMENT (@"Refusing non-HTTPS plugin URL: $url");
            }
            var msg = new Soup.Message ("GET", url);
            msg.request_headers.append ("Accept", "application/json, text/plain, application/octet-stream, */*");
            var bytes = yield get_community_session ().send_and_read_async (msg, Priority.DEFAULT, cancellable);
            if (msg.status_code != 200 || bytes == null) {
                throw new IOError.FAILED (@"HTTP $(msg.status_code) while fetching $url");
            }
            return bytes;
        }

        public async ArrayList<CommunityPluginEntry> fetch_community_registry_async (
            bool force_refresh = false,
            GLib.Cancellable? cancellable = null
        ) throws GLib.Error {
            string cache_path = get_registry_cache_path ();
            string? raw_json = null;

            try {
                var bytes = yield download_https_bytes_async (COMMUNITY_REGISTRY_URL, cancellable);
                raw_json = Core.PlatformUtils.bytes_to_string (bytes);
                if (raw_json != null && raw_json.strip ().length > 0) {
                    try {
                        var cache_dir = File.new_for_path (Path.get_dirname (cache_path));
                        if (!cache_dir.query_exists ()) {
                            cache_dir.make_directory_with_parents ();
                        }
                        FileUtils.set_contents (cache_path, raw_json);
                    } catch (GLib.Error ce) {
                        debug ("Could not cache community plugin registry: %s", ce.message);
                    }
                }
            } catch (GLib.Error net_err) {
                if (!force_refresh && FileUtils.test (cache_path, FileTest.EXISTS)) {
                    try {
                        FileUtils.get_contents (cache_path, out raw_json);
                    } catch (GLib.Error re) {}
                }
                if (raw_json == null || raw_json.strip ().length == 0) {
                    throw net_err;
                }
            }

            return CommunityPluginEntry.parse_registry_json (raw_json ?? "");
        }

        public async bool install_community_plugin_async (
            CommunityPluginEntry entry,
            Gtk.Window? parent_window,
            GLib.Cancellable? cancellable = null
        ) throws GLib.Error {
            if (!PluginManifest.is_valid_plugin_id (entry.id)) {
                throw new IOError.INVALID_DATA (@"Invalid community plugin ID: $(entry.id)");
            }

            // Always show permission consent dialog before downloading or installing executable JS
            if (parent_window != null) {
                var alert = new Adw.AlertDialog (
                    @"Install Community Plugin: $(entry.name)",
                    @"Author: $(entry.author)\n" +
                    @"Version: $(entry.version) ($(entry.language))\n" +
                    @"License: $(entry.license)\n\n" +
                    @"Description:\n$(entry.description)\n\n" +
                    @"Requested Permissions:\n" + format_permissions_list (entry.permissions)
                );
                alert.add_response ("cancel", "Cancel");
                alert.add_response ("install", "Download & Enable");
                alert.set_response_appearance ("install", Adw.ResponseAppearance.SUGGESTED);
                alert.set_default_response ("install");
                alert.set_close_response ("cancel");

                string response = yield alert.choose (parent_window, null);
                if (response != "install") {
                    return false;
                }
            }

            // Option A: Archive URL (.implugin / .zip)
            if (entry.archive_url.length > 0) {
                string tmp_dir = DirUtils.make_tmp ("imladris_community_dl_XXXXXX");
                try {
                    var archive_bytes = yield download_https_bytes_async (entry.archive_url, cancellable);
                    string local_zip = Path.build_filename (tmp_dir, @"$(entry.id).implugin");
                    FileUtils.set_data (local_zip, archive_bytes.get_data ());
                    bool ok = yield import_plugin_archive (local_zip, parent_window);
                    Core.PlatformUtils.delete_directory_recursive (File.new_for_path (tmp_dir));
                    return ok;
                } catch (GLib.Error e) {
                    Core.PlatformUtils.delete_directory_recursive (File.new_for_path (tmp_dir));
                    throw e;
                }
            }

            // Option B: Direct repository files (manifest.json + main.js + optional assets)
            if (entry.manifest_url.length == 0 || entry.main_url.length == 0) {
                throw new IOError.INVALID_DATA (@"Community plugin '$(entry.id)' is missing manifest/main download URLs.");
            }

            var manifest_bytes = yield download_https_bytes_async (entry.manifest_url, cancellable);
            string manifest_json = Core.PlatformUtils.bytes_to_string (manifest_bytes);
            var parsed_manifest = PluginManifest.from_json (manifest_json);
            if (parsed_manifest == null || parsed_manifest.id != entry.id) {
                throw new IOError.INVALID_DATA (@"Downloaded manifest.json for '$(entry.id)' is invalid or ID mismatch.");
            }
            foreach (string perm in parsed_manifest.permissions) {
                if (!entry.permissions.contains (perm)) {
                    throw new IOError.PERMISSION_DENIED (@"Security Error: Downloaded manifest.json requests unconsented permission '$perm'.");
                }
            }

            var main_bytes = yield download_https_bytes_async (entry.main_url, cancellable);
            string main_js = Core.PlatformUtils.bytes_to_string (main_bytes);
            if (main_js.strip ().length == 0) {
                throw new IOError.INVALID_DATA (@"Downloaded main.js for '$(entry.id)' is empty.");
            }

            ensure_directories ();
            string target_dir = Path.build_filename (user_plugins_dir, parsed_manifest.id);
            var target_file = File.new_for_path (target_dir);
            if (target_file.query_exists ()) {
                if (plugins.has_key (parsed_manifest.id)) {
                    disable_plugin (parsed_manifest.id);
                }
                Core.PlatformUtils.delete_directory_recursive (target_file);
            }
            target_file.make_directory_with_parents ();

            FileUtils.set_contents (Path.build_filename (target_dir, "manifest.json"), manifest_json);
            FileUtils.set_contents (Path.build_filename (target_dir, "main.js"), main_js);

            foreach (var asset_entry in entry.asset_urls.entries) {
                string rel_path = asset_entry.key;
                string asset_url = asset_entry.value;
                if (rel_path.has_prefix ("/") || rel_path.contains ("..")) {
                    continue;
                }
                var a_bytes = yield download_https_bytes_async (asset_url, cancellable);
                string full_asset_path = Path.build_filename (target_dir, rel_path);
                var parent_dir = File.new_for_path (Path.get_dirname (full_asset_path));
                if (!parent_dir.query_exists ()) {
                    parent_dir.make_directory_with_parents ();
                }
                FileUtils.set_data (full_asset_path, a_bytes.get_data ());
            }

            var inst = load_plugin_from_directory (target_dir);
            if (inst != null) {
                enable_plugin (parsed_manifest.id);
                show_toast (@"Community plugin '$(parsed_manifest.name)' installed and activated!");
                return true;
            }
            return false;
        }
    }

    /**
     * Metadata record for a plugin published in community-plugins/registry.json.
     */
    public class CommunityPluginEntry : GLib.Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string version { get; set; default = "1.0.0"; }
        public string author { get; set; default = "Community"; }
        public string description { get; set; default = ""; }
        public string license { get; set; default = "Apache-2.0"; }
        public string icon { get; set; default = "application-x-addon-symbolic"; }
        public string category { get; set; default = "General"; }
        public string language { get; set; default = "JavaScript"; }
        public string homepage { get; set; default = ""; }
        public string manifest_url { get; set; default = ""; }
        public string main_url { get; set; default = ""; }
        public string archive_url { get; set; default = ""; }
        public ArrayList<string> tags { get; set; default = new ArrayList<string> (); }
        public ArrayList<string> permissions { get; set; default = new ArrayList<string> (); }
        public HashMap<string, string> asset_urls { get; set; default = new HashMap<string, string> (); }

        public bool matches_query (string raw_query) {
            string q = raw_query.strip ().down ();
            if (q.length == 0) {
                return true;
            }

            var haystack = new StringBuilder ();
            haystack.append (id.down ());
            haystack.append_c (' ');
            haystack.append (name.down ());
            haystack.append_c (' ');
            haystack.append (author.down ());
            haystack.append_c (' ');
            haystack.append (description.down ());
            haystack.append_c (' ');
            haystack.append (category.down ());
            haystack.append_c (' ');
            haystack.append (language.down ());
            foreach (var t in tags) {
                haystack.append_c (' ');
                haystack.append (t.down ());
            }
            string hay = haystack.str;

            foreach (string token in q.split (" ")) {
                string tk = token.strip ();
                if (tk.length > 0 && !hay.contains (tk)) {
                    return false;
                }
            }
            return true;
        }

        public string format_permissions_summary () {
            var tmp = new PluginManifest ();
            tmp.permissions = this.permissions;
            return tmp.format_permissions_summary ();
        }

        private static string resolve_repo_url (string raw) {
            string s = raw.strip ();
            if (s.length == 0) return "";
            if (s.has_prefix ("https://")) return s;
            if (s.has_prefix ("http://")) return ""; // Reject insecure HTTP
            while (s.has_prefix ("/")) {
                s = s.substring (1);
            }
            if (s.contains ("..")) return "";
            return PluginManager.COMMUNITY_RAW_BASE_URL + s;
        }

        public static ArrayList<CommunityPluginEntry> parse_registry_json (string json_content) {
            var results = new ArrayList<CommunityPluginEntry> ();
            if (json_content.strip ().length == 0) {
                return results;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json_content);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return results;
                }
                var root_obj = root.get_object ();
                if (!root_obj.has_member ("plugins") || root_obj.get_member ("plugins").get_node_type () != Json.NodeType.ARRAY) {
                    return results;
                }
                var arr = root_obj.get_array_member ("plugins");
                for (uint i = 0; i < arr.get_length (); i++) {
                    if (arr.get_element (i).get_node_type () != Json.NodeType.OBJECT) continue;
                    var obj = arr.get_object_element (i);
                    string id = obj.has_member ("id") ? (obj.get_string_member ("id") ?? "").strip () : "";
                    if (!PluginManifest.is_valid_plugin_id (id)) continue;

                    var e = new CommunityPluginEntry ();
                    e.id = id;
                    e.name = obj.has_member ("name") ? (obj.get_string_member ("name") ?? id) : id;
                    e.version = obj.has_member ("version") ? (obj.get_string_member ("version") ?? "1.0.0") : "1.0.0";
                    e.author = obj.has_member ("author") ? (obj.get_string_member ("author") ?? "Community") : "Community";
                    e.description = obj.has_member ("description") ? (obj.get_string_member ("description") ?? "") : "";
                    e.license = obj.has_member ("license") ? (obj.get_string_member ("license") ?? "Apache-2.0") : "Apache-2.0";
                    e.icon = obj.has_member ("icon") ? (obj.get_string_member ("icon") ?? "application-x-addon-symbolic") : "application-x-addon-symbolic";
                    e.category = obj.has_member ("category") ? (obj.get_string_member ("category") ?? "General") : "General";
                    e.language = obj.has_member ("language") ? (obj.get_string_member ("language") ?? "JavaScript") : "JavaScript";
                    if (obj.has_member ("homepage")) {
                        string hp = (obj.get_string_member ("homepage") ?? "").strip ();
                        if (hp.has_prefix ("https://")) {
                            e.homepage = hp;
                        }
                    }
                    if (obj.has_member ("archive_url")) {
                        e.archive_url = resolve_repo_url (obj.get_string_member ("archive_url") ?? "");
                    }
                    if (obj.has_member ("files") && obj.get_member ("files").get_node_type () == Json.NodeType.OBJECT) {
                        var files_obj = obj.get_object_member ("files");
                        if (files_obj.has_member ("manifest")) {
                            e.manifest_url = resolve_repo_url (files_obj.get_string_member ("manifest") ?? "");
                        }
                        if (files_obj.has_member ("main")) {
                            e.main_url = resolve_repo_url (files_obj.get_string_member ("main") ?? "");
                        }
                        if (files_obj.has_member ("assets") && files_obj.get_member ("assets").get_node_type () == Json.NodeType.OBJECT) {
                            var assets_obj = files_obj.get_object_member ("assets");
                            assets_obj.foreach_member ((o, member_name, node) => {
                                if (node.get_node_type () == Json.NodeType.VALUE) {
                                    string resolved = resolve_repo_url (node.get_string () ?? "");
                                    if (resolved.length > 0 && !member_name.has_prefix ("/") && !member_name.contains ("..")) {
                                        e.asset_urls.set (member_name, resolved);
                                    }
                                }
                            });
                        }
                    }
                    if (obj.has_member ("tags") && obj.get_member ("tags").get_node_type () == Json.NodeType.ARRAY) {
                        var tags_arr = obj.get_array_member ("tags");
                        for (uint ti = 0; ti < tags_arr.get_length (); ti++) {
                            string? tv = tags_arr.get_string_element (ti);
                            if (tv != null && tv.strip ().length > 0) e.tags.add (tv.strip ());
                        }
                    }
                    if (obj.has_member ("permissions") && obj.get_member ("permissions").get_node_type () == Json.NodeType.ARRAY) {
                        var perms_arr = obj.get_array_member ("permissions");
                        for (uint pi = 0; pi < perms_arr.get_length (); pi++) {
                            string? pv = perms_arr.get_string_element (pi);
                            if (pv != null && pv.strip ().length > 0) e.permissions.add (pv.strip ());
                        }
                    }

                    if (e.archive_url.length > 0 || (e.manifest_url.length > 0 && e.main_url.length > 0)) {
                        results.add (e);
                    }
                }
            } catch (GLib.Error e) {
                debug ("Failed to parse community plugin registry: %s", e.message);
            }
            return results;
        }
    }
}
