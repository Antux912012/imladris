<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Flathub Compliance & Generative AI Disclosure (`io.github.Antux912012.Imladris`)

This document provides complete transparency regarding **Flathub Submission Requirements** and the **Flathub Generative AI Policy** for **Imladris (`io.github.Antux912012.Imladris`)**.

---

## 1. Generative AI Policy Disclosure

In full compliance with the [Flathub Generative AI Policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy):

### A. AI Assistance in Application Development & Packaging
* **Affected Parts & Approximate Extent**:
  * **Vala Source Code (`src/`) & Unit Tests (`tests/`)**: Approximately **60–70%** of the boilerplate, UI scaffolding, parser/bridge implementations, and unit test suites were developed using AI pair-programming assistance (**Google Gemini** and **Anthropic Claude**) under the direct architectural design, domain specification, manual code review, security auditing, and hardware testing of the author (**Antonio De Gaetano**, Bioinformatician & Biological Scientist).
  * **Documentation (`README.md`, `docs/`, `docs/wiki/`)**: Technical documentation, ASD-STE100 functional specifications, and landing page copy were drafted and refined with AI editorial assistance and verified against the compiled codebase.
  * **Packaging (`io.github.Antux912012.Imladris.yml`, `data/io.github.Antux912012.Imladris.metainfo.xml`)**: Assisted in formatting and linting, then validated against `flatpak-builder` and Meson test suites.
  * **Icons & Branding (`data/icons/`)**: The application logo is clean geometric vector SVG (`io.github.Antux912012.Imladris.svg`), and bundled toolbar/UI symbolic icons are sourced from the open-source **Papirus Icon Theme** (`GPL-3.0-or-later`), properly attributed in `Adw.AboutDialog` and `README.md`.

### B. In-Application Optional AI Features (Elrond AI Copilot)
* **Strictly Opt-In**: Imladris functions as a complete scientific IDE (Quarto, R Markdown, Jupyter, R/Python consoles, Cairo plotting, Galaxy/AlphaFold/ICH E9 studios) without any AI provider enabled.
* **Privacy & Consent Gate**: No document text, code chunks, or telemetry are ever transmitted to external AI APIs unless the user explicitly configures a provider and accepts the privacy consent gate (`free_api_consent_accepted`).
* **Local Offline Option**: Supports 100% air-gapped local inference via `llama.cpp` (`llama-server`), Ollama, and LM Studio.

---

## 2. Flatpak Sandbox & Technical Compliance (`v0.25.0`)

* **WebKitGTK 6.0 Sandbox Intact**: When running inside Flatpak (`/.flatpak-info` present), Imladris **does not** set `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`, allowing WebKitGTK 6.0 to use the native Flatpak sandbox portal (`org.freedesktop.portal.Flatpak`).
* **Keyring Portal**: Uses `libsecret-1` (backed automatically by `org.freedesktop.portal.Secret` inside Flatpak) without requiring raw D-Bus `--talk-name=org.freedesktop.secrets` holes.
* **Finish-Args Justification**:
  * `--filesystem=home`: Required for multi-file scientific projects (`.Rproj`, `.mallorn`, `renv`, `.venv`, relative CSV/TSV/FASTQ datasets, and BibTeX libraries) where child interpreters (`Rscript`, `python3`, `quarto`) resolve project-relative file paths.
  * `--talk-name=org.freedesktop.Flatpak`: Required for an IDE workbench to invoke host-installed scientific toolchains (`R`, `Rscript`, `python3`, `quarto`, `pandoc`, `typst`) via `flatpak-spawn --host`.
  * `--share=network`: Required for local R Shiny reactive web previews (`127.0.0.1`), local Zotero BetterBibTeX citation server (`127.0.0.1:23119`), CRAN/PyPI package installation, Galaxy/AlphaFold/UniProt scientific APIs, and optional AI endpoints.
