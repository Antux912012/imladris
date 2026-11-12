<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# WIKI 03 // NATURAL MATH & CHEMICAL REACTION STUDIO

**Document ID:** IML-WIKI-003  
**Standard:** ASD-STE100 (Simplified Technical English)  
**Components:** `Imladris.Core.MathChemEngine`, `Imladris.UI.MathChemEditorDialog`  
**Shortcut:** `Ctrl+M` (or Ribbon $\rightarrow$ Insert $\rightarrow$ Math & Chem Studio)  

---

## 1. PURPOSE OF THE SYSTEM

Writing complex mathematical equations and balanced chemical reactions in raw LaTeX (`\frac{}{}`, `\int_{}^{}`, `\ce{...}`) slows down scientific writing and introduces brace-matching errors.

The **Natural Math & Chemical Reaction Studio** lets you write formulas using natural human-readable notation and converts them automatically into publication-grade **LaTeX** or **Markdown**.

---

## 2. OPERATING MODES AND OUTPUT TARGETS

The Studio supports two domain parsers (`MATHEMATICS` and `CHEMISTRY`) and six output formats:

| Output Target | Format Description | Example Output |
| :--- | :--- | :--- |
| **LaTeX Display (`$$...$$`)** | Centered display math or `\ce{...}` block | `$$\frac{-b \pm \sqrt{b^{2} - 4ac}}{2a}$$` |
| **LaTeX Inline (`$...$`)** | Inline math or chemical expression | `$\ce{H2SO4(aq)}$` |
| **LaTeX Equation (`\begin{equation}`)** | Numbered LaTeX equation environment | `\begin{equation}\n...\n\end{equation}` |
| **LaTeX Align (`\begin{align}`)** | Multi-line aligned equation environment | `\begin{align}\n...\n\end{align}` |
| **Markdown (`~sub~` / `^sup^`)** | Pandoc/Quarto native subscript and superscript | `6CO~2~(g) + 6H~2~O(l) → C~6~H~12~O~6~(aq) + 6O~2~(g)` |
| **Markdown Unicode** | Pure Unicode scientific characters (`₀₁₂`, `⁰¹²`, `⇌`, `∫`) | `6CO₂(g) + 6H₂O(l) → C₆H₁₂O₆(aq) + 6O₂(g)` |

---

## 3. NATURAL MATHEMATICS SYNTAX GUIDE

| Construct | Natural Input | Converted LaTeX |
| :--- | :--- | :--- |
| **Fractions** | `(a + b) / (c + d)` | `\frac{a + b}{c + d}` |
| **Square & N-th Roots** | `sqrt(x^2 + y^2)`, `root(3, x)` | `\sqrt{x^{2} + y^{2}}`, `\sqrt[3]{x}` |
| **Definite Integrals** | `int(0, inf) e^(-x^2) dx` | `\int_{0}^{\infty} e^{-x^{2}} \, dx` |
| **Summations & Products** | `sum(i=1, n) x_i`, `prod(k=1, n) k` | `\sum_{i=1}^{n} x_{i}`, `\prod_{k=1}^{n} k` |
| **Limits** | `lim(x -> 0) sin(x)/x = 1` | `\lim_{x \to 0} \frac{\sin(x)}{x} = 1` |
| **Derivatives** | `d/dx f(x)`, `pd/px u(x,t)` | `\frac{d}{dx} f(x)`, `\frac{\partial}{\partial x} u(x,t)` |
| **Matrices** | `matrix([a, b; c, d])` | `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` |
| **Relational & Logic** | `+-`, `!=`, `<=`, `>=`, `~=`, `inf` | `\pm`, `\neq`, `\leq`, `\geq`, `\approx`, `\infty` |
| **Greek Symbols** | `alpha`, `beta`, `gamma`, `Delta`, `Omega` | `\alpha`, `\beta`, `\gamma`, `\Delta`, `\Omega` |

---

## 4. NATURAL CHEMICAL FORMULA & REACTION SYNTAX GUIDE

| Construct | Natural Input | LaTeX (`mhchem`) | Markdown (`~sub~`/`^sup^`) |
| :--- | :--- | :--- | :--- |
| **Molecular Formulas** | `H2SO4`, `C6H12O6`, `Ca(OH)2` | `\ce{H2SO4}`, `\ce{C6H12O6}`, `\ce{Ca(OH)2}` | `H~2~SO~4~`, `C~6~H~12~O~6~`, `Ca(OH)~2~` |
| **Ions & Charges** | `SO4^2-`, `Fe^3+`, `NH4+`, `[Fe(CN)6]^4-` | `\ce{SO4^{2-}}`, `\ce{Fe^{3+}}`, `\ce{[Fe(CN)6]^{4-}}` | `SO~4~^2-^`, `Fe^3+^`, `[Fe(CN)~6~]^4-^` |
| **Reaction Arrows** | `->`, `<=>`, `<->`, `<-` | `->`, `<=>`, `<->`, `<-` | `→`, `⇌`, `↔`, `←` |
| **Catalysts & Conditions** | `->[h*nu][chlorophyll]`, `->[Delta]`, `->[Pt]` | `->[h\nu][\text{chlorophyll}]`, `->[\Delta]`, `->[\text{Pt}]` | `→[hν, chlorophyll]`, `→[Δ]`, `→[Pt]` |
| **Phase States & Precipitates** | `(s)`, `(l)`, `(g)`, `(aq)`, `(v)`, `(^)` | `(s)`, `(l)`, `(g)`, `(aq)`, `\downarrow`, `\uparrow` | `(s)`, `(l)`, `(g)`, `(aq)`, `↓`, `↑` |
| **Hydrates & Bonds** | `CuSO4 * 5H2O`, `CH3-CH=CH2`, `HC#CH` | `\ce{CuSO4 . 5H2O}`, `\ce{CH3-CH=CH2}`, `\ce{HC#CH}` | `CuSO~4~·5H~2~O`, `CH~3~-CH=CH~2~`, `HC≡CH` |

---

## 5. OPERATING PROCEDURE

1. Place your cursor in the active `.qmd`, `.Rmd`, `.ipynb`, or `.md` editor.
2. Press **`Ctrl+M`** (or click **Math & Chem Studio** in the **Insert** ribbon tab).
3. Select **Mathematics** or **Chemical Formula / Reaction**.
4. Type your expression in the **Natural Input** box, or select a template from the **Preset Library** (Quadratic Formula, Gaussian Integral, Shannon Entropy, Bayes' Theorem, Photosynthesis, Haber-Bosch Process, ATP Hydrolysis, Henderson-Hasselbalch, Michaelis-Menten).
5. Inspect the rendered equation in the live offline preview pane.
6. Choose your target output format (**LaTeX** or **Markdown**) and click **Insert into Document**.
