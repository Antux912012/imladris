<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# IMLADRIS PRODUCTION ARCHITECTURE REVIEW & GEMINI 3.8-FLASH-MEDIUM EXECUTION BLUEPRINT

**Document ID:** `IML-ARCH-PROD-2026-01`  
**Target Executor Model:** `Gemini 3.8-Flash-Medium`  
**Standard:** ASD-STE100 (Simplified Technical English) · REUSE 3.3 · Google SWE / DeepMind Production Readiness  
**Target Stack:** Vala (`valac` 0.56+ / C11 Codegen), GTK4 (`4.14+`), Libadwaita (`1.5+`), WebKitGTK (`6.0`), `libsoup-3.0`, `json-glib-1.0`, `libsecret-1`  
**Reviewed Baseline:** Imladris `v0.18.0` (`main` @ `7da249a`)  

---

## 1. EXECUTIVE ARCHITECTURAL ASSESSMENT

Imladris has achieved an impressive foundation as a native GTK4/Libadwaita scientific workbench: it integrates Quarto/Typst/LaTeX authoring, Mallorn/Micromamba environments (`renv` + `uv`), the **Arekyer** Galaxy Project provenance bridge, the **Yavanna** Bio-Entity & Oligo resolver, and an interactive Cairo **Mermaid Flow & Mindmap Studio**.

However, transitioning Imladris from a **feature-rich open-source prototype** to a **mission-critical production platform** for academic core facilities, structural biology groups (AlphaFold / cryo-EM / genomics), and regulated biotech/pharma R&D corporations requires resolving **five P0/P1 architectural hazards** and closing **four core bioinformatics & enterprise reproducibility gaps**.

### 1.1 Production Readiness Scorecard

| Architectural Pillar | Current Score | Target Score | Primary Bottleneck Identified in Baseline (`v0.18.0`) |
| :--- | :---: | :---: | :--- |
| **IPC & Kernel Concurrency** | **5.5 / 10** | **9.8 / 10** | Unserialized `read_line_async` on shared `GDataInputStream` in `PersistentSessionManager.vala`; duplicate R/Python processes between `ReplBridge` and `PersistentSessionManager`. |
| **GTK4 Thread Safety & Memory** | **6.5 / 10** | **9.8 / 10** | `McpServer.vala` mutates `GtkSource.Buffer` and `Gtk.Widget` state directly from a background OS `GLib.Thread`. |
| **ValaCC / C Codegen Hygiene** | **7.5 / 10** | **10.0 / 10** | C compiler pointer-incompatibility warnings (`-Wincompatible-pointer-types`), deprecated GTK 4.10+ APIs, and monolithic `Window.vala` (2,674 LOC). |
| **Bioinformatics & Structural Biology** | **7.8 / 10** | **9.6 / 10** | Missing 3D macromolecular structure & AlphaFold pLDDT/PAE confidence bridge; 2,000-row hard truncation in `DataGridViewer.vala` using slow row-by-row loops. |
| **Corporate GxP / CRA Provenance** | **7.0 / 10** | **9.7 / 10** | Missing cryptographic SHA-256 dataset & environment attestation manifest (`imladris-provenance.lock.json`) required by pharma/biotech audit trails (FDA 21 CFR Part 11 / EU CRA). |

---

## 2. CRITICAL BUGS & CONCURRENCY HAZARDS (ROOT-CAUSE ANALYSIS)

### 2.1 [P0-CRITICAL] Concurrent `GDataInputStream` Read Collision & Dual-Kernel Split-Brain
* **Location:** `src/services/PersistentSessionManager.vala` (lines 72–215), `src/editor/ChunkExecutionEngine.vala` (lines 43–167), `src/console/ReplBridge.vala` (lines 1–165).
* **Root Cause:**
  1. `PersistentSessionManager.execute_r ()` (line 121) and `execute_python ()` (line 191) call `yield r_stdout.read_line_async (GLib.Priority.DEFAULT, null)` directly without an asynchronous FIFO queue or mutex. When two callers invoke `execute_r` concurrently (for example: clicking **Run All**, or executing a chunk while `EnvironmentPanel` or `DataGridViewer` refreshes workspace variables), GIO immediately throws `G_IO_ERROR_PENDING` (`Stream has outstanding operation`). The `catch (GLib.Error e)` block at line 141 sets `r_initialized = false`, silently dropping the session and orphaning the underlying `R --vanilla` child process.
  2. **Split-Brain Subprocesses:** `DocumentPage` spawns interactive `ReplBridge` subprocesses for `ChunkExecutionEngine`, while `PersistentSessionManager` spawns a *second* pair of `R` and `python3` subprocesses for `DataGridViewer` and `EnvironmentPanel`. Variables created via `ChunkExecutionEngine` (`ReplBridge`) do not exist in `PersistentSessionManager`, and vice versa.
  3. **Python Indentation Corruption (`PersistentSessionManager.vala:167-176`):** When `has_plot` is `true`, `execute_python` prepends `"    "` to every line of `code` to nest it inside a `try:` block. Any user code containing multiline triple-quoted strings (`"""SQL or FASTA"""`) has whitespace injected into the string literal, corrupting data. (By contrast, `ChunkExecutionEngine.vala:79-100` properly uses `GLib.Base64.encode` + `exec(compile(...))`).
  4. **Busy-Wait Polling (`ChunkExecutionEngine.vala:136-139`):** `execute_chunk` polls `while (!output_buffer.str.contains (sentinel))` every `50ms` via `Nap.sleep (50)`, performing repeated $O(N)$ substring scans over the entire stdout buffer instead of resolving a `GLib.SourceFunc` continuation when the sentinel line arrives.

