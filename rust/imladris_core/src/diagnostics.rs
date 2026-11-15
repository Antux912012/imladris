/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct LatexLogEntry {
    pub severity: String,
    pub line: usize,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct TsSymbol {
    pub name: String,
    pub kind: String,
    pub line: usize,
    pub exported: bool,
}

pub fn parse_latex_log_json(log: &str) -> String {
    let mut entries = Vec::new();
    let lines: Vec<&str> = log.lines().collect();
    let mut i = 0usize;
    while i < lines.len() {
        let line = lines[i].trim();
        if let Some(msg) = line.strip_prefix('!') {
            let mut err_line = 0usize;
            for j in i + 1..(i + 5).min(lines.len()) {
                let nxt = lines[j].trim();
                if let Some(rest) = nxt.strip_prefix("l.") {
                    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
                    if let Ok(n) = digits.parse::<usize>() {
                        err_line = n;
                        break;
                    }
                }
            }
            entries.push(LatexLogEntry {
                severity: "error".to_string(),
                line: err_line,
                message: msg.trim().to_string(),
            });
        } else if line.contains("Warning:") {
            entries.push(LatexLogEntry {
                severity: "warning".to_string(),
                line: 0,
                message: line.to_string(),
            });
        }
        i += 1;
    }
    serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_string())
}

pub fn analyze_typescript_symbols_json(source: &str) -> String {
    let mut symbols = Vec::new();
    for (idx, raw) in source.lines().enumerate() {
        let trimmed = raw.trim();
        if trimmed.starts_with("//") || trimmed.starts_with("/*") {
            continue;
        }
        let exported = trimmed.starts_with("export ");
        let s = trimmed.strip_prefix("export ").map(str::trim).unwrap_or(trimmed);
        let s = s.strip_prefix("default ").map(str::trim).unwrap_or(s);
        let s = s.strip_prefix("declare ").map(str::trim).unwrap_or(s);
        let s = s.strip_prefix("async ").map(str::trim).unwrap_or(s);

        let kind = if s.starts_with("interface ") {
            Some("interface")
        } else if s.starts_with("type ") {
            Some("type")
        } else if s.starts_with("class ") {
            Some("class")
        } else if s.starts_with("enum ") {
            Some("enum")
        } else if s.starts_with("function ") {
            Some("function")
        } else if s.starts_with("const ") || s.starts_with("let ") {
            Some("variable")
        } else {
            None
        };

        if let Some(k) = kind {
            let after = s.split_whitespace().nth(1).unwrap_or("");
            let name: String = after
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '$')
                .collect();
            if !name.is_empty() {
                symbols.push(TsSymbol {
                    name,
                    kind: k.to_string(),
                    line: idx + 1,
                    exported,
                });
            }
        }
    }
    serde_json::to_string(&symbols).unwrap_or_else(|_| "[]".to_string())
}
