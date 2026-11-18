# Changelog

All notable changes to **Imladris** are documented in this file.

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