### 2.2 [P0-CRITICAL] GTK4 Main-Thread Violation in `McpServer`
* **Location:** `src/McpServer.vala` (lines 141–190).
* **Root Cause:** `run_stdio_server_async` spawns an OS worker thread (`new GLib.Thread<void*> ("mcp-stdio-worker", ...)` at line 180) and invokes `handle_json_rpc (line, win)` -> `execute_tool (...)` **directly on that background thread**. Inside `execute_tool`, lines 149–170 read `doc.source_buffer.text`, mutate `doc.source_buffer.insert_at_cursor (txt, -1)`, and call `window.trigger_render (fmt)`.
* **Impact:** GTK4 and `GtkSourceView-5` are strictly single-threaded (`GLib.MainContext.default ()`). Mutating a `GtkSource.Buffer` from a foreign OS thread corrupts the B-tree line index and triggers fatal Pango/GDK assertions under load.
* **Secondary Bugs in `McpServer.vala`:**
  * Line 95: `return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"" + e.message + "\"}}";` injects unescaped `e.message` into raw JSON.
  * Line 165: `string[] parts = cmd.split (" ");` breaks quoted CLI arguments (e.g., `python3 -c "import math; print(math.pi)"`). Must use `GLib.Shell.parse_argv`.

### 2.3 [P1-HIGH] Inline Chunk Output Anchor Drift & Buffer Mutation
* **Location:** `src/DocumentPage.vala` (lines 60–81).
* **Root Cause:** `display_inline_chunk_output` indexes `inline_chunk_widgets` by `int end_line` (static integer line number) and calls `source_buffer.insert (ref iter, "\n", 1)` before creating a `Gtk.TextChildAnchor`.
* **Impact:**
  1. When the researcher types or deletes lines *above* an executed code chunk, the chunk's `end_line` changes. Re-executing the chunk fails to find the previous widget in `inline_chunk_widgets` and inserts a second orphaned widget into the buffer.
  2. Inserting `\n` directly into `source_buffer` marks the document as modified and permanently adds blank lines around child anchors every time a chunk is run.
