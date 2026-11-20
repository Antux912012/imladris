<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# Building File 01 — Universal 7-Format Taxonomy & Adaptive GTK4/Libadwaita UI

**Phase:** 1 of 4
**Prerequisites:** Read [`00_AGENT_GUIDELINES_TIPS_AND_PROCESS.md`](00_AGENT_GUIDELINES_TIPS_AND_PROCESS.md).
**Primary Ownership:** `src/core/project_scaffolder.vala`, new `src/core/FormatProfile.vala`, `src/Application.vala`, `src/Window.vala`, `src/DocumentPage.vala`, `src/ui/new_project_dialog.vala`, `src/ui/rproj_dialog.vala`, `src/ui/RStudioDockGrid.vala`, `src/ui/WorkspaceDockManager.vala`, `src/services/WorkspaceStateManager.vala`, `src/SmartRibbonHelpers.vala`, `src/editor/CitationCompletionProvider.vala`, `data/language-specs/`, `data/imladris.gresource.xml`.

---

## 1. Objective

Make **every one of the 7 user-facing formats** (`.qmd`, `.Rmd`, `.ipynb`, `.md`, `.tex`, `.ts`, `.html`)—plus supporting project files (`.R`, `.py`, `.css`, `.bib`)—a **first-class citizen** driven by a single declarative `FormatProfile` / `FormatRegistry`, so opening, creating, editing, or switching tabs adapts:
- HeaderBar controls (primary Compile/Run button, target selector, Shiny toggle, visibility on Welcome page)
- Ribbon tabs & per-group controls (`Home`, `Insert`, `Run`, `Publish`, `View`, `Packages`)
- Workbench layout & default quadrant panels (`APOSTROPHE` vs `RSTUDIO` per-tab, without clobbering user choice or Q4 panels)
- GtkSourceView 5 language highlighting & scheme styling
- Comment toggle syntax & citation syntax
- Console / Kernel default engine & Notebook Cell Toolbar visibility

---

## 2. Target Adaptive UI Matrix (All 7 Core Formats)

Hydrogen 4 Medium MUST implement this exact behavior via a central `FormatProfile` descriptor instead of scattered `if (is_md)` / `if (is_html)` checks:

