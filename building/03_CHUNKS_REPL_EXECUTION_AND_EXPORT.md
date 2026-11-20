<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# Building File 03 — Chunks, Isolated REPLs, Compilers & Multi-Format Export

**Phase:** 3 of 4
**Prerequisites:** Phases 1 & 2 complete (`FormatProfile`, `NativeCore`/Rust parsers, clean `ChunkParser`, and lossless `.ipynb` serializer live).
**Primary Ownership:** `src/services/PersistentSessionManager.vala`, `src/editor/ChunkExecutionEngine.vala`, `src/console/ReplBridge.vala`, `src/ExecutionEngine.vala`, `src/ui/PersistentPanelRegistry.vala`, `src/ui/InlineChunkOutputWidget.vala`, `src/ui/EnvironmentController.vala`, `src/ui/DataGridViewer.vala`, `src/editor/CodeIntelliSenseEngine.vala`, `src/editor/CodeIntelliSenseProvider.vala`, new `src/runners/LatexBuildRunner.vala`, new `src/runners/TypeScriptRunner.vala`, `src/core/QuartoExportEngine.vala`, `src/services/ExportService.vala`, `src/DocumentPage.vala`, `src/Window.vala`.

---

## 1. Objective

Make **every chunk run, console command, data inspector, IntelliSense suggestion, document compilation, and export** deterministic, leak-free, properly scoped per document/project, and explicit on errors across all 7 formats (`.qmd`, `.Rmd`, `.ipynb`, `.md`, `.tex`, `.ts`, `.html`).

---

## 2. Kernel, Chunk Execution & Inline Output Fixes

### Task 3.1 — Unify Execution Architecture & Isolate Per-Workspace Sessions
* **Current Architecture Flaw:** `ReplBridge` + `ChunkExecutionEngine` (which spawn raw interactive R/Python without PTY and hang 30s on R syntax errors) sit unused while `PersistentPanelRegistry` talks to a single global process-wide `PersistentSessionManager.get_default()`. Multiple tabs overwrite each other's working directory (`Window.vala:658`), pollute each other's `plot_gallery`, and leak stdout lines across tabs via singleton `session_output_received`!
* **Required Changes:**
  1. Refactor or deprecate/replace dead `ReplBridge` / `ChunkExecutionEngine` split-brain so ALL REPL execution uses one clean, rock-solid **Session Pool (`SessionCoordinator`)** keyed by `(project_root_or_doc_id)`:
     - Tabs in the same `.Rproj`/project folder share one project kernel pair (`r`, `python`, persistent shell), while separate projects or standalone files get isolated sessions.
     - Closing the last tab for a session cleanly shuts down its child R/Python processes (`stdin.close()` + wait + `force_exit()` fallback).
  2. Fix `PersistentSessionManager` protocol & lifecycle bugs (`src/services/PersistentSessionManager.vala`):
     - **Route `set_working_directory` (`L122-141`) through locked 4-field protocol execution (`setwd(...)` / `os.chdir(...)`)!** Previously raw `setwd` was silently discarded by `if (length(.parts) < 4L) next` (`L344`) and raced concurrent reads.
     - **Check process health (`L318-320, 373-375`):** Track `proc.wait_async` / `get_if_exited ()`. If R or Python dies (`q()`, `sys.exit()`, OOM), automatically mark `initialized = false` and restart cleanly on next command.
     - **Eliminate blocking I/O & infinite hangs (`L125-126, 201-210, 270-279`):** Use `write_all_async` (non-blocking), add `GLib.Cancellable` + configurable execution timeout (e.g., 60s default, cancelable via UI **Interrupt / Stop** button!).
     - **Safe `SIGINT` / Cancellation (`L309-316`):** Run child sessions in a dedicated process group (`setsid` / host wrapper or signal handler that ignores `SIGINT` in outer R/Python protocol driver `tryCatch(..., interrupt=...)` / `signal.signal(SIGINT, ...)` while interrupting user code cleanly and still emitting `sentinel`).
     - **Per-Request Tagged Output Callback (Kill Singleton Signal Cross-Talk!):** Pass an optional per-call output callback `OutputLineFunc` (or tag every protocol frame with `req_id`) so `session_output_received` NEVER mixes background `EnvironmentController` / `DataGridViewer` / `Packages` probes or Tab B's output into Tab A's console or inline chunk output! Separate stdout and stderr clearly instead of merging stderr blindly into stdout or treating R `library()` startup messages as failures!
  3. **Fix R & Python Plot Capture (`PersistentSessionManager.vala:180-190, 256-258, 414-426`):**
     - **NEVER use `code.contains("print(")` or fragile keyword matching (`L189`) to guess whether a plot happened!**
     - **R:** Always parse user code first with `tryCatch(parse(text = src), error = ...)` (fixes R syntax-error hangs cleanly!), open a temp `grDevices::png(..., type="cairo")` device (fallback `svg` / default `png`), run with `withVisible()` handling (`ggplot2`/lattice objects auto-printed!), call `dev.off()` quietly, and check whether the PNG file exists AND differs from an empty blank plot (or check `grDevices::dev.cur()` + `grid` / `recordPlot()` / file existence after checking `dev.list()`!). Only register a plot when a non-empty graphics output was actually produced!
     - **Python:** Set `os.environ.setdefault("MPLBACKEND", "Agg")` and `matplotlib.use("Agg")` **at Python driver startup** (not conditionally inside an `if has_plot` block after `pyplot` was already imported!). Call `plt.close('all')` BEFORE running cell code inside a `try/finally` block, execute user code via `compile(src, '<chunk>', 'exec')` cleanly, check `len(plt.get_fignums()) > 0` afterwards, save each open figure (supporting multiple plots per cell cleanly!), and `plt.close('all')` in `finally`!

