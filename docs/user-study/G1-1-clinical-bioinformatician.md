# G1-1 — Experienced Clinical Bioinformatician

> Provenance: the coordinator wrote this report from direct code inspection, because the independent agent hit its quota. Every finding below was checked in the source. The scores are coordinator estimates.

*Profile: Clinical data, Galaxy, biological databases, RStudio, MATLAB/Octave.*

## 1. Scores (1.0–5.0)
| ux | learnability | reliability | feature_fit |
|---|---|---|---|
| 3.6 | 3.8 | 3.4 | 3.5 |

## 2. Bugs & errors
1. **Galaxy API key load failures are silently swallowed.** In `src/bridges/galaxy_client.vala:209-218`, `load_api_key_async` catches `GLib.Error` with only the comment *"Secret service may be absent"*. No log, toast, or panel state change follows. If the keyring is locked or unavailable, the user sees an authenticated-looking panel, and the next API call fails with a confusing error.
2. **Bridge resolvers reject gene symbols and lowercase IDs**, as also found by the independent G2-3 agent. The causes are `src/bridges/yavanna/BioEntityPopover.vala:271-280, 356-361` and `src/bridges/taniquetil/AlphaFoldBridgePopover.vala:281-292`. Clinical bioinformaticians routinely type `TP53`, `brca1`, or `ensg…`.
3. **The bridges generate invalid Quarto Python chunk headers** (`{python yavanna-…}`) at `BioEntityPopover.vala:457` and `AlphaFoldBridgePopover.vala:392`. This breaks `quarto render` on Jupyter-engine documents.

## 3. UX friction
- **No MATLAB/Octave engine at all.** `grep -i "octave\|matlab"` over `src/` returns no matches. `.m` scripts and ```` ```{octave} ```` chunks cannot be run. This persona's legacy signal-processing and statistics scripts have no home.
- **Galaxy, Yavanna, Taniquetil, and Elbereth sit in nested header-bar popovers** (`src/Window.vala:286-395`). They are not dockable panels, so a database lookup cannot stay open next to the analysis.
- **No CSV/TSV import preview.** Clinical extracts open as raw text (`src/ui/PersistentPanelRegistry.vala:1004-1006`).

## 4. Missing features
- **`[PLUGIN]` Octave/MATLAB execution engine** (`octave-cli` via `PlatformUtils.resolve_runtime`). Only part of the user base needs it, and it fits the existing `PluginManager` well.
- **`[CORE]` CSV/TSV import wizard into `DataGridViewer`.** Data intake is basic functionality for every analysis persona.
- **`[CORE]` Gene-symbol resolution and case normalisation** in the bio-entity bridges.
- **`[PLUGIN]` Clinical database connectors** (REDCap, OMOP/SQL, cBioPortal). These are specialised and institution-specific.

## 5. Worked well
- The Galaxy bridge with keyring-stored credentials and generated workflow chunks (`src/bridges/galaxy_chunk_generator.vala`).
- The Elbereth clinical biostatistics templates and power curves.
- The provenance attestation (SHA-256 manifests) gives a GxP-style audit trail for clinical reports.
