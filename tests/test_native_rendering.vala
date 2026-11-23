/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: Apache-2.0
 */

using GLib;
using Imladris.Core;
using Imladris.Adapters;

namespace Imladris.Tests {

    private static void test_chunk_parser_native () {
        string doc = """---
title: "Chunk Test"
---

Intro text.

```{r setup, echo=FALSE}
x <- 1 + 1
print(x)
```

```{python}
y = 2 * 3
```
""";
        var chunks = ChunkParser.parse_chunks (doc);
        assert (chunks.size == 2);
        assert (chunks[0].language == "r");
        assert (chunks[0].chunk_label == "setup");
        assert (chunks[0].echo == false);
        assert (chunks[0].code.contains ("x <- 1 + 1"));
        assert (chunks[1].language == "python");
        assert (chunks[1].code.contains ("y = 2 * 3"));
    }

    private static void test_frontmatter_parser_native () {
        string doc = """---
title: "My Paper"
author: "Ada Lovelace"
format: html
---

Body paragraph.
""";
        FrontmatterData? meta;
        string body;
        FrontmatterParser.split_frontmatter (doc, out meta, out body);
        assert (meta != null);
        assert (!meta.is_empty ());
        assert (meta.title == "My Paper");
        assert (meta.author == "Ada Lovelace");
        assert (body.strip () == "Body paragraph.");
        string fm_html = meta.to_html ();
        assert (fm_html.contains ("My Paper"));
        assert (fm_html.contains ("Ada Lovelace"));
    }

    private static void test_ipynb_roundtrip_preserves_outputs () {
        string orig_ipynb = """{
 "cells": [
  {
   "cell_type": "markdown",
   "id": "c1",
   "metadata": {},
   "source": ["# Notebook Title\n", "Hello $x^2$"]
  },
  {
   "cell_type": "code",
   "execution_count": 7,
   "id": "c2",
   "metadata": {"tags": ["keep-me"]},
   "outputs": [{"output_type": "stream", "name": "stdout", "text": ["42\n"]}],
   "source": ["print(40 + 2)"]
  }
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}""";
        try {
            string editor_md = NotebookSerializer.ipynb_to_markdown (orig_ipynb);
            assert (editor_md.contains ("Notebook Title"));
            assert (editor_md.contains ("```{python}"));
            assert (editor_md.contains ("print(40 + 2)"));

            string modified_md = editor_md.replace ("print(40 + 2)", "print(41 + 1)");
            string roundtrip_json = NotebookSerializer.markdown_to_ipynb (modified_md, "", orig_ipynb);
            assert (roundtrip_json.contains ("keep-me"));
            assert (roundtrip_json.contains ("42\\n") || roundtrip_json.contains ("42"));
            assert (roundtrip_json.contains ("print(41 + 1)"));
            assert (roundtrip_json.contains ("python3"));
        } catch (GLib.Error e) {
            assert_not_reached ();
        }
    }

    private static void test_document_adapter_code_protection_and_formats () {
        string md = """---
title: "Math & Code"
---

Prose math $x + y$ and chemistry \ce{H2O}.

```python
price = "$x + y$"
# $a + b$ inside code must stay literal
```
""";
        string html = DocumentAdapter.render_html (md, DocumentFormat.QMD);
        assert (!html.contains ("\"html\":"));
        assert (!html.contains ("imladris-math-inline"));
        assert (html.contains ("Math &amp; Code") || html.contains ("Math & Code"));
        assert (html.contains ("<pre><code"));
        assert (html.contains ("$x + y$")); // inside <pre><code> untouched
        assert (html.contains ("class=\"math-inline\"")); // prose $x + y$ hydrated

        // Currency guard in raw HTML
        string raw_html = "<p>Total is $5 and $10 today, while $x^2$ is math.</p>";
        string rendered_raw = DocumentAdapter.render_html_with_latex (raw_html);
        assert (rendered_raw.contains ("$5 and $10"));
        assert (rendered_raw.contains ("math-inline"));

        // LaTeX and TypeScript previews
        string tex_html = DocumentAdapter.render_html ("\\title{Demo}\\begin{document}\\section{Intro}$a < b$\\end{document}", DocumentFormat.TEX);
        assert (tex_html.contains ("<h2>Intro</h2>"));
        assert (tex_html.contains ("math-inline"));

        string ts_html = DocumentAdapter.render_html ("export interface Point { x: number; y: number; }", DocumentFormat.TS);
        assert (ts_html.contains ("Point"));
        assert (ts_html.contains ("language-typescript"));
    }

