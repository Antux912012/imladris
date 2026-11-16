/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[CCode (cheader_filename = "imladris_core.h")]
namespace Imladris.Core.RustFFI {
    [CCode (cname = "imladris_free_string")]
    public void free_string (char* ptr);

    [CCode (cname = "imladris_parse_frontmatter_json")]
    public char* parse_frontmatter_json_raw (string source_utf8);

    [CCode (cname = "imladris_parse_chunks_json")]
    public char* parse_chunks_json_raw (string source_utf8, string format_code);

    [CCode (cname = "imladris_extract_outline_json")]
    public char* extract_outline_json_raw (string source_utf8, string format_code);

    [CCode (cname = "imladris_render_markdown_html")]
    public char* render_markdown_html_raw (string body_utf8, string options_json);

    [CCode (cname = "imladris_ipynb_to_editor_json")]
    public char* ipynb_to_editor_json_raw (string ipynb_json_utf8);

    [CCode (cname = "imladris_editor_to_ipynb_json")]
    public char* editor_to_ipynb_json_raw (string editor_utf8, string existing_ipynb_utf8, string outputs_map_json);

    [CCode (cname = "imladris_parse_latex_log_json")]
    public char* parse_latex_log_json_raw (string log_utf8);

    [CCode (cname = "imladris_analyze_typescript_symbols_json")]
    public char* analyze_typescript_symbols_json_raw (string ts_source_utf8);

    [CCode (cname = "imladris_analyze_manuscript_json")]
    public char* analyze_manuscript_json_raw (string source_utf8);
}
