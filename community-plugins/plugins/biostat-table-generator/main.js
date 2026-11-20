// Compiled from src/main.ts (TypeScript -> ES2019 for Imladris JSC.Context)
"use strict";
function buildSummaryChunk(datasetName) {
    var safeName = datasetName.trim().replace(/[^a-zA-Z0-9_.]/g, "") || "mtcars";
    return [
        "",
        "```{r}",
        "#| label: tbl-summary",
        "#| tbl-cap: \"Baseline summary statistics for " + safeName + "\"",
        "library(gt)",
        safeName + " |> head(10) |> gt() |> tab_header(title = \"" + safeName + " Summary\")",
        "```",
        ""
    ].join("\n");
}
function onload() {
    imladris.ui.addRibbonButton({
        id: "insert-apa-table",
        label: "APA Table",
        icon: "x-office-spreadsheet-symbolic",
        onClick: function () {
            var selected = imladris.editor.getSelectedText();
            var dataset = selected && selected.trim().length > 0 ? selected.trim() : "mtcars";
            var chunk = buildSummaryChunk(dataset);
            imladris.editor.insertAtCursor(chunk);
            imladris.ui.showToast("Inserted publication gt() table chunk for '" + dataset + "'");
        }
    });
}
function onunload() {
}