* **Fix:** Key inline chunk widgets by a persistent `Gtk.TextMark` (with `left_gravity = false`) placed at the closing ```` ``` ```` fence line, and reuse the existing `Gtk.TextChildAnchor` attached to that mark.

### 2.4 [P1-HIGH] `DataGridViewer` $O(N \times M)$ Serialization & Silent `mtcars` Fallback
* **Location:** `src/ui/DataGridViewer.vala` (lines 334–410).
* **Root Cause:**
  1. `fetch_r_dataframe` loops row-by-row in R (`for (i in seq_len(n)) { row_vals <- as.character(as.vector(t(d[i, , drop = FALSE]))) ... }`) and `fetch_python_dataframe` uses `_d.head(2000).iterrows()`. In both R and Pandas, row-wise iteration over 2,000 rows incurs massive S3/Series boxing overhead (~800 ms) instead of vectorized `write.table(d[offset:limit, ], sep="\t")` or `_d.iloc[offset:limit].to_csv(sep="\t")` (~12 ms).
  2. Both methods hard-truncate at `2000` rows with no virtual page window (`offset` / `page_size`) or column summary statistics (missing values, mean/SD, data type badges).
  3. Lines 400–407 silently display hardcoded `mtcars` data whenever a query returns empty or errors out—a dangerous anti-pattern in scientific software where displaying fabricated numbers can mislead an analyst.

### 2.5 [P2-MEDIUM] ValaCC / C Compiler Diagnostics & Headless D-Bus Lifecycle
* **Locations:**
  * `src/Application.vala:182`, `src/core/SettingsManager.vala:603`: Uses deprecated `Gtk.StyleContext.add_provider_for_display`.
  * `src/bridges/galaxy_client.vala:210`: `GalaxyClient ()` constructor unconditionally fires `load_api_key_async.begin (...)` even in headless unit tests where `org.freedesktop.secrets` is unavailable, causing `GTask secret_service_async_initable_init_async finalized without ever returning` warnings.
  * `src/Window.vala` (2,674 lines): Exceeds single-responsibility sizing guidelines; ribbon construction, citation inspection, and export orchestration should be modularized.

---

## 3. MISSING BIOINFORMATICS, DEEP LEARNING & ENTERPRISE CAPABILITIES

Drawing from production workflows in structural biology (AlphaFold / DeepMind / EMBL-EBI), high-throughput genomics, and pharmaceutical GxP environments, Imladris requires four high-impact capabilities to become the undisputed standard workbench:

### 3.1 Structural Biology & AlphaFold Confidence Bridge (`Imladris.Bridges.Taniquetil`)
* **Problem:** Structural biologists and protein engineers routinely analyze **AlphaFold 2 / AlphaFold 3** models alongside sequence alignments and molecular dynamics trajectories in Quarto manuscripts. Currently, researchers must manually query the AlphaFold Protein Structure Database (AFDB) or RCSB PDB, download `.pdb`/`.cif` files and PAE JSON matrices, and write boilerplate plotting code for per-residue **pLDDT** (predicted Local Distance Difference Test) confidence scores.
* **Solution:** A single-file structural biology bridge (`src/bridges/taniquetil/AlphaFoldBridgePopover.vala`) that:
  1. Resolves any UniProt accession against the **EBI AlphaFold DB REST API** (`https://alphafold.ebi.ac.uk/api/prediction/{uniprot}`).
  2. Parses model version, mean/per-region **pLDDT** confidence distribution (`Very High > 90`, `Confident 70–90`, `Low 50–70`, `Disordered < 50`), `.pdb`/`.cif` coordinates URL, and Predicted Aligned Error (`paeDocUrl`).
  3. Renders a native **Cairo pLDDT Confidence Domain Bar** inside the popover using the official AlphaFold color scale (`#0053D6`, `#65CBF3`, `#FFDB13`, `#FF7D45`).
  4. Injects reproducible **R (`bio3d` / `r3dmol`)** or **Python (`biotite` / `py3Dmol`)** code chunks and Markdown structural provenance citations directly into the active `.qmd` manuscript.

### 3.2 Cryptographic GxP / EU CRA Provenance Lockfile (`imladris-provenance.lock.json`)
* **Problem:** Biotech corporations, clinical genomics labs, and regulatory bodies (FDA 21 CFR Part 11, EMA Annex 11, EU Cyber Resilience Act) require cryptographic proof of **which exact input files, cloud datasets, R/Python package lockfiles (`renv.lock`, `uv.lock`), and Quarto runtime versions** produced a compiled PDF/HTML report.
* **Solution:** A deterministic `ProvenanceAttestationService` (`src/core/ProvenanceAttestationService.vala`) that computes SHA-256 digests (`GLib.ChecksumType.SHA256`) of the source `.qmd` file, local data files referenced in chunks, `renv.lock` / `uv.lock` / `environment.yml`, and injected Arekyer/Yavanna/Taniquetil metadata, writing a signed/verifiable `imladris-provenance.lock.json` sidecar upon every render.

### 3.3 Vectorized Paginated `DataGridViewer` with Column Type & NA Profiling
* **Problem:** Genomics tables (`DESeq2` results with 60,000 genes, `vcf` variant tables, single-cell metadata) exceed 2,000 rows.
* **Solution:** Replace the row-by-row R/Python loop in `DataGridViewer.vala` with vectorized slice serialization (`offset`, `page_size = 1000`), add Prev/Next page navigation controls, display per-column type badges (`dbl`, `int`, `chr`, `fct`) + `NA` counts, and remove the fabricated `mtcars` fallback in favor of an explicit diagnostic empty state.

### 3.4 Nextflow / Snakemake Workflow Provenance Inspector (`Imladris.Bridges.Celebrimbor`)
* **Problem:** Dry-lab bioinformatics pipelines execute upstream on HPC/Cloud via **Nextflow** (`nextflow.config`, `.nextflow.log`, `trace.txt`) or **Snakemake** (`Snakefile`), feeding downstream Quarto reports.
* **Solution:** A lightweight local workflow trace parser (`src/bridges/celebrimbor/WorkflowTraceInspector.vala`) that reads Nextflow execution traces (`trace.txt`) or Snakemake summaries in the project directory, summarizes task CPU/memory/duration metrics and container digests (`docker://` / `oras://`), and injects a reproducible pipeline execution summary table into the manuscript.

---

