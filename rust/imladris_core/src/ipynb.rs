/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

use crate::chunks::{is_closing_fence, parse_opening_fence};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

#[derive(Debug, Serialize, Deserialize)]
struct CellMarker {
    id: String,
    #[serde(rename = "type")]
    cell_type: String,
    #[serde(default)]
    lang: String,
    #[serde(default)]
    metadata: Value,
    #[serde(default)]
    attachments: Value,
}

fn source_to_string(val: Option<&Value>) -> String {
    match val {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Array(arr)) => arr
            .iter()
            .filter_map(|v| v.as_str())
            .collect::<Vec<_>>()
            .join(""),
        _ => String::new(),
    }
}

fn string_to_source_lines(s: &str) -> Value {
    if s.is_empty() {
        return json!([]);
    }
    let mut lines: Vec<Value> = Vec::new();
    let parts: Vec<&str> = s.split_inclusive('\n').collect();
    for p in parts {
        lines.push(Value::String(p.to_string()));
    }
    Value::Array(lines)
}

fn max_backtick_run(s: &str) -> usize {
    let mut max_run = 0usize;
    let mut cur = 0usize;
    for ch in s.chars() {
        if ch == '`' {
            cur += 1;
            if cur > max_run {
                max_run = cur;
            }
        } else {
            cur = 0;
        }
    }
    max_run
}

fn detect_notebook_lang(root: &Value) -> String {
    if let Some(lang) = root
        .pointer("/metadata/kernelspec/language")
        .and_then(|v| v.as_str())
    {
        return lang.to_ascii_lowercase();
    }
    if let Some(name) = root
        .pointer("/metadata/kernelspec/name")
        .and_then(|v| v.as_str())
    {
        let lower = name.to_ascii_lowercase();
        if lower == "ir" || lower.starts_with("r") {
            return "r".to_string();
        }
        if lower.contains("bash") {
            return "bash".to_string();
        }
        if lower.contains("typescript") || lower.contains("deno") {
            return "typescript".to_string();
        }
        if lower.contains("python") {
            return "python".to_string();
        }
    }
    if let Some(lang) = root
        .pointer("/metadata/language_info/name")
        .and_then(|v| v.as_str())
    {
        return lang.to_ascii_lowercase();
    }
    "python".to_string()
}

pub fn ipynb_to_editor_json(ipynb_raw: &str) -> String {
    let Ok(root) = serde_json::from_str::<Value>(ipynb_raw) else {
        return json!({ "error": "invalid_json", "editor": "" }).to_string();
    };
    let default_lang = detect_notebook_lang(&root);
    let cells = root
        .get("cells")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let mut out = String::new();
    for (idx, cell) in cells.iter().enumerate() {
        let cell_type = cell
            .get("cell_type")
            .and_then(|v| v.as_str())
            .unwrap_or("code");
        let cell_id = cell
            .get("id")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| format!("cell-{}", idx + 1));
        let metadata = cell.get("metadata").cloned().unwrap_or_else(|| json!({}));
        let attachments = cell.get("attachments").cloned().unwrap_or(Value::Null);
        let src = source_to_string(cell.get("source"));

        let cell_lang = if cell_type == "code" {
            cell.pointer("/metadata/language")
                .and_then(|v| v.as_str())
                .map(|s| s.trim().to_ascii_lowercase())
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| default_lang.clone())
        } else {
            String::new()
        };

        let marker = CellMarker {
            id: cell_id.clone(),
            cell_type: cell_type.to_string(),
            lang: cell_lang.clone(),
            metadata,
            attachments,
        };
        let marker_json = serde_json::to_string(&marker).unwrap_or_else(|_| "{}".to_string());
        out.push_str(&format!("<!-- imladris:cell {marker_json} -->\n"));

        if cell_type == "code" {
            let fence_len = (max_backtick_run(&src) + 1).max(3);
            let fence = "`".repeat(fence_len);
            out.push_str(&format!("{fence}{{{cell_lang}}}\n"));
            out.push_str(&src);
            if !src.ends_with('\n') && !src.is_empty() {
                out.push('\n');
            }
            out.push_str(&format!("{fence}\n\n"));
        } else {
            out.push_str(&src);
            if !src.ends_with('\n') && !src.is_empty() {
                out.push('\n');
            }
            out.push('\n');
        }
    }

    json!({
        "editor": out,
        "language": default_lang,
        "cell_count": cells.len()
    })
    .to_string()
}

