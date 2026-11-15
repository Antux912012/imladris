<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Building File 02 — Rust `imladris-core` Engine, Parsing & Multi-Format Rendering

**Phase:** 2 of 4
**Prerequisites:** Phase 1 complete (`FormatProfile` & `DocumentFormat.TEX` / `TS` live).
**Primary Ownership:** New `rust/imladris_core/` crate + `meson.build` integration + `src/core/NativeCore.vala` / `.vapi`, `src/core/ChunkParser.vala`, `src/core/frontmatter_parser.vala`, `src/core/notebook_serializer.vala`, `src/adapters/DocumentAdapter.vala`, `src/core/MathChemEngine.vala`, `src/core/MermaidFlowEngine.vala`, `src/ui/WebViewFactory.vala`, `src/DocumentPage.vala`.

---

## 1. Objective

Replace fragile, order-dependent regex transformations with a **deterministic parsing and rendering pipeline** backed by a safe **Rust C-ABI static library (`imladris-core`)** integrated cleanly into Meson and Vala:
1. Eliminate chunk-fence misparsing (plain Markdown fences vs executable `{lang}` chunks, nested backticks, tilde fences, exact chunk options, unclosed fence diagnostics).
2. Replace flat YAML parsing with real YAML parsing (`serde_yaml` / `yaml-rust2`).
3. Achieve lossless `.ipynb` (`nbformat 4.5`) round-trip conversion + live executed cell output sync back into the saved notebook.
4. Build a **token/AST-preserving Markdown + Math + Chemistry + Mermaid -> HTML pipeline** (`pulldown-cmark` + dedicated Math/Chem/Mermaid renderers) so code blocks are **never** corrupted by `$$`, `\ce{}`, `![img]`, `*`, `~`, or `^`.
5. Fix critical math (`\int` -> `∈t`), SVG Mermaid z-order/sequence diagram bugs, `.tex`/`.ts`/`.html` rich previews, WebKitGTK 6.0 scroll preservation + Dark/Sepia themes + script sandboxing, and `WebViewFactory.reload()` blanking.

---

## 2. Architecture: Rust `imladris-core` C-ABI Static Library (`rust/imladris_core/`)

> **Why Rust here:** Parsing nested Markdown/YAML/Quarto blocks, CommonMark tables/lists, `.ipynb` JSON + MIME outputs, LaTeX math AST + symbol boundaries, TypeScript outline/diagnostics, LaTeX `.log` error extraction, and tar/zip path/symlink safety in ad-hoc GLib regexes caused >60% of the audited rendering & serialization bugs. Putting those pure deterministic transforms in Rust (`libimladris_core.a`) guarantees memory safety, speed, unit-testability with `cargo test`, and single source of truth.

### 2.1 Crate Layout & Dependencies (`rust/imladris_core/Cargo.toml`)
Keep dependencies lean, well-maintained, and vendorable (`cargo vendor` / `flatpak-cargo-generator`):
- `serde` + `serde_json` (for `.ipynb` `nbformat 4.5`, FFI JSON DTOs, diagnostic spans)
- `serde_yaml_ng` (or `yaml-rust2` — avoid unmaintained `serde_yaml`) for full nested YAML frontmatter + `#|` chunk YAML option parsing (`format: html: toc:`)
- `pulldown-cmark` (`ENABLE_TABLES`, `ENABLE_STRIKETHROUGH`, `ENABLE_TASKLISTS`, `ENABLE_FOOTNOTES`, `ENABLE_MATH` where applicable, plus event-stream token interception) for CommonMark + GFM HTML rendering
- `zip` / `tar` metadata validator (optional helper for pre-extract symlink/path audit)