## 4. GEMINI 3.8-FLASH-MEDIUM EXECUTION BLUEPRINT (WORK PACKAGES)

> **INSTRUCTIONS FOR GEMINI 3.8-FLASH-MEDIUM:**  
> Execute the following 6 self-contained Work Packages (`WP-01` through `WP-06`) sequentially.  
> * Every new or modified file **MUST** start with the 2-line REUSE 3.3 SPDX header (`// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>` and `// SPDX-License-Identifier: GPL-3.0-or-later`).  
> * All comments and UI strings **MUST** follow **ASD-STE100** (Simplified Technical English: active voice, concrete technical nouns, zero AI-slop filler).  
> * Zero new external C/Vala library dependencies may be added to `meson.build`. Use only the existing dependencies (`gtk4`, `libadwaita-1`, `gtksourceview-5`, `libsoup-3.0`, `json-glib-1.0`, `libsecret-1`, `gee-0.8`, `cairo`).  
> * Verify each Work Package by compiling and running `ninja -C build test`.

---

### WORK PACKAGE 01 (`WP-01`): Thread-Safe `McpServer` MainContext Marshaling & Shell Argv Parsing

* **Target File:** `src/McpServer.vala`
* **Objective:** Eliminate the GTK4 cross-thread memory corruption hazard when servicing JSON-RPC requests from the `mcp-stdio-worker` thread, fix JSON error escaping, and parse CLI commands with `GLib.Shell.parse_argv`.

#### Technical Specification (`src/McpServer.vala`)
1. **Main-Thread Dispatch Helper (`dispatch_on_main_thread`):**
   * Create a private static method `string dispatch_tool_on_main_thread (string tool_name, Json.Object? args, Window? window)`:
   * If `GLib.MainContext.default ().is_owner ()` is `true`, call `execute_tool (tool_name, args, window)` directly.
   * Otherwise, allocate a `GLib.Mutex`, a `GLib.Cond`, a `bool completed = false`, and a `string result = ""`.
   * Schedule an idle callback via `GLib.MainContext.default ().invoke (() => { ... })` that executes `execute_tool (tool_name, args, window)`, locks the mutex, stores `result`, sets `completed = true`, signals the condition variable, and returns `GLib.Source.REMOVE`.
   * Wait on `cond.wait (mutex)` until `completed == true` and return `result`.
2. **Safe JSON Error Serialization:**
   * In `handle_json_rpc` `catch (GLib.Error e)` (lines 94–96), replace raw string concatenation with `Json.Builder` so quotes and newlines inside `e.message` are properly escaped.
3. **Proper Quoted Argument Parsing in `execute_code`:**
   * In `execute_tool` (`name == "execute_code"`, lines 161–167), replace `string[] parts = cmd.split (" ");` with:
     ```vala
     string[] argv;
     try {
         GLib.Shell.parse_argv (cmd, out argv);
     } catch (GLib.ShellError e) {
         return "Error: Invalid command syntax: " + e.message;
     }
     ExecutionEngine.run_command_async.begin (argv, doc);
     ```

---

### WORK PACKAGE 02 (`WP-02`): Async FIFO Mutex Queue & Base64 AST Harness in `PersistentSessionManager`

* **Target File:** `src/services/PersistentSessionManager.vala`
* **Objective:** Prevent `G_IO_ERROR_PENDING` stream crashes during concurrent R/Python evaluations, fix Python multiline string corruption by switching to Base64 + `exec(compile(...))`, and use cryptographic UUID sentinels.

#### Technical Specification (`src/services/PersistentSessionManager.vala`)
1. **Async FIFO Lock (`acquire_r_lock` / `release_r_lock` and `acquire_py_lock` / `release_py_lock`):**
   * Add private fields to `PersistentSessionManager`:
     ```vala
     private bool r_busy = false;
     private GLib.Queue<GLib.SourceFuncWrapper> r_wait_queue = new GLib.Queue<GLib.SourceFuncWrapper> ();
     private bool py_busy = false;
     private GLib.Queue<GLib.SourceFuncWrapper> py_wait_queue = new GLib.Queue<GLib.SourceFuncWrapper> ();
     ```
     where `private class SourceFuncWrapper { public GLib.SourceFunc cb; public SourceFuncWrapper (owned GLib.SourceFunc c) { this.cb = (owned) c; } }`.
   * Implement `private async void lock_r ()`:
     ```vala
     if (!r_busy) {
         r_busy = true;
         return;
     }
     r_wait_queue.push_tail (new SourceFuncWrapper (lock_r.callback));
     yield;
     ```
   * Implement `private void unlock_r ()`:
     ```vala
     var next = r_wait_queue.pop_head ();
     if (next != null) {
         GLib.Idle.add ((owned) next.cb);
     } else {
         r_busy = false;
     }
     ```
   * Wrap the body of `execute_r` with `yield lock_r (); try { ... } finally { unlock_r (); }` and `execute_python` with `yield lock_py (); try { ... } finally { unlock_py (); }`.
