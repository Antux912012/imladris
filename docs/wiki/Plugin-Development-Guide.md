<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: Apache-2.0
-->

# Plugin Development & Publishing Guide (TypeScript & JavaScript)

Imladris features a sandboxed, Obsidian-inspired extension system powered by **JavaScriptCore (`JSC.Context`)**. Third-party developers can author extensions in **TypeScript** (recommended, with full type definitions) or **JavaScript**, test them locally, and publish them directly to the **Imladris Community Plugins Registry** so every user can search and install them in one click from inside the app.

> [!NOTE]
> **Licensing Freedom (Apache-2.0 Hybrid Open-Core):** Third-party extensions communicating through the `imladris.*` JavaScript API are independent works. You may license your plugin under **any license** you prefer (Apache-2.0, MIT, BSD, GPLv3, or internal proprietary enterprise license).

---

## 1. How Plugins Work in Imladris

Every plugin runs inside its own isolated `JSC.Context` virtual machine with:
- A declarative **`manifest.json`** declaring metadata and explicit permissions (`editor`, `repl_r`, `repl_python`, `elrond_ai`, `workspace`, `ui`).
- A compiled ES2019 entry point **`main.js`** exposing two global lifecycle hooks: **`onload()`** and **`onunload()`**.
- A host API object **`imladris`** (`imladris.ui`, `imladris.editor`, `imladris.repl`, `imladris.elrond`, `imladris.workspace`, `imladris.plugin`).
- Native **GNOME HIG** & **Papirus symbolic icons** so extensions match both Light and Dark themes seamlessly.

---

## 2. Option A: Creating a Plugin in TypeScript (Recommended)

Imladris ships official TypeScript ambient declarations at [`community-plugins/types/imladris.d.ts`](https://github.com/Antux912012/imladris/blob/main/community-plugins/types/imladris.d.ts).

### Step 1 — Scaffold Your Plugin Folder

```text
my-biostat-plugin/
├── manifest.json
├── tsconfig.json
├── src/
│   └── main.ts
└── main.js          # Compiled output loaded by Imladris
```

### Step 2 — Create `manifest.json`

```json
{
  "id": "my-biostat-plugin",
  "name": "APA & Lancet Table Formatter",
  "version": "1.0.0",
  "author": "Your Name or Lab",
  "description": "Inserts publication-ready gt() and gtsummary R summary tables for the selected dataframe.",
  "license": "Apache-2.0",
  "icon": "x-office-spreadsheet-symbolic",
  "permissions": [
    "editor",
    "repl_r"
  ]
}
```

#### Available Permissions
| Permission | Capability Granted |
| :--- | :--- |
| `"editor"` | Read active document/selection and insert text at cursor (`imladris.editor.*`) |
| `"repl_r"` | Execute R code in the persistent R session (`imladris.repl.runR`) |
| `"repl_python"` | Execute Python code in the persistent Python session (`imladris.repl.runPython`) |
| `"elrond_ai"` | Send prompts to Elrond AI Assistant (`imladris.elrond.ask`) |
| `"workspace"` | List, read, and open files inside the active project root (`imladris.workspace.*`) |
| `"ui"` | Open custom HTML5/Canvas/WebGL modal dialogs (`imladris.ui.openWebDialog`) |

> [!IMPORTANT]
> `id` must be 1–64 characters containing only `a-z`, `A-Z`, `0-9`, `-`, and `_`. Always request the minimum set of permissions your plugin needs—users review every permission in a consent dialog before installing.

### Step 3 — Configure `tsconfig.json`

Because `JSC.Context` evaluates `main.js` as a single self-contained script (not an ES module with `import`/`export`), compile with `"module": "None"` and `"outFile": "./main.js"` (or bundle with `esbuild` using `--format=iife` if using npm helpers):

```json
{
  "compilerOptions": {
    "target": "ES2019",
    "module": "None",
    "strict": true,
    "outFile": "./main.js",
    "lib": ["ES2019"]
  },
  "include": ["src/main.ts", "../../types/imladris.d.ts"]
}
```

### Step 4 — Write `src/main.ts`

```typescript
// src/main.ts — Type-safe Imladris Plugin

function buildTableChunk(datasetName: string): string {
  const safe = datasetName.trim().replace(/[^a-zA-Z0-9_.]/g, "") || "mtcars";
  return [
    "",
    "```{r}",
    "#| label: tbl-summary",
    `#| tbl-cap: "Summary statistics for ${safe}"`,
    "library(gt)",
    `${safe} |> head(10) |> gt()`,
    "```",
    ""
  ].join("\n");
}

function onload(): void {
  imladris.ui.addRibbonButton({
    id: "insert-apa-table",
    label: "APA Table",
    icon: "x-office-spreadsheet-symbolic",
    onClick: () => {
      const selected = imladris.editor.getSelectedText();
      const dataset = selected && selected.trim().length > 0 ? selected.trim() : "mtcars";
      imladris.editor.insertAtCursor(buildTableChunk(dataset));
      imladris.ui.showToast(`Inserted APA table chunk for '${dataset}'`);
    }
  });
}

