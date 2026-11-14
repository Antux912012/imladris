# G2-4 — Returning MSc Student (10 years in CX/BPO, now studying Bioinformatics online)

> Provenance: the coordinator wrote this report from direct code inspection, because the independent agent hit its quota. Every finding below was checked in the source. The scores are coordinator estimates.

## 1. Scores (1.0–5.0)
| ux | learnability | reliability | feature_fit |
|---|---|---|---|
| 3.5 | 3.3 | 3.7 | 3.8 |

## 2. Bugs & errors
1. **Coursework notebooks lose their outputs on save** (`src/core/notebook_serializer.vala:530-532`). Notebooks downloaded from online course platforms (Coursera, edX) have their solutions and plots wiped as soon as they are saved.
2. **The Zotero picker fails silently when Zotero is closed** (`src/Window.vala:2712-2738`), as also found by G2-1. A returning student does not know why nothing happened.
3. **Choosing an existing `.bib` brings up a "Replace file?" prompt** (`src/ui/DoiBibDialog.vala:188`, as also found by G2-1). That is frightening for someone who is not sure they won't lose their references.
4. **New project creation fails silently** (`src/ui/new_project_dialog.vala:297-299`, as also found by G2-2).

## 3. UX friction
- Labels mix jargon and fantasy names (`Mallorn`, `Elrond`, `Arekyer`, `GxP Lock`). Someone coming from CX expects clear, task-named actions such as "Import data", "Cite a paper", or "Share report".
- There is no guided first-run tour and no interactive "what is this panel?" overlay.
- Switching between a course's `.ipynb` and the student's own `.qmd` works. However, the visual model changes completely: the notebook shows as text and the preview pane shows HTML.

## 4. Missing features
- **`[CORE]` First-run onboarding tour**, with a runtime readiness summary (R / Python / Quarto / LaTeX ✓/✗) in the status bar.
- **`[CORE]` Keep notebook outputs** (shared with G1-2 and G1-4).
- **`[CORE]` A friendly toast with a fallback** when Zotero is unavailable: "Zotero isn't running — use the DOI manager instead?"
- **`[PLUGIN]` Learning-platform integration** (course notebook sync, assignment submission).

## 5. Worked well
- **Crash recovery and autosave**: every buffer change writes a recovery snapshot (`src/DocumentPage.vala:377`), and it is offered again on startup (`src/Window.vala:711`). That is reassuring for students on unreliable home setups.
- DOI → BibTeX in one paste, without needing Zotero at all.
- `View(df)` spreadsheet grid for inspecting data, which feels familiar after years of Excel in CX roles.
