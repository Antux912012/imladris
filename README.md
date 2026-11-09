<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

<p align="center">
  <img src="data/icons/hicolor/256x256/apps/io.github.Antux912012.Imladris.png" alt="Imladris Logo" width="128" height="128">
</p>

<h1 align="center">Imladris</h1>
<h3 align="center">Scientific Notebook Studio and Polyglot Markdown Editor</h3>

<p align="center">
  <a href="https://github.com/Antux912012/imladris/releases"><img src="https://img.shields.io/github/v/release/Antux912012/imladris?include_prereleases&style=flat-square&color=blue" alt="Release"></a>
  <img src="https://img.shields.io/badge/GTK4%20%2F%20Libadwaita-1.5%2B-blue?style=flat-square" alt="Toolkit">
  <img src="https://img.shields.io/badge/Vala-0.56%2B-green?style=flat-square" alt="Vala">
  <img src="https://img.shields.io/badge/License-GPL--3.0--or--later-brightgreen?style=flat-square" alt="License">
</p>

## 1. Technical Summary

Imladris is a native Linux scientific document studio and polyglot notebook editor. The application runs on GTK4, Libadwaita, GtkSourceView 5, and WebKitGTK 6.0 using the Vala programming language.

The application automatically transitions between two editing layouts. Single-pane Writer Mode displays simple Markdown files (`.md`, `.html`). Multi-pane Workbench Mode loads complex computational documents (`.qmd`, `.Rmd`, `.ipynb`, `.R`, `.py`) with integrated consoles, variable environments, package managers, and reactive execution panes.

> Note: Imladris is an independent software project. It is not affiliated with, sponsored by, or endorsed by Posit PBC, RStudio, or Project Jupyter.

---

## 2. Key Features

* **Adaptive Dual-Mode Layout Engine**: Transitions between Apostrophe-style distraction-free writing and an RStudio-style four-quadrant docked workbench without losing cursor focus.
* **Polyglot Execution Engines**: Executes code chunks in R, Python, Julia, SQL, and Bash through persistent stateful REPL bridges (`ReplBridge`).
* **Interactive Dataframe Viewer**: Inspects structured data tables using `Gtk.ColumnView` with column sorting, regex filtering, and clipboard export.
* **R Shiny Reactive Server Integration**: Intercepts and runs Shiny web applications with live outputs routed to Quadrant 4, a standalone window, or an external browser.
* **Export Pipeline**: Generates publication-ready documents in PDF, standalone HTML, OpenDocument Text (`.odt`), and OpenDocument Presentation (`.odp`) formats through Quarto and Pandoc.
* **Reproducible Project Environments**: Manages isolated `renv` (R) and `.venv` (Python) sandboxes with status badge indicators and export profiles.
* **Local Elrond AI Copilot**: Integrates a local `llama-server` engine on loopback (`127.0.0.1:8088`) for offline code completion and data science synthesis.
* **Galaxy Project Bioinformatics Bridge**: Connects to remote Galaxy servers (e.g., `usegalaxy.eu`), inspects active histories/datasets in Quadrant 3, and generates reproducible R (`httr`) or Python (`requests`/`pandas`) data-fetching chunks into active documents.
* **Model Context Protocol (MCP)**: Provides a JSON-RPC stdio server (`imladris --mcp-server`) for agentic tool use and document analysis.

---

## 3. System Architecture

Imladris follows a modular architecture that separates UI presentation, core domain logic, and execution services:

```text
+-----------------------------------------------------------------------+
|                           User Interface                              |
|   +-------------------+  +-------------------+  +-----------------+   |
|   |   Adw.Window      |  |  RibbonFactory    |  | RStudioDockGrid |   |
|   |  (Header & Views) |  |  (Context Tabs)   |  | (4 Quadrants)   |   |
|   +-------------------+  +-------------------+  +-----------------+   |
|            |                      |                      |            |
|   +---------------------------------------------------------------+   |
|   |        DocumentPage & PersistentPanelRegistry (GTK4 / Vala)    |   |
+---+---------------------------------------------------------------+---+
                                    |
+-----------------------------------+-----------------------------------+
|                            Core Domain                                |
|   +-------------------+  +-------------------+  +-----------------+   |
|   |    ChunkParser    |  | FrontmatterParser |  | Serializer (.qmd|   |
|   |  (Fenced Blocks)  |  |  (YAML Metadata)  |  |   .ipynb, .Rmd) |   |
|   +-------------------+  +-------------------+  +-----------------+   |
|            |                      |                      |            |
|   +-------------------+  +-------------------+  +-----------------+   |
|   |  DocumentAdapter  |  |   MallornManager  |  | SettingsManager |   |
|   |  (HTML / KaTeX)   |  |   (.mallorn Sync) |  |  (GLib.Settings)|   |
+---+-------------------+--+-------------------+--+-----------------+---+
                                    |
+-----------------------------------+-----------------------------------+
|                        Services & Execution                           |
|   +-------------------+  +-------------------+  +-----------------+   |
|   |    ReplBridge     |  |   ShinyService    |  | SandboxController|  |
|   | (R / Python PTY)  |  | (Ephemeral Ports) |  |  (renv / venv)  |   |
|   +-------------------+  +-------------------+  +-----------------+   |
|            |                      |                      |            |
|   +-------------------+  +-------------------+  +-----------------+   |
|   |   ExportService   |  |  RecoveryService  |  | PlatformUtils   |   |
|   |  (Quarto/Pandoc)  |  |  (Crash Snapshots)|  | (flatpak-spawn) |   |
+---+-------------------+--+-------------------+--+-----------------+---+
```

