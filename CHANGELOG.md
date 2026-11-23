# Changelog

All notable changes to **Imladris** are documented in this file.

## [0.42.1] - 2026-11-23

### Fixed
- **RTF Creation Crash (`SIGSEGV`) & Editor Parity:** Guarded `GtkSource.Buffer` construction when `GtkSource.LanguageManager` returns `null` (fixing crashes when creating `.rtf`, `.txt`, `.csv`, and `.tsv` documents), added `DocumentFormat.RTF` template generation in `ProjectScaffolder`, fixed non-UTF-8 CP1252 byte handling and non-BMP UTF-16 surrogate serialization in `RtfCodec`, cleared stale pending text/highlight colors on cursor movement in `RtfEditorView`, wired RTF crash-recovery snapshotting, routed ribbon/MCP/Math/Mermaid/AI insertions through `rtf_editor`, and enabled PDF/ODT export buttons for `.rtf` files.
- **Security & Sandbox Hardening (EGM Audit):** Closed plugin permission consent bypasses in `PluginManager` (archive duplicate-manifest/zip-bomb checks, post-download permission subset verification, `realpath()` confinement on `readAsset`, removal of CWD registry fallback, safe JSC value passing, and JSON type validation), eliminated raw-HTML XSS passthrough and sentinel collisions in `DocumentAdapter`, required explicit `IMLADRIS_MCP_WORKSPACE` and output-path validation in `McpServer`, enforced `IMLADRIS_MCP_READONLY` and audit logging on `McpDbusBridge`, and removed `GALAXY_API_KEY` injection and unprompted `tinytex` installs from `ExportService`.
- **Thread Safety & C Memory Safety:** Switched `imladris_export_render_pdf` in `export_native.c` to a per-call `PangoFontMap`/`PangoContext` with UTF-8 validation and partial-ZIP cleanup on error, protected static `GLib.Regex` caches with `GLib.Mutex` in `DocumentAdapter` and `ExportService`, and used checked 64-bit arithmetic in `toolchain_native.c`.
- **License & Packaging Alignment:** Aligned `NativePreviewView.vala` SPDX header and `flake.nix` metadata to `Apache-2.0`, and synchronized version `0.42.1` across Flatpak/FlatPark, `.deb`, `.rpm`, AUR `PKGBUILD`, and NixOS `flake.nix`.

## [0.42.0] - 2026-11-22

### Added
- **Elrond AI Hardware Auto-Optimizer:** Added `ElrondHardwareProbe` (`llama-server --list-devices` async probing, `/proc/meminfo` & CPU core detection, 5-tier NVIDIA/AMD/Intel Arc/iGPU/CPU classification), `ElrondOptimizer` flag profiles, `elrond-auto-optimize` and `elrond-compute-mode` GSettings keys, 15-second `/health` crash recovery with automatic CPU fallback + `Adw.Toast`, and an active hardware profile badge in Preferences.
- **Flatpak Host Bridge & Kernel Routing (`HostBridge`, `EnvDiscovery`, `ExecutionRouter`):** Added `--watch-bus` `flatpak-spawn --host` abstraction, single-shot host probe for `.venv`, `uv`, `~/.conda/environments.txt`, `renv`, multi-version `rig` R (`/opt/R/*/bin/Rscript`), and Quarto, plus Quarto/R/Python kernel selection, **Rescan Environments**, and a Host/Sandbox scope toggle in the Environment panel.
- **Redesigned Elrond AI Chat Panel (`ElrondChatPanel`, `ElrondChatWidgets`, `elrond-chat.css`):** Native `Adw.ToolbarView` with `.flat` `Adw.HeaderBar`, searchable session popover, `Adw.StatusPage` empty state with starter pills, floating `ElrondComposer` with removable context chips, `@` attachment popover, model/hardware pill, context usage meter, circular Send/Stop button, collapsible `Gtk.Expander` thinking row, `30ms` throttled streaming Markdown, read-only `GtkSource.View` code blocks, and smart auto-scroll.

### Changed
- **Latest R & CRAN Parity:** Unpinned `r-base` in `ToolchainManager` (`r_ver = "latest"`) so managed R installations track the latest R and CRAN releases 1-to-1.
- **Deep Codebase Audit & Optimization:** Consolidated `bytes_to_string` and `flatpak-spawn` wrappers onto `PlatformUtils`/`HostBridge`, cached `GLib.Regex` instances in `AiClient`, `RtfCodec`, `ExportService`, `DoiBibService`, `CitationCompletionProvider`, `MathChemEngine`, and `ElrondHardwareProbe`, and added explicit HTTP timeouts on `PackageIndexCache`.

