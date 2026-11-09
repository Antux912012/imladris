// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Gee;
using Imladris.Services;

public class TestZoteroService {

    public static void test_bib_parsing () {
        var zotero = ZoteroService.get_default ();

        string sample_bib = """
@article{knuth1984,
  title = {Literate Programming},
  author = {Knuth, Donald E.},
  year = {1984}
}

@book{turing1950,
  title = {Computing Machinery and Intelligence},
  author = {Turing, Alan M.},
  year = {1950}
}
""";

        var res_knuth = zotero.search_offline_bib ("knuth", sample_bib);
        assert (res_knuth.size == 1);
        var item_k = res_knuth[0];
        assert (item_k.citekey == "knuth1984");
        assert (item_k.title == "Literate Programming");
        assert (item_k.authors == "Knuth, Donald E.");
        assert (item_k.year == "1984");
        assert (item_k.source == "local-bib");

        var res_turing = zotero.search_offline_bib ("intelligence", sample_bib);
        assert (res_turing.size == 1);
        assert (res_turing[0].citekey == "turing1950");

        var res_all = zotero.search_offline_bib ("", sample_bib);
        assert (res_all.size == 2);
    }

    public static void test_bib_merging () {
        var zotero = ZoteroService.get_default ();

        string initial_bib = """@article{knuth1984,
  title = {Literate Programming},
  author = {Knuth, Donald E.},
  year = {1984}
}
""";

        string duplicate_entry = """@article{knuth1984,
  title = {Literate Programming},
  author = {Knuth, Donald E.},
  year = {1984}
}
""";

        // Merging already existing key returns original content without duplication
        string merged_dup = zotero.merge_into_bib_file_content (initial_bib, duplicate_entry, "knuth1984");
        assert (merged_dup == initial_bib);

        string new_entry = """@book{turing1950,
  title = {Computing Machinery and Intelligence},
  author = {Turing, Alan M.},
  year = {1950}
}""";

        string merged_new = zotero.merge_into_bib_file_content (initial_bib, new_entry, "turing1950");
        assert ("@book{turing1950" in merged_new);
        assert ("@article{knuth1984" in merged_new);
    }

    public static void test_yaml_frontmatter () {
        var zotero = ZoteroService.get_default ();

        // Case 1: No frontmatter at all
        string raw_md = "# My Document\n\nContent here.";
        string with_bib = zotero.ensure_yaml_bibliography (raw_md, "references.bib");
        assert (with_bib.has_prefix ("---\nbibliography: references.bib\n---\n\n"));

        // Case 2: Existing frontmatter without bibliography
        string existing_yaml = "---\ntitle: \"Study\"\nauthor: \"Alice\"\n---\n\nContent.";
        string updated_yaml = zotero.ensure_yaml_bibliography (existing_yaml, "references.bib");
        assert ("bibliography: references.bib" in updated_yaml);
        assert ("title: \"Study\"" in updated_yaml);

        // Case 3: Existing frontmatter with bibliography already defined
        string already_bib = "---\ntitle: \"Study\"\nbibliography: custom.bib\n---\n\nContent.";
        string unchanged = zotero.ensure_yaml_bibliography (already_bib, "references.bib");
        assert (unchanged == already_bib);
    }

    public static void test_zotero_select_uri () {
        var zotero = ZoteroService.get_default ();
        string uri = zotero.get_zotero_select_uri ("knuth1984");
        assert (uri == "zotero://select/items/@knuth1984");
    }

    public static int main (string[] args) {
        Test.init (ref args);

        Test.add_func ("/zotero/bib_parsing", test_bib_parsing);
        Test.add_func ("/zotero/bib_merging", test_bib_merging);
        Test.add_func ("/zotero/yaml_frontmatter", test_yaml_frontmatter);
        Test.add_func ("/zotero/select_uri", test_zotero_select_uri);

        return Test.run ();
    }
}
