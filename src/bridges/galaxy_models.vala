// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Defines domain data models for Galaxy histories and bioinformatics datasets.
 *
 * Architectural Position:
 * Foundation data transfer models for the Galaxy Bridge subsystem.
 * Downstream consumers: Imladris.GalaxyClient, Imladris.GalaxyChunkGenerator, and Imladris.GalaxyPanel.
 * Upstream dependencies: GLib.Object.
 *
 * Concurrency Constraints:
 * Thread-safe data objects. Code instantiates and accesses them on the GLib MainContext thread.
 */

using GLib;

namespace Imladris {

    /**
     * Enumerates operational execution states of Galaxy datasets.
     */
    public enum GalaxyDatasetState {
        OK,
        RUNNING,
        QUEUED,
        ERROR,
        DISCARDED,
        PAUSED,
        UPLOADING,
        UNKNOWN;

        /**
         * Converts state enum to Galaxy REST API string identifier.
         *
         * @return Standardized state identifier string.
         */
        public string to_id_string () {
            switch (this) {
                case OK: return "ok";
                case RUNNING: return "running";
                case QUEUED: return "queued";
                case ERROR: return "error";
                case DISCARDED: return "discarded";
                case PAUSED: return "paused";
                case UPLOADING: return "upload";
                default: return "unknown";
            }
        }

        /**
         * Parses Galaxy server state string into typed enum value.
         *
         * @param raw_state Raw state string from Galaxy JSON response.
         * @return Matching GalaxyDatasetState enum value.
         */
        public static GalaxyDatasetState from_string (string raw_state) {
            switch (raw_state.down ()) {
                case "ok": return OK;
                case "running": return RUNNING;
                case "queued": return QUEUED;
                case "error": return ERROR;
                case "discarded": return DISCARDED;
                case "paused": return PAUSED;
                case "upload": return UPLOADING;
                default: return UNKNOWN;
            }
        }

        /**
         * Returns Nord theme hex color code for UI state badge display.
         *
         * @return Hexadecimal color string.
         */
        public string get_color_hex () {
            switch (this) {
                case OK: return "#A3BE8C";       // Nord green
                case RUNNING:
                case QUEUED: return "#EBCB8B";   // Nord yellow
                case ERROR: return "#BF616A";     // Nord red
                default: return "#D8DEE9";        // Nord light gray
            }
        }

        /**
         * Returns Libadwaita badge CSS style class.
         *
         * @return CSS class name string.
         */
        public string get_badge_css_class () {
            switch (this) {
                case OK: return "success";
                case RUNNING: return "accent";
                case QUEUED: return "warning";
                case ERROR: return "error";
                default: return "dim-label";
            }
        }

        /**
         * Returns Freedesktop symbolic icon name for the dataset state.
         *
         * @return Icon name string.
         */
        public string get_symbolic_icon () {
            switch (this) {
                case OK: return "emblem-ok-symbolic";
                case RUNNING: return "process-working-symbolic";
                case QUEUED: return "appointment-soon-symbolic";
                case ERROR: return "dialog-error-symbolic";
                default: return "dialog-information-symbolic";
            }
        }
    }

    /**
     * Represents a remote Galaxy History containing bioinformatics datasets.
     * Inherits from GLib.Object to allow direct binding to GTK4 ListStore models.
     */
    public class GalaxyHistory : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string name { get; construct set; default = ""; }
        public string update_time { get; construct set; default = ""; }
        public bool deleted { get; construct set; default = false; }

        /**
         * Constructs a new GalaxyHistory domain model instance.
         *
         * @param id Encoded history identifier string.
         * @param name Human-readable history label.
         * @param update_time ISO 8601 timestamp string of last modification.
         * @param deleted Boolean deletion flag on remote server.
         */
        public GalaxyHistory (
            string id,
            string name,
            string update_time = "",
            bool deleted = false
        ) {
            GLib.Object (
                id: id,
                name: name,
                update_time: update_time,
                deleted: deleted
            );
        }
    }

    /**
     * Represents a single bioinformatics dataset residing in a Galaxy history.
     * Inherits from GLib.Object to allow direct binding to GTK4 ListStore models.
     */
    public class GalaxyDataset : GLib.Object {
        public string id { get; construct set; default = ""; }
        public string history_id { get; construct set; default = ""; }
        public int hid { get; construct set; default = 0; }
        public string name { get; construct set; default = ""; }
        public string extension { get; construct set; default = ""; }
        public string state { get; construct set; default = "ok"; }
        public int64 file_size { get; construct set; default = 0; }
        public string download_url { get; construct set; default = ""; }

        /**
         * Constructs a new GalaxyDataset domain model instance.
         *
         * @param id Encoded dataset identifier string.
         * @param history_id Encoded parent history identifier string.
         * @param hid Sequential integer history index number.
         * @param name File name of the dataset.
         * @param extension Scientific format extension (e.g. tabular, tsv, bam).
         * @param state Current processing state string from Galaxy server.
         * @param file_size Dataset payload size in bytes.
         * @param download_url Fully qualified HTTP download address.
         */
        public GalaxyDataset (
            string id,
            string history_id,
            int hid,
            string name,
            string extension,
            string state = "ok",
            int64 file_size = 0,
            string download_url = ""
        ) {
            GLib.Object (
                id: id,
                history_id: history_id,
                hid: hid,
                name: name,
                extension: extension,
                state: state,
                file_size: file_size,
                download_url: download_url
            );
        }

        /**
         * Returns parsed GalaxyDatasetState enum representation.
         *
         * @return Typed GalaxyDatasetState enum value.
         */
        public GalaxyDatasetState get_state_enum () {
            return GalaxyDatasetState.from_string (state);
        }

        /**
         * Returns human-readable binary size string.
         *
         * Formats byte counts into B, KB, MB, or GB unit strings.
         *
         * @return Formatted size string.
         */
        public string get_formatted_size () {
            if (file_size <= 0) {
                return "0 B";
            }
            if (file_size < 1024) {
                return @"$(file_size) B";
            }
            if (file_size < 1024 * 1024) {
                double kb = (double) file_size / 1024.0;
                return "%.1f KB".printf (kb);
            }
            if (file_size < 1024 * 1024 * 1024) {
                double mb = (double) file_size / (1024.0 * 1024.0);
                return "%.1f MB".printf (mb);
            }
            double gb = (double) file_size / (1024.0 * 1024.0 * 1024.0);
            return "%.2f GB".printf (gb);
        }

        /**
         * Converts dataset file name into safe script variable identifier.
         *
         * @return Lowercase alphanumeric identifier starting with df_.
         */
        public string get_safe_variable_name () {
            return GalaxyChunkGenerator.sanitize_variable_name (name);
        }

        /**
         * Generates reproducible R Quarto code block for active manuscript.
         *
         * @param server_url Base URL of remote Galaxy server.
         * @param history_name Label of parent Galaxy history.
         * @return Complete executable R Quarto chunk string.
         */
        public string generate_r_quarto_chunk (string server_url, string history_name = "Galaxy History") {
            return GalaxyChunkGenerator.generate_chunk (this, server_url, history_name, TargetLanguage.R_QUARTO);
        }

        /**
         * Generates reproducible Python Quarto code block for active manuscript.
         *
         * @param server_url Base URL of remote Galaxy server.
         * @param history_name Label of parent Galaxy history.
         * @return Complete executable Python Quarto chunk string.
         */
        public string generate_python_quarto_chunk (string server_url, string history_name = "Galaxy History") {
            return GalaxyChunkGenerator.generate_chunk (this, server_url, history_name, TargetLanguage.PYTHON_QUARTO);
        }
    }
}