| Property / UI Control | Quarto (`.qmd`) | R Markdown (`.Rmd`) | Jupyter (`.ipynb`) | Markdown (`.md`) | LaTeX (`.tex`) | TypeScript (`.ts`) | HTML (`.html`) |
|---|---|---|---|---|---|---|---|
| **`DocumentFormat` Enum** | `QMD` | `RMD` | `IPYNB` | `MD` | **`TEX` (NEW)** | **`TS` (NEW)** | `HTML` |
| **Default Workbench Mode** | `RSTUDIO` (4-pane) | `RSTUDIO` (4-pane) | `RSTUDIO` (4-pane) | `APOSTROPHE` (Focus / Split) | `APOSTROPHE` or Split (Source + PDF/Preview) | `RSTUDIO` (Code + Console/Terminal/Diagnostics + Preview/Files) | `APOSTROPHE` or Split (Source + Live WebView) |
| **Default Right/Output Panel** | Live Preview / Plots / Environment | Live Preview / Plots / Environment | Live Preview / Plots / Environment | Live Preview | Rendered PDF / TeX Preview + Diagnostics Log | Execution Console / TypeCheck Diagnostics / DOM Preview (if HTML companion) | Live DOM Preview |
| **Notebook Cell Toolbar (Q1)** | Visible (`+R`, `+Python`, `+Bash`, `+Mermaid`, Run Cell/All) | Visible (`+R`, `+Python`, Run Cell/All) | Visible (`+Code`, `+Markdown`, Cell Navigation, Save Outputs) | **Hidden** (prose; insert code block only) | **Hidden** (optional LaTeX snippet bar / Compile status) | **Hidden** (Script toolbar: `Check (tsc)`, `Run TS`, Format) | **Hidden** (HTML toolbar: `Open in Browser`, `Format`) |
| **HeaderBar Primary Action** | **Render Quarto** + Format Dropdown (`HTML`, `PDF`, `RevealJS`, `Beamer`, `Typst`) | **Knit / Render Rmd** (`HTML`, `PDF`, `Word/ODT`) | **Export Notebook** / **Run All** (`HTML`, `PDF`, `.ipynb`) | **Export Markdown** (`HTML`, `PDF`, `ODT`, `RTF`) | **Build LaTeX PDF** (`latexmk`/`xelatex`/`pdflatex` + BibTeX) | **Run / Typecheck TS** (`Run TS`, `tsc --noEmit`) | **Refresh / External Preview** (`Print to PDF`, `Open Browser`) |
| **Ribbon `Run` Tab** | **Visible & Full** (Chunk, All, Above, Below, Line, Source, Restart, Kernel) | **Visible & Full** (Chunk, All, Line, Source, Restart, R Kernel) | **Visible & Notebook** (Run Cell, Run All, Above, Below, Clear Outputs, Restart Kernel, Python/Detected Kernel) | **Hidden** (no arbitrary hidden Python eval on `Ctrl+Enter`!) | **Visible (Compile Mode)** (`Build PDF`, `BibTeX/Biber`, `Clean Aux`, `View TeX Log`) | **Visible (Script Mode)** (`Run File`, `Run Selection` via Node/Deno, `Typecheck tsc`, `Restart REPL/Watcher`) | **Hidden** |
| **Ribbon `Home` Prose Tools** | Markdown Prose Formatting (Bold/Italic/H1-H3/Lists/Quote) | Markdown Prose Formatting | Markdown Prose Formatting | Markdown Prose Formatting | **LaTeX Formatting** (`\textbf{}`, `\textit{}`, `\section{}`, `itemize`, `enumerate`, `$...$`) | **Hidden or Code Editing** (Indent, Format, Comment, Find/Replace) | **HTML Tag Helpers** (`<strong>`, `<em>`, `<h1>..<h3>`, `<ul>`, `<a href>`) |
| **Ribbon `Insert` Tools** | MD Table, Code Chunk (`{r}`, `{python}`, `{bash}`, `{ts}`), Math/Chem, Mermaid, Citation `[@k]`, Cross-ref `@fig-`, Footnote `^[]`, Image/Video | MD Table, R/Python Chunk, Math/Chem, Mermaid, Citation `[@k]`, Image/Video | Code Cell, MD Cell, Math/Chem, Image/Attachment | MD Table, Math/Chem, Mermaid, Citation `[@k]`, Image/Video | **LaTeX Table (`tabular`)**, **Section**, **Equation / `\ce{}`**, **BibTeX Citation (`\cite{}`)**, **Figure (`\includegraphics`)**, **Bib `\bibliography{}`** | Function/Class/Interface/Test snippet, Docstring JSDoc | HTML Table, Script/Style block, Image `<img>`, Video `<video>`, Link `<a>` |
| **Comment Toggle (`Ctrl+/`)** | Context-aware (`<!-- -->` in prose, `# ` in R/Py/Bash, `// ` in Mermaid/JS/TS) | Context-aware (`<!-- -->` in prose, `# ` in R/Py) | Context-aware (`<!-- -->` in MD cells, `# ` in Py/R cells) | `<!-- ... -->` | **`% `** | **`// `** | `<!-- ... -->` |
| **Starter Template** | Valid Quarto YAML `format:` + `{r}` | Valid RMarkdown YAML `output:` + `{r setup}` | Valid JSON `nbformat: 4.5` serialized to editor | Pure Markdown prose (**NO Quarto frontmatter / R chunks!**) | Clean `\documentclass{article}` + `amsmath`/`mhchem`/`graphicx` + sample math | Clean typed TS sample (`interface`, typed function, `console.log`) | Clean HTML5 boilerplate with dark-mode aware meta/styles |
| **GtkSourceView Lang ID** | `quarto` (custom `.lang` embedding YAML + MD + R + Py + LaTeX math!) | `rmd` (custom `.lang` embedding YAML + MD + R + LaTeX math!) | Mapped dynamically to notebook cell syntax / `quarto`-like multi-cell `.lang` (**NOT `json`!**) | `markdown` | `latex` | `typescript` (custom/bundled `.lang` guaranteeing TS types/decorators/generics) | `html` |

*(Plus keep `.R` -> `RSCRIPT`, `.py` -> `PYSCRIPT`, `.css` -> `CSS`, `.bib` -> `BIB` with clean Code/Data-only Ribbons and zero Render/Export Quarto buttons.)*

