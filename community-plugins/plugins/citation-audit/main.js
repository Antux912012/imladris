// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

function escapeHtml(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function onload() {
    imladris.ui.addRibbonButton({
        id: "audit-citations",
        label: "Cite Audit",
        icon: "accessories-dictionary-symbolic",
        onClick: function () {
            var text = imladris.editor.getText() || "";
            var citeMatches = text.match(/@[a-zA-Z][a-zA-Z0-9_:-]*/g) || [];
            var xrefs = [];
            var cites = [];
            var seen = {};
            for (var i = 0; i < citeMatches.length; i++) {
                var token = citeMatches[i];
                if (seen[token]) continue;
                seen[token] = true;
                if (/^@(fig|tbl|sec|eq|lst)-/.test(token)) {
                    xrefs.push(token);
                } else {
                    cites.push(token);
                }
            }
            var citeItems = cites.length > 0
                ? cites.map(function (c) { return "<li><code>" + escapeHtml(c) + "</code></li>"; }).join("")
                : "<li><em>No @citekey references found.</em></li>";
            var xrefItems = xrefs.length > 0
                ? xrefs.map(function (x) { return "<li><code>" + escapeHtml(x) + "</code></li>"; }).join("")
                : "<li><em>No @fig-/@tbl-/@sec-/@eq- cross-references found.</em></li>";

            var html = "<!DOCTYPE html><html><head><meta charset='utf-8'><style>"
                + "body{font-family:system-ui,sans-serif;padding:24px;background:#1e1e24;color:#f3f4f6;}"
                + "h2{margin-top:0;color:#88c0d0;} h3{color:#a3be8c;margin-top:20px;}"
                + "ul{line-height:1.7;} code{background:#2e3440;padding:2px 6px;border-radius:4px;}"
                + ".summary{background:#2e3440;padding:12px 16px;border-radius:8px;margin-bottom:16px;}"
                + "</style></head><body>"
                + "<h2>Manuscript Citation &amp; Cross-Reference Audit</h2>"
                + "<div class='summary'><strong>Unique Citations:</strong> " + cites.length
                + " &nbsp;|&nbsp; <strong>Cross-References:</strong> " + xrefs.length + "</div>"
                + "<h3>Bibliography Citations</h3><ul>" + citeItems + "</ul>"
                + "<h3>Document Cross-References</h3><ul>" + xrefItems + "</ul>"
                + "</body></html>";

            imladris.ui.openWebDialog({
                title: "Citation & Cross-Ref Audit",
                html: html,
                width: 680,
                height: 520
            });
        }
    });
}

function onunload() {
}
