# Galaxy Workflows & BioBlend API Manual

Connect upstream Galaxy cloud genomics histories to local Imladris manuscripts via the Arekyer provenance bridge and BioBlend API.

## Querying Histories & Datasets with BioBlend

Store `GALAXY_API_KEY` in the system keyring through the Arekyer panel so credentials never appear in plain-text `.qmd` files.

```python
import os
from bioblend.galaxy import GalaxyInstance

gi = GalaxyInstance(
    url=os.environ.get("GALAXY_URL", "https://usegalaxy.eu"),
    key=os.environ["GALAXY_API_KEY"]
)
histories = gi.histories.get_histories(limit=5)
for h in histories:
    print(h["id"], h["name"])
```

## Galaxy Workflow `.ga` Structure

Galaxy `.ga` files store a JSON directed acyclic graph of `steps`, `input_connections`, and `tool_state` definitions for reproducible server-side execution.

```json
{
  "a_galaxy_workflow": "true",
  "format-version": "0.1",
  "name": "RNA-Seq DESeq2 Pipeline",
  "steps": {
    "0": { "type": "data_collection_input", "label": "Paired FASTQ Reads" },
    "1": { "type": "tool", "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8" }
  }
}
```
