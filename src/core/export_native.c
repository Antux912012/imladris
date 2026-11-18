// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "export_native.h"

#include <cairo.h>
#include <cairo-pdf.h>
#include <gio/gio.h>
#include <pango/pangocairo.h>
#include <stdio.h>
#include <string.h>
#include <zlib.h>

/* =========================================================================
 * 1. Zero-Dependency OASIS OpenDocument ZIP Packager (PKZIP + zlib)
 * ========================================================================= */

typedef struct {
    char    *name;
    guint32  crc;
    guint32  comp_size;
    guint32  uncomp_size;
    guint16  method;
    guint32  local_offset;
} ZipEntryMeta;

static void
write_le16 (guint8 *buf, guint16 v)
{
    buf[0] = (guint8) (v & 0xFF);
    buf[1] = (guint8) ((v >> 8) & 0xFF);
}

static void
write_le32 (guint8 *buf, guint32 v)
{
    buf[0] = (guint8) (v & 0xFF);
    buf[1] = (guint8) ((v >> 8) & 0xFF);
    buf[2] = (guint8) ((v >> 16) & 0xFF);
    buf[3] = (guint8) ((v >> 24) & 0xFF);
}

static gboolean
raw_deflate_bytes (const guint8  *in_data,
                   gsize          in_len,
                   guint8       **out_data,
                   gsize         *out_len)
{
    z_stream zs;
    memset (&zs, 0, sizeof (zs));
    if (deflateInit2 (&zs, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return FALSE;
    }

    uLong bound = deflateBound (&zs, (uLong) in_len);
    guint8 *buf = g_malloc (bound > 0 ? bound : 16);

    zs.next_in = (Bytef *) in_data;
    zs.avail_in = (uInt) in_len;
    zs.next_out = buf;
    zs.avail_out = (uInt) bound;

    int rc = deflate (&zs, Z_FINISH);
    deflateEnd (&zs);

    if (rc != Z_STREAM_END) {
        g_free (buf);
        return FALSE;
    }

    *out_data = buf;
    *out_len = (gsize) zs.total_out;
    return TRUE;
}

static gboolean
write_zip_entry (FILE         *fp,
                 const char   *name,
                 const char   *data,
                 gboolean      compress,
                 ZipEntryMeta *meta)
{
    gsize name_len = strlen (name);
    gsize raw_len = strlen (data);
    guint32 crc = (guint32) crc32 (0L, (const Bytef *) data, (uInt) raw_len);

    g_autofree guint8 *comp_buf = NULL;
    const guint8 *payload = (const guint8 *) data;
    gsize payload_len = raw_len;
    guint16 method = 0;

    if (compress && raw_len > 0) {
        gsize clen = 0;
        if (raw_deflate_bytes ((const guint8 *) data, raw_len, &comp_buf, &clen) && clen < raw_len) {
            payload = comp_buf;
            payload_len = clen;
            method = 8;
        }
    }

    long offset = ftell (fp);
    if (offset < 0) {
        return FALSE;
    }

    guint8 hdr[30];
    memset (hdr, 0, sizeof (hdr));
    write_le32 (hdr + 0, 0x04034B50U);
    write_le16 (hdr + 4, 20);
    write_le16 (hdr + 6, 0x0800); /* UTF-8 */
    write_le16 (hdr + 8, method);
    write_le32 (hdr + 14, crc);
    write_le32 (hdr + 18, (guint32) payload_len);
    write_le32 (hdr + 22, (guint32) raw_len);
    write_le16 (hdr + 26, (guint16) name_len);

    if (fwrite (hdr, 1, sizeof (hdr), fp) != sizeof (hdr) ||
        fwrite (name, 1, name_len, fp) != name_len ||
        (payload_len > 0 && fwrite (payload, 1, payload_len, fp) != payload_len)) {
        return FALSE;
    }

    meta->name = g_strdup (name);
    meta->crc = crc;
    meta->comp_size = (guint32) payload_len;
    meta->uncomp_size = (guint32) raw_len;
    meta->method = method;
    meta->local_offset = (guint32) offset;
    return TRUE;
}

gboolean
imladris_export_write_oasis_zip (const char  *output_path,
                                 const char  *mimetype,
                                 const char  *content_xml,
                                 const char  *styles_xml,
                                 const char  *manifest_xml,
                                 GError     **error)
{
    FILE *fp = fopen (output_path, "wb");
    if (fp == NULL) {
        g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                     "Could not open %s for writing", output_path);
        return FALSE;
    }

    ZipEntryMeta entries[4];
    memset (entries, 0, sizeof (entries));

    gboolean ok = TRUE;
    ok = ok && write_zip_entry (fp, "mimetype", mimetype, FALSE, &entries[0]);
    ok = ok && write_zip_entry (fp, "content.xml", content_xml, TRUE, &entries[1]);
    ok = ok && write_zip_entry (fp, "styles.xml", styles_xml, TRUE, &entries[2]);
    ok = ok && write_zip_entry (fp, "META-INF/manifest.xml", manifest_xml, TRUE, &entries[3]);

    long cd_offset = ftell (fp);
    if (cd_offset < 0) {
        ok = FALSE;
    }

    for (int i = 0; i < 4 && ok; i++) {
        gsize name_len = strlen (entries[i].name);
        guint8 cd[46];
        memset (cd, 0, sizeof (cd));
        write_le32 (cd + 0, 0x02014B50U);
        write_le16 (cd + 4, 20);
        write_le16 (cd + 6, 20);
        write_le16 (cd + 8, 0x0800);
        write_le16 (cd + 10, entries[i].method);
        write_le32 (cd + 16, entries[i].crc);
        write_le32 (cd + 20, entries[i].comp_size);
        write_le32 (cd + 24, entries[i].uncomp_size);
        write_le16 (cd + 28, (guint16) name_len);
        write_le32 (cd + 42, entries[i].local_offset);

        if (fwrite (cd, 1, sizeof (cd), fp) != sizeof (cd) ||
            fwrite (entries[i].name, 1, name_len, fp) != name_len) {
            ok = FALSE;
        }
    }

    long cd_end = ftell (fp);
    if (ok && cd_end >= cd_offset) {
        guint8 eocd[22];
        memset (eocd, 0, sizeof (eocd));
        write_le32 (eocd + 0, 0x06054B50U);
        write_le16 (eocd + 8, 4);
        write_le16 (eocd + 10, 4);
        write_le32 (eocd + 12, (guint32) (cd_end - cd_offset));
        write_le32 (eocd + 16, (guint32) cd_offset);
        if (fwrite (eocd, 1, sizeof (eocd), fp) != sizeof (eocd)) {
            ok = FALSE;
        }
    } else {
        ok = FALSE;
    }

    for (int i = 0; i < 4; i++) {
        g_free (entries[i].name);
    }
    fclose (fp);

    if (!ok) {
        g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                     "Failed to write OASIS OpenDocument ZIP container to %s", output_path);
    }
    return ok;
}

