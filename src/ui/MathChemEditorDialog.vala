// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Interactive dialog for natural mathematical expression and chemical reaction authoring.
 *
 * This module provides a Libadwaita studio dialog where users write mathematical
 * formulas or chemical equations in natural notation, inspect a live offline visual
 * preview, and insert or save the result in LaTeX or Markdown format.
 */
namespace Imladris.UI {

    /**
     * Studio dialog that converts natural math and chemistry input into LaTeX or Markdown.
     */
    public class MathChemEditorDialog : Adw.Dialog {

        /**
         * Emitted when the user requests to insert the generated formula into the active document.
         *
         * @param formatted_output The converted LaTeX or Markdown text.
         * @param save_document    True if the active document must be saved immediately after insertion.
         */
        public signal void formula_inserted (string formatted_output, bool save_document);

        private Adw.ToastOverlay toast_overlay;
        private Adw.ComboRow mode_row;
        private Adw.ComboRow format_row;
        private Adw.ComboRow preset_row;
        private Gtk.Label detected_badge_label;
        private Gtk.TextView natural_input_view;
        private Gtk.TextView output_code_view;
        private WebKit.WebView preview_web_view;
        private Gee.ArrayList<Core.FormulaPreset> presets;
        private bool updating_programmatically = false;

        /**
         * Constructs a new Math & Chemical Reaction Studio dialog.
         *
         * @param initial_mode  The initial parsing mode (AUTO, MATH, or CHEMISTRY).
         * @param initial_input Optional initial natural formula text (for example, from editor selection).
         */
        public MathChemEditorDialog (Core.FormulaMode initial_mode = Core.FormulaMode.AUTO, string? initial_input = null) {
            Object (
                title: "Math & Chemical Reaction Studio",
                content_width: 820,
                content_height: 720
            );

            this.presets = Core.MathChemEngine.get_presets ();
            build_ui (initial_mode, initial_input);
        }

        private void build_ui (Core.FormulaMode initial_mode, string? initial_input) {
            toast_overlay = new Adw.ToastOverlay ();

            var toolbar_view = new Adw.ToolbarView ();
            var header_bar = new Adw.HeaderBar ();

            detected_badge_label = new Gtk.Label ("Auto: Math") {
                css_classes = { "caption", "pill" },
                margin_start = 6,
                margin_end = 6
            };
            header_bar.pack_start (detected_badge_label);

            var btn_copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                tooltip_text = "Copy Converted Output to Clipboard"
            };
            btn_copy.clicked.connect (on_copy_clicked);
            header_bar.pack_end (btn_copy);

            toolbar_view.add_top_bar (header_bar);

            var main_scroll = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vexpand = true,
                hexpand = true
            };

            var clamp = new Adw.Clamp () {
                maximum_size = 780,
                margin_top = 12,
                margin_bottom = 12,
                margin_start = 16,
                margin_end = 16
            };

