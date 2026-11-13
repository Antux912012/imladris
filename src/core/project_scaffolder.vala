// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

namespace Imladris {

    public enum ProjectType {
        STANDARD,
        SANDBOXED;

        public string to_string () {
            switch (this) {
                case SANDBOXED:
                    return "Sandboxed";
                case STANDARD:
                default:
                    return "Standard";
            }
        }

        public static ProjectType from_string (string str) {
            string s = str.strip ().down ();
            if (s == "sandboxed") {
                return SANDBOXED;
            }
            return STANDARD;
        }

        public string get_badge_label () {
            switch (this) {
                case SANDBOXED:
                    return "[Sandboxed - Reproducible]";
                case STANDARD:
                default:
                    return "[System Libraries - Non-Portable]";
            }
        }

        public string get_badge_css_class () {
            switch (this) {
                case SANDBOXED:
                    return "success";
                case STANDARD:
                default:
                    return "warning";
            }
        }
    }

    public enum DocumentFormat {
        MD,
        HTML,
        CSS,
        BIB,
        RSCRIPT,
        RMD,
        QMD,
        IPYNB,
        PYSCRIPT;

        public string get_extension () {
            switch (this) {
                case MD:       return ".md";
                case HTML:     return ".html";
                case CSS:      return ".css";
                case BIB:      return ".bib";
                case RSCRIPT:  return ".R";
                case RMD:      return ".Rmd";
                case QMD:      return ".qmd";
                case IPYNB:    return ".ipynb";
                case PYSCRIPT: return ".py";
                default:       return ".qmd";
            }
        }

        public string get_display_name () {
            switch (this) {
                case MD:       return "Simple Markdown (.md)";
                case HTML:     return "HTML5 + CSS + LaTeX (.html)";
                case CSS:      return "CSS Stylesheet (.css)";
                case BIB:      return "BibTeX Bibliography (.bib)";
                case RSCRIPT:  return "R Script (.R)";
                case RMD:      return "R Markdown (.Rmd)";
                case QMD:      return "Quarto Document (.qmd)";
                case IPYNB:    return "Jupyter Notebook (.ipynb)";
                case PYSCRIPT: return "Python Script (.py)";
                default:       return "Quarto Document (.qmd)";
            }
        }

        public string to_badge_label () {
            return get_display_name ();
        }

        public string to_syntax_lang () {
            switch (this) {
                case HTML:     return "html";
                case CSS:      return "css";
                case BIB:      return "bibtex";
                case RSCRIPT:  return "r";
                case RMD:      return "rmd";
                case IPYNB:    return "json";
                case PYSCRIPT: return "python3";
                case MD:
                case QMD:
                default:       return "markdown";
            }
        }

        public string get_short_code () {
            switch (this) {
                case MD:       return "Md";
                case HTML:     return "Html";
                case CSS:      return "Css";
                case BIB:      return "Bib";
                case RSCRIPT:  return "RScript";
                case RMD:      return "Rmd";
                case QMD:      return "Qmd";
                case IPYNB:    return "Ipynb";
                case PYSCRIPT: return "PyScript";
                default:       return "Qmd";
            }
        }

        public static DocumentFormat from_short_code (string code) {
            string c = code.strip ().down ();
            if (c == "md" || c == "markdown") return MD;
            if (c == "html" || c == "htm") return HTML;
            if (c == "css") return CSS;
            if (c == "bib" || c == "bibtex") return BIB;
            if (c == "rscript" || c == "r") return RSCRIPT;
            if (c == "rmd" || c == "rmarkdown") return RMD;
            if (c == "qmd" || c == "quarto") return QMD;
            if (c == "ipynb" || c == "jupyter") return IPYNB;
            if (c == "pyscript" || c == "py" || c == "python") return PYSCRIPT;
            return QMD;
        }

        public static DocumentFormat from_filename (string filename) {
            string lower = filename.down ();
            if (lower.has_suffix (".ipynb")) return IPYNB;
            if (lower.has_suffix (".qmd")) return QMD;
            if (lower.has_suffix (".rmd")) return RMD;
            if (lower.has_suffix (".r")) return RSCRIPT;
            if (lower.has_suffix (".py")) return PYSCRIPT;
            if (lower.has_suffix (".css")) return CSS;
            if (lower.has_suffix (".bib")) return BIB;
            if (lower.has_suffix (".html") || lower.has_suffix (".htm")) return HTML;
            return MD;
        }

        public bool is_computational_notebook () {
            return this == QMD || this == RMD || this == IPYNB;
        }

        public bool is_r_primary () {
            return this == RMD || this == RSCRIPT;
        }

        public bool is_python_primary () {
            return this == IPYNB || this == PYSCRIPT;
        }
    }

