/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: Apache-2.0
 */

use crate::chunks::{is_closing_fence, parse_chunks, parse_opening_fence};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Serialize)]
pub struct ScienceRefItem {
    pub key: String,
    pub line: usize,
    pub kind: String,
}

#[derive(Debug, Serialize)]
pub struct ManuscriptAnalytics {
    pub prose_words: usize,
    pub reading_time_minutes: usize,
    pub citation_count: usize,
    pub unique_citations: Vec<String>,
    pub cross_references: Vec<ScienceRefItem>,
    pub inline_code_count: usize,
    pub chunk_counts_by_lang: BTreeMap<String, usize>,
}

fn is_cross_ref(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    lower.starts_with("@fig-")
        || lower.starts_with("@tbl-")
        || lower.starts_with("@sec-")
        || lower.starts_with("@eq-")
        || lower.starts_with("@lst-")
        || lower.starts_with("@thm-")
        || lower.starts_with("@lem-")
        || lower.starts_with("@cor-")
        || lower.starts_with("@prp-")
        || lower.starts_with("@cnj-")
        || lower.starts_with("@def-")
        || lower.starts_with("@exm-")
        || lower.starts_with("@exr-")
}

fn is_valid_cite_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-' | b':' | b'.' | b'$' | b'#' | b'+' | b'/')
}

fn count_inline_exec_expressions(line: &str) -> usize {
    let mut count = 0usize;
    let bytes = line.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == b'`' {
            if let Some(rel_end) = line[i + 1..].find('`') {
                let inner = line[i + 1..i + 1 + rel_end].trim_start();
                if inner.starts_with("r ")
                    || inner.starts_with("{r}")
                    || inner.starts_with("{python}")
                    || inner.starts_with("{julia}")
                {
                    count += 1;
                }
                i += rel_end + 2;
                continue;
            }
        }
        i += 1;
    }
    count
}

pub fn analyze_manuscript(source: &str) -> ManuscriptAnalytics {
    let lines: Vec<&str> = source
        .split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect();

    let mut i = 0usize;
    if !lines.is_empty() && lines[0].trim() == "---" {
        for (j, raw) in lines.iter().enumerate().skip(1) {
            let t = raw.trim();
            if t == "---" || t == "..." {
                i = j + 1;
                break;
            }
        }
    }

    let mut prose_words = 0usize;
    let mut inline_code_count = 0usize;
    let mut unique_citations = BTreeSet::new();
    let mut cross_references = Vec::new();
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
            active_fence = Some((fence.fence_char, fence.fence_len));
            i += 1;
            continue;
        }

        prose_words += line.split_whitespace().count();
        inline_code_count += count_inline_exec_expressions(line);

        let bytes = line.as_bytes();
        let mut idx = 0usize;
        while idx < bytes.len() {
            if bytes[idx] == b'@' {
                let prev_is_ident = idx > 0
                    && (bytes[idx - 1].is_ascii_alphanumeric() || bytes[idx - 1] == b'.');
                if !prev_is_ident && idx + 1 < bytes.len() && bytes[idx + 1].is_ascii_alphanumeric() {
                    let mut end = idx + 1;
                    while end < bytes.len() && is_valid_cite_char(bytes[end]) {
                        end += 1;
                    }
                    let token = line[idx..end].trim_end_matches('.');
                    if token.len() > 2 {
                        if is_cross_ref(token) {
                            cross_references.push(ScienceRefItem {
                                key: token.to_string(),
                                line: i + 1,
                                kind: "cross_ref".to_string(),
                            });
                        } else {
                            unique_citations.insert(token.to_string());
                        }
                    }
                    idx = end;
                    continue;
                }
            }
            idx += 1;
        }

        i += 1;
    }

    let mut chunk_counts_by_lang = BTreeMap::new();
    for ch in parse_chunks(source, "qmd") {
        if ch.is_executable && !ch.language.is_empty() {
            *chunk_counts_by_lang.entry(ch.language).or_insert(0) += 1;
        }
    }

    let reading_time_minutes = if prose_words == 0 {
        0
    } else {
        (prose_words + 219) / 220
    };

    let unique_vec: Vec<String> = unique_citations.into_iter().collect();
    ManuscriptAnalytics {
        prose_words,
        reading_time_minutes,
        citation_count: unique_vec.len(),
        unique_citations: unique_vec,
        cross_references,
        inline_code_count,
        chunk_counts_by_lang,
    }
}

pub fn analyze_manuscript_json(source: &str) -> String {
    let analytics = analyze_manuscript(source);
    serde_json::to_string(&analytics).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn analyzes_prose_citations_cross_refs_and_inline_code() {
        let doc = "---\ntitle: \"Paper\"\n---\n\nSee @smith2024 and @fig-pca.\nEmail: test@example.com.\nMean was `r mean(x)`.\n\n```{r}\n#| label: fig-pca\nplot(cars)\n```\n";
        let res = analyze_manuscript(doc);
        assert_eq!(res.citation_count, 1);
        assert_eq!(res.unique_citations, vec!["@smith2024"]);
        assert_eq!(res.cross_references.len(), 1);
        assert_eq!(res.cross_references[0].key, "@fig-pca");
        assert_eq!(res.inline_code_count, 1);
        assert_eq!(res.chunk_counts_by_lang.get("r"), Some(&1));
        assert!(res.prose_words > 0);
    }
}
