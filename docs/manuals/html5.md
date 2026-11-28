# HTML5 Semantic & Baseline Reference

Write standards-compliant HTML5 documents with native top-layer `<dialog>`, `<details>`, semantic figures, and explicit `color-scheme` metadata.

## Accessible Modal `<dialog>` with Inert Background

Opening a `<dialog>` via `showModal()` places it in the browser top layer, makes background elements inert, traps keyboard focus, and closes on `Escape`.

```html
<meta name="color-scheme" content="light dark">

<button id="open-audit" type="button">Inspect Audit Record</button>

<dialog id="audit-dialog" aria-labelledby="audit-title">
  <h2 id="audit-title">ALCOA+ Verification Record</h2>
  <p>SHA-256 checksum verified against source manuscript line 42.</p>
  <form method="dialog">
    <button autofocus type="submit">Close</button>
  </form>
</dialog>

<script>
  const dlg = document.getElementById("audit-dialog");
  document.getElementById("open-audit").addEventListener("click", () => dlg.showModal());
</script>
```
