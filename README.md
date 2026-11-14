<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

<p align="center">
  <img src="data/icons/hicolor/256x256/apps/io.github.Antux912012.Imladris.png" alt="Imladris Logo" width="128" height="128">
</p>

<h1 align="center">Imladris</h1>
<h3 align="center">The Native Linux Scientific Workbench &amp; Polyglot Notebook Studio</h3>

<p align="center">
  <em>Sub-second startup. Zero Electron overhead. High-density scientific authoring from cloud genomics to clinical biostatistics.</em>
</p>

<p align="center">
  <a href="https://antux912012.github.io/imladris/"><img src="https://img.shields.io/badge/Website-Landing%20Page-88C0D0?style=flat-square&logo=googlechrome&logoColor=white" alt="Landing Page"></a>
  <a href="https://flatpark.org/apps/io.github.Antux912012.Imladris/"><img src="https://img.shields.io/badge/Flatpark-io.github.Antux912012.Imladris-4B89AC?style=flat-square&logo=flatpak&logoColor=white" alt="Flatpark"></a>
  <a href="https://github.com/Antux912012/imladris/wiki"><img src="https://img.shields.io/badge/Docs-Technical%20Wiki-5E81AC?style=flat-square&logo=readthedocs&logoColor=white" alt="Technical Wiki"></a>
  <a href="https://github.com/Antux912012/imladris/releases/tag/v0.25.0"><img src="https://img.shields.io/badge/Release-v0.25.0-blue?style=flat-square" alt="Release v0.25.0"></a>
  <img src="https://img.shields.io/badge/GTK4%20%2F%20Libadwaita-1.5%2B-blue?style=flat-square" alt="Toolkit">
  <img src="https://img.shields.io/badge/Vala-0.56%2B-green?style=flat-square" alt="Vala">
  <img src="https://img.shields.io/badge/License-GPL--3.0--or--later-brightgreen?style=flat-square" alt="License">
</p>

<p align="center">
  <strong><a href="https://antux912012.github.io/imladris/">🌐 Official Landing Page</a></strong> ·
  <strong><a href="https://github.com/Antux912012/imladris/releases/tag/v0.25.0">⬇️ Download v0.25.0 (.deb / .rpm / Flatpak / AUR)</a></strong> ·
  <strong><a href="https://flatpark.org/apps/io.github.Antux912012.Imladris/">📦 Install from Flatpark</a></strong> ·
  <strong><a href="https://github.com/Antux912012/imladris/wiki">📖 Technical Wiki</a></strong> ·
  <strong><a href="docs/IMLADRIS_PRODUCTION_ARCHITECTURE_BLUEPRINT.md">🏗️ Production Blueprint</a></strong>
</p>

---

## Why Imladris?

Modern scientific computing forces an inefficient compromise: Electron-based editors consume 1–2 GB of system RAM before opening a dataset, while lightweight text editors lack interactive REPLs, reproducible package sandboxes, and scientific domain tooling.

**Imladris** is engineered in compiled **Vala**, **GTK4**, **Libadwaita**, **GtkSourceView 5**, and **WebKitGTK 6.0**. It delivers a native, sub-second scientific desktop studio that leaves workstation memory and GPU resources dedicated to statistical computation, genomic matrices, and local model inference.

### Comparative Workflow Matrix