pub fn editor_to_ipynb_json(editor_text: &str, existing_ipynb: &str, outputs_map_json: &str) -> String {
    let mut root: Value = serde_json::from_str(existing_ipynb).unwrap_or_else(|_| {
        json!({
            "cells": [],
            "metadata": {
                "kernelspec": { "display_name": "Python 3", "language": "python", "name": "python3" },
                "language_info": { "name": "python" }
            },
            "nbformat": 4,
            "nbformat_minor": 5
        })
    });

    let live_outputs: Value = serde_json::from_str(outputs_map_json).unwrap_or_else(|_| json!({}));
    let existing_cells = root
        .get("cells")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let default_lang = detect_notebook_lang(&root);

    let normalized = editor_text.replace("\r\n", "\n");
    let lines: Vec<&str> = normalized.split('\n').collect();

    let mut new_cells: Vec<Value> = Vec::new();
    let mut i = 0usize;

    while i < lines.len() {
        let trimmed = lines[i].trim();
        if let Some(rest) = trimmed.strip_prefix("<!-- imladris:cell ") {
            if let Some(json_part) = rest.strip_suffix("-->") {
                if let Ok(marker) = serde_json::from_str::<CellMarker>(json_part.trim()) {
                    i += 1;
                    // Collect lines until next cell marker
                    let mut seg_lines = Vec::new();
                    while i < lines.len()
                        && !lines[i].trim().starts_with("<!-- imladris:cell ")
                    {
                        seg_lines.push(lines[i]);
                        i += 1;
                    }
                    let seg = seg_lines.join("\n").trim_end_matches('\n').to_string();

                    if marker.cell_type == "code" {
                        let seg_vec: Vec<&str> = seg.split('\n').collect();
                        let mut code_body = seg.clone();
                        if let Some(first) = seg_vec.first() {
                            if let Some(fence) = parse_opening_fence(first) {
                                let mut body_end = seg_vec.len();
                                for k in (1..seg_vec.len()).rev() {
                                    if is_closing_fence(seg_vec[k], fence.fence_char, fence.fence_len) {
                                        body_end = k;
                                        break;
                                    }
                                }
                                code_body = seg_vec[1..body_end].join("\n");
                            }
                        }

                        let prev = existing_cells.iter().find(|c| {
                            c.get("id").and_then(|v| v.as_str()) == Some(&marker.id)
                        });
                        let mut cell_obj = Map::new();
                        cell_obj.insert("cell_type".into(), json!("code"));
                        cell_obj.insert("id".into(), json!(marker.id));
                        cell_obj.insert("metadata".into(), marker.metadata);
                        cell_obj.insert("source".into(), string_to_source_lines(&code_body));

                        if let Some(live) = live_outputs.get(&marker.id) {
                            cell_obj.insert(
                                "execution_count".into(),
                                live.get("execution_count").cloned().unwrap_or(Value::Null),
                            );
                            cell_obj.insert(
                                "outputs".into(),
                                live.get("outputs").cloned().unwrap_or_else(|| json!([])),
                            );
                        } else if let Some(p) = prev {
                            cell_obj.insert(
                                "execution_count".into(),
                                p.get("execution_count").cloned().unwrap_or(Value::Null),
                            );
                            cell_obj.insert(
                                "outputs".into(),
                                p.get("outputs").cloned().unwrap_or_else(|| json!([])),
                            );
                        } else {
                            cell_obj.insert("execution_count".into(), Value::Null);
                            cell_obj.insert("outputs".into(), json!([]));
                        }
                        new_cells.push(Value::Object(cell_obj));
                    } else {
                        let mut cell_obj = Map::new();
                        cell_obj.insert("cell_type".into(), json!("markdown"));
                        cell_obj.insert("id".into(), json!(marker.id));
                        cell_obj.insert("metadata".into(), marker.metadata);
                        cell_obj.insert("source".into(), string_to_source_lines(&seg));
                        if !marker.attachments.is_null() {
                            cell_obj.insert("attachments".into(), marker.attachments);
                        }
                        new_cells.push(Value::Object(cell_obj));
                    }
                    continue;
                }
            }
        }

        // Unmarked region fallback: parse executable `{lang}` chunks vs markdown prose
        if let Some(fence) = parse_opening_fence(lines[i]) {
            if fence.info.starts_with('{') && fence.info.ends_with('}') {
                let mut j = i + 1;
                while j < lines.len() && !is_closing_fence(lines[j], fence.fence_char, fence.fence_len) {
                    j += 1;
                }
                let inner_lang = fence.info[1..fence.info.len() - 1]
                    .split(|c: char| c.is_whitespace() || c == ',')
                    .next()
                    .unwrap_or("")
                    .trim()
                    .to_ascii_lowercase();
                let mut cell_id = format!("cell-{:04}", new_cells.len() + 1);
                let mut exec_count: Value = Value::Null;
                let mut meta_map = Map::new();
                if !inner_lang.is_empty() && inner_lang != default_lang {
                    meta_map.insert("language".into(), json!(inner_lang));
                }
                let mut code_lines = Vec::new();
                let mut in_header = true;
                for raw_ln in &lines[i + 1..j.min(lines.len())] {
                    let tr = raw_ln.trim();
                    if in_header && tr.starts_with("#|") {
                        let kv = tr[2..].trim();
                        if let Some(colon) = kv.find(':') {
                            let k = kv[..colon].trim();
                            let v = kv[colon + 1..].trim();
                            if k == "cell_id" && !v.is_empty() {
                                cell_id = v.trim_matches('"').to_string();
                                continue;
                            } else if k == "execution_count" {
                                if let Ok(n) = v.parse::<i64>() {
                                    exec_count = json!(n);
                                    continue;
                                }
                            } else if k == "tags" {
                                let inner = v.trim_start_matches('[').trim_end_matches(']');
                                let tags: Vec<Value> = inner
                                    .split(',')
                                    .map(|s| s.trim().trim_matches('"').trim_matches('\'').to_string())
                                    .filter(|s| !s.is_empty())
                                    .map(Value::String)
                                    .collect();
                                meta_map.insert("tags".into(), Value::Array(tags));
                                continue;
                            }
                        }
                    } else {
                        in_header = false;
                    }
                    code_lines.push(*raw_ln);
                }
                let body = code_lines.join("\n");
                new_cells.push(json!({
                    "cell_type": "code",
                    "id": cell_id,
                    "metadata": Value::Object(meta_map),
                    "execution_count": exec_count,
                    "outputs": [],
                    "source": string_to_source_lines(&body)
                }));
                i = if j < lines.len() { j + 1 } else { lines.len() };
                continue;
            }
        }

        let mut md_lines = Vec::new();
        while i < lines.len() && !lines[i].trim().starts_with("<!-- imladris:cell ") {
            if let Some(fence) = parse_opening_fence(lines[i]) {
                if fence.info.starts_with('{') && fence.info.ends_with('}') {
                    break;
                }
            }
            md_lines.push(lines[i]);
            i += 1;
        }
        let md_body = md_lines.join("\n").trim().to_string();
        if !md_body.is_empty() {
            new_cells.push(json!({
                "cell_type": "markdown",
                "id": format!("cell-{:04}", new_cells.len() + 1),
                "metadata": {},
                "source": string_to_source_lines(&md_body)
            }));
        }
    }

    if let Some(obj) = root.as_object_mut() {
        obj.insert("cells".into(), Value::Array(new_cells));
        if !obj.contains_key("nbformat") {
            obj.insert("nbformat".into(), json!(4));
        }
        if !obj.contains_key("nbformat_minor") {
            obj.insert("nbformat_minor".into(), json!(5));
        }
        let _ = default_lang;
    }

    json!({
        "ipynb": serde_json::to_string_pretty(&root).unwrap_or_else(|_| "{}".to_string())
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_preserves_kernel_attachments_and_md_code_fence() {
        let nb = json!({
            "cells": [
                {
                    "cell_type": "markdown",
                    "id": "md-1",
                    "metadata": { "tags": ["intro"] },
                    "attachments": { "fig.png": { "image/png": "AAAA" } },
                    "source": ["Example:\n```json\n{\"k\":1}\n```"]
                },
                {
                    "cell_type": "code",
                    "id": "code-1",
                    "metadata": {},
                    "execution_count": 3,
                    "outputs": [{ "output_type": "stream", "name": "stdout", "text": ["hi\n"] }],
                    "source": ["print(\"```inside```\")"]
                }
            ],
            "metadata": {
                "kernelspec": { "display_name": "R", "language": "R", "name": "ir" },
                "colab": { "name": "test" }
            },
            "nbformat": 4,
            "nbformat_minor": 5
        })
        .to_string();

        let ed_res: Value = serde_json::from_str(&ipynb_to_editor_json(&nb)).unwrap();
        assert_eq!(ed_res["language"], "r");
        let editor = ed_res["editor"].as_str().unwrap();
        assert!(editor.contains("````{r}"));

        let rt_res: Value = serde_json::from_str(&editor_to_ipynb_json(editor, &nb, "{}")).unwrap();
        let saved: Value = serde_json::from_str(rt_res["ipynb"].as_str().unwrap()).unwrap();
        assert_eq!(saved["cells"].as_array().unwrap().len(), 2);
        assert_eq!(saved["cells"][0]["cell_type"], "markdown");
        assert_eq!(saved["cells"][0]["attachments"]["fig.png"]["image/png"], "AAAA");
        assert_eq!(saved["cells"][1]["execution_count"], 3);
        assert_eq!(saved["metadata"]["colab"]["name"], "test");
    }
}
