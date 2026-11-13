// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Scientific presentations and symposium poster scaffolding dialog.
 * Architecture: Modal dialog providing preset templates for RevealJS, Beamer PDF, and Typst posters.
 * Concurrency: Executes on the GLib MainContext thread.
 */

using GLib;
using Gtk;

namespace Imladris.UI {

    public class PresentationTemplateDialog : Adw.Dialog {

        public signal void template_selected (string template_title, string starter_content, string suggested_filename);

        public PresentationTemplateDialog () {
            this.title = "New Scientific Deck or Poster";
            this.content_width = 540;
            this.content_height = 460;

            setup_ui ();
        }

        private void setup_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header_bar = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header_bar);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 12,
                margin_bottom = 16,
                margin_start = 16,
                margin_end = 16
            };

            var desc_lbl = new Gtk.Label ("Select a scientific presentation format. Quarto renders decks and posters directly into Quadrant 4.") {
                wrap = true,
                xalign = 0.0f,
                css_classes = { "dim-label" }
            };
            box.append (desc_lbl);

            var list_box = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE
            };
            list_box.add_css_class ("boxed-list");

            // Preset 1: RevealJS Interactive Slides
            var row_reveal = new Adw.ActionRow () {
                title = "Interactive Conference Deck (RevealJS)",
                subtitle = "HTML5 presentation rendered in WebKitGTK 6.0 with KaTeX math, dark theme, and slide navigation",
                activatable = true
            };
            row_reveal.add_prefix (new Gtk.Image.from_icon_name ("applications-internet-symbolic") { pixel_size = 24 });
            row_reveal.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            row_reveal.activated.connect (() => {
                string content = get_revealjs_template ();
                template_selected ("Lab Presentation (RevealJS)", content, "presentation.qmd");
                this.close ();
            });
            list_box.append (row_reveal);

            // Preset 2: Beamer PDF Slides
            var row_beamer = new Adw.ActionRow () {
                title = "Academic Conference Slides (Beamer PDF)",
                subtitle = "LaTeX PDF deck with 16:9 aspect ratio, professional math fonts, and self-healing TinyTeX support",
                activatable = true
            };
            row_beamer.add_prefix (new Gtk.Image.from_icon_name ("x-office-presentation-symbolic") { pixel_size = 24 });
            row_beamer.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            row_beamer.activated.connect (() => {
                string content = get_beamer_template ();
                template_selected ("Conference Slides (Beamer)", content, "slides.qmd");
                this.close ();
            });
            list_box.append (row_beamer);

            // Preset 3: Typst Scientific Symposium Poster
            var row_poster = new Adw.ActionRow () {
                title = "Symposium Conference Poster (Typst / PDF)",
                subtitle = "3-column academic conference poster layout with volcano plots, wet-lab methods, and references",
                activatable = true
            };
            row_poster.add_prefix (new Gtk.Image.from_icon_name ("x-office-document-symbolic") { pixel_size = 24 });
            row_poster.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            row_poster.activated.connect (() => {
                string content = get_poster_template ();
                template_selected ("Symposium Poster (Typst)", content, "poster.qmd");
                this.close ();
            });
            list_box.append (row_poster);

            box.append (list_box);
            toolbar_view.set_content (box);
            this.set_child (toolbar_view);
        }

        private string get_revealjs_template () {
            return """---
title: "Genomic and Biostatistical Investigation"
subtitle: "Reproducible Workflow via Imladris and Arekyer"
author: "Researcher Name"
format:
  revealjs:
    theme: [dark, default]
    transition: slide
    slide-number: true
    chalkboard: false
    embed-resources: true
    html-math-method: katex
---

## 1. Experimental Hypothesis and Stoichiometry

Scientific reaction modeling with natural chemical syntax:

$$\ce{E + S <=>[$k_1$][$k_{-1}$] ES ->[$k_{\text{cat}}$] E + P}$$

- Substrate concentration dynamics
- Enzyme saturation threshold
- Michaelis-Menten kinetic verification

---

## 2. Upstream Galaxy Provenance (Arekyer)

```{r}
#| echo: true
#| fig-cap: "Differential Gene Expression Volcano Plot"
library(ggplot2)
df <- data.frame(
  log2FC = rnorm(100, mean = 0, sd = 1.5),
  padj = runif(100, min = 0.0001, max = 0.05)
)
ggplot(df, aes(x = log2FC, y = -log10(padj))) +
  geom_point(color = "#3584e4", alpha = 0.8) +
  theme_minimal() +
  labs(title = "RNA-Seq Expression Delta", x = "log2 Fold Change", y = "-log10 Adjusted P-Value")
```

---

## 3. Conclusions and Perspectives

1. High statistical power achieved across primary cohorts.
2. Verified cryptographic GxP SHA-256 provenance manifest generated.
3. Live interactive deck export completed via Imladris.
""";
        }

        private string get_beamer_template () {
            return """---
title: "Title of Scientific Presentation"
subtitle: "Conference Proceedings and Statistical Evaluation"
author: "Author Name"
institute: "Department of Computational Biology"
date: "\\today"
format:
  beamer:
    aspectratio: 169
    theme: Madrid
    colortheme: whale
    fonttheme: professionalfonts
---

## Introduction and Study Rationale

- Study Cohort: $N = 450$ randomized subjects.
- Primary Endpoint: Progression-Free Survival (PFS) hazard ratio $< 0.70$.
- Regulatory Standard: ICH E9 Statistical Principles for Clinical Trials.

## Statistical Methodology

$$\log\left(\frac{p}{1 - p}\right) = \beta_0 + \beta_1 X_{\text{treatment}} + \gamma Z_{\text{covariates}}$$

```{python}
#| echo: true
import numpy as np
hazard_ratios = np.array([0.62, 0.58, 0.71, 0.65])
print(f"Mean Hazard Ratio: {hazard_ratios.mean():.2f}")
```

## Summary of Findings

- Statistically significant survival benefit observed ($p < 0.001$).
- Full dataset reproducible via isolated lockfile environment.
""";
        }

        private string get_poster_template () {
            return """---
title: "Multi-Omics Profiling of Cellular Signatures"
author: "Author One, Author Two, and Principal Investigator"
institute: "Institute for Advanced Bioinformatics"
format:
  typst:
    papersize: a0
    margin: 2.5cm
---

# Abstract

This symposium poster illustrates the multi-format publishing capabilities of Imladris. Scientific documents compile to high-resolution print PDF with Typst and KaTeX.

# Methods and Data Pipeline

1. **Cell Culture & Perturbation**: Targeted gene knockdown assays.
2. **Sequencing & Galaxy API**: Processed via Galaxy Cloud REST workflows using Arekyer.
3. **Reproducibility**: Environment locked via `micromamba` and `renv`.

# Results

```{r}
#| echo: false
#| fig-width: 8
#| fig-height: 5
summary(mtcars[, 1:4])
```

# References and Acknowledgements

- Funded by European Research Council (ERC) grant.
- Developed with Imladris Scientific Notebook Studio.
""";
        }
    }
}