## [0.41.0] - 2026-11-22

### Added
- **CLI and MCP Bridge:** Added `--mcp-server` to `imladris --help`. Added a D-Bus bridge (`io.github.Antux912012.Imladris.McpBridge`) so `--mcp-server` connects to open GUI windows.
- **Headless MCP Tools:** Added `file_path` support to `get_active_document`, `insert_text`, and `render_document`. Added `compile_latex` and `get_environment_summary` tools.
- **MCP Security and Audit Controls:** Added `IMLADRIS_MCP_READONLY=1`, `IMLADRIS_MCP_AUDIT=1` metadata-only JSONL logging, and `realpath()` workspace boundary checks.
- **Science Packages and Profiles:** Added `scipy`, `duckdb`, `pyarrow`, `nbformat`, `ipywidgets`, and `openpyxl` to the Python toolchain, and `r-rsqlite`, `r-duckdb`, `r-arrow`, and `r-openxlsx` to R. Added domain profiles (`QUANT_FINANCE`, `ECOLOGY_SPATIAL`, `CLINICAL_BIOSTATS`, `BIOINFORMATICS`) and external Conda environment discovery.
- **Air-Gapped Policy and PHI Lock:** Added Air-Gapped Mode, PHI/PII Data Lock, `/etc/imladris/policy.json` administrator lock support, Verify Offline Readiness check, and Free LLM RAM control in Preferences.

### Fixed
- **Quarto and Tectonic Toolchain:** Fixed `QUARTO_DENO_DOM` and `QUARTO_SHARE_PATH` in `configure_managed_env`. Added Tectonic bundle warmup during LaTeX setup for offline PDF and Beamer builds.
- **Local Model Naming:** Renamed `lfm25-12b` to `lfm25-1.2b` (and `1.5b`/`1.7b` IDs) with fallback lookup for existing model folders.

## [0.40.0] - 2026-11-20

### Changed
- **Apache-2.0 Hybrid Open-Core Licensing**: Relicensed Imladris Core Desktop Studio from `GPL-3.0-or-later` to **Apache License 2.0 (`Apache-2.0`)** with explicit patent protection (`LICENSE`, `NOTICE`), clean `JSC.Context` / `McpServer` extension boundaries, and Commercial Enterprise Pack readiness for pharma, biotech, and regulated R&D teams. Updated About dialog (`Gtk.License.APACHE_2_0`), AppStream metadata, `README.md`, landing page (`docs/index.html`), and Wiki (`License-and-Enterprise-Policy.md`).

### Added
- **Community Plugins Registry & In-App Marketplace (`community-plugins/`)**: Added `community-plugins/registry.json`, TypeScript ambient declarations (`community-plugins/types/imladris.d.ts`), 3 starter TypeScript/JavaScript plugins, live search & 1-click installer in **Preferences → Extensions** (with HTTPS validation and permission consent dialogs), and reworked the Plugin Development Wiki.
- **VS Code & RStudio-Grade Autocompletion**: Implemented live keystroke `refilter()`, `GtkSource.Completion.fuzzy_highlight()`, Markdown/Quarto prose snippets & live document cross-references (`@fig-*`, `@tbl-*`, `@sec-*`, `@eq-*`), HTML5 tag & smart `</tag>` completion, R `library()` package & named function argument completions, Python pandas DataFrame methods, live REPL DataFrame column discovery (`$` / `.`), paired `BackSpace` deletion, and triple-backtick chunk completion.
- **Quick Table Picker Popover (`Ctrl+Alt+T`)**: Cursor-anchored 8×8 hover grid and custom Rows/Cols dialog (`PopoverFactory.create_table_picker_popover`) with format-aware Markdown, HTML, LaTeX, and RTF table generation from the toolbar, editor context menu, and Command Palette.

