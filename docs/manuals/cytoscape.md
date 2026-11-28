# Cytoscape, CyREST & CX2 Manual

Imladris provides a native GTK4/Cairo graph canvas, automates **Cytoscape Desktop** over `CyREST` (`http://localhost:1234/v1`), and exchanges **CX2** and **GraphML** files.

## Core CyREST v1 Endpoints

Start Cytoscape Desktop on your workstation; CyREST listens on port `1234` by default.

```bash
# Check Cytoscape health and version
curl -s http://localhost:1234/v1 | python3 -m json.tool

# List loaded network SUIDs
curl -s http://localhost:1234/v1/networks

# Export the active view as an SVG file
curl -s http://localhost:1234/v1/networks/42/views/first.svg -o network.svg
```

## CX2 (Cytoscape Exchange 2.0) Aspect Structure

CX2 files store a JSON array of typed aspects (`CXVersion`, `attributeDeclarations`, `networkAttributes`, `nodes`, `edges`, `visualProperties`, `status`) compatible with Cytoscape 3.10+ and NDEx.

```json
[
  { "CXVersion": "2.0", "hasFragments": false },
  {
    "nodes": [
      { "id": 1, "x": 120.0, "y": 80.0, "v": { "name": "UniProtKB:P04637", "label": "TP53", "groundedness": 6 } }
    ]
  },
  { "status": [{ "error": "", "success": true }] }
]
```
