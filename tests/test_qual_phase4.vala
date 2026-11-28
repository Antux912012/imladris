// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Soup;
using Imladris.Qual;
using Imladris.Bridges.Cytoscape;

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/qual/phase4/cx2_and_graphml_lossless_roundtrip", () => {
        try {
            string tmp_dir = GLib.DirUtils.make_tmp ("imladris-qual-p4-XXXXXX");
            var svc = new QualWorkspaceService (tmp_dir);
            string qmd = """
[TP53 nuclear accumulation]{.qual id="q-1" domain="protein" code="loc-nuclear" entity="UniProtKB:P04637" coder="antonio" confidence="high"}
[MDM2 ubiquitin-mediated degradation]{.qual id="q-2" domain="protein" code="ptm-ubiquitin" entity="UniProtKB:Q00987" coder="antonio" confidence="high"}
""";
            string fpath = GLib.Path.build_filename (tmp_dir, "tp53.qmd");
            GLib.FileUtils.set_contents (fpath, qmd);
            svc.db.sync_document_spans (fpath, qmd, "antonio");

            var g = NetworkBuilder.build_from_workspace (svc);
            assert (g.nodes.size == 5); // 2 entities + 2 codes + 1 document
            assert (g.edges.size >= 4);

            // CX2 lossless round-trip
            string cx2 = Cx2Serializer.serialize (g);
            assert (cx2.contains ("\"CXVersion\" : \"2.0\""));
            var g_cx2 = Cx2Serializer.deserialize (cx2);
            assert (g_cx2.nodes.size == g.nodes.size);
            assert (g_cx2.edges.size == g.edges.size);
            assert (g_cx2.node_by_id.has_key ("UniProtKB:P04637"));

            // GraphML lossless round-trip
            string gml = GraphMlSerializer.serialize (g);
            assert (gml.contains ("<graphml"));
            var g_gml = GraphMlSerializer.deserialize (gml);
            assert (g_gml.nodes.size == g.nodes.size);
            assert (g_gml.edges.size == g.edges.size);
            assert (g_gml.node_by_id.get ("loc-nuclear").color_hex == "#88C0D0");
        } catch (GLib.Error e) {
            error ("Roundtrip failed: %s", e.message);
        }
    });

    Test.add_func ("/qual/phase4/cyrest_live_push_style_selection_sync_and_svg", () => {
        var loop = new GLib.MainLoop ();
        bool pushed_cx2 = false;
        bool pushed_nord_style = false;
        bool applied_style = false;
        bool applied_layout = false;

        // Spin up an in-process mock Cytoscape CyREST v1 HTTP server on an ephemeral port
        var server = new Soup.Server ("server-header", "Cytoscape-CyREST-Mock/3.10");
        server.add_handler ("/v1", (srv, msg, path, query) => {
            string method = msg.get_method ();
            var req_flat = msg.get_request_body ().flatten ();
            var req_sb = new GLib.StringBuilder.sized (req_flat.get_size () + 1);
            if (req_flat.get_size () > 0) {
                req_sb.append_len ((string) req_flat.get_data (), (ssize_t) req_flat.get_size ());
            }
            string req = req_sb.str;
            if (path == "/v1" && method == "GET") {
                string body = "{\"apiVersion\":\"v1\",\"cytoscapeVersion\":\"3.10.3\"}";
                msg.set_status (200, null);
                msg.set_response ("application/json", Soup.MemoryUse.COPY, body.data);
            } else if (path == "/v1/networks" && method == "POST") {
                if (req.contains ("CXVersion") && req.contains ("UniProtKB:P04637")) {
                    pushed_cx2 = true;
                }
                string resp = "{\"networkSUID\": 4242}";
                msg.set_status (200, null);
                msg.set_response ("application/json", Soup.MemoryUse.COPY, resp.data);
            } else if (path == "/v1/styles" && method == "POST") {
                if (req.contains ("Imladris-Nord") && req.contains ("#2E3440")) {
                    pushed_nord_style = true;
                }
                msg.set_status (201, null);
                msg.set_response ("application/json", Soup.MemoryUse.COPY, "{\"title\":\"Imladris-Nord\"}".data);
            } else if (path == "/v1/apply/styles/Imladris-Nord/4242") {
                applied_style = true;
                msg.set_status (200, null);
                msg.set_response ("application/json", Soup.MemoryUse.COPY, "{}".data);
            } else if (path == "/v1/apply/layouts/force-directed/4242") {
                applied_layout = true;
                msg.set_status (200, null);
                msg.set_response ("application/json", Soup.MemoryUse.COPY, "{}".data);
            } else if (path == "/v1/networks/4242/nodes" && method == "GET") {
                msg.set_status (200, null);
                msg.set_response ("application/json", Soup.MemoryUse.COPY, "[101]".data);
            } else if (path == "/v1/networks/4242/tables/defaultnode/rows" && method == "GET") {
                string rows = "[{\"SUID\":101,\"name\":\"UniProtKB:P04637\"},{\"SUID\":102,\"name\":\"UniProtKB:Q00987\"}]";
                msg.set_status (200, null);
                msg.set_response ("application/json", Soup.MemoryUse.COPY, rows.data);
            } else if (path == "/v1/networks/4242/views/first.svg" && method == "GET") {
                string svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"400\" height=\"300\"><circle cx=\"50\" cy=\"50\" r=\"20\"/></svg>";
                msg.set_status (200, null);
                msg.set_response ("image/svg+xml", Soup.MemoryUse.COPY, svg.data);
            } else {
                msg.set_status (404, null);
            }
        });

        try {
            server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
        } catch (GLib.Error e) {
            error ("Failed to start mock CyREST server: %s", e.message);
        }
        var uris = server.get_uris ();
        int bound_port = uris.nth_data (0).get_port ();

        string tmp_dir = "";
        try { tmp_dir = GLib.DirUtils.make_tmp ("imladris-cyrest-e2e-XXXXXX"); } catch (GLib.FileError fe) {}
        var svc = new QualWorkspaceService (tmp_dir);
        string qmd = """
[TP53 nuclear accumulation]{.qual id="q-1" domain="protein" code="loc-nuclear" entity="UniProtKB:P04637" coder="antonio" confidence="high"}
[MDM2 ubiquitin-mediated degradation]{.qual id="q-2" domain="protein" code="ptm-ubiquitin" entity="UniProtKB:Q00987" coder="antonio" confidence="high"}
""";
        string fpath = GLib.Path.build_filename (tmp_dir, "manuscript.qmd");
        try {
            GLib.FileUtils.set_contents (fpath, qmd);
            svc.db.sync_document_spans (fpath, qmd, "antonio");
        } catch (GLib.Error e) { error (e.message); }

        var graph = NetworkBuilder.build_from_workspace (svc);
        var client = new CyRestClient ("127.0.0.1", bound_port);

        run_cyrest_flow_async.begin (client, svc, graph, tmp_dir, (o, res) => {
            run_cyrest_flow_async.end (res);
            loop.quit ();
        });
        loop.run ();

        assert (pushed_cx2);
        assert (pushed_nord_style);
        assert (applied_style);
        assert (applied_layout);
        server.disconnect ();
    });

    return Test.run ();
}

