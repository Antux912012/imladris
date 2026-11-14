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

    public static void test_doi_to_bib_and_nested_braces () {
        // 1. DOI extraction
        assert (DoiBibService.extract_doi ("https://doi.org/10.1038/s41586-020-2649-2") == "10.1038/s41586-020-2649-2");
        assert (DoiBibService.extract_doi ("doi:10.1126/science.abc1234.") == "10.1126/science.abc1234");
        assert (DoiBibService.extract_doi ("not a doi") == null);

        // 2. Crossref JSON -> BibTeX
        string cr_json = """{
            "status": "ok",
            "message": {
                "type": "journal-article",
                "DOI": "10.1038/s41586-020-2649-2",
                "title": ["Array programming with {NumPy}"],
                "author": [{"family": "Harris", "given": "Charles R."}],
                "container-title": ["Nature"],
                "published-print": {"date-parts": [[2020, 9, 17]]},
                "volume": "585",
                "issue": "7825",
                "page": "357-362"
            }
        }""";
        string? bib = DoiBibService.crossref_json_to_bibtex (cr_json);
        assert (bib != null);
        assert (bib.has_prefix ("@article{harris2020array,"));
        assert ("journal = {Nature}" in bib);
        assert ("pages = {357--362}" in bib);
        assert ("doi = {10.1038/s41586-020-2649-2}" in bib);

        // 3. Nested brace BibTeX parsing in ZoteroService
        string nested_bib = "@article{harris2020array,\n  author = {Harris, Charles R.},\n  title = {Array programming with {NumPy} and {RNA} Polymerase {II}},\n  year = {2020}\n}\n";
        var parsed = ZoteroService.get_default ().search_offline_bib ("Polymerase", nested_bib);
        assert (parsed.size == 1);
        assert (parsed[0].citekey == "harris2020array");
        assert ("Polymerase II" in parsed[0].title);

        // 4. PubMed PMID extraction & esummary JSON -> BibTeX
        assert (DoiBibService.extract_pmid ("PMID: 32939066") == "32939066");
        assert (DoiBibService.extract_pmid ("https://pubmed.ncbi.nlm.nih.gov/32939066/") == "32939066");
        assert (DoiBibService.extract_pmid ("10.1038/s41586-020-2649-2") == null);

        string pm_json = """{
            "result": {
                "32939066": {
                    "title": "Array programming with NumPy.",
                    "fulljournalname": "Nature",
                    "pubdate": "2020 Sep",
                    "volume": "585",
                    "issue": "7825",
                    "pages": "357-362",
                    "authors": [{"name": "Harris CR"}],
                    "articleids": [{"idtype": "doi", "value": "10.1038/s41586-020-2649-2"}]
                }
            }
        }""";
        string? pm_bib = DoiBibService.pubmed_json_to_bibtex (pm_json, "32939066");
        assert (pm_bib != null);
        assert ("@article{harris2020_pmid32939066," in pm_bib);
        assert ("pmid = {32939066}" in pm_bib);
        assert ("doi = {10.1038/s41586-020-2649-2}" in pm_bib);
    }

    public static int main (string[] args) {
        Test.init (ref args);

        Test.add_func ("/zotero/bib_parsing", test_bib_parsing);
        Test.add_func ("/zotero/bib_merging", test_bib_merging);
        Test.add_func ("/zotero/yaml_frontmatter", test_yaml_frontmatter);
        Test.add_func ("/zotero/select_uri", test_zotero_select_uri);
        Test.add_func ("/doi/crossref_to_bibtex_and_nested_braces", test_doi_to_bib_and_nested_braces);

        return Test.run ();
    }
}
