# Bash & Linux Scripting Manual

Write deterministic POSIX and GNU Bash automation pipelines for reproducible data processing, checksum verification, and batch Quarto builds.

## Defensive Shell Header & Checksum Verification

Always enable `set -euo pipefail` so unset variables and failed pipeline stages stop execution immediately.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Compute SHA-256 provenance manifest for all Quarto manuscripts
find . -maxdepth 2 -name "*.qmd" -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
sha256sum --check SHA256SUMS.txt
```

## Text Processing with `awk`, `sed`, and `grep`

```bash
# Filter TSV rows where adjusted p-value (col 6) < 0.05 and |log2FC| (col 3) > 1.5
awk -F'	' 'NR == 1 || ($6 != "NA" && $6 + 0 < 0.05 && ($3 > 1.5 || $3 < -1.5))' deseq2_results.tsv > significant_hits.tsv

# Extract all Pandoc {.qual ...} span IDs across manuscripts
grep -RhoE '\{\.qual[^}]+\}' .
```
