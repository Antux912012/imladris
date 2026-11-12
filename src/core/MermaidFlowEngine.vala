// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Provides the domain model, code generator, parser,
 * auto-layout engine, and scientific presets for visual Mermaid diagrams.
 *
 * Architectural Position:
 * Core domain module inside Imladris.Core.
 * Upstream callers: Imladris.UI.MermaidFlowStudioDialog and unit test suites.
 * Downstream dependencies: GLib, Gee.
 *
 * Concurrency Constraints:
 * Stateless transformation methods are pure and thread-safe. Mutable node and
 * edge collections must be accessed from the GLib MainContext thread.
 */
namespace Imladris.Core {

    /**
     * Defines the supported Mermaid diagram types in the visual studio.
     */
    public enum MermaidDiagramKind {
        FLOWCHART,
        MINDMAP,
        SEQUENCE,
        STATE
    }

    /**
     * Defines the primary layout direction for flowcharts and state diagrams.
     */
    public enum MermaidFlowDirection {
        TOP_DOWN,
        LEFT_RIGHT,
        BOTTOM_TOP,
        RIGHT_LEFT;

        /**
         * Returns the Mermaid syntax token for this flow direction.
         *
         * @return Two-letter direction code ("TD", "LR", "BT", or "RL").
         */
        public string to_token () {
            switch (this) {
                case LEFT_RIGHT: return "LR";
                case BOTTOM_TOP: return "BT";
                case RIGHT_LEFT: return "RL";
                default:         return "TD";
            }
        }

        /**
         * Parses a direction token string into a MermaidFlowDirection value.
         *
         * @param token Direction token such as "TD", "TB", "LR", "BT", or "RL".
         * @return Matching MermaidFlowDirection enum value.
         */
        public static MermaidFlowDirection from_token (string token) {
            string up = token.strip ().up ();
            if (up == "LR") return LEFT_RIGHT;
            if (up == "BT") return BOTTOM_TOP;
            if (up == "RL") return RIGHT_LEFT;
            return TOP_DOWN;
        }
    }

    /**
     * Defines the geometric shape of a node in a visual flowchart or mindmap.
     */
    public enum MermaidNodeShape {
        RECTANGLE,
        ROUNDED,
        STADIUM,
        DIAMOND,
        DATABASE,
        SUBROUTINE,
        HEXAGON,
        CIRCLE,
        PARALLELOGRAM,
        CLOUD
    }

    /**
     * Defines the line and arrowhead style of a connector between two nodes.
     */
    public enum MermaidEdgeStyle {
        SOLID_ARROW,
        DOTTED_ARROW,
        THICK_ARROW,
        SOLID_LINE,
        BIDIRECTIONAL;

        /**
         * Returns the Mermaid arrow operator for this connector style.
         *
         * @return Mermaid connector token.
         */
        public string to_mermaid_operator () {
            switch (this) {
                case DOTTED_ARROW:  return "-.->";
                case THICK_ARROW:   return "==>";
                case SOLID_LINE:    return "---";
                case BIDIRECTIONAL: return "<-->";
                default:            return "-->";
            }
        }
    }

    /**
     * Semantic color palettes aligned with GNOME HIG and Libadwaita tokens.
     */
    public enum MermaidNodePalette {
        DEFAULT,
        BLUE,
        GREEN,
        AMBER,
        RED,
        PURPLE,
        TEAL;

        /**
         * Returns the fill hex color for Mermaid style declarations.
         */
        public string get_fill_hex () {
            switch (this) {
                case BLUE:   return "#dceafe";
                case GREEN:  return "#dcfce7";
                case AMBER:  return "#fef3c7";
                case RED:    return "#fee2e2";
                case PURPLE: return "#f3e8ff";
                case TEAL:   return "#ccfbf1";
                default:     return "#f8fafc";
            }
        }

        /**
         * Returns the border stroke hex color for Mermaid style declarations.
         */
        public string get_stroke_hex () {
            switch (this) {
                case BLUE:   return "#3584e4";
                case GREEN:  return "#2ec27e";
                case AMBER:  return "#e5a50a";
                case RED:    return "#e01b24";
                case PURPLE: return "#9141ac";
                case TEAL:   return "#2190a4";
                default:     return "#64748b";
            }
        }

        /**
         * Returns the text hex color for Mermaid style declarations.
         */
        public string get_text_hex () {
            switch (this) {
                case BLUE:   return "#1e3a8a";
                case GREEN:  return "#14532d";
                case AMBER:  return "#78350f";
                case RED:    return "#7f1d1d";
                case PURPLE: return "#581c87";
                case TEAL:   return "#134e4a";
                default:     return "#1e293b";
            }
        }
    }

    /**
     * Defines how the generated Mermaid code is wrapped when inserted into a document.
     */
    public enum MermaidTargetFormat {
        QUARTO_CHUNK,
        MARKDOWN_FENCE,
        RAW_MERMAID
    }

    /**
     * Represents a visual node on the interactive diagram canvas.
     */
    public class MermaidNode : GLib.Object {
        public string id { get; set; default = "N1"; }
        public string label { get; set; default = "Step"; }
        public MermaidNodeShape shape { get; set; default = MermaidNodeShape.RECTANGLE; }
        public MermaidNodePalette palette { get; set; default = MermaidNodePalette.DEFAULT; }
        public double x { get; set; default = 120.0; }
        public double y { get; set; default = 100.0; }
        public double width { get; set; default = 150.0; }
        public double height { get; set; default = 54.0; }
        public string parent_id { get; set; default = ""; }
        public string subgraph_title { get; set; default = ""; }

        /**
         * Constructs a new visual diagram node.
         *
         * @param id    Unique node identifier (alphanumeric).
         * @param label Display text inside the node.
         * @param shape Geometric shape of the node.
         * @param x     Canvas X coordinate (center).
         * @param y     Canvas Y coordinate (center).
         */
        public MermaidNode (
            string id,
            string label,
            MermaidNodeShape shape = MermaidNodeShape.RECTANGLE,
            double x = 160.0,
            double y = 120.0
        ) {
            this.id = sanitize_id (id);
            this.label = label;
            this.shape = shape;
            this.x = x;
            this.y = y;
            update_dimensions_for_label ();
        }

        /**
         * Updates node bounding box dimensions proportionally to the text label length.
         */
        public void update_dimensions_for_label () {
            int char_len = this.label.char_count ();
            double base_w = 136.0 + (double) int.max (0, char_len - 10) * 6.5;
            this.width = double.min (280.0, double.max (126.0, base_w));
            if (this.shape == MermaidNodeShape.DIAMOND) {
                this.width = double.max (156.0, this.width + 24.0);
                this.height = 72.0;
            } else if (this.shape == MermaidNodeShape.CIRCLE) {
                double d = double.max (76.0, double.min (130.0, 68.0 + char_len * 3.5));
                this.width = d;
                this.height = d;
            } else if (this.shape == MermaidNodeShape.DATABASE) {
                this.height = 64.0;
            } else {
                this.height = 54.0;
            }
        }