    public class ProjectConfig : GLib.Object {
        public string project_name { get; set; default = "Untitled-Project"; }
        public string author { get; set; default = ""; }
        public ProjectType project_type { get; set; default = ProjectType.STANDARD; }
        public DocumentFormat format { get; set; default = DocumentFormat.QMD; }

        public string custom_project_dir { get; set; default = ""; }
        public string custom_data_dir { get; set; default = ""; }
        public string custom_images_dir { get; set; default = ""; }
        public string custom_bib_dir { get; set; default = ""; }
        public string imladris_version { get; set; default = "1.0"; }

        public bool sandboxed {
            get { return project_type == ProjectType.SANDBOXED; }
            set { project_type = value ? ProjectType.SANDBOXED : ProjectType.STANDARD; }
        }

        public ProjectConfig clone () {
            var c = new ProjectConfig ();
            c.project_name = this.project_name;
            c.author = this.author;
            c.project_type = this.project_type;
            c.format = this.format;
            c.custom_project_dir = this.custom_project_dir;
            c.custom_data_dir = this.custom_data_dir;
            c.custom_images_dir = this.custom_images_dir;
            c.custom_bib_dir = this.custom_bib_dir;
            c.imladris_version = this.imladris_version;
            return c;
        }
    }

    public class ProjectScaffolder : GLib.Object {

        public static File create_project (ProjectConfig config) throws GLib.Error {
            // 1. Resolve Root Project Directory
            string base_docs = Path.build_filename (Environment.get_home_dir (), "Documents");
            string root_path = config.custom_project_dir.strip () != ""
                ? config.custom_project_dir.strip ()
                : Path.build_filename (base_docs, sanitize_dirname (config.project_name));

            ensure_directory (root_path);

            // 2. Resolve & Create Subfolders (Data, Images, Bibliography)
            string data_path = config.custom_data_dir.strip () != ""
                ? config.custom_data_dir.strip ()
                : Path.build_filename (root_path, "data");

            string images_path = config.custom_images_dir.strip () != ""
                ? config.custom_images_dir.strip ()
                : Path.build_filename (root_path, "images");

            string bib_path = config.custom_bib_dir.strip () != ""
                ? config.custom_bib_dir.strip ()
                : Path.build_filename (root_path, "bibliography");

            ensure_directory (data_path);
            ensure_directory (images_path);
            ensure_directory (bib_path);

            // 3. Create starter references.bib
            string bib_file_path = Path.build_filename (bib_path, "references.bib");
            File bib_file = File.new_for_path (bib_file_path);
            if (!bib_file.query_exists ()) {
                FileUtils.set_contents (bib_file_path, "% Bibliography database generated by Imladris\n");
            }

            // 4. Generate Main Document File
            string main_filename = sanitize_dirname (config.project_name) + config.format.get_extension ();
            string main_file_path = Path.build_filename (root_path, main_filename);
            File main_file = File.new_for_path (main_file_path);

            if (!main_file.query_exists ()) {
                string template = build_template (config, root_path, data_path, images_path, bib_file_path);
                FileUtils.set_contents (main_file_path, template);
            }

            // 5. Generate .mallorn & 1:1 .Rproj manifests + metadata
            MallornManager.write_project_manifests (root_path, config);

            // 6. If Sandboxed, initialize dependencies
            if (config.project_type == ProjectType.SANDBOXED) {
                if (config.format == DocumentFormat.RMD || config.format == DocumentFormat.QMD) {
                    try {
                        Services.SandboxController.init_r_sandbox (root_path);
                    } catch (GLib.Error e) {
                        // Handled via bootstrap stubs
                    }
                }
                if (config.format == DocumentFormat.IPYNB || config.format == DocumentFormat.QMD) {
                    try {
                        Services.SandboxController.init_py_sandbox (root_path);
                    } catch (GLib.Error e) {
                        // Handled via bootstrap stubs
                    }
                }
            }

            return main_file;
        }

        public static File create_standalone_file (string target_dir, string base_name, DocumentFormat format, string author = "") throws GLib.Error {
            ensure_directory (target_dir);
            string sanitized = sanitize_dirname (base_name);
            string filename = sanitized + format.get_extension ();
            string file_path = Path.build_filename (target_dir, filename);
            File target_file = File.new_for_path (file_path);

            if (!target_file.query_exists ()) {
                var dummy_cfg = new ProjectConfig () {
                    project_name = sanitized,
                    author = author,
                    format = format
                };
                string template = build_template (dummy_cfg, target_dir, "data", "images", "references.bib");
                FileUtils.set_contents (file_path, template);
            }

            return target_file;
        }

        private static void ensure_directory (string path) throws GLib.Error {
            File dir = File.new_for_path (path);
            if (!dir.query_exists ()) {
                dir.make_directory_with_parents (null);
            }
        }

