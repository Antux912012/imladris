// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

function wrapCallout(kind: "note" | "important", body: string): string {
  const title = kind === "note" ? "Note" : "Important";
  const content = body.trim().length > 0 ? body.trim() : "Write your key takeaway here.";
  return `\n::: {.callout-${kind}}\n## ${title}\n${content}\n:::\n`;
}

function onload(): void {
  imladris.ui.addRibbonButton({
    id: "insert-callout-note",
    label: "Callout",
    icon: "dialog-information-symbolic",
    onClick: () => {
      const sel = imladris.editor.getSelectedText();
      imladris.editor.insertAtCursor(wrapCallout("note", sel));
      imladris.ui.showToast("Inserted Quarto callout block.");
    }
  });
}

function onunload(): void {
}
