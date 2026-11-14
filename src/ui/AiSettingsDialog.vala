// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;
using Gtk;
using Adw;
using Imladris.Core;

namespace Imladris.UI {

    public class AiSettingsDialog : Adw.PreferencesDialog {

        private AiConfigManager config_mgr;

        public AiSettingsDialog () {
            Object (title: "AI Engine & Model Configuration");
            this.config_mgr = AiConfigManager.get_default ();

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

            // --- Google Gemini Group ---
            var gemini_group = new Adw.PreferencesGroup () {
                title = "Google Gemini",
                description = "Google DeepMind's flagship models with state-of-the-art multimodal reasoning",
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
                gemini_settings.model = gemini_model_row.text;
                config_mgr.save ();
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
            var claude_group = new Adw.PreferencesGroup () {
                title = "Claude (Anthropic)",
                description = "Anthropic's Claude 3.5 Sonnet, 3.7 Sonnet, Haiku, and Opus via native Messages API",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.CLAUDE.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var claude_settings = config_mgr.get_settings_for (AiProvider.CLAUDE);

            var claude_key_row = new Adw.PasswordEntryRow () {
                title = "Anthropic API Key",
                text = claude_settings.api_key
            };
            claude_key_row.notify["text"].connect (() => {
                claude_settings.api_key = claude_key_row.text;
                config_mgr.save ();
            });
            claude_group.add (claude_key_row);

            var claude_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = claude_settings.endpoint
            };
            claude_endpoint_row.notify["text"].connect (() => {
                claude_settings.endpoint = claude_endpoint_row.text;
                config_mgr.save ();
            });
            claude_group.add (claude_endpoint_row);

            var claude_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = claude_settings.model
            };
            claude_model_row.notify["text"].connect (() => {
                claude_settings.model = claude_model_row.text;
                config_mgr.save ();
            });
            claude_group.add (claude_model_row);

            var claude_action_row = new Adw.ActionRow () {
                title = "Get Anthropic API Key",
                subtitle = "Manage API keys in the Anthropic Console"
            };
            var claude_btn = new Gtk.Button.with_label ("Get API Key ↗") { valign = Gtk.Align.CENTER };
            claude_btn.add_css_class ("suggested-action");
            claude_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://console.anthropic.com/settings/keys");
            });
            claude_action_row.add_suffix (claude_btn);
            claude_group.add (claude_action_row);

            frontier_page.add (claude_group);

            // --- OpenAI Group ---
            var openai_group = new Adw.PreferencesGroup () {
                title = "OpenAI",
                description = "OpenAI GPT-4o, GPT-4o-mini, o1, and o3-mini models",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.OPENAI.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var openai_settings = config_mgr.get_settings_for (AiProvider.OPENAI);

            var openai_key_row = new Adw.PasswordEntryRow () {
                title = "OpenAI API Key",
                text = openai_settings.api_key
            };
            openai_key_row.notify["text"].connect (() => {
                openai_settings.api_key = openai_key_row.text;
                config_mgr.save ();
            });
            openai_group.add (openai_key_row);

            var openai_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = openai_settings.endpoint
            };
            openai_endpoint_row.notify["text"].connect (() => {
                openai_settings.endpoint = openai_endpoint_row.text;
                config_mgr.save ();
            });
            openai_group.add (openai_endpoint_row);