/* =========================================================================
 * 2. Native Cairo + Pango Report PDF Renderer (A4 Vector Typography)
 * ========================================================================= */

#define PDF_PAGE_W 595.28
#define PDF_PAGE_H 841.89
#define PDF_MARGIN_X 54.0
#define PDF_MARGIN_TOP 54.0
#define PDF_MARGIN_BOTTOM 54.0
#define PDF_CONTENT_W (PDF_PAGE_W - 2.0 * PDF_MARGIN_X)
#define PDF_CONTENT_BOTTOM (PDF_PAGE_H - PDF_MARGIN_BOTTOM)

typedef struct {
    cairo_surface_t *surface;
    cairo_t         *cr;
    double           y;
    int              page_num;
} PdfRenderCtx;

static void
pdf_draw_page_footer (PdfRenderCtx *ctx)
{
    PangoLayout *layout = pango_cairo_create_layout (ctx->cr);
    PangoFontDescription *fd = pango_font_description_from_string ("Sans 8.5");
    pango_layout_set_font_description (layout, fd);
    g_autofree char *label = g_strdup_printf ("Page %d", ctx->page_num);
    pango_layout_set_text (layout, label, -1);

    int tw = 0, th = 0;
    pango_layout_get_pixel_size (layout, &tw, &th);

    cairo_save (ctx->cr);
    cairo_set_source_rgb (ctx->cr, 0.45, 0.50, 0.58);
    cairo_move_to (ctx->cr, PDF_PAGE_W - PDF_MARGIN_X - tw, PDF_PAGE_H - 34.0);
    pango_cairo_show_layout (ctx->cr, layout);
    cairo_restore (ctx->cr);

    pango_font_description_free (fd);
    g_object_unref (layout);
}

