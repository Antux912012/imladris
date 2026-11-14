# Changelog

All notable changes to **Imladris** are documented in this file.

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