| Dimension | Legacy Desktop IDEs (Electron / Java) | The Imladris v0.25.0 Approach |
| :--- | :--- | :--- |
| **Idle Memory Overhead** | 1.2–2.5 GB RAM idle | **< 120 MB RAM** (native compiled Vala/GTK4 binary) |
| **Cold Startup Latency** | 4.0–9.0 seconds | **< 0.6 seconds** instant launch |
| **AI In-Editor Writing** | Locked to proprietary cloud subscriptions | **Positron-style Direct Editor Writing** + **GitHub Copilot OAuth** + **Free-Tier Quota Failover** (Groq/Cerebras/OpenRouter) + **Local llama.cpp** |
| **Editor Ergonomics** | Generic web view or rigid legacy panels | **Dual-Mode Workbench**: Distraction-Free Focus Writer for Markdown, 4-Quadrant Workbench for Quarto, R, and Python |
| **Cloud Genomics Integration**| Manual browser downloads breaking provenance | **Arekyer Galaxy Bridge**: Native `libsecret` token storage + verified `httr2`/`pandas` provenance code injection |
| **Clinical Biostatistics** | External calculators and scripts | **Elbereth Studio**: Native ICH E9 sample size calculations, power curves, and CDISC ADaM table generators |
| **Environment Portability** | Machine-dependent state drift | **1:1 RStudio `.Rproj` compatibility**, portable `.mallorn` bundles, and sandboxed `renv`/`venv` managers |

> **Note:** Imladris is an independent open-source software project. It is not affiliated with, sponsored by, or endorsed by Posit PBC, RStudio, Project Jupyter, or the Galaxy Project.

---

## Tailored for Scientific Personas

### For Clinical Biostatisticians & Epidemiologists
* **Regulatory Compliance & GxP Lockfiles**: Automatic cryptographic SHA-256 provenance manifests (`<document>.provenance.lock.json`) generated on export.
* **ICH E9 Statistical Power Models**: Calculate sample sizes and statistical power (Two-Sample Continuous, Proportions with Casagrande-Pike correction, Schoenfeld Log-Rank Survival) with live Cairo power curves.
* **CDISC Code Generators**: Rapid generation of compliant ADSL Table 1 summary demographics, ADTTE Kaplan-Meier survival curves, and Cox Proportional Hazards regression blocks.

### For Bioinformaticians & Genomic Data Scientists
* **Native Galaxy Project Integration**: Connect securely to `usegalaxy.eu`, `usegalaxy.org`, or `usegalaxy.org.au` via `libsecret-1` to inspect history datasets and inject programmatic retrieval code.
* **AlphaFold DB & PDB Inspection**: Fetch DeepMind / EMBL-EBI structures directly into the workbench with per-residue pLDDT confidence visualization and R `bio3d` / Python `biotite` script generation.
* **Yavanna Bio-Entity & RT-qPCR Studio**: Live UniProtKB and Ensembl GRCh38 querying, alongside oligo length, GC%, melting temperature ($T_m$), and molecular weight calculations.

### For Data Science Practitioners & Technical Authors
* **Direct Editor Writing (`Ctrl+Shift+E`)**: Stream AI-generated code directly into active code chunks or document selections while strictly preserving Quarto cell options (`#|`) and enabling single-step `Ctrl+Z` undo.
* **Zero-Cost AI Failover**: Built-in support for permanent free-tier API endpoints (Groq, Cerebras, OpenRouter `:free`, GitHub Models) with automatic HTTP 429 quota cascading.
* **Lossless Jupyter Parity**: Round-trip `.ipynb` (`nbformat 4.5`) support that maintains cell IDs, execution counts, outputs, and metadata without conversion loss.

---

## What’s New in v0.25.0

* **Free-Tier AI Orchestration & Automatic Quota Failover**: Configure permanent free-tier providers (**Groq**, **Cerebras**, **OpenRouter `:free`**, **GitHub Models**, and **FreeLLMAPI Local Proxy**). When a primary provider encounters rate limits (`HTTP 429`) or quota exhaustion, `AiClient` cascades automatically to verified backups under explicit user privacy consent.
* **GitHub Copilot OAuth Device Flow**: Authenticate directly from **AI Settings** using RFC 8628 GitHub Device Flow (`https://github.com/login/device`), with credentials secured in `libsecret` (`io.github.Antux912012.Imladris.Copilot`).
* **Positron/RStudio-Style Direct Editor Writing**: Direct in-buffer transformations via Elrond AI: **Apply to Selection**, **Update Active Chunk** (preserving Quarto `#|` cell options and buffer undo history), and one-click actions (*Improve Writing*, *Refactor Code*, *Fix Syntax*).
* **Security & Data-Integrity Hardening**: MCP `execute_code` disabled by default (`IMLADRIS_MCP_ALLOW_EXEC=1` opt-in with strict binary allowlist), `.mallorn` Zip Slip path traversal mitigation, shell-free `micromamba` bootstrap, `\uFFFC` anchor cleanup on file save, and dock panel lifecycle stability fixes.

