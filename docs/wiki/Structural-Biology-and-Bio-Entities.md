<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# WIKI 03 // TANIQUETIL & YAVANNA: STRUCTURAL BIOLOGY & BIO-ENTITY PROVENANCE
**Document ID:** IML-WIKI-003  
**Standard:** ASD-STE100 (Simplified Technical English)  
**Components:** `Imladris.Bridges.Taniquetil`, `Imladris.Bridges.Yavanna`, `Imladris.Core.ProvenanceAttestationService`  
**Applicable Formats:** Quarto (`.qmd`), R Markdown (`.Rmd`)  

---

## 1. PURPOSE OF THE SUBSYSTEMS

Modern bioinformatics workflows unite sequence accessions, high-throughput tabular histories, molecular structural predictions, and wet-lab oligonucleotides.

1. **Taniquetil (`Imladris.Bridges.Taniquetil`)**: Queries the DeepMind / EMBL-EBI **AlphaFold Protein Structure Database (AFDB)** and RCSB PDB asynchronously. Visualizes per-residue predicted Local Distance Difference Test (**pLDDT**) confidence tracks and injects verified 3D structure and Predicted Aligned Error (**PAE**) loaders into the manuscript.
2. **Yavanna (`Imladris.Bridges.Yavanna`)**: Resolves UniProtKB protein accessions and Ensembl GRCh38 gene coordinates. Computes oligonucleotide properties (length, GC content, Melting Temperature $T_m$, Molecular Weight) in memory and injects verified reverse-complement specification tables.
3. **Provenance Attestation (`Imladris.Core.ProvenanceAttestationService`)**: Generates verifiable SHA-256 `<document>.provenance.lock.json` manifests tracking manuscript revisions, environment lockfiles (`renv.lock`, `uv.lock`), and biological provenance headers to satisfy FDA 21 CFR Part 11 and EU Cyber Resilience Act requirements.

---

## 2. SYSTEM ARCHITECTURE

| Subsystem | Stack | Primary Function |
| :--- | :--- | :--- |
| **Taniquetil Bridge** | `libsoup-3.0`, `json-glib-1.0`, Cairo | Resolves AFDB prediction records and renders 4-tier pLDDT confidence tracks. |
| **Yavanna Resolver** | `libsoup-3.0`, `json-glib-1.0`, Vala | Queries UniProt/Ensembl REST endpoints and calculates RT-qPCR oligo thermodynamics. |
| **Provenance Attestor** | `gio-2.0`, `GLib.Checksum` (SHA-256) | Computes cryptographic digest manifests for manuscripts and environment lockfiles. |

---

## 3. OPERATING PROCEDURES

### 3.1 Resolving an AlphaFold 3D Structure
1. Click the **Taniquetil AlphaFold Bridge** icon in the window header bar.
2. Enter a UniProt accession (for example: `P04637` or `P53_HUMAN`).
3. Click **Fetch**. Taniquetil loads prediction metadata and draws the color-coded pLDDT track:
   * **Very High (`pLDDT > 90`):** Dark Blue (`#0053D6`)
   * **Confident (`70 < pLDDT <= 90`):** Light Blue (`#65CBF3`)
   * **Low (`50 < pLDDT <= 70`):** Yellow (`#FFDB13`)
   * **Disordered / Very Low (`pLDDT <= 50`):** Orange (`#FF7D45`)
4. Click **[ + Citation ]**, **[ + R Bio3D ]**, or **[ + Py Structure ]** to inject code blocks into the manuscript.

### 3.2 Calculating Oligo Thermodynamics
1. Click the **Yavanna Bio-Entity & Oligo** icon in the window header bar.
2. Switch to the **Oligo Calculator** tab.
3. Paste a $5' \rightarrow 3'$ nucleotide sequence (for example: `ATGGCCATCGTAGC`).
4. Review the computed Length, GC%, $T_m$, Molecular Weight, and $5' \rightarrow 3'$ Reverse Complement.
5. Click **Insert Oligo Specification Table** to append a publication table to the document.

---

## 4. PROVENANCE MANIFEST SPECIFICATION (`<document>.provenance.lock.json`)

When you compile a manuscript in Imladris, the system writes a sidecar JSON lockfile:

```json
{
  "schemaVersion": "1.0",
  "generator": "Imladris Scientific Workbench 0.19.0",
  "timestampUtc": "2026-11-12T15:20:00Z",
  "manuscript": {
    "path": "/home/user/study/report.qmd",
    "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "lengthBytes": 4096
  },
  "environmentLocks": [
    { "file": "renv.lock", "sha256": "8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4" }
  ],
  "externalBioEntities": [
    { "record": "# TANIQUETIL ALPHAFOLD PROVENANCE: AF-P04637-F1 (TP53 | Mean pLDDT: 67.5)" }
  ],
  "attestationDigest": "7d793037a0760186574b0282f2f435e7090a6c4d66e83a0961ab7434b7b4a2f8"
}
```
