// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Generates reproducible polyglot code chunks for Quarto and RMarkdown manuscripts.
 *
 * Architectural Position:
 * Core bridge utility class for code synthesis.
 * Downstream consumers: Imladris.GalaxyPanel, Imladris.GalaxyDataset, and unit tests.
 * Upstream dependencies: Imladris.GalaxyDataset and GLib.
 *
 * Concurrency Constraints:
 * Pure static methods with immutable parameters. Re-entrant and thread-safe.
 */

using GLib;

namespace Imladris {

    /**
     * Target computational language for Quarto executable code chunk generation.
     */
    public enum TargetLanguage {
        R_QUARTO,
        PYTHON_QUARTO
    }

    /**
     * Stateless generator for scientific provenance code blocks.
     */
    public class GalaxyChunkGenerator : GLib.Object {

        /**
         * Sanitizes raw dataset names into safe lowercase scripting variable identifiers.
         *
         * The algorithm strips file extensions, replaces non-alphanumeric characters with
         * underscores, collapses consecutive underscores, trims boundary underscores, and
         * ensures a 'df_' prefix.
         *
         * @param raw_name Untrusted file name string from remote Galaxy server.
         * @return Valid lowercase identifier starting with df_.
         */
        public static string sanitize_variable_name (string raw_name) {
            string cleaned = raw_name.strip ();

            // Strip file extension if present
            int last_dot = cleaned.last_index_of_char ('.');
            if (last_dot > 0 && last_dot > cleaned.last_index_of_char ('/')) {
                cleaned = cleaned.substring (0, last_dot);
            }

            var builder = new StringBuilder ();
            string lower_name = cleaned.down ();
            long len = lower_name.length;

            for (long i = 0; i < len; i++) {
                unichar c = lower_name.get_char (i);
                if (c.isalnum ()) {
                    builder.append_unichar (c);
                } else {
                    builder.append_c ('_');
                }
            }

            string token = builder.str;

            // Collapse multiple consecutive underscores
            while (token.contains ("__")) {
                token = token.replace ("__", "_");
            }

            // Trim leading underscores
            while (token.has_prefix ("_")) {
                token = token.substring (1);
            }

            // Trim trailing underscores
            while (token.has_suffix ("_")) {
                token = token.substring (0, token.length - 1);
            }

            if (token.length == 0) {
                return "df_dataset";
            }

            // Ensure the variable name starts with the df_ prefix
            if (!token.has_prefix ("df_")) {
                token = "df_" + token;
            }

            return token;
        }

        /**
         * Generates reproducible executable code chunk with scientific provenance header.
         *
         * @param ds Remote Galaxy dataset domain object.
         * @param server_url Base URL of remote Galaxy server instance.
         * @param history_name Human-readable parent history title.
         * @param lang Target computational language (R or Python).
         * @return Formatted Quarto code block string.
         */
        public static string generate_chunk (
            GalaxyDataset ds,
            string server_url,
            string history_name,
            TargetLanguage lang
        ) {
            string norm_url = server_url.strip ();
            while (norm_url.has_suffix ("/")) {
                norm_url = norm_url.substring (0, norm_url.length - 1);
            }

            string var_name = sanitize_variable_name (ds.name);
            string ext = ds.extension.down ().strip ();
            bool is_tsv = (ext == "tabular" || ext == "tsv");
            bool is_csv = (ext == "csv");

            if (lang == TargetLanguage.R_QUARTO) {
                return generate_r_quarto (ds, norm_url, history_name, var_name, is_tsv, is_csv);
            } else {
                return generate_python_quarto (ds, norm_url, history_name, var_name, is_tsv, is_csv);
            }
        }