### Fixed
- **Flatpak WebKitGTK 6.0 Live Preview**: Fixed `WebKit.WebContext.get_default()` vs. `JSC.Context` initialization ordering in `Application` and `PluginManager` so live preview renders reliably in Flatpak sandboxes.
- **Deep Codebase Audit (Memory, GUI Glitches, Performance & Zero Warnings)**: Fixed Command Palette `win.insert_table` & bridge snippet wiring, RTF starter template & pending typing styles, RTF Undo/Redo/Clipboard/Heading routing, NativePreview un-hide refresh, color palette swatch painting, `Adw.ButtonContent` inline buttons, `RStudioDockGrid` crosshair drag sync, `DocumentPage`/dock/theme/datagrid reference cycles and singleton signal leaks, `Application.shutdown()` pooled R/Python & Shiny cleanup, `CodeIntelliSenseEngine`/`NativePreviewView` regex caching and Pango markup safety, and eliminated all Vala compiler warnings (`Ok: 10, Fail: 0`).

## [0.33.1] - 2026-11-19

### Added
- **Apple TextEdit-Style WYSIWYG `.rtf` Editor**: Added `RtfCodec` (RTF 1.x parser, serializer, and HTML renderer) and `RtfEditorView` (font family/size, Bold/Italic/Underline/Strikethrough with `Ctrl+B`/`I`/`U`, text & highlight colors, paragraph alignment, bullet lists, pending typing attributes, and WebKitGTK 6.0 live preview), plus `app.new_rtf` and `application/rtf;text/rtf;` desktop MIME registration.
- **Unified Single-Package Toolchain**: Integrated `R`, `Python`, `pip`/`venv`, `Pandoc`, `curl`, `bzip2`, and `git` runtime dependencies directly into the main `.deb`, `.rpm`, AUR `PKGBUILD`, and Nix Flake packages (`Provides: imladris-toolchain`).
- **Scientific Software Paper**: Added `docs/paper/imladris-scientific-paper.qmd` detailing architecture, `FormatProfile`, dual-mode docking, `nbformat` 4.5 notebooks, bioinformatics/clinical biostatistics case studies, security, and verification.

### Fixed
- **WebKitGTK 6.0 Live Preview & Flatpak Parity**: Fixed `unrealize`/`map` reparenting reloads across Apostrophe ↔ RStudio transitions, zero-allocation deferral during `Gtk.Revealer`/`Gtk.Paned` animations, `load_failed` cancelled-load filtering, `preview_load_generation` async race guard, proportional editor-to-preview scroll sync, ribbon toggle sync (`btn_preview`, `chk_console`, mode buttons), and Flatpak manifest `WEBKIT_DISABLE_DMABUF_RENDERER=1` parity.
- **Security, Privacy & C/Vala Memory Audit**: Defaulted `AiConfigManager` to local/offline (`AiProvider.OLLAMA`, `auto_failover_enabled = false`), preserved `detail_prompt` on failover, isolated `GALAXY_API_KEY` from child process environments, sanitized Galaxy/Elbereth/Yavanna/Taniquetil code generators, enforced `PluginManager` permissions, set `0600` on `.shadow` recovery files, added `G_MAXUINT32`/`G_MAXUINT16` bounds and UTF-8 validation in `export_native.c`, fixed session refcount leaks (`release_session`/`peek_for_key`), and cleaned up destructors/FDs/signal handlers.
- **Citations, Export & Execution**: Resolved `bibliography/references.bib` in Zotero/DOI sync, fixed CAYW locator conversion (`\cite[loc]{key}`), escaped PubMed BibTeX values, added pre-2007 arXiv ID support, passed `TEXINPUTS`/`BIBINPUTS` for unsaved `.tex` PDF exports, fixed `ChunkExecutionEngine` error detection, and fixed inline Markdown code/math ordering in `DocumentAdapter`.

## [0.33.0] - 2026-11-18

### Added
- **arXiv ID Citation Resolution**: `DoiBibService` now resolves `arXiv:XXXX.XXXXX` identifiers via `export.arxiv.org/api/query` alongside DOIs and PubMed PMIDs, with Latin diacritic transliteration for citekeys and LaTeX special-character escaping.
- **Keyboard Shortcuts Dialog (`Ctrl+?`)**: Added a Libadwaita Keyboard Shortcuts dialog (`app.shortcuts`) and surfaced **New Deck or Poster Template...** directly on the Welcome Dashboard and File → New menu.
- **R/Biostatistics Editor Shortcuts & Python Data Science Defaults**: Added `Alt+-` (` <- `) and `Ctrl+Shift+M` (` |> `) in `DocumentPage`, and included `numpy`, `pandas`, and `matplotlib` in `ToolchainComponent.PYTHON`.

