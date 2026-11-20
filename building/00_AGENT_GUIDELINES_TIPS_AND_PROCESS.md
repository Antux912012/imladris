<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# Building File 00 — Guidelines, Engineering Tips & Execution Process

**Target Agent:** `Hydrogen 4 Medium` (`gemini-4-hydrogen-medium`)
**Applies To:** All work in `/home/antonio/Project/imladris` across Phases 1–4.

---

## 1. Ground-Truth Environment & Baseline Facts

Before touching code, verify your build/runtime environment rather than assuming tools exist on `$PATH`:

1. **Host Tooling Observed at Audit Time (`7eb6b95`):**
   - Present on host: `ninja`, `flatpak`, `quarto` (`1.11.9`), `R` / `Rscript` (`4.6.2` with `rmarkdown`, `knitr`, `jsonlite`), `python3` (`3.15.2`), `pdflatex` / `lualatex` (`TeX Live 2026`), `bibtex`, `node` (`v22.23.1`), `npm`, `npx`.
   - Broken/missing on host `$PATH` at audit time: `valac`, `meson`, `cargo`, `rustc`, `flatpak-builder`, `pandoc`, `tectonic`, `tsc`, `/home/antonio/.local/bin/jupyter` (missing `jupyter_core` for Python 3.15), `org.gnome.Sdk` Flatpak SDK.
   - Installed Flatpak runtimes/extensions observed: `org.gnome.Platform` (`50`, `51`), `org.freedesktop.Platform` (`25.08`, `26.08`), `org.freedesktop.Sdk.Extension.texlive` (`25.08`, `26.08`).
2. **Action for Hydrogen 4 Medium before Phase 1:**
   - Run an initial environment check (`which meson valac cargo rustc pkg-config` and `flatpak list`).
   - If building via Flatpak SDK, use `org.gnome.Sdk//51` (+ matching `org.freedesktop.Sdk.Extension.rust-stable`) or local distro toolchain / container where `gtk4 >= 4.12`, `libadwaita-1 >= 1.5`, `gtksourceview-5 >= 5.10`, `webkitgtk-6.0`, `javascriptcoregtk-6.0`, `libsoup-3.0`, `json-glib-1.0`, `libsecret-1`, `gee-0.8`, `vala`, `meson`, `cargo`, `rustc` are installed.
   - Never fake or skip test verification if a build tool is missing — install or invoke inside the proper SDK/build container or report the exact blocker clearly.

---

## 2. Hard Engineering Guidelines (Non-Negotiable)

### 2.1 Vala, C11 Codegen & GLib Memory/Thread Safety
1. **Strict GTK Main-Thread Ownership:**
   - NEVER touch `Gtk.Widget`, `GtkSource.Buffer`, `GtkSource.View`, `WebKit.WebView`, or `Adw.*` from background `GLib.Thread` or `Subprocess` callbacks unless marshaled explicitly via `GLib.Idle.add` (or `async` methods running on `GLib.MainContext.default ()`).
2. **Zero Sync I/O or Subprocess Blocking on the UI Thread:**
   - Replace every remaining `proc.communicate_utf8`, `GLib.Process.spawn_command_line_sync`, or synchronous network/filesystem scan in `PlatformUtils`, `ToolchainManager`, `ExportService`, and `Window` with `async` (`communicate_utf8_async`, `wait_check_async`) paired with a **`GLib.Timeout` + `GLib.Cancellable`** deadline.
