/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;
using Imladris.Core;
using Imladris.Adapters;

namespace Imladris.Tests {

    private static void test_chunk_parser_via_rust () {
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

    private static void test_frontmatter_parser_via_rust () {
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
            string roundtrip_json = NotebookSerializer.markdown_to_ipynb (modified_md, orig_ipynb);
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

    public static int main (string[] args) {
        Test.init (ref args);
        Test.add_func ("/rust_rendering/chunk_parser", test_chunk_parser_via_rust);
        Test.add_func ("/rust_rendering/frontmatter_parser", test_frontmatter_parser_via_rust);
        Test.add_func ("/rust_rendering/ipynb_roundtrip", test_ipynb_roundtrip_preserves_outputs);
        Test.add_func ("/rust_rendering/document_adapter_formats", test_document_adapter_code_protection_and_formats);
        Test.add_func ("/rust_rendering/math_chem_fixes", test_math_chem_engine_fixes);
        Test.add_func ("/rust_rendering/mermaid_fixes", test_mermaid_engine_fixes);
        return Test.run ();
    }
}
