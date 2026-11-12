// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: High-level Galaxy-to-Quarto and RMarkdown provenance bridge.
 *
 * Architectural Position:
 * Core bridge component inside the Imladris.Bridges.Arekyer namespace.
 * Connects upstream cloud bioinformatics histories (Galaxy Project) to local
 * reproducible manuscripts (.qmd and .Rmd). Coordinates GalaxyClient (network requests,
 * libsoup-3.0, json-glib-1.0), OS Keyring credentials (libsecret-1), and standardized
 * reproducible code chunk synthesis.
 *
 * Concurrency Constraints:
 * Executes on the GLib MainContext thread. Asynchronous network operations run non-blocking.
 */

using GLib;
using GtkSource;

namespace Imladris.Bridges.Arekyer {

    /**
     * Arekyer provenance bridge connecting upstream cloud bioinformatics
     * histories to local reproducible Quarto (.qmd) and RMarkdown (.Rmd) documents.
     */
    public class ArekyerBridge : GLib.Object {

        private static ArekyerBridge? instance = null;

        /**
         * Low-level Galaxy REST API client instance.
         */
        public GalaxyClient client { get; private set; }

        /**
         * Returns the singleton instance of ArekyerBridge.
         *
         * @return Shared ArekyerBridge reference.
         */
        public static ArekyerBridge get_default () {
            if (instance == null) {
                instance = new ArekyerBridge ();
            }
            return instance;
        }

        /**
         * Constructs a new ArekyerBridge instance.
         */
        public ArekyerBridge () {
            this.client = GalaxyClient.get_default ();
        }

        /**
         * Generates a standardized Arekyer provenance code block for a Galaxy dataset.
         *
         * @param dataset Remote Galaxy dataset descriptor.
         * @param history_name Parent history title.
         * @param lang Target language (R or Python).
         * @return Standardized Quarto code block string.
         */
        public string generate_provenance_chunk (
            GalaxyDataset dataset,
            string history_name,
            TargetLanguage lang
        ) {
            return GalaxyChunkGenerator.generate_chunk (
                dataset,
                client.server_url,
                history_name,
                lang
            );
        }

        /**
         * Injects a verified data-fetching code block into an active GtkSource.Buffer.
         *
         * @param buffer Target text buffer of the active editor.
         * @param chunk_code Formatted code block string.
         */
        public void inject_into_buffer (GtkSource.Buffer buffer, string chunk_code) {
            buffer.begin_user_action ();
            Gtk.TextIter cursor_iter;
            buffer.get_iter_at_mark (out cursor_iter, buffer.get_insert ());
            string formatted = "\n" + chunk_code.strip () + "\n\n";
            buffer.insert (ref cursor_iter, formatted, -1);
            buffer.end_user_action ();
        }

        /**
         * Injects credentials from system keyring into a SubprocessLauncher environment.
         *
         * @param launcher Process launcher to configure with GALAXY_API_KEY.
         */
        public void inject_credentials_to_launcher (GLib.SubprocessLauncher launcher) {
            Core.PlatformUtils.inject_galaxy_credentials (launcher);
        }
    }
}
