# G1-3 — Linux & RStudio Pro (Statistics / Finance)

> Provenance: the coordinator wrote this report from direct code inspection, because the independent agent hit its quota. Every finding below was checked in the source. The scores are coordinator estimates.

*Profile: Expert, keyboard-driven RStudio user. Works on statistical modelling, time series, renv, and RMarkdown/Quarto.*

## 1. Scores (1.0–5.0)
| ux | learnability | reliability | feature_fit |
|---|---|---|---|
| 3.5 | 4.0 | 3.6 | 3.7 |

## 2. Bugs & errors
1. **Shortcut collisions with RStudio muscle memory** (`src/Application.vala:132-159`):
   - `Ctrl+Shift+M` is bound to `app.insert_image` (line 143). In RStudio this key inserts the pipe (`|>` / `%>%`), and an R pro presses it hundreds of times a day.
   - `Ctrl+Alt+I` is bound to `app.insert_image` (line 143). In RStudio it means **Insert Code Chunk**.
   - `Ctrl+N` opens the *New Project* modal (line 132). In RStudio it creates a new untitled script.
2. **Toggle comment is missing** (`Ctrl+Shift+C`). `grep "toggle_comment"` returns no matches.
3. **The citations panel overwrites the whole buffer** (`src/ui/PersistentPanelRegistry.vala:174`), as also found by the independent G2-1 agent. The undo history is lost.

## 3. UX friction
- RStudio's core keys **do** work: `Ctrl+Enter` runs the current line, `Ctrl+Shift+Enter` runs the chunk, `Ctrl+Alt+R` runs all, `Ctrl+Alt+P` runs chunks above, `Ctrl+Shift+F10` restarts, `Ctrl+L` clears the console, and `Ctrl+Shift+K` renders. That is why learnability scores high. But the three collisions above break flow constantly.
- There are no pane-focus shortcuts (`Ctrl+1` editor, `Ctrl+2` console) and no `Alt+-` for the `<-` assignment operator.
- R execution was rebuilt in this cycle (`R --slave` driver with `withVisible`). It now handles auto-printed ggplots and incomplete expressions correctly. That raises reliability.

## 4. Missing features
- **`[CORE]` RStudio keymap compatibility**: `Ctrl+Shift+M` → pipe, `Ctrl+Alt+I` → insert chunk, `Ctrl+N` → new script, `Ctrl+Shift+C` → toggle comment, `Alt+-` → `<-`.
- **`[CORE]` A selectable keymap preset** (RStudio / Jupyter / VS Code) in Preferences.
- **`[PLUGIN]` Time-series and econometrics templates** (forecast, tsibble, quantmod). These suit a specialised audience.

## 5. Worked well
- A faithful RStudio 4-pane layout with Environment, `View(df)` DataGridViewer, plots, and `?help`.
- Mallorn/renv sandboxed projects and snapshot/restore.
- The Packages ribbon for CRAN install and management.
