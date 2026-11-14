<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

<p align="center">
  <img src="data/icons/hicolor/256x256/apps/io.github.Antux912012.Imladris.png" alt="Imladris Logo" width="128" height="128">
</p>

<h1 align="center">Imladris</h1>
<h3 align="center">The Native Linux Scientific Workbench, Bioinformatics Bridge &amp; Polyglot Notebook IDE</h3>

<p align="center">
  <em>Zero Electron overhead. Instant startup. Reproducible manuscripts from cloud genomics to clinical biostatistics.</em>
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

Modern scientific software forces an unnecessary compromise: heavy Electron-based IDEs consume gigabytes of RAM before you load a single dataset, while lightweight editors lack R/Python notebooks, reproducible environments, and domain-specific scientific tooling.

**Imladris** is engineered in compiled **Vala**, **GTK4**, **Libadwaita**, **GtkSourceView 5**, and **WebKitGTK 6.0** to give researchers, bioinformaticians, biostatisticians, and data scientists a **sub-second native desktop studio** that keeps CPU and memory dedicated to statistical compute, genomic matrices, and local AI inference.

| Challenge | Legacy Workflow | The Imladris v0.25.0 Approach |
| :--- | :--- | :--- |
| **IDE Overhead** | 1–2 GB RAM idle in Electron | Native compiled Vala + GTK4 binary with hardware-accelerated rendering |
| **AI Coding & Cost** | Locked to one paid cloud API | **Local Elrond** (offline `llama-server`) + **Free-Tier APIs** (Groq, Cerebras, OpenRouter `:free`, GitHub Models) + **Auto-Failover** + **GitHub Copilot OAuth** |
| **Editor Refactoring** | Copy-pasting from chat or losing YAML | **Positron/RStudio-Style Direct Editor Writing** (`Apply to Selection` & `Update Chunk` preserving `#|` Quarto options + `Ctrl+Z` undo) |
| **Cloud Genomics** | Manual CSV downloads break provenance | **Arekyer Galaxy Bridge** (`libsecret-1` keyring + verified `httr2`/`pandas` provenance chunks) |
| **Domain Tooling** | Disconnected web calculators | Integrated **Elbereth** (ICH E9 Biostats), **Taniquetil** (AlphaFold DB), **Yavanna** (RT-qPCR & UniProt/Ensembl), & **MathChem** (`Ctrl+M`) |

> **Note:** Imladris is an independent open-source software project. It is not affiliated with, sponsored by, or endorsed by Posit PBC, RStudio, Project Jupyter, or the Galaxy Project.

---

## What’s New in v0.25.0

* **Free-Tier AI Orchestration & Automatic Quota Failover**: Configure permanent free-tier providers (**Groq**, **Cerebras**, **OpenRouter `:free`**, **GitHub Models**, and **FreeLLMAPI Local Proxy**). When a primary cloud provider hits rate limits (`HTTP 429`) or quota exhaustion, `AiClient` automatically cascades to your configured backup providers (guarded by explicit user privacy opt-in).
* **GitHub Copilot OAuth Device Flow**: Sign in directly from **AI Settings** using standard RFC 8628 GitHub Device Flow (`https://github.com/login/device`), with tokens stored in `libsecret` (`io.github.Antux912012.Imladris.Copilot`) and `0600` fallback.
* **Positron/RStudio-Style Direct Editor Writing**: Replaces modal inline popovers with direct, undoable buffer actions inside **Elrond AI**: **Apply to Selection**, **Update Active Chunk** (preserving `#|` Quarto cell options without resetting cursor/scroll/undo history), and one-click quick actions (*Improve Writing*, *Refactor Code*, *Fix Error*).
* **Security & Data-Integrity Hardening**: MCP `execute_code` disabled by default (`IMLADRIS_MCP_ALLOW_EXEC=1` opt-in + `Rscript`/`python3`/`quarto` allowlist), `.mallorn` Zip Slip path traversal validation, shell-free `micromamba` bootstrap with SHA-256 verification, `\uFFFC` child-anchor sanitization on save, and dock popout/tab-close lifecycle fixes.

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
* **Single-Pane Writer Mode**: Opens Markdown (`.md`) and HTML (`.html`) files in a calm, distraction-free writing surface without spawning background interpreters.
* **Four-Quadrant Workbench Mode**: Opens computational notebooks (`.qmd`, `.Rmd`, `.ipynb`, `.R`, `.py`) in a configurable RStudio-style 4-quadrant layout with Source Editor (Q1), Console & Terminal (Q2), Environment / History / Outline / Citations / Arekyer (Q3), and Files / Plots / Packages / Live Preview / Shiny Viewer (Q4).

