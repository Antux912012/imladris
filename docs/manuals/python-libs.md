# Python Scientific Libraries Reference

Use `numpy`, `pandas`, `scipy.stats`, `matplotlib`, `scanpy`, and `biopython` for quantitative enrichment, single-cell omics, and sequence verification.

## Pandas DataFrames & SciPy Exact Contingency Tests

```python
import numpy as np
import pandas as pd
from scipy.stats import fisher_exact, chi2_contingency

table = np.array([[14, 2], [3, 21]])
odds_ratio, p_fisher = fisher_exact(table, alternative="two-sided")
chi2, p_chi2, dof, _ = chi2_contingency(table, correction=False)
print(f"OR = {odds_ratio:.3f}, Fisher p = {p_fisher:.4g}, Chi2 = {chi2:.3f} (p = {p_chi2:.4g})")
```

## Single-Cell Transcriptomics (`scanpy`) & Emitting `.qual-hook.json`

```python
import json

# Emit quantitative marker genes into Imladris qualitative evidence index
hook_payload = {
    "source": "Scanpy Rank-Genes-Groups",
    "domain": "gene-expr",
    "rules_applied": "pvals_adj < 0.01 & logfoldchanges > 1.5",
    "annotations": [
        {
            "entity_id": "Ensembl:ENSG00000141510",
            "code_id": "deg-up",
            "valence": "upregulated",
            "confidence": "high",
            "excerpt": "TP53 cluster marker (log2FC = 2.18, padj = 4.2e-7)"
        }
    ]
}
with open(".qual-hook.json", "w", encoding="utf-8") as fh:
    json.dump(hook_payload, fh, indent=2)
```

## BioPython Sequence Inspection (`Bio.Seq`, `Bio.SeqIO`)

```python
from Bio.Seq import Seq

seq = Seq("ATGGAGGAGCCGCAGTCAGATCCTAGCGTCGAG")
print("Length:", len(seq), "RevComp:", seq.reverse_complement(), "AA:", seq.translate())
```
