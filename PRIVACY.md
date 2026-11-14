<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Privacy Policy & GDPR Compliance

Imladris is designed from first principles as a **local-first, private scientific computing studio and Markdown editor**. We believe your research, statistical models, datasets, and intellectual property belong entirely to you.

---

## 1. Zero Telemetry & No Remote Tracking
* **No Telemetry**: Imladris collects **zero** analytics, telemetry, diagnostics, or tracking data.
* **No "Phone Home" Calls**: The application does not contact remote servers on startup, during editing, or on application shutdown.
* **Status Bar Telemetry**: The telemetry displayed in the bottom status bar (`Elrond running on <model> - <RAM/VRAM> used`) is **strictly local hardware telemetry** gathered by polling the local process table (`/proc/<pid>/status` and sysfs) for the local `llama-server` process. It is never transmitted over any network interface.

---

## 2. Local-First Data Storage & User Ownership
* All notebooks, Quarto/RMarkdown files, `.mallorn` bundles, and sandboxed project environments are stored directly on your local file system.
* Configuration and index cache files are stored strictly within standard XDG user directories:
  * Configuration: `~/.config/imladris/`
  * Cache & Indices: `~/.cache/imladris/`
  * Downloaded Local Models: `~/.local/share/imladris/models/`
* **Package Index Caching**: Built-in default CRAN and PyPI package lists are bundled locally for offline autocomplete. Remote index caches (`~/.cache/imladris/indices/`) are refreshed from CRAN (`PACKAGES`) and PyPI (PEP 691 JSON) strictly on demand when explicitly requested by the user in the Packages Ribbon Manager. No network checks or updates are run during application startup.
* You retain complete ownership and control over all files created or cached by the application.

---

## 3. Artificial Intelligence: Local vs. Cloud Providers

### A. Elrond Assistance (Local AI Copilot)
* **100% Local Inference & No Cloud Fallback**: When using Elrond Assistance, inference runs on your machine via a local `llama-server` subprocess or local server (Ollama, LM Studio, Cherry Studio) over loopback (`localhost` / `127.0.0.1`). There is no silent fallback to cloud AI providers. If local inference is unavailable or fails, requests are never routed externally without explicit configuration.
* **Air-Gapped & Offline**: No document context, dataframes, prompts, or generated code are sent over the Internet. The model runs fully offline.

### B. Frontier Cloud AI & Free-Tier Providers
* **Strictly Opt-In**: Cloud AI features are disabled by default and require you to explicitly configure a provider or enter an API key.
* **Direct Encrypted Connections**: Requests are transmitted directly from your client to the provider’s official API endpoint over encrypted TLS (HTTPS). There are no intermediary proxy servers operated by Imladris.
* **Local Credential Storage**: API keys are stored only in your local configuration directory (`~/.config/imladris/ai_config.json`) with file access restricted to your local Linux user account (POSIX permissions `0600`).
* **Free-Tier Cloud AI APIs & Automatic Quota Failover**:
  When cloud providers return HTTP 429 (quota exhaustion or rate limiting), automatic failover across free-tier candidates (Groq, Cerebras, OpenRouter `:free`, GitHub Models) is strictly guarded. It requires explicit user privacy opt-in via `free_api_consent_accepted` (in `ai_config.json` or Preferences) before any prompt is transmitted to an alternate free cloud endpoint. Local FreeLLMAPI proxy failover (`localhost:8000`) remains internal and does not transmit data over the public internet.
* **GitHub Copilot OAuth Device Flow**:
  When authenticating with GitHub Copilot via OAuth Device Code Flow (`https://github.com/login/device`), the resulting token is stored in the Linux OS keyring (`org.freedesktop.Secret.Service` via `libsecret`) under the schema `io.github.Antux912012.Imladris.Copilot`. If Secret Service is unavailable, the token is written to `~/.config/imladris/copilot_token` with POSIX permissions `0600`.

---

## 4. GDPR & Data Protection Compliance

Under the European Union General Data Protection Regulation (GDPR) and equivalent privacy regulations:

* **Data Minimization (Art. 5(1)(c))**: The application does not collect, retain, or process personal data on external servers.
* **Integrity and Confidentiality (Art. 5(1)(f))**: All data is managed locally under user permissions; external API requests use TLS encryption.
* **Right of Access & Data Portability (Art. 15 & 20)**: All your files and project bundles are stored in open, human-readable formats (standard Markdown, YAML frontmatter, JSON, and standard `.tar.zst` or `.zip` for `.mallorn` archives).
* **Right to Erasure ("Right to be Forgotten", Art. 17)**: You can permanently erase all application data, caches, and state at any time by executing the deterministic command `imladris --purge-user-data` or by deleting the `~/.config/imladris`, `~/.cache/imladris`, and `~/.local/share/imladris` directories.

---

## 5. Open Source Licensing & Code Provenance
* **Core License**: Imladris is released under the **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.
* **Permissive (MIT) Compatibility**: Any integrated or referenced permissive libraries are fully compatible with and subsumed under GPLv3 terms.
* **Bundled Assets**: Bundled Papirus symbolic icons are distributed under the GNU GPLv3 license.
* **Flathub AI Disclosure**: In compliance with Flathub Generative AI policies, development transparency and code provenance details are explicitly documented in the project repository and release documentation.