2. **Base64 Python Execution Harness (Replacing Naive Line Indentation):**
   * In `execute_python` (lines 150–186), remove the line-by-line `"    " + l` indentation loop.
   * Encode `code` via `string b64_code = GLib.Base64.encode (code.data);` and execute via:
     ```vala
     string sentinel = "__IMLADRIS_EOF_" + GLib.Uuid.string_random ().replace ("-", "") + "__";
     string payload = """
     import sys, os, base64, traceback
     _imladris_plot_path = r"%s"
     try:
         import matplotlib
         matplotlib.use('Agg')
         import matplotlib.pyplot as plt
         _imladris_has_mpl = True
     except Exception:
         _imladris_has_mpl = False
     try:
         _imladris_src = base64.b64decode("%s").decode('utf-8')
         exec(compile(_imladris_src, '<imladris-cell>', 'exec'), globals())
         if _imladris_has_mpl and plt.get_fignums():
             plt.savefig(_imladris_plot_path, dpi=150, bbox_inches='tight')
             plt.close('all')
     except Exception:
         traceback.print_exc(file=sys.stdout)
     print("%s", flush=True)
     """.printf (candidate_plot, b64_code, sentinel);
     ```
3. **Sentinel Cleanup:**
   * Use `GLib.Uuid.string_random ().replace ("-", "")` for R and Python sentinels and plot filenames instead of `GLib.Random.next_int ()` (which can produce negative integers).

---

### WORK PACKAGE 03 (`WP-03`): Event-Driven Sentinel Resolution in `ChunkExecutionEngine` & Persistent `Gtk.TextMark` Anchors in `DocumentPage`

* **Target Files:**
  * `src/editor/ChunkExecutionEngine.vala`
  * `src/DocumentPage.vala`
* **Objective:** Replace the 50ms busy-wait polling loop (`Nap.sleep (50)`) in `ChunkExecutionEngine` with an event-driven signal completion callback, and replace integer line-indexed inline output widgets in `DocumentPage` with edit-resilient `Gtk.TextMark` anchors.

#### Technical Specification
1. **`src/editor/ChunkExecutionEngine.vala` (lines 120–144):**
   * Replace the `while (!output_buffer.str.contains (sentinel))` loop with a direct signal-driven wakeup plus a single timeout timer:
     ```vala
     bool done = false;
     uint timeout_id = 0;
     GLib.SourceFunc? resume_cb = null;

     ulong out_id = active_bridge.output_received.connect ((text) => {
         output_buffer.append (text);
         if (!done && output_buffer.str.contains (sentinel)) {
             done = true;
             if (resume_cb != null) {
                 GLib.Idle.add ((owned) resume_cb);
                 resume_cb = null;
             }
         }
     });
     ulong err_id = active_bridge.error_received.connect ((text) => {
         error_buffer.append (text);
     });

     timeout_id = GLib.Timeout.add (30000, () => {
         timeout_id = 0;
         if (!done) {
             done = true;
             if (resume_cb != null) {
                 GLib.Idle.add ((owned) resume_cb);
                 resume_cb = null;
             }
         }
         return GLib.Source.REMOVE;
     });

     try {
         yield active_bridge.send_command (wrapped_code);
         if (!done && active_bridge.is_running) {
             resume_cb = execute_chunk.callback;
             yield;
         }
     } finally {
         if (timeout_id != 0) {
             GLib.Source.remove (timeout_id);
         }
         active_bridge.disconnect (out_id);
         active_bridge.disconnect (err_id);
     }
     ```
2. **`src/DocumentPage.vala` (lines 60–81):**
   * Add a `private Gee.HashMap<string, Gtk.TextMark> chunk_marks = new Gee.HashMap<string, Gtk.TextMark> ();` and change `inline_chunk_widgets` to `Gee.HashMap<string, UI.InlineChunkOutputWidget>`.
   * When `display_inline_chunk_output (int end_line, string text_output, string? plot_path, int count)` is called:
     * Scan existing `chunk_marks` to see if any mark currently resides on `end_line` or `end_line + 1`:
       ```vala
       string? matched_key = null;
       foreach (var entry in chunk_marks.entries) {
           Gtk.TextIter mark_iter;
           source_buffer.get_iter_at_mark (out mark_iter, entry.value);
           int mark_line = mark_iter.get_line ();
           if (mark_line == end_line || mark_line == end_line + 1) {
               matched_key = entry.key;
               break;
           }
       }
       ```
     * If `matched_key != null`, update the existing `InlineChunkOutputWidget` in-place without inserting a new `\n` or anchor into `source_buffer`.
     * Otherwise, create a new UUID key, insert the anchor once, and register a `Gtk.TextMark` at the anchor iter so subsequent line edits above the chunk automatically move the mark with the text.