### Module Responsibilities:
* `Imladris.UI`: Manages GTK4 and Libadwaita window components, docking splits, ribbons, and modals.
* `Imladris.Core`: Parses document syntaxes, frontmatter metadata, configuration keys, and project structures.
* `Imladris.Execution`: Operates subprocess pipes, interactive language bridges, and chunk stdout/stderr interception.
* `Imladris.Services`: Orchestrates data export, Shiny process lifecycles, and automatic session recovery.
* `Imladris.Bridges`: Manages cloud bioinformatics connections, dataset retrieval, and external platform bridges (Galaxy Project REST APIs).

---

## 4. Prerequisites and Dependencies

### Toolchain Requirements:
* Vala compiler: `valac` >= 0.56.0
* C compiler: `gcc` or `clang`
* Build system: `meson` >= 0.60.0 and `ninja`

### Required Libraries:
* `gtk4` >= 4.12
* `libadwaita-1` >= 1.5
* `gtksourceview-5` >= 5.10
* `webkitgtk-6.0` >= 2.40
* `libsoup-3.0` >= 3.0
* `json-glib-1.0` >= 1.6
* `libgee-0.8` >= 0.20
* `gio-2.0` / `glib-2.0` >= 2.76

### Distribution Package Commands:

**Fedora / RHEL / CentOS Stream:**
```bash
sudo dnf install vala meson ninja-build gcc \
    gtk4-devel libadwaita-devel gtksourceview5-devel \
    webkitgtk6.0-devel libsoup3-devel json-glib-devel libgee-devel
```

**Debian (Bookworm / Trixie) / Ubuntu (24.04 LTS):**
```bash
sudo apt update
sudo apt install valac meson ninja-build gcc \
    libgtk-4-dev libadwaita-1-dev libgtksourceview-5-dev \
    libwebkitgtk-6.0-dev libsoup-3.0-dev libjson-glib-dev libgee-0.8-dev
```

**Arch Linux:**
```bash
sudo pacman -S vala meson ninja gcc \
    gtk4 libadwaita gtksourceview5 webkitgtk-6.0 libsoup3 json-glib libgee
```

---

## 5. Build and Installation Instructions

### Debug Profile Build:
```bash
git clone https://github.com/Antux912012/imladris.git
cd imladris
meson setup build-debug --buildtype=debug
meson compile -C build-debug
meson test -C build-debug --print-errorlogs
./build-debug/imladris
```

### Optimized Release Profile Build:
```bash
meson setup build-release --buildtype=release --strip
meson compile -C build-release
sudo meson install -C build-release
```

### Automated Package Scripts:
* Generate Flatpak and Debian packages: `./build-packages.sh`
* Generate Fedora RPM packages: `./build-rpm.sh`
* Generate SPDX SBOM: `./scripts/generate-sbom.sh`

---

## 6. Configuration and Usage

### Command-Line Interface (CLI):
```bash
# Display help and usage information
imladris --help

# Display the installed application version
imladris --version

# Launch the Model Context Protocol stdio server
imladris --mcp-server

# Erase all local user data, cache, and state (GDPR Article 17)
imladris --purge-user-data

# Open a specific file or notebook
imladris path/to/document.qmd
```

### Keyboard Shortcuts:
| Shortcut | Action |
| :--- | :--- |
| `Ctrl+N` | Open the New Project or File dialog |
| `Ctrl+O` | Open an existing document from disk |
| `Ctrl+S` | Save the current active document buffer |
| `Ctrl+F1` | Collapse or expand the top ribbon toolbar |
| `Ctrl+Z` / `Ctrl+Shift+Z` | Undo or redo the previous buffer edit |
| `Ctrl++` / `Ctrl+-` / `Ctrl+0` | Zoom in, zoom out, or reset zoom level |
| `Ctrl+Shift+E` | Trigger Elrond Assistance code generation |
| `Ctrl+Shift+P` | Focus the Packages Ribbon tab |
| `Ctrl+Shift+A` | Run or stop the active R Shiny web application |
| `Ctrl+Enter` | Execute the current code line or selection |
| `Ctrl+Shift+Enter` | Execute the active fenced code chunk |
| `Ctrl+Comma` | Open the Preferences dialog |
| `Ctrl+Q` | Terminate the application |

---

## 7. Privacy, Compliance, and License

### GDPR Compliance (Regulation (EU) 2016/679):
* **Data Minimization (Art. 5(1)(c))**: Imladris collects zero telemetry, zero analytics, and zero crash reports.
* **Local-First Processing**: Code analysis and Elrond AI operations run on local hardware (`127.0.0.1`).
* **Right to Erasure (Art. 17)**: Users can permanently remove all local configurations, indices, and cache entries using:
  ```bash
  imladris --purge-user-data
  ```

### EU Cyber Resilience Act (Regulation (EU) 2024/2847):
* Machine-readable SBOMs can be generated using `./scripts/generate-sbom.sh`.
* Security advisories and disclosure protocols are documented in [`SECURITY.md`](SECURITY.md).

### License:
All core source files in Imladris are released under the **[GNU General Public License v3.0 or later (GPL-3.0-or-later)](LICENSE)**.
```text
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
```