        /**
         * Creates a deep copy of this node for undo/redo snapshots.
         *
         * @return Cloned MermaidNode instance.
         */
        public MermaidNode clone () {
            var copy = new MermaidNode (this.id, this.label, this.shape, this.x, this.y);
            copy.palette = this.palette;
            copy.width = this.width;
            copy.height = this.height;
            copy.parent_id = this.parent_id;
            copy.subgraph_title = this.subgraph_title;
            return copy;
        }

        /**
         * Sanitizes an identifier so it is valid in Mermaid syntax.
         */
        public static string sanitize_id (string raw_id) {
            var sb = new StringBuilder ();
            for (int i = 0; i < raw_id.length; i++) {
                char c = raw_id[i];
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') {
                    sb.append_c (c);
                }
            }
            if (sb.len == 0) {
                return "N1";
            }
            char first = sb.str[0];
            if (first >= '0' && first <= '9') {
                return "N" + sb.str;
            }
            return sb.str;
        }
    }

    /**
     * Represents a directed or undirected edge connecting two MermaidNode instances.
     */
    public class MermaidEdge : GLib.Object {
        public string id { get; set; default = "E1"; }
        public string from_id { get; set; default = ""; }
        public string to_id { get; set; default = ""; }
        public string label { get; set; default = ""; }
        public MermaidEdgeStyle style { get; set; default = MermaidEdgeStyle.SOLID_ARROW; }

        /**
         * Constructs a new edge between two node IDs.
         *
         * @param id      Unique edge identifier.
         * @param from_id Source node identifier.
         * @param to_id   Target node identifier.
         * @param label   Optional text label on the connector.
         * @param style   Line and arrow style.
         */
        public MermaidEdge (
            string id,
            string from_id,
            string to_id,
            string label = "",
            MermaidEdgeStyle style = MermaidEdgeStyle.SOLID_ARROW
        ) {
            this.id = id;
            this.from_id = from_id;
            this.to_id = to_id;
            this.label = label;
            this.style = style;
        }

        /**
         * Creates a deep copy of this edge for undo/redo snapshots.
         *
         * @return Cloned MermaidEdge instance.
         */
        public MermaidEdge clone () {
            return new MermaidEdge (this.id, this.from_id, this.to_id, this.label, this.style);
        }
    }

    /**
     * Represents a built-in scientific diagram preset template.
     */
    public class MermaidPreset : GLib.Object {
        public string title { get; set; }
        public string description { get; set; }
        public MermaidDiagramKind kind { get; set; }
        public MermaidFlowDirection direction { get; set; }
        public string mermaid_code { get; set; }

        public MermaidPreset (
            string title,
            string description,
            MermaidDiagramKind kind,
            MermaidFlowDirection direction,
            string mermaid_code
        ) {
            this.title = title;
            this.description = description;
            this.kind = kind;
            this.direction = direction;
            this.mermaid_code = mermaid_code;
        }
    }

    /**
     * Stateless engine that serializes, parses, and lays out visual Mermaid graphs.
     */
    public class MermaidFlowEngine : GLib.Object {

        /**
         * Formats a node declaration in Mermaid flowchart syntax with proper quoting.
         *
         * @param node The visual node to serialize.
         * @return Mermaid node syntax (for example, `A["Process Step"]` or `B{"Check?"}`).
         */
        public static string format_flowchart_node (MermaidNode node) {
            string safe_label = escape_label (node.label);
            string id = MermaidNode.sanitize_id (node.id);
            switch (node.shape) {
                case MermaidNodeShape.ROUNDED:
                    return @"$id(\"$safe_label\")";
                case MermaidNodeShape.STADIUM:
                    return @"$id([\"$safe_label\"])";
                case MermaidNodeShape.DIAMOND:
                    return @"$id{\"$safe_label\"}";
                case MermaidNodeShape.DATABASE:
                    return @"$id([(\"$safe_label\")])".replace ("([(", "[(").replace (")])", ")]");
                case MermaidNodeShape.SUBROUTINE:
                    return @"$id[[\"$safe_label\"]]";
                case MermaidNodeShape.HEXAGON:
                    return @"$id{{\"$safe_label\"}}";
                case MermaidNodeShape.CIRCLE:
                    return @"$id((\"$safe_label\"))";
                case MermaidNodeShape.PARALLELOGRAM:
                    return @"$id[/\"$safe_label\"/]";
                case MermaidNodeShape.CLOUD:
                    return @"$id(\"$safe_label\")";
                default:
                    return @"$id[\"$safe_label\"]";
            }
        }

        /**
         * Formats a node declaration for a Mermaid mindmap branch.
         *
         * @param node   The mindmap node to serialize.
         * @param is_root True if this node is the central root topic.
         * @return Mermaid mindmap node token.
         */
        public static string format_mindmap_node (MermaidNode node, bool is_root = false) {
            string clean = node.label.replace ("\"", "'").replace ("\n", " ").strip ();
            if (clean.length == 0) clean = "Topic";
            string id = MermaidNode.sanitize_id (node.id);

            switch (node.shape) {
                case MermaidNodeShape.CIRCLE:
                    return @"$id(($clean))";
                case MermaidNodeShape.ROUNDED:
                case MermaidNodeShape.STADIUM:
                    return @"$id($clean)";
                case MermaidNodeShape.RECTANGLE:
                    return @"$id[$clean]";
                case MermaidNodeShape.HEXAGON:
                case MermaidNodeShape.DIAMOND:
                    return @"$id{{$clean}}";
                case MermaidNodeShape.CLOUD:
                    return @"$id)$clean(";
                default:
                    if (is_root) {
                        return @"$id(($clean))";
                    }
                    return @"$id($clean)";
            }
        }

        /**
         * Generates standard Mermaid code from the visual nodes and edges collection.
         *
         * @param kind      Diagram type (FLOWCHART, MINDMAP, SEQUENCE, STATE).
         * @param direction Flow direction (TD, LR, BT, RL).
         * @param nodes     Ordered list of visual nodes.
         * @param edges     Ordered list of visual edges.
         * @return Valid Mermaid syntax string.
         */
        public static string generate_mermaid_code (
            MermaidDiagramKind kind,
            MermaidFlowDirection direction,
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges
        ) {
            switch (kind) {
                case MermaidDiagramKind.MINDMAP:
                    return generate_mindmap_code (nodes, edges);
                case MermaidDiagramKind.SEQUENCE:
                    return generate_sequence_code (nodes, edges);
                case MermaidDiagramKind.STATE:
                    return generate_state_code (direction, nodes, edges);
                default:
                    return generate_flowchart_code (direction, nodes, edges);
            }
        }

        private static string generate_flowchart_code (
            MermaidFlowDirection direction,
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges
        ) {
            var sb = new StringBuilder ();
            sb.append (@"flowchart $(direction.to_token ())\n");

            if (nodes.size == 0) {
                sb.append ("  Start([\"Start\"]) --> End([\"End\"])\n");
                return sb.str.strip ();
            }

            // Collect subgraphs vs top-level nodes
            var subgraphs = new Gee.HashMap<string, Gee.ArrayList<MermaidNode>> ();
            var top_nodes = new Gee.ArrayList<MermaidNode> ();

            foreach (var n in nodes) {
                string sg = n.subgraph_title.strip ();
                if (sg.length > 0) {
                    if (!subgraphs.has_key (sg)) {
                        subgraphs.set (sg, new Gee.ArrayList<MermaidNode> ());
                    }
                    subgraphs.get (sg).add (n);
                } else {
                    top_nodes.add (n);
                }
            }

            // Emit top-level node declarations
            foreach (var n in top_nodes) {
                sb.append (@"  $(format_flowchart_node (n))\n");
            }

            // Emit subgraphs if present
            int sg_idx = 1;
            foreach (var entry in subgraphs.entries) {
                string sg_id = @"SG$(sg_idx++)";
                string sg_label = escape_label (entry.key);
                sb.append (@"  subgraph $sg_id [\"$sg_label\"]\n");
                foreach (var n in entry.value) {
                    sb.append (@"    $(format_flowchart_node (n))\n");
                }
                sb.append ("  end\n");
            }

            // Emit edges
            if (edges.size > 0) {
                sb.append ("\n");
                foreach (var e in edges) {
                    string from_id = MermaidNode.sanitize_id (e.from_id);
                    string to_id = MermaidNode.sanitize_id (e.to_id);
                    string op = e.style.to_mermaid_operator ();
                    string lbl = e.label.strip ();
                    if (lbl.length > 0) {
                        string safe_lbl = escape_label (lbl).replace ("|", "/");
                        sb.append (@"  $from_id $op|\"$safe_lbl\"| $to_id\n");
                    } else {
                        sb.append (@"  $from_id $op $to_id\n");
                    }
                }
            }

            // Emit semantic style rules for colored nodes
            bool has_styles = false;
            foreach (var n in nodes) {
                if (n.palette != MermaidNodePalette.DEFAULT) {
                    if (!has_styles) {
                        sb.append ("\n");
                        has_styles = true;
                    }
                    string id = MermaidNode.sanitize_id (n.id);
                    string fill = n.palette.get_fill_hex ();
                    string stroke = n.palette.get_stroke_hex ();
                    string color = n.palette.get_text_hex ();
                    sb.append (@"  style $id fill:$fill,stroke:$stroke,stroke-width:2px,color:$color\n");
                }
            }

            return sb.str.strip ();
        }

        private static string generate_mindmap_code (
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges
        ) {
            var sb = new StringBuilder ();
            sb.append ("mindmap\n");

            if (nodes.size == 0) {
                sb.append ("  root((Central Topic))\n");
                return sb.str.strip ();
            }

            // Build parent -> children adjacency from explicit parent_id or directed edges
            var parent_map = new Gee.HashMap<string, string> ();
            foreach (var n in nodes) {
                if (n.parent_id.strip ().length > 0) {
                    parent_map.set (n.id, n.parent_id.strip ());
                }
            }
            foreach (var e in edges) {
                if (!parent_map.has_key (e.to_id) && e.from_id != e.to_id) {
                    parent_map.set (e.to_id, e.from_id);
                }
            }

            // Identify root node (first node without a parent, or nodes[0])
            MermaidNode root = nodes[0];
            foreach (var n in nodes) {
                if (!parent_map.has_key (n.id)) {
                    root = n;
                    break;
                }
            }

            var visited = new Gee.HashSet<string> ();
            emit_mindmap_Subtree (sb, root, nodes, parent_map, visited, 1, true);

            // Emit any disconnected orphan nodes under root
            foreach (var n in nodes) {
                if (!visited.contains (n.id)) {
                    emit_mindmap_Subtree (sb, n, nodes, parent_map, visited, 2, false);
                }
            }

            return sb.str.strip ();
        }

        private static void emit_mindmap_Subtree (
            StringBuilder sb,
            MermaidNode current,
            Gee.ArrayList<MermaidNode> all_nodes,
            Gee.HashMap<string, string> parent_map,
            Gee.HashSet<string> visited,
            int depth,
            bool is_root
        ) {
            if (visited.contains (current.id)) return;
            visited.add (current.id);

            string indent = string.nfill (depth * 2, ' ');
            sb.append (@"$indent$(format_mindmap_node (current, is_root))\n");

            foreach (var child in all_nodes) {
                if (!visited.contains (child.id) && parent_map.has_key (child.id) && parent_map.get (child.id) == current.id) {
                    emit_mindmap_Subtree (sb, child, all_nodes, parent_map, visited, depth + 1, false);
                }
            }
        }

        private static string generate_sequence_code (
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges
        ) {
            var sb = new StringBuilder ();
            sb.append ("sequenceDiagram\n");
            sb.append ("  autonumber\n");

            foreach (var n in nodes) {
                string id = MermaidNode.sanitize_id (n.id);
                string lbl = escape_label (n.label);
                sb.append (@"  participant $id as $lbl\n");
            }

            if (edges.size > 0) {
                sb.append ("\n");
                foreach (var e in edges) {
                    string from_id = MermaidNode.sanitize_id (e.from_id);
                    string to_id = MermaidNode.sanitize_id (e.to_id);
                    string arrow = "->>";
                    if (e.style == MermaidEdgeStyle.DOTTED_ARROW) {
                        arrow = "-->>";
                    } else if (e.style == MermaidEdgeStyle.SOLID_LINE) {
                        arrow = "->";
                    }
                    string msg = e.label.strip ().length > 0 ? e.label.strip () : "Message";
                    sb.append (@"  $from_id$arrow$to_id: $msg\n");
                }
            }

            return sb.str.strip ();
        }

        private static string generate_state_code (
            MermaidFlowDirection direction,
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges
        ) {
            var sb = new StringBuilder ();
            sb.append ("stateDiagram-v2\n");
            sb.append (@"  direction $(direction.to_token ())\n");

            foreach (var n in nodes) {
                string id = MermaidNode.sanitize_id (n.id);
                string lbl = escape_label (n.label);
                sb.append (@"  state \"$lbl\" as $id\n");
            }

            if (edges.size > 0) {
                sb.append ("\n");
                foreach (var e in edges) {
                    string from_id = MermaidNode.sanitize_id (e.from_id);
                    string to_id = MermaidNode.sanitize_id (e.to_id);
                    string lbl = e.label.strip ();
                    if (lbl.length > 0) {
                        sb.append (@"  $from_id --> $to_id : $lbl\n");
                    } else {
                        sb.append (@"  $from_id --> $to_id\n");
                    }
                }
            }

            return sb.str.strip ();
        }

        /**
         * Wraps raw Mermaid diagram syntax into the target document block format.
         *
         * @param raw_mermaid    Valid Mermaid syntax.
         * @param target_format  QUARTO_CHUNK, MARKDOWN_FENCE, or RAW_MERMAID.
         * @param figure_label   Optional Quarto cross-reference label (for example, "fig-workflow").
         * @param figure_caption Optional Quarto figure caption.
         * @return Formatted block ready for insertion into the document buffer.
         */
        public static string format_for_document (
            string raw_mermaid,
            MermaidTargetFormat target_format,
            string? figure_label = null,
            string? figure_caption = null
        ) {
            string body = raw_mermaid.strip ();
            switch (target_format) {
                case MermaidTargetFormat.QUARTO_CHUNK:
                    var sb = new StringBuilder ();
                    sb.append ("\n```{mermaid}\n");
                    if (figure_label != null && figure_label.strip ().length > 0) {
                        string clean_lbl = figure_label.strip ();
                        if (!clean_lbl.has_prefix ("fig-")) {
                            clean_lbl = "fig-" + clean_lbl;
                        }
                        sb.append (@"#| label: $clean_lbl\n");
                    }
                    if (figure_caption != null && figure_caption.strip ().length > 0) {
                        string safe_cap = figure_caption.strip ().replace ("\"", "'");
                        sb.append (@"#| fig-cap: \"$safe_cap\"\n");
                    }
                    sb.append (body);
                    sb.append ("\n```\n");
                    return sb.str;

                case MermaidTargetFormat.MARKDOWN_FENCE:
                    return @"\n```mermaid\n$body\n```\n";

                default:
                    return body + "\n";
            }
        }

        /**
         * Parses Mermaid code (flowchart, mindmap, sequence, or state) into visual nodes and edges.
         *
         * @param input_text Raw Mermaid syntax or fenced code block.
         * @param kind       Output diagram kind detected.
         * @param direction  Output flow direction detected.
         * @param nodes      Output list of parsed visual nodes.
         * @param edges      Output list of parsed visual edges.
         */
        public static void parse_mermaid_code (
            string input_text,
            out MermaidDiagramKind kind,
            out MermaidFlowDirection direction,
            out Gee.ArrayList<MermaidNode> nodes,
            out Gee.ArrayList<MermaidEdge> edges
        ) {
            kind = MermaidDiagramKind.FLOWCHART;
            direction = MermaidFlowDirection.TOP_DOWN;
            nodes = new Gee.ArrayList<MermaidNode> ();
            edges = new Gee.ArrayList<MermaidEdge> ();

            var node_map = new Gee.HashMap<string, MermaidNode> ();
            string[] lines = input_text.split ("\n");
            bool header_parsed = false;

            // Stack for tracking mindmap indentation levels: (indent_spaces -> node_id)
            var indent_stack_spaces = new Gee.ArrayList<int> ();
            var indent_stack_ids = new Gee.ArrayList<string> ();
            string current_subgraph = "";
            int edge_counter = 1;
            int auto_node_counter = 1;

            foreach (string raw_line in lines) {
                string trimmed = raw_line.strip ();
                if (trimmed.length == 0) continue;
                if (trimmed.has_prefix ("```") || trimmed.has_prefix ("%%") || trimmed.has_prefix ("#|")) {
                    continue;
                }

                if (!header_parsed) {
                    string lower = trimmed.down ();
                    if (lower.has_prefix ("flowchart") || lower.has_prefix ("graph")) {
                        kind = MermaidDiagramKind.FLOWCHART;
                        string[] parts = trimmed.split (" ");
                        if (parts.length >= 2) {
                            direction = MermaidFlowDirection.from_token (parts[1]);
                        }
                        header_parsed = true;
                        continue;
                    } else if (lower.has_prefix ("mindmap")) {
                        kind = MermaidDiagramKind.MINDMAP;
                        header_parsed = true;
                        continue;
                    } else if (lower.has_prefix ("sequencediagram")) {
                        kind = MermaidDiagramKind.SEQUENCE;
                        header_parsed = true;
                        continue;
                    } else if (lower.has_prefix ("statediagram")) {
                        kind = MermaidDiagramKind.STATE;
                        header_parsed = true;
                        continue;
                    }
                }

                if (kind == MermaidDiagramKind.MINDMAP) {
                    int indent = count_leading_spaces (raw_line);
                    string m_id;
                    string m_label;
                    MermaidNodeShape m_shape;
                    parse_mindmap_token (trimmed, auto_node_counter++, out m_id, out m_label, out m_shape);

                    var m_node = new MermaidNode (m_id, m_label, m_shape);
                    while (indent_stack_spaces.size > 0 && indent_stack_spaces[indent_stack_spaces.size - 1] >= indent) {
                        indent_stack_spaces.remove_at (indent_stack_spaces.size - 1);
                        indent_stack_ids.remove_at (indent_stack_ids.size - 1);
                    }
                    if (indent_stack_ids.size > 0) {
                        m_node.parent_id = indent_stack_ids[indent_stack_ids.size - 1];
                        edges.add (new MermaidEdge (@"E$(edge_counter++)", m_node.parent_id, m_node.id));
                    } else {
                        m_node.palette = MermaidNodePalette.BLUE;
                    }
                    indent_stack_spaces.add (indent);
                    indent_stack_ids.add (m_node.id);
                    nodes.add (m_node);
                    node_map.set (m_node.id, m_node);
                    continue;
                }

                if (kind == MermaidDiagramKind.SEQUENCE) {
                    if (trimmed.down () == "autonumber") continue;
                    if (trimmed.has_prefix ("participant ") || trimmed.has_prefix ("actor ")) {
                        string rest = trimmed.substring (trimmed.index_of (" ") + 1).strip ();
                        int as_idx = rest.index_of (" as ");
                        string p_id = as_idx > 0 ? rest.substring (0, as_idx).strip () : rest;
                        string p_lbl = as_idx > 0 ? unquote (rest.substring (as_idx + 4).strip ()) : p_id;
                        p_id = MermaidNode.sanitize_id (p_id);
                        if (!node_map.has_key (p_id)) {
                            var pn = new MermaidNode (p_id, p_lbl, MermaidNodeShape.RECTANGLE);
                            nodes.add (pn);
                            node_map.set (p_id, pn);
                        }
                        continue;
                    }
                    if (trimmed.contains ("->>") || trimmed.contains ("-->>") || trimmed.contains ("->")) {
                        string op = trimmed.contains ("-->>") ? "-->>" : (trimmed.contains ("->>") ? "->>" : "->");
                        int op_pos = trimmed.index_of (op);
                        string left = trimmed.substring (0, op_pos).strip ();
                        string right_part = trimmed.substring (op_pos + op.length).strip ();
                        int colon_pos = right_part.index_of (":");
                        string right = colon_pos >= 0 ? right_part.substring (0, colon_pos).strip () : right_part;
                        string msg = colon_pos >= 0 ? right_part.substring (colon_pos + 1).strip () : "";

                        string f_id = MermaidNode.sanitize_id (left);
                        string t_id = MermaidNode.sanitize_id (right);
                        ensure_node_exists (f_id, nodes, node_map);
                        ensure_node_exists (t_id, nodes, node_map);
                        var st = (op == "-->>") ? MermaidEdgeStyle.DOTTED_ARROW : MermaidEdgeStyle.SOLID_ARROW;
                        edges.add (new MermaidEdge (@"E$(edge_counter++)", f_id, t_id, msg, st));
                    }
                    continue;
                }

                // Flowchart & State parsing
                if (trimmed.has_prefix ("direction ")) {
                    direction = MermaidFlowDirection.from_token (trimmed.substring (10));
                    continue;
                }
                if (trimmed.has_prefix ("subgraph ")) {
                    string sg_rest = trimmed.substring (9).strip ();
                    int brk = sg_rest.index_of ("[");
                    if (brk >= 0 && sg_rest.has_suffix ("]")) {
                        current_subgraph = unquote (sg_rest.substring (brk + 1, sg_rest.length - brk - 2));
                    } else {
                        current_subgraph = unquote (sg_rest);
                    }
                    continue;
                }
                if (trimmed == "end") {
                    current_subgraph = "";
                    continue;
                }
                if (trimmed.has_prefix ("style ")) {
                    parse_style_line (trimmed, node_map);
                    continue;
                }
                if (trimmed.has_prefix ("state ")) {
                    parse_state_declaration (trimmed, nodes, node_map);
                    continue;
                }

                // Check for edge arrow in line
                string[] arrow_ops = { "<-->", "-.->", "==>", "-->", "---" };
                string? matched_op = null;
                int arrow_pos = -1;
                foreach (string op in arrow_ops) {
                    int idx = trimmed.index_of (op);
                    if (idx > 0) {
                        matched_op = op;
                        arrow_pos = idx;
                        break;
                    }
                }

                if (matched_op != null && arrow_pos > 0) {
                    string lhs = trimmed.substring (0, arrow_pos).strip ();
                    string rhs = trimmed.substring (arrow_pos + matched_op.length).strip ();
                    string edge_label = "";

                    // Check for |label| after operator
                    if (rhs.has_prefix ("|")) {
                        int second_pipe = rhs.index_of ("|", 1);
                        if (second_pipe > 0) {
                            edge_label = unquote (rhs.substring (1, second_pipe - 1).strip ());
                            rhs = rhs.substring (second_pipe + 1).strip ();
                        }
                    } else if (kind == MermaidDiagramKind.STATE && rhs.contains (":")) {
                        int c_idx = rhs.index_of (":");
                        edge_label = rhs.substring (c_idx + 1).strip ();
                        rhs = rhs.substring (0, c_idx).strip ();
                    }

                    MermaidNode src_node = parse_or_get_flowchart_node (lhs, current_subgraph, nodes, node_map);
                    MermaidNode dst_node = parse_or_get_flowchart_node (rhs, current_subgraph, nodes, node_map);

                    MermaidEdgeStyle e_style = MermaidEdgeStyle.SOLID_ARROW;
                    if (matched_op == "-.->") e_style = MermaidEdgeStyle.DOTTED_ARROW;
                    else if (matched_op == "==>") e_style = MermaidEdgeStyle.THICK_ARROW;
                    else if (matched_op == "---") e_style = MermaidEdgeStyle.SOLID_LINE;
                    else if (matched_op == "<-->") e_style = MermaidEdgeStyle.BIDIRECTIONAL;

                    edges.add (new MermaidEdge (@"E$(edge_counter++)", src_node.id, dst_node.id, edge_label, e_style));
                } else {
                    // Standalone node definition
                    parse_or_get_flowchart_node (trimmed, current_subgraph, nodes, node_map);
                }
            }

            // Compute automatic 2D coordinates for all parsed nodes
            auto_layout (kind, direction, nodes, edges, 880.0, 560.0);
        }

        /**
         * Automatically positions nodes on the 2D canvas according to diagram kind and direction.
         *
         * @param kind          Diagram type.
         * @param direction     Flow direction.
         * @param nodes         Nodes to position.
         * @param edges         Edges defining connectivity.
         * @param canvas_width  Target canvas width in pixels.
         * @param canvas_height Target canvas height in pixels.
         */
        public static void auto_layout (
            MermaidDiagramKind kind,
            MermaidFlowDirection direction,
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges,
            double canvas_width = 880.0,
            double canvas_height = 560.0
        ) {
            if (nodes.size == 0) return;

            foreach (var n in nodes) {
                n.update_dimensions_for_label ();
            }

            if (kind == MermaidDiagramKind.MINDMAP) {
                layout_mindmap_tree (nodes, edges, canvas_width, canvas_height);
                return;
            }

            if (kind == MermaidDiagramKind.SEQUENCE) {
                double start_x = 130.0;
                double spacing_x = 200.0;
                for (int i = 0; i < nodes.size; i++) {
                    nodes[i].x = start_x + i * spacing_x;
                    nodes[i].y = 85.0;
                }
                return;
            }

            // Layered topological layout for Flowcharts and State diagrams
            var rank_map = new Gee.HashMap<string, int> ();
            foreach (var n in nodes) {
                rank_map.set (n.id, 0);
            }

            // Relax edge ranks up to nodes.size iterations (handles cycles safely)
            for (int iter = 0; iter < nodes.size; iter++) {
                bool changed = false;
                foreach (var e in edges) {
                    if (e.from_id == e.to_id) continue;
                    int r_from = rank_map.has_key (e.from_id) ? rank_map.get (e.from_id) : 0;
                    int r_to = rank_map.has_key (e.to_id) ? rank_map.get (e.to_id) : 0;
                    if (r_to <= r_from) {
                        rank_map.set (e.to_id, int.min (nodes.size, r_from + 1));
                        changed = true;
                    }
                }
                if (!changed) break;
            }

            int max_rank = 0;
            var layers = new Gee.HashMap<int, Gee.ArrayList<MermaidNode>> ();
            foreach (var n in nodes) {
                int r = rank_map.get (n.id);
                if (r > max_rank) max_rank = r;
                if (!layers.has_key (r)) {
                    layers.set (r, new Gee.ArrayList<MermaidNode> ());
                }
                layers.get (r).add (n);
            }

            bool horizontal = (direction == MermaidFlowDirection.LEFT_RIGHT || direction == MermaidFlowDirection.RIGHT_LEFT);
            bool reverse = (direction == MermaidFlowDirection.BOTTOM_TOP || direction == MermaidFlowDirection.RIGHT_LEFT);

            double layer_step = horizontal ? 225.0 : 120.0;
            double sibling_step = horizontal ? 115.0 : 210.0;

            for (int r = 0; r <= max_rank; r++) {
                if (!layers.has_key (r)) continue;
                var layer_nodes = layers.get (r);
                int effective_r = reverse ? (max_rank - r) : r;
                int count = layer_nodes.size;

                for (int i = 0; i < count; i++) {
                    var node = layer_nodes[i];
                    double offset = ((double) i - (double) (count - 1) / 2.0) * sibling_step;
                    if (horizontal) {
                        node.x = 140.0 + effective_r * layer_step;
                        node.y = double.max (80.0, canvas_height / 2.0 + offset);
                    } else {
                        node.x = double.max (120.0, canvas_width / 2.0 + offset);
                        node.y = 90.0 + effective_r * layer_step;
                    }
                }
            }
        }

        private static void layout_mindmap_tree (
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges,
            double canvas_width,
            double canvas_height
        ) {
            var parent_map = new Gee.HashMap<string, string> ();
            foreach (var n in nodes) {
                if (n.parent_id.strip ().length > 0) {
                    parent_map.set (n.id, n.parent_id.strip ());
                }
            }
            foreach (var e in edges) {
                if (!parent_map.has_key (e.to_id) && e.from_id != e.to_id) {
                    parent_map.set (e.to_id, e.from_id);
                }
            }

            MermaidNode root = nodes[0];
            foreach (var n in nodes) {
                if (!parent_map.has_key (n.id)) {
                    root = n;
                    break;
                }
            }

            double cx = double.max (380.0, canvas_width / 2.0);
            double cy = double.max (260.0, canvas_height / 2.0);
            root.x = cx;
            root.y = cy;

            // Gather level-1 children of root
            var level1 = new Gee.ArrayList<MermaidNode> ();
            foreach (var n in nodes) {
                if (n != root && (!parent_map.has_key (n.id) || parent_map.get (n.id) == root.id)) {
                    n.parent_id = root.id;
                    level1.add (n);
                }
            }

            int n1 = level1.size;
            for (int i = 0; i < n1; i++) {
                var branch = level1[i];
                bool left_side = (i % 2 == 1);
                int side_idx = i / 2;
                int side_total = (n1 + (left_side ? 0 : 1)) / 2;
                double y_offset = ((double) side_idx - (double) (side_total - 1) / 2.0) * 125.0;

                branch.x = cx + (left_side ? -235.0 : 235.0);
                branch.y = cy + y_offset;

                // Gather level-2 children of this branch
                var level2 = new Gee.ArrayList<MermaidNode> ();
                foreach (var sub in nodes) {
                    if (parent_map.has_key (sub.id) && parent_map.get (sub.id) == branch.id) {
                        level2.add (sub);
                    }
                }
                for (int j = 0; j < level2.size; j++) {
                    var leaf = level2[j];
                    double leaf_y_off = ((double) j - (double) (level2.size - 1) / 2.0) * 72.0;
                    leaf.x = branch.x + (left_side ? -215.0 : 215.0);
                    leaf.y = branch.y + leaf_y_off;
                }
            }
        }

        /**
         * Returns the built-in scientific and bioinformatics diagram presets.
         */
        public static Gee.ArrayList<MermaidPreset> get_presets () {
            var list = new Gee.ArrayList<MermaidPreset> ();

            list.add (new MermaidPreset (
                "Bioinformatics RNA-Seq Pipeline",
                "FASTQ quality control, HISAT2 alignment, featureCounts, and DESeq2 differential expression",
                MermaidDiagramKind.FLOWCHART,
                MermaidFlowDirection.TOP_DOWN,
                """flowchart TD
  FASTQ[/"Raw FASTQ Reads"/] --> QC{"FastQC Pass?"}
  QC -->|"Yes"| Align["HISAT2 Alignment"]
  QC -.->|"Adapter Trim"| Trim["fastp Trimming"]
  Trim --> Align
  Align --> BAM[("Sorted BAM Files")]
  BAM --> Counts["featureCounts Matrix"]
  Counts --> DESeq2[["DESeq2 Statistical Model"]]
  DESeq2 --> Volcano(["Volcano & PCA Figures"])

  style FASTQ fill:#ccfbf1,stroke:#2190a4,stroke-width:2px,color:#134e4a
  style QC fill:#fef3c7,stroke:#e5a50a,stroke-width:2px,color:#78350f
  style DESeq2 fill:#f3e8ff,stroke:#9141ac,stroke-width:2px,color:#581c87
  style Volcano fill:#dcfce7,stroke:#2ec27e,stroke-width:2px,color:#14532d"""
            ));

            list.add (new MermaidPreset (
                "Scientific Hypothesis & Experiment Loop",
                "Standard empirical research workflow from observation to peer-reviewed manuscript",
                MermaidDiagramKind.FLOWCHART,
                MermaidFlowDirection.LEFT_RIGHT,
                """flowchart LR
  Obs(["Observation"]) --> Hyp["Formulate Hypothesis"]
  Hyp --> Exp["Design & Run Experiment"]
  Exp --> Data[("Collect Dataset")]
  Data --> Stat{"p < 0.05?"}
  Stat -->|"Significant"| Pub(["Publish in Quarto"])
  Stat -.->|"Refine Model"| Hyp

  style Obs fill:#dceafe,stroke:#3584e4,stroke-width:2px,color:#1e3a8a
  style Stat fill:#fef3c7,stroke:#e5a50a,stroke-width:2px,color:#78350f
  style Pub fill:#dcfce7,stroke:#2ec27e,stroke-width:2px,color:#14532d"""
            ));

            list.add (new MermaidPreset (
                "Clinical Trial CONSORT Diagram",
                "Patient enrollment, randomization, allocation, follow-up, and intention-to-treat analysis",
                MermaidDiagramKind.FLOWCHART,
                MermaidFlowDirection.TOP_DOWN,
                """flowchart TD
  Enroll(["Assessed for Eligibility (n = 420)"]) --> Excl{"Excluded (n = 60)"}
  Excl --> Rand["Randomized (n = 360)"]
  Rand --> ArmA["Treatment Group (n = 180)"]
  Rand --> ArmB["Control Placebo (n = 180)"]
  ArmA --> AnalA(["Analyzed ITT (n = 176)"])
  ArmB --> AnalB(["Analyzed ITT (n = 178)"])

  style Enroll fill:#dceafe,stroke:#3584e4,stroke-width:2px,color:#1e3a8a
  style Excl fill:#fee2e2,stroke:#e01b24,stroke-width:2px,color:#7f1d1d
  style AnalA fill:#dcfce7,stroke:#2ec27e,stroke-width:2px,color:#14532d
  style AnalB fill:#dcfce7,stroke:#2ec27e,stroke-width:2px,color:#14532d"""
            ));

            list.add (new MermaidPreset (
                "Research Manuscript Architecture (Mindmap)",
                "Hierarchical mindmap for planning a reproducible scientific paper",
                MermaidDiagramKind.MINDMAP,
                MermaidFlowDirection.TOP_DOWN,
                """mindmap
  root((Reproducible Study))
    Introduction
      Literature Review
      Primary Hypothesis
    Methods
      Galaxy Provenance
      Statistical Models
    Results
      Normalized Counts
      Survival Curves
    Discussion
      Clinical Impact
      Limitations"""
            ));

            list.add (new MermaidPreset (
                "Machine Learning & Omics Study (Mindmap)",
                "Feature engineering, cross-validation, and biomarker discovery mindmap",
                MermaidDiagramKind.MINDMAP,
                MermaidFlowDirection.TOP_DOWN,
                """mindmap
  root((Omics ML Pipeline))
    Data Preprocessing
      Batch Correction
      Log2 Normalization
    Model Training
      Random Forest
      Gradient Boosting
    Evaluation
      ROC AUC Curve
      SHAP Feature Importance"""
            ));

            list.add (new MermaidPreset (
                "Arekyer Galaxy-to-Quarto Provenance Sequence",
                "Sequence diagram illustrating authenticated dataset fetching from Galaxy Project",
                MermaidDiagramKind.SEQUENCE,
                MermaidFlowDirection.TOP_DOWN,
                """sequenceDiagram
  autonumber
  participant Keyring as libsecret Vault
  participant Imladris as Arekyer Bridge
  participant Galaxy as Galaxy REST API
  participant Quarto as Quarto R/Py Kernel

  Imladris->>Keyring: Lookup GALAXY_API_KEY
  Keyring-->>Imladris: Secret Token Verified
  Imladris->>Galaxy: GET /api/histories
  Galaxy-->>Imladris: JSON Dataset Metadata
  Imladris->>Quarto: Inject Provenance Chunk
  Quarto->>Galaxy: Fetch Tabular Dataset (httr2)"""
            ));

            list.add (new MermaidPreset (
                "Reproducible Sandbox Lifecycle (State Diagram)",
                "State transitions for renv / venv environment locking and Mallorn archiving",
                MermaidDiagramKind.STATE,
                MermaidFlowDirection.LEFT_RIGHT,
                """stateDiagram-v2
  direction LR
  state "Initialized (.Rproj)" as Init
  state "Packages Installed" as Deps
  state "Lockfile Snapshotted" as Locked
  state "Rendered Manuscript" as Rendered
  state "Archived (.mallorn)" as Mallorn

  Init --> Deps : install.packages / uv pip
  Deps --> Locked : renv::snapshot()
  Locked --> Rendered : quarto render
  Rendered --> Mallorn : Export Bundle"""
            ));

            return list;
        }

        private static string escape_label (string raw) {
            return raw.replace ("\"", "'").replace ("\n", " ").strip ();
        }

        private static string unquote (string s) {
            string t = s.strip ();
            if (t.length >= 2 && ((t.has_prefix ("\"") && t.has_suffix ("\"")) || (t.has_prefix ("'") && t.has_suffix ("'")))) {
                return t.substring (1, t.length - 2);
            }
            return t;
        }

        private static int count_leading_spaces (string line) {
            int count = 0;
            for (int i = 0; i < line.length; i++) {
                if (line[i] == ' ') count++;
                else if (line[i] == '\t') count += 2;
                else break;
            }
            return count;
        }

        private static void ensure_node_exists (
            string id,
            Gee.ArrayList<MermaidNode> nodes,
            Gee.HashMap<string, MermaidNode> node_map
        ) {
            if (!node_map.has_key (id)) {
                var n = new MermaidNode (id, id);
                nodes.add (n);
                node_map.set (id, n);
            }
        }

        private static void parse_mindmap_token (
            string token,
            int seq,
            out string id,
            out string label,
            out MermaidNodeShape shape
        ) {
            shape = MermaidNodeShape.ROUNDED;
            string t = token.strip ();

            if (t.contains ("((") && t.has_suffix ("))")) {
                int idx = t.index_of ("((");
                id = idx > 0 ? MermaidNode.sanitize_id (t.substring (0, idx)) : @"M$seq";
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.CIRCLE;
            } else if (t.contains ("{{") && t.has_suffix ("}}")) {
                int idx = t.index_of ("{{");
                id = idx > 0 ? MermaidNode.sanitize_id (t.substring (0, idx)) : @"M$seq";
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.HEXAGON;
            } else if (t.contains ("[") && t.has_suffix ("]")) {
                int idx = t.index_of ("[");
                id = idx > 0 ? MermaidNode.sanitize_id (t.substring (0, idx)) : @"M$seq";
                label = unquote (t.substring (idx + 1, t.length - idx - 2));
                shape = MermaidNodeShape.RECTANGLE;
            } else if (t.contains ("(") && t.has_suffix (")")) {
                int idx = t.index_of ("(");
                id = idx > 0 ? MermaidNode.sanitize_id (t.substring (0, idx)) : @"M$seq";
                label = unquote (t.substring (idx + 1, t.length - idx - 2));
                shape = MermaidNodeShape.ROUNDED;
            } else {
                id = @"M$seq";
                label = unquote (t);
            }
        }

        private static MermaidNode parse_or_get_flowchart_node (
            string expr,
            string subgraph_name,
            Gee.ArrayList<MermaidNode> nodes,
            Gee.HashMap<string, MermaidNode> node_map
        ) {
            string t = expr.strip ();
            string id = t;
            string label = t;
            MermaidNodeShape shape = MermaidNodeShape.RECTANGLE;
            bool has_explicit_shape = false;

            if (t.contains ("([") && t.has_suffix ("])")) {
                int idx = t.index_of ("([");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.STADIUM;
                has_explicit_shape = true;
            } else if (t.contains ("[(") && t.has_suffix (")]")) {
                int idx = t.index_of ("[(");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.DATABASE;
                has_explicit_shape = true;
            } else if (t.contains ("[[") && t.has_suffix ("]]")) {
                int idx = t.index_of ("[[");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.SUBROUTINE;
                has_explicit_shape = true;
            } else if (t.contains ("{{") && t.has_suffix ("}}")) {
                int idx = t.index_of ("{{");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.HEXAGON;
                has_explicit_shape = true;
            } else if (t.contains ("((") && t.has_suffix ("))")) {
                int idx = t.index_of ("((");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.CIRCLE;
                has_explicit_shape = true;
            } else if (t.contains ("[/") && t.has_suffix ("/]")) {
                int idx = t.index_of ("[/");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 2, t.length - idx - 4));
                shape = MermaidNodeShape.PARALLELOGRAM;
                has_explicit_shape = true;
            } else if (t.contains ("{") && t.has_suffix ("}")) {
                int idx = t.index_of ("{");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 1, t.length - idx - 2));
                shape = MermaidNodeShape.DIAMOND;
                has_explicit_shape = true;
            } else if (t.contains ("[") && t.has_suffix ("]")) {
                int idx = t.index_of ("[");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 1, t.length - idx - 2));
                shape = MermaidNodeShape.RECTANGLE;
                has_explicit_shape = true;
            } else if (t.contains ("(") && t.has_suffix (")")) {
                int idx = t.index_of ("(");
                id = t.substring (0, idx);
                label = unquote (t.substring (idx + 1, t.length - idx - 2));
                shape = MermaidNodeShape.ROUNDED;
                has_explicit_shape = true;
            }

            id = MermaidNode.sanitize_id (id);
            if (node_map.has_key (id)) {
                var existing = node_map.get (id);
                if (has_explicit_shape) {
                    existing.label = label;
                    existing.shape = shape;
                    existing.update_dimensions_for_label ();
                }
                if (subgraph_name.length > 0 && existing.subgraph_title.length == 0) {
                    existing.subgraph_title = subgraph_name;
                }
                return existing;
            }

            var created = new MermaidNode (id, label, shape);
            created.subgraph_title = subgraph_name;
            nodes.add (created);
            node_map.set (id, created);
            return created;
        }

        private static void parse_style_line (
            string trimmed,
            Gee.HashMap<string, MermaidNode> node_map
        ) {
            string[] parts = trimmed.split (" ");
            if (parts.length < 3) return;
            string id = MermaidNode.sanitize_id (parts[1]);
            if (!node_map.has_key (id)) return;
            var node = node_map.get (id);
            string rules = parts[2].down ();
            if (rules.contains ("#3584e4") || rules.contains ("#dceafe")) node.palette = MermaidNodePalette.BLUE;
            else if (rules.contains ("#2ec27e") || rules.contains ("#dcfce7")) node.palette = MermaidNodePalette.GREEN;
            else if (rules.contains ("#e5a50a") || rules.contains ("#fef3c7")) node.palette = MermaidNodePalette.AMBER;
            else if (rules.contains ("#e01b24") || rules.contains ("#fee2e2")) node.palette = MermaidNodePalette.RED;
            else if (rules.contains ("#9141ac") || rules.contains ("#f3e8ff")) node.palette = MermaidNodePalette.PURPLE;
            else if (rules.contains ("#2190a4") || rules.contains ("#ccfbf1")) node.palette = MermaidNodePalette.TEAL;
        }

        private static void parse_state_declaration (
            string trimmed,
            Gee.ArrayList<MermaidNode> nodes,
            Gee.HashMap<string, MermaidNode> node_map
        ) {
            int as_idx = trimmed.index_of (" as ");
            if (as_idx > 6) {
                string raw_lbl = unquote (trimmed.substring (6, as_idx - 6).strip ());
                string id = MermaidNode.sanitize_id (trimmed.substring (as_idx + 4).strip ());
                if (node_map.has_key (id)) {
                    node_map.get (id).label = raw_lbl;
                } else {
                    var n = new MermaidNode (id, raw_lbl, MermaidNodeShape.ROUNDED);
                    nodes.add (n);
                    node_map.set (id, n);
                }
            }
        }

        /**
         * Exports the current visual diagram to a standalone vector SVG string.
         *
         * @param nodes Nodes on the canvas.
         * @param edges Edges connecting the nodes.
         * @return Valid SVG XML document string.
         */
        public static string export_to_svg (
            Gee.ArrayList<MermaidNode> nodes,
            Gee.ArrayList<MermaidEdge> edges
        ) {
            double max_x = 800.0;
            double max_y = 520.0;
            foreach (var n in nodes) {
                if (n.x + n.width / 2.0 + 60.0 > max_x) max_x = n.x + n.width / 2.0 + 60.0;
                if (n.y + n.height / 2.0 + 60.0 > max_y) max_y = n.y + n.height / 2.0 + 60.0;
            }

            var sb = new StringBuilder ();
            sb.append (@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append (@"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$((int) max_x)\" height=\"$((int) max_y)\" viewBox=\"0 0 $((int) max_x) $((int) max_y)\">\n");
            sb.append ("  <defs>\n");
            sb.append ("    <marker id=\"arrow\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" markerWidth=\"7\" markerHeight=\"7\" orient=\"auto-start-reverse\">\n");
            sb.append ("      <path d=\"M 0 1 L 10 5 L 0 9 z\" fill=\"#475569\"/>\n");
            sb.append ("    </marker>\n");
            sb.append ("  </defs>\n");
            sb.append (@"  <rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n");

            var node_lookup = new Gee.HashMap<string, MermaidNode> ();
            foreach (var n in nodes) {
                node_lookup.set (n.id, n);
            }

            foreach (var e in edges) {
                if (!node_lookup.has_key (e.from_id) || !node_lookup.has_key (e.to_id)) continue;
                var src = node_lookup.get (e.from_id);
                var dst = node_lookup.get (e.to_id);
                string dash = (e.style == MermaidEdgeStyle.DOTTED_ARROW) ? " stroke-dasharray=\"6,4\"" : "";
                string marker = (e.style == MermaidEdgeStyle.SOLID_LINE) ? "" : " marker-end=\"url(#arrow)\"";
                sb.append (@"  <line x1=\"$((int) src.x)\" y1=\"$((int) src.y)\" x2=\"$((int) dst.x)\" y2=\"$((int) dst.y)\" stroke=\"#475569\" stroke-width=\"2\"$dash$marker/>\n");
                if (e.label.strip ().length > 0) {
                    int mx = (int) ((src.x + dst.x) / 2.0);
                    int my = (int) ((src.y + dst.y) / 2.0) - 6;
                    string esc = Markup.escape_text (e.label.strip ());
                    sb.append (@"  <text x=\"$mx\" y=\"$my\" font-family=\"Inter, Cantarell, sans-serif\" font-size=\"11\" fill=\"#334155\" text-anchor=\"middle\">$esc</text>\n");
                }
            }

            foreach (var n in nodes) {
                double rx = n.x - n.width / 2.0;
                double ry = n.y - n.height / 2.0;
                string fill = n.palette.get_fill_hex ();
                string stroke = n.palette.get_stroke_hex ();
                string text_col = n.palette.get_text_hex ();
                int corner = (n.shape == MermaidNodeShape.STADIUM) ? 26 : ((n.shape == MermaidNodeShape.ROUNDED) ? 12 : 6);
                string esc_lbl = Markup.escape_text (n.label);

                if (n.shape == MermaidNodeShape.CIRCLE) {
                    int r = (int) (n.width / 2.0);
                    sb.append (@"  <circle cx=\"$((int) n.x)\" cy=\"$((int) n.y)\" r=\"$r\" fill=\"$fill\" stroke=\"$stroke\" stroke-width=\"2\"/>\n");
                } else if (n.shape == MermaidNodeShape.DIAMOND) {
                    int cx = (int) n.x;
                    int cy = (int) n.y;
                    int hw = (int) (n.width / 2.0);
                    int hh = (int) (n.height / 2.0);
                    sb.append (@"  <polygon points=\"$cx,$(cy - hh) $(cx + hw),$cy $cx,$(cy + hh) $(cx - hw),$cy\" fill=\"$fill\" stroke=\"$stroke\" stroke-width=\"2\"/>\n");
                } else {
                    sb.append (@"  <rect x=\"$((int) rx)\" y=\"$((int) ry)\" width=\"$((int) n.width)\" height=\"$((int) n.height)\" rx=\"$corner\" fill=\"$fill\" stroke=\"$stroke\" stroke-width=\"2\"/>\n");
                }
                sb.append (@"  <text x=\"$((int) n.x)\" y=\"$((int) n.y + 4)\" font-family=\"Inter, Cantarell, sans-serif\" font-size=\"13\" font-weight=\"600\" fill=\"$text_col\" text-anchor=\"middle\">$esc_lbl</text>\n");
            }

            sb.append ("</svg>\n");
            return sb.str;
        }
    }
}