---

### WORK PACKAGE 04 (`WP-04`): Vectorized Paginated `DataGridViewer` with Column Profiling & Safe Empty State

* **Target File:** `src/ui/DataGridViewer.vala`
* **Objective:** Replace the slow $O(N \times M)$ row-by-row R/Python loops with fast vectorized slice serialization, add pagination (`page_offset`, `page_size = 1000`), remove the fabricated `mtcars` fallback, and sanitize dataframe identifiers.

#### Technical Specification (`src/ui/DataGridViewer.vala`)
1. **Identifier Sanitization (`sanitize_identifier`):**
   * Add `private static bool is_safe_identifier (string name)` that verifies `GLib.Regex.match_simple ("^[A-Za-z_][A-Za-z0-9_.$\\[\\]]*$", name.strip ())`. Reject unsafe expressions before passing to R/Python.
2. **Pagination State & Toolbar Controls:**
   * Add private fields:
     ```vala
     private int current_offset = 0;
     private int page_size = 1000;
     private int total_df_rows = 0;
     private int total_df_cols = 0;
     private Gtk.Button btn_prev_page;
     private Gtk.Button btn_next_page;
     private Gtk.Label page_label;
     ```
   * Add `[ < ]`, `page_label` (`"Rows 1–1000"`), and `[ > ]` buttons to `setup_toolbar ()`.
3. **Vectorized R Dataframe Serializer (`fetch_r_dataframe`):**
   * Replace the `for (i in seq_len(n))` loop with vectorized `apply`/`do.call(paste, ...)`:
     ```vala
     int start_row = current_offset + 1;
     int end_row = current_offset + page_size;
     string r_code = """
     local({
       if (!exists('%s', envir = .GlobalEnv)) {
         cat('__ERROR__\tObject not found in R GlobalEnv\n')
       } else {
         d <- get('%s', envir = .GlobalEnv)
         if (is.matrix(d)) d <- as.data.frame(d)
         nr <- nrow(d); nc <- ncol(d)
         cols <- colnames(d)
         if (is.null(cols)) cols <- paste0('V', seq_len(nc))
         types <- vapply(d, function(x) class(x)[1], character(1))
         headers <- paste0(cols, ' [', types, ']')
         cat('__COLS__\t', paste(headers, collapse = '\t'), '\n', sep='')
         if (nr > 0) {
           idx <- seq.int(min(%dL, nr), min(%dL, nr))
           sub_d <- d[idx, , drop = FALSE]
           sub_chr <- lapply(sub_d, function(col) {
             v <- as.character(col)
             v[is.na(v)] <- 'NA'
             gsub('[\t\r\n]', ' ', v)
           })
           lines <- do.call(paste, c(sub_chr, sep = '\t'))
           cat(paste0('__ROW__\t', idx, '\t', lines, collapse = '\n'), '\n', sep='')
         }
         cat('__DONE__\t', nr, '\t', nc, '\n', sep='')
       }
     })
     """.printf (obj_name, obj_name, start_row, end_row);
     ```
4. **Vectorized Python Dataframe Serializer (`fetch_python_dataframe`):**
   * Replace `.iterrows()` with vectorized Pandas/NumPy formatting:
     ```vala
     int start_idx = current_offset;
     int end_idx = current_offset + page_size;
     ```
     Extract column names + `dtype` badges (`f"{c} [{_d[c].dtype}]"`), slice `_sub = _d.iloc[start_idx:end_idx]`, convert tabs/newlines safely, and emit `__ROW__\t{row_num}\t{tsv_line}` and `__DONE__\t{total_rows}\t{total_cols}`.
5. **Remove Fabricated `mtcars` Fallback:**
   * Delete lines 400–407 (`cols = { "mpg", "cyl", ... }`). If `cols.length == 0 && rows.size == 0`, display a clear diagnostic row: `new DataRow (0, new string[] { "—", @"Object '$obj_name' is empty or not loaded in active session." })`.

---

### WORK PACKAGE 05 (`WP-05`): Taniquetil — AlphaFold DB & Macromolecular Confidence Bridge

* **Target File:** `src/bridges/taniquetil/AlphaFoldBridgePopover.vala` (Strictly Single-File Implementation)
* **Wiring Files:** `src/Window.vala` (HeaderBar button next to Yavanna), `meson.build`
* **Objective:** Bring DeepMind **AlphaFold Protein Structure Database (AFDB)** and **RCSB PDB** structural bioinformatics directly into Imladris, complete with a native Cairo **pLDDT Confidence Domain Track** and reproducible R (`bio3d`) / Python (`biotite` / `py3Dmol`) code chunk injectors.

