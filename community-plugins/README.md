<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# Imladris Community Plugins Registry

This directory hosts the official **Imladris Community Plugins Registry** (`registry.json`), TypeScript ambient type definitions (`types/imladris.d.ts`), and community-contributed extensions (`plugins/<plugin-id>/`).

Every plugin merged into `registry.json` becomes **instantly searchable and 1-click installable** inside Imladris via **Preferences → Extensions → Community Plugins** (or Command Palette → *Browse Community Plugins…*).

## Quick Submission Checklist (Pull Request)

1. Fork [`Antux912012/imladris`](https://github.com/Antux912012/imladris) and create a branch (e.g., `plugin/my-plugin-id`).
2. Add your plugin under `community-plugins/plugins/<your-plugin-id>/` containing:
   - `manifest.json` (valid plugin `id`, `name`, `version`, `author`, `description`, `license`, `icon`, `permissions`)
   - `main.js` (compiled ES2019 JavaScript entry point defining `onload()` and `onunload()`)
   - Optional TypeScript source (`src/main.ts` + `tsconfig.json` referencing `../../types/imladris.d.ts`)
3. Add a metadata entry to [`community-plugins/registry.json`](registry.json).
4. Test locally by copying your folder into `~/.local/share/imladris/plugins/<your-plugin-id>/` (or importing a `.implugin` zip).
5. Open a Pull Request! See the full **[Plugin Development Guide](https://github.com/Antux912012/imladris/wiki/Plugin-Development-Guide)** for step-by-step TypeScript and JavaScript walkthroughs.
