// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Soup;
using Json;
using Imladris.Qual;

namespace Imladris.Bridges.Cytoscape {

    public errordomain CyRestError {
        OFFLINE,
        HTTP_FAILED,
        PARSE_ERROR
    }

    /**
     * Bidirectional Cytoscape Desktop CyREST Client (libsoup-3.0).
     * Handles background health discovery, CX2 network push, Nord visual style injection,
     * automatic layout application, selected node pull sync, and SVG/PNG figure export.
     */
    public class CyRestClient : GLib.Object {
        private static CyRestClient? _default = null;

        public string host { get; set; default = "localhost"; }
        public int port { get; set; default = 1234; }
        public bool is_connected { get; private set; default = false; }
        public string api_version { get; private set; default = ""; }
        public int64 last_network_suid { get; set; default = 0; }

        private Soup.Session session;
        private uint poll_timer_id = 0;

        public signal void connection_status_changed (bool connected, string label);

        public static CyRestClient get_default () {
            if (_default == null) {
                _default = new CyRestClient ();
            }
            return _default;
        }

        public CyRestClient (string host = "localhost", int port = 1234) {
            this.host = host;
            this.port = port;
            this.session = new Soup.Session () {
                timeout = 5,
                user_agent = "Imladris-CyREST-Bridge/1.0"
            };
        }

        public string base_url () {
            return @"http://$(host):$(port)/v1";
        }

        private static string bytes_to_utf8 (GLib.Bytes b) {
            size_t sz = b.get_size ();
            if (sz == 0) return "";
            unowned uint8[] raw = b.get_data ();
            var sb = new GLib.StringBuilder.sized (sz + 1);
            sb.append_len ((string) raw, (ssize_t) sz);
            return sb.str;
        }

        public void start_background_discovery (uint interval_seconds = 15) {
            if (poll_timer_id != 0) return;
            probe_health_async.begin ();
            poll_timer_id = GLib.Timeout.add_seconds (interval_seconds, () => {
                probe_health_async.begin ();
                return GLib.Source.CONTINUE;
            });
        }

        public void stop_background_discovery () {
            if (poll_timer_id != 0) {
                GLib.Source.remove (poll_timer_id);
                poll_timer_id = 0;
            }
        }

        public async bool probe_health_async () {
            var msg = new Soup.Message ("GET", base_url ());
            msg.request_headers.append ("Accept", "application/json");
            try {
                var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
                if (msg.status_code >= 200 && msg.status_code < 300 && bytes != null) {
                    string txt = bytes_to_utf8 (bytes);
                    string ver = "v1";
                    try {
                        var p = new Json.Parser ();
                        p.load_from_data (txt, -1);
                        var root = p.get_root ();
                        if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                            var obj = root.get_object ();
                            if (obj.has_member ("apiVersion")) ver = obj.get_string_member ("apiVersion");
                        }
                    } catch (GLib.Error pe) {}

                    bool changed = (!is_connected || api_version != ver);
                    is_connected = true;
                    api_version = ver;
                    if (changed) {
                        connection_status_changed (true, @"Cytoscape Live ($ver)");
                    }
                    return true;
                }
            } catch (GLib.Error e) {}

            if (is_connected) {
                is_connected = false;
                api_version = "";
                connection_status_changed (false, "Cytoscape Offline");
            }
            return false;
        }

