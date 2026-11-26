// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Core {

    public class RewaitaPalette : GLib.Object {
        public string id { get; private set; }
        public string name { get; private set; }
        public bool is_dark { get; private set; }
        public bool is_default { get; private set; }
        public string window_bg { get; private set; }
        public string window_fg { get; private set; }
        public string view_bg { get; private set; }
        public string header_bg { get; private set; }
        public string card_bg { get; private set; }
        public string[] swatches { get; private set; }

        public RewaitaPalette (
            string id,
            string name,
            bool is_dark,
            bool is_default,
            string window_bg,
            string window_fg,
            string view_bg,
            string header_bg,
            string card_bg,
            string[] swatches
        ) {
            this.id = id;
            this.name = name;
            this.is_dark = is_dark;
            this.is_default = is_default;
            this.window_bg = window_bg;
            this.window_fg = window_fg;
            this.view_bg = view_bg;
            this.header_bg = header_bg;
            this.card_bg = card_bg;
            this.swatches = swatches;
        }
    }

    public class ThemePalettes : GLib.Object {

        private static Gee.ArrayList<RewaitaPalette>? _catalog = null;

        public static Gee.ArrayList<RewaitaPalette> get_catalog () {
            if (_catalog != null) return _catalog;
            _catalog = new Gee.ArrayList<RewaitaPalette> ();

            // Featured palettes (first 6 shown by default, matching Ptyxis)
            _catalog.add (new RewaitaPalette (
                "adwaita", "Adwaita (Default)", false, true,
                "#fafafa", "#2e3436", "#ffffff", "#ebebeb", "#ffffff",
                { "#e01b24", "#33d17a", "#f6d32d", "#3584e4", "#9141ac", "#2190a4" }
            ));
            _catalog.add (new RewaitaPalette (
                "catppuccin-mocha", "Catppuccin Mocha", true, false,
                "#1e1e2e", "#cdd6f4", "#181825", "#11111b", "#313244",
                { "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5" }
            ));
            _catalog.add (new RewaitaPalette (
                "nord", "Nord", true, false,
                "#2e3440", "#eceff4", "#272c36", "#242933", "#3b4252",
                { "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0" }
            ));
            _catalog.add (new RewaitaPalette (
                "dracula", "Dracula", true, false,
                "#282a36", "#f8f8f2", "#21222c", "#191a21", "#343746",
                { "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd" }
            ));
            _catalog.add (new RewaitaPalette (
                "tokyo-night", "Tokyo Night", true, false,
                "#1a1b26", "#c0caf5", "#16161e", "#13141c", "#24283b",
                { "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff" }
            ));
            _catalog.add (new RewaitaPalette (
                "gruvbox-dark", "Gruvbox Dark", true, false,
                "#282828", "#ebdbb2", "#1d2021", "#181a1b", "#32302f",
                { "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c" }
            ));

            // Extended Rewaita community palettes (revealed via "Show All Palettes")
            _catalog.add (new RewaitaPalette (
                "catppuccin-latte", "Catppuccin Latte", false, false,
                "#eff1f5", "#4c4f69", "#ffffff", "#e6e9ef", "#dce0e8",
                { "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#8839ef", "#179299" }
            ));
            _catalog.add (new RewaitaPalette (
                "gruvbox-light", "Gruvbox Light", false, false,
                "#fbf1c7", "#3c3836", "#f9f5d7", "#f2e5bc", "#ebdbb2",
                { "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a" }
            ));
            _catalog.add (new RewaitaPalette (
                "tokyo-night-day", "Tokyo Night Day", false, false,
                "#e1e2e7", "#1f2335", "#ebecf0", "#d5d6db", "#ffffff",
                { "#f52a65", "#587539", "#8c6c3e", "#2e7de9", "#9854f1", "#007197" }
            ));
            _catalog.add (new RewaitaPalette (
                "solarized-dark", "Solarized Dark", true, false,
                "#002b36", "#93a1a1", "#00212b", "#073642", "#073642",
                { "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198" }
            ));
            _catalog.add (new RewaitaPalette (
                "solarized-light", "Solarized Light", false, false,
                "#fdf6e3", "#586e75", "#ffffff", "#eee8d5", "#f5efdc",
                { "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198" }
            ));
            _catalog.add (new RewaitaPalette (
                "kanagawa", "Kanagawa", true, false,
                "#1f1f28", "#dcd7ba", "#16161d", "#16161d", "#2a2a37",
                { "#c34043", "#76946a", "#c0a36e", "#7e9cd8", "#957fb8", "#6a9589" }
            ));
            _catalog.add (new RewaitaPalette (
                "everforest-dark", "Everforest Dark", true, false,
                "#2d353b", "#d3c6aa", "#232a2e", "#1e2326", "#343f44",
                { "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092" }
            ));
            _catalog.add (new RewaitaPalette (
                "rose-pine", "Rosé Pine", true, false,
                "#191724", "#e0def4", "#1f1d2e", "#16141f", "#26233a",
                { "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba" }
            ));
            _catalog.add (new RewaitaPalette (
                "one-dark", "One Dark", true, false,
                "#282c34", "#abb2bf", "#21252b", "#1e2227", "#2c313c",
                { "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2" }
            ));
            _catalog.add (new RewaitaPalette (
                "eldritch", "Eldritch", true, false,
                "#212337", "#ebfafa", "#171928", "#141624", "#292e42",
                { "#f16c75", "#37f499", "#f7c67f", "#04d1f9", "#a48cf2", "#7081d0" }
            ));
            _catalog.add (new RewaitaPalette (
                "material-palenight", "Material Palenight", true, false,
                "#292d3e", "#a6accd", "#202331", "#1b1e2b", "#32374d",
                { "#f07178", "#c3e88d", "#ffcb6b", "#82aaff", "#c792ea", "#89ddff" }
            ));
            _catalog.add (new RewaitaPalette (
                "monokai-pro", "Monokai Pro", true, false,
                "#2d2a2e", "#fcfcfa", "#221f22", "#19181a", "#383539",
                { "#ff6188", "#a9dc76", "#ffd866", "#fc9867", "#ab9df2", "#78dce8" }
            ));

            return _catalog;
        }

        public static RewaitaPalette? find_by_id (string id) {
            string norm = id.strip ().down ();
            foreach (var p in get_catalog ()) {
                if (p.id == norm) return p;
            }
            return null;
        }
    }
}