### Task 3.2 — Sequential Multi-Cell Queue, `Gtk.TextChildAnchor` Stability & `\uFFFC` Purge
* **Files:** `src/ui/PersistentPanelRegistry.vala` (`273-386`, `1355-1363`, `1431-1457`, `1475-1597`), `src/DocumentPage.vala` (`67-145`, `454-478`, `1010`), `src/Window.vala` (`1398`, `1406`, `1577`, `2116`, `2639`, `2879`).
* **Defects Fixed:**
  - `execute_all_cells`, `execute_cells_above`, `execute_cells_below` spawn all cells concurrently with stale upfront `ch.end_line`, causing line-shift collision (`+1` per prior widget), duplicate console output, and non-deterministic R/Python/Bash ordering.
  - `display_inline_chunk_output` uses `begin_user_action()`, poisoning Undo (`Ctrl+Z`).
  - `\uFFFC` (`\xef\xbf\xbc`) leaks into word stats, preview, recovery snapshots, ChunkParser, compile, export, GxP lock, and REPL!
  - `notebook_cell_toolbar` mislabels Run button `"Run Cell (Ctrl+Enter)"` instead of `Ctrl+Shift+Enter` and lacks horizontal scroll wrapping (`PersistentPanelRegistry.vala:273-386`).
* **Required Changes:**
  1. **Single Canonical Accessor:** Add `DocumentPage.get_clean_source_text ()` stripping `\uFFFC` (`"\xef\xbf\xbc"`) cleanly, and replace ALL raw `source_buffer.text` / `buffer.get_text(...)` calls across `DocumentPage`, `Window`, `PersistentPanelRegistry`, `RecoveryService`, `ExportService`, and `McpServer`!
  2. **Fix Inline Output Anchors & Undo (`DocumentPage.vala:67-145`):**
     - Key widgets by a stable `InlineAnchorEntry { Gtk.TextMark end_mark; Gtk.TextChildAnchor anchor; InlineChunkOutputWidget widget; }` placed at the closing fence line cleanly (`left_gravity = true` on end of fence or dedicated start/end marks), wrapped in **`source_buffer.begin_not_undoable_action ()` / `end_not_undoable_action ()`** so running/clearing chunks NEVER modifies Undo history or buffer `modified` flag!
     - Store `widget` cleanly inside `Gtk.TextChildAnchor`; before reusing, verify `!entry.anchor.get_deleted ()` and `widget.get_parent () != null`. Remove `\uFFFC` cleanly via the anchor's iter bounds `[iter, iter + 1]` in `clear_inline_chunk_outputs`.
     - Add `.inline-chunk-card` styling in `data/style.css`.
  3. **Serialize Multi-Cell Execution (`PersistentPanelRegistry.vala:1355-1457`):**
     - Convert `run_code_snippet_in_console`, `execute_active_cell`, `execute_all_cells`, `execute_cells_above`, `execute_cells_below` into **`async` sequential execution pipelines** (guarded by a `GLib.Cancellable` & `is_batch_running` state so Stop/Interrupt cancels remaining queued cells cleanly!):
     - Instead of reading `ch.end_line` once upfront, either:
       (a) Assign each chunk a temporary `Gtk.TextMark` at its `end_line` **before** starting the batch, and look up `mark_line` dynamically as each cell completes (deleting temp marks in `finally`), OR
       (b) Re-resolve the chunk end mark dynamically right before attaching the output!
     - Execute R, Python, Bash, AND TypeScript (`{ts}`) chunks strictly **one-by-one in document order**, updating `.ipynb` live cell outputs (`cell_id -> NbCellOutput[]`, `execution_count++`) after every cell finishes!
  4. **Fix `PersistentPanelRegistry` Misc Execution & Plot Routing Bugs:**
     - `notebook_cell_toolbar`: wrap in horizontal `Gtk.ScrolledWindow` (`vscrollbar_policy = NEVER`) and fix tooltip/label (`Ctrl+Shift+Enter` vs `Ctrl+Enter` line/selection).
     - Default kernel selector (`L436`) and `detect_engine_at_cursor()` (`L1317-1334`): consult `FormatProfile.default_kernel`! Never execute Python blindly when pressing `Ctrl+Enter` outside chunks in `.md`, `.qmd` (without Python focus), `.tex` (`"tex"`), `.ts` (`"typescript"`), or `.html` (`"html"`).
     - **`View(df)` (`L1482-1509`):** Strip comments/strings cleanly before detecting `View(...)`, parse nested parentheses properly (`View(head(df))`), execute `run_code_snippet_in_console` **FIRST (`yield`)**, and ONLY THEN switch Q1/data viewer and call `data_grid_viewer.fetch_and_display`! Also fix `move_tab` source quadrant lookup (`dock_state.find_panel_quadrant(PanelId.DATA_VIEWER)` instead of hardcoded `Q1`).
     - **`?topic` / `help(...)`:** Handle Python (`pydoc.render_doc`) for Python context instead of running R help; HTML-escape all help/plot fallback titles (`L1849, 2541-2545`).
     - **Plot Routing (`L1979-2015`):** Deliver generated plots ONLY to the owning tab/session (`PersistentPanelRegistry`), AND automatically activate/reveal `PanelId.PLOTS` in Q4 when a new plot is produced (if configured)! Add `PlotGalleryItem` timestamps cleanly.

