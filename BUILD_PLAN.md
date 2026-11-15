<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# IMLADRIS v0.26.0 — MASTER BUILDING PLAN & REMEDIATION HANDOFF

**Target Executor Model:** `Hydrogen 4 Medium` (`gemini-4-hydrogen-medium`)
**Audited Baseline:** `origin/main` @ `7eb6b95` (`v0.25.0`, plus 2 Flatpak pin commits)
**Engineering Review Board:** Scientific Formats & Compilers, GTK4 / Libadwaita Adaptive UI, and Vala / Rust FFI / Flatpak Build & QA
**Supersedes:** Previous `v0.18.0–v0.25.0` Gemini 3.8 `BUILD_PLAN.md` (which marked `.qmd`/`.Rmd`/`.ipynb`/`.md` complete despite severe parsing, execution, preview, UI-adaptation, and Flatpak defects, and omitted `.tex` and `.ts`).

---

## 1. Mission Statement

Bring **Imladris** from a brittle prototype to a reliable, production-grade scientific workbench across **all seven core formats**:

1. **Quarto (`.qmd`)**
2. **R Markdown (`.Rmd`)**
3. **Jupyter Notebook (`.ipynb`)**
4. **Markdown (`.md`)**
5. **LaTeX (`.tex`)**
6. **TypeScript (`.ts`)**
7. **HTML (`.html`)**

Every format selected or opened by the user must:
1. **Adapt the UI intentionally and immediately** (Welcome screen, New menu/dialogs, HeaderBar actions, contextual Ribbon tabs/buttons, Workbench vs Focus layout, Console/Kernel selector, GtkSourceView 5 syntax highlighting, and Outline panel) with zero stale controls from other formats.
2. **Render accurately and deterministically** (live HTML/math/chemistry/Mermaid/LaTeX/TS preview without regex corruption of code blocks, dark/eye-friendly theme synchronization, scroll preservation, and strict WebKit sandboxing).
3. **Handle chunks and execution reliably** (exact fence/option parsing, sequential multi-cell execution without line-drift or singleton signal cross-talk, real graphics device plot capture, working R/Python Variable & DataGrid inspection, and per-tab working directory isolation).
4. **Compile, export, and package cleanly** across native hosts (`Rscript`, `quarto`, `latexmk`/`xelatex`/`pdflatex`, `node`/`tsc`/`deno`, `pandoc`) and **Flatpak** (`org.freedesktop.Flatpak=talk`, env propagation via `--env=`, shared paths, and offline-vendored Rust `imladris-core` build).

---

## 2. Building Files Directory (Read & Execute in Order)

Pass all Building Files below to **Hydrogen 4 Medium (`gemini-4-hydrogen-medium`)** in strict sequential phases unless parallel file ownership is explicitly declared:

