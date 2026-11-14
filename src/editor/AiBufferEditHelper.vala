// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: GPL-3.0-or-later

using GLib;

namespace Imladris.Editor {

    /**
     * Pure, testable helper for Positron/RStudio Copilot-style direct document
     * editing operations on computational Markdown/Quarto/R/Python buffers.
     */
    public class AiBufferEditHelper : GLib.Object {

        /**
         * Finds the 0-based line range `[body_start_line, end_fence_line)` of the active
         * fenced code chunk body enclosing `cursor_line`, skipping leading `#| ...` Quarto
         * options. Returns false if `cursor_line` is not inside a closed chunk.
         */
        public static bool get_active_chunk_body_range (
            string doc_text,
            int cursor_line,
            out int body_start_line,
            out int end_fence_line
        ) {
            body_start_line = -1;
            end_fence_line = -1;
            string[] lines = doc_text.split ("\n");
            if (cursor_line < 0 || cursor_line >= lines.length) {
                return false;
            }

            int start_fence = -1;
            for (int i = cursor_line; i >= 0; i--) {
                if (lines[i].strip ().has_prefix ("```")) {
                    string after = lines[i].strip ().substring (3).strip ();
                    if (after.length > 0) {
                        start_fence = i;
                        break;
                    } else {
                        return false;
                    }
                }
            }

            if (start_fence == -1) {
                return false;
            }

            int end_fence = -1;
            for (int i = start_fence + 1; i < lines.length; i++) {
                string s = lines[i].strip ();
                if (s == "```" || (s.has_prefix ("```") && !s.substring (3).strip ().has_prefix ("{"))) {
                    end_fence = i;
                    break;
                }
            }

            if (end_fence == -1 || cursor_line >= end_fence) {
                return false;
            }

            int body_start = start_fence + 1;
            while (body_start < end_fence && lines[body_start].strip ().has_prefix ("#|")) {
                body_start++;
            }

            body_start_line = body_start;
            end_fence_line = end_fence;
            return true;
        }

        /**
         * Replaces the body of the fenced code chunk enclosing `cursor_line`
         * while preserving the opening fence (` ```{r} `) and any `#| ...` Quarto
         * chunk options at the top of the chunk.
         *
         * Returns the updated document text, or null if `cursor_line` is not inside a chunk.
         */
        public static string? replace_active_chunk_preserving_options (string doc_text, int cursor_line, string new_code) {
            int body_start;
            int end_fence;
            if (!get_active_chunk_body_range (doc_text, cursor_line, out body_start, out end_fence)) {
                return null;
            }

            string[] lines = doc_text.split ("\n");
            var sb = new StringBuilder ();
            for (int i = 0; i < body_start; i++) {
                sb.append (lines[i]).append ("\n");
            }

            string clean_code = new_code;
            while (clean_code.has_suffix ("\n")) {
                clean_code = clean_code.substring (0, clean_code.length - 1);
            }
            sb.append (clean_code).append ("\n");

            for (int i = end_fence; i < lines.length; i++) {
                sb.append (lines[i]);
                if (i < lines.length - 1) {
                    sb.append ("\n");
                }
            }

            return sb.str;
        }
    }
}