### 2.2 C-ABI Contract (`rust/imladris_core/include/imladris_core.h` & `src/core/imladris_core.vapi`)
Design a tiny, panic-proof C API:
```c
// Every exported fn catches panics with std::panic::catch_unwind.
// Caller frees every non-NULL return string via imladris_free_string().
void imladris_free_string(char *ptr);

char *imladris_parse_frontmatter_json(const char *source_utf8);
char *imladris_parse_chunks_json(const char *source_utf8, const char *format_code);
char *imladris_extract_outline_json(const char *source_utf8, const char *format_code);
char *imladris_render_markdown_html(const char *body_utf8, const char *options_json);
char *imladris_ipynb_to_editor_json(const char *ipynb_json_utf8);
char *imladris_editor_to_ipynb_json(const char *editor_utf8, const char *existing_ipynb_utf8, const char *outputs_map_json);
char *imladris_parse_latex_log_json(const char *log_utf8);
char *imladris_analyze_typescript_symbols_json(const char *ts_source_utf8);
```
- Wrap every C API boundary in `vapi` with `[CCode (cname = "...", free_function = "imladris_free_string")]` OR explicit `Vala` wrapper `Imladris.Core.NativeCore` taking/freeing `char*` cleanly via `string.dup ()` + `free`. (Always test with `valac` C-output inspection + ASan / Valgrind to verify zero leaks and zero double-frees!)

### 2.3 Meson Integration (`meson.build`)
- Add a `custom_target('imladris_core_lib', ...)` invoking a small build helper script `scripts/build-rust-core.sh` (`cargo build --release --offline` when `vendor/` or `.cargo/config.toml` exists, `--manifest-path ...`, copying `libimladris_core.a` into build dir), OR build staticlib linked into both `imladris` executable and test executables.
- Pass `-Irust/imladris_core/include` cleanly and preserve `cargo test --manifest-path rust/imladris_core/Cargo.toml` in `meson test` (`test('rust_core_tests', ...)`).

---

## 3. Parsing & Serialization Fixes (Exact Defect Remediation)

### Task 2.1 — Exact Chunk & Fence Scanner (`ChunkParser.vala` -> `imladris_parse_chunks_json`)
* **Current Bugs (`ChunkParser.vala:46-127`):**
  - Matches non-executable ```` ```json ````, ```` ```yaml ````, ```` ```mermaid ```` as executable chunks (`line 46`), emitting `✖ Unsupported chunk engine` during `Run All`.
  - Fails on 4-backtick fences (````` ````{r} `````), tilde fences (`~~~{r}`), or inner triple backticks inside strings (`line 101`).
  - `eval=first` false-triggers `.contains("eval=f")` (`line 58`).
  - Strips every `#|` line unconditionally, ignores `echo`, `output`, `include`, `warning`, `error`, `label`, `fig-cap`, `fig-width`, `fig-height`.
  - Discards unclosed chunks silently at EOF (`lines 125-127`).