See [`CHANGELOG.md`](CHANGELOG.md) for the full breakdown of functions added, improvements, and bugs fixed.

---

## Visual Overview

<p align="center">
  <img src="data/screenshots/imladris-screenshot.png" alt="Imladris 4-Pane Scientific Workbench with Redesigned Elrond AI" width="100%">
  <em>Figure 1: Four-quadrant scientific workbench featuring live Quarto preview, interactive console, environment inspector, and redesigned Elrond AI copilot with multi-context chips.</em>
</p>

<table width="100%">
  <tr>
    <td width="50%" align="center">
      <img src="data/screenshots/imladris-welcome.png" alt="Progressive-Disclosure Welcome Screen" width="100%"><br>
      <em>Figure 2: Streamlined Welcome screen with Quick Start actions and expandable templates row.</em>
    </td>
    <td width="50%" align="center">
      <img src="data/screenshots/imladris-ai-copilot.png" alt="Elrond Direct Editor Writing Assistance" width="100%"><br>
      <em>Figure 3: Positron/RStudio-style Direct Editor Writing with in-place chunk updates and Quarto option preservation.</em>
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <img src="data/screenshots/imladris-preferences-workspace.png" alt="Workspace &amp; Editor Preferences" width="100%"><br>
      <em>Figure 4: Workspace &amp; Editor preferences (4-Pane vs Focus mode, ribbon toggle, zoom).</em>
    </td>
    <td width="50%" align="center">
      <img src="data/screenshots/imladris-preferences-theming.png" alt="Appearance &amp; Theme Preferences" width="100%"><br>
      <em>Figure 5: GNOME system themes, Eye Friendly mode, and custom accent color selection.</em>
    </td>
  </tr>
</table>

---

## Core Capabilities

### 1. Adaptive Dual-Mode Workbench
* **Single-Pane Focus Mode**: Calibrated for Markdown (`.md`) and HTML (`.html`) authoring without interpreter overhead.
* **Four-Quadrant Workbench Mode**: Automatic layout activation for `.qmd`, `.Rmd`, `.ipynb`, `.R`, and `.py`:
  * **Q1 (Top-Left)**: GtkSourceView 5 polyglot editor with code folding, breadcrumbs, and live diagnostics.
  * **Q2 (Bottom-Left)**: Persistent interactive REPL consoles for R, Python, Julia, SQL, and Bash.
  * **Q3 (Top-Right)**: Environment variable inspector, command history, document outline, citation manager, and Arekyer Galaxy bridge.
  * **Q4 (Bottom-Right)**: File browser, Cairo plot viewer, package manager, WebKitGTK 6.0 live preview, and embedded Shiny viewer.

### 2. Multi-Tier AI Copilot & Direct Writing
* **Local Offline Models**: Zero-configuration `llama-server` (Vulkan/CUDA acceleration), Ollama, and LM Studio endpoints operating fully offline.
* **Cloud & Free-Tier Engine**: Seamless support for Google Gemini, Anthropic Claude, OpenAI, DeepSeek, Kimi, Qwen, NVIDIA NIM, Groq, Cerebras, OpenRouter `:free`, and GitHub Models.
* **Direct Editor Writing (`Ctrl+Shift+E`)**: Update code blocks and text selections directly within the editor buffer with single-step `Ctrl+Z` undo.

