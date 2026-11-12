// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * Single Responsibility: Cryptographic provenance attestation and manifest generation.
 *
 * Architectural Position:
 * Core reproducibility service. Calculates SHA-256 digests of manuscripts, environment
 * lockfiles, and extracted bioinformatics cloud provenance records.
 * Downstream consumers: Imladris.Window, Quarto render pipeline.
 * Upstream dependencies: glib-2.0, gio-2.0, json-glib-1.0.
 *
 * Concurrency Constraints:
 * Asynchronously calculates file checksums using GIO without blocking the UI loop.
 */

using GLib;
using Json;

namespace Imladris.Core {

    public class ProvenanceAttestationService : GLib.Object {

        public const string VERSION = "0.19.0";

        public static string compute_sha256_string (string content) {
            return GLib.Checksum.compute_for_string (GLib.ChecksumType.SHA256, content);
        }

        public static string? compute_sha256_file (string file_path) {
            if (!GLib.FileUtils.test (file_path, GLib.FileTest.IS_REGULAR)) {
                return null;
            }
            try {
                uint8[] data;
                GLib.FileUtils.get_data (file_path, out data);
                return GLib.Checksum.compute_for_data (GLib.ChecksumType.SHA256, data);
            } catch (GLib.Error e) {
                return null;
            }
        }

        /**
         * Generates deterministic JSON manifest <document>.provenance.lock.json.
         */
        public static async string generate_attestation_async (
            string document_path,
            string document_content,
            string project_dir
        ) throws GLib.Error {
            var builder = new Json.Builder ();
            builder.begin_object ();

            builder.set_member_name ("schemaVersion");
            builder.add_string_value ("1.0");

            builder.set_member_name ("generator");
            builder.add_string_value ("Imladris Scientific Workbench " + VERSION);

            builder.set_member_name ("timestampUtc");
            builder.add_string_value (new GLib.DateTime.now_utc ().format_iso8601 ());

            // Manuscript Record
            string doc_hash = compute_sha256_string (document_content);
            builder.set_member_name ("manuscript");
            builder.begin_object ();
            builder.set_member_name ("path");
            builder.add_string_value (document_path);
            builder.set_member_name ("sha256");
            builder.add_string_value (doc_hash);
            builder.set_member_name ("lengthBytes");
            builder.add_int_value ((int64) document_content.length);
            builder.end_object ();

            // Environment Lockfiles
            builder.set_member_name ("environmentLocks");
            builder.begin_array ();

            string[] candidate_locks = { "renv.lock", "uv.lock", "environment.yml", "conda-lock.yml", "_quarto.yml" };
            var lock_digests = new GLib.StringBuilder ();
            lock_digests.append (doc_hash);

            foreach (var lock_name in candidate_locks) {
                string lock_path = GLib.Path.build_filename (project_dir, lock_name);
                string? hash = compute_sha256_file (lock_path);
                if (hash != null) {
                    builder.begin_object ();
                    builder.set_member_name ("file");
                    builder.add_string_value (lock_name);
                    builder.set_member_name ("sha256");
                    builder.add_string_value (hash);
                    builder.end_object ();
                    lock_digests.append (hash);
                }
            }
            builder.end_array ();

            // Bio-Entity Provenance Records from Markdown
            builder.set_member_name ("externalBioEntities");
            builder.begin_array ();

            string[] lines = document_content.split ("\n");
            foreach (var l in lines) {
                string trimmed = l.strip ();
                if (trimmed.has_prefix ("# AREKYER PROVENANCE RECORD") ||
                    trimmed.has_prefix ("# YAVANNA BIO-ENTITY PROVENANCE:") ||
                    trimmed.has_prefix ("# TANIQUETIL ALPHAFOLD PROVENANCE:")) {
                    builder.begin_object ();
                    builder.set_member_name ("record");
                    builder.add_string_value (trimmed);
                    builder.end_object ();
                    lock_digests.append (trimmed);
                }
            }
            builder.end_array ();

            // Master Attestation Digest
            string master_attestation = compute_sha256_string (lock_digests.str);
            builder.set_member_name ("attestationDigest");
            builder.add_string_value (master_attestation);

            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            generator.pretty = true;
            string json_manifest = generator.to_data (null);

            // Write sidecar file next to document
            string manifest_path = document_path + ".provenance.lock.json";
            string? etag_out = null;
            var file = GLib.File.new_for_path (manifest_path);
            yield file.replace_contents_async (
                json_manifest.data,
                null,
                false,
                GLib.FileCreateFlags.REPLACE_DESTINATION,
                null,
                out etag_out
            );

            return manifest_path;
        }
    }
}
