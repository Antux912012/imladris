/*
 * SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

pub mod chunks;
pub mod diagnostics;
pub mod frontmatter;
pub mod ipynb;
pub mod markdown;
pub mod outline;
pub mod science;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::catch_unwind;

fn cstr_to_str<'a>(ptr: *const c_char) -> &'a str {
    if ptr.is_null() {
        return "";
    }
    // SAFETY: Caller passes valid NUL-terminated UTF-8 (or lossy fallback).
    unsafe { CStr::from_ptr(ptr) }.to_str().unwrap_or("")
}

fn to_owned_c_string(s: String) -> *mut c_char {
    let clean = if s.contains('\0') {
        s.replace('\0', "")
    } else {
        s
    };
    CString::new(clean)
        .unwrap_or_else(|_| CString::new("{}").expect("static fallback"))
        .into_raw()
}

fn ffi_json<F>(f: F) -> *mut c_char
where
    F: FnOnce() -> String + std::panic::UnwindSafe,
{
    match catch_unwind(f) {
        Ok(out) => to_owned_c_string(out),
        Err(_) => to_owned_c_string(r#"{"error":"rust_panic"}"#.to_string()),
    }
}

#[no_mangle]
pub extern "C" fn imladris_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // SAFETY: Pointer was allocated via CString::into_raw in to_owned_c_string.
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

#[no_mangle]
pub extern "C" fn imladris_parse_frontmatter_json(source_utf8: *const c_char) -> *mut c_char {
    let src = cstr_to_str(source_utf8);
    ffi_json(|| frontmatter::parse_frontmatter_json(src))
}

#[no_mangle]
pub extern "C" fn imladris_parse_chunks_json(
    source_utf8: *const c_char,
    format_code: *const c_char,
) -> *mut c_char {
    let src = cstr_to_str(source_utf8);
    let fmt = cstr_to_str(format_code);
    ffi_json(|| chunks::parse_chunks_json(src, fmt))
}

#[no_mangle]
pub extern "C" fn imladris_extract_outline_json(
    source_utf8: *const c_char,
    format_code: *const c_char,
) -> *mut c_char {
    let src = cstr_to_str(source_utf8);
    let fmt = cstr_to_str(format_code);
    ffi_json(|| outline::extract_outline_json(src, fmt))
}

#[no_mangle]
pub extern "C" fn imladris_render_markdown_html(
    body_utf8: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    let body = cstr_to_str(body_utf8);
    let opts = cstr_to_str(options_json);
    ffi_json(|| markdown::render_markdown_html(body, opts))
}

#[no_mangle]
pub extern "C" fn imladris_ipynb_to_editor_json(ipynb_json_utf8: *const c_char) -> *mut c_char {
    let raw = cstr_to_str(ipynb_json_utf8);
    ffi_json(|| ipynb::ipynb_to_editor_json(raw))
}

#[no_mangle]
pub extern "C" fn imladris_editor_to_ipynb_json(
    editor_utf8: *const c_char,
    existing_ipynb_utf8: *const c_char,
    outputs_map_json: *const c_char,
) -> *mut c_char {
    let ed = cstr_to_str(editor_utf8);
    let ex = cstr_to_str(existing_ipynb_utf8);
    let om = cstr_to_str(outputs_map_json);
    ffi_json(|| ipynb::editor_to_ipynb_json(ed, ex, om))
}

#[no_mangle]
pub extern "C" fn imladris_parse_latex_log_json(log_utf8: *const c_char) -> *mut c_char {
    let log = cstr_to_str(log_utf8);
    ffi_json(|| diagnostics::parse_latex_log_json(log))
}

#[no_mangle]
pub extern "C" fn imladris_analyze_typescript_symbols_json(
    ts_source_utf8: *const c_char,
) -> *mut c_char {
    let src = cstr_to_str(ts_source_utf8);
    ffi_json(|| diagnostics::analyze_typescript_symbols_json(src))
}

#[no_mangle]
pub extern "C" fn imladris_analyze_manuscript_json(source_utf8: *const c_char) -> *mut c_char {
    let src = cstr_to_str(source_utf8);
    ffi_json(|| science::analyze_manuscript_json(src))
}