### Fixed
- **LaTeX Build, Export & `@` Completion**: Added 3rd-pass BibTeX/Biber resolution (`Rerun to get` check) in `LatexBuildRunner`, routed `.tex` PDF exports in `ExportService` through LaTeX engines instead of Pandoc/Markdown, fixed HeaderBar TeX engine selection (`latexmk`/`xelatex`/`pdflatex`/`HTML`) and multi-citation Zotero `;` → `,` conversion, fixed `CitationCompletionProvider` to insert `\cite{...}` without injecting YAML frontmatter into `.tex` files, and added `mhchem`/`algorithm` while removing obsolete `inputenc` in `LatexTemplates`.
- **DataGridViewer & Polyglot Environment**: Added RFC-4180 CSV/TSV parsing, local-file pagination, R `rownames()` support, `NA`/`NaN`/`Inf` numeric sort handling, 2D shape checks for Python matrices, capped R `str()` summaries, `polyglot` preservation in `.qmd`/`.ipynb`, `DataGridViewer` pop-in re-mounting, and recursive non-empty directory deletion.
- **Preferences, Command Palette & Onboarding UX**: Fixed `PreferencesDialog` AI provider enum mapping across all 19 providers, aligned temperature range (`0.0..2.0`), initialized live Elrond status, fixed `CommandPaletteDialog` shortcuts/markup/24-item cap with tokenized search, and respected explicit **Skip** in `OnboardingTourDialog`.

## [0.32.0] - 2026-11-18

### Added
- **Top 10 LaTeX Publisher Templates & Top 10 Citation Styles**: Added `LatexTemplates` and `LatexTemplateDialog` supporting IEEE, ACM (`acmart`), Springer LNCS (`llncs`), Elsevier (`elsarticle`), Nature, PLOS ONE, APS (`revtex4-2`), NeurIPS, ICML, and MDPI templates paired with IEEE, APA 7th, Nature, Science, ACM, `splncs04`, `elsarticle-num`, Vancouver, Chicago (BibLaTeX), and APS citation styles.
- **GNOME Tour–Style First-Launch Onboarding**: Added `OnboardingTourDialog` with an `Adw.Carousel` feature walkthrough shown automatically on first launch (`onboarding_tour_completed`) and accessible anytime via **Feature Tour...**.
- **Open-Source Presentation & Beamer Templates**: Expanded `PresentationTemplateDialog` with LaTeX Beamer (Metropolis, Defense, Lightning Talk), Markdown (Marp, Academic Lecture, RevealJS, Quarto Beamer), TypeScript (Reveal.js & Slidev programmatic decks), and Typst templates.

### Fixed
- **FFI & Null-Safety Hardening**: Fixed `GenericArray<string>.data` non-null-terminated `strv` calls in `PackagesRibbonBar`/`Window`, null optional regex capture `SIGSEGV` in `NativeCore.extract_outline_json`, null JSON `"content"` handling in `ElrondEngineController`, and NULL guards in `export_native.c`.
- **Security & Subprocess Hardening**: Escaped backslashes in `ExportService` `Rscript -e` expressions, fixed `MallornManager` `tar -tvf` member parsing for filenames with spaces, blocked path-qualified binaries in `McpServer.execute_code`, preserved symlinks safely in `SandboxController.copy_directory_tree`, and moved `ToolchainManager` micromamba downloads into private `0700` `mkdtemp` directories with `finally` cleanup.
- **UI & Test Isolation**: Fixed unescaped Pango `&` markup warnings (`use_markup = false`), dialog parent/close handling in `AiSettingsDialog` and `PreferencesDialog`, `XDG_CACHE_HOME` respect in `PlatformUtils.get_shared_cache_dir`, and standalone test XDG isolation.

## [0.31.1] - 2026-11-18

### Fixed
- **Crash on New Document Creation**: Fixed a `SIGSEGV` in `DocumentPage.ensure_bundled_language_specs()` caused by passing a non-null-terminated `GLib.GenericArray<string>.data` pointer array to `GtkSource.LanguageManager.set_search_path()` (`g_strdupv()`), replacing it with a null-terminated Vala `string[]` array.

## [0.31.0] - 2026-11-18

