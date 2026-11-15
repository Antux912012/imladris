/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

use serde::Serialize;
use serde_yaml_ng::Value as YamlValue;

#[derive(Debug, Clone, Serialize)]
pub struct ParsedChunk {
    pub index: usize,
    pub kind: String,
    pub language: String,
    pub is_executable: bool,
    pub label: String,
    pub eval_enabled: bool,
    pub echo: bool,
    pub include: bool,
    pub output_mode: String,
    pub warning: bool,
    pub error: bool,
    pub fig_cap: String,
    pub fig_width: Option<f64>,
    pub fig_height: Option<f64>,
    pub raw_header: String,
    pub code: String,
    pub fence_start_line: usize,
    pub fence_end_line: usize,
    pub code_start_line: usize,
    pub code_end_line: usize,
    pub unclosed_eof: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct FenceMatch {
    pub fence_char: char,
    pub fence_len: usize,
    pub info: String,
}

pub(crate) fn parse_opening_fence(line: &str) -> Option<FenceMatch> {
    let bytes = line.as_bytes();
    let mut indent = 0usize;
    while indent < bytes.len() && indent < 3 && bytes[indent] == b' ' {
        indent += 1;
    }
    if indent >= bytes.len() {
        return None;
    }
    let ch = bytes[indent] as char;
    if ch != '`' && ch != '~' {
        return None;
    }
    let mut len = 0usize;
    while indent + len < bytes.len() && bytes[indent + len] as char == ch {
        len += 1;
    }
    if len < 3 {
        return None;
    }
    let info = line[indent + len..].trim().to_string();
    // CommonMark: backtick info string cannot contain backticks
    if ch == '`' && info.contains('`') {
        return None;
    }
    Some(FenceMatch {
        fence_char: ch,
        fence_len: len,
        info,
    })
}

pub(crate) fn is_closing_fence(line: &str, fence_char: char, min_len: usize) -> bool {
    let bytes = line.as_bytes();
    let mut indent = 0usize;
    while indent < bytes.len() && indent < 3 && bytes[indent] == b' ' {
        indent += 1;
    }
    let mut len = 0usize;
    while indent + len < bytes.len() && bytes[indent + len] as char == fence_char {
        len += 1;
    }
    if len < min_len {
        return false;
    }
    line[indent + len..].trim().is_empty()
}

fn split_rmd_args(inner: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut cur = String::new();
    let mut in_quote: Option<char> = None;
    let mut escaped = false;
    for c in inner.chars() {
        if escaped {
            cur.push(c);
            escaped = false;
            continue;
        }
        if c == '\\' {
            cur.push(c);
            escaped = true;
            continue;
        }
        if let Some(q) = in_quote {
            if c == q {
                in_quote = None;
            }
            cur.push(c);
            continue;
        }
        if c == '"' || c == '\'' {
            in_quote = Some(c);
            cur.push(c);
            continue;
        }
        if c == ',' {
            let trimmed = cur.trim().to_string();
            if !trimmed.is_empty() {
                parts.push(trimmed);
            }
            cur.clear();
        } else {
            cur.push(c);
        }
    }
    let trimmed = cur.trim().to_string();
    if !trimmed.is_empty() {
        parts.push(trimmed);
    }
    parts
}

fn parse_bool_str(val: &str) -> Option<bool> {
    match val.trim().trim_matches('"').trim_matches('\'').to_ascii_lowercase().as_str() {
        "true" | "t" | "1" | "yes" => Some(true),
        "false" | "f" | "0" | "no" => Some(false),
        _ => None,
    }
}

fn normalize_engine(raw: &str) -> String {
    match raw.trim().to_ascii_lowercase().as_str() {
        "py" | "python3" | "python" => "python".to_string(),
        "ts" | "typescript" => "typescript".to_string(),
        "sh" | "bash" => "bash".to_string(),
        "r" => "r".to_string(),
        other => other.to_string(),
    }
}

pub fn parse_chunks(source: &str, _format_code: &str) -> Vec<ParsedChunk> {
    let normalized = source.replace("\r\n", "\n");
    let lines: Vec<&str> = normalized.split('\n').collect();
    let mut chunks = Vec::new();
    let mut i = 0usize;

    // Skip leading YAML frontmatter so `---` doesn't interact with parsing
    if !lines.is_empty() && lines[0].trim() == "---" {
        for j in 1..lines.len() {
            let t = lines[j].trim();
            if t == "---" || t == "..." {
                i = j + 1;
                break;
            }
        }
    }

    while i < lines.len() {
        let Some(fence) = parse_opening_fence(lines[i]) else {
            i += 1;
            continue;
        };

        let start_line = i;
        let mut end_line = None;
        let mut j = i + 1;
        while j < lines.len() {
            if is_closing_fence(lines[j], fence.fence_char, fence.fence_len) {
                end_line = Some(j);
                break;
            }
            j += 1;
        }

        let (close_idx, unclosed_eof) = match end_line {
            Some(idx) => (idx, false),
            None => (lines.len().saturating_sub(1), true),
        };

        let info = fence.info.trim();
        let mut kind = "display".to_string();
        let mut language = info.split_whitespace().next().unwrap_or("").to_string();
        let mut is_executable = false;
        let mut label = String::new();
        let mut eval_enabled = true;
        let mut echo = true;
        let mut include = true;
        let mut output_mode = "true".to_string();
        let mut warning = true;
        let mut error = false;
        let mut fig_cap = String::new();
        let mut fig_width = None;
        let mut fig_height = None;

        if info.starts_with('{') && info.ends_with('}') && info.len() >= 2 {
            let inner = info[1..info.len() - 1].trim();
            let tokens = split_rmd_args(inner);
            if let Some(first) = tokens.first() {
                // `{r setup}` or `{r, echo=FALSE}`
                let mut head_parts = first.split_whitespace();
                let raw_lang = head_parts.next().unwrap_or("");
                language = normalize_engine(raw_lang);
                if let Some(lbl) = head_parts.next() {
                    if !lbl.contains('=') {
                        label = lbl.to_string();
                    }
                }
                if language == "mermaid" {
                    kind = "diagram_mermaid".to_string();
                    is_executable = false;
                } else if !language.is_empty() {
                    kind = "executable".to_string();
                    is_executable = true;
                }
            }
            for tok in tokens.iter().skip(1) {
                if let Some((k, v)) = tok.split_once('=') {
                    let key = k.trim().to_ascii_lowercase();
                    let val = v.trim();
                    match key.as_str() {
                        "eval" => {
                            if let Some(b) = parse_bool_str(val) {
                                eval_enabled = b;
                            }
                        }
                        "echo" => {
                            if let Some(b) = parse_bool_str(val) {
                                echo = b;
                            }
                        }
                        "include" => {
                            if let Some(b) = parse_bool_str(val) {
                                include = b;
                            }
                        }
                        "warning" => {
                            if let Some(b) = parse_bool_str(val) {
                                warning = b;
                            }
                        }
                        "error" => {
                            if let Some(b) = parse_bool_str(val) {
                                error = b;
                            }
                        }
                        "label" => label = val.trim_matches('"').trim_matches('\'').to_string(),
                        "fig.cap" | "fig-cap" => fig_cap = val.trim_matches('"').trim_matches('\'').to_string(),
                        "fig.width" | "fig-width" => fig_width = val.parse::<f64>().ok(),
                        "fig.height" | "fig-height" => fig_height = val.parse::<f64>().ok(),
                        _ => {}
                    }
                } else if label.is_empty() {
                    label = tok.trim().to_string();
                }
            }
        } else if language.eq_ignore_ascii_case("mermaid") {
            kind = "diagram_mermaid".to_string();
            language = "mermaid".to_string();
            is_executable = false;
        }

        let body_end_exclusive = if unclosed_eof { lines.len() } else { close_idx };
        let mut yaml_lines = Vec::new();
        let mut code_lines = Vec::new();
        let mut in_quarto_header = true;
        let mut code_start_line = start_line + 1;

        for (offset, raw_line) in lines[start_line + 1..body_end_exclusive].iter().enumerate() {
            let trimmed_start = raw_line.trim_start();
            if in_quarto_header && trimmed_start.starts_with("#|") {
                yaml_lines.push(trimmed_start[2..].trim_start().to_string());
                code_start_line = start_line + 1 + offset + 1;
            } else {
                in_quarto_header = false;
                code_lines.push(*raw_line);
            }
        }

        if !yaml_lines.is_empty() {
            let yaml_str = yaml_lines.join("\n");
            if let Ok(YamlValue::Mapping(map)) = serde_yaml_ng::from_str::<YamlValue>(&yaml_str) {
                for (k, v) in map {
                    let Some(ks) = k.as_str() else { continue };
                    match ks {
                        "label" => if let Some(s) = v.as_str() { label = s.to_string(); },
                        "eval" => if let Some(b) = v.as_bool() { eval_enabled = b; },
                        "echo" => if let Some(b) = v.as_bool() { echo = b; },
                        "include" => if let Some(b) = v.as_bool() { include = b; },
                        "warning" => if let Some(b) = v.as_bool() { warning = b; },
                        "error" => if let Some(b) = v.as_bool() { error = b; },
                        "output" => {
                            if let Some(b) = v.as_bool() {
                                output_mode = if b { "true" } else { "false" }.to_string();
                            } else if let Some(s) = v.as_str() {
                                output_mode = s.to_string();
                            }
                        }
                        "fig-cap" => if let Some(s) = v.as_str() { fig_cap = s.to_string(); },
                        "fig-width" => fig_width = v.as_f64(),
                        "fig-height" => fig_height = v.as_f64(),
                        _ => {}
                    }
                }
            }
        }

        let code_end_line = if body_end_exclusive > code_start_line {
            body_end_exclusive - 1
        } else {
            code_start_line
        };

        chunks.push(ParsedChunk {
            index: chunks.len(),
            kind,
            language,
            is_executable,
            label,
            eval_enabled,
            echo,
            include,
            output_mode,
            warning,
            error,
            fig_cap,
            fig_width,
            fig_height,
            raw_header: info.to_string(),
            code: code_lines.join("\n"),
            fence_start_line: start_line,
            fence_end_line: close_idx,
            code_start_line,
            code_end_line,
            unclosed_eof,
        });

        i = if unclosed_eof { lines.len() } else { close_idx + 1 };
    }

    chunks
}

pub fn parse_chunks_json(source: &str, format_code: &str) -> String {
    let chunks = parse_chunks(source, format_code);
    serde_json::to_string(&chunks).unwrap_or_else(|_| "[]".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_json_fence_is_not_executable_and_eval_first_stays_true() {
        let doc = "```json\n{\"a\":1}\n```\n\n````{r setup, eval=first}\n#| echo: false\n#| fig-cap: \"Plot\"\nx <- 1\n```\nprint(x)\n````\n";
        let chunks = parse_chunks(doc, "qmd");
        assert_eq!(chunks.len(), 2);
        assert!(!chunks[0].is_executable);
        assert_eq!(chunks[0].kind, "display");
        assert!(chunks[1].is_executable);
        assert_eq!(chunks[1].language, "r");
        assert_eq!(chunks[1].label, "setup");
        assert!(chunks[1].eval_enabled);
        assert!(!chunks[1].echo);
        assert_eq!(chunks[1].fig_cap, "Plot");
        assert!(chunks[1].code.contains("```"));
    }

    #[test]
    fn unclosed_eof_chunk_is_recorded() {
        let doc = "```{python}\nprint(42)\n";
        let chunks = parse_chunks(doc, "qmd");
        assert_eq!(chunks.len(), 1);
        assert!(chunks[0].unclosed_eof);
        assert!(chunks[0].is_executable);
    }
}