| Phase / Order | Building File | Domain & Primary Ownership |
| :---: | :--- | :--- |
| **Mandatory Read First** | [`building/00_AGENT_GUIDELINES_TIPS_AND_PROCESS.md`](building/00_AGENT_GUIDELINES_TIPS_AND_PROCESS.md) | Mandatory Vala/GTK4/WebKitGTK/Rust/Flatpak rules, verified pitfall warnings, build/test environment notes, and required verification workflow. |
| **Phase 1** | [`building/01_FORMAT_TAXONOMY_AND_ADAPTIVE_UI.md`](building/01_FORMAT_TAXONOMY_AND_ADAPTIVE_UI.md) | Complete 7-format `FormatProfile` / `DocumentFormat` taxonomy (adding `TEX`, `TS`), Welcome/New/HeaderBar gating, format-adaptive Ribbons & Comments/Citations, `WorkspaceStateManager` per-tab isolation, `RStudioDockGrid` splitter/3-pane fixes, and bundled GtkSourceView 5 `.lang` specs. |
| **Phase 2** | [`building/02_RUST_CORE_PARSERS_AND_RENDERING.md`](building/02_RUST_CORE_PARSERS_AND_RENDERING.md) | Rust `imladris-core` C-ABI static library (`rust/imladris_core/` + Meson + `.vapi` + offline vendoring) + deterministic fixes for `ChunkParser`, nested YAML `FrontmatterParser`, `.ipynb` `nbformat 4.5` parity, token-preserving HTML preview, `MathChemEngine` (`\int` vs `\in`, HTML escaping), `MermaidFlowEngine` (z-order, sequence lifelines), WebKitGTK 6.0 security/scroll/themes. |
| **Phase 3** | [`building/03_CHUNKS_REPL_EXECUTION_AND_EXPORT.md`](building/03_CHUNKS_REPL_EXECUTION_AND_EXPORT.md) | Eliminating dual-kernel split-brain, per-tab/per-request `PersistentSessionManager` with timeouts/cancellation/`setwd` protocol fix, sequential `execute_all_cells` + `Gtk.TextChildAnchor` stability + global `\uFFFC` stripping + `begin_not_undoable_action()`, `EnvironmentController` (`.GlobalEnv` fix), `DataGridViewer`, LaTeX & TypeScript build/execution runners, `CodeIntelliSenseEngine` TS/LaTeX/Markdown fixes, and `QuartoExportEngine`/`ExportService` explicit-error routing. |
| **Phase 4** | [`building/04_FLATPAK_TOOLCHAIN_AND_QA_MATRIX.md`](building/04_FLATPAK_TOOLCHAIN_AND_QA_MATRIX.md) | Flatpak manifest convergence (`--talk-name=org.freedesktop.Flatpak`, cache/home portals, Rust + TeX Live SDK extensions), `PlatformUtils` container-vs-host `/usr/bin/python3` & `--env=` fixes, secret schema unification, `ToolchainManager` & `RecoveryService` & `MallornManager` & `build-packages.sh` fixes, `.desktop`/packaging sync, and full automated Meson/CI test suite across all 7 formats. |

---

## 3. Master Execution Dependency Graph

```text
Phase 0 (Baseline Check & Test Isolation)
   └──► Phase 1: FormatRegistry + DocumentFormat (TEX/TS) + GtkSource .lang + Adaptive Window/Ribbon/Dock
           └──► Phase 2: Rust imladris-core C-ABI + Chunk/YAML/ipynb/Math/Mermaid/WebKit Preview Pipeline
                   └──► Phase 3: Session Isolation + Sequential Chunk Queue + Anchor/Undo + TeX/TS/Quarto/Export Runners
                           └──► Phase 4: Flatpak/Host Portal + ToolchainManager + Packaging Sync + 7-Format QA Matrix + CI
```

### Why This Order Matters
1. **Format identity (`Phase 1`) must come first:** Currently `.tex` and `.ts` map to `DocumentFormat.MD`, `.ts` highlights as Markdown, `.md` receives `.qmd` templates, and HeaderBar/Ribbon controls bleed across all tabs. Establishing a typed `FormatProfile` and fixing per-tab UI state gives Phases 2 and 3 clean format dispatch hooks.
2. **Deterministic parsers & Rust core (`Phase 2`) come before execution/export (`Phase 3`):** Reliable chunk boundaries, `#|` options, nested YAML, `.ipynb` schema fidelity, and outline extraction are prerequisites for executing cells safely and syncing outputs back into `.ipynb` or previewing `.tex`/`.ts`/`.html`/`.qmd`.
3. **Session isolation & runner fixes (`Phase 3`) precede Flatpak/QA certification (`Phase 4`):** Once local execution, anchor stability, LaTeX/TS compilers, and export error propagation work natively, Flatpak `--talk-name`, `--env=` forwarding, offline Cargo vendoring, and end-to-end 7-format regression tests can be validated systematically.

---

## 4. High-Severity Defect Summary (Verified Audit Counts)

