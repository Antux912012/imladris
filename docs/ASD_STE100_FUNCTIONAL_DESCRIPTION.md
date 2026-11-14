<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Imladris v0.25.0 — Functional Description (ASD-STE100)

This document describes the functions of **Imladris v0.25.0** in Simplified Technical English (ASD-STE100).

## 1. Document Editor and Workbench
- **Single-Pane Focus Mode**: The application opens `.md` and `.html` files in a single-pane editor. This mode hides computational panels to reduce visual clutter.
- **Four-Quadrant Workbench Mode**: The application opens `.qmd`, `.Rmd`, `.ipynb`, `.R`, and `.py` files in four quadrants:
  1. **Top-Left (Source Editor)**: Edit code and text with syntax highlighting, code folding, and line numbers.
  2. **Bottom-Left (Console and Terminal)**: Run R, Python, Julia, SQL, and Bash commands in persistent sessions.
  3. **Top-Right (Environment and Bridges)**: Inspect active variables, command history, document outline, citations, and Galaxy datasets.
  4. **Bottom-Right (Files, Plots, and Preview)**: Browse project files, inspect Cairo plots, manage packages, and view live WebKitGTK 6.0 HTML output.
- **Adaptive Ribbon Toolbar**: Switch between *Home*, *Insert*, *Run*, *Publish*, *View*, and *Packages* tabs. Press `Ctrl+F1` to collapse or expand the ribbon.

## 2. Elrond AI Copilot and Direct Editor Writing
- **Direct Editor Writing (`Ctrl+Shift+E`)**: Elrond writes AI responses directly into the active editor buffer.
- **Selection and Chunk Actions**: Use *Apply to Selection*, *Update Active Chunk*, *Improve Writing*, *Refactor Code*, and *Fix Syntax*.
- **Quarto Option Preservation**: When Elrond updates a code chunk, it preserves `#|` YAML options (for example, `#| label:` and `#| fig-cap:`).
- **Single-Step Undo**: Press `Ctrl+Z` to revert an AI buffer edit in one step.
- **Multi-Provider AI & Quota Failover**: Connect local engines (`llama-server`, Ollama, LM Studio), **GitHub Copilot** (RFC 8628 OAuth Device Flow), or free-tier cloud providers (**Groq**, **Cerebras**, **OpenRouter `:free`**, **GitHub Models**, **FreeLLMAPI Local**). When a provider returns `HTTP 429`, `AiClient` switches to the next configured backup after explicit user privacy opt-in.

## 3. Reproducible Projects and Sandboxing
- **RStudio Compatibility**: Open and save `.Rproj` workspaces with 1:1 DCF field preservation.
- **Mallorn Bundles (`.mallorn`)**: Export and import portable project archives (`tar.zst` or `zip`) with path traversal validation.
- **Isolated Environments**: Manage project-local `renv` (R) and `.venv` (Python) environments from the *Packages* ribbon.
- **Jupyter Parity**: Open and save `.ipynb` (`nbformat 4.5`) notebooks while preserving cell IDs, execution counts, and outputs.

## 4. Scientific Domain Studios
- **Arekyer (Galaxy Bridge)**: Connect to `usegalaxy.eu`, `usegalaxy.org`, or `usegalaxy.org.au` with `libsecret-1` keys and insert `httr2` or `pandas` ingestion chunks.
- **Yavanna (Bio-Entity & RT-qPCR)**: Calculate primer $T_m$, GC%, and molecular weight, and query UniProtKB and Ensembl GRCh38.
- **Taniquetil (AlphaFold DB)**: Search protein structures, plot pLDDT confidence tracks, and generate `bio3d` (R) or `biotite` (Python) scripts.
- **Elbereth (ICH E9 Biostatistics)**: Calculate sample size and power curves, and generate CDISC ADSL/ADTTE code blocks.
- **MathChem (`Ctrl+M`) & Visual Flow (`Ctrl+Shift+D`)**: Convert natural expressions to LaTeX/mhchem (`\ce{...}`) and sync Cairo flowcharts with Mermaid blocks.

## 5. Publishing, Security, and Privacy
- **Multi-Format Export**: Export documents to HTML, PDF, OpenDocument Text (`.odt`), OpenDocument Presentation (`.odp`), and `.rtf`.
- **GxP Provenance**: Generate SHA-256 lockfiles (`<document>.provenance.lock.json`) on export.
- **Model Context Protocol (`--mcp-server`)**: Run a stdio MCP server with `execute_code` disabled by default (`IMLADRIS_MCP_ALLOW_EXEC=1` opt-in).
- **Zero Telemetry & GDPR Art. 17**: The application sends no telemetry on startup. Run `imladris --purge-user-data` to erase local settings, caches, and keyring secrets.
