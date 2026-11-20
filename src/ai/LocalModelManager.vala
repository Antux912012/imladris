// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Json;
using Soup;
using Gee;
using Imladris.Core;

namespace Imladris.AI {

    private class LocalModelFileInfo : GLib.Object {
        public uint64 size { get; set; }
        public string sha256 { get; set; default = ""; }
        public string revision { get; set; default = ""; }
    }

    public class LocalModelPreset : GLib.Object {
        public string id { get; construct; }
        public string name { get; construct; }
        public string repository { get; construct; }
        public string[] preferred_quants { get; construct; }
        public string footprint { get; construct; }
        public string strengths { get; construct; }
        public bool fits_2gb_profile { get; construct; }

        public LocalModelPreset (string id, string name, string repository, string[] preferred_quants,
                                 string footprint, string strengths, bool fits_2gb_profile = false) {
            GLib.Object (
                id: id,
                name: name,
                repository: repository,
                preferred_quants: preferred_quants,
                footprint: footprint,
                strengths: strengths,
                fits_2gb_profile: fits_2gb_profile
            );
        }
    }

    public class LocalModelManager : GLib.Object {
        private Soup.Session session;

        public signal void download_progress (string model_id, double fraction, string status);

        public LocalModelManager () {
            session = new Soup.Session () {
                timeout = 0
            };
        }

        public static Gee.ArrayList<LocalModelPreset> get_catalog () {
            var presets = new Gee.ArrayList<LocalModelPreset> ();
            presets.add (new LocalModelPreset ("qwen25-coder-7b", "Qwen2.5-Coder-7B-Instruct",
                "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF", { "Q4_K_M", "Q4_0", "Q3_K_M" }, "5.0-5.5 GB",
                "Code generation for Python, R, TypeScript, HTML, CSS, and Markdown."));
            presets.add (new LocalModelPreset ("qwen35-4b", "Qwen3.5-4B",
                "unsloth/Qwen3.5-4B-GGUF", { "UD-Q4_K_XL", "Q6_K", "Q4_K_M" }, "3.0-3.8 GB",
                "Efficient coding and reasoning with headroom for long contexts and documents."));
            presets.add (new LocalModelPreset ("deepseek-r1-qwen3-8b", "DeepSeek-R1-0528-Qwen3-8B",
                "unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF", { "Q3_K_XL", "Q4_0", "Q3_K_M" }, "4.8-5.4 GB",
                "Scientific reasoning, mathematics, LaTeX, Python, and statistical modeling."));
            presets.add (new LocalModelPreset ("granite-4-h-tiny", "IBM Granite 4.0 H-Tiny",
                "ibm-granite/granite-4.0-h-tiny-GGUF", { "Q4_K_M", "Q4_0", "Q3_K_M" }, "4.5-5.2 GB",
                "Fast structured Markdown and JSON, plus Python and TypeScript generation."));
            presets.add (new LocalModelPreset ("phi-4-mini", "Phi-4-Mini-Instruct",
                "unsloth/Phi-4-mini-instruct-GGUF", { "Q4_K_M", "Q4_0", "Q3_K_M" }, "2.8–3.5 GB",
                "Compact STEM reasoning, LaTeX, and Python or TypeScript code."));
            presets.add (new LocalModelPreset ("qwen25-coder-15b", "Qwen2.5-Coder-1.5B-Instruct",
                "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF", { "Q4_K_M", "Q4_0", "Q3_K_M" }, "1.3-1.6 GB",
                "Lightweight code generation across Python, R, TypeScript, HTML, and CSS.", true));
            presets.add (new LocalModelPreset ("qwen35-2b", "Qwen3.5-2B",
                "unsloth/Qwen3.5-2B-GGUF", { "UD-Q4_K_XL", "Q4_K_M", "Q4_0" }, "1.6-1.9 GB",
                "Efficient all-round reasoning, Markdown structure, Python, and TypeScript.", true));
            presets.add (new LocalModelPreset ("qwen3-17b", "Qwen3-1.7B",
                "bartowski/Qwen_Qwen3-1.7B-GGUF", { "Q4_K_M", "Q4_0", "Q3_K_M" }, "1.4-1.7 GB",
                "Compact coding with optional thinking-mode prompts for deeper reasoning.", true));
            presets.add (new LocalModelPreset ("qwen25-math-15b", "Qwen2.5-Math-1.5B-Instruct",
                "bartowski/Qwen2.5-Math-1.5B-Instruct-GGUF", { "Q4_K_M", "Q4_0", "Q3_K_M" }, "1.3-1.6 GB",
                "Symbolic mathematics, statistics, scientific reasoning, and LaTeX.", true));
            presets.add (new LocalModelPreset ("lfm25-12b", "Liquid LFM2.5-1.2B-Instruct",
                "LiquidAI/LFM2.5-1.2B-Instruct-GGUF", { "Q4_K_M", "Q4_0", "Q3_K_M" }, "0.9-1.2 GB",
                "Very small footprint, quick CPU inference, and structured instruction following.", true));
            return presets;
        }