        /**
         * Serializes QualGraph to CX2, pushes to Cytoscape Desktop, injects the Nord Visual Style,
         * and applies the requested layout algorithm. Returns the Cytoscape networkSUID.
         */
        public async int64 push_network_cx2_async (
            QualGraph graph,
            string layout_algorithm = "force-directed"
        ) throws CyRestError {
            string cx2_body = Cx2Serializer.serialize (graph);
            string url = @"$(base_url ())/networks?format=cx2&collection=Imladris";
            var msg = new Soup.Message ("POST", url);
            msg.set_request_body_from_bytes ("application/json", new GLib.Bytes (cx2_body.data));

            GLib.Bytes? resp_bytes = null;
            try {
                resp_bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
            } catch (GLib.Error e) {
                is_connected = false;
                connection_status_changed (false, "Cytoscape Offline");
                throw new CyRestError.OFFLINE (@"Cannot reach Cytoscape CyREST at $(base_url ()): $(e.message)");
            }

            if (msg.status_code < 200 || msg.status_code >= 300 || resp_bytes == null) {
                throw new CyRestError.HTTP_FAILED (@"CyREST POST /networks returned HTTP $(msg.status_code)");
            }

            int64 suid = extract_suid_from_response (resp_bytes);
            this.last_network_suid = suid;
            this.is_connected = true;
            connection_status_changed (true, @"Cytoscape SUID $suid");

            // Push & apply Nord Visual Style
            yield apply_nord_style_async (suid);

            // Trigger layout automation
            string clean_layout = layout_algorithm.strip () != "" ? layout_algorithm.strip () : "force-directed";
            var lmsg = new Soup.Message ("GET", @"$(base_url ())/apply/layouts/$(GLib.Uri.escape_string (clean_layout, null, false))/$suid");
            try {
                yield session.send_and_read_async (lmsg, GLib.Priority.DEFAULT, null);
                if (lmsg.status_code < 200 || lmsg.status_code >= 300) {
                    throw new CyRestError.HTTP_FAILED (@"CyREST layout '$clean_layout' returned HTTP $(lmsg.status_code)");
                }
            } catch (GLib.Error le) {
                if (le is CyRestError) throw (CyRestError) le;
                throw new CyRestError.HTTP_FAILED (@"Failed to apply layout '$clean_layout': $(le.message)");
            }

            return suid;
        }

