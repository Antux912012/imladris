# Markdown, Pandoc Spans & Quarto Authoring

Create plain-text `.md`, `.qmd`, and `.Rmd` manuscripts that compile in Pandoc and Quarto without altering qualitative span metadata.

## Pandoc Qualitative Bracketed Spans (`{.qual}`)

Imladris encodes qualitative annotations as Pandoc bracketed spans so `quarto render` parses them as valid spans and `git diff` tracks them as plain text:

```markdown
[TP53 exhibits nuclear accumulation without transcriptional activation]{.qual id="q-8f3a" domain="protein" code="ptm-dysregulation" valence="negative" coder="antonio" confidence="high" ref="@doe2025"}
```

## Quarto YAML Frontmatter & Cross-References

Use `#fig-` and `#tbl-` identifiers to reference figures (`@fig-network`) and tables (`@tbl-irr`) in prose.

```yaml
---
title: "Translational Proteomics & Qualitative Adjudication"
bibliography: references.bib
format:
  html:
    toc: true
  pdf:
    documentclass: article
---
```