        public static string get_models_directory () {
            return GLib.Path.build_filename (Environment.get_user_data_dir (), "imladris", "models");
        }

        public static string get_model_directory (LocalModelPreset preset) {
            return GLib.Path.build_filename (get_models_directory (), preset.id);
        }

        public static string[] select_gguf_files (string tree_json, string[] preferred_quants) throws GLib.Error {
            var parser = new Json.Parser ();
            parser.load_from_data (tree_json, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                throw new GLib.IOError.INVALID_DATA ("Hugging Face model file list is not a JSON array.");
            }

            var files = new Gee.ArrayList<string> ();
            var tree = root.get_array ();
            for (uint i = 0; i < tree.get_length (); i++) {
                var entry = tree.get_object_element (i);
                if (!entry.has_member ("path")) {
                    continue;
                }
                string path = entry.get_string_member ("path");
                if (path.down ().has_suffix (".gguf")) {
                    files.add (path);
                }
            }

            foreach (string quant in preferred_quants) {
                var matches = new Gee.ArrayList<string> ();
                foreach (string path in files) {
                    if (path.down ().contains (quant.down ())) {
                        matches.add (path);
                    }
                }
                if (matches.size == 0) {
                    continue;
                }
                matches.sort ((a, b) => { return strcmp (a, b); });
                foreach (string path in matches) {
                    if (!is_shard_file (path)) {
                        return { path };
                    }
                }
                string first_shard = "";
                foreach (string path in matches) {
                    if (path.contains ("-00001-of-")) {
                        first_shard = path;
                        break;
                    }
                }
                if (first_shard.length > 0) {
                    int marker = first_shard.index_of ("-00001-of-");
                    string prefix = first_shard.substring (0, marker);
                    string count = first_shard.substring (marker + 10, first_shard.length - marker - 15);
                    var shards = new Gee.ArrayList<string> ();
                    foreach (string path in matches) {
                        if (path.has_prefix (prefix + "-") && path.contains ("-of-" + count + ".gguf")) {
                            shards.add (path);
                        }
                    }
                    string[] shard_paths = new string[shards.size];
                    for (int i = 0; i < shards.size; i++) {
                        shard_paths[i] = shards[i];
                    }
                    return shard_paths;
                }
                throw new GLib.IOError.INVALID_DATA ("Multiple GGUF files match quantization %s.".printf (quant));
            }

            throw new GLib.IOError.NOT_FOUND ("No compatible GGUF quantization was found in the selected model repository.");
        }

        private static bool is_shard_file (string path) {
            return GLib.Regex.match_simple ("-[0-9]{5}-of-[0-9]{5}\\.gguf$", path);
        }