---

## 3. Detailed Implementation Tasks

### Task 1.1 — Expand `DocumentFormat` & Create `FormatRegistry` / `FormatProfile`
* **Files:** `src/core/project_scaffolder.vala` (`lines 49-162`), new `src/core/FormatProfile.vala`, `meson.build`.
* **Defects Fixed:** `DocumentFormat` lacks `TEX` and `TS`; `.from_filename` defaults unknowns to `MD`; `.from_short_code` defaults unknowns to `QMD`.
* **Required Changes:**
  1. Add `TEX` and `TS` to `public enum DocumentFormat` (`MD`, `HTML`, `CSS`, `BIB`, `RSCRIPT`, `RMD`, `QMD`, `IPYNB`, `PYSCRIPT`, `TEX`, `TS`).
  2. Fix `from_filename (string filename)`:
     - Lowercase filename once (`string lower = filename.down ();`).
     - Match `.tex`, `.ltx` -> `TEX`; `.ts`, `.tsx`, `.mts`, `.cts` -> `TS` (check carefully before `.r`/other suffixes); `.qmd`, `.rmd`, `.ipynb`, `.r`, `.py`, `.css`, `.bib`, `.html`/`.htm`, `.md`/`.markdown`.
     - Add explicit `UNKNOWN` handling or document clearly why unknown prose falls back to `MD`.
  3. Fix `from_short_code`, `get_extension ()` (`.tex`, `.ts`), `get_display_name ()`, `to_syntax_lang ()`:
     - `QMD` -> `"quarto"` (with runtime fallback `"markdown"` if spec absent)
     - `RMD` -> `"rmd"` (fallback `"markdown"`)
     - `IPYNB` -> `"quarto"` / `"markdown"` (NEVER `"json"` because buffer edits normalized Markdown representation!)
     - `TEX` -> `"latex"`
     - `TS` -> `"typescript"` (fallback `"js"`)
  4. Create `Imladris.Core.FormatProfile`:
     - Expose capability flags: `supports_chunks`, `supports_prose_ribbon`, `supports_latex_ribbon`, `supports_ts_actions`, `supports_html_actions`, `supports_quarto_render`, `supports_latex_build`, `supports_live_preview`, `default_layout_mode`, `default_kernel`, `line_comment_prefix`, `block_comment_open`, `block_comment_close`, `citation_style` (`PANDOC_AT` | `LATEX_CITE` | `NONE`), `export_targets[]`.
     - Register ALL UI decisions against `FormatProfile.for_format (fmt)` instead of ad-hoc boolean checks in `Window.vala`.

### Task 1.2 — Bundle Missing GtkSourceView 5 `.lang` Specs via GResource
* **Root Cause Verified:** Host/runtime GtkSourceView-5 often lacks `typescript.lang`, `rmd.lang`, `quarto.lang`, or drops optional specs in minimal Flatpak/container runtimes. Also `DocumentPage.vala:157-164` bypassed `lang_id` fallback because `fmt.to_syntax_lang()` returned `"markdown"` (`!= null`), locking `.ts` and `.tex` into Markdown highlighting.
* **Required Changes:**
  1. Create `data/language-specs/`:
     - `quarto.lang`: Markdown + leading `---...---` YAML frontmatter + `#|` Quarto option highlighting + embedded `r` / `python` / `bash` / `typescript` / `latex` contexts.
     - `rmd.lang`: R Markdown grammar embedding `r` / `python` / YAML / LaTeX math.
     - `typescript.lang`: Full TypeScript ES2023+ & type annotation (`interface`, `type`, `enum`, `implements`, `readonly`, `as`, `satisfies`, generics, decorators, JSX/TSX optional).
     - `latex.lang` (fallback bundle if system GtkSourceView lacks `latex`).
  2. Embed them in `data/imladris.gresource.xml` OR install to `${datadir}/imladris/language-specs` via `meson.build`, and prepend that directory to `GtkSource.LanguageManager.get_default ().append_search_path (...)` (or custom instance / search path prepended before lookup in `DocumentPage.vala:155-165`).
  3. Fix `Window.vala:1236-1245` (`open_file_from_path`):
     - Lowercase `name` (`string lower_name = file.get_basename ().down ();`) BEFORE every `.has_suffix(...)` check so `.PY`, `.TS`, `.TEX`, `.HTML`, `.IPYNB`, `.RMD`, `.QMD` work case-insensitively!
     - Set `lang` strictly from `DocumentFormat.from_filename(lower_name)` (`"latex"` for `.tex`, `"typescript"` for `.ts`, etc.).
  4. Fix `DocumentPage.vala:157-164`: Try resolved `DocumentFormat.to_syntax_lang()`, then `lang_id`, then format fallbacks cleanly (`rmd` -> `markdown`, `quarto` -> `markdown`, `typescript` -> `js`, etc.)—never let `MD` override explicit `lang_id` like `"typescript"` or `"latex"`.

