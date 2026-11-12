// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Unit test suite for Galaxy Bridge subsystem.
 *
 * Architectural Position:
 * Automated test suite executed by Meson and Ninja under the Beyonce Rule standard.
 * Tests data models, code chunk generation, variable sanitization, and keyring schema.
 *
 * Concurrency Constraints:
 * Synchronous test runner execution on the main thread.
 */

using GLib;
using Imladris;

public class TestGalaxyBridge {

    /**
     * Verifies that dataset state strings map correctly to enum values.
     */
    public static void test_state_mapping () {
        assert (GalaxyDatasetState.from_string ("ok") == GalaxyDatasetState.OK);
        assert (GalaxyDatasetState.from_string ("RUNNING") == GalaxyDatasetState.RUNNING);
        assert (GalaxyDatasetState.from_string ("queued") == GalaxyDatasetState.QUEUED);
        assert (GalaxyDatasetState.from_string ("error") == GalaxyDatasetState.ERROR);
        assert (GalaxyDatasetState.from_string ("discarded") == GalaxyDatasetState.DISCARDED);
        assert (GalaxyDatasetState.from_string ("paused") == GalaxyDatasetState.PAUSED);
        assert (GalaxyDatasetState.from_string ("upload") == GalaxyDatasetState.UPLOADING);
        assert (GalaxyDatasetState.from_string ("invalid_state_xyz") == GalaxyDatasetState.UNKNOWN);

        assert (GalaxyDatasetState.OK.to_id_string () == "ok");
        assert (GalaxyDatasetState.ERROR.to_id_string () == "error");
        assert (GalaxyDatasetState.OK.get_color_hex () == "#A3BE8C");
        assert (GalaxyDatasetState.ERROR.get_color_hex () == "#BF616A");
    }

    /**
     * Verifies that dataset names convert safely into lowercase scripting variable identifiers.
     */
    public static void test_variable_name_sanitization () {
        // Standard test matching specification
        string test_spec = GalaxyChunkGenerator.sanitize_variable_name ("#43: DESeq2 Counts (2026).tsv");
        assert (test_spec == "df_43_deseq2_counts_2026");

        var ds1 = new GalaxyDataset (
            "ds_001",
            "hist_001",
            43,
            "DESeq2_Normalized_Counts.tsv",
            "tsv",
            "ok",
            1048576,
            "https://usegalaxy.eu/api/histories/hist_001/contents/ds_001/display"
        );
        assert (ds1.get_safe_variable_name () == "df_deseq2_normalized_counts");

        var ds2 = new GalaxyDataset (
            "ds_002",
            "hist_001",
            12,
            "---Sample #12 (Rep A)---.bam",
            "bam",
            "ok",
            5242880,
            "https://usegalaxy.eu/api/histories/hist_001/contents/ds_002/display"
        );
        assert (ds2.get_safe_variable_name () == "df_sample_12_rep_a");

        // Edge case: empty string
        assert (GalaxyChunkGenerator.sanitize_variable_name ("") == "df_dataset");
    }

    /**
     * Verifies that reproducible R Quarto code blocks contain required syntax and provenance.
     */
    public static void test_r_code_chunk_generation () {
        var ds = new GalaxyDataset (
            "f2db41e1fa331b3e",
            "bbd44e69cb8906b5",
            43,
            "diff_expr_results.tsv",
            "tabular",
            "ok",
            2048,
            "https://usegalaxy.eu/api/histories/bbd44e69cb8906b5/contents/f2db41e1fa331b3e/display"
        );

        string chunk = GalaxyChunkGenerator.generate_chunk (
            ds,
            "https://usegalaxy.eu",
            "Differential Expression",
            TargetLanguage.R_QUARTO
        );

        assert ("```{r arekyer-galaxy-43, message=FALSE}" in chunk);
        assert ("# AREKYER PROVENANCE RECORD" in chunk);
        assert ("# Server: https://usegalaxy.eu" in chunk);
        assert ("# History ID: bbd44e69cb8906b5" in chunk);
        assert ("# Dataset ID: f2db41e1fa331b3e (HID: 43 | Format: tabular)" in chunk);
        assert ("galaxy_url <- \"https://usegalaxy.eu/api/histories/bbd44e69cb8906b5/contents/f2db41e1fa331b3e/display\"" in chunk);
        assert ("httr2::request(galaxy_url)" in chunk);
        assert ("httr2::req_headers(\"x-api-key\" = Sys.getenv(\"GALAXY_API_KEY\"))" in chunk);
        assert ("resp <- httr2::req_perform(req)" in chunk);
        assert ("galaxy_df_43 <- readr::read_tsv(httr2::resp_body_raw(resp), show_col_types = FALSE)" in chunk);
        assert ("```" in chunk);
    }

    /**
     * Verifies that reproducible Python Quarto code blocks contain required syntax and provenance.
     */
    public static void test_python_code_chunk_generation () {
        var ds = new GalaxyDataset (
            "f2db41e1fa331b3e",
            "bbd44e69cb8906b5",
            43,
            "diff_expr_results.tsv",
            "tabular",
            "ok",
            2048,
            "https://usegalaxy.eu/api/histories/bbd44e69cb8906b5/contents/f2db41e1fa331b3e/display"
        );

        string chunk = GalaxyChunkGenerator.generate_chunk (
            ds,
            "https://usegalaxy.eu",
            "Differential Expression",
            TargetLanguage.PYTHON_QUARTO
        );

        assert ("```{python arekyer-galaxy-43}" in chunk);
        assert ("# AREKYER PROVENANCE RECORD" in chunk);
        assert ("import requests" in chunk);
        assert ("import pandas as pd" in chunk);
        assert ("os.environ.get(\"GALAXY_API_KEY\")" in chunk);
        assert ("galaxy_df_43 = pd.read_csv" in chunk);
        assert ("sep=\"\\t\"" in chunk);
        assert ("galaxy_df_43.head()" in chunk);
        assert ("```" in chunk);
    }

