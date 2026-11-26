// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;
using Gtk;
using Adw;
using Imladris.Core;

namespace Imladris.UI {

    public class AiSettingsDialog : Adw.PreferencesDialog {

        private AiConfigManager config_mgr;
        private Imladris.AI.LocalModelManager local_model_manager;
        private Gtk.ProgressBar? local_model_progress;
        private Adw.ActionRow? local_model_status;
        private Gtk.Button? local_model_download_button;
        private Gtk.Button? local_model_cancel_button;
        private Cancellable? local_model_cancellable;

        public AiSettingsDialog () {
            Object (title: "AI Engine & Model Configuration");
            this.config_mgr = AiConfigManager.get_default ();
            this.local_model_manager = new Imladris.AI.LocalModelManager ();
            this.closed.connect (() => {
                if (local_model_cancellable != null) {
                    local_model_cancellable.cancel ();
                }
            });

            setup_pages ();
        }

        private void setup_pages () {
            // ==========================================
            // Page 1: Frontier Cloud AI (Gemini, Claude, OpenAI, Cursor)
            // ==========================================
            var frontier_page = new Adw.PreferencesPage () {
                title = "Frontier AI",
                icon_name = "network-server-symbolic"
            };

            var generation_group = new Adw.PreferencesGroup () {
                title = "Generation Style",
                description = "Shared response detail and sampling settings for cloud and local AI."
            };
            var detail_options = new Gtk.StringList (null);
            detail_options.append ("Concise");
            detail_options.append ("Balanced");
            detail_options.append ("Detailed");
            var detail_row = new Adw.ComboRow () {
                title = "Response Detail",
                subtitle = "Controls how brief or thorough Elrond's answers should be.",
                model = detail_options,
                selected = (uint) config_mgr.response_detail
            };
            detail_row.notify["selected"].connect (() => {
                if (detail_row.selected <= (uint) AiResponseDetail.DETAILED) {
                    config_mgr.response_detail = (AiResponseDetail) detail_row.selected;
                }
            });
            generation_group.add (detail_row);

            var temperature_row = new Adw.ActionRow () {
                title = "Temperature",
                subtitle = "%.2f".printf (config_mgr.temperature)
            };
            var temperature_scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0.0, 2.0, 0.05) {
                valign = Gtk.Align.CENTER,
                width_request = 200,
                draw_value = false
            };
            temperature_scale.set_digits (2);
            temperature_scale.set_value (config_mgr.temperature);
            temperature_scale.value_changed.connect (() => {
                config_mgr.temperature = temperature_scale.get_value ();
                temperature_row.subtitle = "%.2f".printf (config_mgr.temperature);
            });
            temperature_row.add_suffix (temperature_scale);
            generation_group.add (temperature_row);
            frontier_page.add (generation_group);

            // --- Google Gemini Group ---
            var gemini_group = new Adw.PreferencesGroup () {
                title = "Google Gemini",
                description = "Select a model in the chat model menu or enter a model ID here. Use Refresh Models to load the models enabled for your API key.",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.GEMINI.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var gemini_settings = config_mgr.get_settings_for (AiProvider.GEMINI);

            var gemini_key_row = new Adw.PasswordEntryRow () {
                title = "Google API Key or OAuth Token",
                text = gemini_settings.api_key
            };
            gemini_key_row.notify["text"].connect (() => {
                gemini_settings.api_key = gemini_key_row.text;
                config_mgr.save ();
            });
            gemini_group.add (gemini_key_row);

            var gemini_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = gemini_settings.endpoint
            };
            gemini_endpoint_row.notify["text"].connect (() => {
                gemini_settings.endpoint = gemini_endpoint_row.text;
                config_mgr.save ();
            });
            gemini_group.add (gemini_endpoint_row);

            var gemini_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = gemini_settings.model
            };
            gemini_model_row.notify["text"].connect (() => {
                config_mgr.set_model_for (AiProvider.GEMINI, gemini_model_row.text);
            });
            gemini_group.add (gemini_model_row);