### Task 1.3 — Fix Welcome Screen, `New` Menus, `NewProjectDialog` & Starter Templates
* **Files:** `src/Application.vala`, `src/Window.vala` (`133-146`, `1028-1135`), `src/DocumentPage.vala` (`523-589`), `src/ui/new_project_dialog.vala` (`167-256`).
* **Required Changes:**
  1. Add `app.new_tex` action in `src/Application.vala` (`on_new_tex ()` opening `Document.tex`, `"latex"`).
  2. Update `Window.vala:133-146` (`new_submenu`): organize cleanly by category (Notebooks & Scientific Authoring: `.qmd`, `.Rmd`, `.ipynb`; Technical & Web: `.md`, `.tex`, `.html`, `.css`, `.ts`; Code & Data: `.R`, Shiny App, `.py`, `.bib`) and wire **`app.new_ts`** and **`app.new_tex`**!
  3. Update `NewProjectDialog` (`src/ui/new_project_dialog.vala`): add `.tex`, `.ts`, `.css`, `.bib` to Standalone Simple Files, and allow LaTeX Thesis / TypeScript Module in Workspace Project presets too.
  4. Update Welcome Screen (`Window.vala:1028-1135`): ensure expandable Quick Start / All Formats section gives 1-click access to **all 7 core formats** (`.qmd`, `.Rmd`, `.ipynb`, `.md`, `.tex`, `.ts`, `.html`).
  5. Fix `DocumentPage.populate_starter_template` (`lines 523-589`):
     - Separate `"markdown"` (clean CommonMark prose: `# <Title>\n\nStart writing in Markdown...\n`) from `"quarto"` (`on_new_qmd` MUST pass `"quarto"`, NOT `"markdown"`!).
     - Separate `"rmd"` (R Markdown YAML `output: html_document` + `{r setup, include=FALSE}` chunk).
     - Add `"latex"` / `"tex"` starter template (`\documentclass[11pt]{article}` + `\usepackage{amsmath,amssymb,mhchem,graphicx}` + title/author/section/equation).
     - Add `"css"` and `"bib"` templates.
     - Ensure `title` and `author` interpolated into templates are properly escaped for YAML/JSON/HTML/LaTeX.
  6. Fix **Undo Poisoning on File Open** (`DocumentPage.vala:182` + `Window.vala:991`):
     - Pass initial text cleanly (or wrap template population & file load `source_buffer.text = ...` inside `source_buffer.begin_not_undoable_action ()` / `end_not_undoable_action ()`) so `Ctrl+Z` NEVER reverts an opened file back to a starter template!