    /**
     * Verifies that binary bioinformatics formats generate cache download logic.
     */
    public static void test_binary_format_chunk_generation () {
        var ds_bam = new GalaxyDataset (
            "b9914c",
            "h123",
            7,
            "alignment.bam",
            "bam",
            "ok",
            104857600,
            "https://usegalaxy.eu/api/histories/h123/contents/b9914c/display"
        );

        string r_chunk = GalaxyChunkGenerator.generate_chunk (
            ds_bam,
            "https://usegalaxy.eu",
            "Genomics",
            TargetLanguage.R_QUARTO
        );
        assert ("dir.create(\"./data/galaxy\"" in r_chunk);
        assert ("httr2::req_perform(req, path = dest_path)" in r_chunk);
        assert ("galaxy_file_7 <- dest_path" in r_chunk);

        string py_chunk = GalaxyChunkGenerator.generate_chunk (
            ds_bam,
            "https://usegalaxy.eu",
            "Genomics",
            TargetLanguage.PYTHON_QUARTO
        );
        assert ("cache_dir = os.path.join(\".\", \"data\", \"galaxy\")" in py_chunk);
        assert ("galaxy_file_7 = dest_path" in py_chunk);
    }

    /**
     * Verifies that file sizes format accurately across unit boundaries.
     */
    public static void test_size_formatting () {
        var ds_zero = new GalaxyDataset ("1", "1", 1, "a", "tsv", "ok", 0, "");
        assert (ds_zero.get_formatted_size () == "0 B");

        var ds_bytes = new GalaxyDataset ("2", "1", 2, "b", "tsv", "ok", 512, "");
        assert (ds_bytes.get_formatted_size () == "512 B");

        var ds_kb = new GalaxyDataset ("3", "1", 3, "c", "tsv", "ok", 1024 * 15, "");
        assert ("KB" in ds_kb.get_formatted_size ());

        var ds_mb = new GalaxyDataset ("4", "1", 4, "d", "tsv", "ok", 1024 * 1024 * 12, "");
        assert ("MB" in ds_mb.get_formatted_size ());
    }

    /**
     * Verifies that history models construct and retain properties.
     */
    public static void test_history_model () {
        var hist = new GalaxyHistory ("h_abc123", "RNA-Seq Analysis", "2026-11-12T10:00:00Z", false);
        assert (hist.id == "h_abc123");
        assert (hist.name == "RNA-Seq Analysis");
        assert (hist.update_time == "2026-11-12T10:00:00Z");
        assert (!hist.deleted);
    }

    /**
     * Verifies that Secret.Schema is configured with correct service schema name and attributes.
     */
    public static void test_secret_schema () {
        var schema = GalaxyClient.get_secret_schema ();
        assert (schema != null);
        assert (schema.name == "org.ardatech.Imladris.GalaxyApiKey");
    }

    /**
     * Verifies the Arekyer provenance bridge facade and chunk generation.
     */
    public static void test_arekyer_bridge () {
        var bridge = Imladris.Bridges.Arekyer.ArekyerBridge.get_default ();
        assert (bridge != null);
        assert (bridge.client != null);

        var ds = new GalaxyDataset (
            "f2db41e1fa331b3e",
            "bbd44e69cb8906b5",
            43,
            "DESeq2_Normalized_Counts.tsv",
            "tabular",
            "ok",
            1048576,
            "https://usegalaxy.eu/api/histories/bbd44e69cb8906b5/contents/f2db41e1fa331b3e/display"
        );

        string chunk = bridge.generate_provenance_chunk (ds, "RNA-Seq", TargetLanguage.R_QUARTO);
        assert ("```{r arekyer-galaxy-43, message=FALSE}" in chunk);
        assert ("# AREKYER PROVENANCE RECORD" in chunk);
        assert ("galaxy_df_43" in chunk);
    }

    public static int main (string[] args) {
        Test.init (ref args);

        Test.add_func ("/galaxy_bridge/state_mapping", test_state_mapping);
        Test.add_func ("/galaxy_bridge/variable_name_sanitization", test_variable_name_sanitization);
        Test.add_func ("/galaxy_bridge/r_code_chunk_generation", test_r_code_chunk_generation);
        Test.add_func ("/galaxy_bridge/python_code_chunk_generation", test_python_code_chunk_generation);
        Test.add_func ("/galaxy_bridge/binary_format_chunk_generation", test_binary_format_chunk_generation);
        Test.add_func ("/galaxy_bridge/size_formatting", test_size_formatting);
        Test.add_func ("/galaxy_bridge/history_model", test_history_model);
        Test.add_func ("/galaxy_bridge/secret_schema", test_secret_schema);
        Test.add_func ("/galaxy_bridge/arekyer_bridge", test_arekyer_bridge);

        return Test.run ();
    }
}