        public async string download_model_async (LocalModelPreset preset, Cancellable? cancellable = null) throws GLib.Error {
            string tree_url = "https://huggingface.co/api/models/%s/tree/main?recursive=true&expand=true".printf (preset.repository);
            string tree_json = yield get_text_async (tree_url, cancellable);
            string[] filenames = select_gguf_files (tree_json, preset.preferred_quants);
            var file_metadata = parse_file_metadata (tree_json);

            uint64 total_size = 0;
            uint64 required_space = 0;
            var verified_existing = new Gee.HashSet<string> ();
            foreach (string filename in filenames) {
                var metadata = file_metadata.get (filename);
                if (metadata == null || metadata.size == 0 || metadata.sha256.length != 64 || metadata.revision.length == 0) {
                    throw new GLib.IOError.INVALID_DATA (
                        "Hugging Face did not provide a valid size, SHA-256, or revision for %s.".printf (filename)
                    );
                }
                total_size += metadata.size;
                string destination = GLib.Path.build_filename (
                    get_model_directory (preset), GLib.Path.get_basename (filename)
                );
                bool already_downloaded = false;
                if (FileUtils.test (destination, FileTest.EXISTS)) {
                    FileInfo existing = File.new_for_path (destination).query_info (
                        FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE, cancellable
                    );
                    if (existing.get_size () == (int64) metadata.size) {
                        string existing_sha256 = yield checksum_file_async (destination, cancellable);
                        already_downloaded = existing_sha256 == metadata.sha256;
                    }
                }
                if (already_downloaded) {
                    verified_existing.add (filename);
                } else {
                    required_space += metadata.size;
                }
            }
            if (total_size == 0) {
                throw new GLib.IOError.INVALID_DATA ("The selected model's GGUF files have no reported size.");
            }

            string model_dir = get_model_directory (preset);
            DirUtils.create_with_parents (model_dir, 0755);
            var dir = File.new_for_path (model_dir);
            var fs_info = dir.query_filesystem_info (FileAttribute.FILESYSTEM_FREE, cancellable);
            uint64 free_bytes = fs_info.get_attribute_uint64 (FileAttribute.FILESYSTEM_FREE);
            if (free_bytes < required_space) {
                throw new GLib.IOError.NO_SPACE ("Not enough free disk space to download %s.".printf (preset.name));
            }

            uint64 downloaded = 0;
            string model_path = "";
            foreach (string filename in filenames) {
                var metadata = file_metadata.get (filename);
                uint64 file_size = metadata.size;
                string local_name = GLib.Path.get_basename (filename);
                string destination = GLib.Path.build_filename (model_dir, local_name);
                if (verified_existing.contains (filename)) {
                    downloaded += file_size;
                    download_progress (preset.id, (double) downloaded / (double) total_size, local_name);
                    if (model_path == "") {
                        model_path = destination;
                    }
                    continue;
                }

                string encoded_filename = Uri.escape_string (filename, "/", true);
                string url = "https://huggingface.co/%s/resolve/%s/%s?download=true".printf (
                    preset.repository, metadata.revision, encoded_filename
                );
                string part_path = destination + ".part";
                var part_file = File.new_for_path (part_path);
                var dest_file = File.new_for_path (destination);
                var checksum = new GLib.Checksum (GLib.ChecksumType.SHA256);
                InputStream? input = null;
                FileOutputStream? output = null;
                try {
                    var message = new Soup.Message ("GET", url);
                    input = yield session.send_async (message, Priority.DEFAULT, cancellable);
                    if (message.status_code < 200 || message.status_code >= 300) {
                        throw new GLib.IOError.FAILED (
                            "Hugging Face download failed (HTTP %u %s).".printf (message.status_code, message.reason_phrase)
                        );
                    }
                    output = part_file.create (FileCreateFlags.PRIVATE, cancellable);
                    uint64 file_downloaded = 0;
                    while (true) {
                        Bytes chunk = yield input.read_bytes_async (262144, Priority.DEFAULT, cancellable);
                        if (chunk.get_size () == 0) {
                            break;
                        }
                        size_t written = 0;
                        if (!output.write_all (chunk.get_data (), out written, cancellable)) {
                            throw new GLib.IOError.FAILED ("Could not write downloaded model data.");
                        }
                        checksum.update (chunk.get_data (), (ssize_t) written);
                        file_downloaded += written;
                        double fraction = (double) (downloaded + file_downloaded) / (double) total_size;
                        download_progress (preset.id, fraction.clamp (0.0, 1.0), local_name);
                    }
                    input.close (cancellable);
                    input = null;
                    output.close (cancellable);
                    output = null;
                    if (file_downloaded != file_size) {
                        throw new GLib.IOError.INVALID_DATA (
                            "Downloaded size for %s does not match Hugging Face's file metadata.".printf (local_name)
                        );
                    }
                    if (checksum.get_string () != metadata.sha256) {
                        throw new GLib.IOError.INVALID_DATA (
                            "SHA-256 verification failed for %s.".printf (local_name)
                        );
                    }
                    part_file.move (dest_file, FileCopyFlags.OVERWRITE, cancellable, null);
                    downloaded += file_downloaded;
                    if (model_path == "") {
                        model_path = destination;
                    }
                } catch (GLib.Error e) {
                    if (input != null) {
                        try {
                            input.close (null);
                        } catch (GLib.Error close_error) {
                            warning ("Could not close the model download stream: %s", close_error.message);
                        }
                    }
                    if (output != null) {
                        try {
                            output.close (null);
                        } catch (GLib.Error close_error) {
                            warning ("Could not close the partial model file: %s", close_error.message);
                        }
                    }
                    try {
                        part_file.delete (null);
                    } catch (GLib.Error cleanup_error) {}
                    throw e;
                }
            }

            download_progress (preset.id, 1.0, "Download complete");
            return model_path;
        }

