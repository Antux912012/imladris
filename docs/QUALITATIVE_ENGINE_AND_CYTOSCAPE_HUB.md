# Qualitative Analysis Engine, Cytoscape Bridge & Documentation Hub (ASD-STE100)

**Standard:** ASD-STE100 (Simplified Technical English)  
**Compliance:** ALCOA+ / GCP Auditability & Reproducible Research  

## 1. Purpose

This document describes the Qualitative Analysis Engine, the Bidirectional Cytoscape Bridge, and the Integrated Help and Documentation Hub in Imladris.

## 2. Qualitative Inline Markup and Sidecar Storage

Imladris stores qualitative tags in plain-text `.md`, `.qmd`, `.Rmd`, and `.ipynb` manuscripts as standard Pandoc bracketed spans:

```markdown
[TP53 exhibits nuclear accumulation]{.qual id="q-8f3a" domain="protein" code="loc-nuclear" valence="negative" entity="UniProtKB:P04637" coder="antonio" confidence="high" ref="@doe2025"}
```

* `QualSpanParser` reads and writes `{.qual ...}` spans without changing surrounding prose, YAML frontmatter, citations, or fenced code blocks.
* `QualDatabase` indexes all workspace spans into `.imladris-qual.db` with SQLite WAL mode enabled.
* `QualDatabase` stores a SHA-256 hash of the source lines for each span for Source Data Verification (SDV).
* `AuditLogger` writes an append-only record to `audit_log` for each create, update, or delete operation. SQLite triggers block `UPDATE` and `DELETE` statements on `audit_log`.

## 3. Domain Profiles and Blinded Dual-Coding

Domain Profiles define hierarchical codes, Nord color hex values, scales, and Yavanna entity resolvers in `.imladris/profiles/*.yaml` or `~/.config/imladris/profiles/*.yaml`.

* Default profiles include `protein-qual.yaml`, `gene-expr-qual.yaml`, `finance-qual.yaml`, and `clinical-qual.yaml`.
* When **Blinded** mode is active, Imladris hides all spans where `coder_id` does not match the active user in the editor buffer, the Live Preview, the Codebook counts, and the Evidence Matrix.

## 4. Biostatistical Reliability and Enrichment

`QualStatsEngine` and `BiostatDashboard` compute:

* **Cohen's Kappa ($\kappa$):** Two-coder categorical agreement.
* **Fleiss' Kappa ($\kappa_F$):** Multi-coder categorical agreement.
* **Krippendorff's Alpha ($\alpha$):** Nominal and ordinal reliability with missing values.
* **Exact Enrichment:** $N \times N$ code co-occurrence matrices with two-sided Fisher's Exact Test and Pearson's $\chi^2$ test.
* **Thematic Saturation:** Cumulative unique codes per sequential document.

## 5. Bidirectional Cytoscape Bridge

* **Native Canvas (`QualGraphView`):** Force-directed and hierarchical GTK4/Cairo graph inspection with click-to-filter links to `EvidenceMatrixView`.
* **Live CyREST (`CyRestClient`):** Connects to `http://localhost:1234/v1`, sends **CX2** networks, applies the `Imladris-Nord` visual style, synchronizes selected nodes back to Imladris, and imports SVG or PNG figures into Quarto manuscripts.
* **Offline Exchange:** Lossless `.cx2` and `.graphml` export and import.

## 6. Subsystem Bridges (Yavanna, Elrond AI, Arekyer)

* **Yavanna:** Normalizes and resolves UniProtKB, Ensembl, GO, SEC CIK, and Ticker identifiers into `spans.entity_id`.
* **Elrond AI:** Generates grammar-constrained JSON coding suggestions into `ai_suggestions` (`Pending Review`). Suggestions never enter `spans` without explicit human approval.
* **Arekyer Hook:** Reads `.qual-hook.json` files from R, Python, or Galaxy code chunks to convert quantitative thresholds into qualitative annotations.

## 7. Integrated Help and Documentation Hub

`DocsRepositoryClient` and `HelpHubPanel` serve 11 documentation domains (`r-language`, `cran-packages`, `python-core`, `python-libs`, `galaxy`, `cytoscape`, `markdown-quarto`, `html5`, `css3`, `typescript`, `bash-linux`) from `docs/manuals/manuals-manifest.json`. The client updates manuals via HTTP `ETag`, verifies SHA-256 checksums, and caches files in `~/.cache/imladris/docs/`. `HelpHubPanel` provides `F1` contextual lookup and one-click code insertion.