### Task 3.3 — Fix `EnvironmentController`, `DataGridViewer` & Persistent Shell
* **Files:** `src/ui/EnvironmentController.vala` (`301-348`), `src/ui/DataGridViewer.vala` (`463-537`), `src/ExecutionEngine.vala`.
* **Required Fixes:**
  1. **`EnvironmentController.fetch_r_environment` (`L303-318`):** Fix `ls(envir = .GlobalEnv, all.names = FALSE)` and `get(x, envir = .GlobalEnv)` so R Global Environment populates reliably! Escape variable names cleanly when displaying in UI!
  2. **Polyglot Environment Support:** Track/display R and Python objects simultaneously (section headers or dual engine pill) on polyglot `.qmd`/`.ipynb` notebooks instead of overwriting one language's variables every time the other runs.
  3. **`DataGridViewer` (`L507-527`):** Stop interpolating raw `'obj_name'` into Python `eval('%s')` (validate identifier / pass safely via JSON/Base64 + `globals()[name]` or `eval` with Base64); vectorize Pandas serialization via `_d.iloc[...].to_csv(sep='\t', ...)` and sanitize tabs/newlines properly; handle 0-column R data.frames safely.
  4. **`ExecutionEngine.vala` + Shell Runner:** Bind working directory strictly to `project_root` (fallback document dir), add timeout + `GCancellable`, and parse CLI/runtime paths via fixed `PlatformUtils.resolve_runtime`.

---

## 3. Native Compilers & IntelliSense for `.tex`, `.ts`, `.html`, `.Rmd`, `.qmd`, `.ipynb`, `.md`

