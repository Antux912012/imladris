# Group 2 Evaluation Report (G2-1, G2-2, G2-3) — Independent Goldfish Agent

> Provenance: independent `egm-scientist-user` agent (conversation `ff7d52b0-c1e3-484b-9cb8-03d274fc825d`), received 2026-11-13T21:03:41Z. Saved word for word.

Below is the independent out-of-the-box evaluation of **Imladris 0.24.2** (`/home/antonio/Projects/imladris/build-deb/imladris`) across the three Group 2 personas from `/home/antonio/Documents/User-study-implementation.md`.

---

## Persona G2-1: Academia Professor in Biochemistry & Molecular Biology
*Profile: Extensive research and publication record; daily user of RStudio, Quarto, and Jupyter Notebook for manuscripts, grant proposals, biochemistry lecture decks, symposium posters, and supervising student analyses.*

### 1. Numeric Scores (1.0 to 5.0)
- `ux_score`: **3.9 / 5.0**
- `learnability_score`: **4.1 / 5.0**
- `reliability_score`: **3.6 / 5.0**
- `feature_fit_score`: **4.2 / 5.0**

### 2. `bugs_and_errors`
1. **Consecutive uppercase chemical elements merged into single `\text{...}` token (`src/core/MathChemEngine.vala:969-975`)**: In `MathChemEngine.natural_chem_to_latex()`, element scanning loops `while (i < len && s[i].isalpha ()) i++;` (line 972) instead of checking `s[i].islower ()` as `natural_chem_to_markdown()` does at line 1087. Multi-element formulas without intervening digits (e.g., `NaCl`, `KOH`, `NaOH`, `CH3COOH`, `ATP`) merge consecutive elements into a single `\text{NaCl}` or `\text{COOH}` block.
2. **Literal `$` signs rendered in offline chemistry arrow conditions (`src/ui/PresentationTemplateDialog.vala:120` & `src/core/MathChemEngine.vala:1007-1012, 1308-1335`)**: The RevealJS biochemistry template inserts `$$\ce{E + S <=>[$k_1$][$k_{-1}$] ES ->[$k_{\text{cat}}$] E + P}$$`. `natural_chem_to_latex()` wraps bracketed conditions in `\text{$k_1$}`; `strip_outer_delimiters()` (`MathChemEngine.vala:351-356`) only strips `$` if the whole string is wrapped, so literal `$` appears above/below the arrows.
3. **Full-buffer overwrite (`set_text`) on citation insertion from Citations Panel (`src/ui/PersistentPanelRegistry.vala:164-177`)**: Inserting `[@key]` then `doc_page.source_buffer.set_text (updated_text)` (line 174) resets the cursor, clears marks/inline outputs, and breaks undo — unlike `CitationCompletionProvider.ensure_buffer_bibliography_line()`.
4. **"Replace existing file?" warning when choosing an existing `.bib` (`src/ui/DoiBibDialog.vala:63, 180-199`)**: `"Choose / Create..."` uses `dialog.save (...)` (line 188), so picking an existing master `.bib` triggers a destructive overwrite confirmation.
5. **Silent no-op when Zotero is closed (`src/Window.vala:2712-2738` & `src/services/ZoteroService.vala:347-363`)**: `open_native_citation_picker_async()` returns `null` and `open_zotero_picker()` exits with no toast or fallback to `DoiBibDialog`.
6. **Symposium Poster template does not match its description (`PresentationTemplateDialog.vala:83-86, 193-228`)**: advertised 3-column poster with volcano plots; actual output is single-column Typst running `summary(mtcars[, 1:4])`.
7. **Citations panel misidentifies `@fig-`, `@tbl-`, S4 slots, Python decorators as citations (`src/ui/PersistentPanelRegistry.vala:1671-1693`)**.
8. **Citations panel ignores YAML `bibliography:` paths and standalone file directories (`src/ui/PersistentPanelRegistry.vala:118-131`)**: only checks `current_project_dir/references.bib`.

### 3. `ux_friction`
- **Two disconnected export workflows**: header `Render` dropdown (`src/Window.vala:230-255`, QuartoExportEngine) vs. `Publish` ribbon buttons (`src/Window.vala:2040-2050`, ExportService with Save-As first).
- **Repeated "System Libraries (Non-Portable)" modal on every export (`src/Window.vala:1337-1352, 1360`)** with no "Don't ask again for this project".
- **No batch DOI/PMID import in `DoiBibDialog` (`src/ui/DoiBibDialog.vala:78-95, 208-231`)**.

### 4. `missing_features`
- **`[CORE]` PubMed (PMID/PMCID) & batch DOI lookup** in `DoiBibService`/`DoiBibDialog`.
- **`[CORE]` CSL style selector** (Nature, Cell, JBC, NAR) writing `csl:` to YAML.
- **`[CORE]` Real multi-column Typst poster template** with figure scaffolding.
- **`[PLUGIN]` Journal submission word/figure-count & formatting checker.**

### 5. `worked_well`
- Tiered Zotero + Better BibTeX + offline `.bib` + Crossref DOI architecture.
- Self-healing TinyTeX provisioning (`src/core/QuartoExportEngine.vala:99-116`).
- Natural Biochemistry & Math Studio (`src/ui/MathChemEditorDialog.vala`).

---

## Persona G2-2: Undergraduate Bioinformatics Freshman
*Profile: First-year Bachelor's student with zero prior coding, CLI, or bioinformatics experience.*

