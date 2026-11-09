// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Unit test suite for the Galaxy Bridge subsystem.
 *
 * Architectural Position:
 * Automated test suite executed by Meson/Ninja under the Beyonce Rule standard.
 * Tests data modeling, code chunk generation, and variable name sanitization.
 *
 * Concurrency Constraints:
 * Synchronous test runner execution on the main thread.
 */

using GLib;
using Gee;
using Imladris.Bridges;

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
    }

    /**
     * Verifies that dataset names are safely converted into language identifiers.
     */
    public static void test_variable_name_sanitization () {
        var ds1 = new GalaxyDataset (
            "ds_001",
            "hist_001",
            "DESeq2_Normalized_Counts.tsv",
            "tsv",
            GalaxyDatasetState.OK,
            1048576,
            "https://usegalaxy.eu/api/datasets/ds_001/display"
        );
        assert (ds1.get_safe_variable_name () == "deseq2_normalized_counts_tsv");

        var ds2 = new GalaxyDataset (
            "ds_002",
            "hist_001",
            "---Sample #12 (Rep A)---.bam",
            "bam",
            GalaxyDatasetState.OK,
            5242880,
            "https://usegalaxy.eu/api/datasets/ds_002/display"
        );
        assert (ds2.get_safe_variable_name () == "sample_12_rep_a_bam");
    }

    /**
     * Verifies that reproducible R Quarto code blocks contain required syntax.
     */
    public static void test_r_code_chunk_generation () {
        var ds = new GalaxyDataset (
            "f2db41e1",
            "bbd44e69",
            "diff_expr_results.tsv",
            "tsv",
            GalaxyDatasetState.OK,
            2048,
            "https://usegalaxy.eu/api/datasets/f2db41e1/display"
        );

        string chunk = ds.generate_r_quarto_chunk ("https://usegalaxy.eu");
        assert ("```{r galaxy_pull_f2db41e1, message=FALSE}" in chunk);
        assert ("library(httr)" in chunk);
        assert ("imladris_fetch_dataset" in chunk);
        assert ("df_diff_expr_results_tsv <- read.delim" in chunk);
        assert ("https://usegalaxy.eu/api/datasets/f2db41e1/display" in chunk);
        assert ("Sys.getenv(\"GALAXY_API_KEY\")" in chunk);
        assert ("```" in chunk);
    }

    /**
     * Verifies that reproducible Python Quarto code blocks contain required syntax.
     */
    public static void test_python_code_chunk_generation () {
        var ds = new GalaxyDataset (
            "f2db41e1",
            "bbd44e69",
            "diff_expr_results.tsv",
            "tsv",
            GalaxyDatasetState.OK,
            2048,
            "https://usegalaxy.eu/api/datasets/f2db41e1/display"
        );

        string chunk = ds.generate_python_quarto_chunk ("https://usegalaxy.eu");
        assert ("```{python galaxy_pull_f2db41e1}" in chunk);
        assert ("import requests" in chunk);
        assert ("import pandas as pd" in chunk);
        assert ("df_diff_expr_results_tsv = pd.read_csv" in chunk);
        assert ("https://usegalaxy.eu/api/datasets/f2db41e1/display" in chunk);
        assert ("os.environ.get(\"GALAXY_API_KEY\"" in chunk);
        assert ("```" in chunk);
    }

    /**
     * Verifies that file sizes are formatted accurately across unit boundaries.
     */
    public static void test_size_formatting () {
        var ds_zero = new GalaxyDataset ("1", "1", "a", "tsv", GalaxyDatasetState.OK, 0, "");
        assert (ds_zero.get_formatted_size () == "0 B");

        var ds_bytes = new GalaxyDataset ("2", "1", "b", "tsv", GalaxyDatasetState.OK, 512, "");
        assert (ds_bytes.get_formatted_size () == "512 B");

        var ds_kb = new GalaxyDataset ("3", "1", "c", "tsv", GalaxyDatasetState.OK, 1024 * 15, "");
        assert ("KB" in ds_kb.get_formatted_size ());

        var ds_mb = new GalaxyDataset ("4", "1", "d", "tsv", GalaxyDatasetState.OK, 1024 * 1024 * 12, "");
        assert ("MB" in ds_mb.get_formatted_size ());
    }

    public static int main (string[] args) {
        Test.init (ref args);

        Test.add_func ("/galaxy_bridge/state_mapping", test_state_mapping);
        Test.add_func ("/galaxy_bridge/variable_name_sanitization", test_variable_name_sanitization);
        Test.add_func ("/galaxy_bridge/r_code_chunk_generation", test_r_code_chunk_generation);
        Test.add_func ("/galaxy_bridge/python_code_chunk_generation", test_python_code_chunk_generation);
        Test.add_func ("/galaxy_bridge/size_formatting", test_size_formatting);

        return Test.run ();
    }
}