        private int64 extract_suid_from_response (GLib.Bytes bytes) throws CyRestError {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (bytes_to_utf8 (bytes), -1);
                var root = parser.get_root ();
                if (root == null) throw new CyRestError.PARSE_ERROR ("Empty CyREST network response");

                if (root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("networkSUID")) return obj.get_int_member ("networkSUID");
                    if (obj.has_member ("data") && obj.get_member ("data").get_node_type () == Json.NodeType.ARRAY) {
                        var darr = obj.get_array_member ("data");
                        if (darr.get_length () > 0 && darr.get_object_element (0).has_member ("networkSUID")) {
                            return darr.get_object_element (0).get_int_member ("networkSUID");
                        }
                    }
                } else if (root.get_node_type () == Json.NodeType.ARRAY) {
                    var arr = root.get_array ();
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var el = arr.get_element (i);
                        if (el.get_node_type () == Json.NodeType.OBJECT && el.get_object ().has_member ("networkSUID")) {
                            return el.get_object ().get_int_member ("networkSUID");
                        }
                    }
                }
            } catch (GLib.Error e) {
                throw new CyRestError.PARSE_ERROR (e.message);
            }
            throw new CyRestError.PARSE_ERROR ("Missing networkSUID in CyREST response");
        }

        public static string build_nord_visual_style_json () {
            return """[
  {
    "title": "Imladris-Nord",
    "defaults": [
      { "visualProperty": "NETWORK_BACKGROUND_PAINT", "value": "#2E3440" },
      { "visualProperty": "NODE_FILL_COLOR", "value": "#88C0D0" },
      { "visualProperty": "NODE_LABEL_COLOR", "value": "#ECEFF4" },
      { "visualProperty": "NODE_BORDER_PAINT", "value": "#D8DEE9" },
      { "visualProperty": "NODE_BORDER_WIDTH", "value": 2.0 },
      { "visualProperty": "NODE_SHAPE", "value": "ELLIPSE" },
      { "visualProperty": "EDGE_STROKE_UNSELECTED_PAINT", "value": "#81A1C1" },
      { "visualProperty": "EDGE_WIDTH", "value": 2.0 }
    ],
    "mappings": [
      {
        "mappingType": "passthrough",
        "mappingColumn": "label",
        "mappingColumnType": "String",
        "visualProperty": "NODE_LABEL"
      },
      {
        "mappingType": "passthrough",
        "mappingColumn": "color",
        "mappingColumnType": "String",
        "visualProperty": "NODE_FILL_COLOR"
      },
      {
        "mappingType": "continuous",
        "mappingColumn": "groundedness",
        "mappingColumnType": "Integer",
        "visualProperty": "NODE_SIZE",
        "points": [
          { "value": 1, "lesser": 28.0, "equal": 28.0, "greater": 28.0 },
          { "value": 20, "lesser": 68.0, "equal": 68.0, "greater": 68.0 }
        ]
      },
      {
        "mappingType": "discrete",
        "mappingColumn": "sdv_verified",
        "mappingColumnType": "Boolean",
        "visualProperty": "NODE_BORDER_WIDTH",
        "map": [
          { "key": "true", "value": 4.0 },
          { "key": "false", "value": 1.5 }
        ]
      },
      {
        "mappingType": "continuous",
        "mappingColumn": "weight",
        "mappingColumnType": "Double",
        "visualProperty": "EDGE_WIDTH",
        "points": [
          { "value": 1.0, "lesser": 1.5, "equal": 1.5, "greater": 1.5 },
          { "value": 10.0, "lesser": 7.0, "equal": 7.0, "greater": 7.0 }
        ]
      }
    ]
  }
]""";
        }

        public async void apply_nord_style_async (int64 suid) throws CyRestError {
            string style_json = build_nord_visual_style_json ();
            var post_msg = new Soup.Message ("POST", @"$(base_url ())/styles");
            post_msg.set_request_body_from_bytes ("application/json", new GLib.Bytes (style_json.data));
            try {
                yield session.send_and_read_async (post_msg, GLib.Priority.DEFAULT, null);
                // HTTP 200/201 created or 409 if style already exists in Cytoscape session
                if ((post_msg.status_code < 200 || post_msg.status_code >= 300) && post_msg.status_code != 409) {
                    throw new CyRestError.HTTP_FAILED (@"CyREST POST /styles returned HTTP $(post_msg.status_code)");
                }
                var apply_msg = new Soup.Message ("GET", @"$(base_url ())/apply/styles/Imladris-Nord/$suid");
                yield session.send_and_read_async (apply_msg, GLib.Priority.DEFAULT, null);
                if (apply_msg.status_code < 200 || apply_msg.status_code >= 300) {
                    throw new CyRestError.HTTP_FAILED (@"CyREST GET /apply/styles returned HTTP $(apply_msg.status_code)");
                }
            } catch (GLib.Error e) {
                if (e is CyRestError) throw (CyRestError) e;
                throw new CyRestError.HTTP_FAILED (@"Failed to apply Nord visual style: $(e.message)");
            }
        }

        /**
         * Queries GET /v1/networks/{suid}/nodes?selected=true (and maps SUIDs via defaultnode table
         * if numeric SUIDs are returned) to retrieve selected node identifiers.
         */
        public async Gee.ArrayList<string> pull_selected_nodes_async (int64 suid = -1) throws CyRestError {
            int64 target_suid = suid > 0 ? suid : last_network_suid;
            if (target_suid <= 0) {
                throw new CyRestError.HTTP_FAILED ("No active Cytoscape network SUID.");
            }

            var selected_names = new Gee.ArrayList<string> ();
            var msg = new Soup.Message ("GET", @"$(base_url ())/networks/$target_suid/nodes?selected=true");
            msg.request_headers.append ("Accept", "application/json");

            GLib.Bytes? bytes = null;
            try {
                bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
            } catch (GLib.Error e) {
                throw new CyRestError.OFFLINE (e.message);
            }
            if (msg.status_code < 200 || msg.status_code >= 300 || bytes == null) {
                throw new CyRestError.HTTP_FAILED (@"GET selected nodes failed with HTTP $(msg.status_code)");
            }

            var selected_suids = new Gee.HashSet<string> ();
            try {
                var p = new Json.Parser ();
                p.load_from_data (bytes_to_utf8 (bytes), -1);
                var root = p.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.ARRAY) {
                    var arr = root.get_array ();
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var el = arr.get_element (i);
                        if (el.get_value_type () == typeof (string)) {
                            selected_names.add (el.get_string ());
                        } else if (el.get_value_type () == typeof (int64)) {
                            selected_suids.add (el.get_int ().to_string ());
                        } else if (el.get_node_type () == Json.NodeType.OBJECT) {
                            var o = el.get_object ();
                            if (o.has_member ("name")) selected_names.add (o.get_string_member ("name"));
                            else if (o.has_member ("SUID")) selected_suids.add (o.get_int_member ("SUID").to_string ());
                        }
                    }
                }
            } catch (GLib.Error pe) {
                throw new CyRestError.PARSE_ERROR (pe.message);
            }

            if (selected_suids.size > 0) {
                var tmsg = new Soup.Message ("GET", @"$(base_url ())/networks/$target_suid/tables/defaultnode/rows");
                try {
                    var tbytes = yield session.send_and_read_async (tmsg, GLib.Priority.DEFAULT, null);
                    if (tmsg.status_code == 200 && tbytes != null) {
                        var tp = new Json.Parser ();
                        tp.load_from_data (bytes_to_utf8 (tbytes), -1);
                        if (tp.get_root () != null && tp.get_root ().get_node_type () == Json.NodeType.ARRAY) {
                            var rows = tp.get_root ().get_array ();
                            for (uint i = 0; i < rows.get_length (); i++) {
                                var r = rows.get_object_element (i);
                                if (r.has_member ("SUID") && r.has_member ("name")) {
                                    int64 r_suid = r.get_int_member ("SUID");
                                    if (selected_suids.contains (r_suid.to_string ())) {
                                        selected_names.add (r.get_string_member ("name"));
                                    }
                                }
                            }
                        }
                    }
                } catch (GLib.Error te) {}
            }

            return selected_names;
        }

        /**
         * Exports first network view from Cytoscape as SVG or PNG, saves to dest_path,
         * and returns a captioned Quarto Markdown figure block.
         */
        public async string export_figure_to_quarto_async (
            int64 suid,
            string dest_path,
            string relative_md_path,
            string ext = "svg",
            string caption = "Qualitative Entity–Code–Evidence Network"
        ) throws CyRestError {
            int64 target_suid = suid > 0 ? suid : last_network_suid;
            if (target_suid <= 0) {
                throw new CyRestError.HTTP_FAILED ("No active Cytoscape network SUID.");
            }
            string fmt = (ext.down () == "png") ? "png" : "svg";
            var msg = new Soup.Message ("GET", @"$(base_url ())/networks/$target_suid/views/first.$fmt");
            try {
                var bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
                if (msg.status_code < 200 || msg.status_code >= 300 || bytes == null) {
                    throw new CyRestError.HTTP_FAILED (@"CyREST image export returned HTTP $(msg.status_code)");
                }
                string parent = GLib.Path.get_dirname (dest_path);
                if (parent != "" && parent != ".") GLib.DirUtils.create_with_parents (parent, 0755);
                GLib.FileUtils.set_data (dest_path, bytes.get_data ());
            } catch (GLib.Error e) {
                if (e is CyRestError) throw (CyRestError) e;
                throw new CyRestError.OFFLINE (e.message);
            }

            return @"\n![$caption (Cytoscape SUID $target_suid)]($relative_md_path){#fig-qual-network-$target_suid}\n";
        }
    }
}
