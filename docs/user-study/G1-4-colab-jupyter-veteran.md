# G1-4 — Senior, Change-Reluctant Colab & Jupyter Veteran

> Provenance: the coordinator wrote this report from direct code inspection, because the independent agent hit its quota. Every finding below was checked in the source. The scores are coordinator estimates.

*Profile: Has always used Colab and Jupyter. Python expert working in genetics and molecular biology. Reluctant to learn new tools.*

## 1. Scores (1.0–5.0)
| ux | learnability | reliability | feature_fit |
|---|---|---|---|
| 3.0 | 2.9 | 2.8 | 3.2 |

## 2. Bugs & errors
1. **🔴 Saving `.ipynb` deletes every cell output** (`src/core/notebook_serializer.vala:530-532` always writes an empty `outputs` array). A notebook carefully executed in Colab loses all its figures and results after one save in Imladris. For this persona that is a trust-breaking incident.
2. **🔴 Stored outputs are never displayed when a notebook is opened.** `outputs` is never parsed on load, so opening any existing notebook shows code only.
3. The Python REPL used to hang because of a `SyntaxError` in the `python3 -i` driver. That was **fixed in this cycle** (single-line base64 driver, verified on Python 3.14.10).

## 3. UX friction
- **The notebook is shown as a single Markdown text buffer**, not as cells. There are no cell borders, no `+ Code` / `+ Text` buttons, and no per-cell run button or execution counter. Everything a Colab user relies on to find their way around is missing.
- `Shift+Enter` does run the cell and move to the next one (`src/DocumentPage.vala:437-444`), but only when the cursor is inside a fenced chunk. Outside a chunk it just inserts a newline. That is inconsistent with Jupyter.
- Jupyter command-mode keys (`A`/`B` insert a cell, `DD` deletes it, `M`/`Y` switch type) are missing.

## 4. Missing features
- **`[CORE]` Load, show, and preserve `.ipynb` outputs** (stream, `execute_result`, `display_data` with PNG, `text/html` tables).
- **`[CORE]` A "Notebook view" for `.ipynb`**: cell cards with run buttons, execution counts, and add-cell controls, built on top of the existing chunk parser.
- **`[CORE]` Jupyter keymap preset** (command-mode `A`/`B`/`DD`/`M`/`Y`).
- **`[PLUGIN]` Colab/Drive import and `!pip` magic shim.** It is a migration aid and not needed by everyone.

## 5. Worked well
- `.ipynb` opens natively without a Jupyter server, and code round-trips as valid JSON.
- Python state persists between cells, and matplotlib figures appear in the Plots pane.
- One-click toolchain setup installs Python and Jupyter without any terminal work.
