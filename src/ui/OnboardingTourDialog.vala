// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: GNOME Tour-style first-launch onboarding carousel.
 * Architecture: Adw.Dialog hosting an Adw.Carousel of Adw.StatusPage slides,
 * persisted via SettingsManager.onboarding_tour_completed so it auto-launches once.
 * Concurrency: Executes on the GLib MainContext thread.
 */

using GLib;
using Gtk;

namespace Imladris.UI {

    public class OnboardingTourDialog : Adw.Dialog {

        public signal void tour_finished (bool open_toolchain_setup);

        private Adw.Carousel carousel;
        private Gtk.Button prev_btn;
        private Gtk.Button next_btn;
        private Gtk.Button skip_btn;
        private bool finished_emitted = false;
        private uint total_slides = 0;

        public OnboardingTourDialog () {
            Object (
                title: "Welcome to Imladris",
                content_width: 620,
                content_height: 520
            );
            build_ui ();
        }

        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar () {
                show_title = false
            };

            skip_btn = new Gtk.Button.with_label ("Skip");
            skip_btn.add_css_class ("flat");
            skip_btn.clicked.connect (() => {
                finish_tour (false);
            });
            header.pack_start (skip_btn);
            toolbar_view.add_top_bar (header);

            carousel = new Adw.Carousel () {
                hexpand = true,
                vexpand = true,
                allow_scroll_wheel = true,
                allow_mouse_drag = true,
                allow_long_swipes = true
            };

            add_slide (
                "io.github.Antux912012.Imladris",
                "Welcome to Imladris",
                "A native GTK4 & Libadwaita scientific workbench for Markdown, Quarto, R, Python, LaTeX, and TypeScript—built for speed without Electron overhead."
            );

            add_slide (
                "x-office-document-symbolic",
                "Publish-Ready LaTeX & Citations",
                "Start manuscripts with the top 10 publisher templates (IEEE, ACM, Nature, Elsevier, Springer LNCS, PLOS, APS, NeurIPS, ICML, MDPI) and 10 academic citation styles, plus DOI-to-BibTeX lookup (Ctrl+Shift+B)."
            );

            add_slide (
                "applications-science-symbolic",
                "Dual-Mode Scientific Workbench",
                "Write distraction-free in Apostrophe mode with live WebKitGTK 6.0 preview, or switch to the 4-quadrant RStudio Dock for interactive R & Python chunks, plots, environment inspection, and console."
            );

            add_slide (
                "x-office-presentation-symbolic",
                "Presentations, Math & Diagrams",
                "Create Beamer LaTeX decks, Marp/RevealJS Markdown slides, TypeScript presentations, and Typst posters. Compose equations in the Math & Chemistry Studio and diagrams in Mermaid Flow."
            );

            add_slide (
                "avatar-default-symbolic",
                "Elrond AI & Bioinformatics",
                "Connect local GGUF models (llama.cpp), cloud AI providers, Zotero/PubMed citations, and Galaxy workflows—all with isolated Micromamba & renv reproducible environments."
            );

            add_final_slide ();

            total_slides = carousel.get_n_pages ();

            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            main_box.append (carousel);

            var bottom_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                margin_top = 8,
                margin_bottom = 16,
                margin_start = 20,
                margin_end = 20
            };

            prev_btn = new Gtk.Button.with_label ("Previous") {
                sensitive = false
            };
            prev_btn.clicked.connect (() => {
                int pos = ((int) GLib.Math.round (carousel.position)).clamp (0, (int) total_slides - 1);
                if (pos > 0) {
                    carousel.scroll_to (carousel.get_nth_page ((uint) (pos - 1)), true);
                }
            });

            var dots = new Adw.CarouselIndicatorDots () {
                carousel = carousel,
                hexpand = true
            };

            next_btn = new Gtk.Button.with_label ("Next");
            next_btn.add_css_class ("suggested-action");
            next_btn.clicked.connect (() => {
                int pos = ((int) GLib.Math.round (carousel.position)).clamp (0, (int) total_slides - 1);
                if (pos + 1 < (int) total_slides) {
                    carousel.scroll_to (carousel.get_nth_page ((uint) (pos + 1)), true);
                } else {
                    finish_tour (false);
                }
            });

            bottom_bar.append (prev_btn);
            bottom_bar.append (dots);
            bottom_bar.append (next_btn);
            main_box.append (bottom_bar);

            carousel.page_changed.connect ((idx) => {
                prev_btn.sensitive = (idx > 0);
                bool is_last = (idx + 1 >= total_slides);
                next_btn.label = is_last ? "Start Writing" : "Next";
                skip_btn.visible = !is_last;
            });

            this.closed.connect (() => {
                if (!finished_emitted) {
                    finished_emitted = true;
                    Core.SettingsManager.get_default ().onboarding_tour_completed = true;
                    tour_finished (false);
                }
            });

            toolbar_view.set_content (main_box);
            this.set_child (toolbar_view);
        }

        private void add_slide (string icon_name, string heading, string body) {
            var status = new Adw.StatusPage () {
                icon_name = icon_name,
                title = heading,
                description = body,
                hexpand = true,
                vexpand = true
            };
            carousel.append (status);
        }

        private void add_final_slide () {
            var status = new Adw.StatusPage () {
                icon_name = "emblem-ok-symbolic",
                title = "You’re Ready to Explore",
                description = "Create a new document from the Welcome Dashboard, or configure your isolated R, Python, LaTeX, and Quarto toolchains.",
                hexpand = true,
                vexpand = true
            };

            if (!Core.ToolchainManager.get_default ().is_base_environment_installed ()) {
                var setup_btn = new Gtk.Button.with_label ("Set Up Scientific Toolchains…") {
                    halign = Gtk.Align.CENTER
                };
                setup_btn.add_css_class ("pill");
                setup_btn.clicked.connect (() => {
                    finish_tour (true);
                });
                status.set_child (setup_btn);
            }

            carousel.append (status);
        }

        private void finish_tour (bool open_toolchain_setup) {
            if (finished_emitted) return;
            finished_emitted = true;
            Core.SettingsManager.get_default ().onboarding_tour_completed = true;
            this.close ();
            tour_finished (open_toolchain_setup);
        }
    }
}
