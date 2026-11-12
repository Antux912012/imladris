<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# WIKI 02 // AREKYER: GALAXY-TO-QUARTO PROVENANCE BRIDGE

**Document ID:** IML-WIKI-002  
**Standard:** ASD-STE100 (Simplified Technical English)  
**Component:** `Imladris.Bridges.Arekyer`  
**Applicable Formats:** Quarto (`.qmd`), RMarkdown (`.Rmd`)  

---

## 1. PURPOSE OF THE SYSTEM

**Arekyer** is the asynchronous data bridge inside the Imladris scientific workbench. Arekyer connects upstream cloud bioinformatics histories (**Galaxy Project**, including `usegalaxy.eu`, `usegalaxy.org`, `usegalaxy.org.au`, and private institutional servers) to local reproducible documents (`.qmd` and `.Rmd`).

Scientists frequently download tabular files manually from Galaxy. Manual downloads break data provenance between the cloud alignment and the manuscript. Arekyer reads remote Galaxy metadata directly and injects verified R or Python data-fetching code chunks into the local document.

```text
+-------------------+      HTTPS / REST API      +----------------------------+
|  Galaxy Instance  | <------------------------> |   Imladris.Bridges.Arekyer |
| (usegalaxy.eu/org)|      /api/whoami           | (libsoup-3.0 + json-glib)  |
+-------------------+      /api/histories        +----------------------------+
                           /api/datasets                       |
                                                               v
+-------------------+   Single-Click Injection   +----------------------------+
| Source Buffer Q1  | <------------------------> |   Arekyer Bridge Panel     |
| (.qmd / .Rmd)     |   arekyer-galaxy-{hid}     |   [ + R ]      [ + Py ]    |
+-------------------+                            +----------------------------+
          |
          v (Compile Time: quarto render)
+-----------------------------------------------------------------------------+
| GLib.SubprocessLauncher <- libsecret-1 (org.freedesktop.Secret.Service)     |
| Injects GALAXY_API_KEY exclusively into isolated child process memory       |
+-----------------------------------------------------------------------------+
```

---

## 2. SYSTEM ARCHITECTURE

| Subsystem | Library / Stack | Source File | Function |
| :--- | :--- | :--- | :--- |
| **Bridge Facade** | `GLib.Object`, `GtkSourceView-5` | `src/bridges/ArekyerBridge.vala` | Coordinates client calls, buffer insertion, and subprocess credential injection. |
| **Network Client** | `libsoup-3.0`, `json-glib-1.0` | `src/bridges/galaxy_client.vala` | Sends asynchronous HTTP GET requests to the Galaxy REST API. |
| **Credential Vault** | `libsecret-1` | `src/bridges/galaxy_client.vala` | Stores the Galaxy API key in the native Linux OS keyring (`org.ardatech.Imladris.GalaxyApiKey`). |
| **Provenance Injector** | `GtkSourceView-5` | `src/bridges/galaxy_chunk_generator.vala` | Inserts R or Python code blocks with dataset UUID/HID metadata into the active `.qmd` buffer. |
| **Subprocess Environment** | `GLib.SubprocessLauncher` | `src/core/PlatformUtils.vala` | Passes the `GALAXY_API_KEY` environment variable to the `quarto render` process at compile time. |

---

## 3. SECURITY AND CREDENTIAL MANAGEMENT

> [!WARNING]
> Do not write plain-text Galaxy API keys into `.qmd` or `.Rmd` source files. Exposed keys cause security breaches when you push code to Git repositories.

1. Arekyer stores the Galaxy API key in the system keyring (`org.freedesktop.Secret.Service`) under schema `org.ardatech.Imladris.GalaxyApiKey`.
2. The injected R and Python code chunks read the key dynamically from the `GALAXY_API_KEY` environment variable (`Sys.getenv("GALAXY_API_KEY")` in R; `os.environ.get("GALAXY_API_KEY")` in Python).
3. When you compile the document or execute a chunk, Imladris reads the key from `libsecret-1` and injects it exclusively into the isolated subprocess memory space (`PlatformUtils.inject_galaxy_credentials`).
4. Running `imladris --purge-user-data` permanently erases all stored Galaxy credentials from the OS keyring in compliance with GDPR Article 17.

---

## 4. OPERATING PROCEDURE: CONNECTING A GALAXY DATASET

### 4.1 Configure the Galaxy Connection
1. Open the **Arekyer Bridge** panel in the right-hand dock (Quadrant 2 / Quadrant 3).
2. Click the **Settings (Gear)** button to open the Galaxy Connection modal.
3. Enter your Galaxy server URL (for example: `https://usegalaxy.eu`).
4. Enter your personal Galaxy API key in the **API Key** field.
5. Click **Verify & Save**. Arekyer validates your account via `/api/whoami`, saves the key to the OS keyring, and loads your available Galaxy Histories.

### 4.2 Inject a Reproducible Code Chunk
1. Select the target Galaxy History from the **History** drop-down menu.
2. Locate the processed dataset (for example: `DESeq2_Normalized_Counts.tsv`) in the dataset list.
3. Place your text cursor at the target line in the Quadrant 1 `.qmd` or `.Rmd` editor.
4. Click **[ + R ]** to insert an R data frame loader, or click **[ + Py ]** to insert a Python `pandas` loader.

---

## 5. PROVENANCE CODE OUTPUT SPECIFICATION

### 5.1 R Quarto Output (`[ + R ]`)
When you click **[ + R ]**, Arekyer inserts the following standardized block into the `.qmd` buffer:

````markdown
```{r arekyer-galaxy-43, message=FALSE}
# AREKYER PROVENANCE RECORD
# Server: https://usegalaxy.eu
# History ID: bbd44e69cb8906b5
# Dataset ID: f2db41e1fa331b3e (HID: 43 | Format: tabular)

galaxy_url <- "https://usegalaxy.eu/api/histories/bbd44e69cb8906b5/contents/f2db41e1fa331b3e/display"
req <- httr2::request(galaxy_url) |>
  httr2::req_headers("x-api-key" = Sys.getenv("GALAXY_API_KEY"))
resp <- httr2::req_perform(req)
galaxy_df_43 <- readr::read_tsv(httr2::resp_body_raw(resp), show_col_types = FALSE)
head(galaxy_df_43)
```
````

### 5.2 Python Quarto Output (`[ + Py ]`)
When you click **[ + Py ]**, Arekyer inserts the following standardized Python block:

````markdown
```{python arekyer-galaxy-43}
# AREKYER PROVENANCE RECORD
# Server: https://usegalaxy.eu
# History ID: bbd44e69cb8906b5
# Dataset ID: f2db41e1fa331b3e (HID: 43 | Format: tabular)

import os
import io
import requests
import pandas as pd

galaxy_url = "https://usegalaxy.eu/api/histories/bbd44e69cb8906b5/contents/f2db41e1fa331b3e/display"
resp = requests.get(
    galaxy_url,
    headers={"x-api-key": os.environ.get("GALAXY_API_KEY", "")},
    timeout=60
)
resp.raise_for_status()
galaxy_df_43 = pd.read_csv(io.BytesIO(resp.content), sep="\t")
galaxy_df_43.head()
```
````

### 5.3 Binary Bioinformatics Formats (`bam`, `fastq.gz`, `vcf`, `h5ad`)
For non-tabular binary datasets, Arekyer automatically generates a local cache check under `./data/galaxy/` so large alignment files are downloaded only once and assigned to `galaxy_file_{hid}`.
