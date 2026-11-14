# G2-5 — PhD Student on a Modern Linux Desktop

> Provenance: the coordinator wrote this report from direct code inspection, because the independent agent hit its quota. Every finding below was checked in the source. The scores are coordinator estimates.

*Profile: GNOME/Wayland user who wants a fast native tool for publication-grade reports with figures, diagrams, math, and citations.*

## 1. Scores (1.0–5.0)
| ux | learnability | reliability | feature_fit |
|---|---|---|---|
| 4.0 | 4.0 | 3.6 | 3.9 |

## 2. Bugs & errors
1. **Mermaid diagrams show as raw code in the live preview.** There is no Mermaid handling in `src/adapters/DocumentAdapter.vala` or `src/DocumentPage.vala`, and the `MermaidFlowStudioDialog` output is not previewed inline. Diagrams are a core part of a thesis.
2. **Chemistry rendering defects** (`src/core/MathChemEngine.vala:969-975, 1007-1012`), as also found by G2-1: `NaCl`/`COOH` tokens are merged, and literal `$` appears in reaction-arrow conditions.
3. **Citation scanning treats Quarto cross-references (`@fig-…`, `@tbl-…`) as citations** (`src/ui/PersistentPanelRegistry.vala:1671-1693`, as also found by G2-1). Thesis cross-references fill up the citations panel.
4. **Startup used to print a Pango markup warning** for "DOI & .bib Bibliography Manager". That was **fixed in this cycle**.

## 3. UX friction
- The GTK4/libadwaita look, the dark/sepia themes, and the accent colours that follow the GNOME accent are excellent and feel native. Only the toolbar density is heavy for a 13″ laptop.
- `@citation` keys show as raw text in the live preview until a full Quarto render.
- There is no outline-driven navigation for long thesis documents (chapters, sections, figures).

## 4. Missing features
- **`[CORE]` Offline Mermaid preview** (shared with G1-5).
- **`[CORE]` Exclude cross-reference prefixes from citation detection** (`@fig-`, `@tbl-`, `@sec-`, `@eq-`).
- **`[CORE]` Live citation preview** that resolves `@key` against the `.bib` file into "Author (Year)" in the preview.
- **`[PLUGIN]` Thesis/book templates** (Quarto book, university LaTeX classes).
- **`[PLUGIN]` Zen / compact toolbar mode** for small screens.

## 5. Worked well
- A native GTK4/libadwaita app that is fast and works with the system dark mode and accent colour.
- HTML+CSS+LaTeX live preview with offline math, plus Quarto PDF with self-healing TinyTeX.
- Native Flatpak, `.deb`, RPM, and Arch packaging.
