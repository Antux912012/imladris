# Python 3 Core Reference

Write typed, reproducible Python 3 modules and Quarto code cells using standard library primitives.

## Typed Dataclasses & Pathlib File I/O

Prefer `pathlib.Path` and `@dataclass` over untyped dictionaries and string path concatenation.

```python
from dataclasses import dataclass
from pathlib import Path
import hashlib
import json

@dataclass(frozen=True)
class EvidenceRecord:
    span_id: str
    code_id: str
    excerpt: str

    def sha256(self) -> str:
        return hashlib.sha256(self.excerpt.encode("utf-8")).hexdigest()

rec = EvidenceRecord("q-101", "ptm-dysregulation", "TP53 Ser15 phosphorylation")
print(rec.span_id, rec.sha256()[:16])
```

## Querying the Imladris Qualitative SQLite Sidecar

```python
import sqlite3

with sqlite3.connect(".imladris-qual.db") as conn:
    rows = conn.execute(
        "SELECT span_id, code_id, entity_id, coder_id FROM spans ORDER BY created_utc DESC LIMIT 10"
    ).fetchall()
    for row in rows:
        print(row)
```
