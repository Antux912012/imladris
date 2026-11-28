// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Qual {

    public enum GraphLayoutMode {
        FORCE_DIRECTED,
        HIERARCHICAL
    }

    public class QualGraphNode : GLib.Object {
        public int int_id { get; set; default = 0; }
        public string id { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public string node_type { get; set; default = "code"; } // entity, code, document
        public string domain_category { get; set; default = "general"; }
        public string color_hex { get; set; default = "#88C0D0"; }
        public int groundedness { get; set; default = 1; }
        public int density { get; set; default = 0; }
        public bool sdv_verified { get; set; default = true; }
        public double x { get; set; default = 0.0; }
        public double y { get; set; default = 0.0; }
    }

    public class QualGraphEdge : GLib.Object {
        public int int_id { get; set; default = 0; }
        public string id { get; set; default = ""; }
        public int source_int { get; set; default = 0; }
        public int target_int { get; set; default = 0; }
        public string source_id { get; set; default = ""; }
        public string target_id { get; set; default = ""; }
        public string interaction { get; set; default = "co_occurs"; }
        public double weight { get; set; default = 1.0; }
        public string? evidence_span_id { get; set; default = null; }
    }

    public class QualGraph : GLib.Object {
        public string name { get; set; default = "Imladris Qualitative Network"; }
        public string domain { get; set; default = "general"; }
        public Gee.ArrayList<QualGraphNode> nodes { get; owned set; }
        public Gee.ArrayList<QualGraphEdge> edges { get; owned set; }
        public Gee.HashMap<string, QualGraphNode> node_by_id { get; owned set; }

        public QualGraph () {
            nodes = new Gee.ArrayList<QualGraphNode> ();
            edges = new Gee.ArrayList<QualGraphEdge> ();
            node_by_id = new Gee.HashMap<string, QualGraphNode> ();
        }

        public QualGraphNode ensure_node (
            string id,
            string label,
            string node_type,
            string color_hex = "#88C0D0",
            string domain_cat = "general"
        ) {
            var existing = node_by_id.get (id);
            if (existing != null) return existing;

            var n = new QualGraphNode () {
                int_id = nodes.size + 1,
                id = id,
                label = label != "" ? label : id,
                node_type = node_type,
                domain_category = domain_cat,
                color_hex = color_hex != "" ? color_hex : "#88C0D0"
            };
            nodes.add (n);
            node_by_id.set (id, n);
            return n;
        }

        public void add_or_accumulate_edge (
            string src_id,
            string dst_id,
            string interaction,
            double weight = 1.0,
            string? span_id = null
        ) {
            var src = node_by_id.get (src_id);
            var dst = node_by_id.get (dst_id);
            if (src == null || dst == null || src_id == dst_id) return;

            foreach (var e in edges) {
                if (e.source_id == src_id && e.target_id == dst_id && e.interaction == interaction) {
                    e.weight += weight;
                    return;
                }
            }

            var edge = new QualGraphEdge () {
                int_id = edges.size + 1,
                id = @"e-$(edges.size + 1)",
                source_int = src.int_id,
                target_int = dst.int_id,
                source_id = src_id,
                target_id = dst_id,
                interaction = interaction,
                weight = weight,
                evidence_span_id = span_id
            };
            edges.add (edge);
            src.density++;
            dst.density++;
        }
    }

    /**
     * Builds Entity-Code-Document qualitative graphs from .imladris-qual.db
     * and computes deterministic Force-Directed and Hierarchical layouts.
     */
    public class NetworkBuilder : GLib.Object {

        public static QualGraph build_from_workspace (
            QualWorkspaceService svc,
            GraphLayoutMode layout_mode = GraphLayoutMode.FORCE_DIRECTED,
            Gee.HashMap<string, string>? open_doc_buffers = null
        ) {
            var g = new QualGraph ();
            if (svc.active_profile != null) {
                g.name = svc.active_profile.name + " Network";
                g.domain = svc.active_profile.domain_slug;
            }

            string? vis_coder = svc.blinded_mode ? svc.current_coder : null;
            var spans = svc.db != null ? svc.db.list_spans (null, vis_coder) : new Gee.ArrayList<QualSpan> ();
            var grounded = svc.db != null ? svc.db.get_groundedness_counts (vis_coder) : new Gee.HashMap<string, int> ();

            var doc_Unit_codes = new Gee.HashMap<string, Gee.ArrayList<string>> ();

            foreach (var sp in spans) {
                if (sp.code_id == "") continue;
                var cdef = svc.active_profile != null ? svc.active_profile.find_code (sp.code_id) : null;
                string c_label = cdef != null ? cdef.label : sp.code_id;
                string c_color = cdef != null && cdef.color != "" ? cdef.color : "#88C0D0";

                var code_node = g.ensure_node (sp.code_id, c_label, "code", c_color, sp.domain);
                code_node.groundedness = grounded.has_key (sp.code_id) ? grounded.get (sp.code_id) : int.max (1, code_node.groundedness);

                if (open_doc_buffers != null && open_doc_buffers.has_key (sp.file_path)) {
                    if (QualSpanParser.verify_span_sdv (sp, open_doc_buffers.get (sp.file_path)) == SdvStatus.MODIFIED) {
                        code_node.sdv_verified = false;
                    }
                }

                if (sp.entity_id != null && sp.entity_id != "") {
                    var ent_node = g.ensure_node (sp.entity_id, sp.entity_id, "entity", "#A3BE8C", sp.domain);
                    ent_node.groundedness++;
                    g.add_or_accumulate_edge (sp.entity_id, sp.code_id, "tagged_with", 1.0, sp.span_id);
                }

                if (sp.file_path != "") {
                    string doc_base = GLib.Path.get_basename (sp.file_path);
                    var doc_node = g.ensure_node (doc_base, doc_base, "document", "#EBCB8B", sp.domain);
                    doc_node.groundedness++;
                    g.add_or_accumulate_edge (sp.code_id, doc_base, "appears_in", 1.0, sp.span_id);

                    string ukey = @"$(sp.file_path)::$(sp.line_start / 6)";
                    var ulist = doc_Unit_codes.get (ukey);
                    if (ulist == null) {
                        ulist = new Gee.ArrayList<string> ();
                        doc_Unit_codes.set (ukey, ulist);
                    }
                    if (!ulist.contains (sp.code_id)) {
                        ulist.add (sp.code_id);
                    }
                }
            }

            // Add co-occurrence edges between codes appearing in the same block
            foreach (var ulist in doc_Unit_codes.values) {
                for (int i = 0; i < ulist.size; i++) {
                    for (int j = i + 1; j < ulist.size; j++) {
                        string a = ulist[i];
                        string b = ulist[j];
                        if (strcmp (a, b) < 0) g.add_or_accumulate_edge (a, b, "co_occurs", 1.0, null);
                        else g.add_or_accumulate_edge (b, a, "co_occurs", 1.0, null);
                    }
                }
            }

            // Overlay explicit edges from network_edges SQLite table
            if (svc.db != null) {
                foreach (var ex in svc.db.list_edges ()) {
                    if (!g.node_by_id.has_key (ex.source_node)) {
                        g.ensure_node (ex.source_node, ex.source_node, "entity", "#A3BE8C", g.domain);
                    }
                    if (!g.node_by_id.has_key (ex.target_node)) {
                        g.ensure_node (ex.target_node, ex.target_node, "code", "#88C0D0", g.domain);
                    }
                    g.add_or_accumulate_edge (ex.source_node, ex.target_node, ex.relation_type, ex.weight, ex.evidence_span_id);
                }
            }

            apply_layout (g, layout_mode);
            return g;
        }

        public static void apply_layout (QualGraph g, GraphLayoutMode mode, double width = 760.0, double height = 480.0) {
            int n = g.nodes.size;
            if (n == 0) return;

            if (mode == GraphLayoutMode.HIERARCHICAL) {
                var entities = new Gee.ArrayList<QualGraphNode> ();
                var codes = new Gee.ArrayList<QualGraphNode> ();
                var docs = new Gee.ArrayList<QualGraphNode> ();
                foreach (var nd in g.nodes) {
                    if (nd.node_type == "entity") entities.add (nd);
                    else if (nd.node_type == "document") docs.add (nd);
                    else codes.add (nd);
                }
                place_layer (entities, width, 90.0);
                place_layer (codes, width, height / 2.0);
                place_layer (docs, width, height - 90.0);
                return;
            }

            // Deterministic circular seed followed by Fruchterman-Reingold iterations
            double cx = width / 2.0;
            double cy = height / 2.0;
            double radius = double.min (width, height) * 0.34;
            for (int i = 0; i < n; i++) {
                double angle = (2.0 * GLib.Math.PI * i) / double.max (1.0, n);
                g.nodes[i].x = cx + radius * GLib.Math.cos (angle);
                g.nodes[i].y = cy + radius * GLib.Math.sin (angle);
            }
            if (n == 1) {
                g.nodes[0].x = cx;
                g.nodes[0].y = cy;
                return;
            }

            double area = width * height;
            double k = GLib.Math.sqrt (area / (double) n) * 0.65;
            double temp = width * 0.12;
            double[] dx = new double[n];
            double[] dy = new double[n];

            for (int iter = 0; iter < 45; iter++) {
                for (int i = 0; i < n; i++) { dx[i] = 0.0; dy[i] = 0.0; }

                for (int i = 0; i < n; i++) {
                    for (int j = i + 1; j < n; j++) {
                        double vx = g.nodes[i].x - g.nodes[j].x;
                        double vy = g.nodes[i].y - g.nodes[j].y;
                        double dist = double.max (1.0, GLib.Math.sqrt (vx * vx + vy * vy));
                        double rep = (k * k) / dist;
                        double rx = (vx / dist) * rep;
                        double ry = (vy / dist) * rep;
                        dx[i] += rx; dy[i] += ry;
                        dx[j] -= rx; dy[j] -= ry;
                    }
                }

                foreach (var e in g.edges) {
                    int si = e.source_int - 1;
                    int ti = e.target_int - 1;
                    if (si < 0 || si >= n || ti < 0 || ti >= n) continue;
                    double vx = g.nodes[si].x - g.nodes[ti].x;
                    double vy = g.nodes[si].y - g.nodes[ti].y;
                    double dist = double.max (1.0, GLib.Math.sqrt (vx * vx + vy * vy));
                    double attr = (dist * dist) / k;
                    double ax = (vx / dist) * attr;
                    double ay = (vy / dist) * attr;
                    dx[si] -= ax; dy[si] -= ay;
                    dx[ti] += ax; dy[ti] += ay;
                }

                for (int i = 0; i < n; i++) {
                    double disp = double.max (1.0, GLib.Math.sqrt (dx[i] * dx[i] + dy[i] * dy[i]));
                    double step = double.min (disp, temp);
                    g.nodes[i].x = (g.nodes[i].x + (dx[i] / disp) * step).clamp (60.0, width - 60.0);
                    g.nodes[i].y = (g.nodes[i].y + (dy[i] / disp) * step).clamp (50.0, height - 50.0);
                }
                temp *= 0.92;
            }
        }

        private static void place_layer (Gee.ArrayList<QualGraphNode> layer, double width, double y) {
            int m = layer.size;
            if (m == 0) return;
            for (int i = 0; i < m; i++) {
                layer[i].x = ((double) (i + 1) / (double) (m + 1)) * width;
                layer[i].y = y;
            }
        }

        /**
         * Exports a publication-grade Nord-styled vector SVG directly from QualGraph.
         */
        public static string export_svg (QualGraph g, int width = 800, int height = 520) {
            var sb = new GLib.StringBuilder ();
            sb.append_printf (
                "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\" width=\"%d\" height=\"%d\">\n",
                width, height, width, height
            );
            sb.append_printf ("  <rect width=\"%d\" height=\"%d\" rx=\"10\" fill=\"#2E3440\"/>\n", width, height);

            foreach (var e in g.edges) {
                var s = g.node_by_id.get (e.source_id);
                var t = g.node_by_id.get (e.target_id);
                if (s == null || t == null) continue;
                double sw = (1.2 + e.weight * 0.7).clamp (1.2, 6.0);
                sb.append_printf (
                    "  <line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" stroke=\"#81A1C1\" stroke-opacity=\"0.58\" stroke-width=\"%.2f\"/>\n",
                    s.x, s.y, t.x, t.y, sw
                );
            }

            foreach (var n in g.nodes) {
                double r = (14.0 + GLib.Math.sqrt (n.groundedness) * 4.0).clamp (14.0, 32.0);
                double bw = n.sdv_verified ? 3.0 : 1.5;
                string bc = n.sdv_verified ? "#ECEFF4" : "#BF616A";
                sb.append_printf (
                    "  <circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%.1f\"/>\n",
                    n.x, n.y, r,
                    GLib.Markup.escape_text (n.color_hex),
                    bc, bw
                );
                sb.append_printf (
                    "  <text x=\"%.1f\" y=\"%.1f\" text-anchor=\"middle\" fill=\"#ECEFF4\" font-family=\"Inter, system-ui, sans-serif\" font-size=\"11\" font-weight=\"600\">%s</text>\n",
                    n.x, n.y + r + 14.0,
                    GLib.Markup.escape_text (n.label)
                );
            }
            sb.append ("</svg>\n");
            return sb.str;
        }
    }
}
