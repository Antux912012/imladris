/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

use pulldown_cmark::{CodeBlockKind, Event, Options, Parser, Tag, TagEnd};

pub fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

pub fn is_safe_uri(uri: &str) -> bool {
    let trimmed = uri.trim();
    if trimmed.is_empty() {
        return false;
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower.starts_with("javascript:")
        || lower.starts_with("vbscript:")
        || lower.starts_with("data:text/html")
    {
        return false;
    }
    true
}

/// Replace inline/display math and `\ce{...}` only inside prose text segments,
/// leaving code blocks and inline code untouched.
fn emit_prose_with_math_placeholders(text: &str, out: &mut String) {
    let bytes = text.as_bytes();
    let len = bytes.len();
    let mut i = 0usize;

    while i < len {
        // Escaped dollar `\$`
        if bytes[i] == b'\\' && i + 1 < len && bytes[i + 1] == b'$' {
            out.push('$');
            i += 2;
            continue;
        }

        // Display math `$$...$$`
        if i + 1 < len && bytes[i] == b'$' && bytes[i + 1] == b'$' {
            if let Some(rel_end) = text[i + 2..].find("$$") {
                let tex = &text[i + 2..i + 2 + rel_end];
                out.push_str("<div class=\"imladris-math-display\" data-tex=\"");
                out.push_str(&html_escape(tex.trim()));
                out.push_str("\"></div>");
                i += 4 + rel_end;
                continue;
            }
        }

        // `\begin{equation}...\end{equation}`
        if text[i..].starts_with("\\begin{equation}") {
            if let Some(rel_end) = text[i..].find("\\end{equation}") {
                let inner = &text[i + "\\begin{equation}".len()..i + rel_end];
                out.push_str("<div class=\"imladris-math-display\" data-tex=\"");
                out.push_str(&html_escape(inner.trim()));
                out.push_str("\"></div>");
                i += rel_end + "\\end{equation}".len();
                continue;
            }
        }

        // Standalone `\ce{...}`
        if text[i..].starts_with("\\ce{") {
            let mut depth = 0usize;
            let mut end_idx = None;
            for (off, ch) in text[i + 3..].char_indices() {
                if ch == '{' {
                    depth += 1;
                } else if ch == '}' {
                    depth = depth.saturating_sub(1);
                    if depth == 0 {
                        end_idx = Some(i + 3 + off + 1);
                        break;
                    }
                }
            }
            if let Some(end) = end_idx {
                let tex = &text[i..end];
                out.push_str("<span class=\"imladris-math-inline\" data-tex=\"");
                out.push_str(&html_escape(tex));
                out.push_str("\"></span>");
                i = end;
                continue;
            }
        }

        // Inline math `$...$` with Pandoc currency guard:
        // opening `$` not followed by space/newline; closing `$` not preceded by space and not followed by ASCII digit.
        if bytes[i] == b'$' {
            let next_is_space = i + 1 < len && (bytes[i + 1] as char).is_whitespace();
            if !next_is_space && i + 1 < len {
                let mut j = i + 1;
                let mut found = None;
                while j < len {
                    if bytes[j] == b'\n' {
                        break;
                    }
                    if bytes[j] == b'\\' && j + 1 < len {
                        j += 2;
                        continue;
                    }
                    if bytes[j] == b'$' {
                        let prev_is_space = (bytes[j - 1] as char).is_whitespace();
                        let next_is_digit = j + 1 < len && bytes[j + 1].is_ascii_digit();
                        if !prev_is_space && !next_is_digit && j > i + 1 {
                            found = Some(j);
                        }
                        break;
                    }
                    j += 1;
                }
                if let Some(end_dollar) = found {
                    let tex = &text[i + 1..end_dollar];
                    out.push_str("<span class=\"imladris-math-inline\" data-tex=\"");
                    out.push_str(&html_escape(tex));
                    out.push_str("\"></span>");
                    i = end_dollar + 1;
                    continue;
                }
            }
        }

        // Pandoc superscript `^...^` (prose only)
        if bytes[i] == b'^' && i + 1 < len && !(bytes[i + 1] as char).is_whitespace() {
            if let Some(rel_end) = text[i + 1..].find('^') {
                let inner = &text[i + 1..i + 1 + rel_end];
                if !inner.is_empty() && !inner.chars().any(|c| c.is_whitespace()) {
                    out.push_str("<sup>");
                    out.push_str(&html_escape(inner));
                    out.push_str("</sup>");
                    i += 2 + rel_end;
                    continue;
                }
            }
        }

        // Pandoc subscript `~...~` (single tilde, prose only)
        if bytes[i] == b'~'
            && !(i + 1 < len && bytes[i + 1] == b'~')
            && i + 1 < len
            && !(bytes[i + 1] as char).is_whitespace()
        {
            if let Some(rel_end) = text[i + 1..].find('~') {
                let inner = &text[i + 1..i + 1 + rel_end];
                if !inner.is_empty() && !inner.chars().any(|c| c.is_whitespace()) {
                    out.push_str("<sub>");
                    out.push_str(&html_escape(inner));
                    out.push_str("</sub>");
                    i += 2 + rel_end;
                    continue;
                }
            }
        }

        // Copy next UTF-8 char safely escaped
        let ch = text[i..].chars().next().unwrap();
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
        i += ch.len_utf8();
    }
}

pub fn render_markdown_html(body: &str, _options_json: &str) -> String {
    let mut opts = Options::empty();
    opts.insert(Options::ENABLE_TABLES);
    opts.insert(Options::ENABLE_STRIKETHROUGH);
    opts.insert(Options::ENABLE_TASKLISTS);
    opts.insert(Options::ENABLE_FOOTNOTES);

    let parser = Parser::new_ext(body, opts);
    let mut out = String::with_capacity(body.len() * 2);

    let mut in_code_block = false;
    let mut code_lang = String::new();
    let mut code_buf = String::new();
    let mut in_image = false;
    let mut prose_buf = String::new();

    for event in parser {
        let is_prose_piece = !in_code_block
            && !in_image
            && matches!(event, Event::Text(_) | Event::SoftBreak);
        if !is_prose_piece && !prose_buf.is_empty() {
            emit_prose_with_math_placeholders(&prose_buf, &mut out);
            prose_buf.clear();
        }

        match event {
            Event::Start(Tag::CodeBlock(kind)) => {
                in_code_block = true;
                code_buf.clear();
                code_lang = match kind {
                    CodeBlockKind::Fenced(info) => info.trim().to_string(),
                    CodeBlockKind::Indented => String::new(),
                };
            }
            Event::End(TagEnd::CodeBlock) => {
                in_code_block = false;
                let lang_trimmed = code_lang.trim();
                if lang_trimmed.eq_ignore_ascii_case("mermaid")
                    || lang_trimmed.eq_ignore_ascii_case("{mermaid}")
                {
                    out.push_str("<div class=\"imladris-mermaid-block\" data-mermaid=\"");
                    out.push_str(&html_escape(&code_buf));
                    out.push_str("\"></div>\n");
                } else if lang_trimmed.starts_with('{') && lang_trimmed.ends_with('}') {
                    let inner = lang_trimmed[1..lang_trimmed.len() - 1].trim();
                    let engine = inner
                        .split(|c: char| c.is_whitespace() || c == ',')
                        .next()
                        .unwrap_or("code")
                        .to_ascii_lowercase();
                    out.push_str("<div class=\"chunk-card\"><div class=\"chunk-header\">");
                    out.push_str(&html_escape(&engine));
                    out.push_str(" chunk</div><pre><code class=\"language-");
                    out.push_str(&html_escape(&engine));
                    out.push_str("\">");
                    out.push_str(&html_escape(&code_buf));
                    out.push_str("</code></pre></div>\n");
                } else {
                    let lang_word = lang_trimmed.split_whitespace().next().unwrap_or("text");
                    out.push_str("<pre><code class=\"language-");
                    out.push_str(&html_escape(lang_word));
                    out.push_str("\">");
                    out.push_str(&html_escape(&code_buf));
                    out.push_str("</code></pre>\n");
                }
            }
            Event::Code(code) => {
                out.push_str("<code>");
                out.push_str(&html_escape(&code));
                out.push_str("</code>");
            }
            Event::Text(text) => {
                if in_code_block {
                    code_buf.push_str(&text);
                } else if in_image {
                    out.push_str(&html_escape(&text));
                } else {
                    prose_buf.push_str(&text);
                }
            }
            Event::SoftBreak => {
                if in_code_block {
                    code_buf.push('\n');
                } else if in_image {
                    out.push('\n');
                } else {
                    prose_buf.push('\n');
                }
            }
            Event::HardBreak => out.push_str("<br />\n"),
            Event::Rule => out.push_str("<hr />\n"),
            Event::TaskListMarker(checked) => {
                if checked {
                    out.push_str("<input type=\"checkbox\" checked disabled /> ");
                } else {
                    out.push_str("<input type=\"checkbox\" disabled /> ");
                }
            }
            Event::Start(Tag::Paragraph) => out.push_str("<p>"),
            Event::End(TagEnd::Paragraph) => out.push_str("</p>\n"),
            Event::Start(Tag::Heading { level, .. }) => {
                out.push_str(&format!("<h{}>", level as u8));
            }
            Event::End(TagEnd::Heading(level)) => {
                out.push_str(&format!("</h{}>\n", level as u8));
            }
            Event::Start(Tag::BlockQuote(_)) => out.push_str("<blockquote>\n"),
            Event::End(TagEnd::BlockQuote(_)) => out.push_str("</blockquote>\n"),
            Event::Start(Tag::List(None)) => out.push_str("<ul>\n"),
            Event::Start(Tag::List(Some(1))) => out.push_str("<ol>\n"),
            Event::Start(Tag::List(Some(start))) => {
                out.push_str(&format!("<ol start=\"{start}\">\n"));
            }
            Event::End(TagEnd::List(true)) => out.push_str("</ol>\n"),
            Event::End(TagEnd::List(false)) => out.push_str("</ul>\n"),
            Event::Start(Tag::Item) => out.push_str("<li>"),
            Event::End(TagEnd::Item) => out.push_str("</li>\n"),
            Event::Start(Tag::Emphasis) => out.push_str("<em>"),
            Event::End(TagEnd::Emphasis) => out.push_str("</em>"),
            Event::Start(Tag::Strong) => out.push_str("<strong>"),
            Event::End(TagEnd::Strong) => out.push_str("</strong>"),
            Event::Start(Tag::Strikethrough) => out.push_str("<del>"),
            Event::End(TagEnd::Strikethrough) => out.push_str("</del>"),
            Event::Start(Tag::Table(_)) => out.push_str("<table>\n"),
            Event::End(TagEnd::Table) => out.push_str("</table>\n"),
            Event::Start(Tag::TableHead) => out.push_str("<thead><tr>"),
            Event::End(TagEnd::TableHead) => out.push_str("</tr></thead>\n"),
            Event::Start(Tag::TableRow) => out.push_str("<tr>"),
            Event::End(TagEnd::TableRow) => out.push_str("</tr>\n"),
            Event::Start(Tag::TableCell) => out.push_str("<td>"),
            Event::End(TagEnd::TableCell) => out.push_str("</td>"),
            Event::Start(Tag::Link { dest_url, title, .. }) => {
                let href = if is_safe_uri(&dest_url) { &*dest_url } else { "#" };
                out.push_str("<a href=\"");
                out.push_str(&html_escape(href));
                out.push('"');
                if !title.is_empty() {
                    out.push_str(" title=\"");
                    out.push_str(&html_escape(&title));
                    out.push('"');
                }
                out.push('>');
            }
            Event::End(TagEnd::Link) => out.push_str("</a>"),
            Event::Start(Tag::Image { dest_url, title, .. }) => {
                in_image = true;
                let src = if is_safe_uri(&dest_url) { &*dest_url } else { "" };
                out.push_str("<figure class=\"imladris-figure\"><img src=\"");
                out.push_str(&html_escape(src));
                out.push_str("\" title=\"");
                out.push_str(&html_escape(&title));
                out.push_str("\" alt=\"");
            }
            Event::End(TagEnd::Image) => {
                in_image = false;
                out.push_str("\" /></figure>");
            }
            Event::Html(raw) | Event::InlineHtml(raw) => {
                let lower = raw.to_ascii_lowercase();
                if !lower.contains("<script") && !lower.contains("javascript:") {
                    out.push_str(&raw);
                }
            }
            Event::FootnoteReference(name) => {
                out.push_str("<sup class=\"footnote-ref\">");
                out.push_str(&html_escape(&name));
                out.push_str("</sup>");
            }
            Event::Start(Tag::FootnoteDefinition(name)) => {
                out.push_str("<div class=\"footnote-def\" data-fn=\"");
                out.push_str(&html_escape(&name));
                out.push_str("\">");
            }
            Event::End(TagEnd::FootnoteDefinition) => out.push_str("</div>\n"),
            _ => {}
        }
    }

    if !prose_buf.is_empty() {
        emit_prose_with_math_placeholders(&prose_buf, &mut out);
    }

    serde_json::json!({ "html": out }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn code_blocks_are_never_corrupted_by_math_or_currency() {
        let md = "Cost is $5 and $10, math is $\\int_0^1 x dx$.\n\n```python\nx = \"$$1 + 1$$ \\ce{H2O} *not_bold*\"\n```\n";
        let res: serde_json::Value = serde_json::from_str(&render_markdown_html(md, "{}")).unwrap();
        let html = res["html"].as_str().unwrap();
        assert!(html.contains("Cost is $5 and $10"));
        assert!(html.contains("imladris-math-inline"));
        assert!(html.contains("$$1 + 1$$ \\ce{H2O} *not_bold*"));
    }
}
