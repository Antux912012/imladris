<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# FlatPark Release Changelog (`io.github.Antux912012.Imladris`)

## [0.40.0] - 2026-11-20 — Most Stable Release (`stable` branch)

- **License Upgrade (`Apache-2.0` Hybrid Open-Core):** Relicensed Imladris Core Desktop Studio from `GPL-3.0-or-later` to `Apache-2.0` (`LICENSE`, `NOTICE`) with explicit patent protection, clean `JSC.Context`/`McpServer` extension boundaries, and Commercial Enterprise Pack readiness for pharma, biotech, and academic R&D.
- **Flatpak WebKitGTK 6.0 Live Preview Stability Fix:** Fixed `WebKit.WebContext.get_default()` initialization order prior to `JSC.Context` creation so live HTML/Markdown/Quarto previews render reliably inside Flatpak sandboxes (`org.gnome.Platform//51`).
- **VS Code & RStudio-Grade Autocompletion:** Implemented live keystroke `refilter()`, `GtkSource.Completion.fuzzy_highlight()`, Markdown/Quarto prose snippets & live document cross-references (`@fig-*`, `@tbl-*`, `@sec-*`, `@eq-*`), HTML5 tag & smart `</tag>` completion, R `library()` package & named parameter completion, Python DataFrame methods, live REPL column discovery, and paired `BackSpace`/triple-backtick handling.
- **Quick Table Picker Popover (`Ctrl+Alt+T`):** Cursor-anchored 8×8 hover grid and custom Rows/Cols dialog supporting Markdown, HTML, LaTeX, and RTF tables.
- **Verified:** All 10/10 Meson test suites passing inside `org.gnome.Sdk//51`.

## [0.33.1] - 2026-11-19

- Apple TextEdit-style WYSIWYG `.rtf` editor (`RtfCodec` + `RtfEditorView`).
- WebKitGTK 6.0 preview reparenting, scroll sync, and Flatpak finish-args alignment.
- Offline-first AI defaults (`OLLAMA`), `0600` `.shadow` recovery, and C/Vala security audit.

## [0.33.0] - 2026-11-18

- arXiv ID citation resolution, Keyboard Shortcuts dialog (`Ctrl+?`), DataGridViewer RFC-4180 CSV/TSV pagination, and Command Palette polish.