### Task 3.4 — Dedicated LaTeX Build Runner (`src/runners/LatexBuildRunner.vala`)
* **Problem Verified:** Zero TeX build runner exists anywhere in Imladris; pressing Run/Compile sends `.tex` files to Quarto or Python REPL!
* **Required Implementation:**
  1. Create `Imladris.Runners.LatexBuildRunner`:
     - Engine preference/auto-detection: `latexmk -pdf`/`-xelatex`/`-lualatex` (`-interaction=nonstopmode -file-line-error -synctex=1`), with direct fallback chain (`xelatex` / `lualatex` / `pdflatex` + `bibtex` / `biber` multi-pass when bibliography commands/files exist, cleanly discovering TeX binaries via host PATH / `/usr/lib/sdk/texlive/...` / TinyTeX).
     - Support compiling saved `.tex` in its directory (`working_dir = parent_dir`) or unsaved temp build dir cleanly while resolving project assets.
     - Parse `.log` output via Rust **`imladris_parse_latex_log_json`** extracting structured diagnostics (`file`, `line`, `severity: error|warning`, `message`) so errors highlight directly in Console/Diagnostics and jump editor cursor on click!
     - Upon PDF success: render PDF preview in Quadrant 4 (using embedded PDF.js / `pdftoppm` PNG/SVG page strip inside WebKit / Poppler / or Evince button fallback) AND emit path to status bar + Logs.

### Task 3.5 — Dedicated TypeScript Runner & TypeChecker (`src/runners/TypeScriptRunner.vala`)
* **Problem Verified:** Zero TS runner exists (`ExecutionEngine.vala:39` only had a comment; `Window.vala:2882` sent `.ts` to Python!).
* **Required Implementation:**
  1. Create `Imladris.Runners.TypeScriptRunner`:
     - Discover JS/TS runtimes via `PlatformUtils.resolve_runtime`: project `node_modules/.bin/tsc` / `tsx`, global/host **`node`** (v22.6+ native `--experimental-strip-types` / v22.18+ native `.ts`!), **`deno run`**, **`bun run`**, **`npx tsx`**, **`tsc --noEmit --pretty false`**.
     - **Actions:**
       - `Run File` / `Run {ts} Chunk`: executes TypeScript cleanly, streaming ANSI-stripped stdout/stderr to Console/InlineChunkOutputWidget with exit code + duration HUD.
       - `Typecheck`: runs `tsc --noEmit` (respecting nearest `tsconfig.json`), parsing `file(line,col): error TSxxxx: msg` diagnostics into clickable error rows!
       - `Eval Selection / Line`: executes active line/selection cleanly in ephemeral/temp TS harness via Node/Deno!
  2. Wire `{ts}` / `{typescript}` chunk execution cleanly in `PersistentPanelRegistry` and `McpServer` (`chunk` & `run`!).

### Task 3.6 — Fix `CodeIntelliSenseEngine.vala` & `CodeIntelliSenseProvider.vala`
* **Files:** `src/editor/CodeIntelliSenseEngine.vala` (`321-774`), `src/editor/CodeIntelliSenseProvider.vala` (`101-200`).
* **Required Changes:**
  1. **Add full `TYPESCRIPT_CODE` handling:** Build `ts_catalog` (built-in globals, types `string`, `number`, `boolean`, `Promise`, `Record`, `Partial`, `interface`, `type`, `async`, `Array`/`Map`/`Set`, DOM/Node/Deno helpers) AND integrate Rust `imladris_analyze_typescript_symbols_json` (or `.ts` buffer parser) into `scan_buffer_symbols` + `query_completions`!
  2. **Add `.tex` (`LATEX_MATH_CHEM`) document mode & completions:** Recognize `doc_type == "latex" || doc_type == "tex"`, suggest document/preamble commands (`\documentclass`, `\usepackage`, `\section`, `\subsection`, `\begin{equation}`, `\begin{align}`, `\begin{figure}`, `\includegraphics`, `\cite`, `\bibliography`, `\ref`, `\label`) alongside `\ce{}` and math macros!
  3. **Fix `scan_buffer_symbols` backtick bug (`L463`):** Use `doc_type` to decide whether the file is a fenced notebook (`qmd`/`rmd`/`ipynb`/`md`) vs a pure script (`.R`/`.py`/`.ts`) so triple backticks inside Python/R docstrings NEVER turn off script completions!
  4. **Fix Quarto `#|` completion corruption (`L617-628`):** Extract the key/value after `#|` cleanly (`echo`, `eval`, `label`, `fig-cap`, `warning`, `error`, `output`, `include`) so completing after `#| echo: t` never produces `#| echo: echo: true`.
  5. **Sort merged REPL variables + static catalog proposals cleanly (`CodeIntelliSenseProvider.vala:174-200`):** Merge and sort by `.score` before truncating at `max_items`.