### 2. Elrond AI Copilot, Free-Tier Backup & GitHub Copilot
* **Local-First AI**: Zero-config `llama-server` (Vulkan/CUDA), Ollama, LM Studio, Cherry Studio, and Antigravity CLI (`agy`) — 100% offline with zero silent cloud fallback.
* **Cloud & Free-Tier Multi-Provider Engine**: Supports Gemini, Claude, OpenAI, DeepSeek, Kimi, Qwen, NVIDIA NIM, Groq, Cerebras, OpenRouter `:free`, GitHub Models, and FreeLLMAPI Local Proxy with automatic `HTTP 429` failover.
* **GitHub Copilot OAuth**: Native Device Flow sign-in from **AI Settings**.
* **Direct Editor Writing (`Ctrl+Shift+E`)**: Apply AI code directly to editor selections or active chunks while preserving `#|` Quarto options and single-step `Ctrl+Z` undo.

### 3. Integrated Scientific & Clinical Studios
* **Elbereth Clinical Biostatistics (`Imladris.Bridges.Elbereth`)**: ICH E9 statistical power & sample size (Two-Sample Continuous, Proportions with Casagrande-Pike correction, Schoenfeld Log-Rank Survival), live Cairo power curves, and CDISC ADSL Table 1 / ADTTE Kaplan-Meier / Cox PH code generation.
* **Arekyer Galaxy-to-Quarto Bridge (`Imladris.Bridges.Arekyer`)**: Browse Galaxy Project histories (`usegalaxy.eu`, `usegalaxy.org`, `usegalaxy.org.au`), store API keys in `libsecret-1`, and inject verified `httr2` (R) and `pandas` (Python) loaders.
* **Taniquetil AlphaFold Bridge (`Imladris.Bridges.Taniquetil`)**: Inspect DeepMind / EMBL-EBI AlphaFold DB and RCSB PDB structures with Cairo per-residue pLDDT tracks and `bio3d` / `biotite` code generation.
* **Yavanna Bio-Entity & RT-qPCR Studio (`Imladris.Bridges.Yavanna`)**: Asynchronous UniProtKB & Ensembl GRCh38 lookup plus in-memory oligo length, GC%, $T_m$, molecular weight, and reverse-complement calculation.
* **Natural Math & Chemical Reaction Studio (`Ctrl+M`)**: Converts natural expressions (`(-b +- sqrt(b^2 - 4*a*c)) / (2*a)`, `6CO2(g) + 6H2O(l) ->[h*nu] C6H12O6(aq) + 6O2(g)`) into LaTeX (`$$...$$`, `\ce{...}`) or Markdown.
* **Visual Flow & Mindmap Studio (`Ctrl+Shift+D`)**: Interactive Cairo 2D canvas synced two-way with Quarto ` ```{mermaid} ` and Markdown ` ```mermaid ` blocks.