#### Class & Signal Contract (`src/bridges/taniquetil/AlphaFoldBridgePopover.vala`)

```vala
namespace Imladris.Bridges.Taniquetil {

    public errordomain TaniquetilError {
        NETWORK_ERROR,
        STRUCTURE_NOT_FOUND,
        PARSE_ERROR
    }

    public class AlphaFoldBridgePopover : Gtk.Popover {
        /**
         * Emitted when the user clicks an injection button to insert
         * a Markdown structural provenance badge or an R/Python 3D structure chunk.
         */
        public signal void insert_snippet_requested (string qmd_snippet);

        private Soup.Session http_session;
        private GLib.Cancellable? active_cancellable;

        public AlphaFoldBridgePopover ();
    }
}
```

#### Functional Requirements
1. **REST Query (`https://alphafold.ebi.ac.uk/api/prediction/{uniprot_accession}`):**
   * Asynchronous `Soup.Session.send_and_read_async` GET request with `Accept: application/json`.
   * Parse the first prediction object in the returned JSON array:
     * `entryId` (e.g., `"AF-P04637-F1"`)
     * `uniprotAccession` (e.g., `"P04637"`), `uniprotId` (e.g., `"P53_HUMAN"`), `gene` (e.g., `"TP53"`)
     * `organismScientificName` (e.g., `"Homo sapiens"`)
     * `uniprotEnd` (int64 sequence length in residues)
     * `globalMetricValue` (double mean pLDDT score, `0.0`–`100.0`)
     * `fractionPlddtVeryHigh` (double `0.0`–`1.0`, pLDDT > 90)
     * `fractionPlddtConfident` (double `0.0`–`1.0`, 70 < pLDDT <= 90)
     * `fractionPlddtLow` (double `0.0`–`1.0`, 50 < pLDDT <= 70)
     * `fractionPlddtVeryLow` (double `0.0`–`1.0`, pLDDT <= 50)
     * `pdbUrl` (string), `cifUrl` (string), `paeDocUrl` (string)
     * `latestVersion` (int64)
2. **Native Cairo pLDDT Confidence Stacked Bar (`Gtk.DrawingArea`):**
   * Render a proportional horizontal bar (height `22px`, rounded corners `6px`) showing the 4 official AlphaFold confidence fractions:
     * **Very High (`pLDDT > 90`):** `#0053D6`
     * **Confident (`90 >= pLDDT > 70`):** `#65CBF3`
     * **Low (`70 >= pLDDT > 50`):** `#FFDB13`
     * **Very Low / Disordered (`pLDDT <= 50`):** `#FF7D45`
3. **Injected Snippet Templates:**
   * **`[ + Markdown Badge ]`:**
     `[**{entry_id}** ({gene} / UniProt:{uniprot} | {length} aa | Mean pLDDT: {global_plddt:.1f} | Very High: {vh_pct:.1f}% | Verified: {YYYY-MM-DD})](https://alphafold.ebi.ac.uk/entry/{uniprot})`
   * **`[ + R Bio3D Chunk ]`:**
     ````markdown
     ```{r taniquetil-{entry_id}, message=FALSE}
     # TANIQUETIL ALPHAFOLD PROVENANCE: {entry_id} ({gene} | Mean pLDDT: {global_plddt:.1f})
     af_pdb_url <- "{pdb_url}"
     af_pae_url <- "{pae_url}"
     af_pdb_file <- tempfile(fileext = ".pdb")
     utils::download.file(af_pdb_url, af_pdb_file, quiet = TRUE)
     pdb_model <- bio3d::read.pdb(af_pdb_file)
     # Extract per-residue pLDDT stored in the B-factor column
     plddt_scores <- pdb_model$atom[pdb_model$calpha, "b"]
     summary(plddt_scores)
     ```
     ````
   * **`[ + Py Structure & PAE Chunk ]`:**
     ````markdown
     ```{python taniquetil-{entry_id}}
     # TANIQUETIL ALPHAFOLD PROVENANCE: {entry_id} ({gene} | Mean pLDDT: {global_plddt:.1f})
     import requests
     af_cif_url = "{cif_url}"
     af_pae_url = "{pae_url}"
     pae_resp = requests.get(af_pae_url, timeout=15)
     pae_resp.raise_for_status()
     pae_data = pae_resp.json()
     print(f"Loaded {entry_id}: mean pLDDT = {global_plddt:.1f} ({length} residues)")
     ```
     ````

---

### WORK PACKAGE 06 (`WP-06`): Cryptographic GxP / EU CRA Provenance Lockfile Service (`imladris-provenance.lock.json`)