3. **Always Escape User/Document Strings Before Serialization:**
   - **Pango Markup (`Gtk.Label.set_markup`, `Adw.PreferencesRow.title`/`subtitle`):** Libadwaita `ActionRow`/`ComboRow`/`SwitchRow`/`ExpanderRow` default to `use_markup = true` (while `Adw.PreferencesPage.title` and `Adw.PreferencesGroup.title` render plain UTF-8!). Either set `use_markup = false` when showing filenames/diagnostics or pass `GLib.Markup.escape_text(...)`. Use `"and"` rather than `"&"`/`"&amp;"` in static UI headers.
   - **HTML:** Always escape interpolated titles, filenames, diagnostics, plot paths, LaTeX fallback text, and code contents via `GLib.Markup.escape_text(...)` or structured Rust HTML generation. Never interpolate raw URLs without validating schemes (`http:`, `https:`, `file:`, relative paths only — reject `javascript:`, `data:text/html`, `vbscript:`).
   - **JSON / YAML / R / Python Strings:** NEVER use `.printf ("... \"%s\" ...", user_val)` for JSON (`kernel.json`, `.ipynb`, `.mallorn.json`) or YAML frontmatter or R (`PackagesRibbonBar`, `DataGridViewer`, `ExportService`) or Python (`DataGridViewer`, `ToolchainManager`). Use `Json.Builder`/`serde_json`, `serde_yaml`, or Base64 / argv/stdin JSON payloads!
4. **Never Corrupt Undo Stack (`Ctrl+Z`):**
   - Any programmatic setup (`populate_starter_template` followed by opening a file, restoring crash recovery, or inserting/removing `InlineChunkOutputWidget` anchors `\uFFFC`) MUST wrap mutations in `buffer.begin_not_undoable_action ()` / `buffer.end_not_undoable_action ()`, NOT `begin_user_action ()`.
5. **Single Canonical Buffer Text Accessor (`get_clean_source_text()`):**
   - Add `public string get_clean_source_text ()` on `DocumentPage` that strips **all** `\uFFFC` (`\xef\xbf\xbc`) child-anchor placeholder characters cleanly (or extracts ranges between anchors).
   - **Forbid direct `.source_buffer.text` reads** for saving, previewing, chunk parsing, outline indexing, compilation, export, GxP provenance hashing, word count, REPL sourcing, or recovery snapshotting! Every caller must go through `get_clean_source_text ()`.
6. **Prevent Singleton Signal Leaks & Cross-Tab Contamination:**
   - Avoid connecting per-tab (`DocumentPage` / `PersistentPanelRegistry`) handlers to global singletons without tracking `ulong` handler IDs and disconnecting in `dispose ()` / `close_page`, OR better: scope sessions/signals per workspace/document/request using `GLib.WeakRef` and request IDs so closing a tab or running chunks in Tab A never leaks into Tab B!
7. **Close Every `GLib.FileEnumerator` and Reap Child Processes:**
   - Always `try { ... } finally { enumerator.close (); }` cleanly (never leak file descriptors). Track child PIDs/subprocesses so closing a tab or window terminates owned helpers instead of leaving orphan `R`, `python3`, `latexmk`, or `node` processes.

### 2.2 UTF-8 Byte Offsets vs Character Offsets in Vala
* **Classic Bug Observed:** Taking a byte index from `text.down ().index_of (...)` or `Regex` match byte offsets (`mi.fetch_pos`) and passing it back to `text.substring (...)` or `Gtk.TextIter` character offsets breaks on accents, Greek/math symbols (`×`, `∈`, `α`, `→`), or case-changing Unicode characters (`İ`, `ß`).
* **Rule:** Always slice/search using the same string object's byte positions OR convert byte positions to UTF-8 character offsets explicitly (`str.substring (0, byte_pos).char_count ()`) before calling `TextBuffer.get_iter_at_offset` / `forward_chars`.

