<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# IMLADRIS UI/UX, GNOME/LIBADWAITA HIG & GPU-ACCELERATED PHYSICS BLUEPRINT
**Target Execution Model**: `Gemini 3.8-Flash-High` / `Gemini 3.8-Flash-Medium`  
**Role Persona**: Principal Scientific GUI Architect, Senior GNOME/GTK4 & Libadwaita HIG Designer, and GPU Graphics Systems Engineer (Alacritty / PuTTY / GSK Pipeline Specialist)  
**Target Codebase**: Imladris (`io.github.Antux912012.Imladris`) — GTK4 + Libadwaita 1.5+ + GtkSourceView 5 + WebKitGTK 6.0 in Vala

---

## 1. Executive UI/UX & Scientific GUI Audit

As a hybrid scientific workbench bridging **Apostrophe** (distraction-free academic prose) and **RStudio / Posit Workbench** (high-density 4-quadrant computational biostatistics and multi-omics IDE), Imladris faces a unique interface challenge: it must respect the **GNOME Human Interface Guidelines (HIG)** while delivering the **zero-latency, crisp glyph and frame pacing** of GPU-accelerated terminal emulators like **Alacritty** and **PuTTY**.

Our comprehensive line-by-line audit of `src/`, `data/style.css`, and `data/imladris.gresource.xml` identified five critical areas requiring remediation and architectural optimization:

### 1.1 Typography, Pango Markup & Header Hierarchy Audit
1. **Literal `&amp;` Entities in Non-Markup Properties**:
   - `Adw.PreferencesPage.title` and `Adw.PreferencesGroup.title` render plain UTF-8 strings (`use_markup` is not active on page/group header labels). Setting `title = "AI &amp; Elrond"` in `src/ui/PreferencesDialog.vala` caused the literal string `"AI &amp; Elrond"` to appear in the `Adw.ViewSwitcher` header bar.
2. **Unescaped `&` in Pango Markup Properties (`Adw.PreferencesRow.title` / `.subtitle`)**:
   - `Adw.PreferencesRow` (`Adw.ActionRow`, `Adw.SwitchRow`, `Adw.ComboRow`, `Adw.ExpanderRow`) defaults to `use_markup = true`. Unescaped ampersands in `src/Window.vala` (`"R & Shiny"`), `src/bridges/yavanna/BioEntityPopover.vala` (`"Organism & Taxon"`), `src/ui/ToolchainSetupDialog.vala` (`"R Tidyverse & RMarkdown Bundle"`), and `src/ui/MathChemEditorDialog.vala` caused runtime Pango entity parser warnings (`Gtk-WARNING: Failed to set text ...`).
   - **GNOME HIG Standard**: Replace `"&"` / `"&amp;"` in all UI headers, group titles, and row titles with `"and"` for clean typographic scannability and zero Pango parser faults.
3. **HeaderBar Brand & StatusBar Badge Clutter**:
   - `Window.vala` appended a manual Unicode triangle (`"Imladris ▾"`) to `Adw.ButtonContent`, visually clashing with native Libadwaita menu button conventions.
   - Status bar badges (`[Sandboxed - Reproducible]` and `[System Libraries - Non-Portable]`) wrapped text in redundant ASCII square brackets `[...]` inside an already pill-bordered `.status-badge` widget. Replaced with clean HIG pills: `"Sandboxed • Reproducible"` and `"System Environment"`.

### 1.2 Iconography & GResource Completeness Audit
An automated audit of all 100 icon names referenced across `src/**/*.vala` against standard `Adwaita` and `data/icons` revealed **9 missing symbolic icons** that previously rendered as "missing image" placeholders on vanilla GNOME desktops and inside Flatpak/AppImage sandboxes:
- `book-open-symbolic` (Insert Ribbon — Zotero Citation)
- `character-map-symbolic` (Insert Ribbon — Special Characters)
- `emblem-ok-symbolic` (ThemeSelectorWidget & WelcomeView checkmark badge)
- `format-text-superscript-symbolic` (Insert Ribbon — Footnote)
- `send-symbolic` (Elrond AI Chat Panel send button)
- `software-properties-symbolic` (Preferences Dialog)
- `text-html-symbolic` (WelcomeView & NewProjectDialog)
- `view-column-symbolic` (View Ribbon — Left Tall / Vertical Split)
- `view-statistics-symbolic` (HeaderBar — Elbereth Clinical Biostatistics Studio)

**Resolution**: All 9 crisp 16×16 GNOME-compliant `currentColor` symbolic SVGs have been authored in `data/icons/papirus/scalable/actions/` and registered in `data/imladris.gresource.xml`.

### 1.3 Dynamic Theming & GNOME Accent Color Synchronization
- **Hardcoded Hex Colors in `data/style.css`**: Rules for `.ribbon-tab-packages:checked`, `.citation-pill`, and `.accent-btn` hardcoded Adwaita Blue (`#3584e4`), ignoring the user's selected GNOME Accent Color (`@accent_color` / `@accent_bg_color`).
- **GtkSourceView 5 Scheme Synchronization**: `DocumentPage.update_style_scheme ()` dynamically switches between `Adwaita` (Light), `Adwaita-dark` (Dark), and `solarized-light` (Eye-Friendly Sepia) whenever `SettingsManager.theme_changed` or `Adw.StyleManager.dark` changes.

