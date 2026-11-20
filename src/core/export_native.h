// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

#ifndef IMLADRIS_EXPORT_NATIVE_H
#define IMLADRIS_EXPORT_NATIVE_H

#include <glib.h>

G_BEGIN_DECLS

gboolean imladris_export_write_oasis_zip (const char  *output_path,
                                          const char  *mimetype,
                                          const char  *content_xml,
                                          const char  *styles_xml,
                                          const char  *manifest_xml,
                                          GError     **error);

gboolean imladris_export_render_pdf (const char  *output_path,
                                     const char  *title,
                                     const char  *author,
                                     const char  *date,
                                     const char  *markdown_body,
                                     GError     **error);

G_END_DECLS

#endif /* IMLADRIS_EXPORT_NATIVE_H */