### 2.3 Rust C-ABI Integration Hygiene
1. Keep the Vala <-> Rust FFI boundary minimal, coarse-grained, and UTF-8 JSON-based (plus explicit `imladris_free_string (char *ptr)` exported by Rust via `Box::into_raw` / `CString::into_raw` / `CString::from_raw`):
   - **Rule:** Never return borrowed Rust `&str` pointers across FFI. Every allocated `char*` returned by `imladris_core_*` must be freed cleanly in Vala (use `[CCode (cname = "imladris_...", free_function = "imladris_free_string")]` or `owned string` / wrapper helpers verified with AddressSanitizer / Valgrind / GLib leak tests!).
   - **Rule:** Every Rust `#[no_mangle] pub extern "C" fn` MUST wrap its body in `std::panic::catch_unwind(...)` so a Rust panic **never** unwinds across the C/Vala ABI boundary (UB / immediate crash).
   - **Rule:** Use `Cargo.lock` + offline vendoring (`cargo vendor`) / `cargo-sources.json` so **Flatpak offline sandboxed builds work with zero network access**.

### 2.4 GTK4 / Libadwaita / WebKitGTK 6.0 Best Practices
1. Never keep stale local variables (`var btn_render_quarto`) unbound when `update_ribbon_state_machine` needs to toggle `.visible`, `.sensitive`, label, or tooltip on format switches. Store every adaptive control as an explicit field or register it cleanly with a data-driven adaptive controller.
2. Remember GTK 4 CSS: `transition` / animations follow `@accent_color` / `@accent_bg_color` and `SettingsManager` theme changes; **never hardcode `#ffffff` or `#3584e4` in WebView HTML or CSS without CSS custom property theme variables (`--bg`, `--fg`, `--surface`, `--border`, `--accent`, `--code-bg`) synchronized with `SettingsManager.app_theme` (`SYSTEM`, `LIGHT`, `DARK`, `EYE_FRIENDLY`)**!
3. Never use `web_view.reload ()` to re-apply settings when HTML was loaded with `load_html (html, base_uri)` — `reload ()` reloads `base_uri` (a directory listing or blank page!). Store last rendered payload or call `doc_page.refresh_live_preview (true)`!
4. Keep WebKitGTK 6.0 secure: disable arbitrary script execution & `allow_universal_access_from_file_urls` on untrusted HTML/Markdown previews unless explicitly opted into trusted mode, OR enforce Content-Security-Policy + isolated base origins.

### 2.5 Flatpak & External Toolchains
1. Inside Flatpak (`/.flatpak-info` exists):
   - Always check **project sandbox** (`.imladris-env`, `.venv`, `renv`, `node_modules/.bin`), then **managed global toolchain** (`base-ds`), then **Flatpak-bundled extensions** (`/usr/lib/sdk/texlive/...` or bundled app bin if present), then **host via `flatpak-spawn --host`** **BEFORE** checking container `/usr/bin/python3` or `/bin/sh`! Otherwise `/usr/bin/python3` inside `org.gnome.Platform` silently shadows the host scientific Python!
   - When calling `flatpak-spawn --host`, forward ALL required launcher env vars explicitly as `--env=KEY=VALUE` (filtered safely) and handle `--directory=` fallback when `working_dir` is inside a container-only path (`/tmp`, `/app`).
2. Never ship Flatpak manifests claiming host execution without `--talk-name=org.freedesktop.Flatpak`, and never claim features in `metainfo.xml`, `README.md`, or `FLATHUB_AI_DISCLOSURE_AND_SUBMISSION.md` that contradict the manifest.

---

## 3. Coding Tips & Common Traps in This Codebase