private async void run_cyrest_flow_async (
    CyRestClient client,
    QualWorkspaceService svc,
    QualGraph graph,
    string tmp_dir
) {
    try {
        bool healthy = yield client.probe_health_async ();
        assert (healthy);
        assert (client.api_version == "v1");

        int64 suid = yield client.push_network_cx2_async (graph, "force-directed");
        assert (suid == 4242);

        // Pull selection from Cytoscape & verify EvidenceMatrixView filtering!
        var selected = yield client.pull_selected_nodes_async (suid);
        assert (selected.size == 1 && selected[0] == "UniProtKB:P04637");
        svc.set_graph_node_filter (selected);
        var filtered_matrix = svc.build_matrix_rows ();
        assert (filtered_matrix.size == 1);
        assert (filtered_matrix[0].entity_label == "UniProtKB:P04637");

        // Export SVG figure from Cytoscape into Quarto snippet
        string svg_dest = GLib.Path.build_filename (tmp_dir, "figures", "cy-net.svg");
        string fig_md = yield client.export_figure_to_quarto_async (suid, svg_dest, "figures/cy-net.svg", "svg");
        assert (GLib.FileUtils.test (svg_dest, GLib.FileTest.EXISTS));
        assert (fig_md.contains ("{#fig-qual-network-4242}"));
    } catch (GLib.Error e) {
        error ("CyREST async flow failed: %s", e.message);
    }
}
