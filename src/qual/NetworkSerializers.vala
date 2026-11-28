// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Json;

namespace Imladris.Qual {

    /**
     * Lossless Cytoscape Exchange 2.0 (CX2, NDEx-compatible) Serializer & Parser.
     */
    public class Cx2Serializer : GLib.Object {

        public static string serialize (QualGraph g) {
            var b = new Json.Builder ();
            b.begin_array ();

            // 1. Pre-amble CXVersion
            b.begin_object ();
            b.set_member_name ("CXVersion"); b.add_string_value ("2.0");
            b.set_member_name ("hasFragments"); b.add_boolean_value (false);
            b.end_object ();

            // 2. Attribute Declarations
            b.begin_object ();
            b.set_member_name ("attributeDeclarations");
            b.begin_array ();
            b.begin_object ();

            b.set_member_name ("networkAttributes");
            b.begin_object ();
            add_type_decl (b, "name", "string");
            add_type_decl (b, "domain", "string");
            b.end_object ();

            b.set_member_name ("nodes");
            b.begin_object ();
            add_type_decl (b, "name", "string");
            add_type_decl (b, "label", "string");
            add_type_decl (b, "node_type", "string");
            add_type_decl (b, "domain_category", "string");
            add_type_decl (b, "color", "string");
            add_type_decl (b, "groundedness", "integer");
            add_type_decl (b, "density", "integer");
            add_type_decl (b, "sdv_verified", "boolean");
            b.end_object ();

            b.set_member_name ("edges");
            b.begin_object ();
            add_type_decl (b, "interaction", "string");
            add_type_decl (b, "weight", "double");
            add_type_decl (b, "evidence_span_id", "string");
            b.end_object ();

            b.end_object ();
            b.end_array ();
            b.end_object ();

            // 3. Network Attributes
            b.begin_object ();
            b.set_member_name ("networkAttributes");
            b.begin_array ();
            b.begin_object ();
            b.set_member_name ("name"); b.add_string_value (g.name);
            b.set_member_name ("domain"); b.add_string_value (g.domain);
            b.end_object ();
            b.end_array ();
            b.end_object ();

            // 4. Nodes Aspect
            b.begin_object ();
            b.set_member_name ("nodes");
            b.begin_array ();
            foreach (var n in g.nodes) {
                b.begin_object ();
                b.set_member_name ("id"); b.add_int_value (n.int_id);
                b.set_member_name ("x"); b.add_double_value (n.x);
                b.set_member_name ("y"); b.add_double_value (n.y);
                b.set_member_name ("v");
                b.begin_object ();
                b.set_member_name ("name"); b.add_string_value (n.id);
                b.set_member_name ("label"); b.add_string_value (n.label);
                b.set_member_name ("node_type"); b.add_string_value (n.node_type);
                b.set_member_name ("domain_category"); b.add_string_value (n.domain_category);
                b.set_member_name ("color"); b.add_string_value (n.color_hex);
                b.set_member_name ("groundedness"); b.add_int_value (n.groundedness);
                b.set_member_name ("density"); b.add_int_value (n.density);
                b.set_member_name ("sdv_verified"); b.add_boolean_value (n.sdv_verified);
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();

            // 5. Edges Aspect
            b.begin_object ();
            b.set_member_name ("edges");
            b.begin_array ();
            foreach (var e in g.edges) {
                b.begin_object ();
                b.set_member_name ("id"); b.add_int_value (e.int_id);
                b.set_member_name ("s"); b.add_int_value (e.source_int);
                b.set_member_name ("t"); b.add_int_value (e.target_int);
                b.set_member_name ("v");
                b.begin_object ();
                b.set_member_name ("interaction"); b.add_string_value (e.interaction);
                b.set_member_name ("weight"); b.add_double_value (e.weight);
                if (e.evidence_span_id != null && e.evidence_span_id != "") {
                    b.set_member_name ("evidence_span_id");
                    b.add_string_value (e.evidence_span_id);
                }
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();

            // 6. Status Aspect
            b.begin_object ();
            b.set_member_name ("status");
            b.begin_array ();
            b.begin_object ();
            b.set_member_name ("error"); b.add_string_value ("");
            b.set_member_name ("success"); b.add_boolean_value (true);
            b.end_object ();
            b.end_array ();
            b.end_object ();

            b.end_array ();

            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        private static void add_type_decl (Json.Builder b, string attr_name, string dtype) {
            b.set_member_name (attr_name);
            b.begin_object ();
            b.set_member_name ("d");
            b.add_string_value (dtype);
            b.end_object ();
        }

        public static QualGraph deserialize (string cx2_json) throws GLib.Error {
            var g = new QualGraph ();
            var parser = new Json.Parser ();
            parser.load_from_data (cx2_json, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                throw new GLib.IOError.INVALID_DATA ("CX2 root must be a JSON array of aspects.");
            }

            var int_to_str_id = new Gee.HashMap<int, string> ();
            var arr = root.get_array ();
            for (uint i = 0; i < arr.get_length (); i++) {
                var elem = arr.get_element (i);
                if (elem.get_node_type () != Json.NodeType.OBJECT) continue;
                var obj = elem.get_object ();

                if (obj.has_member ("networkAttributes")) {
                    var na = obj.get_array_member ("networkAttributes");
                    if (na.get_length () > 0) {
                        var n0 = na.get_object_element (0);
                        if (n0.has_member ("name")) g.name = n0.get_string_member ("name");
                        if (n0.has_member ("domain")) g.domain = n0.get_string_member ("domain");
                    }
                } else if (obj.has_member ("nodes")) {
                    var narr = obj.get_array_member ("nodes");
                    for (uint j = 0; j < narr.get_length (); j++) {
                        var no = narr.get_object_element (j);
                        int iid = no.has_member ("id") ? (int) no.get_int_member ("id") : (int) (j + 1);
                        double x = no.has_member ("x") ? no.get_double_member ("x") : 0.0;
                        double y = no.has_member ("y") ? no.get_double_member ("y") : 0.0;
                        string nid = @"n-$iid";
                        string lbl = nid;
                        string ntype = "code";
                        string dcat = "general";
                        string col = "#88C0D0";
                        int grnd = 1;
                        int dens = 0;
                        bool sdv = true;
                        if (no.has_member ("v")) {
                            var v = no.get_object_member ("v");
                            if (v.has_member ("name")) nid = v.get_string_member ("name");
                            if (v.has_member ("label")) lbl = v.get_string_member ("label");
                            if (v.has_member ("node_type")) ntype = v.get_string_member ("node_type");
                            if (v.has_member ("domain_category")) dcat = v.get_string_member ("domain_category");
                            if (v.has_member ("color")) col = v.get_string_member ("color");
                            if (v.has_member ("groundedness")) grnd = (int) v.get_int_member ("groundedness");
                            if (v.has_member ("density")) dens = (int) v.get_int_member ("density");
                            if (v.has_member ("sdv_verified")) sdv = v.get_boolean_member ("sdv_verified");
                        }
                        var node = g.ensure_node (nid, lbl, ntype, col, dcat);
                        node.int_id = iid;
                        node.x = x;
                        node.y = y;
                        node.groundedness = grnd;
                        node.density = dens;
                        node.sdv_verified = sdv;
                        int_to_str_id.set (iid, nid);
                    }
                } else if (obj.has_member ("edges")) {
                    var earr = obj.get_array_member ("edges");
                    for (uint j = 0; j < earr.get_length (); j++) {
                        var eo = earr.get_object_element (j);
                        int s_int = (int) eo.get_int_member ("s");
                        int t_int = (int) eo.get_int_member ("t");
                        string? s_id = int_to_str_id.get (s_int);
                        string? t_id = int_to_str_id.get (t_int);
                        if (s_id == null || t_id == null) continue;
                        string inter = "co_occurs";
                        double w = 1.0;
                        string? sp_id = null;
                        if (eo.has_member ("v")) {
                            var v = eo.get_object_member ("v");
                            if (v.has_member ("interaction")) inter = v.get_string_member ("interaction");
                            if (v.has_member ("weight")) w = v.get_double_member ("weight");
                            if (v.has_member ("evidence_span_id")) sp_id = v.get_string_member ("evidence_span_id");
                        }
                        var edge = new QualGraphEdge () {
                            int_id = eo.has_member ("id") ? (int) eo.get_int_member ("id") : (int) (g.edges.size + 1),
                            id = @"e-$(g.edges.size + 1)",
                            source_int = s_int,
                            target_int = t_int,
                            source_id = s_id,
                            target_id = t_id,
                            interaction = inter,
                            weight = w,
                            evidence_span_id = sp_id
                        };
                        g.edges.add (edge);
                    }
                }
            }
            return g;
        }
    }

    /**
     * Lossless GraphML (XML) Serializer & Parser for archival and offline exchange.
     */
    public class GraphMlSerializer : GLib.Object {

        public static string serialize (QualGraph g) {
            var sb = new GLib.StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\">\n");
            sb.append ("  <key id=\"g_domain\" for=\"graph\" attr.name=\"domain\" attr.type=\"string\"/>\n");
            sb.append ("  <key id=\"d_label\" for=\"node\" attr.name=\"label\" attr.type=\"string\"/>\n");
            sb.append ("  <key id=\"d_type\" for=\"node\" attr.name=\"node_type\" attr.type=\"string\"/>\n");
            sb.append ("  <key id=\"d_domain\" for=\"node\" attr.name=\"domain_category\" attr.type=\"string\"/>\n");
            sb.append ("  <key id=\"d_color\" for=\"node\" attr.name=\"color\" attr.type=\"string\"/>\n");
            sb.append ("  <key id=\"d_grounded\" for=\"node\" attr.name=\"groundedness\" attr.type=\"int\"/>\n");
            sb.append ("  <key id=\"d_density\" for=\"node\" attr.name=\"density\" attr.type=\"int\"/>\n");
            sb.append ("  <key id=\"d_sdv\" for=\"node\" attr.name=\"sdv_verified\" attr.type=\"boolean\"/>\n");
            sb.append ("  <key id=\"d_x\" for=\"node\" attr.name=\"x\" attr.type=\"double\"/>\n");
            sb.append ("  <key id=\"d_y\" for=\"node\" attr.name=\"y\" attr.type=\"double\"/>\n");
            sb.append ("  <key id=\"e_inter\" for=\"edge\" attr.name=\"interaction\" attr.type=\"string\"/>\n");
            sb.append ("  <key id=\"e_weight\" for=\"edge\" attr.name=\"weight\" attr.type=\"double\"/>\n");
            sb.append ("  <key id=\"e_span\" for=\"edge\" attr.name=\"evidence_span_id\" attr.type=\"string\"/>\n");
            sb.append_printf ("  <graph id=\"%s\" edgedefault=\"directed\">\n", GLib.Markup.escape_text (g.name));
            sb.append_printf ("    <data key=\"g_domain\">%s</data>\n", GLib.Markup.escape_text (g.domain));

            foreach (var n in g.nodes) {
                sb.append_printf ("    <node id=\"%s\">\n", GLib.Markup.escape_text (n.id));
                sb.append_printf ("      <data key=\"d_label\">%s</data>\n", GLib.Markup.escape_text (n.label));
                sb.append_printf ("      <data key=\"d_type\">%s</data>\n", GLib.Markup.escape_text (n.node_type));
                sb.append_printf ("      <data key=\"d_domain\">%s</data>\n", GLib.Markup.escape_text (n.domain_category));
                sb.append_printf ("      <data key=\"d_color\">%s</data>\n", GLib.Markup.escape_text (n.color_hex));
                sb.append_printf ("      <data key=\"d_grounded\">%d</data>\n", n.groundedness);
                sb.append_printf ("      <data key=\"d_density\">%d</data>\n", n.density);
                sb.append_printf ("      <data key=\"d_sdv\">%s</data>\n", n.sdv_verified ? "true" : "false");
                sb.append_printf ("      <data key=\"d_x\">%.4f</data>\n", n.x);
                sb.append_printf ("      <data key=\"d_y\">%.4f</data>\n", n.y);
                sb.append ("    </node>\n");
            }

            foreach (var e in g.edges) {
                sb.append_printf (
                    "    <edge id=\"%s\" source=\"%s\" target=\"%s\">\n",
                    GLib.Markup.escape_text (e.id),
                    GLib.Markup.escape_text (e.source_id),
                    GLib.Markup.escape_text (e.target_id)
                );
                sb.append_printf ("      <data key=\"e_inter\">%s</data>\n", GLib.Markup.escape_text (e.interaction));
                sb.append_printf ("      <data key=\"e_weight\">%.4f</data>\n", e.weight);
                if (e.evidence_span_id != null && e.evidence_span_id != "") {
                    sb.append_printf ("      <data key=\"e_span\">%s</data>\n", GLib.Markup.escape_text (e.evidence_span_id));
                }
                sb.append ("    </edge>\n");
            }

            sb.append ("  </graph>\n</graphml>\n");
            return sb.str;
        }

        public static QualGraph deserialize (string xml_text) throws GLib.Error {
            var g = new QualGraph ();
            if (!xml_text.contains ("<graphml")) {
                throw new GLib.IOError.INVALID_DATA ("Invalid GraphML document: missing <graphml> root.");
            }

            string g_id = extract_xml_attr (xml_text, "<graph ", "id");
            if (g_id != "") g.name = unescape_xml (g_id);
            int g_dom_idx = xml_text.index_of ("<data key=\"g_domain\">");
            if (g_dom_idx < 0) g_dom_idx = xml_text.index_of ("<data key='g_domain'>");
            if (g_dom_idx >= 0) {
                int gd_s = xml_text.index_of_char ('>', g_dom_idx) + 1;
                int gd_e = xml_text.index_of ("</data>", gd_s);
                if (gd_s > 0 && gd_e >= gd_s) {
                    g.domain = unescape_xml (xml_text.substring (gd_s, gd_e - gd_s).strip ());
                }
            }

            int pos = 0;
            while (true) {
                int n_start = xml_text.index_of ("<node ", pos);
                if (n_start < 0) break;
                int gt = xml_text.index_of_char ('>', n_start);
                if (gt < 0) break;
                bool self_closing = (gt > n_start && xml_text[gt - 1] == '/');
                int n_end = self_closing ? gt : xml_text.index_of ("</node>", gt);
                if (n_end < 0) break;
                int block_len = self_closing ? (gt - n_start + 1) : (n_end - n_start + 7);
                string block = xml_text.substring (n_start, block_len);
                string nid = unescape_xml (extract_xml_attr (block, "<node ", "id"));
                if (nid != "") {
                    var nd = g.ensure_node (nid, nid, "code");
                    if (!self_closing) apply_data_fields_to_node (block, nd);
                }
                pos = n_start + block_len;
            }

            pos = 0;
            while (true) {
                int e_start = xml_text.index_of ("<edge ", pos);
                if (e_start < 0) break;
                int gt = xml_text.index_of_char ('>', e_start);
                if (gt < 0) break;
                bool self_closing = (gt > e_start && xml_text[gt - 1] == '/');
                int e_end = self_closing ? gt : xml_text.index_of ("</edge>", gt);
                if (e_end < 0) break;
                int block_len = self_closing ? (gt - e_start + 1) : (e_end - e_start + 7);
                string block = xml_text.substring (e_start, block_len);
                string eid = unescape_xml (extract_xml_attr (block, "<edge ", "id"));
                string src = unescape_xml (extract_xml_attr (block, "<edge ", "source"));
                string dst = unescape_xml (extract_xml_attr (block, "<edge ", "target"));
                if (src != "" && dst != "") {
                    var sn = g.ensure_node (src, src, "code");
                    var tn = g.ensure_node (dst, dst, "code");
                    var edge = new QualGraphEdge () {
                        int_id = g.edges.size + 1,
                        id = eid != "" ? eid : @"e-$(g.edges.size + 1)",
                        source_int = sn.int_id,
                        target_int = tn.int_id,
                        source_id = src,
                        target_id = dst
                    };
                    if (!self_closing) apply_data_fields_to_edge (block, edge);
                    g.edges.add (edge);
                }
                pos = e_start + block_len;
            }
            return g;
        }

        private static string extract_xml_attr (string text, string tag_prefix, string attr_name) {
            int t = text.index_of (tag_prefix);
            if (t < 0) return "";
            int gt = text.index_of_char ('>', t);
            if (gt < 0) return "";
            string header = text.substring (t, gt - t);
            char[] quotes = { '"', '\'' };
            foreach (char q in quotes) {
                string needle = attr_name + "=" + q.to_string ();
                int a = header.index_of (needle);
                if (a >= 0) {
                    int vs = a + needle.length;
                    int ve = header.index_of_char (q, vs);
                    if (ve >= vs) return header.substring (vs, ve - vs);
                }
            }
            return "";
        }

        private static void apply_data_fields_to_node (string block, QualGraphNode nd) {
            int p = 0;
            while (true) {
                int ds = block.index_of ("<data ", p);
                if (ds < 0) break;
                int gt = block.index_of_char ('>', ds);
                int de = block.index_of ("</data>", ds);
                if (gt < 0 || de < 0 || de < gt) break;
                string key = extract_xml_attr (block.substring (ds, gt - ds + 1), "<data ", "key");
                string val = unescape_xml (block.substring (gt + 1, de - gt - 1).strip ());
                switch (key) {
                    case "d_label": nd.label = val; break;
                    case "d_type": nd.node_type = val; break;
                    case "d_domain": nd.domain_category = val; break;
                    case "d_color": nd.color_hex = val; break;
                    case "d_grounded": nd.groundedness = int.parse (val); break;
                    case "d_density": nd.density = int.parse (val); break;
                    case "d_sdv": nd.sdv_verified = (val == "true" || val == "1"); break;
                    case "d_x": nd.x = double.parse (val); break;
                    case "d_y": nd.y = double.parse (val); break;
                }
                p = de + 7;
            }
        }

        private static void apply_data_fields_to_edge (string block, QualGraphEdge ed) {
            int p = 0;
            while (true) {
                int ds = block.index_of ("<data ", p);
                if (ds < 0) break;
                int gt = block.index_of_char ('>', ds);
                int de = block.index_of ("</data>", ds);
                if (gt < 0 || de < 0 || de < gt) break;
                string key = extract_xml_attr (block.substring (ds, gt - ds + 1), "<data ", "key");
                string val = unescape_xml (block.substring (gt + 1, de - gt - 1).strip ());
                switch (key) {
                    case "e_inter": ed.interaction = val; break;
                    case "e_weight": ed.weight = double.parse (val); break;
                    case "e_span": ed.evidence_span_id = val != "" ? val : null; break;
                }
                p = de + 7;
            }
        }

        private static string unescape_xml (string s) {
            return s
                .replace ("&quot;", "\"")
                .replace ("&apos;", "'")
                .replace ("&lt;", "<")
                .replace ("&gt;", ">")
                .replace ("&amp;", "&");
        }
    }
}
