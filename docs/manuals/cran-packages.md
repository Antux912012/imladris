# CRAN Biostatistics & Bioinformatics Packages

Use these curated CRAN and Bioconductor packages for clinical trials, inter-rater reliability (IRR), survival analysis, and SQLite sidecar inspection.

## Inter-Rater Reliability (`irr`)

Compute Cohen's Kappa, Fleiss' Kappa, and Krippendorff's Alpha to benchmark qualitative dual-coding agreement.

```r
library(irr)

# Two-coder Cohen's Kappa
ratings_2 <- data.frame(coder1 = c("loc-nuclear", "deg-up", "loc-nuclear", "deg-down"),
                        coder2 = c("loc-nuclear", "deg-up", "deg-down", "deg-down"))
kappa2(ratings_2, weight = "unweighted")

# Multi-coder Krippendorff's Alpha (rows = coders, cols = units)
mat <- rbind(
  coder1 = c(1, 2, 3, 3, 2, NA),
  coder2 = c(1, 2, 3, 2, 2, 1),
  coder3 = c(1, 3, 3, 3, 2, 1)
)
kripp.alpha(mat, method = "nominal")
```

## Clinical Survival & Baseline Tables (`survival`, `gtsummary`)

```r
library(survival)
fit_km <- survfit(Surv(time, status) ~ sex, data = lung)
fit_cox <- coxph(Surv(time, status) ~ age + sex + ph.ecog, data = lung)
summary(fit_cox)
```

## Cytoscape Automation from R (`RCy3`)

```r
if (requireNamespace("RCy3", quietly = TRUE)) {
  RCy3::cytoscapePing()
  RCy3::getNetworkList()
}
```
