<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# FlatPark Release Changelog (`io.github.Antux912012.Imladris`)

## [0.42.1] - 2026-11-23 — Stable Release (`stable` branch, `Apache-2.0`)

- **RTF Creation Crash Fix & Editor Parity:** Fixed deterministic `SIGSEGV` when creating `.rtf` (and `.txt`/`.csv`/`.tsv`) documents due to `null` `GtkSource.Language`, added RTF project scaffolding, UTF-8/non-BMP codec fixes, crash-recovery snapshotting, and PDF/ODT export button parity.
- **Security & Concurrency Hardening:** Closed plugin archive/community-installer consent bypasses and `readAsset` symlink escapes, eliminated Markdown raw-HTML XSS passthrough in `DocumentAdapter`, hardened `McpServer` workspace/output-path/D-Bus controls, removed credential propagation from `ExportService`, switched `export_native.c` PDF rendering to a thread-safe per-call `PangoFontMap`, and added mutex-protected static regexes and overflow-safe 64-bit disk helpers.
- **License Coherence:** Unified `Apache-2.0` licensing across `NativePreviewView.vala`, AppStream metainfo, NixOS `flake.nix`, and FlatPark metadata.

## [0.42.0] - 2026-11-22 — Stable Release (`stable` branch)

- **Elrond AI Hardware Auto-Optimizer:** 5-tier Vulkan GPU/iGPU/CPU probing via `llama-server --list-devices`, tailored launch profiles, 15s `/health` crash recovery with CPU fallback, and Preferences profile badge.
- **Flatpak Host Bridge & Kernel Routing:** Added `HostBridge` (`--watch-bus`), `EnvDiscovery` (`uv`, Conda, venv, `rig` R, Quarto), `ExecutionRouter` with Quarto/R/Python kernel selector, Host/Sandbox scope toggle, and unpinned latest R/CRAN support.
- **Redesigned Elrond AI Chat UI:** Native `Adw.ToolbarView`, searchable sessions, `Adw.StatusPage` empty state, floating composer with `@` mentions, 30ms streaming Markdown, collapsible reasoning row, and syntax-highlighted code blocks.

## [0.41.0] - 2026-11-22 — Stable Release (`stable` branch)

- **CLI and MCP Bridge:** Added `--mcp-server` to `imladris --help`. Added a D-Bus bridge (`io.github.Antux912012.Imladris.McpBridge`) so `--mcp-server` connects to open GUI windows.
- **Headless MCP Tools:** Added `file_path` support to `get_active_document`, `insert_text`, and `render_document`. Added `compile_latex` and `get_environment_summary` tools with `IMLADRIS_MCP_READONLY=1` and canonical path checks.
- **Quarto and Tectonic Toolchain:** Fixed `QUARTO_DENO_DOM` and `QUARTO_SHARE_PATH` in `configure_managed_env`. Added Tectonic bundle warmup during LaTeX setup and added a Verify Offline Readiness check in Preferences.
- **Science Packages and Profiles:** Added `scipy`, `duckdb`, `pyarrow`, `nbformat`, `ipywidgets`, and `openpyxl` to Python, and `r-rsqlite`, `r-duckdb`, `r-arrow`, and `r-openxlsx` to R. Added domain profiles and external Conda environment discovery.
- **Security and Model Controls:** Added Air-Gapped Mode, PHI/PII Data Lock, `/etc/imladris/policy.json` lock support, a Free LLM RAM button, and the `lfm25-1.2b` model directory fix.
- **Verified:** All 10/10 Meson test suites pass.

## [0.40.0] - 2026-11-20 — Most Stable Release (`stable` branch)

- **License Upgrade (`Apache-2.0` Hybrid Open-Core):** Relicensed Imladris Core Desktop Studio from `GPL-3.0-or-later` to `Apache-2.0` (`LICENSE`, `NOTICE`) with explicit patent protection, clean `JSC.Context`/`McpServer` extension boundaries, and Commercial Enterprise Pack readiness for pharma, biotech, and academic R&D.
- **Community Plugins Registry & In-App Browser:** Added `community-plugins/registry.json`, TypeScript declarations (`imladris.d.ts`), 3 starter plugins, and live search + 1-click installer in **Preferences → Extensions**.
- **Flatpak WebKitGTK 6.0 Live Preview Stability Fix:** Fixed `WebKit.WebContext.get_default()` initialization order prior to `JSC.Context` creation so live HTML/Markdown/Quarto previews render reliably inside Flatpak sandboxes (`org.gnome.Platform//51`).
- **VS Code & RStudio-Grade Autocompletion:** Implemented live keystroke `refilter()`, `GtkSource.Completion.fuzzy_highlight()`, Markdown/Quarto prose snippets & live document cross-references (`@fig-*`, `@tbl-*`, `@sec-*`, `@eq-*`), HTML5 tag & smart `</tag>` completion, R `library()` package & named parameter completion, Python DataFrame methods, live REPL column discovery, and paired `BackSpace`/triple-backtick handling.
- **Quick Table Picker Popover (`Ctrl+Alt+T`):** Cursor-anchored 8×8 hover grid and custom Rows/Cols dialog supporting Markdown, HTML, LaTeX, and RTF tables.
- **Deep Stability, Memory & UI Audit:** Fixed Command Palette actions/bridges, `.rtf` starter template & pending typing styles, NativePreview refresh, color swatch painting, dock crosshair drag sync, widget/singleton memory leaks, pooled session shutdown cleanup, and regex caching with **0 Vala compiler warnings**.
- **Verified:** All 10/10 Meson test suites passing inside `org.gnome.Sdk//51`.

## [0.33.1] - 2026-11-19

- Apple TextEdit-style WYSIWYG `.rtf` editor (`RtfCodec` + `RtfEditorView`).
- WebKitGTK 6.0 preview reparenting, scroll sync, and Flatpak finish-args alignment.
- Offline-first AI defaults (`OLLAMA`), `0600` `.shadow` recovery, and C/Vala security audit.

## [0.33.0] - 2026-11-18

- arXiv ID citation resolution, Keyboard Shortcuts dialog (`Ctrl+?`), DataGridViewer RFC-4180 CSV/TSV pagination, and Command Palette polish.
