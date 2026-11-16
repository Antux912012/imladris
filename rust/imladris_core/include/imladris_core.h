/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#ifndef IMLADRIS_CORE_H
#define IMLADRIS_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

void imladris_free_string(char *ptr);

char *imladris_parse_frontmatter_json(const char *source_utf8);
char *imladris_parse_chunks_json(const char *source_utf8, const char *format_code);
char *imladris_extract_outline_json(const char *source_utf8, const char *format_code);
char *imladris_render_markdown_html(const char *body_utf8, const char *options_json);
char *imladris_ipynb_to_editor_json(const char *ipynb_json_utf8);
char *imladris_editor_to_ipynb_json(const char *editor_utf8, const char *existing_ipynb_utf8, const char *outputs_map_json);
char *imladris_parse_latex_log_json(const char *log_utf8);
char *imladris_analyze_typescript_symbols_json(const char *ts_source_utf8);
char *imladris_analyze_manuscript_json(const char *source_utf8);

#ifdef __cplusplus
}
#endif

#endif /* IMLADRIS_CORE_H */
