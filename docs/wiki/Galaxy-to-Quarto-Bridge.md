<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Galaxy-to-Quarto Provenance Bridge

This technical specification explains how Imladris connects upstream cloud bioinformatics histories to local reproducible documents.

---

## 1. Objective and Architecture

Researchers use cloud platforms like Galaxy to run upstream alignment and quantification pipelines. They then transfer data files locally for statistical analysis in R, Python, and Quarto. 

Manual file downloads break data provenance and cause reproducibility errors. The Imladris Galaxy Bridge automates this process through direct REST API communication.

```text
+-------------------+      HTTPS / REST API      +-----------------------+
|  Galaxy Instance  | <------------------------> | Imladris GalaxyClient |
| (usegalaxy.eu/org)|      /api/histories        | (Soup.Session async)  |
+-------------------+      /api/datasets         +-----------------------+
                                                             |
                                                             v
+-------------------+   Single-Click Injection   +-----------------------+
| Source Buffer Q1  | <------------------------> | Galaxy Inspector Q3   |
| (.qmd / .Rmd)     |      R / Python Chunk      | (History / Datasets)  |
+-------------------+                            +-----------------------+
```

---

## 2. API Endpoints and Data Contracts

The client communicates through the standard Galaxy REST API:

| Endpoint | Method | Purpose | Authentication |
| :--- | :--- | :--- | :--- |
| `/api/whoami` | `GET` | Verifies user identity and validates the API key. | `x-api-key: <KEY>` |
| `/api/histories` | `GET` | Retrieves active user histories. | `x-api-key: <KEY>` |
| `/api/histories/{id}/contents` | `GET` | Lists all datasets within a specific history. | `x-api-key: <KEY>` |
| `/api/datasets/{id}` | `GET` | Fetches dataset metadata (format, size, state). | `x-api-key: <KEY>` |
| `/api/datasets/{id}/display` | `GET` | Streams dataset contents for analysis. | `x-api-key: <KEY>` |

---

## 3. Security and Credential Storage

Imladris follows strict European regulatory standards (GDPR and Cyber Resilience Act):

1. **Zero Hardcoded Secrets**: Imladris never embeds server credentials in source code or persistent logs.
2. **Environment Variable Override**: Users can define `GALAXY_SERVER_URL` and `GALAXY_API_KEY` in environment variables.
3. **Restricted Storage**: Imladris stores user credentials in `$XDG_CONFIG_HOME/imladris/settings.ini` with `0600` (owner read/write only) file permissions.
4. **Local Execution**: The client dispatches network requests only when the user explicitly triggers a refresh or test action.

---

## 4. Reproducible Code Injection

When a researcher clicks **R** or **Py** on a dataset in the Galaxy panel, Imladris inserts an idiomatic code chunk into the active document at the cursor position.

### R Quarto Template (`httr`):

```r
```{r galaxy_pull_f2db41e1, message=FALSE}
# Imladris Provenance Anchor: Galaxy History `bbd44e69` Dataset `f2db41e1`
# Server: `https://usegalaxy.eu`
library(httr)

imladris_fetch_dataset <- function(file_url, api_key) {
  response <- GET(file_url, add_headers("X-API-Key" = api_key))
  content(response, "text", encoding = "UTF-8")
}

# Fetch dataset into local dataframe
df_deseq2_normalized_counts_tsv <- read.delim(
  text = imladris_fetch_dataset("https://usegalaxy.eu/api/datasets/f2db41e1/display", Sys.getenv("GALAXY_API_KEY")),
  header = TRUE,
  sep = "\t"
)
```
```

### Python Quarto Template (`requests` / `pandas`):

```python
```{python galaxy_pull_f2db41e1}
# Imladris Provenance Anchor: Galaxy History `bbd44e69` Dataset `f2db41e1`
# Server: `https://usegalaxy.eu`
import os
import io
import requests
import pandas as pd

api_key = os.environ.get("GALAXY_API_KEY", "")
headers = {"X-API-Key": api_key} if api_key else {}
response = requests.get("https://usegalaxy.eu/api/datasets/f2db41e1/display", headers=headers)
response.raise_for_status()

# Fetch dataset into local dataframe
df_deseq2_normalized_counts_tsv = pd.read_csv(io.StringIO(response.text), sep="\t")
```
```

---

## 5. UI Integration in the Workbench

1. **Quadrant 3 Docking**: The Galaxy panel docks natively in Quadrant 3 alongside the Citations and Environment inspectors.
2. **Dynamic Badging**: Dataset states display color-coded status badges:
   * **Green**: Complete and verified (`ok`).
   * **Blue**: Pending execution (`queued`).
   * **Orange**: Running computation (`running`).
   * **Red**: Execution failure (`error`).
3. **Filtering**: The search bar filters histories and dataset names in real time.