        /**
         * Synthesizes an R Quarto chunk using httr2 and readr with standardized Arekyer provenance.
         */
        private static string generate_r_quarto (
            GalaxyDataset ds,
            string server_url,
            string history_name,
            string var_name,
            bool is_tsv,
            bool is_csv
        ) {
            var sb = new StringBuilder ();

            sb.append_printf ("```{r arekyer-galaxy-%d, message=FALSE}\n", ds.hid);
            sb.append ("# AREKYER PROVENANCE RECORD\n");
            sb.append_printf ("# Server: %s\n", server_url);
            sb.append_printf ("# History ID: %s\n", ds.history_id);
            sb.append_printf ("# Dataset ID: %s (HID: %d | Format: %s)\n\n", ds.id, ds.hid, ds.extension);

            sb.append_printf ("galaxy_url <- \"%s/api/histories/%s/contents/%s/display\"\n", server_url, ds.history_id, ds.id);
            sb.append ("req <- httr2::request(galaxy_url) |>\n");
            sb.append ("  httr2::req_headers(\"x-api-key\" = Sys.getenv(\"GALAXY_API_KEY\"))\n");
            sb.append ("resp <- httr2::req_perform(req)\n");

            if (is_tsv || is_csv) {
                string reader = is_tsv ? "readr::read_tsv" : "readr::read_csv";
                sb.append_printf ("galaxy_df_%d <- %s(httr2::resp_body_raw(resp), show_col_types = FALSE)\n", ds.hid, reader);
            } else {
                // Large bioinformatics binary or non-tabular format (bam, vcf, fasta, h5ad)
                sb.append ("dir.create(\"./data/galaxy\", recursive = TRUE, showWarnings = FALSE)\n");
                sb.append_printf ("dest_path <- file.path(\"./data/galaxy\", \"%s_%s\")\n", ds.id, ds.name);
                sb.append ("if (!file.exists(dest_path)) {\n");
                sb.append ("  httr2::req_perform(req, path = dest_path)\n");
                sb.append ("}\n");
                sb.append_printf ("galaxy_file_%d <- dest_path\n", ds.hid);
                sb.append_printf ("message(paste(\"Cached dataset file at:\", galaxy_file_%d))\n", ds.hid);
            }

            sb.append ("```\n");
            return sb.str;
        }

        /**
         * Synthesizes a Python Quarto chunk using requests and pandas with standardized Arekyer provenance.
         */
        private static string generate_python_quarto (
            GalaxyDataset ds,
            string server_url,
            string history_name,
            string var_name,
            bool is_tsv,
            bool is_csv
        ) {
            var sb = new StringBuilder ();

            sb.append_printf ("```{python arekyer-galaxy-%d}\n", ds.hid);
            sb.append ("# AREKYER PROVENANCE RECORD\n");
            sb.append_printf ("# Server: %s\n", server_url);
            sb.append_printf ("# History ID: %s\n", ds.history_id);
            sb.append_printf ("# Dataset ID: %s (HID: %d | Format: %s)\n\n", ds.id, ds.hid, ds.extension);

            sb.append ("import os\n");
            if (is_tsv || is_csv) {
                sb.append ("import io\n");
            }
            sb.append ("import requests\n");
            if (is_tsv || is_csv) {
                sb.append ("import pandas as pd\n");
            }
            sb.append ("\n");

            sb.append_printf ("galaxy_url = \"%s/api/histories/%s/contents/%s/display\"\n", server_url, ds.history_id, ds.id);
            sb.append ("galaxy_key = os.environ.get(\"GALAXY_API_KEY\")\n");
            sb.append ("if not galaxy_key:\n");
            sb.append ("    raise RuntimeError(\"Set GALAXY_API_KEY in your environment or Imladris workbench.\")\n\n");

            if (is_tsv || is_csv) {
                sb.append ("resp = requests.get(galaxy_url, headers={\"x-api-key\": galaxy_key}, timeout=60)\n");
                sb.append ("resp.raise_for_status()\n");
                if (is_tsv) {
                    sb.append_printf ("galaxy_df_%d = pd.read_csv(io.StringIO(resp.text), sep=\"\\t\")\n", ds.hid);
                } else {
                    sb.append_printf ("galaxy_df_%d = pd.read_csv(io.StringIO(resp.text))\n", ds.hid);
                }
                sb.append_printf ("galaxy_df_%d.head()\n", ds.hid);
            } else {
                // Non-tabular file cache download
                sb.append ("cache_dir = os.path.join(\".\", \"data\", \"galaxy\")\n");
                sb.append ("os.makedirs(cache_dir, exist_ok=True)\n");
                sb.append_printf ("dest_path = os.path.join(cache_dir, \"%s_%s\")\n\n", ds.id, ds.name);
                sb.append ("if not os.path.exists(dest_path):\n");
                sb.append ("    resp = requests.get(galaxy_url, headers={\"x-api-key\": galaxy_key}, timeout=60)\n");
                sb.append ("    resp.raise_for_status()\n");
                sb.append ("    with open(dest_path, \"wb\") as f:\n");
                sb.append ("        f.write(resp.content)\n\n");
                sb.append_printf ("galaxy_file_%d = dest_path\n", ds.hid);
                sb.append_printf ("print(f\"Cached dataset file at: {dest_path}\")\n");
            }

            sb.append ("```\n");
            return sb.str;
        }
    }
}
