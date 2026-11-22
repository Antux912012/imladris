// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gee;
using Imladris.Core;

namespace Imladris.AI {

    public enum ElrondHardwareTier {
        TIER_1_NVIDIA_DGPU = 1,
        TIER_2_AMD_DGPU = 2,
        TIER_3_INTEL_ARC_DGPU = 3,
        TIER_4_MODERN_IGPU = 4,
        TIER_5_LEGACY_OR_CPU = 5;

        public string get_short_label () {
            switch (this) {
                case TIER_1_NVIDIA_DGPU: return "Tier 1: NVIDIA dGPU";
                case TIER_2_AMD_DGPU: return "Tier 2: AMD dGPU";
                case TIER_3_INTEL_ARC_DGPU: return "Tier 3: Intel Arc dGPU";
                case TIER_4_MODERN_IGPU: return "Tier 4: Modern iGPU";
                case TIER_5_LEGACY_OR_CPU:
                default: return "Tier 5: CPU Fallback";
            }
        }
    }

    public class ElrondVulkanDevice : GLib.Object {
        public string device_id { owned get; set; default = ""; }
        public string device_name { owned get; set; default = ""; }
        public int64 total_vram_mib { get; set; default = 0; }
        public int64 free_vram_mib { get; set; default = 0; }
        public ElrondHardwareTier tier { get; set; default = ElrondHardwareTier.TIER_5_LEGACY_OR_CPU; }
        public bool is_software_renderer { get; set; default = false; }

        public ElrondVulkanDevice (
            string device_id,
            string device_name,
            int64 total_vram_mib,
            int64 free_vram_mib,
            ElrondHardwareTier tier,
            bool is_software_renderer
        ) {
            this.device_id = device_id;
            this.device_name = device_name;
            this.total_vram_mib = total_vram_mib;
            this.free_vram_mib = free_vram_mib;
            this.tier = tier;
            this.is_software_renderer = is_software_renderer;
        }
    }

    public class ElrondHardwareProbeResult : GLib.Object {
        public int64 total_ram_mib { get; set; default = 0; }
        public int logical_cores { get; set; default = 1; }
        public int physical_cores { get; set; default = 1; }
        public Gee.ArrayList<ElrondVulkanDevice> devices { get; private set; }
        public ElrondVulkanDevice? selected_device { get; set; default = null; }
        public ElrondHardwareTier effective_tier { get; set; default = ElrondHardwareTier.TIER_5_LEGACY_OR_CPU; }

        public ElrondHardwareProbeResult () {
            devices = new Gee.ArrayList<ElrondVulkanDevice> ();
        }

        public string format_profile_badge (
            bool auto_optimize = true,
            ElrondComputeMode compute_mode = ElrondComputeMode.AUTO
        ) {
            if (!auto_optimize && compute_mode == ElrondComputeMode.CPU) {
                return "Manual: CPU (%s)".printf (ElrondHardwareTier.TIER_5_LEGACY_OR_CPU.get_short_label ());
            }

            if (selected_device != null && effective_tier != ElrondHardwareTier.TIER_5_LEGACY_OR_CPU) {
                return "Auto-Optimized: %s (%s)".printf (
                    selected_device.device_name,
                    effective_tier.get_short_label ()
                );
            }

            return "Auto-Optimized: CPU (%s)".printf (ElrondHardwareTier.TIER_5_LEGACY_OR_CPU.get_short_label ());
        }
    }

    /**
     * ElrondHardwareProbe
     *
     * Probes Vulkan-capable GPUs via `llama-server --list-devices` along with
     * host system RAM and physical CPU core count, then classifies and selects
     * the highest-priority compute device.
     */
    public class ElrondHardwareProbe : GLib.Object {

        private static GLib.Regex? cached_line_regex = null;
        private static GLib.Regex? cached_mem_regex = null;
        private static GLib.Regex? cached_single_mem_regex = null;

        public static int64 read_total_ram_mib () {
            try {
                string contents;
                if (FileUtils.get_contents ("/proc/meminfo", out contents)) {
                    foreach (string line in contents.split ("\n")) {
                        if (line.has_prefix ("MemTotal:")) {
                            string rest = line.substring (9).strip ();
                            string[] parts = rest.split (" ");
                            if (parts.length > 0) {
                                int64 kb = int64.parse (parts[0]);
                                if (kb > 0) {
                                    return kb / 1024;
                                }
                            }
                        }
                    }
                }
            } catch (GLib.Error e) {
                GLib.debug ("Could not read /proc/meminfo: %s", e.message);
            }
            return 0;
        }

