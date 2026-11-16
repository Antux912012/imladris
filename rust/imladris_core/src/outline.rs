/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

use crate::chunks::{is_closing_fence, parse_opening_fence};
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct OutlineItem {
    pub level: usize,
    pub title: String,
    pub line: usize,
    pub kind: String,
}

fn extract_braced_arg(s: &str) -> Option<String> {
    let start = s.find('{')?;
    let mut depth = 0usize;
    let mut out = String::new();
    for ch in s[start + 1..].chars() {
        if ch == '{' {
            depth += 1;
            out.push(ch);
        } else if ch == '}' {
            if depth == 0 {
                return Some(out.trim().to_string());
            }
            depth -= 1;
            out.push(ch);
        } else {
            out.push(ch);
        }
    }
    None
}

pub fn extract_outline_json(source: &str, format_code: &str) -> String {
    let fmt = format_code.trim().to_ascii_lowercase();
    let lines: Vec<&str> = source
        .split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect();
    let mut items = Vec::new();

    if fmt == "tex" || fmt == "latex" || fmt == "ltx" {
        for (idx, raw) in lines.iter().enumerate() {
            let line = raw.trim();
            if line.starts_with('%') {
                continue;
            }
            let (lvl, kind) = if line.starts_with("\\part") {
                (1, "section")
            } else if line.starts_with("\\chapter") {
                (1, "section")
            } else if line.starts_with("\\section") {
                (2, "section")
            } else if line.starts_with("\\subsection") {
                (3, "section")
            } else if line.starts_with("\\subsubsection") {
                (4, "section")
            } else if line.starts_with("\\begin{frame}") {
                let after = &line["\\begin{frame}".len()..];
                if let Some(t) = extract_braced_arg(after) {
                    items.push(OutlineItem {
                        level: 2,
                        title: t,
                        line: idx + 1,
                        kind: "frame".to_string(),
                    });
                }
                continue;
            } else {
                continue;
            };
            if let Some(title) = extract_braced_arg(line) {
                items.push(OutlineItem {
                    level: lvl,
                    title,
                    line: idx + 1,
                    kind: kind.to_string(),
                });
            }
        }
        return serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string());
    }

    if fmt == "ts" || fmt == "tsx" || fmt == "mts" || fmt == "cts" || fmt == "typescript" {
        for (idx, raw) in lines.iter().enumerate() {
            let line = raw.trim();
            if line.starts_with("//") || line.starts_with("/*") || line.starts_with('*') {
                continue;
            }
            let stripped = line.strip_prefix("export ").map(str::trim).unwrap_or(line);
            let stripped = stripped.strip_prefix("default ").map(str::trim).unwrap_or(stripped);
            let stripped = stripped.strip_prefix("declare ").map(str::trim).unwrap_or(stripped);
            let stripped = stripped.strip_prefix("async ").map(str::trim).unwrap_or(stripped);

            let kind_opt = if stripped.starts_with("class ") {
                Some(("class", 1))
            } else if stripped.starts_with("interface ") {
                Some(("interface", 1))
            } else if stripped.starts_with("type ") {
                Some(("type", 2))
            } else if stripped.starts_with("enum ") {
                Some(("enum", 1))
            } else if stripped.starts_with("function ") {
                Some(("function", 2))
            } else if stripped.starts_with("const ") && stripped.contains("=>") {
                Some(("function", 2))
            } else {
                None
            };

            if let Some((kind, level)) = kind_opt {
                let after_kw = stripped.split_whitespace().nth(1).unwrap_or("");
                let name: String = after_kw
                    .chars()
                    .take_while(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '$')
                    .collect();
                if !name.is_empty() {
                    items.push(OutlineItem {
                        level,
                        title: name,
                        line: idx + 1,
                        kind: kind.to_string(),
                    });
                }
            }
        }
        return serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string());
    }

    if fmt == "html" || fmt == "htm" {
        for (idx, raw) in lines.iter().enumerate() {
            let lower = raw.to_ascii_lowercase();
            for h in 1..=6usize {
                let open = format!("<h{h}");
                let close = format!("</h{h}>");
                if let Some(pos) = lower.find(&open) {
                    if let Some(gt) = raw[pos..].find('>') {
                        let rest = &raw[pos + gt + 1..];
                        let title = if let Some(end) = rest.to_ascii_lowercase().find(&close) {
                            rest[..end].trim().to_string()
                        } else {
                            rest.trim().to_string()
                        };
                        if !title.is_empty() {
                            items.push(OutlineItem {
                                level: h,
                                title,
                                line: idx + 1,
                                kind: "heading".to_string(),
                            });
                        }
                    }
                }
            }
        }
        return serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string());
    }

    // Markdown / Quarto / RMarkdown / Notebook
    let mut i = 0usize;
    if !lines.is_empty() && lines[0].trim() == "---" {
        for j in 1..lines.len() {
            let t = lines[j].trim();
            if t == "---" || t == "..." {
                i = j + 1;
                break;
            }
        }
    }

    let mut active_fence: Option<(char, usize)> = None;
    while i < lines.len() {
        let line = lines[i];
        if let Some((fc, flen)) = active_fence {
            if is_closing_fence(line, fc, flen) {
                active_fence = None;
            }
            i += 1;
            continue;
        }
        if let Some(fence) = parse_opening_fence(line) {
            if fence.info.starts_with('{') && fence.info.ends_with('}') {
                let inner = fence.info[1..fence.info.len() - 1].trim();
                let mut head_parts = inner
                    .split(',')
                    .next()
                    .unwrap_or("")
                    .split_whitespace();
                let engine = head_parts.next().unwrap_or("").trim();
                let mut chunk_label = head_parts
                    .next()
                    .filter(|s| !s.contains('='))
                    .unwrap_or("")
                    .to_string();

                if chunk_label.is_empty() {
                    for peek in lines.iter().skip(i + 1).take(12) {
                        let ts = peek.trim_start();
                        let Some(rest) = ts
                            .strip_prefix("#|")
                            .or_else(|| ts.strip_prefix("--|"))
                            .or_else(|| ts.strip_prefix("//|"))
                        else {
                            break;
                        };
                        if let Some((k, v)) = rest.split_once(':') {
                            if k.trim() == "label" {
                                chunk_label = v.trim().trim_matches('"').trim_matches('\'').to_string();
                                break;
                            }
                        }
                    }
                }

                let title = if !chunk_label.is_empty() && !engine.is_empty() {
                    format!("Chunk: {chunk_label} ({engine})")
                } else if !engine.is_empty() {
                    format!("Chunk: {engine}")
                } else {
                    String::new()
                };
                if !title.is_empty() {
                    items.push(OutlineItem {
                        level: 4,
                        title,
                        line: i + 1,
                        kind: "chunk".to_string(),
                    });
                }
            }
            active_fence = Some((fence.fence_char, fence.fence_len));
            i += 1;
            continue;
        }

        let trimmed = line.trim_start();
        let hashes = trimmed.bytes().take_while(|&b| b == b'#').count();
        if (1..=6).contains(&hashes) && trimmed.as_bytes().get(hashes) == Some(&b' ') {
            let title = trimmed[hashes + 1..].trim().trim_end_matches('#').trim().to_string();
            if !title.is_empty() {
                items.push(OutlineItem {
                    level: hashes,
                    title,
                    line: i + 1,
                    kind: "heading".to_string(),
                });
            }
        }
        i += 1;
    }

    serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string())
}