        public static string sanitize_dirname (string input) {
            string cleaned = input.strip ().replace (" ", "_").replace ("/", "-");
            return cleaned != "" ? cleaned : "Untitled_Project";
        }

        public static string build_template (
            ProjectConfig cfg,
            string root_path,
            string data_path,
            string images_path,
            string bib_file_path
        ) {
            string date_str = new DateTime.now_local ().format ("%Y-%m-%d");
            string author_name = cfg.author.strip () != "" ? cfg.author.strip () : Environment.get_real_name ();

            string rel_bib = bib_file_path.has_prefix (root_path)
                ? "bibliography/references.bib" : bib_file_path;
            string rel_data = data_path.has_prefix (root_path)
                ? "data/" : data_path;
            string rel_img = images_path.has_prefix (root_path)
                ? "images/" : images_path;

            switch (cfg.format) {
                case DocumentFormat.QMD:
                    return """---
title: "%s"
author: "%s"
date: "%s"
format:
  html:
    toc: true
    code-fold: true
bibliography: "%s"
---

## Introduction

Project workspace initialized by **Imladris**.

- **Data directory:** `%s`
- **Figures directory:** `%s`

```{r}
#| label: setup
#| include: false
DATA_DIR <- "%s"
IMG_DIR  <- "%s"
```

""".printf (cfg.project_name, author_name, date_str, rel_bib, rel_data, rel_img, rel_data, rel_img);

                case DocumentFormat.RMD:
                    return """---
title: "%s"
author: "%s"
date: "%s"
output: html_document
bibliography: "%s"
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo = TRUE, fig.path = "%s")
DATA_DIR <- "%s"
```

## Overview

Start writing your R Markdown analysis here.
""".printf (cfg.project_name, author_name, date_str, rel_bib, rel_img, rel_data);

                case DocumentFormat.IPYNB:
                    return """{
  "cells": [
    {
      "cell_type": "markdown",
      "id": "header-cell",
      "metadata": {},
      "source": [
        "# %s\\n",
        "**Author:** %s | **Date:** %s\\n"
      ]
    },
    {
      "cell_type": "code",
      "execution_count": null,
      "id": "setup-cell",
      "metadata": {},
      "outputs": [],
      "source": [
        "from pathlib import Path\\n",
        "DATA_DIR = Path(\\\"%s\\\")\\n",
        "IMG_DIR = Path(\\\"%s\\\")\\n"
      ]
    }
  ],
  "metadata": {
    "kernelspec": {
      "display_name": "Python 3",
      "language": "python",
      "name": "python3"
    },
    "language_info": {
      "name": "python"
    }
  },
  "nbformat": 4,
  "nbformat_minor": 5
}
""".printf (cfg.project_name, author_name, date_str, rel_data, rel_img);

                case DocumentFormat.HTML:
                    return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>%s</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; line-height: 1.6; max-width: 800px; margin: 40px auto; padding: 0 20px; }
  </style>
</head>
<body>
  <h1>%s</h1>
  <p><strong>Author:</strong> %s | <strong>Date:</strong> %s</p>
  <hr>
  <p>Standard HTML5 document created with <strong>Imladris</strong>.</p>
</body>
</html>
""".printf (cfg.project_name, cfg.project_name, author_name, date_str);

                case DocumentFormat.RSCRIPT:
                    return """# ==============================================================================
# %s
# Author: %s
# Date: %s
# Generated by Imladris
# ==============================================================================

# Setup directories
DATA_DIR <- "%s"
IMG_DIR  <- "%s"

message("Imladris R script session initialized.")
""".printf (cfg.project_name, author_name, date_str, rel_data, rel_img);

                case DocumentFormat.PYSCRIPT:
                    return """#!/usr/bin/env python3
# ==============================================================================
# %s
# Author: %s
# Date: %s
# Generated by Imladris
# ==============================================================================

from pathlib import Path

DATA_DIR = Path("%s")
IMG_DIR = Path("%s")

def main():
    print("Imladris Python script session initialized.")

if __name__ == "__main__":
    main()
""".printf (cfg.project_name, author_name, date_str, rel_data, rel_img);

                case DocumentFormat.MD:
                default:
                    return """---
title: "%s"
author: "%s"
date: "%s"
bibliography: "%s"
---

# %s

Start typing your Markdown document here.
""".printf (cfg.project_name, author_name, date_str, rel_bib, cfg.project_name);
            }
        }

        public static string get_shiny_template (string app_title = "Imladris Scientific Shiny App") {
            return """# ==============================================================================
# %s
# Interactive Reactive Web Application powered by R & Shiny
# ==============================================================================

library(shiny)
library(bslib)

ui <- page_sidebar(
  title = "%s",
  sidebar = sidebar(
    title = "Controls",
    sliderInput("obs", "Number of Observations:", min = 20, max = 1000, value = 250),
    selectInput("dist", "Distribution:", choices = c("Normal", "Uniform", "Exponential")),
    checkboxInput("density", "Overlay Density Curve", value = TRUE),
    hr(),
    actionButton("resample", "Re-sample Data", class = "btn-primary")
  ),
  card(
    card_header("Distribution Histogram"),
    plotOutput("distPlot")
  ),
  card(
    card_header("Summary Statistics"),
    verbatimTextOutput("summary")
  )
)

server <- function(input, output, session) {
  # Reactive distribution sampler
  data <- reactive({
    input$resample # Dependency on button
    switch(input$dist,
      "Normal" = rnorm(input$obs),
      "Uniform" = runif(input$obs),
      "Exponential" = rexp(input$obs)
    )
  })

  output$distPlot <- renderPlot({
    x <- data()
    hist(x, probability = TRUE, col = "#3584e4", border = "white",
         main = paste(input$dist, "Distribution (n =", length(x), ")"),
         xlab = "Value", ylab = "Density")
    if (input$density) {
      lines(density(x), col = "#e01b24", lwd = 2.5)
    }
  })

  output$summary <- renderPrint({
    summary(data())
  })
}

shinyApp(ui = ui, server = server)
""".printf (app_title, app_title);
        }

        public static string get_clinical_sap_qmd_template (string title = "Statistical Analysis Plan", string author = "Clinical Biostatistician") {
            return """---
title: "%s"
subtitle: "Randomized Controlled Trial Statistical Analysis Plan (ICH E9 / CONSORT)"
author: "%s"
date: today
format:
  html:
    toc: true
    number-sections: true
    code-fold: show
execute:
  echo: true
  warning: false
  message: false
---

# Introduction & Study Objectives

This Statistical Analysis Plan (SAP) specifies the primary, secondary, and safety statistical hypotheses and estimation methods for the trial.

## Primary Objective & Endpoint

The primary objective is to evaluate whether the investigational regimen improves overall survival or objective response compared to control.

# Study Design & Sample Size Justification

```{r sample-size-justification}
# ELBERETH ICH E9 SAMPLE SIZE JUSTIFICATION
alpha <- 0.05
power <- 0.80
hr <- 0.65
p_event <- 0.60
dropout <- 0.10

z_alpha <- qnorm(1 - alpha / 2)
z_beta <- qnorm(power)
req_events <- ceiling(4 * (z_alpha + z_beta)^2 / (log(hr)^2))
n_evaluable <- ceiling(req_events / p_event)
n_enrolled <- ceiling(n_evaluable / (1 - dropout))

cat(sprintf("Required Target Events: %%d\n", req_events))
cat(sprintf("Minimum Evaluable Sample Size: %%d subjects\n", n_evaluable))
cat(sprintf("Total Enrollment Target (accounting for 10%%%% attrition): %%d subjects\n", n_enrolled))
```

# Analysis Populations & Baseline Demographics (Table 1)

```{r baseline-table-1}
# Summary of patient baseline demographics (ADSL)
data(mtcars)
summary(mtcars[, c("mpg", "cyl", "hp", "wt")])
```

# Primary Time-to-Event Efficacy Analysis (Kaplan-Meier & Cox PH)

```{r survival-analysis}
library(survival)
# Simulation of clinical trial survival data
set.seed(42)
n <- 100
arm <- rbinom(n, 1, 0.5)
surv_time <- rexp(n, rate = 0.05 * exp(-0.4 * arm))
event <- rbinom(n, 1, 0.7)

km_fit <- survfit(Surv(surv_time, event) ~ arm)
cox_fit <- coxph(Surv(surv_time, event) ~ arm)
summary(cox_fit)
```
""".printf (title, author);
        }

        public static string get_rnaseq_biomarker_qmd_template (string title = "RNA-Seq Differential Expression Report", string author = "Bioinformatician") {
            return """---
title: "%s"
subtitle: "Transcriptomic Profiling & Survival Biomarker Discovery"
author: "%s"
date: today
format:
  html:
    toc: true
    code-fold: show
---

# Multi-Omics Profiling

Differential expression analysis using negative binomial generalized linear models.

```{r volcano-differential-expression}
# Simulated RNA-Seq differential expression table
set.seed(123)
n_genes <- 1000
log2fc <- rnorm(n_genes, 0, 1.5)
pvals <- runif(n_genes, 1e-6, 1.0)
padj <- p.adjust(pvals, method = "BH")

sig <- padj < 0.05 & abs(log2fc) >= 1.0
cat(sprintf("Total genes profiled: %%d\n", n_genes))
cat(sprintf("Significant differentially expressed genes: %%d\n", sum(sig)))
```
""".printf (title, author);
        }
    }
}