static void
pdf_new_page (PdfRenderCtx *ctx)
{
    pdf_draw_page_footer (ctx);
    cairo_show_page (ctx->cr);
    ctx->page_num++;
    ctx->y = PDF_MARGIN_TOP;
}

static void
pdf_ensure_space (PdfRenderCtx *ctx, double needed_h)
{
    if (ctx->y + needed_h > PDF_CONTENT_BOTTOM && ctx->y > PDF_MARGIN_TOP + 1.0) {
        pdf_new_page (ctx);
    }
}

static char *
markdown_inline_to_pango (const char *text)
{
    if (text == NULL) {
        return g_strdup ("");
    }

    GString *out = g_string_new ("");
    const char *p = text;

    while (*p != '\0') {
        if (p[0] == '*' && p[1] == '*') {
            const char *end = strstr (p + 2, "**");
            if (end != NULL && end > p + 2) {
                g_autofree char *inner = g_strndup (p + 2, (gsize) (end - (p + 2)));
                g_autofree char *esc = g_markup_escape_text (inner, -1);
                g_string_append_printf (out, "<b>%s</b>", esc);
                p = end + 2;
                continue;
            }
        }
        if (p[0] == '`') {
            const char *end = strchr (p + 1, '`');
            if (end != NULL && end > p + 1) {
                g_autofree char *inner = g_strndup (p + 1, (gsize) (end - (p + 1)));
                g_autofree char *esc = g_markup_escape_text (inner, -1);
                g_string_append_printf (out, "<tt>%s</tt>", esc);
                p = end + 1;
                continue;
            }
        }
        if (p[0] == '*' && p[1] != '*') {
            const char *end = strchr (p + 1, '*');
            if (end != NULL && end > p + 1) {
                g_autofree char *inner = g_strndup (p + 1, (gsize) (end - (p + 1)));
                g_autofree char *esc = g_markup_escape_text (inner, -1);
                g_string_append_printf (out, "<i>%s</i>", esc);
                p = end + 1;
                continue;
            }
        }

        const char *next = g_utf8_next_char (p);
        g_autofree char *ch = g_strndup (p, (gsize) (next - p));
        g_autofree char *esc = g_markup_escape_text (ch, -1);
        g_string_append (out, esc);
        p = next;
    }

    return g_string_free (out, FALSE);
}

static void
pdf_render_text_block (PdfRenderCtx *ctx,
                       const char   *text,
                       const char   *font_desc,
                       double        r,
                       double        g,
                       double        b,
                       double        indent_x,
                       double        width,
                       double        space_before,
                       double        space_after,
                       gboolean      use_markup,
                       gboolean      draw_quote_bar)
{
    PangoLayout *layout = pango_cairo_create_layout (ctx->cr);
    PangoFontDescription *fd = pango_font_description_from_string (font_desc);
    pango_layout_set_font_description (layout, fd);
    pango_layout_set_width (layout, (int) (width * PANGO_SCALE));
    pango_layout_set_wrap (layout, PANGO_WRAP_WORD_CHAR);
    pango_layout_set_spacing (layout, 3 * PANGO_SCALE);

    if (use_markup) {
        g_autofree char *markup = markdown_inline_to_pango (text);
        pango_layout_set_markup (layout, markup, -1);
    } else {
        pango_layout_set_text (layout, text, -1);
    }

    int pw = 0, ph = 0;
    pango_layout_get_pixel_size (layout, &pw, &ph);
    double h = (double) ph;

    pdf_ensure_space (ctx, space_before + h);
    ctx->y += space_before;

    if (draw_quote_bar) {
        cairo_save (ctx->cr);
        cairo_set_source_rgb (ctx->cr, 0.01, 0.52, 0.78);
        cairo_rectangle (ctx->cr, PDF_MARGIN_X + 4.0, ctx->y, 2.5, h);
        cairo_fill (ctx->cr);
        cairo_restore (ctx->cr);
    }

    cairo_save (ctx->cr);
    cairo_set_source_rgb (ctx->cr, r, g, b);
    cairo_move_to (ctx->cr, PDF_MARGIN_X + indent_x, ctx->y);
    pango_cairo_show_layout (ctx->cr, layout);
    cairo_restore (ctx->cr);

    ctx->y += h + space_after;

    pango_font_description_free (fd);
    g_object_unref (layout);
}