    private static void test_math_chem_engine_fixes () {
        string integral = MathChemEngine.render_latex_to_html ("\\int_0^1 x^2 dx", false);
        assert (integral.contains ("∫"));
        assert (!integral.contains ("∈t"));

        string cmp = MathChemEngine.render_latex_to_html ("a < b > c", false);
        assert (cmp.contains ("&lt;"));
        assert (cmp.contains ("&gt;"));
    }

    private static void test_native_outline_and_typescript_symbols () {
        string document = "# Notes\n\n```{python setup}\nprint(1)\n```\n\n## Results\n";
        string outline_json = NativeCore.extract_outline_json (document);
        assert (outline_json.contains ("\"kind\":\"heading\""));
        assert (outline_json.contains ("\"kind\":\"chunk\""));
        assert (outline_json.contains ("setup (python)"));

        string symbols_json = NativeCore.analyze_typescript_symbols_json (
            "export interface Point { x: number; }\nconst distance = (x: number) => x;"
        );
        assert (symbols_json.contains ("Point"));
        assert (symbols_json.contains ("distance"));
        assert (symbols_json.contains ("\"kind\":\"function\""));
    }

    private static void test_native_latex_diagnostics () {
        string json = NativeCore.parse_latex_log_json ("! Undefined control sequence.\nl.17 \\badcommand\n");
        assert (json.contains ("Undefined control sequence"));
        assert (json.contains ("\"line\":17"));
        assert (json.contains ("\"severity\":\"error\""));
    }

    private static void test_mermaid_engine_fixes () {
        MermaidDiagramKind kind;
        MermaidFlowDirection dir;
        Gee.ArrayList<MermaidNode> nodes;
        Gee.ArrayList<MermaidEdge> edges;

        MermaidFlowEngine.parse_mermaid_code ("flowchart LR\nA[Start] --> B[End]", out kind, out dir, out nodes, out edges);
        assert (nodes.size == 2);
        MermaidFlowEngine.auto_layout (kind, dir, nodes, edges);
        string svg = MermaidFlowEngine.export_to_svg (nodes, edges);
        assert (svg.contains ("<marker"));
        assert (!svg.contains ("background: #ffffff"));

        MermaidFlowEngine.parse_mermaid_code ("sequenceDiagram\nAlice->>Bob: Hello", out kind, out dir, out nodes, out edges);
        assert (kind == MermaidDiagramKind.SEQUENCE);
        assert (nodes.size == 2);
        MermaidFlowEngine.auto_layout (kind, dir, nodes, edges);
        string seq_svg = MermaidFlowEngine.export_to_svg (nodes, edges, kind);
        assert (seq_svg.contains ("stroke-dasharray"));
    }

    static void test_latex_templates_and_citations () {
        var templates = Imladris.Core.LatexTemplates.get_top_templates ();
        var citations = Imladris.Core.LatexTemplates.get_top_citation_styles ();
        assert (templates.length == 10);
        assert (citations.length == 10);

        for (int i = 0; i < templates.length; i++) {
            var tpl = templates[i];
            var default_cite = Imladris.Core.LatexTemplates.find_citation_style (tpl.default_citation_id);
            assert (default_cite != null);
            string tex = Imladris.Core.LatexTemplates.generate_document (
                tpl, default_cite, "Quantum Simulation", "Dr. Researcher", "myrefs.bib"
            );
            assert (tex.contains ("\\documentclass"));
            assert (tex.contains (tpl.document_class));
            assert (tex.contains ("\\begin{document}"));
            assert (tex.contains ("\\end{document}"));
            assert (tex.contains ("Quantum Simulation"));
            assert (tex.contains ("Dr. Researcher"));
            assert (tex.contains ("myrefs"));
        }

        // Verify BibLaTeX Chicago style & Natbib APA style
        var chicago = Imladris.Core.LatexTemplates.find_citation_style ("chicago");
        assert (chicago != null && chicago.uses_biblatex);
        var ieee = Imladris.Core.LatexTemplates.find_template ("ieee");
        assert (ieee != null);
        string chicago_tex = Imladris.Core.LatexTemplates.generate_document (ieee, chicago, "Test", "Author");
        assert (chicago_tex.contains ("\\addbibresource{references.bib}"));
        assert (chicago_tex.contains ("\\printbibliography"));
        assert (chicago_tex.contains ("\\parencite{example2026}"));
    }