* **Target File:** `src/core/ProvenanceAttestationService.vala` (Strictly Single-File Implementation)
* **Wiring Files:** `src/Window.vala` (triggered automatically after Quarto/Typst render and via menu action `win.export_provenance_lock`), `meson.build`
* **Objective:** Generate a cryptographically verifiable SHA-256 provenance manifest (`imladris-provenance.lock.json`) alongside rendered manuscripts to satisfy enterprise pharma/biotech GxP (21 CFR Part 11) and EU Cyber Resilience Act audit requirements.

#### Class & Method Contract (`src/core/ProvenanceAttestationService.vala`)

```vala
namespace Imladris.Core {

    public class ProvenanceAttestationService : GLib.Object {
        /**
         * Computes SHA-256 checksums for the manuscript, environment lockfiles
         * (renv.lock, uv.lock, environment.yml, _quarto.yml), and extracted
         * Arekyer/Yavanna/Taniquetil cloud provenance records, writing a
         * deterministic JSON manifest to `<document>.provenance.lock.json`.
         */
        public static async string generate_attestation_async (
            string document_path,
            string document_content,
            string project_dir
        ) throws GLib.Error;

        /**
         * Computes the lowercase hex SHA-256 digest of a byte buffer or file.
         */
        public static string compute_sha256_string (string content);
        public static string? compute_sha256_file (string file_path);
    }
}
```

#### Manifest Schema (`<document>.provenance.lock.json`)
* `schemaVersion`: `"1.0"`
* `generator`: `"Imladris Scientific Workbench v0.18.0"`
* `timestampUtc`: ISO-8601 UTC timestamp (`GLib.DateTime.now_utc ().format_iso8601 ()`)
* `manuscript`: `{ "path": "...", "sha256": "...", "lineCount": ... }`
* `environmentLocks`: Array of `{ "file": "renv.lock" | "uv.lock" | "environment.yml" | "_quarto.yml", "sha256": "..." }` for every lockfile present in `project_dir`.
* `externalBioEntities`: Array of regex-extracted provenance headers from the manuscript (`# AREKYER PROVENANCE RECORD`, `# YAVANNA BIO-ENTITY PROVENANCE:`, `# TANIQUETIL ALPHAFOLD PROVENANCE:`).
* `attestationDigest`: Master SHA-256 digest computed over the concatenated hashes above.

---

## 5. VALACC & GTK4/LIBADWAITA CODEBASE OPTIMIZATION CHECKLIST

When executing the Work Packages above or performing maintenance touches, apply these Vala/C codegen optimizations:

1. **Headless Secret Service Guard (`src/bridges/galaxy_client.vala:208`):**
   * Before calling `load_api_key_async.begin` in `load_initial_configuration ()`, check `GLib.Environment.get_variable ("DBUS_SESSION_BUS_ADDRESS") != null`. If `null` (such as inside headless CI / `meson test`), skip D-Bus keyring initialization to eliminate the `GTask secret_service_async_initable_init_async finalized without ever returning` warning.
2. **Eliminate C Pointer Type Warnings (`-Wincompatible-pointer-types`):**
   * In Vala 0.56 with GTK4, passing `Gtk.Popover` to `Gtk.MenuButton.popover` property works cleanly without warnings, whereas calling `.set_popover (Gtk.Widget)` emits a C pointer cast warning in GCC 16 when passed a subclass (`BioEntityPopover`, `AlphaFoldBridgePopover`). Always assign `menu_btn.popover = popover_instance;` or cast `menu_btn.set_popover ((Gtk.Popover) popover_instance);`.
3. **Avoid String Allocations Inside Cairo `SetDrawFunc` Loops:**
   * In custom `Gtk.DrawingArea` widgets (`MermaidFlowStudioDialog.vala`, `AlphaFoldBridgePopover.vala`), never allocate `GLib.Regex` or perform disk I/O inside `set_draw_func`. Precompute layout geometries and numeric ratios when state changes and call `queue_draw ()`.

---

## 6. VERIFICATION & ACCEPTANCE MATRIX FOR GEMINI 3.8-FLASH-MEDIUM

After implementing `WP-01` through `WP-06`, execute the following verification suite inside the Flatpak SDK (`org.gnome.Sdk//51`) or host Meson environment:

```bash
meson compile -C build
meson test -C build --print-errorlogs
```

All existing unit tests plus the new unit assertions for:
1. `PersistentSessionManager` FIFO queue serialization (`WP-02`),
2. `ProvenanceAttestationService.compute_sha256_string` & manifest generation (`WP-06`), and
3. `AlphaFoldBridgePopover` JSON parsing & pLDDT fraction calculation (`WP-05`)
must pass with **0 errors** and **0 unhandled `GTask` warnings**.
