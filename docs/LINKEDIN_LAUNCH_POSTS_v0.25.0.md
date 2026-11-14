<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Imladris v0.25.0 — LinkedIn Product Launch Playbook & Posts

Prepared from a **Product Launch & Senior Marketing Manager** perspective for global developer, bioinformatics, and data science audiences.

---

## Post 1: Flagship Global Product Launch (Founder / Product Lead Voice)
**Best for:** Launch Day morning (Tuesday–Thursday, 08:30–10:00 local time).  
**Visual Asset:** Screenshot of the 4-Quadrant Workbench (`data/screenshots/imladris-screenshot.png`) or short 30s screen recording.

> **Stop paying a 2 GB RAM Electron tax just to run R, Python, and Quarto.**
>
> Today, I’m launching **Imladris v0.25.0** — a native Linux scientific workbench, bioinformatics bridge, and polyglot notebook IDE built from the ground up in compiled **Vala, GTK4, Libadwaita, GtkSourceView 5, and WebKitGTK 6.0**.
>
> Why did we build Imladris? Because researchers shouldn't have to choose between a snappy native editor and a full reproducible science environment.
>
> **What’s inside v0.25.0:**
> 1. **Positron/RStudio-Style Direct Editor Writing** — Refactor selections or update Quarto code chunks in place while strictly preserving `#|` YAML chunk options and single-step `Ctrl+Z` undo.
> 2. **Resilient AI Orchestration (Zero Lock-In)** — Run 100% offline with **Local Elrond (`llama-server` / Ollama / LM Studio)**, sign in with **GitHub Copilot OAuth Device Flow**, or connect **Free-Tier AI APIs** (Groq, Cerebras, OpenRouter `:free`, GitHub Models) with **automatic HTTP 429 quota failover**.
> 3. **Built-In Scientific & Clinical Studios** —
>    - **Arekyer**: Galaxy Project histories -> verified `httr2`/`pandas` Quarto chunks (`libsecret-1` keyring).
>    - **Elbereth**: ICH E9 clinical trial power curves, Schoenfeld survival sample size, and CDISC ADSL/ADTTE code gen.
>    - **Taniquetil & Yavanna**: AlphaFold DB pLDDT tracks, UniProt/Ensembl lookup, and RT-qPCR oligo $T_m$ calculators.
>    - **Math & Chem Studio (`Ctrl+M`)**: Natural math & chemical reactions straight to LaTeX/Markdown.
>
> **Zero telemetry. Zero phone-home startup calls. GPL-3.0 open source.**
>
> Available today as `.flatpak`, `.deb`, `.rpm`, and AUR:
> - Landing Page: https://antux912012.github.io/imladris/
> - GitHub Release v0.25.0: https://github.com/Antux912012/imladris/releases/tag/v0.25.0
>
> What’s the biggest bottleneck in your current R / Python / Quarto workflow on Linux? Let’s discuss in the comments.
>
> #OpenSource #Linux #DataScience #Bioinformatics #Quarto #RStats #Python #GTK4 #ScientificComputing #ReproducibleResearch

---

## Post 2: The AI & Developer Experience Deep Dive (No Lock-In, No Quota Dead-Ends)
**Best for:** Day 3 post-launch (targeting RStudio/Positron, VS Code, and AI-assisted coding audiences).  
**Visual Asset:** `data/screenshots/imladris-ai-copilot.png` or a side-by-side clip showing `Update Chunk` preserving `#| label:` and `#| fig-cap:`.

> **Two things break flow when coding with AI in scientific notebooks:**
> 1. Hitting an `HTTP 429` rate limit mid-analysis.
> 2. Having an AI rewrite your code chunk and accidentally wipe your `#|` Quarto YAML options or undo stack.
>
> In **Imladris v0.25.0**, we solved both:
>
> - **Automatic Free-Tier Quota Failover**: Use your primary AI provider — and if you hit rate limits or quota exhaustion, Imladris automatically cascades across configured free-tier endpoints (**Groq**, **Cerebras**, **OpenRouter `:free`**, **GitHub Models**, or a local **FreeLLMAPI** proxy), guarded by explicit privacy opt-in.
> - **GitHub Copilot OAuth Device Flow**: Already have Copilot? Sign in directly inside AI Settings via standard GitHub Device Flow, stored securely in your Linux OS keyring (`libsecret-1`).
> - **100% Offline Local Elrond**: Prefer air-gapped local inference? `llama-server` (Vulkan/CUDA), Ollama, and LM Studio run completely offline with zero silent cloud fallback.
> - **Positron-Style Direct Editor Writing**: Click **Apply to Selection** or **Update Chunk** — Imladris splices only the chunk body lines, keeping every `#| label`, `#| echo`, and `#| fig-cap` intact and fully reversible with a single `Ctrl+Z`.
>
> Try v0.25.0 on Fedora, Ubuntu/Debian, Arch, or Flatpak:
> https://github.com/Antux912012/imladris/releases/tag/v0.25.0
>
> #AI #DeveloperExperience #RStudio #Positron #Quarto #GitHubCopilot #LocalLLM #LinuxDesktop