### Task 1.4 — Adaptive HeaderBar, Ribbons, Comment Toggle & Citation Awareness
* **Files:** `src/Window.vala` (`230-268`, `388-394`, `630-670`, `1784-1975`, `2145-2300`, `2779-2868`), `src/SmartRibbonHelpers.vala`, `src/editor/CitationCompletionProvider.vala`.
* **Required Changes:**
  1. **Welcome Screen Zero-Chrome (`Window.vala:630-633, 670`):**
     - Store `export_format_selector`, `btn_render_quarto`, `btn_shiny_app`, `sci_tools_btn` as instance fields on `Window`.
     - When `tab_view.n_pages == 0`, hide ALL document-scoped HeaderBar widgets (`export_format_selector`, `btn_render_quarto`, `btn_shiny_app`, `sci_tools_btn`, and a new format badge pill if added). Only call `update_ribbon_state_machine` for an active document.
  2. **HeaderBar Format Adaptation:**
     - Adapt `btn_render_quarto`'s label/icon/tooltip and `export_format_selector` options dynamically from `FormatProfile`:
       - `.qmd`: **Render** -> `HTML`, `PDF`, `RevealJS`, `Beamer PDF`, `Typst/PDF`
       - `.Rmd`: **Knit** -> `HTML`, `PDF`, `Word / ODT`
       - `.ipynb`: **Run / Export** -> `Execute & Preview`, `HTML`, `PDF`, `.ipynb`
       - `.md`: **Preview / Export** -> `HTML`, `PDF`, `ODT`, `RTF`
       - `.tex`: **Compile PDF** -> `PDF (latexmk/xelatex)`, `PDF (pdflatex)`, `HTML (Pandoc)`
       - `.ts`: **Run / Check** -> `Run TypeScript`, `Typecheck (tsc --noEmit)`
       - `.html`: **Browser / Print** -> `Refresh Preview`, `Print to PDF`
       - `.R` / `.py`: **Run Script** (or Launch Shiny when Shiny detected)
       - `.css` / `.bib`: hide Render/Compile controls completely!
     - Update `btn_shiny_app` visibility both on tab switch AND debounced on `source_buffer.changed` using `ShinyService.get_default ().is_shiny_file (fname, clean_text)`.
  3. **Fix `update_ribbon_state_machine` (`Window.vala:2161-2300`):**
     - Drive visibility and sensitivity of EVERY ribbon tab (`tab_home`, `tab_insert`, `tab_run`, `tab_publish`, `tab_packages`) and tool group from `FormatProfile`:
       - Stop leaving `btn_render_html` / `btn_render_pdf` enabled on `.css`, `.bib`, `.ts`, `.R`, `.py`!
       - Swap `Home` formatting group smoothly (Markdown bar vs LaTeX bar vs Code bar vs HTML bar) via a `Gtk.Stack` inside the Home ribbon!
       - Swap `Insert` group smoothly (Markdown/Quarto Chunk+Table+`@cite` vs LaTeX `tabular`/`\cite{}`/`\includegraphics`/`\begin{equation}` vs Code/TS/HTML snippets).
     - Sync View/Publish checkbuttons (`btn_preview`, `chk_console`, Mode radio/toggle buttons, Topology, SplitMode, Ribbon toggle) whenever `tab_view.notify["selected-page"]` or `layout_changed` fires!
  4. **Fix Format-Aware Comment Toggle (`Window.vala:2779-2812`):**
     - In `.tex`: toggle `% `; in `.ts`/`.css`: toggle `// ` / `/* ... */`; in `.html`: toggle `<!-- ... -->`; in `.qmd`/`.Rmd`/`.ipynb`: inspect `ChunkParser.find_chunk_at_line` / fence context at cursor so R/Python/Bash lines toggle `# `, Mermaid/TS chunks toggle `// `, and prose toggles `<!-- ... -->`.
  5. **Fix Citation Insertion (`Window.vala:2825, 2868`, `CitationCompletionProvider.vala:178-190`):**
     - In `.tex`: insert `\cite{key}` and ensure `\bibliography{...}` / `\addbibresource{...}` (NOT YAML `---`!).
     - In `.R`, `.py`, `.ts`, `.css`, `.html`: never auto-prepend YAML frontmatter! Only insert `@citekey` / YAML `bibliography:` in `.qmd`, `.Rmd`, `.md` (and `.ipynb` Markdown cells).

### Task 1.5 — Fix `WorkspaceStateManager`, Per-Tab Docking & `RStudioDockGrid`
* **Files:** `src/services/WorkspaceStateManager.vala`, `src/DocumentPage.vala` (`373-374`, `503`, `757-762`, `1000-1007`), `src/ui/RStudioDockGrid.vala`, `src/ui/WorkspaceDockManager.vala`, `src/ui/LayoutSerializer.vala`.
* **Defects Fixed:**
  - Global `active_layout` + `user_override_lock` fights `DocumentPage` ctor (`lines 373-374`), causing tabs to desync.
  - `set_split_orientation` switches Q4 to `LIVE_PREVIEW` on every tab switch (`DocumentPage.vala:757-762`).
  - `set_workbench_mode(RSTUDIO)` forces `notebook_cell_toolbar` visible on `.R`, `.py`, `.ts` scripts (`DocumentPage.vala:503`).
  - `append_console_log` calls `dock_layout_state.activate_tab` per line, rebuilding the entire dock and writing `dock-layout.json` on every stdout line (`DocumentPage.vala:1000-1007`).
  - `LEFT_TALL_3` & `RIGHT_TALL_3` hide `Q2` or `Q3` without moving tabs (`RStudioDockGrid.vala:523-540`).
  - Dragging `main_hpaned`, `left_vpaned`, `right_vpaned` handles snaps back on next state update (`RStudioDockGrid.vala:373-407`).
  - `WorkspaceDockManager.create_move_panel_menu` emits unregistered `win.move_panel_*` actions (`lines 153-162`).
