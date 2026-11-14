# G1-2 — MD in Clinical Research (Non-Technical Reviewer)

> Provenance: the coordinator wrote this report from direct code inspection, because the independent agent hit its quota. Every finding below was checked in the source. The scores are coordinator estimates.

*Profile: Genetics and disease clinician with limited technical background. Reviews notebooks and reports prepared by her assistants.*

## 1. Scores (1.0–5.0)
| ux | learnability | reliability | feature_fit |
|---|---|---|---|
| 2.6 | 2.4 | 3.2 | 2.8 |

## 2. Bugs & errors
1. **🔴 Results saved in assistants' Jupyter notebooks are never shown.** `src/core/notebook_serializer.vala` never reads the `outputs` array of `.ipynb` cells. The only reference to `outputs` is at line 530, and that is on the *write* path. When the MD opens an assistant's executed notebook, she sees code with **no tables, plots, or printed results**. She would have to re-run code she does not understand, possibly without the required data or packages. For a reviewer this is a workflow blocker.
2. **🔴 Saving a notebook wipes its outputs.** `notebook_serializer.vala:530-532` always writes `"outputs": []`. Pressing Ctrl+S on a colleague's notebook silently deletes every result stored in it. This is data loss.
3. **The "System Libraries (Non-Portable)" modal appears on every export** (`src/Window.vala:1337-1352`), as also found by the independent G2-1 agent. Its technical wording means nothing to a clinician.

## 3. UX friction
- **There is no read-only, review, or annotation mode.** `grep -i "read_only\|review\|annotation"` returns only one unrelated comment. A reviewer can accidentally edit or execute the assistant's code, and she has no way to leave margin comments.
- **The first screen is overwhelming.** It shows 3 toolbar tiers, a 4-quadrant dock with more than 13 tabs, and Tolkien-named tools (as G2-2 also reported). Nothing offers a simple "just read this report" layout.
- Rendered HTML/PDF previews are good, but she has to know that she should switch to the preview pane or the Publish ribbon.

## 4. Missing features
- **`[CORE]` Display stored `.ipynb` outputs (text, tables, images) and keep them on save.** Every Jupyter user depends on this.
- **`[CORE]` Read-only "Review mode"**: a single toggle that locks editing, hides the console and environment, and shows the rendered preview full-width.
- **`[PLUGIN]` Review comments and annotations** stored as a sidecar file and exportable as a review report.
- **`[CORE]` A plain-language export flow**: one "Share as PDF/Word" button with no technical modals.

## 5. Worked well
- Native WebKit preview of HTML, Markdown, and Quarto, with offline math rendering.
- Export to PDF, ODT (opens in Word/LibreOffice), and RTF, with offline fallbacks.
- Crash recovery restores unsaved work on the next launch (`src/Window.vala:711`).