### 3. Integrated Domain Scientific Bridges
* **Elbereth Biostatistics (`Imladris.Bridges.Elbereth`)**: ICH E9 sample size and power calculation module with Cairo visualization.
* **Arekyer Galaxy Bridge (`Imladris.Bridges.Arekyer`)**: Cloud genomics dataset browser with automated `httr2` and `pandas` data loading scripts.
* **Taniquetil AlphaFold Bridge (`Imladris.Bridges.Taniquetil`)**: Protein structure search, pLDDT plotting, and R/Python structural script generation.
* **Yavanna Bio-Entity Studio (`Imladris.Bridges.Yavanna`)**: Ensembl and UniProtKB programmatic client with integrated oligo calculator.
* **Natural Math & Chemistry (`Ctrl+M`)**: Natural expression parsing to KaTeX/LaTeX (`$$...$$`, `\ce{...}`).
* **Mermaid Flow Canvas (`Ctrl+Shift+D`)**: Bi-directional Cairo diagram editor synced with Quarto and Markdown code blocks.

### 4. Reproducibility & Scientific Publishing
* **Bidirectional `.Rproj` & `.mallorn` Portability**: Native loading of RStudio project structures and single-file `.mallorn` (`tar.zst`/`zip`) packages.
* **Sandboxed Dependency Management**: Project-isolated package environments powered by `renv` (R) and `.venv` (Python).
* **Multi-Format Export Pipeline**: Headless compilation to PDF, HTML, OpenDocument Text (`.odt`), OpenDocument Presentation (`.odp`), and Rich Text Format (`.rtf`).
* **Cryptographic GxP Lockfiles**: Production of verifiable SHA-256 manifest records ensuring reproducible research audits.

---

## Architecture & Module Map

```text
+-----------------------------------------------------------------------+
|                       GTK4 / Libadwaita UI Layer                      |
|  Window (HeaderBar + Ribbons + 4-Pane RStudioDockGrid + StatusBar)    |
+-----------------------------------+-----------------------------------+
                                    |
        +---------------------------+---------------------------+
        v                           v                           v
+---------------+           +---------------+           +---------------+
|  DocumentPage |           |   Elrond AI   |           |  Domain UI    |
| (GtkSource 5) |           | (Chat/Copilot)|           | (Bridges/Viz) |
+-------+-------+           +-------+-------+           +-------+-------+
        |                           |                           |
        v                           v                           v
+-----------------------------------------------------------------------+
|                       Core, Bridges & Services                        |
|  DocumentAdapter · AiBufferEditHelper · MallornManager · ChunkParser  |
|  AiConfigManager · AiClient · CopilotAuthService · McpServer          |
|  PersistentSessionManager · SandboxController · ExportService         |
|  Arekyer · Yavanna · Taniquetil · Elbereth · ZoteroService            |
+-----------------------------------------------------------------------+
```