static void
pdf_render_code_block (PdfRenderCtx *ctx, const char *code_text)
{
    if (code_text == NULL || code_text[0] == '\0') {
        return;
    }

    PangoLayout *layout = pango_cairo_create_layout (ctx->cr);
    PangoFontDescription *fd = pango_font_description_from_string ("Monospace 9");
    pango_layout_set_font_description (layout, fd);
    pango_layout_set_width (layout, (int) ((PDF_CONTENT_W - 16.0) * PANGO_SCALE));
    pango_layout_set_wrap (layout, PANGO_WRAP_WORD_CHAR);
    pango_layout_set_text (layout, code_text, -1);

    int pw = 0, ph = 0;
    pango_layout_get_pixel_size (layout, &pw, &ph);
    double box_h = (double) ph + 14.0;

    pdf_ensure_space (ctx, box_h + 8.0);

    cairo_save (ctx->cr);
    cairo_set_source_rgb (ctx->cr, 0.97, 0.98, 0.99);
    cairo_rectangle (ctx->cr, PDF_MARGIN_X, ctx->y, PDF_CONTENT_W, box_h);
    cairo_fill_preserve (ctx->cr);
    cairo_set_source_rgb (ctx->cr, 0.80, 0.84, 0.88);
    cairo_set_line_width (ctx->cr, 0.75);
    cairo_stroke (ctx->cr);

    cairo_set_source_rgb (ctx->cr, 0.12, 0.16, 0.23);
    cairo_move_to (ctx->cr, PDF_MARGIN_X + 8.0, ctx->y + 7.0);
    pango_cairo_show_layout (ctx->cr, layout);
    cairo_restore (ctx->cr);

    ctx->y += box_h + 8.0;

    pango_font_description_free (fd);
    g_object_unref (layout);
}

static void
pdf_render_rule (PdfRenderCtx *ctx)
{
    pdf_ensure_space (ctx, 12.0);
    ctx->y += 5.0;
    cairo_save (ctx->cr);
    cairo_set_source_rgb (ctx->cr, 0.82, 0.85, 0.90);
    cairo_set_line_width (ctx->cr, 0.75);
    cairo_move_to (ctx->cr, PDF_MARGIN_X, ctx->y);
    cairo_line_to (ctx->cr, PDF_PAGE_W - PDF_MARGIN_X, ctx->y);
    cairo_stroke (ctx->cr);
    cairo_restore (ctx->cr);
    ctx->y += 7.0;
}