### 1.4 OpenGL / Vulkan GSK Hardware Acceleration Pipeline
- **GTK4 Scene Kit (`GSK_RENDERER`) Bootstrap**:
  - Previously, `hardware_acceleration_enabled` only toggled `WebKit.Settings.hardware_acceleration_policy`, leaving the main GTK4 window and `GtkSourceView` 5 text editor canvas unconfigured at startup.
  - In `src/main.vala`, Imladris now reads `~/.config/imladris/settings.ini` (`[Hardware]`) **before** `Gdk.Display` initialization and configures `GSK_RENDERER`:
    - **Auto / OpenGL (`GpuRendererBackend.AUTO_GPU` / `OPENGL`)**: Sets `GSK_RENDERER=ngl` (GTK 4.14+ unified GLSL glyph-atlas renderer) or `gl` (GTK 4.6–4.12), accelerating all text scrolling, line numbers, gutter diagnostics, and paned splits on the GPU.
    - **Vulkan (`GpuRendererBackend.VULKAN`)**: Sets `GSK_RENDERER=vulkan` for explicit SPIR-V command buffer submission.
    - **Software Fallback (`GpuRendererBackend.SOFTWARE_CAIRO` or Toggle OFF)**: Sets `GSK_RENDERER=cairo` and `WEBKIT_DISABLE_DMABUF_RENDERER=1` for deterministic CPU rendering on headless/VM setups.

### 1.5 Alacritty & PuTTY Terminal / Editor Physics
To achieve the unmistakable responsiveness of **Alacritty** and **PuTTY**:
- **Three Coherent Physics Profiles (`AnimationPhysicsMode`)**:
  1. **`ALACRITTY_CRISP` (65ms Zero-Lag Micro-Transitions — Default)**: Replaces sluggish 150–250ms transitions with crisp `65ms cubic-bezier(0.2, 0.0, 0.0, 1.0)` transitions, contextual monospace font ligatures, `tabular-nums`, and 50ms stack crossfades.
  2. **`PUTTY_INSTANT` (0ms Zero-Latency Snap)**: Forces `transition-duration: 0ms`, `animation-duration: 0ms`, `gtk-enable-animations = false`, and `0ms` on all `Gtk.Revealer` and `Gtk.Stack` widgets for instant frame changes.
  3. **`ADWAITA_SMOOTH` (180ms Standard GNOME Easing)**: Standard Libadwaita motion curve.
- **Steady Terminal Cursor (`steady_cursor`)**: Synchronizes `Gtk.Settings.gtk_cursor_blink = !steady_cursor` across the code editor (`source_view`), REPL (`console_view`), and terminal (`terminal_view`) so the caret remains rock-solid during intensive coding sessions.

---

## 2. Creative Scientific GUI Optimizations (Next-Phase Enhancements for Gemini 3.8-Flash-High/Medium)

Below are four high-impact, creative Scientific GUI enhancements designed specifically for **Gemini 3.8-Flash-High/Medium** to implement in the next iteration:

### Optimization A: Command Palette & Scientific Omni-Search (`Ctrl+Shift+P` / `Ctrl+K`)
Researchers switching between VS Code, RStudio, and Posit Workbench rely heavily on a keyboard-driven Command Palette.
- **Design**: An `Adw.Dialog` with a floating `Gtk.SearchEntry` and a fuzzy-filtered `Gtk.ListView` that searches across:
  1. All 45+ `GAction` workbench commands (Render HTML/PDF, Run Chunk, Snapshot `renv`, Open Elbereth Power Calculator, Open Yavanna Oligo Inspector).
  2. Active R/Python DataFrames and Environment Symbols (`EnvironmentController`).
  3. Open document headings (`#`, `##`, `###`) and code chunks (`{r}`, `{python}`).

### Optimization B: Inline Execution HUD & Chunk Timing Pill in Gutter
- **Design**: When a user executes an `{r}` or `{python}` chunk via `Ctrl+Enter`, render a subtle, Alacritty-crisp monospace pill in the `InlineChunkOutputWidget` header displaying:
  - Execution status icon (`✔` green / `✖` red / `⏳` running)
  - Wall-clock duration in tabular milliseconds (e.g., `142 ms` or `1.84 s`)
  - Peak R/Python memory delta (`+12.4 MB`)

### Optimization C: High-Contrast Data Science Syntax Overlay ("Alacritty Dark" & "Posit Light")
- **Design**: Bundle two custom `GtkSourceView` 5 XML style schemes inside `data/styles/` (`imladris-alacritty-dark.xml` and `imladris-posit-light.xml`) tuned specifically for polyglot `.qmd` / `.Rmd` files:
  - Distinct background tinting for fenced `{r}` and `{python}` code blocks vs. Markdown prose.
  - High-contrast semantic coloring for statistical operators (`<-`, `|>`, `%>%`, `~`, `$`) and LaTeX math blocks (`$$...$$`).

