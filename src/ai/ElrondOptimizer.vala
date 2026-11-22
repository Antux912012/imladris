// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gee;
using Imladris.Core;

namespace Imladris.AI {

    /**
     * ElrondOptimizer
     *
     * Builds safe, high-performance `llama-server` launch argument profiles
     * from the hardware tier selected by `ElrondHardwareProbe`.
     */
    public class ElrondOptimizer : GLib.Object {

        public static string[] build_optimized_argv (
            string binary,
            string model_path,
            LocalModelPreset? preset,
            ElrondHardwareProbeResult probe,
            bool auto_optimize = true,
            ElrondComputeMode compute_mode = ElrondComputeMode.AUTO,
            bool force_cpu_fallback = false,
            int port = 8081
        ) {
            bool compact = preset != null && preset.fits_2gb_profile;
            bool ultra_tight = preset != null && preset.id == "qwen35-2b";
            string context = compact && !ultra_tight ? "4096" : "2048";

            var args = new Gee.ArrayList<string> ();
            args.add (binary);
            args.add ("-m");
            args.add (model_path);
            args.add ("-c");
            args.add (context);
            args.add ("-np");
            args.add ("1");

            ElrondVulkanDevice? dev = null;
            ElrondHardwareTier tier = ElrondHardwareTier.TIER_5_LEGACY_OR_CPU;

            if (!force_cpu_fallback) {
                if (!auto_optimize && compute_mode == ElrondComputeMode.CPU) {
                    tier = ElrondHardwareTier.TIER_5_LEGACY_OR_CPU;
                } else {
                    dev = probe.selected_device;
                    tier = probe.effective_tier;
                    if (!auto_optimize && compute_mode == ElrondComputeMode.VULKAN && dev == null) {
                        foreach (var candidate in probe.devices) {
                            if (!candidate.is_software_renderer) {
                                dev = candidate;
                                tier = candidate.tier;
                                break;
                            }
                        }
                    }
                }
            }

            int physical_cores = int.max (1, probe.physical_cores);
            int gpu_threads = int.max (1, physical_cores / 2);
            int cpu_threads = int.max (1, physical_cores - 1);

            if (dev == null || tier == ElrondHardwareTier.TIER_5_LEGACY_OR_CPU) {
                // Profile D: Tier 5 (Legacy Intel iGPU) or CPU Fallback
                args.add ("-ngl");
                args.add ("0");
                args.add ("-b");
                args.add ("256");
                args.add ("-t");
                args.add (cpu_threads.to_string ());
            } else if (tier == ElrondHardwareTier.TIER_1_NVIDIA_DGPU ||
                       tier == ElrondHardwareTier.TIER_2_AMD_DGPU) {
                // Profile A: Tier 1 (NVIDIA dGPU) & Tier 2 (AMD dGPU)
                args.add ("-dev");
                args.add (dev.device_id);
                args.add ("-ngl");
                args.add ("auto");
                args.add ("--fit");
                args.add ("on");
                args.add ("--fit-target");
                args.add ("256");
                args.add ("--flash-attn");
                args.add ("on");
                if (dev.free_vram_mib < 12288) {
                    args.add ("-ctk");
                    args.add ("q8_0");
                    args.add ("-ctv");
                    args.add ("q8_0");
                }
                args.add ("-b");
                args.add ("512");
                args.add ("-ub");
                args.add ("512");
                args.add ("-t");
                args.add (gpu_threads.to_string ());
            } else if (tier == ElrondHardwareTier.TIER_3_INTEL_ARC_DGPU) {
                // Profile B: Tier 3 (Intel Arc dGPU)
                args.add ("-dev");
                args.add (dev.device_id);
                args.add ("-ngl");
                args.add ("auto");
                args.add ("--fit");
                args.add ("on");
                args.add ("--fit-target");
                args.add ("512");
                args.add ("--flash-attn");
                args.add ("on");
                args.add ("-ctk");
                args.add ("q8_0");
                args.add ("-ctv");
                args.add ("q8_0");
                args.add ("-b");
                args.add ("512");
                args.add ("-ub");
                args.add ("256");
                args.add ("-t");
                args.add (gpu_threads.to_string ());
            } else {
                // Profile C: Tier 4 (Intel Xe / Arc iGPU / AMD APU - Unified Memory)
                args.add ("-dev");
                args.add (dev.device_id);
                args.add ("-ngl");
                args.add ("auto");
                args.add ("--fit");
                args.add ("on");
                args.add ("--fit-target");
                args.add ("1024");
                args.add ("--flash-attn");
                args.add ("on");
                args.add ("-ctk");
                args.add ("q8_0");
                args.add ("-ctv");
                args.add ("q8_0");
                args.add ("-b");
                args.add ("256");
                args.add ("-ub");
                args.add ("128");
                args.add ("-t");
                args.add (gpu_threads.to_string ());
            }

            args.add ("--no-warmup");
            args.add ("--host");
            args.add ("127.0.0.1");
            args.add ("--port");
            args.add (port.to_string ());

            return args.to_array ();
        }

        public static bool is_vulkan_failure_stderr (string stderr_text) {
            string lower = stderr_text.down ();
            return lower.contains ("vk_error") ||
                lower.contains ("vulkan") && (
                    lower.contains ("out of memory") ||
                    lower.contains ("memory allocation") ||
                    lower.contains ("failed to allocate") ||
                    lower.contains ("failed to initialize") ||
                    lower.contains ("device lost")
                );
        }
    }
}