            var openai_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = openai_settings.model
            };
            openai_model_row.notify["text"].connect (() => {
                openai_settings.model = openai_model_row.text;
                config_mgr.save ();
            });
            openai_group.add (openai_model_row);

            var openai_action_row = new Adw.ActionRow () {
                title = "Get OpenAI API Key",
                subtitle = "Manage API keys on the OpenAI Developer Platform"
            };
            var openai_btn = new Gtk.Button.with_label ("Get API Key ↗") { valign = Gtk.Align.CENTER };
            openai_btn.add_css_class ("suggested-action");
            openai_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://platform.openai.com/api-keys");
            });
            openai_action_row.add_suffix (openai_btn);
            openai_group.add (openai_action_row);

            frontier_page.add (openai_group);

            // --- Cursor API Compatibility Group ---
            var cursor_group = new Adw.PreferencesGroup () {
                title = "Cursor API Compatibility",
                description = "Connect using Cursor API or OpenAI-compatible Cursor proxies",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.CURSOR.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var cursor_settings = config_mgr.get_settings_for (AiProvider.CURSOR);

            var cursor_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = cursor_settings.endpoint
            };
            cursor_endpoint_row.notify["text"].connect (() => {
                cursor_settings.endpoint = cursor_endpoint_row.text;
                config_mgr.save ();
            });
            cursor_group.add (cursor_endpoint_row);

            var cursor_key_row = new Adw.PasswordEntryRow () {
                title = "Cursor API Key",
                text = cursor_settings.api_key
            };
            cursor_key_row.notify["text"].connect (() => {
                cursor_settings.api_key = cursor_key_row.text;
                config_mgr.save ();
            });
            cursor_group.add (cursor_key_row);

            var cursor_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = cursor_settings.model
            };
            cursor_model_row.notify["text"].connect (() => {
                cursor_settings.model = cursor_model_row.text;
                config_mgr.save ();
            });
            cursor_group.add (cursor_model_row);

            var cursor_action_row = new Adw.ActionRow () {
                title = "Cursor Information",
                subtitle = "Learn more about Cursor AI and developer API compatibility"
            };
            var cursor_btn = new Gtk.Button.with_label ("Visit cursor.com ↗") { valign = Gtk.Align.CENTER };
            cursor_btn.add_css_class ("suggested-action");
            cursor_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://cursor.com");
            });
            cursor_action_row.add_suffix (cursor_btn);
            cursor_group.add (cursor_action_row);

            frontier_page.add (cursor_group);

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
            var deepseek_group = new Adw.PreferencesGroup () {
                title = "DeepSeek",
                description = "High-performance coding (deepseek-chat) and reasoning (deepseek-reasoner / R1)",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.DEEPSEEK.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var ds_settings = config_mgr.get_settings_for (AiProvider.DEEPSEEK);

            var ds_key_row = new Adw.PasswordEntryRow () {
                title = "DeepSeek API Key",
                text = ds_settings.api_key
            };
            ds_key_row.notify["text"].connect (() => {
                ds_settings.api_key = ds_key_row.text;
                config_mgr.save ();
            });
            deepseek_group.add (ds_key_row);

            var ds_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = ds_settings.endpoint
            };
            ds_endpoint_row.notify["text"].connect (() => {
                ds_settings.endpoint = ds_endpoint_row.text;
                config_mgr.save ();
            });
            deepseek_group.add (ds_endpoint_row);

            var ds_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = ds_settings.model
            };
            ds_model_row.notify["text"].connect (() => {
                ds_settings.model = ds_model_row.text;
                config_mgr.save ();
            });
            deepseek_group.add (ds_model_row);

            var ds_action_row = new Adw.ActionRow () {
                title = "Get DeepSeek API Key",
                subtitle = "Manage API keys on the DeepSeek Open Platform"
            };
            var ds_btn = new Gtk.Button.with_label ("Get API Key ↗") { valign = Gtk.Align.CENTER };
            ds_btn.add_css_class ("suggested-action");
            ds_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://platform.deepseek.com/api_keys");
            });
            ds_action_row.add_suffix (ds_btn);
            deepseek_group.add (ds_action_row);

            enterprise_page.add (deepseek_group);

            // --- NVIDIA NIM Group ---
            var nvidia_group = new Adw.PreferencesGroup () {
                title = "NVIDIA NIM",
                description = "NVIDIA Inference Microservices with GPU-accelerated Llama 3.3, Nemotron, and DeepSeek R1",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.NVIDIA_NIM.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var nvidia_settings = config_mgr.get_settings_for (AiProvider.NVIDIA_NIM);

            var nvidia_key_row = new Adw.PasswordEntryRow () {
                title = "NVIDIA API Key (nvapi-...)",
                text = nvidia_settings.api_key
            };
            nvidia_key_row.notify["text"].connect (() => {
                nvidia_settings.api_key = nvidia_key_row.text;
                config_mgr.save ();
            });
            nvidia_group.add (nvidia_key_row);

            var nvidia_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = nvidia_settings.endpoint
            };
            nvidia_endpoint_row.notify["text"].connect (() => {
                nvidia_settings.endpoint = nvidia_endpoint_row.text;
                config_mgr.save ();
            });
            nvidia_group.add (nvidia_endpoint_row);

            var nvidia_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = nvidia_settings.model
            };
            nvidia_model_row.notify["text"].connect (() => {
                nvidia_settings.model = nvidia_model_row.text;
                config_mgr.save ();
            });
            nvidia_group.add (nvidia_model_row);

            var nvidia_action_row = new Adw.ActionRow () {
                title = "Get NVIDIA NIM API Key",
                subtitle = "Obtain free inference credits and keys at build.nvidia.com"
            };
            var nvidia_btn = new Gtk.Button.with_label ("Get API Key ↗") { valign = Gtk.Align.CENTER };
            nvidia_btn.add_css_class ("suggested-action");
            nvidia_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://build.nvidia.com");
            });
            nvidia_action_row.add_suffix (nvidia_btn);
            nvidia_group.add (nvidia_action_row);

            enterprise_page.add (nvidia_group);

            // --- Kimi (Moonshot AI) Group ---
            var kimi_group = new Adw.PreferencesGroup () {
                title = "Kimi (Moonshot AI)",
                description = "Ultra-long context window and advanced conversational intelligence",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.KIMI.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var kimi_settings = config_mgr.get_settings_for (AiProvider.KIMI);

            var kimi_key_row = new Adw.PasswordEntryRow () {
                title = "Moonshot API Key",
                text = kimi_settings.api_key
            };
            kimi_key_row.notify["text"].connect (() => {
                kimi_settings.api_key = kimi_key_row.text;
                config_mgr.save ();
            });
            kimi_group.add (kimi_key_row);

            var kimi_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = kimi_settings.endpoint
            };
            kimi_endpoint_row.notify["text"].connect (() => {
                kimi_settings.endpoint = kimi_endpoint_row.text;
                config_mgr.save ();
            });
            kimi_group.add (kimi_endpoint_row);

            var kimi_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = kimi_settings.model
            };
            kimi_model_row.notify["text"].connect (() => {
                kimi_settings.model = kimi_model_row.text;
                config_mgr.save ();
            });
            kimi_group.add (kimi_model_row);

            var kimi_action_row = new Adw.ActionRow () {
                title = "Get Kimi / Moonshot API Key",
                subtitle = "Manage API keys in the Moonshot developer console"
            };
            var kimi_btn = new Gtk.Button.with_label ("Get API Key ↗") { valign = Gtk.Align.CENTER };
            kimi_btn.add_css_class ("suggested-action");
            kimi_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://platform.moonshot.cn/console/api-keys");
            });
            kimi_action_row.add_suffix (kimi_btn);
            kimi_group.add (kimi_action_row);

            enterprise_page.add (kimi_group);

            // --- Qwen (Alibaba DashScope) Group ---
            var qwen_group = new Adw.PreferencesGroup () {
                title = "Qwen (Alibaba DashScope)",
                description = "Top-tier code generation and scientific modeling (Qwen 2.5 Coder)",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.QWEN.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var qwen_settings = config_mgr.get_settings_for (AiProvider.QWEN);

            var qwen_key_row = new Adw.PasswordEntryRow () {
                title = "DashScope API Key",
                text = qwen_settings.api_key
            };
            qwen_key_row.notify["text"].connect (() => {
                qwen_settings.api_key = qwen_key_row.text;
                config_mgr.save ();
            });
            qwen_group.add (qwen_key_row);

            var qwen_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = qwen_settings.endpoint
            };
            qwen_endpoint_row.notify["text"].connect (() => {
                qwen_settings.endpoint = qwen_endpoint_row.text;
                config_mgr.save ();
            });
            qwen_group.add (qwen_endpoint_row);

            var qwen_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = qwen_settings.model
            };
            qwen_model_row.notify["text"].connect (() => {
                qwen_settings.model = qwen_model_row.text;
                config_mgr.save ();
            });
            qwen_group.add (qwen_model_row);

            var qwen_action_row = new Adw.ActionRow () {
                title = "Get DashScope API Key",
                subtitle = "Manage API keys on Alibaba Cloud DashScope Console"
            };
            var qwen_btn = new Gtk.Button.with_label ("Get API Key ↗") { valign = Gtk.Align.CENTER };
            qwen_btn.add_css_class ("suggested-action");
            qwen_btn.clicked.connect (() => {
                AiConfigManager.open_url ("https://dashscope.console.aliyun.com/apiKey");
            });
            qwen_action_row.add_suffix (qwen_btn);
            qwen_group.add (qwen_action_row);

            enterprise_page.add (qwen_group);

            this.add (enterprise_page);

            // ==========================================
            // Page 3: Local & Custom AI (Ollama, LM Studio, Custom)
            // ==========================================
            var local_page = new Adw.PreferencesPage () {
                title = "Local and Custom",
                icon_name = "computer-symbolic"
            };

            // --- Ollama Group ---
            var ollama_group = new Adw.PreferencesGroup () {
                title = "Ollama (Local)",
                description = "Run open-weights models locally via Ollama service (no API key required)",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.OLLAMA.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var ollama_settings = config_mgr.get_settings_for (AiProvider.OLLAMA);

            var ollama_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = ollama_settings.endpoint
            };
            ollama_endpoint_row.notify["text"].connect (() => {
                ollama_settings.endpoint = ollama_endpoint_row.text;
                config_mgr.save ();
            });
            ollama_group.add (ollama_endpoint_row);

            var ollama_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = ollama_settings.model
            };
            ollama_model_row.notify["text"].connect (() => {
                ollama_settings.model = ollama_model_row.text;
                config_mgr.save ();
            });
            ollama_group.add (ollama_model_row);

            local_page.add (ollama_group);

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
            var cherry_group = new Adw.PreferencesGroup () {
                title = "Cherry Studio / LocalAI (Local)",
                description = "Connect to Cherry Studio, LocalAI, or local llama.cpp servers (ports 23333 / 8080)",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.CHERRY_STUDIO.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var cherry_settings = config_mgr.get_settings_for (AiProvider.CHERRY_STUDIO);

            var cherry_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = cherry_settings.endpoint
            };
            cherry_endpoint_row.notify["text"].connect (() => {
                cherry_settings.endpoint = cherry_endpoint_row.text;
                config_mgr.save ();
            });
            cherry_group.add (cherry_endpoint_row);

            var cherry_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = cherry_settings.model
            };
            cherry_model_row.notify["text"].connect (() => {
                cherry_settings.model = cherry_model_row.text;
                config_mgr.save ();
            });
            cherry_group.add (cherry_model_row);

            local_page.add (cherry_group);

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

            var agy_status_row = new Adw.ActionRow () {
                title = "Harness Status",
                subtitle = (Imladris.AI.ElrondEngineController.find_agy_binary () != null)
                    ? "Antigravity CLI detected: %s".printf (Imladris.AI.ElrondEngineController.find_agy_binary ())
                    : "Not found in ~/.local/bin or PATH"
            };
            agy_group.add (agy_status_row);

            local_page.add (agy_group);

            // --- Custom OpenAI Compatible Group ---
            var custom_group = new Adw.PreferencesGroup () {
                title = "Custom OpenAI-Compatible Endpoint",
                description = "Connect to any provider supporting standard OpenAI /v1/chat/completions",
                header_suffix = new Gtk.Image.from_icon_name (AiProvider.CUSTOM.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };

            var custom_settings = config_mgr.get_settings_for (AiProvider.CUSTOM);

            var custom_endpoint_row = new Adw.EntryRow () {
                title = "Base Endpoint",
                text = custom_settings.endpoint
            };
            custom_endpoint_row.notify["text"].connect (() => {
                custom_settings.endpoint = custom_endpoint_row.text;
                config_mgr.save ();
            });
            custom_group.add (custom_endpoint_row);

            var custom_key_row = new Adw.PasswordEntryRow () {
                title = "API Key (Optional)",
                text = custom_settings.api_key
            };
            custom_key_row.notify["text"].connect (() => {
                custom_settings.api_key = custom_key_row.text;
                config_mgr.save ();
            });
            custom_group.add (custom_key_row);

            var custom_model_row = new Adw.EntryRow () {
                title = "Model Name",
                text = custom_settings.model
            };
            custom_model_row.notify["text"].connect (() => {
                custom_settings.model = custom_model_row.text;
                config_mgr.save ();
            });
            custom_group.add (custom_model_row);

            local_page.add (custom_group);

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

        private void add_provider_config_group (
            Adw.PreferencesPage page,
            AiProvider provider,
            string title,
            string description,
            bool include_key,
            bool include_endpoint
        ) {
            var group = new Adw.PreferencesGroup () {
                title = title,
                description = description,
                header_suffix = new Gtk.Image.from_icon_name (provider.get_icon_name ()) { pixel_size = 28, valign = Gtk.Align.CENTER }
            };
            var settings = config_mgr.get_settings_for (provider);

            if (include_key) {
                var key_row = new Adw.PasswordEntryRow () {
                    title = @"$(provider.get_short_name ()) API Key",
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

            string help_url = provider.get_api_key_help_url ();
            if (help_url.length > 0) {
                var action_row = new Adw.ActionRow () {
                    title = include_key ? @"Get $(provider.get_short_name ()) API Key" : @"$(provider.get_short_name ()) Documentation",
                    subtitle = help_url
                };
                var btn = new Gtk.Button.with_label ("Open ↗") { valign = Gtk.Align.CENTER };
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
                dlg.present (this);

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