### Optimization D: Zen Academic Reading & Split-Scroll Synchronization
- **Design**: Synchronize vertical scroll fraction (`Gtk.Adjustment.value / (upper - page_size)`) between `editor_scroller` (`GtkSource.View`) and `web_view` (`WebKit.WebView`) using a zero-jitter 60Hz/120Hz frame-clock tick callback (`widget.add_tick_callback`) when in side-by-side Split Mode.

---

## 3. Step-by-Step Implementation Plan for Gemini 3.8-Flash-High/Medium

### Task 1: Verify & Maintain Hardware Acceleration Bootstrap (`src/main.vala`)
Ensure `src/main.vala` reads `[Hardware]` from `~/.config/imladris/settings.ini` prior to `GtkSource.init ()`:
```vala
// Configure GTK4 GSK Hardware Acceleration (OpenGL / Vulkan / Cairo) before Display init
if (GLib.Environment.get_variable ("GSK_RENDERER") == null) {
    bool hw_accel = true;
    int gpu_backend = 0; // 0 = Auto (OpenGL NGL), 1 = OpenGL, 2 = Vulkan, 3 = Cairo Software

    string ini_path = GLib.Path.build_filename (
        GLib.Environment.get_user_config_dir (), "imladris", "settings.ini"
    );
    if (GLib.FileUtils.test (ini_path, GLib.FileTest.EXISTS)) {
        try {
            var kf = new GLib.KeyFile ();
            kf.load_from_file (ini_path, GLib.KeyFileFlags.NONE);
            if (kf.has_key ("Hardware", "hw_acceleration")) {
                hw_accel = kf.get_boolean ("Hardware", "hw_acceleration");
            }
            if (kf.has_key ("Hardware", "gpu_backend")) {
                gpu_backend = kf.get_integer ("Hardware", "gpu_backend");
            }
        } catch (GLib.Error e) {}
    }

    if (!hw_accel || gpu_backend == 3) {
        GLib.Environment.set_variable ("GSK_RENDERER", "cairo", true);
        GLib.Environment.set_variable ("WEBKIT_DISABLE_DMABUF_RENDERER", "1", true);
    } else if (gpu_backend == 2) {
        GLib.Environment.set_variable ("GSK_RENDERER", "vulkan", true);
    } else {
        string gl_renderer = (Gtk.get_minor_version () >= 14) ? "ngl" : "gl";
        GLib.Environment.set_variable ("GSK_RENDERER", gl_renderer, true);
    }
}
```

### Task 2: Implement Universal Command Palette (`src/ui/CommandPaletteDialog.vala`)
Create `src/ui/CommandPaletteDialog.vala` and bind it to `<Control><Shift>p` and `<Control>k` in `src/Application.vala`:
1. Inherit from `Adw.Dialog` (`content_width = 560`, `content_height = 420`).
2. Add a top `Gtk.SearchEntry` (`placeholder_text = "Type a command, statistical test, R/Python symbol, or section..."`).
3. Populate a `Gtk.ListBox` with `Adw.ActionRow` items representing:
   - Document & Execution actions (`win.run_chunk`, `win.run_all`, `app.export_html`, `app.export_pdf`, `app.export_mallorn`).
   - Scientific Bridges (`Elbereth Clinical Biostatistics`, `Yavanna Bio-Entity Inspector`, `Taniquetil AlphaFold Bridge`, `Math and Chemical Reaction Studio`).
   - Hardware & Physics toggles (`Switch to Alacritty Crisp Physics`, `Switch to PuTTY Instant Physics`, `Toggle Hardware Acceleration`).
4. Activate the selected action on `Enter` and close the dialog in `0ms` (PuTTY) or `65ms` (Alacritty).

### Task 3: Add Execution Duration Telemetry to `InlineChunkOutputWidget` (`src/ui/InlineChunkOutputWidget.vala`)
1. Record `int64 start_us = GLib.get_monotonic_time ();` before dispatching R/Python chunk execution in `PersistentPanelRegistry.vala`.
2. Compute `double elapsed_ms = (GLib.get_monotonic_time () - start_us) / 1000.0;`.
3. Display the formatted badge (`"✔ %.0f ms".printf (elapsed_ms)`) in the right header of `InlineChunkOutputWidget` with `.numeric` (`font-variant-numeric: tabular-nums`).

### Task 4: Verification & Test Matrix
Run the Meson build and test suite after any UI/UX modification:
```bash
ninja -C build
meson test -C build --print-errorlogs
```
All 7 test suites (`test-dcf-parser`, `test-chunk-parser`, `test-notebook-serializer`, `test-scientific-adapters`, `test-citation-engine`, `test-r-environment-scanner`, `test-code-intellisense`) must pass with 0 warnings and 0 Pango markup errors.