### 4. Reproducible Environments, Jupyter Parity & Publishing
* **`.Rproj` & `.mallorn` Portability**: Synchronizes RStudio `.Rproj` manifests and `.mallorn` bundles (`tar.zst` / `zip`) with isolated `renv` (R) and `.venv` (Python) sandboxes.
* **Jupyter `nbformat 4.5` Parity**: Lossless round-trip `.ipynb` serialization preserving cell IDs, execution counts, tags, raw cells, and `Shift+Enter` cell advancement.
* **Interactive Compute & R Shiny**: Persistent R, Python, Julia, SQL, and Bash consoles, `Gtk.ColumnView` dataframe viewer, Zotero BetterBibTeX/CSL citations, and ephemeral-port R Shiny hosting (`Ctrl+Shift+A`).
* **GxP & CRA Provenance Attestation**: Writes `<document>.provenance.lock.json` SHA-256 manifests across manuscripts, lockfiles, and bio-entity records.

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

## Installation & Building

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

Download `.flatpak`, `.deb`, `.rpm`, and source `.tar.gz` bundles from [Flatpark](https://flatpark.org/apps/io.github.Antux912012.Imladris/) and [GitHub Releases v0.25.0](https://github.com/Antux912012/imladris/releases/tag/v0.25.0).

### Build & Test from Source (Meson & Ninja)
Requires `valac >= 0.56`, `meson >= 0.60`, `ninja`, `gtk4 >= 4.12`, `libadwaita-1 >= 1.5`, `gtksourceview-5 >= 5.10`, `webkitgtk-6.0 >= 2.40`, `javascriptcoregtk-6.0`, `libsoup-3.0`, `json-glib-1.0`, `libsecret-1`, and `libgee-0.8`.

```bash
git clone https://github.com/Antux912012/imladris.git
cd imladris
meson setup build-debug --buildtype=debug
meson compile -C build-debug
GSETTINGS_BACKEND=memory meson test -C build-debug --print-errorlogs
./build-debug/imladris
```

* Build `.flatpak` & `.deb` packages: `./build-packages.sh`
* Build `.rpm` package: `./build-rpm.sh`
* Inspect build dependencies: `meson introspect build-debug --dependencies`

---

## CLI & Keyboard Shortcuts

```bash
imladris --help              # Show CLI options
imladris --version           # Print installed version
imladris --mcp-server        # Launch hardened MCP stdio server
imladris --purge-user-data   # Erase all local data, keyring secrets, and cache (GDPR Art. 17)
imladris path/to/file.qmd    # Open a document, notebook, .Rproj, or .mallorn bundle
```

| Shortcut | Action |
| :--- | :--- |
| `Ctrl+N` / `Ctrl+O` / `Ctrl+S` | New Project/File, Open, Save |
| `Ctrl+Shift+E` | Open Elrond AI for Direct Editor Writing |
| `Ctrl+M` | Open Natural Math & Chemical Reaction Studio |
| `Ctrl+Shift+D` | Open Visual Flow & Mindmap Studio |
| `Ctrl+Space` | Trigger offline Polyglot IntelliSense |
| `Ctrl+Enter` / `Ctrl+Shift+Enter` / `Shift+Enter` | Run line/selection, run chunk in place, or run chunk & advance |
| `Ctrl+Shift+A` | Run or stop active R Shiny application |
| `Ctrl+F1` / `Ctrl+Comma` | Toggle top ribbon toolbar / Open Preferences |

---

## Privacy, Security & License

* **Zero Telemetry ([`PRIVACY.md`](PRIVACY.md))**: No analytics, no crash reporting, and no startup phone-home calls. CRAN/PyPI index refreshes occur strictly on demand.
* **Hardened Security ([`SECURITY.md`](SECURITY.md))**: `libsecret-1` keyring storage, MCP `execute_code` disabled by default, Zip Slip validation on `.mallorn` extraction, and shell-free `curl`/`tar` downloads.
* **GDPR Right to Erasure (Art. 17)**: `imladris --purge-user-data` removes all local configuration, cache, and keyring entries.
* **License**: Released under **[GNU General Public License v3.0 or later (`GPL-3.0-or-later`)](LICENSE)**.

```text
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
```