* **Target Specification:**
  1. **CommonMark-accurate Fence Matching:** Record fence character (`'`'` or `'~'`) and fence length `N >= 3` plus indentation `<= 3`. A closing fence MUST use the same fence character with length `>= N` and only optional trailing whitespace! Nested triple backticks inside a 4-backtick chunk no longer break parsing.
  2. **Distinguish Display Blocks vs Executable Chunks:**
     - **Executable chunk:** Header starts with `{lang...}` (e.g. ```` ```{r} ````, ```` ```{python, echo=FALSE} ````, ```` ```{bash} ````, ```` ```{ts} ````) OR Quarto/Imladris executable brace tag. Set `is_executable = true`.
     - **Special diagram fence:** ```` ```mermaid ```` / ```` ```{mermaid} ```` -> `kind = DIAGRAM_MERMAID`, `is_executable = false` (rendered in preview, NOT sent to R/Python REPL!).
     - **Plain code block:** ```` ```json ````, ```` ```python ```` (without braces in Markdown/Quarto), ```` ```yaml ````, ```` ```text ```` -> `is_executable = false` (skipped cleanly by `Run All`, `Run Above/Below`, and only highlighted in editor & rendered in `<pre><code>` HTML!). *Exception for `.ipynb` conversion:* handle explicit `cell_type = "code"` carefully via `{lang}` in Imladris's `.ipynb` intermediate Markdown format so Markdown example blocks inside notebook Markdown cells NEVER turn into code cells!
  3. **Exact Chunk Option Parsing:** Parse both RMarkdown header attributes (`{r setup, eval=FALSE, echo=TRUE}`) with a real tokenizer (quoted strings protected!) AND Quarto `#|` YAML lines cleanly via Rust `serde_yaml_ng`. Expose typed fields (`label`, `eval_enabled`, `echo`, `include`, `output_mode`, `warning`, `error`, `fig_width`, `fig_height`, `fig_cap`, `unclosed_eof`, `fence_lang`, `code_start_line`, `code_end_line`). Preserve `#|` lines or emit clean diagnostics cleanly.

### Task 2.2 — Nested YAML Frontmatter & Format-Aware Outline
* **Files:** `src/core/frontmatter_parser.vala`, `src/ui/PersistentPanelRegistry.vala:1627-1672`.
* **Required Changes:**
  1. Replace `FrontmatterParser.parse_yaml_block` (`lines 127-170`) with `imladris_parse_frontmatter_json`: extract nested `format.html.toc`, `format.pdf`, `output`, `title`, `author`, `date`, `bibliography`, `csl`, `runtime` (`shiny`), `server` (`shiny`), `jupyter` / `kernelspec` cleanly without child keys clobbering top-level keys, and serialize back properly using YAML quoting/escaping (`project_scaffolder`, `DocumentPage`).
  2. Replace `refresh_environment_and_outline` (`PersistentPanelRegistry.vala:1627-1672`) with `imladris_extract_outline_json (clean_source_text, format_code)`:
     - **`.qmd` / `.Rmd` / `.ipynb` / `.md`:** Skip YAML frontmatter (`--- ... ---`) AND ALL fenced code blocks (both ```` ```lang ```` and ```` ```{lang} ```` and `~~~`) -> emit Markdown `# .. ######` headings and executable chunk labels!
     - **`.tex`:** Extract `\part`, `\chapter`, `\section`, `\subsection`, `\subsubsection`, `\begin{frame}{Title}` (Beamer) with 1-based line numbers!
     - **`.ts`:** Extract `export`, `class`, `interface`, `type`, `enum`, `function`, `async function`, top-level `const fn = (...) =>` declarations with line numbers!
     - **`.html`:** Extract `<h1>`..`<h6>` and named landmark `<section id="...">` elements with line numbers!

### Task 2.3 — Lossless `.ipynb` (`nbformat 4.5`) Round-Trip & Output Sync
* **Files:** `src/Window.vala` (`1288`, `1314`, `1101`, `1237`), `src/adapters/DocumentAdapter.vala` (`29-41`), `src/core/notebook_serializer.vala` (`123-480`), `src/DocumentPage.vala`.
* **Defects Fixed:**
  - `Window.save_document_async` (`L1288,1314`) omits `existing_raw_file`, forcing `explicit_default_lang = "python"` and disabling `detect_notebook_language()`.
  - Markdown code fences (` ```json `) inside Markdown cells convert into Jupyter code cells (`L389`).
  - Code containing ` ``` ` splits cells (`L406`).
  - Consecutive Markdown cells merge; cell IDs/tags/attachments (`image/png`, etc.)/metadata/`kernelspec`/`nbformat_minor` are dropped; nested `:::` breaks output skipping (`L382`).
  - Live execution in `PersistentPanelRegistry` never updates `#| outputs_b64` / `execution_count`.
* **Required Changes:**
  1. Store `public string? raw_ipynb_source { get; set; default = null; }` (and a live map of `cell_id -> NbCellOutput[]` / `execution_count` updated every time a chunk executes in `DocumentPage`)!
  2. Pass `doc_page.raw_ipynb_source` explicitly from `Window.save_document_async` (AND `ExportService.materialize_input`) to `DocumentAdapter.save_from_editor_buffer (clean_text, DocumentFormat.IPYNB, doc_page.raw_ipynb_source)` — AND fix `DocumentAdapter.save_from_editor_buffer` (`L34`) so `existing_raw_json ?? ""` (NOT `"python"`!) allows auto-detection cleanly when unsaved!
  3. Re-implement `ipynb_to_markdown` & `markdown_to_ipynb` via Rust `imladris_ipynb_to_editor_json` & `imladris_editor_to_ipynb_json`:
     - Emit explicit `<!-- imladris:cell {"id":"...","type":"markdown"} -->` markers (or `ChunkParser` fence length `N = max_inner_backticks + 1`!) so consecutive Markdown cells remain separate, Markdown examples inside ```` ```json ```` NEVER become code cells, nested backticks inside Python docstrings NEVER split cells, and `:::` blocks use balanced delimiter tags (`:::: imladris-ipynb-output-...`).
     - Preserve ALL unknown top-level metadata (`colab`, `widgets`, `language_info`, `kernelspec` display_name & name, `nbformat_minor`) and cell-level `metadata` (`collapsed`, `scrolled`, `slideshow`, `editable`, `deletable`, `tags`) + **`attachments`**!
     - Merge live execution outputs (`stream`, `execute_result`, `display_data` PNG/SVG/HTML, `error` traceback, `execution_count`) directly on Save!

---

## 4. HTML, Math, Chemistry, Mermaid, LaTeX, TS & WebKitGTK 6.0 Rendering Fixes

### Task 2.4 — Token-Preserving HTML Preview Pipeline (`DocumentAdapter.vala` + Rust)
* **Current Fatal Bug (`DocumentAdapter.vala:54-57, 255-288`):** `transform_code_chunks` emits `<pre><code>...</code></pre>`, and THEN `transform_display_math`, `transform_media_tags`, and `basic_markdown_to_html` run raw regexes over the output, rewriting `$$`, `![img]`, `*`, `~`, `^`, `<` INSIDE code chunks and `<pre>` blocks! Inline `Markup.escape_text` escapes `<` inside `$a < b$` before math rendering, and bold/italic run AFTER math HTML spans!
* **Required Target Pipeline:**
  1. Split YAML frontmatter first via Rust (`imladris_parse_frontmatter_json`), rendering clean metadata banner (escaped via `Markup.escape_text`).
  2. Parse Markdown / Quarto / RMarkdown body cleanly via `imladris_render_markdown_html` (`pulldown-cmark` token stream):
     - **Intercept Code Blocks (`Tag::CodeBlock`) FIRST:** Distinguish executable `{lang}` chunk cards, Mermaid blocks (`MermaidFlowEngine` SVG), and ordinary highlighted code blocks (`<pre><code class="language-...">`). Emit HTML placeholders or direct escaped HTML; **never** pass code block contents through math, media, bold, italic, or sub/superscript passes!
     - **Intercept Inline Code (`Event::Code`) SECOND:** Emit `<code>escaped</code>` verbatim — **never** run math, bold, italic, or `~`/`^` regexes over inline code!
     - **Intercept Inline/Display Math (`$...$`, `$$...$$`, `\begin{equation}...\end{equation}`, `\ce{...}`):** Extract raw math **only from prose text nodes** (protected against currency `$5 and $10` using standard Pandoc/CommonMark math boundary rules: opening `$` not followed by whitespace, closing `$` not preceded by whitespace and not followed by digit!), run `MathChemEngine` on raw unescaped math, and emit final HTML directly!
     - **Sanitize all Links (`href`) and Media (`src`):** Block `javascript:` / `vbscript:` / unsafe URIs; render QMD `{{< video path >}}` safely in prose only.
     - Support H1–H6, GFM tables, nested lists, blockquotes, strikethrough, task checkboxes, footnotes, raw `<svg>`/`<table>` HTML blocks cleanly!

### Task 2.5 — Fix `MathChemEngine.vala` (`\int` -> `∈t`, Escaping, Order Bugs)
* **Files:** `src/core/MathChemEngine.vala` (`677-684`, `1308-1571`).
* **Required Fixes:**
  1. **Fix `sym_map` longest-match / token boundary ordering (`lines 1365-1400`):** Replace ALL `s.replace("\\...", ...)` prefix collisions using **longest-command regex matching (`\\([A-Za-z]+)` via a HashMap lookup!)** instead of sequential `string.replace`! That single architectural fix permanently eliminates `\int` -> `∈t` (`\in` + `t`), `\top` -> `→p` (`\to` + `p`), `\epsilon` vs `\varepsilon`, etc.
  2. **HTML-Escape Inside `render_latex_to_html` (`lines 1308-1571`):** Escape raw literal characters (`<`, `>`, `&`) into `&lt;`, `&gt;`, `&amp;` BEFORE emitting `<span>`/`<sup>`/`<sub>` tags (so `x < y` in LaTeX never vanishes inside WebKit as an unclosed HTML tag!).
  3. **Fix `_` / `^` Regex Order (`lines 1420-1426`):** Parse superscripts (`^`) and subscripts (`_`) on LaTeX tokens BEFORE wrapping tokens in `<span class="...">` HTML attributes so attribute names (`data-`, CSS classes) are never mangled, and support multi-char braces/signs (`Fe^{-2}`, `x_{i+1}`, `a^{2n}`).
  4. **Fix `convert_natural_fractions` (`lines 677-684`):** Include `'('` / function call balanced-parentheses scanning so `1 / sin(x)` produces `\frac{1}{\sin(x)}`.
  5. **Add missing LaTeX symbols & environments:** `\sim`, `\cong`, `\simeq`, `\ll`, `\gg`, `\langle`, `\rangle`, `\mathbb{R/N/Z/Q/C}`, `\mathcal`, `\mathbf`, `\dots`/`\cdots`/`\vdots`, `align`/`aligned`, `cases`, `bmatrix`/`pmatrix`, and protect `rx_math_tokens` initialization safely.

### Task 2.6 — Fix `MermaidFlowEngine.vala` (Arrowheads, `sequenceDiagram`, Subgraphs, Dark Theme)
* **Files:** `src/core/MermaidFlowEngine.vala` (`738-937`, `1291-1479`).
* **Required Fixes:**
  1. **SVG Draw Order & Arrowheads (`lines 1438-1475`):** Compute ray-box / ray-circle / ray-diamond intersection points on node borders (`src_border -> dst_border`) AND render edges/arrows clearly outside opaque fills (not center-to-center behind node rectangles!), handle `<br/>` as `<tspan>` multi-line SVG labels, and render curved Bezier loops for self-edges (`A --> A`).
  2. **`sequenceDiagram` Real Layout (`lines 929-937`):** Render participants along the top header row with vertical dashed **lifelines**, step each message downwards by `y += step_height` cleanly with arrows ending at lifeline X coordinates, support `loop`/`alt`/`Note`, `->>`/`-->>`, and activation bars!
  3. **Render `subgraph_title` Containers:** Group subgraph nodes into bounding `<rect class="mermaid-subgraph">` boxes drawn *behind* edges and nodes.
  4. **Syntax & Theme Completeness:** Support chained edges (`A --> B --> C`), `&` fan-in/out (`A & B --> C`), inline edge text (`A -- text --> B`), `--o`/`--x`, `:::className`, CSS values with spaces (`stroke-width: 2px`), AND inject theme-aware CSS variables (`currentColor`, dark surfaces in Dark/Sepia modes instead of hardcoded `#ffffff`). Fallback unsupported diagram types (`classDiagram`, `erDiagram`, `gantt`, `pie`) with clean notice OR implement cleanly rather than silently misparsing as flowchart!

### Task 2.7 — Per-Format Previews & WebKitGTK 6.0 Theme/Scroll/Security
* **Files:** `src/DocumentPage.vala` (`215-217`, `248-264`, `383-387`, `610-762`), `src/ui/WebViewFactory.vala` (`24-48`), `src/ui/PersistentPanelRegistry.vala` (`1786-1849`), `src/adapters/DocumentAdapter.vala` (`70-122`).
* **Required Changes:**
  1. **Preserve & Sync Preview Scroll Position (`DocumentPage.vala:383-387, 632, 754`):**
     - Do NOT replace full DOM with `load_html` losing scroll `(0,0)` on every edit! Either update `<main id="imladris-content">` via `web_view.evaluate_javascript (...)` when template shell matches, OR restore exact scroll fraction (`window.scrollY / Math.max(1, document.body.scrollHeight - window.innerHeight)`) immediately in `load-changed` (`WEBKIT_LOAD_FINISHED`), AND sync editor <-> preview vertical scroll fraction when Split Mode is active!
  2. **Fix `base_uri` (`DocumentPage.vala:622-628`):**
     - When `file_location == null`, use `Window.current_project_dir` (`GLib.File.new_for_path(proj).get_uri() + "/"`) before falling back to temp preview URI; guard root `/` so `get_uri()` never becomes `"file:////"`.
  3. **Dark & Eye-Friendly Theme Support Everywhere:**
     - Define shared CSS theme sheet (`--bg`, `--fg`, `--card-bg`, `--border`, `--accent`, `--code-bg`, `--muted`) driven by `SettingsManager.app_theme`.
     - Inject into `.html` preview gracefully (or provide a theme-adaptive wrapper frame toggle for user HTML), `.qmd`/`.Rmd`/`.md`/`.ipynb` preview, `DocumentAdapter.transform_media_tags` (`<figcaption>`), **and** `PersistentPanelRegistry.load_plot_image` / `render_default_scientific_plot` (`plots_webview` must not blind users with `#ffffff` in Dark mode!).
  4. **Fix `WebViewFactory.vala:24-32` (`hardware_acceleration_changed`):** Replace broken `view.reload()` (which loads `base_uri` directory!) with storing last rendered `(html, base_uri)` or emitting a custom `reapply_required` signal handled by `DocumentPage` (`refresh_live_preview(true)`) and `PersistentPanelRegistry` (`reload_current_plot()`).
  5. **Format-Specific Rich Previews (`refresh_live_preview`):**
     - **`.qmd` / `.Rmd` / `.ipynb` / `.md`:** Token-preserving HTML preview (and preserve compiled Quarto/RMarkdown output cleanly until explicitly refreshed or re-rendered!).
     - **`.tex`:** Rich TeX structural + MathChem live preview (preamble summary + rendered `\section` hierarchy + `$$`/`\begin{equation}`/`\ce{}` equations via fixed `MathChemEngine`!) PLUS switch seamlessly to rendered PDF/HTML artifact when user clicks **Compile PDF** (embedding PDF viewer / Evince / WebKit PDF.js or rendered SVG pages!).
     - **`.ts`:** Clean TypeScript Diagnostic & Execution Summary Card in preview pane (or show compiled HTML/live browser preview if referencing an HTML entry / console output + type-check status badge + symbol outline!).
     - **`.html`:** Fix `DocumentAdapter.render_html_with_latex` (`L70-122`): handle standalone `\ce{}`, protect `$5 and $10` currency tokens, avoid `.down()` byte-offset slicing (`L113-115`), and **lock down `WebKit.Settings`** (`allow_universal_access_from_file_urls = false` on general previews; allow configurable opt-in script execution toggle for user `.html` pages rather than unconditional universal local-file read!).

---

## 5. Phase 2 Verification Checklist

- [ ] `cargo test --manifest-path rust/imladris_core/Cargo.toml` passes 100% (frontmatter, chunk fences, `.ipynb` round-trip, Markdown->HTML code-block protection, LaTeX log parser, TS symbol parser).
- [ ] `meson compile -C builddir` builds `libimladris_core.a` + `imladris` with zero memory errors under ASan (`-Db_sanitize=address,undefined` check on test targets).
- [ ] Code chunks and plain ```` ``` ```` blocks containing `$$`, `\ce{H2O}`, `![alt](x.png)`, `*stars*`, `~tilde~`, and `<tags>` render literally in HTML preview `<pre><code>` without corruption.
- [ ] `MathChemEngine.render_latex_to_html("\\int_0^\\infty e^{-x^2} dx")` renders integral `∫` cleanly (zero `∈t`!) and `x < y` renders `<` cleanly.
- [ ] `MermaidFlowEngine` renders visible arrowheads outside node boxes and clean multi-step vertical lifelines in `sequenceDiagram`.
- [ ] `.ipynb` test fixture (non-Python R/Bash kernel, markdown cell with ```` ```json ```` block, Python docstring with triple backticks, `attachments`, nested `:::` output, executed chart) round-trips without losing kernel, splitting cells, or corrupting metadata.
- [ ] Typing in editor preserves WebKit preview scroll position cleanly; Dark & Eye-Friendly modes style all HTML previews and Plot views properly.