| Subsystem | Critical Root Causes Verified in Baseline (`7eb6b95`) | Target Building File |
|---|---|---|
| **Format Taxonomy & UI** | `.tex`/`.ts` absent from `DocumentFormat`; `.ts` skips `lang_id` fallback; `on_new_md` inserts `.qmd` template; `btn_render_quarto`/`export_format_selector` unmanaged on Welcome & all tabs; `# ` comment hardcoded; YAML bibliography injected into `.tex`/`.ts`/`.html`; `LEFT_TALL_3`/`RIGHT_TALL_3` hide tabs; `append_console_log` rebuilds dock per line; `set_split_orientation` hijacks Q4 on tab switch. | `01` |
| **Parsing & Rendering** | `ChunkParser` matches plain ```` ``` ```` fences as executable chunks & drops EOF; `DocumentAdapter` runs math/media/inline regexes inside `<pre>`/`<code>`; `MathChemEngine` turns `\int` into `∈t` and leaves `<`/`>` unescaped; `MermaidFlowEngine` draws arrowheads under opaque nodes & breaks `sequenceDiagram`; `notebook_serializer` loses language on save (`Window.vala` omits `existing_raw_file`), turns MD fences into code cells, and never updates `#| outputs_b64`; `WebViewFactory.reload()` loads directory listings; Dark/Sepia themes broken on `.html`/plots/badges. | `02` |
| **Execution & Export** | `PersistentPanelRegistry` bypasses `ChunkExecutionEngine`; `execute_all_cells` runs concurrently with singleton signal cross-talk & `end_line` drift into code; `\uFFFC` leaks into preview/compile/recovery/stats/REPL; `set_working_directory` silently dropped by 4-field driver check; `EnvironmentController` runs `ls()` inside `local()` without `.GlobalEnv`; `code.contains("print(")` triggers fake R plot capture; `View(df)` runs before assignment; zero `.tex`/`.ts` execution/compilers; `ExportService` fakes success with raw fallback when Quarto/Pandoc fail. | `03` |
| **Flatpak, Build & QA** | All 4 Flatpak manifests lack `--talk-name=org.freedesktop.Flatpak`; `build_host_command` drops launcher env vars; `configure_managed_env` wipes prior env vars; Flatpak `/usr/bin/python3` traps `resolve_runtime` ahead of host; secret schema mismatch (`io.github...` vs `org.ardatech...`); `RecoveryService` lacks mutex on purge and sets restored crash buffers clean; `test_dock_environment` mutates real `~/.config/imladris`; `meson test` missing from CI & `0` tests cover `.tex`/`.ts`/Quarto/Recovery. | `04` |

---

## 5. Global Definition of Done (Acceptance Sign-Off)

Hydrogen 4 Medium MUST NOT declare completion until **all** conditions hold with observed command outputs:
- [ ] `meson setup` + `meson compile` completes with **0 Vala errors** and **0 new C `-Wincompatible-pointer-types` / Rust warnings** (Rust `imladris-core` built cleanly via Cargo + linked statically).
- [ ] `GSETTINGS_BACKEND=memory meson test --print-errorlogs` passes **100% of test suites** in isolated temp `XDG_CONFIG_HOME` / `XDG_DATA_HOME` / `XDG_CACHE_HOME` (never mutating real `$HOME/.config/imladris/`), including new tests for all **7 formats**, Rust FFI, chunk parsing, sequential execution, `.ipynb` round-trip, `MathChemEngine`, `MermaidFlowEngine`, `RecoveryService`, and `FormatProfile` state transitions.
- [ ] Interactive manual / headless harness matrix verifies **Create -> Syntax Highlight -> Adapt UI -> Run/Preview -> Compile/Export -> Save/Reopen** cleanly for `.qmd`, `.Rmd`, `.ipynb`, `.md`, `.tex`, `.ts`, and `.html`.
- [ ] Flatpak manifest(s) pass `flatpak-builder --lint` / schema checks, include `--talk-name=org.freedesktop.Flatpak` + offline Cargo vendoring + consistent runtime/docs, and `build-packages.sh` has no broken `llama-server` wrapper copy.
- [ ] Documentation (`README.md`, `CHANGELOG.md`, `docs/ARCHITECTURE.md`, `docs/FLATHUB_AI_DISCLOSURE_AND_SUBMISSION.md`) accurately reflects the implemented v0.26.0 architecture with zero false claims.