            var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);

            // 1. Mode, Output Format, and Preset Configuration Group
            var config_group = new Adw.PreferencesGroup () {
                title = "Notation Mode and Output Format",
                description = "Write formulas naturally (e.g. (-b +- sqrt(b^2 - 4*a*c))/(2*a) or 2H2(g) + O2(g) ->[heat] 2H2O(l)) and export to LaTeX or Markdown."
            };

            var mode_model = new Gtk.StringList ({
                "Auto-Detect (Math or Chemistry)",
                "Mathematics (Algebra, Calculus, Matrices)",
                "Chemistry (Formulas, Ions, Reactions & States)"
            });
            mode_row = new Adw.ComboRow () {
                title = "Input Mode",
                subtitle = "Automatically detects chemical equations vs. mathematical expressions",
                model = mode_model
            };
            switch (initial_mode) {
                case Core.FormulaMode.MATH:
                    mode_row.selected = 1;
                    break;
                case Core.FormulaMode.CHEMISTRY:
                    mode_row.selected = 2;
                    break;
                default:
                    mode_row.selected = 0;
                    break;
            }
            mode_row.notify["selected"].connect (() => {
                if (mode_row.selected == 2 && format_row.selected == 0) {
                    format_row.selected = 2; // Default to \ce{...} when switching explicitly to Chemistry
                }
                refresh_conversion ();
            });
            config_group.add (mode_row);

            var format_model = new Gtk.StringList ({
                "LaTeX Display Block ($$ ... $$)",
                "LaTeX Inline ($ ... $)",
                "LaTeX Chemistry ($$\\ce{ ... }$$)",
                "LaTeX Numbered Equation (\\begin{equation})",
                "Markdown Sub/Superscript (~sub~ / ^sup^)",
                "Markdown Unicode Scientific (H₂O / SO₄²⁻ / x²)"
            });
            format_row = new Adw.ComboRow () {
                title = "Target Format",
                subtitle = "Format written into your document when inserting or saving",
                model = format_model,
                selected = (initial_mode == Core.FormulaMode.CHEMISTRY) ? 2 : 0
            };
            format_row.notify["selected"].connect (() => {
                refresh_conversion ();
            });
            config_group.add (format_row);

            var preset_strings = new Gtk.StringList (null);
            preset_strings.append ("— Load a Scientific Preset Template —");
            foreach (var p in presets) {
                string prefix = (p.mode == Core.FormulaMode.CHEMISTRY) ? "[Chemistry] " : "[Math] ";
                preset_strings.append (prefix + p.title + " — " + p.description);
            }
            preset_row = new Adw.ComboRow () {
                title = "Example Presets",
                subtitle = "Load a ready-made equation or reaction to inspect or customize",
                model = preset_strings,
                selected = 0
            };
            preset_row.notify["selected"].connect (on_preset_selected);
            config_group.add (preset_row);

            content_box.append (config_group);

            // 2. Quick-Insert Palettes (Math Structures, Chemistry Reactions, Greek & Symbols)
            var palette_group = new Adw.PreferencesGroup () {
                title = "Quick-Insert Scientific Palette",
                description = "Click any button to insert natural notation at the cursor"
            };

            var math_expander = new Adw.ExpanderRow () {
                title = "Mathematical Structures (Fractions, Integrals, Sums, Matrices)",
                subtitle = "frac(a,b), sqrt(x), int(0, inf), sum(i=1, n), lim(x -> 0), matrix(...)",
                expanded = (initial_mode != Core.FormulaMode.CHEMISTRY)
            };
            math_expander.add_row (build_math_palette_row ());
            palette_group.add (math_expander);

            var chem_expander = new Adw.ExpanderRow () {
                title = "Chemical Reactions, Arrows, States, and Ions",
                subtitle = "->, <=>, ->[heat], (aq), (s), (g), (l), ^2+, ^2-, (v), (^)",
                expanded = (initial_mode == Core.FormulaMode.CHEMISTRY)
            };
            chem_expander.add_row (build_chem_palette_row ());
            palette_group.add (chem_expander);

            var sym_expander = new Adw.ExpanderRow () {
                title = "Greek Letters and Scientific Operators",
                subtitle = "alpha, beta, gamma, delta, theta, lambda, pi, sigma, omega, +-, <=, >=, !=",
                expanded = false
            };
            sym_expander.add_row (build_symbols_palette_row ());
            palette_group.add (sym_expander);

            content_box.append (palette_group);

            // 3. Natural Input Editor Box
            var input_header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var input_title = new Gtk.Label ("<b>Natural Formula / Reaction Input</b>") {
                use_markup = true,
                xalign = 0,
                hexpand = true
            };
            var btn_clear = new Gtk.Button.with_label ("Clear") {
                css_classes = { "flat", "caption" }
            };
            btn_clear.clicked.connect (() => {
                natural_input_view.buffer.text = "";
                natural_input_view.grab_focus ();
            });
            input_header_box.append (input_title);
            input_header_box.append (btn_clear);
            content_box.append (input_header_box);

            natural_input_view = new Gtk.TextView () {
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                monospace = true,
                top_margin = 10,
                bottom_margin = 10,
                left_margin = 12,
                right_margin = 12,
                accepts_tab = false
            };
            var input_scroll = new Gtk.ScrolledWindow () {
                min_content_height = 80,
                max_content_height = 120,
                child = natural_input_view,
                css_classes = { "card" }
            };
            content_box.append (input_scroll);

            // 4. Live Rendered Visual Preview (Offline WebKit View)
            var preview_label = new Gtk.Label ("<b>Live Rendered Preview (Offline Typesetting)</b>") {
                use_markup = true,
                xalign = 0
            };
            content_box.append (preview_label);

            preview_web_view = UI.WebViewFactory.create ();
            preview_web_view.set_size_request (-1, 120);
            var preview_frame = new Gtk.Frame (null) {
                child = preview_web_view,
                css_classes = { "card" }
            };
            content_box.append (preview_frame);

            // 5. Generated LaTeX / Markdown Code (Editable before saving/inserting)
            var output_header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var output_title = new Gtk.Label ("<b>Generated LaTeX / Markdown Output</b> (Editable)") {
                use_markup = true,
                xalign = 0,
                hexpand = true
            };
            output_header_box.append (output_title);
            content_box.append (output_header_box);

            output_code_view = new Gtk.TextView () {
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                monospace = true,
                top_margin = 10,
                bottom_margin = 10,
                left_margin = 12,
                right_margin = 12,
                accepts_tab = false
            };
            var output_scroll = new Gtk.ScrolledWindow () {
                min_content_height = 80,
                max_content_height = 120,
                child = output_code_view,
                css_classes = { "card" }
            };
            content_box.append (output_scroll);

            clamp.child = content_box;
            main_scroll.child = clamp;
            toolbar_view.content = main_scroll;

            // 6. Bottom Action Bar (Cancel, Copy, Insert at Cursor, Insert & Save File)
            var bottom_bar = new Gtk.ActionBar ();

            var btn_cancel = new Gtk.Button.with_label ("Cancel");
            btn_cancel.clicked.connect (() => {
                this.close ();
            });
            bottom_bar.pack_start (btn_cancel);

            var btn_insert_save = new Gtk.Button.with_label ("Insert & Save to File") {
                css_classes = { "suggested-action" },
                tooltip_text = "Insert the formatted LaTeX or Markdown at the cursor and save the document immediately"
            };
            btn_insert_save.clicked.connect (() => {
                emit_insertion (true);
            });
            bottom_bar.pack_end (btn_insert_save);

            var btn_insert_only = new Gtk.Button.with_label ("Insert at Cursor") {
                tooltip_text = "Insert the formatted LaTeX or Markdown at the cursor in the active document"
            };
            btn_insert_only.clicked.connect (() => {
                emit_insertion (false);
            });
            bottom_bar.pack_end (btn_insert_only);

            toolbar_view.add_bottom_bar (bottom_bar);
            toast_overlay.child = toolbar_view;
            this.child = toast_overlay;

            // Connect buffer changes
            natural_input_view.buffer.changed.connect (() => {
                if (!updating_programmatically) {
                    refresh_conversion ();
                }
            });

            output_code_view.buffer.changed.connect (() => {
                if (!updating_programmatically) {
                    update_visual_preview_from_output ();
                }
            });

            // Initialize default text
            updating_programmatically = true;
            if (initial_input != null && initial_input.strip ().length > 0) {
                natural_input_view.buffer.text = initial_input.strip ();
            } else if (initial_mode == Core.FormulaMode.CHEMISTRY) {
                natural_input_view.buffer.text = "6CO2(g) + 6H2O(l) ->[h*nu][chlorophyll] C6H12O6(aq) + 6O2(g)";
            } else {
                natural_input_view.buffer.text = "(-b +- sqrt(b^2 - 4*a*c)) / (2*a)";
            }
            updating_programmatically = false;

            refresh_conversion ();
        }

        private Gtk.Widget build_math_palette_row () {
            var flow = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                max_children_per_line = 8,
                min_children_per_line = 4,
                column_spacing = 6,
                row_spacing = 6,
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8
            };

            add_palette_button (flow, "a / b", "frac(a, b)", "Fraction");
            add_palette_button (flow, "√x", "sqrt(x)", "Square root");
            add_palette_button (flow, "ⁿ√x", "root(n, x)", "Nth root");
            add_palette_button (flow, "xⁿ", "^(n)", "Superscript / Power");
            add_palette_button (flow, "xᵢ", "_(i)", "Subscript / Index");
            add_palette_button (flow, "∫ f(x) dx", "int(0, inf) f(x) dx", "Definite integral");
            add_palette_button (flow, "∑ xᵢ", "sum(i=1, n) x_i", "Summation");
            add_palette_button (flow, "∏ xᵢ", "prod(i=1, n) x_i", "Product");
            add_palette_button (flow, "lim", "lim(x -> 0) ", "Limit");
            add_palette_button (flow, "d/dx", "d/dx ", "Derivative");
            add_palette_button (flow, "∂/∂x", "partial/partial x ", "Partial derivative");
            add_palette_button (flow, "Matrix 2×2", "matrix([a, b], [c, d])", "2x2 Matrix");
            add_palette_button (flow, "(n k)", "binom(n, k)", "Binomial coefficient");
            add_palette_button (flow, "v⃗", "vec(v)", "Vector arrow");
            add_palette_button (flow, "x̄", "bar(x)", "Mean / Overbar");
            add_palette_button (flow, "ŷ", "hat(y)", "Estimator / Hat");

            return flow;
        }

        private Gtk.Widget build_chem_palette_row () {
            var flow = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                max_children_per_line = 8,
                min_children_per_line = 4,
                column_spacing = 6,
                row_spacing = 6,
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8
            };

            add_palette_button (flow, "→ Yield", " -> ", "Forward reaction arrow");
            add_palette_button (flow, "⇌ Equilibrium", " <=> ", "Reversible equilibrium arrow");
            add_palette_button (flow, "↔ Resonance", " <-> ", "Resonance double-headed arrow");
            add_palette_button (flow, "→[Δ]", " ->[heat] ", "Reaction with heat");
            add_palette_button (flow, "→[hν]", " ->[h*nu] ", "Photochemical reaction");
            add_palette_button (flow, "→[cat][T]", " ->[Pt][400 C] ", "Catalyst and condition arrow");
            add_palette_button (flow, "(aq)", "(aq)", "Aqueous phase");
            add_palette_button (flow, "(s)", "(s)", "Solid phase");
            add_palette_button (flow, "(l)", "(l)", "Liquid phase");
            add_palette_button (flow, "(g)", "(g)", "Gas phase");
            add_palette_button (flow, "↓ Precipitate", "(v)", "Precipitate arrow");
            add_palette_button (flow, "↑ Gas Evolved", "(^)", "Gas evolution arrow");
            add_palette_button (flow, "⁺ Cation", "^+", "1+ positive charge");
            add_palette_button (flow, "⁻ Anion", "^-", "1- negative charge");
            add_palette_button (flow, "²⁺ Ion", "^2+", "2+ positive charge");
            add_palette_button (flow, "²⁻ Ion", "^2-", "2- negative charge");
            add_palette_button (flow, "· Hydrate", " * ", "Hydrate dot (e.g. CuSO4 * 5H2O)");

            return flow;
        }

        private Gtk.Widget build_symbols_palette_row () {
            var flow = new Gtk.FlowBox () {
                selection_mode = Gtk.SelectionMode.NONE,
                max_children_per_line = 10,
                min_children_per_line = 5,
                column_spacing = 6,
                row_spacing = 6,
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8
            };

            add_palette_button (flow, "α", "alpha", "Greek alpha");
            add_palette_button (flow, "β", "beta", "Greek beta");
            add_palette_button (flow, "γ", "gamma", "Greek gamma");
            add_palette_button (flow, "δ", "delta", "Greek delta");
            add_palette_button (flow, "Δ", "Delta", "Capital Delta (change)");
            add_palette_button (flow, "θ", "theta", "Greek theta");
            add_palette_button (flow, "λ", "lambda", "Greek lambda");
            add_palette_button (flow, "μ", "mu", "Greek mu");
            add_palette_button (flow, "π", "pi", "Greek pi");
            add_palette_button (flow, "σ", "sigma", "Greek sigma");
            add_palette_button (flow, "Σ", "Sigma", "Capital Sigma");
            add_palette_button (flow, "ω", "omega", "Greek omega");
            add_palette_button (flow, "Ω", "Omega", "Capital Omega");
            add_palette_button (flow, "±", " +- ", "Plus-minus");
            add_palette_button (flow, "≠", " != ", "Not equal");
            add_palette_button (flow, "≤", " <= ", "Less than or equal");
            add_palette_button (flow, "≥", " >= ", "Greater than or equal");
            add_palette_button (flow, "≈", " ~= ", "Approximately equal");
            add_palette_button (flow, "∞", "inf", "Infinity");
            add_palette_button (flow, "∇", "nabla", "Nabla / Gradient");

            return flow;
        }

        private void add_palette_button (Gtk.FlowBox flow, string label, string snippet, string tooltip) {
            var btn = new Gtk.Button.with_label (label) {
                tooltip_text = "%s (%s)".printf (tooltip, snippet),
                css_classes = { "flat" }
            };
            btn.clicked.connect (() => {
                insert_snippet_into_natural_input (snippet);
            });
            flow.append (btn);
        }

        private void insert_snippet_into_natural_input (string snippet) {
            var buf = natural_input_view.buffer;
            buf.begin_user_action ();
            buf.insert_at_cursor (snippet, snippet.length);
            buf.end_user_action ();
            natural_input_view.grab_focus ();
        }

        private void on_preset_selected () {
            uint idx = preset_row.selected;
            if (idx == 0 || idx > presets.size) {
                return;
            }
            var preset = presets.get ((int) idx - 1);
            updating_programmatically = true;
            natural_input_view.buffer.text = preset.natural_input;
            if (preset.mode == Core.FormulaMode.CHEMISTRY && format_row.selected == 0) {
                format_row.selected = 2; // Switch to LaTeX Chemistry (\ce) by default for chemistry presets
            } else if (preset.mode == Core.FormulaMode.MATH && format_row.selected == 2) {
                format_row.selected = 0; // Switch to LaTeX Display Block for math presets
            }
            updating_programmatically = false;
            refresh_conversion ();
        }

        private Core.FormulaMode get_selected_mode () {
            switch (mode_row.selected) {
                case 1:
                    return Core.FormulaMode.MATH;
                case 2:
                    return Core.FormulaMode.CHEMISTRY;
                default:
                    return Core.FormulaMode.AUTO;
            }
        }

        private Core.FormulaOutputFormat get_selected_output_format () {
            switch (format_row.selected) {
                case 0:
                    return Core.FormulaOutputFormat.LATEX_DISPLAY;
                case 1:
                    return Core.FormulaOutputFormat.LATEX_INLINE;
                case 2:
                    return Core.FormulaOutputFormat.LATEX_MHCHEM;
                case 3:
                    return Core.FormulaOutputFormat.LATEX_EQUATION;
                case 4:
                    return Core.FormulaOutputFormat.MARKDOWN_SUBSUP;
                case 5:
                    return Core.FormulaOutputFormat.MARKDOWN_UNICODE;
                default:
                    return Core.FormulaOutputFormat.LATEX_DISPLAY;
            }
        }

        private void refresh_conversion () {
            string natural_text = natural_input_view.buffer.text;
            Core.FormulaMode requested_mode = get_selected_mode ();
            Core.FormulaMode effective_mode = (requested_mode == Core.FormulaMode.AUTO)
                ? Core.MathChemEngine.detect_mode (natural_text)
                : requested_mode;

            if (requested_mode == Core.FormulaMode.AUTO) {
                detected_badge_label.label = (effective_mode == Core.FormulaMode.CHEMISTRY)
                    ? "Auto-Detected: Chemistry"
                    : "Auto-Detected: Mathematics";
            } else {
                detected_badge_label.label = (effective_mode == Core.FormulaMode.CHEMISTRY)
                    ? "Mode: Chemistry"
                    : "Mode: Mathematics";
            }

            Core.FormulaOutputFormat fmt = get_selected_output_format ();
            string converted = Core.MathChemEngine.convert (natural_text, requested_mode, fmt);

            updating_programmatically = true;
            output_code_view.buffer.text = converted;
            updating_programmatically = false;

            // Render live visual HTML preview from the underlying LaTeX representation
            string preview_latex = (effective_mode == Core.FormulaMode.CHEMISTRY)
                ? Core.MathChemEngine.natural_chem_to_latex (natural_text)
                : Core.MathChemEngine.natural_math_to_latex (natural_text);
            load_preview_html (Core.MathChemEngine.render_latex_to_html (preview_latex, true));
        }

        private void update_visual_preview_from_output () {
            string raw_out = output_code_view.buffer.text.strip ();
            string inner = raw_out;
            if (inner.has_prefix ("$$") && inner.has_suffix ("$$") && inner.length >= 4) {
                inner = inner.substring (2, inner.length - 4).strip ();
            } else if (inner.has_prefix ("$") && inner.has_suffix ("$") && inner.length >= 2) {
                inner = inner.substring (1, inner.length - 2).strip ();
            }
            load_preview_html (Core.MathChemEngine.render_latex_to_html (inner, true));
        }

        private void load_preview_html (string body_markup) {
            bool is_dark = Adw.StyleManager.get_default ().dark;
            string bg_color = is_dark ? "#1e1e2e" : "#ffffff";
            string fg_color = is_dark ? "#cdd6f4" : "#1e293b";

            string html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {
    margin: 0;
    padding: 14px 18px;
    background-color: %s;
    color: %s;
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 76px;
    font-family: 'STIX Two Math', 'Cambria Math', 'Latin Modern Math', serif;
  }
  %s
</style>
</head>
<body>
  %s
</body>
</html>""".printf (bg_color, fg_color, Core.MathChemEngine.get_math_chem_css (), body_markup);

            preview_web_view.load_html (html, "file:///");
        }

        private void on_copy_clicked () {
            string text = output_code_view.buffer.text;
            var display = Gdk.Display.get_default ();
            if (display != null) {
                display.get_clipboard ().set_text (text);
                toast_overlay.add_toast (new Adw.Toast ("Copied formula to clipboard"));
            }
        }

        private void emit_insertion (bool save_document) {
            string output_text = output_code_view.buffer.text;
            if (output_text.strip ().length == 0) {
                toast_overlay.add_toast (new Adw.Toast ("Enter a formula or reaction first"));
                return;
            }
            formula_inserted (output_text, save_document);
            this.close ();
        }
    }
}
