# Statistical Analysis & Prioritisation

> [!WARNING]
> **Data quality caveat.** Only G2-1, G2-2, and G2-3 were scored by an independent agent. The other 7 scores are coordinator estimates grounded in code inspection (see `00-README.md`).
> All of the independent scores fall in Group 2, so the Group 1 vs Group 2 gap below is **mixed up with who did the evaluating**. Read it as a direction, not a measured effect. With n = 10 and one rating per persona, no inferential test is meaningful. The statistics are descriptive only.

## 1. Score summary (scale 1.0–5.0, n = 10)

| Dimension | Mean | SD | Median | Min | Max | Group 1 mean | Group 2 mean |
|---|---|---|---|---|---|---|---|
| UX | 3.52 | 0.44 | 3.55 | 2.6 | 4.0 | 3.22 | 3.82 |
| Learnability | 3.57 | 0.55 | 3.80 | 2.4 | 4.1 | 3.40 | 3.74 |
| Reliability | 3.47 | 0.29 | 3.55 | 2.8 | 3.8 | 3.30 | 3.64 |
| Feature fit | 3.71 | 0.46 | 3.75 | 2.8 | 4.3 | 3.36 | 4.06 |

- **Overall composite:** 3.57. **Independent-only composite (G2-1…G2-3):** 3.88.
- **Learnability** varies the most (SD 0.55): power users find the app easy and non-technical users find it hard.
- **Reliability** is the most consistent (SD 0.29) and also the lowest mean (3.47). Every persona hit at least one bug.

### Per-persona composite (mean of 4 dimensions)

| Persona | Composite | Source |
|---|---|---|
| G2-1 Biochemistry Professor | 3.95 | independent |
| G2-5 Modern Linux PhD | 3.88 | coordinator |
| G2-2 BSc Freshman | 3.85 | independent |
| G2-3 Wet → Dry Lab | 3.82 | independent |
| G1-3 RStudio Pro | 3.70 | coordinator |
| G1-5 Enterprise Biostatistician | 3.60 | coordinator |
| G1-1 Clinical Bioinformatician | 3.58 | coordinator |
| G2-4 Returning MSc | 3.58 | coordinator |
| G1-4 Colab/Jupyter Veteran | **2.98** | coordinator |
| G1-2 Clinical MD Reviewer | **2.75** | coordinator |

**Reading:** The two lowest personas are exactly the ones who depend on **existing Jupyter notebooks** (G1-4) and on **read-only review** (G1-2). Both are held back by the same root cause: `.ipynb` outputs are never loaded and are wiped on save.

## 2. Theme frequency (how many of 10 personas raised it)

Severity weights: 3 = data loss or blocker, 2 = major friction or functional bug, 1 = polish.
Priority = frequency × severity.

| # | Theme | Personas | Freq | Sev | **Priority** |
|---|---|---|---|---|---|
| T1 | `.ipynb` outputs not displayed and **wiped on save** (`notebook_serializer.vala:530-532`) | G1-2, G1-4, G2-4 | 3 | 3 | **9** |
| T2 | Citation workflow bugs (`set_text` overwrite, `@fig-` detection, YAML bib path ignored, `.bib` overwrite prompt, silent Zotero failure) | G2-1, G2-4, G2-5, G1-3 | 4 | 2 | **8** |
| T3 | Onboarding overload and opaque Tolkien labels; no first-run readiness check | G1-2, G1-4, G2-2, G2-3, G2-4 | 5 | 1.5 | **7.5** |
| T4 | Silent failures with no user feedback (NewProject, Zotero, Galaxy key) | G1-1, G2-1, G2-2, G2-4 | 4 | 2 | **8** |
| T5 | Two export paths and a repeated "non-portable" modal | G1-2, G1-5, G2-1 | 3 | 2 | **6** |
| T6 | RStudio/Jupyter keymap collisions (`Ctrl+Shift+M`, `Ctrl+Alt+I`, `Ctrl+N`, no toggle comment) | G1-3, G1-4 | 2 | 2 | **4** |
| T7 | CSV/TSV import wizard is missing | G1-1, G2-3, G2-4 | 3 | 2 | **6** |
| T8 | Mermaid not rendered in the live preview | G1-5, G2-5 | 2 | 2 | **4** |
| T9 | Bio-bridge input normalisation (gene symbols, case) and invalid `{python label}` headers | G1-1, G2-3 | 2 | 2 | **4** |
| T10 | Elrond AI routes code to the wrong engine and inserts it without fences | G2-2 | 1 | 2 | 2 |
| T11 | Chemistry rendering defects (`NaCl`, literal `$`) | G2-1, G2-5 | 2 | 1 | 2 |
| T12 | No Git integration | G1-5 | 1 | 1 | 1 |
| T13 | No Octave/MATLAB engine | G1-1 | 1 | 1 | 1 |
| T14 | No review/annotation mode | G1-2 | 1 | 2 | 2 |

## 3. Core vs Plugin classification

The rule: **Core** means the problem breaks a workflow that most personas share (data integrity, citing, exporting, onboarding, basic keymaps). **Plugin** means it serves one niche persona or depends on a third-party service, and it fits `src/plugins/PluginManager.vala`.

### Core features and fixes (recommended for the next implementation cycle, in priority order)
1. **T1** Load, display, and preserve `.ipynb` outputs (text, `execute_result`, `display_data` PNG/HTML).
2. **T2** Citation fixes: targeted insert instead of `set_text`; skip `@fig-`/`@tbl-`/`@sec-`/`@eq-`; resolve YAML `bibliography:`; use an *open* dialog for an existing `.bib`; Zotero-unavailable toast with a DOI-manager fallback.
3. **T4** Replace silent failures with toasts (NewProjectDialog, Galaxy keyring).
4. **T3** Plain-English subtitles for the bridges, and a first-run runtime readiness indicator.
5. **T5** "Don't ask again for this project" on the portability modal.
6. **T6** RStudio keymap alignment: `Ctrl+Shift+M` pipe, `Ctrl+Alt+I` insert chunk, `Ctrl+Shift+C` toggle comment.
7. **T7** CSV/TSV → DataGridViewer preview, plus an "insert read code" action.
8. **T8** Offline Mermaid preview.
9. **T9** Uppercase and gene-symbol resolution in the bridges; Quarto-valid chunk headers.
10. **T11** Chemistry tokenizer fixes.

### Optional plugins (backlog)
- Octave/MATLAB engine (G1-1)
- Git panel (G1-5)
- Review comments and annotations (G1-2)
- Corporate report templates and branding (G1-5)
- Journal word/figure-count checker (G2-1)
- Wet-lab assay templates: ΔΔCt, 4PL IC50, ANOVA (G2-3)
- Primer-pair and IUPAC oligo analyser with SantaLucia Tm (G2-3)
- "Bioinformatics 101" tutorial notebooks (G2-2)
- Colab/Drive import (G1-4)
- Learning-platform sync (G2-4)
- Thesis/book templates and zen toolbar (G2-5)
- Time-series and econometrics templates (G1-3)
- Clinical DB connectors: REDCap, OMOP (G1-1)

## 4. Next steps
1. Re-run G1-1…G1-5, G2-4, and G2-5 with independent Goldfish agents once quota resets, to replace the coordinator estimates.
2. Implement Core items 1–10 with tests, then re-score with the same personas (before/after comparison).
3. Publish the methodology and results to the Imladris GitHub Wiki.