### Added
- **Interactive Micromamba Toolchain Setup**: Opens in selection mode on startup so users can pick Python, R, LaTeX, HTML/CSS, TypeScript, and Quarto, update installed components, and install/switch between Python versions (`3.12`, `3.11`, `3.10`, `3.9`).
- **Native C GNU/Linux Toolchain Backend**: `toolchain_native.c` using `uname(2)`, `statvfs(2)`, `fts(3)` hardlink-deduplicated disk usage, and `conda-meta` version scanning.
- **Out-of-the-Box PDF, ODT, and RTF Export**: Built-in Cairo + Pango A4 vector PDF renderer and zero-dependency zlib PKZIP OASIS ODT packager in `export_native.c` (`ExportService`), plus enhanced RTF formatting.

### Fixed
- **GTK4 Deprecations & Code Hygiene**: Replaced `Gtk.FileChooserNative` with `Gtk.FileDialog` in `ToolchainSetupDialog`, and removed dormant unused symbols.

## [0.30.0] - 2026-11-18

### Added
- **Additional document formats**: Added format detection and editor profiles for plain text, CSV, TSV, `.Rproj`, and `.bibliography` files.
- **Configurable AI generation**: Added Gemini account model discovery and selection, plus shared response-detail and temperature controls.
- **Managed local GGUF models**: Added ten Hugging Face model presets, quantization fallback, streamed downloads, and Imladris-managed `llama-server` startup. Compact models use capped context/KV caches, single-sequence CPU inference, disabled auto-fit, and mmap defaults for low-memory systems.
- **Selectable scientific toolchains**: Added a persistent install-folder chooser and component-aware completion so users can install only the R, Python, Quarto, Node/TypeScript, or TeX runtimes they need.

### Fixed
- **Elrond provider routing**: A ready local Elrond bridge no longer intercepts requests when the selected cloud provider (including Gemini) is configured.

## [0.27.1] - 2026-11-16

### Fixed
- **GitHub CI & Offline Rust Build**: Anchored `.gitignore` `repo/`/`build/`/`target/` rules and re-vendored `rust/imladris_core/vendor` (`syn/tests/repo/mod.rs`) so `cargo build --release --offline` inside Flatpak Builder succeeds.
- **FlatPark Packaging & Toolchain Add-on**: Marked `io.github.Antux912012.Imladris.Toolchain` with `no-autodownload: true` and bumped release version to trigger a clean FlatPark `extra-data` sync.

## [0.27.0] - 2026-11-16

### Added
- **Elrond AI Enhancements**: Local intent routing, multi-turn conversation history, and SSE token streaming.
- **Rust Core Manuscript Analytics**: Zero-copy line parsing, expanded Quarto engines/options, and `imladris_analyze_manuscript_json` exposed in VAPI and `NativeCore`.
- **Distribution Toolchain Packaging**: Added `.deb`/`.rpm` toolchain meta-packages, Flatpak Toolchain add-on extension, and updated editorial landing page.

## [0.26.0] - 2026-11-15">

### Added
- **Hybrid Rust Core (`imladris_core`)**: CommonMark/GFM/math/Mermaid HTML renderer, lossless `.ipynb` round-trip serializer, YAML frontmatter parser, LaTeX outline analyzer, and TypeScript symbol analyzer exposed via C-ABI.
- **Format-Adaptive UI (`FormatProfile`)**: Adaptive ribbon, headerbar, comment toggles, and `GtkSourceView 5` language specs across `.qmd`, `.Rmd`, `.ipynb`, `.md`, `.tex`, `.ts`, and `.html`.
- **LaTeX & TypeScript Runners (`LatexBuildRunner`, `TypeScriptRunner`)**: Native `latexmk`/`xelatex`/`lualatex`/`pdflatex` compilation with `.log` diagnostics and `tsx`/`node`/`deno`/`bun`/`tsc` execution & typechecking.

### Fixed & Hardened
- Sequential chunk execution with `Gtk.TextMark` anchoring, `\uFFFC` clean-text extraction, per-tab/project `PersistentSessionManager` pooling, and polyglot R + Python `EnvironmentController`.
- `ExportService` real error propagation, LibreOffice `-env:UserInstallation` isolation, `_quarto.yml` `output-dir` resolution, and `.venv` Python preservation.
- Flatpak `--talk-name=org.freedesktop.Flatpak` & `--filesystem=xdg-cache/imladris:create`, `MallornManager` symlink archive rejection, `PluginManager` pre-extraction manifest/zip validation, `PackagesRibbonBar` CRAN/GitHub identifier validation, and `RecoveryService` SHA-256 IDs + mutex/generation locking.

