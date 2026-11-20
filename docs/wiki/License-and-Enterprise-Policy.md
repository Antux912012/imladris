<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# License & Enterprise Open-Core Policy

Imladris Core Desktop Studio (`v0.40.0+`) is free and open-source software distributed under the **Apache License, Version 2.0 (`Apache-2.0`)**, structured as a **Hybrid Open-Core** platform for both academic scientists and commercial R&D organizations.

---

## 1. Apache License 2.0 (Core Desktop Studio)

Under the **Apache License 2.0**, scientists, universities, and companies have the freedom to:
- **Use freely** in academic, clinical, governmental, and commercial R&D environments—including Fortune 500 pharma/biotech procurement pipelines without copyleft spillover.
- **Benefit from an explicit patent grant** (Section 3) and patent retaliation protection.
- **Modify and redistribute** the Core Desktop Studio in source or binary form, subject to preserving copyright, patent, trademark, and `NOTICE` attributions.

The complete license text is available at [`LICENSE`](https://github.com/Antux912012/imladris/blob/main/LICENSE) and [`NOTICE`](https://github.com/Antux912012/imladris/blob/main/NOTICE).

> [!NOTE]
> **Trademark Protection (Section 6):** The Apache-2.0 license does not grant permission to use the **Imladris** trade name, trademarks, or logos on third-party commercial forks beyond reasonable origin attribution.

---

## 2. Hybrid Open-Core & Extension Boundaries

Imladris separates the open-source Core Desktop Studio from external extensions and enterprise governance modules:

1. **JavaScriptCore Extensions (`.implugin` / `JSC.Context`):** Third-party plugins communicating via the `imladris.*` JavaScript API may be licensed under **any license** chosen by their authors (Apache-2.0, MIT, GPLv3, or proprietary internal corporate plugins).
2. **Model Context Protocol (`McpServer`) & Subprocess Bridges:** Out-of-process integrations (internal LIMS, ELN, clinical data lakes, or private LLM gateways) communicate over stdio/IPC and are independent works.
3. **Commercial Enterprise Pack:** Organizational governance features (Enterprise SSO, centralized GxP 21 CFR Part 11 audit/policy locks, and proprietary LIMS/ELN connectors) are offered under a separate Commercial Enterprise License.

---

## 3. Third-Party Project Credits & Inspirations

Imladris proudly acknowledges and builds upon inspirations from the wider scientific and open-source community:
- **RStudio / Posit**: Four-quadrant scientific workbench ergonomics and the `.Rproj` project format.
- **Project Jupyter**: Interactive notebook paradigms and reproducible computational science.
- **Apostrophe**: Calm, distraction-free markdown authoring interface.
- **Obsidian**: Modular, user-extensible JavaScript plugin architecture.
- **GNOME Foundation**: GTK4 and Libadwaita human interface guidelines.
- **LM Studio, Ollama & llama.cpp**: Offline, local, privacy-preserving AI inference.
- **Gemini & Claude Assistance**: Developed with Google Gemini and Anthropic Claude AI pair-programming assistance.