    private static void test_rtf_codec_and_format () {
        assert (Imladris.DocumentFormat.from_filename ("notes.rtf") == Imladris.DocumentFormat.RTF);
        assert (Imladris.DocumentFormat.RTF.get_extension () == ".rtf");

        string sample_rtf = """{\rtf1\ansi\ansicpg1252\deff0
{\fonttbl{\f0\fswiss Sans;}{\f1\froman Georgia;}}
{\colortbl ;\red220\green38\blue38;\red254\green240\blue138;}
\pard\qc\f1\fs32\b Title \u945?\b0\fs24\par
\pard\ql\cf1\highlight2\i Body \{escaped\} & text\i0\par
}""";
        string plain = Imladris.Core.RtfCodec.rtf_to_plain_text (sample_rtf);
        assert (plain.contains ("Title α"));
        assert (plain.contains ("Body {escaped} & text"));

        string html = Imladris.Core.RtfCodec.rtf_to_html (sample_rtf);
        assert (html.contains ("text-align:center"));
        assert (html.contains ("font-weight: 700"));
        assert (html.contains ("font-style: italic"));
        assert (html.contains ("color: #dc2626"));
        assert (html.contains ("background-color: #fef08a"));
        assert (html.contains ("Body {escaped} &amp; text"));

        var profile = Imladris.Core.FormatProfile.for_format (Imladris.DocumentFormat.RTF);
        assert (profile.supports_live_preview);
        assert (!profile.default_rstudio_layout);

        var rtf_cfg = new Imladris.ProjectConfig () {
            project_name = "My RTF Note",
            format = Imladris.DocumentFormat.RTF
        };
        string rtf_tpl = Imladris.ProjectScaffolder.build_template (rtf_cfg, "/tmp", "/tmp/data", "/tmp/images", "/tmp/references.bib");
        assert (rtf_tpl.has_prefix ("{\\rtf1"));
        assert (rtf_tpl.contains ("My RTF Note"));

        // Verify XSS raw HTML passthrough (including spoofed internal class prefixes) is blocked,
        // multi-line code chunks remain intact, and query-param links are not double-escaped
        string md_xss = "<div onclick=\"alert(1)\">bad</div>\n<div class=\"code-chunk-card\" onclick=\"alert(1)\">spoof</div>\n```{python}\nx = 1\ny = 2\n```\n[link](https://example.com/?a=1&b=2)";
        string rendered_md = Imladris.Adapters.DocumentAdapter.render_html (md_xss, Imladris.DocumentFormat.MD);
        assert (!rendered_md.contains ("<div onclick="));
        assert (!rendered_md.contains ("onclick=\"alert(1)\""));
        assert (rendered_md.contains ("&lt;div onclick="));
        assert (rendered_md.contains ("&lt;div class=&quot;code-chunk-card&quot;"));
        assert (rendered_md.contains ("<pre><code class=\"language-python\">\nx = 1\ny = 2\n</code></pre></div>"));
        assert (rendered_md.contains ("href=\"https://example.com/?a=1&amp;b=2\""));
        assert (!rendered_md.contains ("&amp;amp;"));
    }

    public static int main (string[] args) {
        Test.init (ref args);
        Test.add_func ("/native_rendering/chunk_parser", test_chunk_parser_native);
        Test.add_func ("/native_rendering/frontmatter_parser", test_frontmatter_parser_native);
        Test.add_func ("/native_rendering/ipynb_roundtrip", test_ipynb_roundtrip_preserves_outputs);
        Test.add_func ("/native_rendering/document_adapter_formats", test_document_adapter_code_protection_and_formats);
        Test.add_func ("/native_rendering/math_chem_fixes", test_math_chem_engine_fixes);
        Test.add_func ("/native_rendering/mermaid_fixes", test_mermaid_engine_fixes);
        Test.add_func ("/native_rendering/outline_and_typescript", test_native_outline_and_typescript_symbols);
        Test.add_func ("/native_rendering/latex_diagnostics", test_native_latex_diagnostics);
        Test.add_func ("/native_rendering/latex_templates_and_citations", test_latex_templates_and_citations);
        Test.add_func ("/native_rendering/rtf_codec_and_format", test_rtf_codec_and_format);
        return Test.run ();
    }
}