## [0.25.0] - 2026-11-14

### Functions Added
- **Free-Tier AI APIs & Automatic Quota Failover (`AiConfigManager`, `AiClient`)**:
  - Built-in support for permanent free-tier cloud & local providers: **Groq**, **Cerebras**, **OpenRouter `:free`**, **GitHub Models**, and **FreeLLMAPI Local Proxy**.
  - Automatic `HTTP 429` / quota-exhaustion cascading from the active provider to configured free-tier backups.
  - Explicit privacy opt-in (`free_api_consent_accepted`) required before routing prompts to external free-tier APIs.
- **GitHub Copilot OAuth Device Flow (`CopilotAuthService`)**:
  - RFC 8628 GitHub Device Flow authentication (`https://github.com/login/device`) integrated directly into AI Settings.
  - Secure token persistence in the system keyring via `libsecret-1` (`io.github.Antux912012.Imladris.Copilot`) with OpenAI-compatible Copilot chat completions.
- **Positron / RStudio-Style Direct Editor Writing (`AiBufferEditHelper`, `ElrondChatPanel`)**:
  - Direct in-buffer editing actions from Elrond AI: **Apply to Selection**, **Update Active Chunk**, **Improve Writing**, **Refactor Code**, and **Fix Syntax**.
  - Preserves Quarto `#|` chunk options (e.g., `#| label:`, `#| fig-cap:`, `#| echo:`) and wraps buffer mutations in a single `Ctrl+Z` undo action.

### Improvements
- **Unified Elrond AI Workflow**: Removed the legacy inline editing popover in favor of the unified Positron-style Direct Editor Writing workflow in Elrond AI.
- **Product Positioning, About Dialog & Metadata Rework**: Updated `Adw.AboutDialog`, ribbon/input tooltips, AppStream metadata (`metainfo.xml`), `.desktop` keywords, `.deb`/`.rpm`/AUR descriptions, `README.md`, and the landing page.
- **Zero-Phone-Home Startup (`PackageIndexCache`)**: Deferred package index fetching to on-demand queries instead of probing network endpoints on application startup.

### Bugs Fixed
- **MCP Execution Hardening (`McpServer`)**: Disabled `execute_code` by default behind `IMLADRIS_MCP_ALLOW_EXEC=1` and enforced a strict interpreter binary allowlist (`Rscript`, `python3`, `quarto`).
- **Galaxy API Key Isolation (`Arekyer` / `Window`)**: Scoped `GALAXY_API_KEY` injection exclusively to targeted child subprocesses rather than mutating the parent process environment.
- **Mallorn Zip Slip Mitigation (`MallornManager`)**: Added canonical path validation when extracting `.mallorn` archives to prevent directory traversal (`../`) writes.
- **Shell-Free `micromamba` Bootstrap (`ToolchainSetupDialog`)**: Replaced shell-piped `curl | tar` execution with native `Soup.Session` download + `libarchive` extraction.
- **File Save Integrity (`DocumentPage`)**: Stripped `\uFFFC` widget anchor characters before writing document buffers to disk.
- **Dock Popout & Tab-Close Lifecycle (`RStudioDockGrid`, `Window`)**: Fixed widget reparenting/stealing when popping dock panels out and resolved window leaks on tab close.
- **Command Palette & Document Adapter Fixes**: Fixed `CommandPaletteDialog` action prefix mismatches and eliminated static race conditions in `DocumentAdapter`.

---

## [0.24.2] - 2026-11-13
- Embedded all 118 required Papirus symbolic SVG icons via GResource for consistent rendering across any desktop icon theme.

## [0.24.1] - 2026-11-13
- Updated AppStream, FlatPark, About dialog, and package homepage URLs to `https://antux912012.github.io/imladris/`.

## [0.24.0] - 2026-11-13
- Resolved WebKitGTK 6.0 & GTK4 Live Preview rendering across `.qmd`, `.md`, `.Rmd`, and `.html` documents, lifecycle-safe dock reparenting, and Quarto fenced callout rendering.