### 1. Numeric Scores (1.0 to 5.0)
- `ux_score`: **3.8 / 5.0**
- `learnability_score`: **3.5 / 5.0**
- `reliability_score`: **3.8 / 5.0**
- `feature_fit_score`: **4.3 / 5.0**

### 2. `bugs_and_errors`
1. **Elrond AI code cards misroute non-Python languages to R (`src/ui/ElrondChatPanel.vala:603, 619-628`)**: `code_engine = (lang == "python"||"py") ? "python" : "r"` sends `bash`/`sh` blocks into R.
2. **Elrond "Insert at Cursor" pastes bare code into Markdown prose without chunk fences (`src/ui/ElrondChatPanel.vala:606-616`)**.
3. **Silent failure when project/file creation fails in `NewProjectDialog` (`src/ui/new_project_dialog.vala:297-299, 336-338, 364-366`)**: only `GLib.warning`, no toast.
4. **`Create .Rproj` hardcodes Sandboxed (`src/ui/new_project_dialog.vala:16, 302-339`)**.
5. **Inconsistent target directory preview (`src/ui/new_project_dialog.vala:261-264` vs `274-276`)**.
6. **`ToolchainSetupDialog` cannot be cancelled; dangling signal handlers if closed mid-install (`src/ui/ToolchainSetupDialog.vala:198-254`)**.
7. **Cross-language symbol leakage in `CodeIntelliSenseEngine.scan_buffer_symbols()` (`src/editor/CodeIntelliSenseEngine.vala:455-524`)**.

### 3. `ux_friction`
- **Cognitive overload**: 3 toolbar tiers + 4-quadrant dock with 13+ panel tabs + opaque Tolkien names (`Yavanna`, `Taniquetil`, `Elbereth`, `.mallorn`, `Arekyer`) in `src/Window.vala:341, 354, 367`.
- **Standard vs. Sandboxed vs. `.Rproj` confusion** in `NewProjectDialog` (`src/ui/new_project_dialog.vala:98-158`).
- **Elrond AI setup friction** (`src/ui/ElrondChatPanel.vala:408-438`): starter pills error out when no LLM is configured, with no guided setup.

### 4. `missing_features`
- **`[CORE]` Plain-English labels/subtitles for domain bridges** (e.g. "Gene & Primer Lookup (Yavanna)").
- **`[CORE]` Auto-wrap Elrond snippets in fenced chunks** when inserted into prose.
- **`[CORE]` One-click "Explain & Fix Error"** on console errors.
- **`[PLUGIN]` "Bioinformatics 101" interactive starter notebooks.**

### 5. `worked_well`
- Zero-config Micromamba Toolchain Manager.
- Built-in dataset column autocomplete & fuzzy IntelliSense.
- `?topic` / `help()` interception into the Help pane.

---

## Persona G2-3: Wet-Lab Veteran Transitioning to Dry-Lab
*Profile: Deep wet-lab experience (RT-qPCR, westerns, ELISA, primer design, protein assays) learning dry-lab R/Python.*

### 1. Numeric Scores (1.0 to 5.0)
- `ux_score`: **3.9 / 5.0**
- `learnability_score`: **3.8 / 5.0**
- `reliability_score`: **3.5 / 5.0**
- `feature_fit_score`: **4.1 / 5.0**

### 2. `bugs_and_errors`
1. **AlphaFold Inspector 404s on its own placeholder examples `P53_HUMAN`/`BRCA1` (`src/bridges/taniquetil/AlphaFoldBridgePopover.vala:119, 281-292`)**: endpoint accepts only primary UniProt accessions.
2. **Yavanna resolver fails on gene symbols/lowercase (`src/bridges/yavanna/BioEntityPopover.vala:271-280, 356-361`)**; `has_prefix ("ENSG")` is case-sensitive.
3. **Invalid Quarto Python chunk headers `{python yavanna-%s}` / `{python taniquetil-%s}` (`BioEntityPopover.vala:457`, `AlphaFoldBridgePopover.vala:392`)**: Quarto requires `{python}` + `#| label:`.
4. **Oligo calculator uses Marmur-Doty Tm, single primer only, strips IUPAC codes (`BioEntityPopover.vala:560-566, 602-608, 646-669`)**.
5. **Forest plot template omits 95% CI error bars (`src/bridges/elbereth/ClinicalBiostatsPopover.vala:559-568`)**.
6. **Dead `environment_list` widget rebuilt on every refresh (`src/ui/PersistentPanelRegistry.vala:553, 1595-1708`)** including a hardcoded `mtcars` row.

### 3. `ux_friction`
- **Scientific tools buried in nested header-bar popovers (`src/Window.vala:286-395`)**; autohide loses state when copying from the document.
- **No GUI CSV/TSV/Excel import**: clicking `.csv` in Files (`src/ui/PersistentPanelRegistry.vala:1004-1006`) opens raw text.
- **Elbereth templates assume CDISC clinical variables**, not bench-assay layouts.

### 4. `missing_features`
- **`[CORE]` CSV/TSV/plate import wizard** (preview in `DataGridViewer` + insert `read.csv`/`pd.read_csv`).
- **`[CORE]` Auto-resolve gene symbols & normalise case** in AlphaFold/Yavanna.
- **`[PLUGIN]` Wet-lab bench assay templates** (ΔΔCt, 4PL IC50, standard curve, ANOVA).
- **`[PLUGIN]` Primer pair & IUPAC degenerate oligo analyser** (SantaLucia NN Tm).

### 5. `worked_well`
- Direct code & provenance injection from Yavanna/Taniquetil/Elbereth.
- `View(df)` DataGridViewer & plot gallery.
- Visual power curve & sample-size justification (Elbereth).
