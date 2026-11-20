// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

function buildSummaryChunk(datasetName: string): string {
  const safeName = datasetName.trim().replace(/[^a-zA-Z0-9_.]/g, "") || "mtcars";
  return [
    "",
    "```{r}",
    "#| label: tbl-summary",
    `#| tbl-cap: "Baseline summary statistics for ${safeName}"`,
    "library(gt)",
    `${safeName} |> head(10) |> gt() |> tab_header(title = "${safeName} Summary")`,
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
      const chunk = buildSummaryChunk(dataset);
      imladris.editor.insertAtCursor(chunk);
      imladris.ui.showToast(`Inserted publication gt() table chunk for '${dataset}'`);
    }
  });
}

function onunload(): void {
  // Ribbon buttons are cleaned up automatically by PluginManager
}
