# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later

project('imladris', 'vala', 'c',
  version: '0.23.0',
  default_options: ['warning_level=1']
)

gnome = import('gnome')
cc = meson.get_compiler('c')
m_dep = cc.find_library('m', required: false)

deps = [
  dependency('gtk4', version: '>= 4.12'),
  dependency('libadwaita-1', version: '>= 1.5'),
  dependency('gtksourceview-5', version: '>= 5.10'),
  dependency('webkitgtk-6.0'),
  dependency('javascriptcoregtk-6.0'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('libsecret-1', version: '>= 0.20'),
  dependency('gee-0.8'),
  dependency('gio-2.0'),
  dependency('glib-2.0'),
  m_dep,
]

resources = gnome.compile_resources(
  'imladris-resources',
  'data/imladris.gresource.xml',
  source_dir: 'data',
  c_name: 'imladris'
)

sources = files(
  'src/main.vala',
  'src/Application.vala',
  'src/RibbonFactory.vala',
  'src/PopoverFactory.vala',
  'src/SmartRibbonHelpers.vala',
  'src/DocumentPage.vala',
  'src/ExecutionEngine.vala',
  'src/AiClient.vala',
  'src/ai/ElrondEngineController.vala',
  'src/ai/AiCompletionProvider.vala',
  'src/McpServer.vala',
  'src/AssistantPanel.vala',
  'src/Window.vala',
  'src/console/ReplBridge.vala',
  'src/editor/ChunkExecutionEngine.vala',
  'src/editor/CodeIntelliSenseEngine.vala',
  'src/editor/CodeIntelliSenseProvider.vala',
  'src/core/frontmatter_parser.vala',
  'src/core/notebook_serializer.vala',
  'src/core/project_scaffolder.vala',
  'src/core/MallornManager.vala',
  'src/core/ChunkParser.vala',
  'src/core/MathChemEngine.vala',
  'src/core/MermaidFlowEngine.vala',
  'src/core/QuartoExportEngine.vala',
  'src/adapters/DocumentAdapter.vala',
  'src/services/RecoveryService.vala',
  'src/services/WorkspaceStateManager.vala',
  'src/services/SandboxController.vala',
  'src/services/PersistentSessionManager.vala',
  'src/services/HistoryManager.vala',
  'src/services/ZoteroService.vala',
  'src/services/ShinyService.vala',
  'src/editor/CitationCompletionProvider.vala',
  'src/services/ExportService.vala',
  'src/services/MediaHelper.vala',
  'src/services/PackageIndexCache.vala',
  'src/plugins/PluginManager.vala',
  'src/bridges/galaxy_models.vala',
  'src/bridges/galaxy_client.vala',
  'src/bridges/galaxy_chunk_generator.vala',
  'src/bridges/ArekyerBridge.vala',
  'src/bridges/yavanna/BioEntityPopover.vala',
  'src/bridges/taniquetil/AlphaFoldBridgePopover.vala',
  'src/bridges/elbereth/ClinicalBiostatsPopover.vala',
  'src/core/ProvenanceAttestationService.vala',
  'src/ui/galaxy_auth_dialog.vala',
  'src/ui/galaxy_panel.vala',
  'src/core/layout/DockTypes.vala',
  'src/ui/PersistentPanelRegistry.vala',
  'src/ui/ShinyWindow.vala',
  'src/ui/RStudioDockGrid.vala',
  'src/ui/DataGridViewer.vala',
  'src/ui/EnvironmentController.vala',
  'src/ui/ElrondChatPanel.vala',
  'src/ui/LayoutSerializer.vala',
  'src/ui/WorkspaceDockManager.vala',
  'src/ui/new_project_dialog.vala',
  'src/ui/rproj_dialog.vala',
  'src/ui/MathChemEditorDialog.vala',
  'src/ui/MermaidFlowStudioDialog.vala',
  'src/ui/PresentationTemplateDialog.vala',
  'src/ui/CommandPaletteDialog.vala',
  'src/ui/PackagesRibbonBar.vala',
  'src/ui/InlineChunkOutputWidget.vala',
  'src/ui/WebViewFactory.vala',
  'src/ui/PreferencesDialog.vala',
  'src/ui/ThemeSelectorWidget.vala',
  'src/ui/AccentColorSelectorWidget.vala',
  'src/ui/AiSettingsDialog.vala',
  'src/ui/ToolchainSetupDialog.vala',
  'src/core/SettingsManager.vala',
  'src/core/AiConfigManager.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
)

executable('imladris',
  sources,
  resources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
  install: true
)

install_data(
  'data/io.github.Antux912012.Imladris.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data(
  'data/io.github.Antux912012.Imladris.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo'
)

install_data(
  'data/io.github.Antux912012.Imladris.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

gnome.post_install(glib_compile_schemas: true)

install_data(
  'scripts/install-llama-server.sh',
  install_dir: get_option('datadir') / 'imladris' / 'scripts'
)

install_subdir(
  'data/icons/hicolor',
  install_dir: get_option('datadir') / 'icons'
)

test_sources = files(
  'tests/test_mallorn_sandbox.vala',
  'src/core/frontmatter_parser.vala',
  'src/core/notebook_serializer.vala',
  'src/core/project_scaffolder.vala',
  'src/core/MallornManager.vala',
  'src/core/MathChemEngine.vala',
  'src/core/MermaidFlowEngine.vala',
  'src/core/QuartoExportEngine.vala',
  'src/adapters/DocumentAdapter.vala',
  'src/services/SandboxController.vala',
  'src/services/PersistentSessionManager.vala',
  'src/services/HistoryManager.vala',
  'src/services/ExportService.vala',
  'src/services/MediaHelper.vala',
  'src/core/ChunkParser.vala',
  'src/console/ReplBridge.vala',
  'src/editor/ChunkExecutionEngine.vala',
  'src/editor/CodeIntelliSenseEngine.vala',
  'src/ui/InlineChunkOutputWidget.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
  'src/bridges/elbereth/ClinicalBiostatsPopover.vala',
)

test_exe = executable('test_mallorn_sandbox',
  test_sources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
)

test('mallorn_sandbox_tests', test_exe, timeout: 120)

ai_test_sources = files(
  'tests/test_ai_integration.vala',
  'src/core/AiConfigManager.vala',
  'src/core/SettingsManager.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
  'src/ai/ElrondEngineController.vala',
)

ai_test_exe = executable('test_ai_integration',
  ai_test_sources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
)

test('ai_integration_tests', ai_test_exe, timeout: 30)

plugin_test_sources = files(
  'tests/test_plugin_engine.vala',
  'src/plugins/PluginManager.vala',
  'src/core/frontmatter_parser.vala',
  'src/core/notebook_serializer.vala',
  'src/core/project_scaffolder.vala',
  'src/core/MallornManager.vala',
  'src/core/MathChemEngine.vala',
  'src/core/MermaidFlowEngine.vala',
  'src/core/QuartoExportEngine.vala',
  'src/adapters/DocumentAdapter.vala',
  'src/services/SandboxController.vala',
  'src/services/PersistentSessionManager.vala',
  'src/services/HistoryManager.vala',
  'src/services/ExportService.vala',
  'src/services/MediaHelper.vala',
  'src/core/ChunkParser.vala',
  'src/console/ReplBridge.vala',
  'src/editor/ChunkExecutionEngine.vala',
  'src/editor/CodeIntelliSenseEngine.vala',
  'src/ui/InlineChunkOutputWidget.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
)

plugin_test_exe = executable('test_plugin_engine',
  plugin_test_sources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
)

test('plugin_engine_tests', plugin_test_exe, timeout: 30)

dock_test_sources = files(
  'tests/test_dock_environment.vala',
  'src/core/frontmatter_parser.vala',
  'src/core/notebook_serializer.vala',
  'src/core/project_scaffolder.vala',
  'src/core/MallornManager.vala',
  'src/core/MathChemEngine.vala',
  'src/core/MermaidFlowEngine.vala',
  'src/core/QuartoExportEngine.vala',
  'src/adapters/DocumentAdapter.vala',
  'src/services/SandboxController.vala',
  'src/services/PersistentSessionManager.vala',
  'src/services/HistoryManager.vala',
  'src/services/ExportService.vala',
  'src/services/MediaHelper.vala',
  'src/core/ChunkParser.vala',
  'src/console/ReplBridge.vala',
  'src/editor/ChunkExecutionEngine.vala',
  'src/editor/CodeIntelliSenseEngine.vala',
  'src/ui/InlineChunkOutputWidget.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
  'src/core/layout/DockTypes.vala',
  'src/ui/LayoutSerializer.vala',
  'src/ui/DataGridViewer.vala',
  'src/ui/EnvironmentController.vala',
)

dock_test_exe = executable('test_dock_environment',
  dock_test_sources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
)

test('dock_environment_tests', dock_test_exe, timeout: 30)

zotero_test_sources = files(
  'tests/test_zotero_service.vala',
  'src/services/ZoteroService.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
)

zotero_test_exe = executable('test_zotero_service',
  zotero_test_sources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
)

test('zotero_service_tests', zotero_test_exe, timeout: 30)

shiny_test_sources = files(
  'tests/test_shiny_service.vala',
  'src/services/ShinyService.vala',
  'src/core/frontmatter_parser.vala',
  'src/core/notebook_serializer.vala',
  'src/core/project_scaffolder.vala',
  'src/core/MallornManager.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
  'src/services/SandboxController.vala',
  'src/services/PersistentSessionManager.vala',
  'src/services/HistoryManager.vala',
  'src/services/ExportService.vala',
  'src/services/MediaHelper.vala',
  'src/core/MathChemEngine.vala',
  'src/adapters/DocumentAdapter.vala',
  'src/core/ChunkParser.vala',
  'src/console/ReplBridge.vala',
  'src/editor/ChunkExecutionEngine.vala',
)

shiny_test_exe = executable('test_shiny_service',
  shiny_test_sources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
)

test('shiny_service_tests', shiny_test_exe, timeout: 30)

galaxy_test_sources = files(
  'tests/test_galaxy_bridge.vala',
  'src/bridges/galaxy_models.vala',
  'src/bridges/galaxy_chunk_generator.vala',
  'src/bridges/galaxy_client.vala',
  'src/bridges/ArekyerBridge.vala',
  'src/core/ProvenanceAttestationService.vala',
  'src/core/PlatformUtils.vala',
  'src/core/ToolchainManager.vala',
)

galaxy_test_exe = executable('test_galaxy_bridge',
  galaxy_test_sources,
  dependencies: deps,
  vala_args: ['--target-glib=2.76'],
)

test('galaxy_bridge_tests', galaxy_test_exe, timeout: 30)