            var gemini_action_row = new Adw.ActionRow () {
                title = "Get Google AI Studio API Key",
                subtitle = "Free tier available at Google AI Studio (login with your Google Account)"
            };
            var gemini_btn = new Gtk.Button.with_label ("Get API Key ↗") { valign = Gtk.Align.CENTER };
            gemini_btn.add_css_class ("suggested-action");
            gemini_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://aistudio.google.com/app/apikey");
            });
            gemini_action_row.add_suffix (gemini_btn);
            gemini_group.add (gemini_action_row);

            var gemini_oauth_row = new Adw.ActionRow () {
                title = "Google Account / OAuth Access Token",
                subtitle = "Authenticate via gcloud auth print-access-token or Google Cloud OAuth2"
            };
            var oauth_btn = new Gtk.Button.with_label ("OAuth Info ↗") { valign = Gtk.Align.CENTER };
            oauth_btn.add_css_class ("flat");
            oauth_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://cloud.google.com/docs/authentication/token-types#access-contents");
            });
            gemini_oauth_row.add_suffix (oauth_btn);
            gemini_group.add (gemini_oauth_row);

            frontier_page.add (gemini_group);

            // --- Claude / Anthropic Group ---
            add_provider_config_group (
                frontier_page, AiProvider.CLAUDE,
                "Claude (Anthropic)",
                "Anthropic's Claude 3.5 Sonnet, 3.7 Sonnet, Haiku, and Opus via native Messages API",
                true, true,
                "Anthropic API Key",
                "Get Anthropic API Key", "Manage API keys in the Anthropic Console",
                "https://console.anthropic.com/settings/keys", "Get API Key ↗", true
            );

            // --- OpenAI Group ---
            add_provider_config_group (
                frontier_page, AiProvider.OPENAI,
                "OpenAI",
                "OpenAI GPT-4o, GPT-4o-mini, o1, and o3-mini models",
                true, true,
                "OpenAI API Key",
                "Get OpenAI API Key", "Manage API keys on the OpenAI Developer Platform",
                "https://platform.openai.com/api-keys", "Get API Key ↗", true
            );

            // --- Cursor API Compatibility Group ---
            add_provider_config_group (
                frontier_page, AiProvider.CURSOR,
                "Cursor API Compatibility",
                "Connect using Cursor API or OpenAI-compatible Cursor proxies",
                true, true,
                "Cursor API Key",
                "Cursor Information", "Learn more about Cursor AI and developer API compatibility",
                "https://cursor.com", "Visit cursor.com ↗", true
            );

            // --- GitHub Copilot (OAuth Device Flow) Group ---
            var copilot_group = new Adw.PreferencesGroup () {
                title = "GitHub Copilot",
                description = "Sign in with your GitHub Copilot subscription via OAuth Device Flow",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.GITHUB_COPILOT.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var copilot_auth = Imladris.AI.CopilotAuthService.get_default ();
            var copilot_settings = config_mgr.get_settings_for (AiProvider.GITHUB_COPILOT);

            var copilot_status_row = new Adw.ActionRow () {
                title = "GitHub Account"
            };
            var copilot_auth_btn = new Gtk.Button () { valign = Gtk.Align.CENTER };

            update_copilot_ui (copilot_auth, copilot_status_row, copilot_auth_btn);

            copilot_auth.auth_state_changed.connect ((signed_in, uname) => {
                update_copilot_ui (copilot_auth, copilot_status_row, copilot_auth_btn);
            });

            copilot_auth_btn.clicked.connect (() => {
                if (copilot_auth.is_signed_in ()) {
                    copilot_auth.sign_out_async.begin ((obj, res) => {
                        copilot_auth.sign_out_async.end (res);
                        update_copilot_ui (copilot_auth, copilot_status_row, copilot_auth_btn);
                        this.add_toast (new Adw.Toast ("Signed out of GitHub Copilot"));
                    });
                } else {
                    start_copilot_device_flow_async.begin ();
                }
            });

            copilot_status_row.add_suffix (copilot_auth_btn);
            copilot_group.add (copilot_status_row);

            var copilot_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = copilot_settings.model
            };
            copilot_model_row.notify["text"].connect (() => {
                copilot_settings.model = copilot_model_row.text;
                config_mgr.save ();
            });
            copilot_group.add (copilot_model_row);

            frontier_page.add (copilot_group);

            this.add (frontier_page);

            // ==========================================
            // Page 2: Open Weights & Enterprise (DeepSeek, Kimi, Qwen, NVIDIA NIM)
            // ==========================================
            var enterprise_page = new Adw.PreferencesPage () {
                title = "Open and Enterprise",
                icon_name = "system-run-symbolic"
            };

            // --- DeepSeek Group ---
            add_provider_config_group (
                enterprise_page, AiProvider.DEEPSEEK,
                "DeepSeek",
                "High-performance coding (deepseek-chat) and reasoning (deepseek-reasoner / R1)",
                true, true,
                "DeepSeek API Key",
                "Get DeepSeek API Key", "Manage API keys on the DeepSeek Open Platform",
                "https://platform.deepseek.com/api_keys", "Get API Key ↗", true
            );

            // --- NVIDIA NIM Group ---
            add_provider_config_group (
                enterprise_page, AiProvider.NVIDIA_NIM,
                "NVIDIA NIM",
                "NVIDIA Inference Microservices with GPU-accelerated Llama 3.3, Nemotron, and DeepSeek R1",
                true, true,
                "NVIDIA API Key (nvapi-...)",
                "Get NVIDIA NIM API Key", "Obtain free inference credits and keys at build.nvidia.com",
                "https://build.nvidia.com", "Get API Key ↗", true
            );

            // --- Kimi (Moonshot AI) Group ---
            add_provider_config_group (
                enterprise_page, AiProvider.KIMI,
                "Kimi (Moonshot AI)",
                "Ultra-long context window and advanced conversational intelligence",
                true, true,
                "Moonshot API Key",
                "Get Kimi / Moonshot API Key", "Manage API keys in the Moonshot developer console",
                "https://platform.moonshot.cn/console/api-keys", "Get API Key ↗", true
            );

            // --- Qwen (Alibaba DashScope) Group ---
            add_provider_config_group (
                enterprise_page, AiProvider.QWEN,
                "Qwen (Alibaba DashScope)",
                "Top-tier code generation and scientific modeling (Qwen 2.5 Coder)",
                true, true,
                "DashScope API Key",
                "Get DashScope API Key", "Manage API keys on Alibaba Cloud DashScope Console",
                "https://dashscope.console.aliyun.com/apiKey", "Get API Key ↗", true
            );

            this.add (enterprise_page);

            // ==========================================
            // Page 3: Local & Custom AI (Ollama, LM Studio, Custom)
            // ==========================================
            var local_page = new Adw.PreferencesPage () {
                title = "Local and Custom",
                icon_name = "computer-symbolic"
            };

            // --- Ollama Group ---
            add_provider_config_group (
                local_page, AiProvider.OLLAMA,
                "Ollama (Local)",
                "Run open-weights models locally via Ollama service (no API key required)",
                false, true,
                null, "", "", "", "", false
            );

            // --- LM Studio (Local Server) Group ---
            var lm_studio_group = new Adw.PreferencesGroup () {
                title = "LM Studio (Local Server)",
                description = "Connect to LM Studio's OpenAI-compatible local inference server (port 1234)",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.LM_STUDIO.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var lm_settings = config_mgr.get_settings_for (AiProvider.LM_STUDIO);

            var lm_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = lm_settings.endpoint
            };
            lm_endpoint_row.notify["text"].connect (() => {
                lm_settings.endpoint = lm_endpoint_row.text;
                config_mgr.save ();
            });
            lm_studio_group.add (lm_endpoint_row);

            var lm_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = lm_settings.model
            };
            lm_model_row.notify["text"].connect (() => {
                lm_settings.model = lm_model_row.text;
                config_mgr.save ();
            });
            lm_studio_group.add (lm_model_row);

            var lm_action_row = new Adw.ActionRow () {
                title = "LM Studio Website",
                subtitle = "Discover, download, and run any open-weights GGUF model locally with GPU acceleration"
            };
            var lm_btn = new Gtk.Button.with_label ("Visit lmstudio.ai ↗") { valign = Gtk.Align.CENTER };
            lm_btn.add_css_class ("suggested-action");
            lm_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://lmstudio.ai");
            });
            lm_action_row.add_suffix (lm_btn);
            lm_studio_group.add (lm_action_row);

            var lm_help_row = new Adw.ActionRow () {
                title = "Local Server Instructions",
                subtitle = "In LM Studio: click Developer tab (<->) on the left sidebar, load a model, and toggle 'Start Server'."
            };
            lm_studio_group.add (lm_help_row);

            local_page.add (lm_studio_group);

            // --- Cherry Studio / LocalAI Group ---
            add_provider_config_group (
                local_page, AiProvider.CHERRY_STUDIO,
                "Cherry Studio / LocalAI (Local)",
                "Connect to Cherry Studio, LocalAI, or local llama.cpp servers (ports 23333 / 8080)",
                false, true,
                null, "", "", "", "", false
            );

            // --- Antigravity Agent Harness Group ---
            var agy_group = new Adw.PreferencesGroup () {
                title = "Antigravity CLI (agy Agent Harness)",
                description = "Use Google DeepMind's agentic CLI harness (~/.local/bin/agy) for local code tasks",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.ANTIGRAVITY.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var agy_settings = config_mgr.get_settings_for (AiProvider.ANTIGRAVITY);

            var agy_model_row = new Adw.EntryRow () {
                title = "Preferred Model / Agent Profile",
                text = agy_settings.model
            };
            agy_model_row.notify["text"].connect (() => {
                agy_settings.model = agy_model_row.text;
                config_mgr.save ();
            });
            agy_group.add (agy_model_row);

            string? detected_agy = Imladris.AI.ElrondEngineController.find_agy_binary ();
            var agy_status_row = new Adw.ActionRow () {
                title = "Harness Status",
                subtitle = (detected_agy != null)
                    ? "Antigravity CLI detected: %s".printf (detected_agy)
                    : "Not found in ~/.local/bin or PATH"
            };
            agy_group.add (agy_status_row);

            local_page.add (agy_group);

            // --- Custom OpenAI Compatible Group ---
            add_provider_config_group (
                local_page, AiProvider.CUSTOM,
                "Custom OpenAI-Compatible Endpoint",
                "Connect to any provider supporting standard OpenAI /v1/chat/completions",
                true, true,
                "API Key (Optional)",
                "", "", "", "", false
            );

            var managed_group = new Adw.PreferencesGroup () {
                title = "Imladris-Managed GGUF Models",
                description = "Download curated GGUF models from Hugging Face and run them with Imladris-managed llama.cpp. Compact profiles reduce memory use but are not hard RSS limits; keep swap/zram enabled. Check each repository's model license before use."
            };
            var model_catalog = Imladris.AI.LocalModelManager.get_catalog ();
            var model_names = new Gtk.StringList (null);
            foreach (var preset in model_catalog) {
                model_names.append (preset.name);
            }
            var model_row = new Adw.ComboRow () {
                title = "Local Model",
                subtitle = "Choose a compact model or a larger specialist model.",
                model = model_names
            };
            var model_detail_row = new Adw.ActionRow () {
                title = "Model Details"
            };
            model_row.notify["selected"].connect (() => {
                int selected = (int) model_row.selected;
                if (selected >= 0 && selected < model_catalog.size) {
                    var preset = model_catalog[selected];
                    string memory_profile = preset.fits_2gb_profile
                        ? "2 GB profile: 4096 context/Q8 KV, or 2048 context/Q4 KV for Qwen3.5-2B."
                        : "Low-memory profile: 2048 context, Q8 KV, single CPU sequence.";
                    model_detail_row.subtitle = "%s Estimated footprint: %s %s".printf (
                        preset.strengths, preset.footprint, memory_profile
                    );
                }
            });
            model_row.selected = 0;
            managed_group.add (model_row);
            managed_group.add (model_detail_row);

            var repo_row = new Adw.ActionRow () {
                title = "Hugging Face Repository",
                subtitle = model_catalog[0].repository
            };
            model_row.notify["selected"].connect (() => {
                int selected = (int) model_row.selected;
                if (selected >= 0 && selected < model_catalog.size) {
                    repo_row.subtitle = model_catalog[selected].repository;
                }
            });
            var repo_button = new Gtk.Button.with_label ("Open ↗") { valign = Gtk.Align.CENTER };
            repo_button.clicked.connect (() => {
                int selected = (int) model_row.selected;
                if (selected >= 0 && selected < model_catalog.size) {
                    AiConfigManager.open_url ("https://huggingface.co/" + model_catalog[selected].repository);
                }
            });
            repo_row.add_suffix (repo_button);
            managed_group.add (repo_row);

            local_model_status = new Adw.ActionRow () {
                title = "Download Status",
                subtitle = "No managed model selected."
            };
            local_model_progress = new Gtk.ProgressBar () {
                valign = Gtk.Align.CENTER,
                width_request = 220,
                show_text = true,
                visible = false
            };
            local_model_status.add_suffix (local_model_progress);
            managed_group.add (local_model_status);

            var download_row = new Adw.ActionRow () {
                title = "Download and Run",
                subtitle = "Downloads the model, installs llama.cpp if needed, and starts the managed local server."
            };
            local_model_download_button = new Gtk.Button.with_label ("Download & Use") {
                valign = Gtk.Align.CENTER
            };
            local_model_download_button.add_css_class ("suggested-action");
            local_model_download_button.clicked.connect (() => {
                int selected = (int) model_row.selected;
                if (selected >= 0 && selected < model_catalog.size) {
                    download_and_run_local_model.begin (model_catalog[selected]);
                }
            });
            local_model_cancel_button = new Gtk.Button.with_label ("Cancel") {
                valign = Gtk.Align.CENTER,
                sensitive = false
            };
            local_model_cancel_button.clicked.connect (() => {
                if (local_model_cancellable != null) {
                    local_model_cancellable.cancel ();
                }
            });
            download_row.add_suffix (local_model_download_button);
            download_row.add_suffix (local_model_cancel_button);
            managed_group.add (download_row);

            this.local_model_manager.download_progress.connect ((model_id, fraction, status) => {
                if (local_model_progress != null && local_model_status != null) {
                    local_model_progress.fraction = fraction;
                    local_model_progress.text = "%d%%".printf ((int) (fraction * 100.0));
                    local_model_progress.visible = true;
                    local_model_status.subtitle = status;
                }
            });

            local_page.add (managed_group);
            this.add (local_page);

            // ==========================================
            // Page 4: Free-Tier APIs & Automatic Failover
            // ==========================================
            var free_page = new Adw.PreferencesPage () {
                title = "Free & Backup",
                icon_name = "network-transmit-receive-symbolic"
            };

            var failover_group = new Adw.PreferencesGroup () {
                title = "Automatic Quota Failover",
                description = "Automatically fall back to configured free-tier AI providers when your primary provider hits rate limits (HTTP 429) or quota exhaustion"
            };

            var auto_failover_row = new Adw.SwitchRow () {
                title = "Enable Automatic Free-Tier Failover",
                subtitle = "Tries Groq, Cerebras, OpenRouter Free, GitHub Models, and FreeLLMAPI Local Proxy in order",
                active = config_mgr.auto_failover_enabled
            };
            auto_failover_row.notify["active"].connect (() => {
                config_mgr.auto_failover_enabled = auto_failover_row.active;
                config_mgr.save ();
            });
            failover_group.add (auto_failover_row);

            var consent_row = new Adw.SwitchRow () {
                title = "Free Cloud AI Privacy Consent",
                subtitle = "Allow sending prompts to free-tier cloud APIs when selected or during failover",
                active = config_mgr.free_api_consent_accepted
            };
            consent_row.notify["active"].connect (() => {
                config_mgr.free_api_consent_accepted = consent_row.active;
                config_mgr.save ();
            });
            failover_group.add (consent_row);

            free_page.add (failover_group);

            add_provider_config_group (free_page, AiProvider.GROQ, "Groq (Free Tier)", "Ultra-fast Llama 3.3 70B & Mixtral inference with permanent free tier", true, false);
            add_provider_config_group (free_page, AiProvider.CEREBRAS, "Cerebras (Free Tier)", "High-speed wafer-scale inference with generous daily free tokens", true, false);
            add_provider_config_group (free_page, AiProvider.OPENROUTER_FREE, "OpenRouter (:free Models)", "Access community :free models via OpenRouter", true, false);
            add_provider_config_group (free_page, AiProvider.GITHUB_MODELS, "GitHub Models (Free Tier)", "Use your GitHub Personal Access Token (models:read) for free inference", true, false);
            add_provider_config_group (free_page, AiProvider.FREELMAPI_LOCAL, "FreeLLMAPI Local Proxy", "Local OpenAI-compatible free proxy (localhost:8000) — no API key required", false, true);

            this.add (free_page);
        }

        private async void download_and_run_local_model (Imladris.AI.LocalModelPreset preset) {
            if (local_model_download_button == null || local_model_cancel_button == null ||
                local_model_status == null || local_model_progress == null) {
                return;
            }

            local_model_cancellable = new Cancellable ();
            local_model_download_button.sensitive = false;
            local_model_cancel_button.sensitive = true;
            local_model_progress.visible = true;
            local_model_progress.fraction = 0.0;
            local_model_progress.text = "Preparing";
            local_model_status.subtitle = "Installing or checking the llama.cpp engine...";

            try {
                yield Imladris.AI.ElrondEngineController.get_default ().ensure_managed_server_async (
                    local_model_cancellable
                );
                local_model_status.subtitle = "Downloading %s from Hugging Face...".printf (preset.name);
                string model_path = yield local_model_manager.download_model_async (
                    preset, local_model_cancellable
                );
                var settings = SettingsManager.get_default ();
                settings.elrond_enabled = false;
                settings.managed_model_path = model_path;
                settings.elrond_mode = ElrondMode.MANAGED_LLAMA;
                settings.elrond_enabled = true;
                local_model_status.subtitle = "%s downloaded and selected. Starting llama-server...".printf (preset.name);
            } catch (GLib.Error e) {
                local_model_status.subtitle = "Model setup failed: %s".printf (e.message);
                local_model_progress.text = "Failed";
            } finally {
                local_model_download_button.sensitive = true;
                local_model_cancel_button.sensitive = false;
                local_model_cancellable = null;
            }
        }

        private void add_provider_config_group (
            Adw.PreferencesPage page,
            AiProvider provider,
            string title,
            string description,
            bool include_key,
            bool include_endpoint,
            string? custom_key_title = null,
            string? custom_help_title = null,
            string? custom_help_subtitle = null,
            string? custom_help_url = null,
            string? custom_btn_label = null,
            bool suggested_btn = false
        ) {
            var group = new Adw.PreferencesGroup () {
                title = title,
                description = description,
                header_suffix = new Gtk.Image.from_icon_name (provider.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };
            var settings = config_mgr.get_settings_for (provider);

            if (include_key) {
                var key_row = new Adw.PasswordEntryRow () {
                    title = custom_key_title ?? @"$(provider.get_short_name ()) API Key",
                    text = settings.api_key
                };
                key_row.notify["text"].connect (() => {
                    settings.api_key = key_row.text;
                    config_mgr.save ();
                });
                group.add (key_row);
            }

            if (include_endpoint) {
                var ep_row = new Adw.EntryRow () {
                    title = "Base Endpoint",
                    text = settings.endpoint
                };
                ep_row.notify["text"].connect (() => {
                    settings.endpoint = ep_row.text;
                    config_mgr.save ();
                });
                group.add (ep_row);
            }

            var model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = settings.model
            };
            model_row.notify["text"].connect (() => {
                settings.model = model_row.text;
                config_mgr.save ();
            });
            group.add (model_row);

            string help_url = custom_help_url != null ? custom_help_url : provider.get_api_key_help_url ();
            if (help_url.length > 0) {
                var action_row = new Adw.ActionRow () {
                    title = (custom_help_title != null && custom_help_title.length > 0)
                        ? custom_help_title
                        : (include_key ? @"Get $(provider.get_short_name ()) API Key" : @"$(provider.get_short_name ()) Documentation"),
                    subtitle = (custom_help_subtitle != null && custom_help_subtitle.length > 0)
                        ? custom_help_subtitle
                        : help_url
                };
                string btn_lbl = (custom_btn_label != null && custom_btn_label.length > 0) ? custom_btn_label : "Open ↗";
                var btn = new Gtk.Button.with_label (btn_lbl) { valign = Gtk.Align.CENTER };
                if (suggested_btn) {
                    btn.add_css_class ("suggested-action");
                }
                btn.clicked.connect (() => {
                    AiConfigManager.open_url (help_url);
                });
                action_row.add_suffix (btn);
                group.add (action_row);
            }

            page.add (group);
        }

        private static void update_copilot_ui (
            Imladris.AI.CopilotAuthService copilot_auth,
            Adw.ActionRow copilot_status_row,
            Gtk.Button copilot_auth_btn
        ) {
            if (copilot_auth.is_signed_in ()) {
                string uname = copilot_auth.get_username ();
                copilot_status_row.subtitle = uname.length > 0 ? @"Signed in as @$uname" : "Signed in to GitHub Copilot";
                copilot_auth_btn.label = "Sign Out";
                copilot_auth_btn.remove_css_class ("suggested-action");
                copilot_auth_btn.add_css_class ("destructive-action");
            } else {
                copilot_status_row.subtitle = "Not signed in — Click to authorize via GitHub";
                copilot_auth_btn.label = "Sign in with GitHub";
                copilot_auth_btn.remove_css_class ("destructive-action");
                copilot_auth_btn.add_css_class ("suggested-action");
            }
        }

        private async void start_copilot_device_flow_async () {
            var auth = Imladris.AI.CopilotAuthService.get_default ();
            var poll_cancellable = new Cancellable ();

            try {
                var info = yield auth.request_device_code_async (poll_cancellable);

                var dlg = new Adw.Dialog () {
                    title = "GitHub Copilot Login",
                    content_width = 400,
                    content_height = 290
                };
                var toolbar = new Adw.ToolbarView ();
                toolbar.add_top_bar (new Adw.HeaderBar ());

                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                    margin_top = 16,
                    margin_bottom = 20,
                    margin_start = 20,
                    margin_end = 20,
                    halign = Gtk.Align.CENTER
                };
                box.append (new Gtk.Label ("Enter this one-time code on GitHub to authorize Imladris:") {
                    wrap = true,
                    justify = Gtk.Justification.CENTER
                });

                var code_lbl = new Gtk.Label (info.user_code) {
                    selectable = true
                };
                code_lbl.add_css_class ("title-1");
                code_lbl.add_css_class ("monospace");
                box.append (code_lbl);

                var status_lbl = new Gtk.Label ("Waiting for authorization in browser...") {
                    css_classes = { "dim-label", "caption" }
                };
                box.append (status_lbl);

                var btn_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                    halign = Gtk.Align.CENTER,
                    margin_top = 8
                };
                var copy_open_btn = new Gtk.Button.with_label ("Copy Code & Open GitHub ↗");
                copy_open_btn.add_css_class ("suggested-action");
                copy_open_btn.clicked.connect (() => {
                    var display = Gdk.Display.get_default ();
                    if (display != null) {
                        display.get_clipboard ().set_text (info.user_code);
                    }
                    AiConfigManager.open_url (info.verification_uri);
                    status_lbl.label = "Code copied! Complete login in browser...";
                });
                btn_row.append (copy_open_btn);

                var cancel_btn = new Gtk.Button.with_label ("Cancel");
                cancel_btn.clicked.connect (() => {
                    poll_cancellable.cancel ();
                    dlg.close ();
                });
                btn_row.append (cancel_btn);

                box.append (btn_row);
                toolbar.set_content (box);
                dlg.set_child (toolbar);

                dlg.closed.connect (() => {
                    poll_cancellable.cancel ();
                });
                if (this.get_mapped ()) {
                    dlg.present (this);
                }

                yield auth.poll_device_token_async (info, poll_cancellable);
                string uname = auth.get_username ();
                dlg.close ();
                this.add_toast (new Adw.Toast (uname.length > 0 ? @"Signed in to GitHub Copilot as @$uname" : "Signed in to GitHub Copilot"));
            } catch (GLib.Error e) {
                if (!(e is GLib.IOError.CANCELLED)) {
                    this.add_toast (new Adw.Toast (@"Copilot login failed: $(e.message)"));
                }
            }
        }
    }
}