        public static int read_physical_core_count () {
            int logical = (int) GLib.get_num_processors ();
            if (logical < 1) {
                logical = 1;
            }

            try {
                string contents;
                if (FileUtils.get_contents ("/proc/cpuinfo", out contents)) {
                    var unique_cores = new Gee.HashSet<string> ();
                    string phys_id = "0";
                    string core_id = "";
                    bool saw_core_id = false;

                    foreach (string raw_line in contents.split ("\n")) {
                        string line = raw_line.strip ();
                        if (line.length == 0) {
                            if (saw_core_id) {
                                unique_cores.add (phys_id + ":" + core_id);
                            }
                            phys_id = "0";
                            core_id = "";
                            saw_core_id = false;
                            continue;
                        }
                        int colon = line.index_of_char (':');
                        if (colon > 0) {
                            string key = line.substring (0, colon).strip ();
                            string val = line.substring (colon + 1).strip ();
                            if (key == "physical id") {
                                phys_id = val;
                            } else if (key == "core id") {
                                core_id = val;
                                saw_core_id = true;
                            }
                        }
                    }
                    if (saw_core_id) {
                        unique_cores.add (phys_id + ":" + core_id);
                    }
                    if (unique_cores.size > 0) {
                        return unique_cores.size;
                    }
                }
            } catch (GLib.Error e) {
                GLib.debug ("Could not read /proc/cpuinfo: %s", e.message);
            }

            return logical;
        }

        public static ElrondHardwareTier classify_device (
            string device_name,
            int64 total_vram_mib,
            int64 free_vram_mib,
            out bool is_software_renderer
        ) {
            string lower = device_name.down ().replace ("(tm)", "").replace ("(r)", "");
            while (lower.contains ("  ")) {
                lower = lower.replace ("  ", " ");
            }
            is_software_renderer = lower.contains ("llvmpipe") || lower.contains ("lavapipe");

            if (is_software_renderer) {
                return ElrondHardwareTier.TIER_5_LEGACY_OR_CPU;
            }

            if (free_vram_mib > 0 && free_vram_mib < 1536) {
                return ElrondHardwareTier.TIER_5_LEGACY_OR_CPU;
            }

            // Tier 1: NVIDIA dGPU
            if (lower.contains ("nvidia") || lower.contains ("geforce") ||
                lower.contains ("rtx") || lower.contains ("gtx") || lower.contains ("quadro")) {
                return ElrondHardwareTier.TIER_1_NVIDIA_DGPU;
            }

            // Tier 2: AMD dGPU (dedicated VRAM > 2048 MiB, excluding APUs/iGPUs)
            bool is_amd_brand = lower.contains ("radeon rx") || lower.contains ("radeon pro") || lower.contains ("amd");
            bool is_amd_apu = lower.contains ("graphics") || lower.contains ("780m") ||
                lower.contains ("890m") || lower.contains ("610m");
            if (is_amd_brand && total_vram_mib > 2048 && !is_amd_apu) {
                return ElrondHardwareTier.TIER_2_AMD_DGPU;
            }

            // Tier 3: Intel Arc dGPU
            if (lower.contains ("intel") && (
                lower.contains ("arc a") || lower.contains ("arc b") ||
                lower.contains ("dg2") || lower.contains ("battlemage"))) {
                return ElrondHardwareTier.TIER_3_INTEL_ARC_DGPU;
            }

            // Tier 4: Modern iGPU (Intel Xe / Arc iGPU / AMD APU)
            if (lower.contains ("iris xe") || lower.contains ("arc graphics") ||
                lower.contains ("radeon 780m") || lower.contains ("radeon 890m") ||
                lower.contains ("radeon graphics") ||
                (lower.contains ("intel") && lower.contains ("iris") && lower.contains ("xe")) ||
                (lower.contains ("intel") && lower.contains ("arc") && lower.contains ("graphics"))) {
                return ElrondHardwareTier.TIER_4_MODERN_IGPU;
            }

            // Tier 5: Legacy iGPU or unrecognized low-capability device
            if (lower.contains ("uhd graphics") || lower.contains ("hd graphics")) {
                return ElrondHardwareTier.TIER_5_LEGACY_OR_CPU;
            }

            return ElrondHardwareTier.TIER_5_LEGACY_OR_CPU;
        }