gboolean
imladris_export_render_pdf (const char  *output_path,
                            const char  *title,
                            const char  *author,
                            const char  *date,
                            const char  *markdown_body,
                            GError     **error)
{
    cairo_surface_t *surface = cairo_pdf_surface_create (output_path, PDF_PAGE_W, PDF_PAGE_H);
    cairo_status_t st = cairo_surface_status (surface);
    if (st != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy (surface);
        g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                     "Failed to create PDF surface: %s", cairo_status_to_string (st));
        return FALSE;
    }

    cairo_t *cr = cairo_create (surface);
    PdfRenderCtx ctx = {
        .surface = surface,
        .cr = cr,
        .y = PDF_MARGIN_TOP,
        .page_num = 1
    };

    if (title != NULL && title[0] != '\0') {
        pdf_render_text_block (&ctx, title, "Sans Bold 20", 0.06, 0.09, 0.16,
                               0.0, PDF_CONTENT_W, 0.0, 4.0, FALSE, FALSE);
    }

    if ((author != NULL && author[0] != '\0') || (date != NULL && date[0] != '\0')) {
        g_autofree char *sub = NULL;
        if (author != NULL && author[0] != '\0' && date != NULL && date[0] != '\0') {
            sub = g_strdup_printf ("%s  •  %s", author, date);
        } else if (author != NULL && author[0] != '\0') {
            sub = g_strdup (author);
        } else {
            sub = g_strdup (date);
        }
        pdf_render_text_block (&ctx, sub, "Sans Italic 10", 0.39, 0.45, 0.55,
                               0.0, PDF_CONTENT_W, 0.0, 8.0, FALSE, FALSE);
    }

    if (title != NULL && title[0] != '\0') {
        pdf_render_rule (&ctx);
    }

    g_auto (GStrv) lines = g_strsplit (markdown_body != NULL ? markdown_body : "", "\n", -1);
    gboolean in_code = FALSE;
    GString *code_buf = g_string_new ("");

    for (int i = 0; lines[i] != NULL; i++) {
        g_autofree char *trimmed = g_strdup (lines[i]);
        g_strstrip (trimmed);

        if (g_str_has_prefix (trimmed, "```")) {
            if (in_code) {
                pdf_render_code_block (&ctx, code_buf->str);
                g_string_truncate (code_buf, 0);
                in_code = FALSE;
            } else {
                in_code = TRUE;
            }
            continue;
        }

        if (in_code) {
            if (code_buf->len > 0) {
                g_string_append_c (code_buf, '\n');
            }
            g_string_append (code_buf, lines[i]);
            continue;
        }

        if (trimmed[0] == '\0') {
            ctx.y += 4.0;
            continue;
        }

        if (g_strcmp0 (trimmed, "---") == 0 || g_strcmp0 (trimmed, "***") == 0) {
            pdf_render_rule (&ctx);
        } else if (g_str_has_prefix (trimmed, "#### ")) {
            pdf_render_text_block (&ctx, trimmed + 5, "Sans Bold 11.5", 0.06, 0.09, 0.16,
                                   0.0, PDF_CONTENT_W, 8.0, 4.0, TRUE, FALSE);
        } else if (g_str_has_prefix (trimmed, "### ")) {
            pdf_render_text_block (&ctx, trimmed + 4, "Sans Bold 13", 0.06, 0.09, 0.16,
                                   0.0, PDF_CONTENT_W, 10.0, 4.0, TRUE, FALSE);
        } else if (g_str_has_prefix (trimmed, "## ")) {
            pdf_render_text_block (&ctx, trimmed + 3, "Sans Bold 15", 0.06, 0.09, 0.16,
                                   0.0, PDF_CONTENT_W, 12.0, 5.0, TRUE, FALSE);
        } else if (g_str_has_prefix (trimmed, "# ")) {
            pdf_render_text_block (&ctx, trimmed + 2, "Sans Bold 18", 0.06, 0.09, 0.16,
                                   0.0, PDF_CONTENT_W, 14.0, 6.0, TRUE, FALSE);
        } else if (g_str_has_prefix (trimmed, "> ")) {
            pdf_render_text_block (&ctx, trimmed + 2, "Sans Italic 10.5", 0.32, 0.38, 0.48,
                                   14.0, PDF_CONTENT_W - 14.0, 4.0, 6.0, TRUE, TRUE);
        } else if (g_str_has_prefix (trimmed, "- ") || g_str_has_prefix (trimmed, "* ")) {
            g_autofree char *bullet_line = g_strdup_printf ("•  %s", trimmed + 2);
            pdf_render_text_block (&ctx, bullet_line, "Sans 10.5", 0.12, 0.16, 0.23,
                                   12.0, PDF_CONTENT_W - 12.0, 1.0, 4.0, TRUE, FALSE);
        } else {
            pdf_render_text_block (&ctx, trimmed, "Sans 10.5", 0.12, 0.16, 0.23,
                                   0.0, PDF_CONTENT_W, 1.0, 6.0, TRUE, FALSE);
        }
    }

    if (in_code && code_buf->len > 0) {
        pdf_render_code_block (&ctx, code_buf->str);
    }
    g_string_free (code_buf, TRUE);

    pdf_draw_page_footer (&ctx);
    cairo_show_page (cr);
    cairo_surface_finish (surface);
    st = cairo_surface_status (surface);

    cairo_destroy (cr);
    cairo_surface_destroy (surface);

    if (st != CAIRO_STATUS_SUCCESS) {
        g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                     "PDF surface finish failed: %s", cairo_status_to_string (st));
        return FALSE;
    }

    return TRUE;
}
