// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Single Responsibility: Scientific presentations and symposium poster scaffolding dialog.
 * Architecture: Modal dialog providing open-source preset templates for LaTeX Beamer,
 * Markdown (Marp / RevealJS), TypeScript programmatic decks, and Typst posters.
 * Concurrency: Executes on the GLib MainContext thread.
 */

using GLib;
using Gtk;

namespace Imladris.UI {

    public class PresentationTemplateDialog : Adw.Dialog {

        public signal void template_selected (string template_title, string starter_content, string suggested_filename);

        private delegate string TemplateContentFunc ();

        public PresentationTemplateDialog () {
            this.title = "New Scientific Deck or Poster";
            this.content_width = 620;
            this.content_height = 600;

            setup_ui ();
        }

        private void setup_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header_bar = new Adw.HeaderBar ();
            toolbar_view.add_top_bar (header_bar);

            var scroller = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true,
                hexpand = true
            };

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16) {
                margin_top = 12,
                margin_bottom = 20,
                margin_start = 16,
                margin_end = 16
            };

            var desc_lbl = new Gtk.Label ("Select an open-source presentation template in LaTeX Beamer, Markdown, TypeScript, or Quarto/Typst.") {
                wrap = true,
                xalign = 0.0f,
                css_classes = { "dim-label" }
            };
            box.append (desc_lbl);

            // 1. LaTeX Beamer (.tex)
            var latex_group = new Adw.PreferencesGroup () {
                title = "LaTeX Beamer Presentations (.tex)",
                description = "Compile directly to vector PDF slides with pdflatex, xelatex, or lualatex."
            };
            var latex_list = create_boxed_list ();
            add_template_row (
                latex_list,
                "Metropolis Minimalist Beamer (.tex)",
                "Clean 16:9 open-source Metropolis-style academic deck with progress bar, booktabs, and code listings",
                "x-office-presentation-symbolic",
                "Metropolis Beamer",
                "beamer_metropolis.tex",
                get_beamer_metropolis_tex
            );
            add_template_row (
                latex_list,
                "Thesis Defense & Seminar Beamer (.tex)",
                "Structured 16:9 Madrid/Whale Beamer deck with theorem blocks, two-column figure layout, and references",
                "x-office-presentation-symbolic",
                "Defense Beamer",
                "beamer_defense.tex",
                get_beamer_defense_tex
            );
            add_template_row (
                latex_list,
                "Conference Lightning Talk Beamer (.tex)",
                "5-minute high-contrast Boadilla Beamer deck focused on key equation, benchmark table, and takeaways",
                "x-office-presentation-symbolic",
                "Lightning Talk Beamer",
                "beamer_lightning.tex",
                get_beamer_lightning_tex
            );
            latex_group.add (latex_list);
            box.append (latex_group);

            // 2. Markdown & Quarto (.md / .qmd)
            var md_group = new Adw.PreferencesGroup () {
                title = "Markdown & Quarto Presentations (.md / .qmd)",
                description = "Open-source slide formats for Marp, RevealJS, Beamer PDF, and Typst."
            };
            var md_list = create_boxed_list ();
            add_template_row (
                md_list,
                "Marp Open-Source Markdown Deck (.md)",
                "Standard Marp-compatible Markdown slides with YAML header, pagination, KaTeX math, and code blocks",
                "text-x-generic-symbolic",
                "Marp Markdown Deck",
                "marp_slides.md",
                get_marp_markdown_template
            );
            add_template_row (
                md_list,
                "Academic Lecture Slides (.md)",
                "Clean Markdown lecture deck with learning objectives, derivations, worked examples, and reading list",
                "text-x-generic-symbolic",
                "Lecture Slides (Markdown)",
                "lecture_slides.md",
                get_lecture_markdown_template
            );
            add_template_row (
                md_list,
                "Interactive Conference Deck (RevealJS .qmd)",
                "HTML5 presentation rendered in WebKitGTK 6.0 with KaTeX math, R plots, and slide navigation",
                "applications-internet-symbolic",
                "Lab Presentation (RevealJS)",
                "presentation.qmd",
                get_revealjs_template
            );
            add_template_row (
                md_list,
                "Academic Conference Slides (Quarto Beamer .qmd)",
                "Quarto-to-Beamer 16:9 PDF deck with executable Python/R chunks and professional math fonts",
                "x-office-presentation-symbolic",
                "Conference Slides (Beamer)",
                "slides.qmd",
                get_beamer_template
            );
            add_template_row (
                md_list,
                "Symposium Conference Poster (Typst .qmd)",
                "3-column A0 academic conference poster layout with volcano plots, wet-lab methods, and references",
                "x-office-document-symbolic",
                "Symposium Poster (Typst)",
                "poster.qmd",
                get_poster_template
            );
            md_group.add (md_list);
            box.append (md_group);

            // 3. TypeScript (.ts)
            var ts_group = new Adw.PreferencesGroup () {
                title = "TypeScript Programmatic Presentations (.ts)",
                description = "Type-safe slide generators for Reveal.js and data-driven interactive decks."
            };
            var ts_list = create_boxed_list ();
            add_template_row (
                ts_list,
                "Reveal.js TypeScript Deck Builder (.ts)",
                "Typed SlideSpec deck generator producing standalone HTML5 Reveal.js slides with KaTeX & highlight.js",
                "applications-engineering-symbolic",
                "Reveal.js TS Deck",
                "reveal_deck.ts",
                get_revealjs_ts_template
            );
            add_template_row (
                ts_list,
                "Slidev / Data-Driven Metrics Deck (.ts)",
                "TypeScript presentation script generating Slidev-compatible Markdown slides from typed benchmark data",
                "applications-engineering-symbolic",
                "Slidev TS Deck",
                "slidev_deck.ts",
                get_slidev_ts_template
            );
            ts_group.add (ts_list);
            box.append (ts_group);

            scroller.set_child (box);
            toolbar_view.set_content (scroller);
            this.set_child (toolbar_view);
        }

        private Gtk.ListBox create_boxed_list () {
            var lb = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE
            };
            lb.add_css_class ("boxed-list");
            return lb;
        }

        private void add_template_row (
            Gtk.ListBox list_box,
            string row_title,
            string row_subtitle,
            string icon_name,
            string emit_title,
            string filename,
            TemplateContentFunc content_fn
        ) {
            var row = new Adw.ActionRow () {
                title = GLib.Markup.escape_text (row_title),
                subtitle = GLib.Markup.escape_text (row_subtitle),
                activatable = true
            };
            row.add_prefix (new Gtk.Image.from_icon_name (icon_name) { pixel_size = 24 });
            row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            row.activated.connect (() => {
                string content = content_fn ();
                template_selected (emit_title, content, filename);
                this.close ();
            });
            list_box.append (row);
        }

        private string get_beamer_metropolis_tex () {
            return """% Open-source Metropolis-style Beamer presentation
\documentclass[aspectratio=169,11pt]{beamer}

% Use 'metropolis' if installed (TeX Live full), or clean Madrid fallback
\IfFileExists{beamerthememetropolis.sty}{
  \usetheme{metropolis}
}{
  \usetheme{Madrid}
  \usecolortheme{whale}
}

\usepackage{amsmath,amssymb,booktabs,graphicx}
\usepackage{listings}

\title{Reproducible Scientific Computing}
\subtitle{Open-Source Methods & Quantitative Evaluation}
\author{Researcher Name}
\institute{Department of Computational Sciences}
\date{\today}

\begin{document}

\maketitle

\begin{frame}{Outline}
  \tableofcontents
\end{frame}

\section{Motivation}

\begin{frame}{Research Problem}
  \begin{itemize}
    \item Complex experimental pipelines require end-to-end reproducibility.
    \item Key hypothesis:
      \[
        \mathcal{L}(\theta) = \frac{1}{N}\sum_{i=1}^{N} \ell(f_\theta(x_i), y_i) + \lambda \|\theta\|_2^2
      \]
    \item Evaluated across $n = 3$ independent cohorts.
  \end{itemize}
\end{frame}

\section{Results}

\begin{frame}{Quantitative Comparison}
  \begin{table}
    \centering
    \begin{tabular}{lcc}
      \toprule
      Method & Accuracy (\%) & Runtime (s) \\
      \midrule
      Baseline & 86.2 & 14.5 \\
      Proposed & \textbf{93.8} & \textbf{4.1} \\
      \bottomrule
    \end{tabular}
    \caption{Benchmark results across validation splits.}
  \end{table}
\end{frame}

\section{Conclusion}

\begin{frame}{Key Takeaways}
  \begin{enumerate}
    \item Significant improvement in accuracy ($p < 0.001$).
    \item $3.5\times$ faster execution with deterministic lockfiles.
  \end{enumerate}
\end{frame}

\end{document}
""";
        }

        private string get_beamer_defense_tex () {
            return """% Scientific Thesis Defense & Seminar Beamer Template
\documentclass[aspectratio=169,11pt]{beamer}

\usetheme{Madrid}
\usecolortheme{whale}
\usefonttheme{professionalfonts}

\usepackage{amsmath,amssymb,amsthm,booktabs,graphicx}

\title[Thesis Defense]{Multi-Scale Modeling of Complex Biological Systems}
\author{Candidate Name}
\institute[University]{Faculty of Science · Doctoral Defense}
\date{\today}

\begin{document}

\begin{frame}
  \titlepage
\end{frame}

\begin{frame}{Agenda}
  \tableofcontents
\end{frame}

\section{Introduction \& Objectives}

\begin{frame}{Research Questions}
  \begin{block}{Central Hypothesis}
    Integrating multi-omics priors improves out-of-distribution generalization across patient cohorts.
  \end{block}
  \vspace{0.5em}
  \begin{itemize}
    \item \textbf{Aim 1}: Formulate a tractable variational objective.
    \item \textbf{Aim 2}: Validate on longitudinal clinical datasets.
  \end{itemize}
\end{frame}

\section{Methodology}

\begin{frame}{Two-Column Model Overview}
  \begin{columns}[T]
    \begin{column}{0.48\textwidth}
      \textbf{Theoretical Formulation}
      \begin{equation}
        p(z \mid x) \approx q_\phi(z \mid x)
      \end{equation}
      \begin{itemize}
        \item Prior regularization via KL divergence.
        \item Exact gradient propagation.
      \end{itemize}
    \end{column}
    \begin{column}{0.48\textwidth}
      \textbf{Validation Protocol}
      \begin{itemize}
        \item 5-fold stratified cross-validation.
        \item External holdout cohort ($N = 320$).
        \item Bootstrap 95\% confidence intervals.
      \end{itemize}
    \end{column}
  \end{columns}
\end{frame}

\section{Conclusion}

\begin{frame}{Summary \& Acknowledgments}
  \begin{alertblock}{Main Contribution}
    Open-source software and reproducible benchmarks published under Apache-2.0.
  \end{alertblock}
  \vspace{0.6em}
  Thank you for your attention. Questions?
\end{frame}

\end{document}
""";
        }

        private string get_beamer_lightning_tex () {
            return """% 5-Minute Conference Lightning Talk Beamer Template
\documentclass[aspectratio=169,14pt]{beamer}

\usetheme{Boadilla}
\usecolortheme{beaver}
\setbeamertemplate{navigation symbols}{}

\usepackage{amsmath,booktabs}

\title{Fast \& Reproducible Pipelines in 5 Minutes}
\author{Speaker Name}
\institute{Symposium 2026}
\date{\today}

\begin{document}

\begin{frame}
  \titlepage
\end{frame}

\begin{frame}{1. The Bottleneck}
  \centering
  \Large
  Why do 60\% of published notebooks fail to reproduce?
  \vspace{1em}
  \normalsize
  \begin{itemize}
    \item Implicit global environments and unpinned dependencies.
    \item Manual copy-paste between analysis and manuscript.
  \end{itemize}
\end{frame}

\begin{frame}{2. Core Insight}
  \[
    \text{Reproducibility} = \text{Pinned Environment} + \text{Automated Build}
  \]
  \begin{table}
    \centering
    \begin{tabular}{lc}
      \toprule
      Workflow & Setup Time \\
      \midrule
      Manual & 45 min \\
      Automated & \textbf{90 sec} \\
      \bottomrule
    \end{tabular}
  \end{table}
\end{frame}

\begin{frame}{3. Try It Today}
  \centering
  \Large
  Scan or visit the repository to reproduce all figures in one command.
\end{frame}

\end{document}
""";
        }

        private string get_marp_markdown_template () {
            return """---
marp: true
theme: default
paginate: true
math: katex
header: "Scientific Research Deck"
footer: "Author Name · 2026"
---

# Quantitative Research Presentation
## Open-Source Marp Markdown Deck

**Author Name**
Department of Scientific Computing

---

## 1. Motivation & Context

- Open-source Markdown slides version cleanly in **Git**.
- Supports inline and display math:

$$E = mc^2 \quad \text{and} \quad \hat{\beta} = (X^\top X)^{-1} X^\top y$$

- Exportable to HTML, PDF, and PPTX via Marp CLI or Imladris.

---

## 2. Reproducible Code Snippet

```python
import math

def shannon_entropy(probs: list[float]) -> float:
    return -sum(p * math.log2(p) for p in probs if p > 0)

print(f"Entropy: {shannon_entropy([0.5, 0.25, 0.25]):.3f} bits")
```

---

## 3. Summary Table

| Metric | Baseline | Proposed |
| :--- | :---: | :---: |
| Precision | 0.84 | **0.92** |
| Recall | 0.81 | **0.90** |
| Latency (ms) | 42.0 | **11.5** |

---

## Thank You

Questions & Discussion
""";
        }

        private string get_lecture_markdown_template () {
            return """# Lecture 01: Statistical Inference & Modeling

**Course**: Quantitative Methods in Science
**Instructor**: Prof. Name

---

## Learning Objectives

1. Understand likelihood-based parameter estimation.
2. Derive the Cramér–Rao lower bound for unbiased estimators.
3. Implement numerical optimization in Python / R.

---

## Maximum Likelihood Estimation

Given i.i.d. observations $x_1, \dots, x_n \sim f(x \mid \theta)$, the log-likelihood is:

$$\ell(\theta) = \sum_{i=1}^n \log f(x_i \mid \theta)$$

The MLE $\hat{\theta}$ satisfies the score equation $\nabla_\theta \ell(\hat{\theta}) = 0$.

---

## Worked Example

- **Sample**: $n = 100$ measurements from $\mathcal{N}(\mu, \sigma^2)$.
- **Closed-form MLE**:
  - $\hat{\mu} = \bar{x}$
  - $\hat{\sigma}^2 = \frac{1}{n} \sum_{i=1}^n (x_i - \bar{x})^2$

---

## Further Reading

- Casella & Berger, *Statistical Inference*, Chapter 7.
- Wasserman, *All of Statistics*, Chapter 9.
""";
        }

        private string get_revealjs_ts_template () {
            return """// Open-source Reveal.js TypeScript Presentation Generator
// Run with Imladris TypeScript Runner to emit standalone HTML5 slides.

export interface SlideSpec {
  title: string;
  subtitle?: string;
  bullets?: string[];
  equation?: string;
  code?: { lang: string; source: string };
}

const slides: SlideSpec[] = [
  {
    title: "Type-Safe Scientific Presentations",
    subtitle: "Generated with TypeScript + Reveal.js",
    bullets: [
      "Strictly typed slide definitions",
      "Built-in KaTeX equation rendering",
      "Zero-config standalone HTML5 output",
    ],
  },
  {
    title: "Mathematical Formulation",
    equation: "J(\\theta) = \\frac{1}{2m} \\sum_{i=1}^{m} (h_\\theta(x^{(i)}) - y^{(i)})^2",
    bullets: [
      "Convex quadratic objective for linear models",
      "Exact analytical gradient available",
    ],
  },
  {
    title: "Reproducible Benchmark Code",
    code: {
      lang: "typescript",
      source: "const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;\nconsole.log(mean([0.91, 0.94, 0.93]));",
    },
  },
];

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function renderSlide(slide: SlideSpec): string {
  const subtitleHtml = slide.subtitle ? `<h3>${escapeHtml(slide.subtitle)}</h3>` : "";
  const eqHtml = slide.equation ? `<p>$$${slide.equation}$$</p>` : "";
  const bulletsHtml = slide.bullets
    ? `<ul>${slide.bullets.map((b) => `<li>${escapeHtml(b)}</li>`).join("")}</ul>`
    : "";
  const codeHtml = slide.code
    ? `<pre><code class="language-${escapeHtml(slide.code.lang)}">${escapeHtml(slide.code.source)}</code></pre>`
    : "";

  return `  <section>\n    <h2>${escapeHtml(slide.title)}</h2>\n    ${subtitleHtml}\n    ${eqHtml}\n    ${bulletsHtml}\n    ${codeHtml}\n  </section>`;
}

export function buildRevealHtml(deckTitle: string, items: SlideSpec[]): string {
  const sections = items.map(renderSlide).join("\n");
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>${escapeHtml(deckTitle)}</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/reveal.js@5/dist/reveal.css" />
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/reveal.js@5/dist/theme/white.css" />
</head>
<body>
  <div class="reveal"><div class="slides">
${sections}
  </div></div>
  <script src="https://cdn.jsdelivr.net/npm/reveal.js@5/dist/reveal.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/reveal.js@5/plugin/math/math.js"></script>
  <script>Reveal.initialize({ hash: true, plugins: [ RevealMath.KaTeX ] });</script>
</body>
</html>`;
}

console.log(buildRevealHtml("Imladris TypeScript Deck", slides));
""";
        }

        private string get_slidev_ts_template () {
            return """// Open-source Slidev-compatible Data-Driven Presentation Builder (TypeScript)
// Generates Slidev Markdown slides from typed experimental metrics.

export interface ExperimentMetric {
  model: string;
  accuracy: number;
  f1Score: number;
  latencyMs: number;
}

const benchmarkResults: ExperimentMetric[] = [
  { model: "Logistic Regression", accuracy: 84.2, f1Score: 0.83, latencyMs: 1.2 },
  { model: "Random Forest", accuracy: 89.7, f1Score: 0.89, latencyMs: 8.4 },
  { model: "Proposed Transformer", accuracy: 94.5, f1Score: 0.94, latencyMs: 12.1 },
];

function formatMarkdownTable(rows: ExperimentMetric[]): string {
  const header = "| Model | Accuracy (%) | F1 | Latency (ms) |\n| :--- | :---: | :---: | :---: |";
  const body = rows
    .map((r) => `| ${r.model} | ${r.accuracy.toFixed(1)} | ${r.f1Score.toFixed(2)} | ${r.latencyMs.toFixed(1)} |`)
    .join("\n");
  return `${header}\n${body}`;
}

const slidevMarkdown = `---
theme: default
title: Data-Driven Benchmark Deck
---

# Experimental Results Overview
Generated programmatically from TypeScript benchmark records.

---

# Model Comparison

${formatMarkdownTable(benchmarkResults)}

---

# Conclusion

- Best accuracy: **${benchmarkResults[benchmarkResults.length - 1].model}** (${benchmarkResults[benchmarkResults.length - 1].accuracy}%)
`;

console.log(slidevMarkdown);
""";
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
    margin: 2cm
---

```{=typst}
#set columns(3, gutter: 1.5em)
```

# 1. Abstract

This 3-column symposium poster demonstrates Imladris multi-format publishing. Scientific documents compile to high-resolution print PDF with Typst, R/Python graphics, and KaTeX.

# 2. Wet-Lab & Data Pipeline

1. **Cell Culture & Perturbation**: Targeted gene knockdown assays ($n = 6$ biological replicates).
2. **Sequencing & Galaxy API**: Processed via Galaxy Cloud REST workflows using Arekyer.
3. **Reproducibility**: Environment locked via `micromamba` and `renv`.

# 3. Differential Expression (Volcano Plot)

```{r}
#| echo: false
#| fig-width: 7
#| fig-height: 5
set.seed(42)
n_genes <- 400
df <- data.frame(
  log2FC = rnorm(n_genes, 0, 1.5),
  negLog10P = rexp(n_genes, rate = 0.6)
)
df$sig <- abs(df$log2FC) > 1.5 & df$negLog10P > 1.3
plot(
  df$log2FC, df$negLog10P,
  col = ifelse(df$sig, "#c01c28", "#77767b"),
  pch = 19, cex = 0.8,
  xlab = "log2 Fold Change",
  ylab = "-log10(p-value)",
  main = "Volcano Plot: Knockdown vs Control"
)
abline(h = 1.3, lty = 2, col = "#1c71d8")
abline(v = c(-1.5, 1.5), lty = 2, col = "#1c71d8")
```

# 4. References & Acknowledgements

- Funded by European Research Council (ERC) grant.
- Authored with Imladris Scientific Notebook Studio.
""";
        }
    }
}