        public static Gee.ArrayList<ElrondVulkanDevice> parse_list_devices_output (string output) {
            var list = new Gee.ArrayList<ElrondVulkanDevice> ();
            try {
                if (cached_line_regex == null) {
                    cached_line_regex = new Regex ("^(Vulkan\\d+)\\s*:\\s*(.+)$", RegexCompileFlags.CASELESS);
                }
                if (cached_mem_regex == null) {
                    cached_mem_regex = new Regex ("\\(\\s*(\\d+)\\s*MiB\\s*,\\s*(\\d+)\\s*MiB\\s+free\\s*\\)\\s*$", RegexCompileFlags.CASELESS);
                }
                if (cached_single_mem_regex == null) {
                    cached_single_mem_regex = new Regex ("\\(\\s*(\\d+)\\s*MiB\\s*\\)\\s*$", RegexCompileFlags.CASELESS);
                }
                var line_regex = cached_line_regex;
                var mem_regex = cached_mem_regex;
                var single_mem_regex = cached_single_mem_regex;

                foreach (string raw_line in output.split ("\n")) {
                    string line = raw_line.strip ();
                    if (line.length == 0) {
                        continue;
                    }

                    MatchInfo line_match;
                    if (!line_regex.match (line, 0, out line_match)) {
                        continue;
                    }

                    string device_id = line_match.fetch (1).strip ();
                    string rest = line_match.fetch (2).strip ();
                    string device_name = rest;
                    int64 total_vram = 0;
                    int64 free_vram = 0;

                    MatchInfo mem_match;
                    if (mem_regex.match (rest, 0, out mem_match)) {
                        total_vram = int64.parse (mem_match.fetch (1));
                        free_vram = int64.parse (mem_match.fetch (2));
                        int start_pos = 0;
                        int end_pos = 0;
                        if (mem_match.fetch_pos (0, out start_pos, out end_pos) && start_pos > 0) {
                            device_name = rest.substring (0, start_pos).strip ();
                        }
                    } else if (single_mem_regex.match (rest, 0, out mem_match)) {
                        total_vram = int64.parse (mem_match.fetch (1));
                        free_vram = total_vram;
                        int start_pos = 0;
                        int end_pos = 0;
                        if (mem_match.fetch_pos (0, out start_pos, out end_pos) && start_pos > 0) {
                            device_name = rest.substring (0, start_pos).strip ();
                        }
                    }

                    bool is_sw = false;
                    ElrondHardwareTier tier = classify_device (device_name, total_vram, free_vram, out is_sw);
                    list.add (new ElrondVulkanDevice (
                        device_id, device_name, total_vram, free_vram, tier, is_sw
                    ));
                }
            } catch (RegexError e) {
                GLib.warning ("Regex error parsing llama-server --list-devices: %s", e.message);
            }
            return list;
        }

        public static ElrondVulkanDevice? select_best_device (Gee.List<ElrondVulkanDevice> devices) {
            ElrondVulkanDevice? best_dgpu = null;
            ElrondVulkanDevice? best_igpu = null;

            foreach (var dev in devices) {
                if (dev.is_software_renderer) {
                    continue;
                }

                if (dev.tier == ElrondHardwareTier.TIER_1_NVIDIA_DGPU ||
                    dev.tier == ElrondHardwareTier.TIER_2_AMD_DGPU ||
                    dev.tier == ElrondHardwareTier.TIER_3_INTEL_ARC_DGPU) {
                    if (best_dgpu == null ||
                        dev.free_vram_mib > best_dgpu.free_vram_mib ||
                        (dev.free_vram_mib == best_dgpu.free_vram_mib && (int) dev.tier < (int) best_dgpu.tier)) {
                        best_dgpu = dev;
                    }
                } else if (dev.tier == ElrondHardwareTier.TIER_4_MODERN_IGPU) {
                    if (best_igpu == null || dev.free_vram_mib > best_igpu.free_vram_mib) {
                        best_igpu = dev;
                    }
                }
            }

            if (best_dgpu != null) {
                return best_dgpu;
            }
            if (best_igpu != null) {
                return best_igpu;
            }
            return null;
        }

        public static ElrondHardwareProbeResult probe_from_output (
            string list_devices_output,
            int64? override_ram_mib = null,
            int? override_physical_cores = null
        ) {
            var result = new ElrondHardwareProbeResult ();
            result.total_ram_mib = override_ram_mib ?? read_total_ram_mib ();
            result.logical_cores = int.max (1, (int) GLib.get_num_processors ());
            result.physical_cores = int.max (1, override_physical_cores ?? read_physical_core_count ());

            var parsed = parse_list_devices_output (list_devices_output);
            foreach (var dev in parsed) {
                result.devices.add (dev);
            }

            result.selected_device = select_best_device (result.devices);
            if (result.selected_device != null) {
                result.effective_tier = result.selected_device.tier;
            } else {
                result.effective_tier = ElrondHardwareTier.TIER_5_LEGACY_OR_CPU;
            }
            return result;
        }

        public static async ElrondHardwareProbeResult probe_async (
            string? binary_path,
            bool is_host_binary = false,
            Cancellable? cancellable = null
        ) {
            string output = "";
            if (binary_path != null && binary_path.length > 0) {
                try {
                    string[] raw = { binary_path, "--list-devices" };
                    string[] argv = is_host_binary ? HostBridge.wrap_command (raw) : raw;

                    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                    var proc = launcher.spawnv (argv);
                    string stdout_buf;
                    string stderr_buf;
                    yield proc.communicate_utf8_async (null, cancellable, out stdout_buf, out stderr_buf);
                    output = stdout_buf ?? "";
                    if (output.strip ().length == 0 && stderr_buf != null) {
                        output = stderr_buf;
                    }
                } catch (GLib.Error e) {
                    GLib.debug ("ElrondHardwareProbe --list-devices failed: %s", e.message);
                }
            }
            return probe_from_output (output);
        }
    }
}
