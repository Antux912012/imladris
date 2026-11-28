#!/usr/bin/env Rscript
# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: Apache-2.0
#
# Imladris Qualitative Biostatistical Verification Bridge (.imladris/scripts/qual_stats.R)
# Computes Krippendorff's Alpha, Fisher's Exact Test, and Thematic Saturation Curves from .imladris-qual.db

args <- commandArgs(trailingOnly = TRUE)
db_path <- if (length(args) >= 1) args[1] else ".imladris-qual.db"

if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RSQLite", quietly = TRUE)) {
  stop("Install DBI and RSQLite to query .imladris-qual.db directly from R.")
}

con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(con), add = TRUE)

spans <- DBI::dbReadTable(con, "spans")
cat(sprintf("Loaded %d qualitative spans across %d coders.\n", nrow(spans), length(unique(spans$coder_id))))

if (nrow(spans) > 0 && requireNamespace("irr", quietly = TRUE)) {
  spans$unit <- paste(spans$file_path, spans$line_start, sep = ":")
  mat_df <- reshape(spans[, c("unit", "coder_id", "code_id")], idvar = "unit", timevar = "coder_id", direction = "wide")
  rating_mat <- t(as.matrix(mat_df[, -1, drop = FALSE]))
  ka <- irr::kripp.alpha(rating_mat, method = "nominal")
  cat(sprintf("Krippendorff's alpha (nominal): %.6f (units = %d, raters = %d)\n", ka$value, ka$subjects, ka$raters))
}

if (nrow(spans) > 0) {
  # Two-sided Fisher's Exact Test across document/entity units
  units <- ifelse(!is.na(spans$entity_id) & nzchar(spans$entity_id), spans$entity_id, spans$file_path)
  codes <- sort(unique(spans$code_id))
  all_units <- unique(units)
  if (length(codes) >= 2 && length(all_units) >= 2) {
    for (i in seq_len(length(codes) - 1)) {
      for (j in (i + 1):length(codes)) {
        has_a <- all_units %in% units[spans$code_id == codes[i]]
        has_b <- all_units %in% units[spans$code_id == codes[j]]
        tbl <- matrix(c(sum(has_a & has_b), sum(has_a & !has_b), sum(!has_a & has_b), sum(!has_a & !has_b)), nrow = 2, byrow = TRUE)
        ft <- stats::fisher.test(tbl, alternative = "two.sided")
        cat(sprintf("Fisher Exact [%s x %s]: co=%d, OR=%.4f, p=%.6g\n", codes[i], codes[j], tbl[1, 1], ft$estimate, ft$p.value))
      }
    }
  }

  docs <- unique(spans$file_path)
  seen <- character(0)
  sat <- data.frame(doc_idx = seq_along(docs), doc = basename(docs), cumulative_codes = integer(length(docs)))
  for (i in seq_along(docs)) {
    seen <- union(seen, spans$code_id[spans$file_path == docs[i]])
    sat$cumulative_codes[i] <- length(seen)
  }
  print(sat)
}
