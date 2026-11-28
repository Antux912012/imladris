// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Soup;
using Imladris.Services;

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/qual/phase6/docs_manifest_11_domains_offline_etag_and_symbol_lookup", () => {
        var loop = new GLib.MainLoop ();
        string manuals_src_dir = "docs/manuals";
        if (!GLib.FileUtils.test (GLib.Path.build_filename (manuals_src_dir, "manuals-manifest.json"), GLib.FileTest.EXISTS)) {
            manuals_src_dir = "../docs/manuals";
        }
        if (!GLib.FileUtils.test (GLib.Path.build_filename (manuals_src_dir, "manuals-manifest.json"), GLib.FileTest.EXISTS)) {
            manuals_src_dir = "/src/docs/manuals";
        }
        string tmp_cache = "";
        try { tmp_cache = GLib.DirUtils.make_tmp ("imladris-docs-cache-XXXXXX"); } catch (GLib.FileError e) {}

        int etag_304_hits = 0;
        var server = new Soup.Server ("server-header", "GitHub-Raw-Docs-Mock");
        server.add_handler ("/docs", (srv, msg, path, query) => {
            string rel = path.substring ("/docs/".length);
            string disk_file = GLib.Path.build_filename (manuals_src_dir, rel);
            if (!GLib.FileUtils.test (disk_file, GLib.FileTest.EXISTS)) {
                msg.set_status (404, null);
                return;
            }
            string? inm = msg.get_request_headers ().get_one ("If-None-Match");
            if (inm == "\"etag-v1\"") {
                etag_304_hits++;
                msg.set_status (304, null);
                return;
            }
            try {
                string txt;
                GLib.FileUtils.get_contents (disk_file, out txt);
                msg.get_response_headers ().append ("ETag", "\"etag-v1\"");
                msg.set_status (200, null);
                msg.set_response ("text/plain; charset=utf-8", Soup.MemoryUse.COPY, txt.data);
            } catch (GLib.Error e) {
                msg.set_status (500, null);
            }
        });

        try { server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY); } catch (GLib.Error e) { error (e.message); }
        int port = server.get_uris ().nth_data (0).get_port ();

        // Empty cache initially so it fetches over HTTP from mock GitHub endpoint
        string empty_local = tmp_cache + "-nonexistent";
        var client = new DocsRepositoryClient (tmp_cache, empty_local);
        client.manifest_url = @"http://127.0.0.1:$port/docs/manuals-manifest.json";

        run_docs_flow_async.begin (client, port, (o, res) => {
            run_docs_flow_async.end (res);
            loop.quit ();
        });
        loop.run ();
        assert (etag_304_hits >= 1);
        server.disconnect ();
    });

    return Test.run ();
}

private async void run_docs_flow_async (DocsRepositoryClient client, int port) {
    bool ok = yield client.refresh_manifest_async ();
    assert (ok);
    // Verify all 11 documentation domains exist!
    assert (client.manuals.size == 11);

    foreach (var m in client.manuals) {
        m.remote_url = @"http://127.0.0.1:$port/docs/$(m.filename)";
    }

    int downloaded = yield client.download_all_for_offline_async ();
    assert (downloaded == 11);

    // Second manifest check must hit HTTP 304 Not Modified via ETag!
    bool ok2 = yield client.refresh_manifest_async ();
    assert (ok2);

    // Verify SHA-256 offline cache verification for every single manual!
    foreach (var m in client.manuals) {
        assert (client.is_cached_offline (m));
    }

    // Verify F1 contextual symbol lookups across tracks:
    assert (client.lookup_symbol ("ggplot", "r").id == "r-language");
    assert (client.lookup_symbol ("kripp.alpha", "r").id == "cran-packages");
    assert (client.lookup_symbol ("fisher_exact", "py").id == "python-libs");
    assert (client.lookup_symbol ("dataclass", "py").id == "python-core");
    assert (client.lookup_symbol ("GalaxyInstance", "py").id == "galaxy");
    assert (client.lookup_symbol ("cyrest", "md").id == "cytoscape");
    assert (client.lookup_symbol ("qual", "qmd").id == "markdown-quarto");
    assert (client.lookup_symbol ("showModal", "html").id == "html5");
    assert (client.lookup_symbol ("prefers-reduced-motion", "css").id == "css3");
    assert (client.lookup_symbol ("readonly", "ts").id == "typescript");
    assert (client.lookup_symbol ("awk", "sh").id == "bash-linux");

    // Verify offline fallback even if remote URL is unreachable
    foreach (var m in client.manuals) {
        m.remote_url = "http://127.0.0.1:1/unreachable";
        string md = yield client.get_manual_markdown_async (m.id, false);
        assert (md.has_prefix ("# "));
    }
}