---

## Post 3: Bioinformatics & Clinical Research Spotlight (Provenance & Regulatory Rigor)
**Best for:** Week 2 post-launch (targeting biotech, pharma biostatistics, and academic genomics teams).  
**Visual Asset:** Screenshot of Arekyer Galaxy Bridge + Elbereth ICH E9 power curve or `docs/index.html` 4-quadrant preview.

> **Downloading `final_counts_v3_REAL.csv` from a browser is where reproducibility goes to die.**
>
> In computational biology and clinical trials, data provenance shouldn't be an afterthought. That’s why **Imladris v0.25.0** integrates domain bridges directly into the manuscript editor:
>
> - **Arekyer (Galaxy-to-Quarto Bridge)**: Browse `usegalaxy.eu` / `usegalaxy.org` histories inside the IDE, keep your API key in the OS keyring (`libsecret-1`), and inject reproducible `httr2` (R) or `pandas` (Python) loaders tagged with dataset UUIDs.
> - **Elbereth (ICH E9 Clinical Biostatistics)**: Compute continuous, proportion, and Schoenfeld log-rank survival sample sizes, inspect live Cairo power curves, and generate CDISC ADSL Table 1 & Cox PH chunks.
> - **Taniquetil & Yavanna**: Pull AlphaFold DB pLDDT confidence tracks (`bio3d` / `biotite`) and resolve UniProt/Ensembl IDs + RT-qPCR oligo $T_m$ in memory.
> - **GxP & CRA Provenance Lock**: Every build can emit a SHA-256 `.provenance.lock.json` sidecar tying your `.qmd` manuscript to `renv.lock`, `uv.lock`, and upstream bio-entity records.
>
> Built in native Linux **Vala + GTK4** — zero Electron, zero telemetry, 100% open source (GPL-3.0).
>
> Explore the Technical Wiki & Release: https://antux912012.github.io/imladris/
>
> #Bioinformatics #ClinicalTrials #Biostatistics #ICH_E9 #GalaxyProject #AlphaFold #Reproducibility #OpenScience

---

## Post 4: Privacy, Security & Architecture Post (Engineering Leadership Voice)
**Best for:** Week 2–3 (targeting CTOs, security-conscious researchers, and GNOME/Linux engineers).  
**Visual Asset:** Clean architecture diagram or `SECURITY.md` / `PRIVACY.md` highlight card.

> **Before tagging Imladris v0.25.0, we put the entire codebase through a 3-track security & architecture audit.**
>
> When scientists run local R/Python kernels, MCP servers, and AI assistants on sensitive datasets, "convenience" can never come at the expense of trust. Here is what we hardened in v0.25.0:
>
> - **MCP `execute_code` Hardening**: Disabled by default (`IMLADRIS_MCP_ALLOW_EXEC=1` opt-in) and strictly allowlisted to `Rscript`, `python3`, and `quarto`.
> - **Credential Isolation**: `GALAXY_API_KEY` is no longer injected into general user script subprocesses; OAuth tokens live in `libsecret-1` with `0600` fallback.
> - **Zip Slip Protection**: `.mallorn` archive extraction (`.tar.zst` & `.zip`) validates every member path against `..` traversal and absolute paths before writing a single byte.
> - **Zero Phone-Home Startup**: Remote CRAN/PyPI index refreshes are deferred strictly to on-demand user action.
> - **GDPR Art. 17 One-Command Erasure**: `imladris --purge-user-data` cleanly wipes all local config, caches, and keyring credentials.
>
> Native software can be fast, capable, *and* auditable.
>
> Check out the source and security policy: https://github.com/Antux912012/imladris
>
> #AppSec #LinuxSecurity #PrivacyByDesign #GDPR #OpenSource #Vala #GTK4 #Libadwaita

---

## Post 5: Short High-Engagement Carousel / Quick-Demo Post
**Best for:** Quick mid-week engagement boost.

> **One native Linux app. Four quadrants. Zero Electron.**
>
> Meet **Imladris v0.25.0** — the open-source scientific workbench for `.qmd`, `.Rmd`, `.ipynb`, and `.Rproj`:
>
> - Compiled **Vala + GTK4 + Libadwaita**
> - **R, Python, Julia, SQL & Bash** live consoles + R Shiny hosting
> - **Positron-style Direct AI Writing** that preserves `#|` Quarto options
> - **Free-Tier AI Failover** (Groq, Cerebras, OpenRouter, GitHub Models) + **Copilot OAuth** + **Offline Local Elrond**
> - **Arekyer** (Galaxy), **Elbereth** (ICH E9), **Taniquetil** (AlphaFold), **Yavanna** (RT-qPCR)
>
> Install via Flatpak, `.deb`, `.rpm`, or AUR: https://github.com/Antux912012/imladris/releases/tag/v0.25.0
>
> #Linux #RStats #Python #Quarto #Jupyter #OpenSource
