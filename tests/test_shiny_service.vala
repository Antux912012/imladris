// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Imladris.Services;
using Imladris.Core;

public static int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/Imladris/Shiny/Detection", () => {
        var service = ShinyService.get_default ();

        assert (service.is_shiny_file ("app.R"));
        assert (service.is_shiny_file ("server.R"));
        assert (service.is_shiny_file ("ui.R"));
        assert (service.is_shiny_file ("APP.r"));

        assert (!service.is_shiny_file ("script.R", "x <- 1 + 1\nprint(x)"));
        assert (service.is_shiny_file ("script.R", "library(shiny)\nui <- fluidPage()\nserver <- function(input, output) {}\nshinyApp(ui, server)"));
        assert (service.is_shiny_file ("dashboard.Rmd", "---\ntitle: 'Dashboard'\nruntime: shiny\n---\n"));
        assert (service.is_shiny_file ("report.qmd", "---\ntitle: 'Report'\nserver: shiny\n---\n"));
    });

    Test.add_func ("/Imladris/Shiny/StatusAndTargets", () => {
        var service = ShinyService.get_default ();
        assert (service.status == ShinyAppStatus.STOPPED);
        assert (ShinyAppStatus.STOPPED.to_badge_label () == "○ Idle");
        assert (ShinyAppStatus.RUNNING.to_badge_label () == "● Live");
        assert (ShinyAppStatus.STARTING.to_badge_label () == "Starting...");

        assert (ShinyViewerTarget.VIEWER_PANE.to_label () == "Viewer Pane (Quadrant 4)");
        assert (ShinyViewerTarget.DEDICATED_WINDOW.to_label () == "Dedicated Window");
        assert (ShinyViewerTarget.EXTERNAL_BROWSER.to_label () == "External Web Browser");
    });

    Test.add_func ("/Imladris/Shiny/TemplateScaffolding", () => {
        string tpl = Imladris.ProjectScaffolder.get_shiny_template ("Test Shiny App");
        assert (tpl.contains ("library(shiny)"));
        assert (tpl.contains ("library(bslib)"));
        assert (tpl.contains ("page_sidebar("));
        assert (tpl.contains ("shinyApp(ui = ui, server = server)"));
        assert (tpl.contains ("Test Shiny App"));
    });

    Test.add_func ("/Imladris/Shiny/UrlRegexMatch", () => {
        try {
            var url_regex = new Regex ("Listening on (http://[0-9a-zA-Z.:]+)");
            string sample_log = "Loading required package: shiny\nListening on http://127.0.0.1:4213\n";
            MatchInfo mi;
            assert (url_regex.match (sample_log, 0, out mi));
            string url = mi.fetch (1);
            assert (url == "http://127.0.0.1:4213");
        } catch (RegexError e) {
            assert_not_reached ();
        }
    });

    return Test.run ();
}
