/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: Apache-2.0
 */

use serde::Serialize;
use serde_json::{json, Value as JsonValue};
use serde_yaml_ng::Value as YamlValue;

#[derive(Debug, Serialize)]
pub struct FrontmatterResult {
    pub has_frontmatter: bool,
    pub raw_yaml: String,
    pub body: String,
    pub body_start_line: usize,
    pub title: String,
    pub author: String,
    pub date: String,
    pub bibliography: String,
    pub csl: String,
    pub runtime: String,
    pub server: String,
    pub format_summary: String,
    pub yaml: JsonValue,
    pub error: Option<String>,
}

fn yaml_to_json(v: &YamlValue) -> JsonValue {
    match v {
        YamlValue::Null => JsonValue::Null,
        YamlValue::Bool(b) => JsonValue::Bool(*b),
        YamlValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                JsonValue::from(i)
            } else if let Some(u) = n.as_u64() {
                JsonValue::from(u)
            } else if let Some(f) = n.as_f64() {
                JsonValue::from(f)
            } else {
                JsonValue::String(n.to_string())
            }
        }
        YamlValue::String(s) => JsonValue::String(s.clone()),
        YamlValue::Sequence(seq) => JsonValue::Array(seq.iter().map(yaml_to_json).collect()),
        YamlValue::Mapping(map) => {
            let mut obj = serde_json::Map::new();
            for (k, val) in map {
                let key_str = match k {
                    YamlValue::String(s) => s.clone(),
                    _ => serde_yaml_ng::to_string(k).unwrap_or_default().trim().to_string(),
                };
                obj.insert(key_str, yaml_to_json(val));
            }
            JsonValue::Object(obj)
        }
        YamlValue::Tagged(tagged) => yaml_to_json(&tagged.value),
    }
}

fn get_str_field(obj: &JsonValue, key: &str) -> String {
    match obj.get(key) {
        Some(JsonValue::String(s)) => s.clone(),
        Some(JsonValue::Number(n)) => n.to_string(),
        Some(JsonValue::Bool(b)) => b.to_string(),
        Some(JsonValue::Array(arr)) => arr
            .iter()
            .filter_map(|x| x.as_str())
            .collect::<Vec<_>>()
            .join(", "),
        _ => String::new(),
    }
}

pub fn split_frontmatter(source: &str) -> (bool, String, String, usize) {
    let lines: Vec<&str> = source
        .split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect();
    if lines.is_empty() || lines[0].trim() != "---" {
        return (false, String::new(), source.to_string(), 0);
    }

    for (idx, line) in lines.iter().enumerate().skip(1) {
        let t = line.trim();
        if t == "---" || t == "..." {
            let raw_yaml = lines[1..idx].join("\n");
            let body = if idx + 1 < lines.len() {
                lines[idx + 1..].join("\n")
            } else {
                String::new()
            };
            return (true, raw_yaml, body, idx + 1);
        }
    }

    (false, String::new(), source.to_string(), 0)
}

pub fn parse_frontmatter_json(source: &str) -> String {
    let (has_fm, raw_yaml, body, body_start_line) = split_frontmatter(source);
    if !has_fm {
        let res = FrontmatterResult {
            has_frontmatter: false,
            raw_yaml: String::new(),
            body,
            body_start_line: 0,
            title: String::new(),
            author: String::new(),
            date: String::new(),
            bibliography: String::new(),
            csl: String::new(),
            runtime: String::new(),
            server: String::new(),
            format_summary: String::new(),
            yaml: json!({}),
            error: None,
        };
        return serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string());
    }

    match serde_yaml_ng::from_str::<YamlValue>(&raw_yaml) {
        Ok(yval) => {
            let jval = yaml_to_json(&yval);
            let format_summary = match jval.get("format").or_else(|| jval.get("output")) {
                Some(JsonValue::String(s)) => s.clone(),
                Some(JsonValue::Object(map)) => map.keys().cloned().collect::<Vec<_>>().join(", "),
                _ => String::new(),
            };
            let res = FrontmatterResult {
                has_frontmatter: true,
                raw_yaml,
                body,
                body_start_line,
                title: get_str_field(&jval, "title"),
                author: get_str_field(&jval, "author"),
                date: get_str_field(&jval, "date"),
                bibliography: get_str_field(&jval, "bibliography"),
                csl: get_str_field(&jval, "csl"),
                runtime: get_str_field(&jval, "runtime"),
                server: get_str_field(&jval, "server"),
                format_summary,
                yaml: jval,
                error: None,
            };
            serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string())
        }
        Err(err) => {
            let res = FrontmatterResult {
                has_frontmatter: true,
                raw_yaml,
                body,
                body_start_line,
                title: String::new(),
                author: String::new(),
                date: String::new(),
                bibliography: String::new(),
                csl: String::new(),
                runtime: String::new(),
                server: String::new(),
                format_summary: String::new(),
                yaml: json!({}),
                error: Some(err.to_string()),
            };
            serde_json::to_string(&res).unwrap_or_else(|_| "{}".to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nested_quarto_yaml_does_not_clobber_top_level() {
        let doc = "---\ntitle: \"My Report\"\nformat:\n  html:\n    toc: true\n  pdf:\n    toc: false\n---\n\n# Intro\n";
        let out: JsonValue = serde_json::from_str(&parse_frontmatter_json(doc)).unwrap();
        assert_eq!(out["has_frontmatter"], true);
        assert_eq!(out["title"], "My Report");
        assert_eq!(out["yaml"]["format"]["html"]["toc"], true);
        assert_eq!(out["body_start_line"], 8);
    }
}
