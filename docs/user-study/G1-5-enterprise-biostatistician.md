# G1-5 — Senior Computational Biologist & Enterprise Biostatistician

> Provenance: the coordinator wrote this report from direct code inspection, because the independent agent hit its quota. Every finding below was checked in the source. The scores are coordinator estimates.

*Profile: Works at a large company and uses VS Code. Writes custom scripts and produces audited reports for business, hospitals, and clients.*

## 1. Scores (1.0–5.0)
| ux | learnability | reliability | feature_fit |
|---|---|---|---|
| 3.4 | 3.9 | 3.5 | 3.6 |

## 2. Bugs & errors
1. **Mermaid diagrams are not rendered in the live preview.** `src/adapters/DocumentAdapter.vala` and `src/DocumentPage.vala` contain no Mermaid handling (`grep -i mermaid` returns no matches), and no `mermaid.js` is bundled. Architecture and process diagrams in client reports show up as raw code until a full Quarto render.
2. **There are two export paths with different behaviour.** The header `Render` button uses QuartoExportEngine; the `Publish` ribbon uses ExportService and opens Save-As first (`src/Window.vala:230-255` vs `2040-2050`, as also found by G2-1). Output location and behaviour differ depending on which one is clicked, which is a reproducibility risk.
3. **A non-portable warning modal appears on every export** (`src/Window.vala:1337-1352`). It blocks scripted and batch-style workflows.

## 3. UX friction
- **There is no Git integration.** `grep '"git"'` over `src/` returns no matches. There is no diff, stage, commit, or branch indicator. A VS Code user expects version control to be built in, especially for audited client deliverables.
- The command palette exists (`Ctrl+Shift+P` / `Ctrl+K`, `src/ui/CommandPaletteDialog.vala`), which is good, but it lists actions only. There is no fuzzy file open (`Ctrl+P`).
- There is no headless or CLI render mode (`imladris --render report.qmd --to pdf`) for CI pipelines.

## 4. Missing features
- **`[CORE]` Offline Mermaid rendering in the WebKit preview** (bundled `mermaid.min.js` in GResource).
- **`[CORE]` One unified export pipeline**, plus a per-project "don't ask again" option for the portability warning.
- **`[PLUGIN]` Git panel** (status, diff, commit, branch). It is valuable, but many users already use external Git tools.
- **`[PLUGIN]` Corporate report templates and branding** (logo, colour theme, disclaimer footer, CSS/LaTeX class packs).
- **`[CORE]` Headless CLI render** (`--render`), which makes CI and automation possible.

## 5. Worked well
- `ProvenanceAttestationService` writes SHA-256 manifests of sources, environments, and lockfiles, giving a strong audit story for regulated clients.
- The MCP server makes the editor scriptable and controllable by AI agents.
- HTML+CSS+LaTeX authoring and native PDF/ODT/RTF export with offline fallbacks.