* 📖 **[GitHub Technical Wiki](https://github.com/Antux912012/imladris/wiki)** — [Home](docs/wiki/Home.md) · [Arekyer Bridge](docs/wiki/Galaxy-to-Quarto-Bridge.md) · [Math & Chem Studio](docs/wiki/Math-and-Chemical-Studio.md) · [Projects & Sandboxing](docs/wiki/Projects-and-Sandboxing.md) · [Elrond AI Copilot](docs/wiki/Elrond-Local-AI-Copilot.md) · [Plugin Development](docs/wiki/Plugin-Development-Guide.md)
* 🏗️ **[Architectural Blueprint](docs/ARCHITECTURE.md)** & **[Docking Architecture](docs/DOCKING_ARCHITECTURE.md)**

---

## Installation & Deployment

### Flatpak / Flatpark (Recommended)
```bash
flatpak remote-add --if-not-exists flatpark https://flatpark.org/repo/flatpark.flatpakrepo
flatpak install flatpark io.github.Antux912012.Imladris
flatpak run io.github.Antux912012.Imladris
```

### Arch Linux (AUR)
```bash
paru -S imladris
```

### Fedora / RHEL (`.rpm`) & Debian / Ubuntu (`.deb`)
```bash
# Fedora / RHEL:
sudo dnf install ./imladris-0.25.0-1.x86_64.rpm

# Debian / Ubuntu:
sudo dpkg -i imladris_0.25.0_amd64.deb
sudo apt-get install -f
```

Pre-built `.flatpak`, `.deb`, `.rpm`, and source `.tar.gz` packages are available via [Flatpark](https://flatpark.org/apps/io.github.Antux912012.Imladris/) and [GitHub Releases v0.25.0](https://github.com/Antux912012/imladris/releases/tag/v0.25.0).

### Build from Source (Meson & Ninja)
Requires `valac >= 0.56`, `meson >= 0.60`, `ninja`, `gtk4 >= 4.12`, `libadwaita-1 >= 1.5`, `gtksourceview-5 >= 5.10`, `webkitgtk-6.0 >= 2.40`, `javascriptcoregtk-6.0`, `libsoup-3.0`, `json-glib-1.0`, `libsecret-1`, and `libgee-0.8`.

```bash
git clone https://github.com/Antux912012/imladris.git
cd imladris
meson setup build-debug --buildtype=debug
meson compile -C build-debug
GSETTINGS_BACKEND=memory meson test -C build-debug --print-errorlogs
./build-debug/imladris
```

* Package build helper (.flatpak & .deb): `./build-packages.sh`
* Package build helper (.rpm): `./build-rpm.sh`

---

## CLI & Keyboard Shortcuts

```bash
imladris --help              # Display CLI arguments
imladris --version           # Output installed version
imladris --mcp-server        # Run standard I/O Model Context Protocol (MCP) server
imladris --purge-user-data   # Purge local configurations, cache, and keyring entries (GDPR Art. 17)
imladris document.qmd        # Launch document, notebook, .Rproj, or .mallorn archive
```

| Key Combination | Functional Action |
| :--- | :--- |
| `Ctrl+N` / `Ctrl+O` / `Ctrl+S` | New Document/Project, Open, Save |
| `Ctrl+Shift+E` | Open Elrond AI for Direct Editor Writing |
| `Ctrl+M` | Open Natural Math & Chemical Reaction Studio |
| `Ctrl+Shift+D` | Open Visual Flow & Mindmap Studio |
| `Ctrl+Space` | Trigger Contextual Code Completion (Polyglot IntelliSense) |
| `Ctrl+Enter` | Execute Active Line or Selection in Console |
| `Ctrl+Shift+Enter` | Execute Active Code Chunk in Place |
| `Shift+Enter` | Execute Active Code Chunk and Advance to Next |
| `Ctrl+Shift+A` | Run / Stop Active Embedded R Shiny Application |
| `Ctrl+F1` | Collapse or Expand Modern Ribbon Toolbar |
| `Ctrl+Comma` | Open Preferences Dialog |

---

## Privacy, Security & Licensing

* **Zero Telemetry ([`PRIVACY.md`](PRIVACY.md))**: No telemetry pings, error logging reporting, or background network calls on application launch.
* **Keyring Security ([`SECURITY.md`](SECURITY.md))**: API keys and OAuth tokens are stored exclusively via system `libsecret-1` credential stores with restrictive `0600` fallbacks.
* **Sandboxed Tooling**: Built-in MCP execution defaults to disabled (`IMLADRIS_MCP_ALLOW_EXEC=1` required) and enforces explicit interpreter binary allowlisting (`Rscript`, `python3`, `quarto`).
* **GDPR Compliance (Art. 17)**: Execute `imladris --purge-user-data` for complete removal of application data from the local host.
* **License**: Published under the **[GNU General Public License v3.0 or later (`GPL-3.0-or-later`)](LICENSE)**.

```text
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
```