### Task 3.7 — Fix `QuartoExportEngine.vala`, `ExportService.vala` & `Window.compile_scientific_document_async`
* **Files:** `src/core/QuartoExportEngine.vala`, `src/services/ExportService.vala`, `src/Window.vala` (`1398-1406`, `1555-1608`, `2879-2890`).
* **Required Fixes:**
  1. **Route compilation cleanly by `FormatProfile` (`Window.vala:1555-1608`):**
     - `.qmd` -> `QuartoExportEngine` (respect `_quarto.yml` `output-dir` / frontmatter `output-file` when checking generated output instead of failing on `<root><ext>` at `QuartoExportEngine.vala:86`!; **STOP** letting `ToolchainManager` `configure_managed_env` override project `.imladris-env` / `.venv` with `base-ds` `QUARTO_PYTHON`/`QUARTO_R`!).
     - `.Rmd` -> **`rmarkdown::render`** via `Rscript` (with safe Base64/JSON-passed arguments instead of raw string interpolation and with explicit `output_dir`/`output_file`!) or Quarto fallback if user selects Quarto explicitly.
     - `.ipynb` -> sync live outputs + `quarto render` OR `python3 -m nbconvert` -> HTML/PDF!
     - `.md` -> Pandoc (with math + Mermaid pre-render) or Playwright/WebKit print-to-PDF!
     - `.tex` -> `LatexBuildRunner` (PDF) or Pandoc (`-f latex`) for HTML/ODT/RTF!
     - `.ts` -> `TypeScriptRunner` (Run / Typecheck)!
     - `.html` -> WebKit Refresh / `webkit_print_operation` PDF / Browser launch!
  2. **Stop Swallowing Compiler Failures in `ExportService.vala` (`L107-460`):**
     - **Rule:** When Quarto, `rmarkdown`, LaTeX, or Pandoc IS invoked for `.qmd`/`.Rmd`/`.ipynb`/`.tex` and fails with a non-zero exit code, **surface the structured compiler error directly to the user (`return false` + toast + Console log)**! NEVER silently swallow the failure, run the naive text-stripping OASIS/RTF writer, and pop `"✔ Successfully exported"`!
     - Fix `pandoc_from`: support `"latex"`, `"gfm"`, `"markdown"`, `"html"`, `"ipynb"`.
     - Fix `materialize_input` (`L53-71`): run unsaved temporary copies in a per-export dir with sibling resources (or `resource-path` set to `project_dir` / `document_dir`), strip `\uFFFC`, and pass `existing_raw_file` for `.ipynb`.
     - Escape `<title>` in HTML fallback (`L298`), add `-env:UserInstallation=file:///tmp/imladris-lo-<pid>` to LibreOffice (`L681`), use `PlatformUtils.resolve_runtime("python3")` in `package_oasis_zip` (`L747`), and make subprocess calls async with timeouts + `GCancellable`.
  3. **Fix `Window.source_active_file` (`L2882`):** Dispatch by `FormatProfile`: `.R`/`.Rmd` -> R `source()`; `.py` -> Python `exec()`; `.ts` -> `TypeScriptRunner`; `.tex` -> `LatexBuildRunner`; `.qmd`/`.ipynb` -> `execute_all_cells ()` (NOT sending raw `.qmd`/`.tex`/`.html`/`.ts` into Python!).

---

## 4. Phase 3 Verification Checklist

- [ ] Sequential `Run All`, `Run Above`, and `Run Below` on multi-chunk `.qmd`, `.Rmd`, and `.ipynb` files (mix of R, Python, Bash, TS chunks + plain ```json display blocks) execute **in exact order**, place every inline output card strictly after its own chunk's closing fence (zero line drift!), preserve clean `Ctrl+Z` Undo history, and leave zero `\uFFFC` characters anywhere in saved files/exports/snapshots.
- [ ] Switching between two open project tabs keeps their `working_directory`, REPL variables, console output streams, and plot galleries completely isolated.
- [ ] `set_working_directory`, `EnvironmentController` (R `.GlobalEnv` + Python `globals()`), `View(df)` on newly created DataFrames, and plot generation without `"print("` hacks (`ggplot(mtcars, aes(wt, mpg)) + geom_point()` stored in `p; p`) all work reliably.
- [ ] Running/compiling `.tex` (`pdflatex`/`lualatex`) builds PDF and populates line-numbered diagnostics; running/typechecking `.ts` (`node`/`tsc`/`deno`) executes code and shows TS diagnostics cleanly.
- [ ] Failing Quarto/RMarkdown/LaTeX/Pandoc exports display real compiler error diagnostics and NEVER show false `"✔ Successfully exported"` messages.
