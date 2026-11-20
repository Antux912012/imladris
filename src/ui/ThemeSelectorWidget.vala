// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Imladris.Core;

namespace Imladris.UI {

    /**
     * ThemeSelectorWidget renders circular theme swatches matching GNOME/Libadwaita
     * style switchers:
     * [ System Theme (diagonal split) | Light | Eye Friendly (Sepia) | Dark ]
     * with an active outline and bottom-right checkmark badge on the selected swatch.
     */
    public class ThemeSelectorWidget : Gtk.Box {

        private SettingsManager settings;
        private ulong theme_changed_hid = 0;

        private Gtk.Button btn_system;
        private Gtk.Button btn_light;
        private Gtk.Button btn_sepia;
        private Gtk.Button btn_dark;

        private Gtk.Image check_system;
        private Gtk.Image check_light;
        private Gtk.Image check_sepia;
        private Gtk.Image check_dark;

        public signal void theme_selected (AppTheme theme);

        public override void dispose () {
            if (theme_changed_hid != 0) {
                settings.disconnect (theme_changed_hid);
                theme_changed_hid = 0;
            }
            base.dispose ();
        }

        public ThemeSelectorWidget () {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
            this.valign = Gtk.Align.CENTER;
            this.settings = SettingsManager.get_default ();

            btn_system = create_theme_button (AppTheme.SYSTEM, "theme-circle-system", "System Theme", out check_system);
            btn_light = create_theme_button (AppTheme.LIGHT, "theme-circle-light", "Light", out check_light);
            btn_sepia = create_theme_button (AppTheme.EYE_FRIENDLY, "theme-circle-sepia", "Eye Friendly", out check_sepia);
            btn_dark = create_theme_button (AppTheme.DARK, "theme-circle-dark", "Dark", out check_dark);

            this.append (btn_system);
            this.append (btn_light);
            this.append (btn_sepia);
            this.append (btn_dark);

            update_selection (settings.app_theme);

            theme_changed_hid = settings.theme_changed.connect ((theme) => {
                update_selection (theme);
            });
        }

        private Gtk.Button create_theme_button (AppTheme theme, string circle_css_class, string tooltip, out Gtk.Image check_icon) {
            var btn = new Gtk.Button ();
            btn.add_css_class ("flat");
            btn.add_css_class ("theme-swatch-button");
            btn.tooltip_text = tooltip;
            btn.valign = Gtk.Align.CENTER;

            var overlay = new Gtk.Overlay ();

            var circle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            circle.add_css_class ("theme-circle");
            circle.add_css_class (circle_css_class);
            overlay.set_child (circle);

            check_icon = new Gtk.Image.from_icon_name ("emblem-ok-symbolic") {
                pixel_size = 10,
                halign = Gtk.Align.END,
                valign = Gtk.Align.END,
                visible = false
            };
            check_icon.add_css_class ("theme-badge-check");
            overlay.add_overlay (check_icon);

            btn.set_child (overlay);

            btn.set_data<int> ("theme-val", (int) theme);
            unowned ThemeSelectorWidget self_ref = this;
            btn.clicked.connect ((b) => {
                AppTheme chosen = (AppTheme) b.get_data<int> ("theme-val");
                self_ref.settings.app_theme = chosen;
                self_ref.theme_selected (chosen);
            });

            return btn;
        }

        private void update_selection (AppTheme active_theme) {
            btn_system.remove_css_class ("is-selected");
            btn_light.remove_css_class ("is-selected");
            btn_sepia.remove_css_class ("is-selected");
            btn_dark.remove_css_class ("is-selected");

            check_system.visible = (active_theme == AppTheme.SYSTEM);
            check_light.visible = (active_theme == AppTheme.LIGHT);
            check_sepia.visible = (active_theme == AppTheme.EYE_FRIENDLY);
            check_dark.visible = (active_theme == AppTheme.DARK);

            switch (active_theme) {
                case AppTheme.SYSTEM:
                    btn_system.add_css_class ("is-selected");
                    break;
                case AppTheme.LIGHT:
                    btn_light.add_css_class ("is-selected");
                    break;
                case AppTheme.EYE_FRIENDLY:
                    btn_sepia.add_css_class ("is-selected");
                    break;
                case AppTheme.DARK:
                    btn_dark.add_css_class ("is-selected");
                    break;
            }
        }
    }
}