function onunload(): void {
  // Ribbon buttons are removed automatically by PluginManager
}
```

### Step 5 — Compile TypeScript to `main.js`

```bash
npx tsc -p tsconfig.json
```

*(If your plugin imports helper libraries, bundle them into a single file via `npx esbuild src/main.ts --bundle --target=es2019 --outfile=main.js` while exposing `globalThis.onload = onload` and `globalThis.onunload = onunload`.)*

---

## 3. Option B: Creating a Plugin in Plain JavaScript

For lightweight plugins without a build step, place `manifest.json` and `main.js` directly in your plugin folder:

```javascript
// main.js
function onload() {
    imladris.ui.addRibbonButton({
        id: "insert-iso-date",
        label: "ISO Date",
        icon: "alarm-symbolic",
        onClick: function () {
            var iso = new Date().toISOString().slice(0, 10);
            imladris.editor.insertAtCursor(iso);
            imladris.ui.showToast("Inserted " + iso);
        }
    });
}

function onunload() {
}
```

---

## 4. Testing Locally & Packaging `.implugin` Bundles

### Test Directly in Your Local Plugins Folder
Imladris automatically scans both directories at startup:
- **Native / Host install:** `~/.local/share/imladris/plugins/<your-plugin-id>/`
- **Flatpak install:** `~/.var/app/io.github.Antux912012.Imladris/data/imladris/plugins/<your-plugin-id>/` (and also reads `~/.local/share/imladris/plugins/`)

Copy `manifest.json` and `main.js` into that folder, then open **Preferences → Extensions** (`Ctrl+,`) and toggle your plugin on.

### Package a Shareable `.implugin` Bundle
```bash
zip -r my-biostat-plugin.implugin my-biostat-plugin/manifest.json my-biostat-plugin/main.js
```
Any user can install it offline via **Preferences → Extensions → Import Plugin…** (supports `.implugin` and `.zip`; symlinks and path traversal are strictly blocked).

---

## 5. Publishing Your Plugin to the Community Repository

Once your plugin works locally, publish it to **`Antux912012/imladris`** so **all Imladris users can find and install it in one click** from **Preferences → Extensions → Community Plugins** (or via **Command Palette → Browse Community Plugins…**).

### Step-by-Step Pull Request Workflow

1. **Fork & Branch:**
   ```bash
   git clone https://github.com/<your-username>/imladris.git
   cd imladris
   git checkout -b plugin/my-biostat-plugin
   ```

2. **Add Your Plugin Folder under `community-plugins/plugins/<id>/`:**
   ```text
   community-plugins/plugins/my-biostat-plugin/
   ├── manifest.json       # Required
   ├── main.js             # Required (compiled ES2019 JS)
   ├── tsconfig.json       # Recommended if written in TypeScript
   └── src/
       └── main.ts         # Recommended TypeScript source for transparency
   ```

3. **Register Your Plugin in `community-plugins/registry.json`:**
   Add an entry inside the `"plugins"` array:
   ```json
   {
     "id": "my-biostat-plugin",
     "name": "APA & Lancet Table Formatter",
     "version": "1.0.0",
     "author": "Your Name",
     "description": "Inserts publication-ready gt() and gtsummary R summary tables.",
     "license": "Apache-2.0",
     "icon": "x-office-spreadsheet-symbolic",
     "category": "Biostatistics",
     "language": "TypeScript",
     "tags": ["r", "tables", "apa", "gt", "clinical"],
     "permissions": ["editor", "repl_r"],
     "homepage": "https://github.com/Antux912012/imladris/tree/main/community-plugins/plugins/my-biostat-plugin",
     "files": {
       "manifest": "community-plugins/plugins/my-biostat-plugin/manifest.json",
       "main": "community-plugins/plugins/my-biostat-plugin/main.js"
     }
   }
   ```
   *(Optional: If your plugin includes static assets such as HTML/CSS templates, add an `"assets": { "template.html": "community-plugins/plugins/<id>/template.html" }` map inside `"files"`. If you host releases on your own GitHub repo, you may alternatively provide an HTTPS `"archive_url"` pointing to a `.implugin` release zip.)*

4. **Review Checklist Before Opening Your PR:**
   - [ ] `manifest.json` `id` matches the folder name and `registry.json` `id`.
   - [ ] `main.js` is freshly compiled and contains no syntax errors or external `require()`/`import` statements.
   - [ ] All requested `permissions` are minimal and accurately declared in both `manifest.json` and `registry.json`.
   - [ ] No hardcoded secrets, tracking pixels, or insecure `http://` URLs.

5. **Open a Pull Request** against `main` on [`Antux912012/imladris`](https://github.com/Antux912012/imladris/pulls). As soon as the PR is merged, Imladris fetches the updated `community-plugins/registry.json` automatically and your extension appears in the in-app **Community Plugins** search!

---

## 6. Installing Community Plugins Inside Imladris

1. Open **Preferences (`Ctrl+,`) → Extensions** (or press `Ctrl+Shift+P` and run **Browse Community Plugins…**).
2. Type keywords into the **Community Plugins** search box (searches by name, description, author, category, tags, or `TypeScript` / `JavaScript`).
3. Expand any result to inspect its description, requested permissions, tags, and GitHub source link.
4. Click **Install**, review and approve the permission consent prompt, and the plugin is downloaded, validated, and activated immediately in your Ribbon!

---

## Next Steps
- Explore every host method in the [[Plugin API Reference|Plugin-API-Reference]].
- Inspect working TypeScript and JavaScript reference plugins in [`community-plugins/plugins/`](https://github.com/Antux912012/imladris/tree/main/community-plugins/plugins).
