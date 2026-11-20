// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Official TypeScript ambient declarations for Imladris Extensions (JSC.Context).
 * Reference this file in your tsconfig.json ("types" or "include") to get full
 * autocompletion and type checking when developing plugins in TypeScript.
 */

interface ImladrisRibbonButtonOptions {
  /** Unique button identifier within your plugin */
  id: string;
  /** Short button label displayed in the Extensions ribbon */
  label: string;
  /** GNOME / Papirus symbolic icon name (e.g. "x-office-spreadsheet-symbolic") */
  icon: string;
  /** Callback executed when the user clicks the ribbon button */
  onClick?: () => void;
  /** Alias for onClick */
  callback?: () => void;
}

interface ImladrisWebDialogOptions {
  /** Dialog title shown in the Adw.Dialog header */
  title?: string;
  /** Complete HTML5 document string rendered via WebKitGTK 6.0 */
  html: string;
  /** Preferred dialog width in pixels (default: 950) */
  width?: number;
  /** Preferred dialog height in pixels (default: 700) */
  height?: number;
}

interface ImladrisUI {
  /** Display a non-blocking native Libadwaita toast notification */
  showToast(message: string): void;
  /** Register an action button in the Ribbon bar (object form) */
  addRibbonButton(options: ImladrisRibbonButtonOptions): void;
  /** Register an action button in the Ribbon bar (positional form) */
  addRibbonButton(id: string, label: string, icon: string, callback: () => void): void;
  /** Open a hardware-accelerated WebKitGTK modal dialog (requires "ui" or "editor") */
  openWebDialog(options: ImladrisWebDialogOptions): void;
}

interface ImladrisEditor {
  /** Read full buffer text of the active editor (requires "editor" permission) */
  getText(): string;
  /** Read currently selected text in the active editor (requires "editor" permission) */
  getSelectedText(): string;
  /** Insert text at the active cursor position (requires "editor" permission) */
  insertAtCursor(text: string): void;
}

interface ImladrisRepl {
  /** Evaluate R code in the persistent R session (requires "repl_r" permission) */
  runR(code: string): void;
  /** Evaluate Python code in the persistent Python session (requires "repl_python" permission) */
  runPython(code: string): void;
}

interface ImladrisElrond {
  /** Send a prompt to Elrond AI Assistant (requires "elrond_ai" permission) */
  ask(prompt: string): void;
}

interface ImladrisWorkspace {
  /** List relative file paths matching a glob pattern (requires "workspace" permission) */
  listFiles(pattern?: string): string[];
  /** Read UTF-8 contents of a workspace file (requires "workspace" permission) */
  readFile(relativePath: string): string;
  /** Open a workspace file in a tab at the given 1-based line (requires "workspace" permission) */
  openFile(relativePath: string, line?: number): void;
  /** Absolute path to the active workspace root (requires "workspace" permission) */
  getRoot(): string;
  /** Path to the currently active document (requires "workspace" or "editor") */
  getActiveFile(): string;
}

interface ImladrisPluginAssets {
  /** Read a static asset bundled inside your plugin folder */
  readAsset(relativePath: string): string;
}

interface ImladrisHostAPI {
  readonly ui: ImladrisUI;
  readonly editor: ImladrisEditor;
  readonly repl: ImladrisRepl;
  readonly elrond: ImladrisElrond;
  readonly workspace: ImladrisWorkspace;
  readonly plugin: ImladrisPluginAssets;
}

declare const imladris: ImladrisHostAPI;

/** Lifecycle hook invoked when your plugin is enabled */
declare function onload(): void;

/** Lifecycle hook invoked when your plugin is disabled or unloaded */
declare function onunload(): void;