        private async string get_text_async (string url, Cancellable? cancellable) throws GLib.Error {
            var message = new Soup.Message ("GET", url);
            var bytes = yield session.send_and_read_async (message, Priority.DEFAULT, cancellable);
            if (message.status_code < 200 || message.status_code >= 300) {
                throw new GLib.IOError.FAILED (
                    "Could not retrieve the Hugging Face model listing (HTTP %u %s).".printf (
                        message.status_code, message.reason_phrase
                    )
                );
            }
            return AiConfigManager.bytes_to_string (bytes);
        }

        private static Gee.HashMap<string, LocalModelFileInfo> parse_file_metadata (string tree_json) throws GLib.Error {
            var parser = new Json.Parser ();
            parser.load_from_data (tree_json, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                throw new GLib.IOError.INVALID_DATA ("Hugging Face model file list is not a JSON array.");
            }
            var metadata_by_path = new Gee.HashMap<string, LocalModelFileInfo> ();
            var entries = root.get_array ();
            for (uint i = 0; i < entries.get_length (); i++) {
                var entry = entries.get_object_element (i);
                if (entry.has_member ("path") && entry.has_member ("size")) {
                    var metadata = new LocalModelFileInfo ();
                    int64 size = entry.get_int_member ("size");
                    if (size <= 0) {
                        continue;
                    }
                    metadata.size = (uint64) size;
                    if (entry.has_member ("lfs")) {
                        var lfs = entry.get_object_member ("lfs");
                        if (lfs.has_member ("oid")) {
                            string oid = lfs.get_string_member ("oid");
                            metadata.sha256 = oid.has_prefix ("sha256:")
                                ? oid.substring ("sha256:".length) : oid;
                        }
                    }
                    if (entry.has_member ("lastCommit")) {
                        var commit = entry.get_object_member ("lastCommit");
                        if (commit.has_member ("id")) {
                            metadata.revision = commit.get_string_member ("id");
                        }
                    }
                    metadata_by_path.set (entry.get_string_member ("path"), metadata);
                }
            }
            return metadata_by_path;
        }

        private async string checksum_file_async (string path, Cancellable? cancellable) throws GLib.Error {
            var input = File.new_for_path (path).read (cancellable);
            var checksum = new GLib.Checksum (GLib.ChecksumType.SHA256);
            while (true) {
                Bytes chunk = yield input.read_bytes_async (262144, Priority.DEFAULT, cancellable);
                if (chunk.get_size () == 0) {
                    break;
                }
                checksum.update (chunk.get_data (), (ssize_t) chunk.get_size ());
            }
            input.close (cancellable);
            return checksum.get_string ();
        }
    }
}