* **Required Changes:**
  1. Track layout mode (`APOSTROPHE` vs `RSTUDIO`), split orientation (`LIVE_PREVIEW` / `NONE`), and user override **per `DocumentPage`** (defaulted from `FormatProfile.default_layout_mode`, persisted in `WorkspaceStateManager` per-tab/preference cleanly).
  2. Only show `panel_registry.notebook_cell_toolbar` when `FormatProfile.supports_chunks` is `true` (`.qmd`, `.Rmd`, `.ipynb`). For `.ts` / `.tex` / `.R` / `.py`, show an appropriate lightweight Script/Build Action Bar or keep clean.
  3. Stop calling `dock_layout_state.activate_panel(LIVE_PREVIEW)` on tab switch inside `set_split_orientation`! Only switch Q4 to `LIVE_PREVIEW` when user explicitly clicks Preview / Compile HTML or toggles live preview for that tab.
  4. In `DocumentPage.append_console_log`, guard `activate_tab`: only switch Q2 to `CONSOLE` if `q2.active_tab != PanelId.CONSOLE` AND explicitly requested (`focus_console = true`), **never** triggering `save_to_disk ()` or full `sync_from_state ()` on every appended log line! Throttle/debounce `dock-layout.json` writes!
  5. Fix `RStudioDockGrid`:
     - Listen to `notify["position"]` on `main_hpaned`, `left_vpaned`, `right_vpaned` (guarded by `if (!syncing_ratios)`) so manual splitter drags update `dock_state.ratios` and persist cleanly, and dynamically reposition `center_crosshair` overlay coordinates (`(main_hpaned.position - 7, ...)` or via `Gtk.Fixed`/margins) instead of anchoring it statically in the center!
     - In `LayoutSerializer.apply_topology_preset`, migrate tabs cleanly when entering `LEFT_TALL_3` / `RIGHT_TALL_3` (e.g., move active Q2 tabs temporarily or record origin quadrant so `QUAD_4` restores them) instead of hiding Console/Terminal/Environment completely!
  6. Register `move_panel_<id>_Q1..Q4` actions cleanly in `WorkspaceDockManager` / `Window.vala` or connect button callbacks directly in the popover so Move-to-Quadrant works.

---

## 4. Phase 1 Verification Checklist

- [ ] `DocumentFormat.from_filename` distinguishes all 7 formats (`.qmd`, `.Rmd`, `.ipynb`, `.md`, `.tex`, `.ts`, `.html`) case-insensitively plus `.R`, `.py`, `.css`, `.bib`.
- [ ] Opening `.ts` highlights with TypeScript rules; opening `.tex` highlights with LaTeX rules; opening `.ipynb` never uses JSON highlighting or `MARKDOWN` badge when `.ipynb` is active; clicking `New -> Markdown` creates pure Markdown without Quarto `.qmd` boilerplate.
- [ ] Switching among Welcome screen and tabs of all 7 formats dynamically updates HeaderBar controls, Ribbon tabs/tools, Home/Insert bars, and status bar badge with zero orphaned controls or `Gtk-WARNING` Pango markup errors.
- [ ] `Ctrl+Z` after opening any file does not revert to starter template; `Ctrl+/` comments lines accurately per format (`%`, `//`, `<!-- -->`, `#`).
- [ ] Dragging 2x2 splitters persists across console output and tab switches; `LEFT_TALL_3` / `RIGHT_TALL_3` preserve access to Console/Environment; automated unit tests cover `FormatProfile`, `DocumentFormat`, and `WorkspaceStateManager` per-tab isolation.
