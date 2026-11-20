// Compiled from src/main.ts (TypeScript -> ES2019 for Imladris JSC.Context)
"use strict";
function wrapCallout(kind, body) {
    var title = kind === "note" ? "Note" : "Important";
    var content = body.trim().length > 0 ? body.trim() : "Write your key takeaway here.";
    return "\n::: {.callout-" + kind + "}\n## " + title + "\n" + content + "\n:::\n";
}
function onload() {
    imladris.ui.addRibbonButton({
        id: "insert-callout-note",
        label: "Callout",
        icon: "dialog-information-symbolic",
        onClick: function () {
            var sel = imladris.editor.getSelectedText();
            imladris.editor.insertAtCursor(wrapCallout("note", sel));
            imladris.ui.showToast("Inserted Quarto callout block.");
        }
    });
}
function onunload() {
}
