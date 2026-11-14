<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Flathub Compliance, Generative AI Disclosure & Submission Guide (`io.github.Antux912012.Imladris`)

This document provides complete technical documentation for **Flathub Reviewers** and **Users** covering:
1. [Flathub Generative AI Policy Disclosure](#1-flathub-generative-ai-policy-disclosure)
2. [Manifest Authorship & Submission Integrity](#2-manifest-authorship--submission-integrity)
3. [Sandbox Permissions (`finish-args`) Justification](#3-sandbox-permissions-finish-args-justification)
4. [Offline Reproducible Build Architecture](#4-offline-reproducible-build-architecture)
5. [Local Build, Test & `flatpak-builder-lint` Verification](#5-local-build-test--flatpak-builder-lint-verification)
6. [Step-by-Step Flathub `new-pr` Submission Procedure & PR Template](#6-step-by-step-flathub-new-pr-submission-procedure--pr-template)

---

## 1. Flathub Generative AI Policy Disclosure

In compliance with the [Flathub Generative AI Policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy), this section discloses all AI-assisted material in the Imladris repository, the affected files, approximate extent, and human engineering verification.

### A. Component-by-Component Provenance & Extent Matrix

| Component / Path | AI-Assisted Extent | Tools Used | Human Authorship & Verification Scope |
| :--- | :--- | :--- | :--- |
| **Flathub Manifest** (`io.github.Antux912012.Imladris.yml`) | **0% (100% Human-Authored)** | None | Hand-authored, maintained, and lint-verified exclusively by Antonio De Gaetano in accordance with Flathub's strict manifest rule. |
| **Flathub Submission PR, Commits & Review Replies** | **0% (100% Human-Authored)** | None | All git commits, pull requests, descriptions, and reviewer communications on `flathub/flathub` are written manually by the maintainer. |
| **Vala Application Source Code** (`src/**/*.vala`) | **~60–70%** | Google Gemini, Anthropic Claude | AI pair-programming used for GTK4/Libadwaita UI scaffolding, parser/serializer boilerplate, and async service plumbing. System architecture, scientific domain logic (ICH E9 biostatistics, Galaxy/AlphaFold/UniProt bridges, `.mallorn` format), and security boundaries (`GLib.SubprocessLauncher` argv isolation, Zip Slip checks, MCP allowlisting) are designed, reviewed line-by-line, and tested on Linux hardware by Antonio De Gaetano. |
| **Automated Unit & Integration Tests** (`tests/*.vala`) | **~65–70%** | Google Gemini, Anthropic Claude | Test case scaffolding drafted with AI assistance and manually validated against deterministic edge cases via `meson test`. |
| **Documentation & AppStream Text** (`README.md`, `docs/`, `data/*.metainfo.xml`) | **~60–70%** | Google Gemini, Anthropic Claude | Technical prose and release notes drafted/edited with AI assistance and verified against compiled application behavior and `appstreamcli` / `flatpak-builder-lint`. |
| **Icons & Visual Assets** (`data/icons/`, `data/screenshots/`) | **0% AI Generation** | Inkscape / GNOME Screenshot | Application icon (`io.github.Antux912012.Imladris.svg`) is pure geometric vector SVG; bundled symbolic UI icons are from the open-source **Papirus Icon Theme** (`GPL-3.0-or-later`); screenshots are captured natively on Linux. |

### B. In-Application Optional AI Features (Elrond AI Copilot)
* **Strictly Opt-In**: Imladris operates as a complete scientific IDE (Quarto, R Markdown, Jupyter, R/Python REPLs, Cairo plotting, Galaxy/AlphaFold/ICH E9 studios) with zero AI providers enabled.
* **No Startup Network Calls**: Imladris makes zero network requests on startup (`PRIVACY.md`).
* **Explicit Privacy Consent Gate**: No document content or code is sent to external AI APIs unless the user configures a provider and accepts the explicit consent gate (`free_api_consent_accepted`).
* **Air-Gapped Local Inference**: Supports 100% offline local inference via `llama-server` (`llama.cpp`), Ollama (`127.0.0.1:11434`), and LM Studio (`127.0.0.1:1234`).

---

## 2. Manifest Authorship & Submission Integrity

Per the [Flathub Generative AI Policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy):
1. `io.github.Antux912012.Imladris.yml` is **hand-authored by Antonio De Gaetano** without AI-generated or AI-assisted content.
2. No AI agent or automated bot is used to open the `flathub/flathub` pull request, write git commit messages, draft the PR body, or respond to Flathub reviewers.

---

## 3. Sandbox Permissions (`finish-args`) Justification

`io.github.Antux912012.Imladris.yml` requests the following minimal `finish-args` under `org.gnome.Platform`:

| Permission (`finish-args`) | Technical Justification |
| :--- | :--- |
| `--share=ipc` | Standard X11 shared memory (`MIT-SHM`) and inter-process communication required by GTK4 when running under XWayland/X11. |
| `--socket=wayland` | Native Wayland display server connection for GTK4, Libadwaita, and WebKitGTK 6.0. |
| `--socket=fallback-x11` | Fallback X11 display connection used only when a Wayland compositor is unavailable (`fallback-x11` blocks X11 access when Wayland is present). |
| `--device=dri` | Direct Rendering Infrastructure GPU access for GTK4 GSK hardware acceleration (OpenGL NGL / Vulkan), WebKitGTK 6.0 accelerated compositing, and local Vulkan `llama.cpp` inference. |
| `--filesystem=home` | Imladris is a full polyglot IDE and scientific project workbench (`.Rproj`, `.mallorn`, `renv`, `.venv`, Quarto multi-file books). Child interpreters (`Rscript`, `python3`, `quarto`, `pandoc`) execute across project directories containing relative datasets (`.csv`, `.tsv`, `.parquet`, `.fastq`), scripts, BibTeX libraries (`.bib`), and virtual environments that cannot be resolved through single-file XDG FileChooser portal document descriptors. |
| `--share=network` | Required for: (1) loopback IPC with local R Shiny reactive web apps (`127.0.0.1:<port>`), Zotero BetterBibTeX citation server (`127.0.0.1:23119`), and local Ollama/LM Studio/`llama-server` endpoints; (2) on-demand CRAN, PyPI, and `ToolchainManager` (`micromamba`) scientific runtime installation into `$XDG_DATA_HOME/imladris/toolchains/`; (3) Galaxy Project, AlphaFold DB, UniProtKB, Ensembl, and Crossref DOI REST APIs; and (4) optional user-configured cloud AI endpoints. |

### Sandbox Hardening Controls Verified in Flatpak:
* **No `org.freedesktop.Flatpak` Host Escape Required**: Imladris ships a sandbox-native `ToolchainManager` (`$XDG_DATA_HOME/imladris/toolchains/mamba_root/envs/base-ds`) that provisions R, Python, Radian, and Quarto inside the user's sandbox storage, alongside `/usr/bin/python3` from `org.gnome.Platform`. Therefore, `--talk-name=org.freedesktop.Flatpak` is not required, eliminating `finish-args-flatpak-spawn-access`.
* **WebKitGTK 6.0 Sandbox Preserved**: In `src/main.vala`, Imladris checks `/.flatpak-info` and **never** sets `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1` inside Flatpak, allowing WebKitGTK 6.0 to delegate sub-process sandboxing to `org.freedesktop.portal.Flatpak`.
* **Keyring Portal (`org.freedesktop.portal.Secret`)**: Imladris links against `libsecret-1` (`>= 0.20`), which uses the Flatpak Secret Portal automatically inside the sandbox without requiring `--talk-name=org.freedesktop.secrets`.

---

## 4. Offline Reproducible Build Architecture

Imladris satisfies Flathub's strict offline build requirement:
* **Build System**: Standard `meson` (`buildsystem: meson`, `--buildtype=release`).
* **Zero Build-Time Network Access**: `meson.build` compiles tracked Vala source files (`src/**/*.vala`), compiles local GResource assets (`data/imladris.gresource.xml`, including bundled local Papirus symbolic SVGs), and installs `.desktop`, `.metainfo.xml`, `.gschema.xml`, and `hicolor` icons. No network calls, package managers, or external binary downloads are invoked during `meson setup`, `meson compile`, or `meson install`.
* **Source Pinning**: `io.github.Antux912012.Imladris.yml` pins the upstream Git repository by both `tag` and immutable 40-character `commit` SHA.
* **Note on `build-packages.sh`**: The script `build-packages.sh` in the repository root is strictly a local GitHub Releases convenience script for standalone `.deb` and side-loaded `.flatpak` bundles; Flathub builds exclusively from `io.github.Antux912012.Imladris.yml`.

---

## 5. Local Build, Test & `flatpak-builder-lint` Verification

Before opening or updating a Flathub pull request, run the exact official Flathub build and linter toolchain:

### Step 1: Install `org.flatpak.Builder` and GNOME Runtime/SDK
```bash
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --user flathub org.flatpak.Builder
```

### Step 2: Build Offline and Install via `org.flatpak.Builder`
```bash
flatpak run org.flatpak.Builder \
  --force-clean --sandbox --user --install --install-deps-from=flathub \
  --ccache --mirror-screenshots-url=https://dl.flathub.org/media/ \
  --repo=repo builddir io.github.Antux912012.Imladris.yml
```

### Step 3: Run and Smoke-Test the Flatpak Application
```bash
flatpak run io.github.Antux912012.Imladris --version
flatpak run io.github.Antux912012.Imladris
```

### Step 4: Run `flatpak-builder-lint` (Zero-Error Gate)
All three linter checks must exit with status `0` and produce zero errors or warnings:

```bash
# 1. Lint the Flatpak manifest:
flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest io.github.Antux912012.Imladris.yml

# 2. Lint the AppStream MetaInfo XML:
flatpak run --command=flatpak-builder-lint org.flatpak.Builder appstream data/io.github.Antux912012.Imladris.metainfo.xml

# 3. Lint the built OSTree repository:
flatpak run --command=flatpak-builder-lint org.flatpak.Builder repo repo
```

---

## 6. Step-by-Step Flathub `new-pr` Submission Procedure & PR Template

### A. Fork, Clone `new-pr`, and Branch
1. Fork [`https://github.com/flathub/flathub`](https://github.com/flathub/flathub) on GitHub (**uncheck** *"Copy the `master` branch only"* so `new-pr` is included).
2. Clone the `new-pr` branch locally and create the submission branch:
   ```bash
   git clone --branch=new-pr git@github.com:Antux912012/flathub.git
   cd flathub
   git checkout -b add-io.github.Antux912012.Imladris new-pr
   ```
3. Copy **only** the hand-authored manifest `io.github.Antux912012.Imladris.yml` into the repository root:
   ```bash
   cp /path/to/imladris/io.github.Antux912012.Imladris.yml .
   git add io.github.Antux912012.Imladris.yml
   git commit -m "Add io.github.Antux912012.Imladris"
   git push -u origin add-io.github.Antux912012.Imladris
   ```
4. Open a Pull Request on `https://github.com/flathub/flathub` with:
   * **Base branch**: `new-pr` (never `master`)
   * **Compare branch**: `Antux912012:add-io.github.Antux912012.Imladris`
   * **PR Title**: `Add io.github.Antux912012.Imladris`

### B. Flathub Submission Pull Request Template (Copy & Paste Manually)

```markdown
### Submission Checklist

- [x] The application ID `io.github.Antux912012.Imladris` matches the upstream GitHub repository (`https://github.com/Antux912012/imladris`).
- [x] I am the upstream author and maintainer of Imladris (`@Antux912012`).
- [x] The application is licensed under `GPL-3.0-or-later` and metadata under `CC0-1.0`.
- [x] The manifest `io.github.Antux912012.Imladris.yml` was hand-authored by me without any AI-generated or AI-assisted content.
- [x] Built and tested locally with `org.flatpak.Builder` in `--sandbox` mode (100% offline Meson build).
- [x] Validated with `flatpak-builder-lint manifest`, `flatpak-builder-lint appstream`, and `flatpak-builder-lint repo` with zero errors and zero warnings.

### Application Overview

**Imladris** (`io.github.Antux912012.Imladris`) is a native GTK4 / Libadwaita / GtkSourceView 5 / WebKitGTK 6.0 scientific notebook studio and IDE for Quarto (`.qmd`), R Markdown (`.Rmd`), Jupyter (`.ipynb`), R (`.R`), Python (`.py`), and Markdown (`.md`).

### Sandbox Permissions (`finish-args`) Justification

- `--share=ipc`, `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`: Standard GTK4 / Libadwaita / WebKitGTK 6.0 display and GPU acceleration permissions (`fallback-x11` disables X11 when running on Wayland).
- `--filesystem=home`: Required because Imladris is a multi-file project IDE (`.Rproj`, `.mallorn`, `renv`, `.venv`) where child scientific toolchains (`Rscript`, `python3`, `quarto`, `pandoc`) resolve project-relative datasets, scripts, and virtual environments across user project directories.
- `--share=network`: Required for local loopback R Shiny web app previews (`127.0.0.1`), local Zotero BetterBibTeX RPC (`127.0.0.1:23119`), local LLM servers (`127.0.0.1`), on-demand CRAN/PyPI and sandbox `ToolchainManager` (`micromamba`) runtime provisioning, bioinformatics REST APIs (Galaxy, AlphaFold DB, UniProt, Ensembl), and optional user-configured AI endpoints.
- **Note**: No `--talk-name=org.freedesktop.Flatpak` host escape is requested (scientific toolchains run inside the sandbox via `ToolchainManager` or `org.gnome.Platform`), WebKitGTK 6.0 sandboxing remains enabled inside Flatpak (`org.freedesktop.portal.Flatpak`), and keyring storage uses `libsecret-1` via `org.freedesktop.portal.Secret` without `--talk-name=org.freedesktop.secrets`.

### Generative AI Policy Disclosure

In accordance with the [Flathub Generative AI Policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy):
1. **Flathub Manifest & Submission PR (0% AI)**: `io.github.Antux912012.Imladris.yml`, this PR description, and all review interactions are 100% hand-written by me (Antonio De Gaetano).
2. **Upstream Application Code & Documentation (~60–70% AI-assisted)**: Approximately 60–70% of the Vala UI/service scaffolding (`src/`), unit test suites (`tests/`), and technical documentation (`README.md`, `docs/`) were developed using AI pair-programming assistance (Google Gemini and Anthropic Claude) under my direct software architecture, domain mathematical/bioinformatics specification, line-by-line code review, security auditing, and hardware testing.
3. **Icons & Branding (0% AI)**: The app icon (`io.github.Antux912012.Imladris.svg`) is pure geometric vector SVG and bundled symbolic UI icons come from the open-source Papirus Icon Theme (`GPL-3.0-or-later`).
4. **In-App AI Features**: Strictly opt-in (`PRIVACY.md`), with zero startup network calls, local offline inference support (`llama.cpp`/Ollama), and an explicit user consent gate before any external API request.
Full details are documented upstream in [`docs/FLATHUB_AI_DISCLOSURE_AND_SUBMISSION.md`](https://github.com/Antux912012/imladris/blob/v0.25.0/docs/FLATHUB_AI_DISCLOSURE_AND_SUBMISSION.md).
```
