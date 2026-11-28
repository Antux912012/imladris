# R Language & Tidyverse Reference

This manual describes base R statistical modeling, `tidyverse` data transformation, and Quarto chunk authoring in Imladris.

## Vectorized DataFrames & Tidyverse Pipelines

Use native R pipes (`|>`) with `dplyr` verbs to filter, group, and summarize rectangular data without mutating input data.

```r
library(dplyr)
library(ggplot2)

cohort_summary <- mtcars |>
  filter(!is.na(mpg), cyl %in% c(4, 6, 8)) |>
  group_by(cyl) |>
  summarize(
    n = n(),
    mean_mpg = mean(mpg),
    sd_mpg = sd(mpg),
    .groups = "drop"
  )
print(cohort_summary)
```

## Linear Models & Contingency Tests

Run linear regression (`lm`), generalized linear models (`glm`), and contingency tests (`fisher.test`, `chisq.test`) on data frames and matrices.

```r
fit <- lm(mpg ~ wt + hp, data = mtcars)
summary(fit)
confint(fit, level = 0.95)

# Exact 2x2 contingency test
mat <- matrix(c(12, 3, 2, 18), nrow = 2, byrow = TRUE)
fisher.test(mat, alternative = "two.sided")
```

## Statistical Plots with ggplot2

Create scatter plots with linear regression overlays using `ggplot2`.

```r
ggplot(mtcars, aes(x = wt, y = mpg, color = factor(cyl))) +
  geom_point(size = 2.6, alpha = 0.85) +
  geom_smooth(method = "lm", se = TRUE) +
  theme_minimal(base_size = 12) +
  labs(title = "Fuel Efficiency by Vehicle Weight", x = "Weight (1000 lbs)", y = "MPG", color = "Cylinders")
```