* **Trap 1 — `ChunkParser` vs Display Fences:** `Markdown` and `.ipynb` Markdown cells routinely contain ` ```json `, ` ```yaml `, ` ```bash `, ` ```mermaid `. **Executable chunks use `{lang}` (or explicit Imladris/Jupyter engine syntax `{r}`, `{python}`, `{bash}`, `{ts}`, `{julia}`, `{sql}` — NOT bare ` ```json `!)** EXCEPT when explicitly configured for Mermaid visual diagrams (` ```mermaid ` or ` ```{mermaid} `).
* **Trap 2 — R `local({ ls() })` Scope Bug:** In R, calling `ls()` inside `local({...})` returns ONLY variables local to that anonymous `local()` frame! Always pass `ls(envir = .GlobalEnv, all.names = FALSE)` and `get(x, envir = .GlobalEnv)`.
* **Trap 3 — R `setwd()` Silently Ignored by Protocol Loop:** Remember `PersistentSessionManager`'s R driver checks `if (length(.parts) < 4L) next`. **Every** command sent to R/Python (even `setwd`, `os.chdir`, environment inspection, package install) MUST go through the locked `execute_r` / `execute_python` 4-field protocol queue!
* **Trap 4 — `Window.save_document_async` Drops `.ipynb` Context:** Always store the original raw file contents (or serialized notebook metadata model) on `DocumentPage` (`raw_ipynb_source`) and pass it to `DocumentAdapter.save_from_editor_buffer (clean_text, fmt, doc_page.raw_ipynb_source)` so language detection, cell IDs, metadata, and attachments aren't wiped!
* **Trap 5 — `Gtk.TextMark` vs `Gtk.TextChildAnchor`:** Anchor `InlineChunkOutputWidget` directly by storing the `Gtk.TextChildAnchor` + a left-gravity `Gtk.TextMark` placed *before* the newline/anchor, checking `!anchor.get_deleted ()` before updating in-place, and updating sequential cells one by one (`async`) using marks resolved dynamically after each cell finishes.
* **Trap 6 — Test Isolation (`XDG_*`):** `test_dock_environment.vala` previously overwrote the developer's real `~/.config/imladris/dock-layout.json`! Every unit test MUST initialize a temporary root directory (`GLib.DirUtils.make_tmp ("imladris-test-XXXXXX")`) and set `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME` BEFORE calling `SettingsManager` / `RStudioDockLayoutState` / `RecoveryService` / `HistoryManager` singletons, and recursively delete it in `finally` / teardown!

---

## 4. Mandatory Process to Follow (For Every Task / Phase)

Follow this 6-step engineering loop on every Building File (`01` -> `02` -> `03` -> `04`):

1. **Inspect Before Editing:**
   - Read the exact file sections cited in the Building File before editing; verify line numbers and symbol names in current `HEAD` (earlier edits in Phase 1 will shift line numbers for Phase 2+).
2. **Implement Small, Cleanly Modularized Changes:**
   - Keep `Window.vala` from growing further — decompose adaptive UI, execution queueing, and per-format handlers into dedicated single-responsibility classes under `src/core/`, `src/services/`, `src/adapters/`, `src/runners/`, `src/ui/`, and `rust/imladris_core/`, and register every new `.vala` file in `meson.build` (`test_sources` and `imladris_sources` as needed).
   - Maintain SPDX headers (`GPL-3.0-or-later`) and concise docstrings/comments explaining the *why*.
3. **Compile Cleanly After Each Phase:**
   - Build both C/Vala and Rust staticlib (`meson compile -C builddir`), treating any new compiler warnings as issues to resolve cleanly.
4. **Write & Run Automated Tests Incrementally:**
   - Add unit tests for every bug fixed and every new format (`TEX`, `TS`, `HTML`, `MD`, `QMD`, `RMD`, `IPYNB`) BEFORE moving to the next phase.
   - Run `GSETTINGS_BACKEND=memory meson test -C builddir --print-errorlogs`.
5. **Run Real Tooling Smoke Verification Across All 7 Formats:**
   - Exercise fixture files (`fixtures/sample.qmd`, `sample.Rmd`, `sample.ipynb`, `sample.md`, `sample.tex`, `sample.ts`, `sample.html`) through parsing, live HTML generation, chunk execution, and external compiler/runner pipelines (`quarto`, `Rscript`, `python3`, `pdflatex`, `node`).
6. **Check Off Acceptance Criteria & Sync Docs:**
   - Only check boxes `[x]` when observed test output passes completely with zero skipped assertions or mocked-away coverage gaps. Update `docs/` and packaging manifests at the end of Phase 4.
