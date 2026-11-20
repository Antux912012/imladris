#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: Apache-2.0

# Description: Verifies that the latest Imladris GitHub release is synchronized
# with the FlatPark package registry and that FlatPark uses the Flatpak archive
# format (never .deb). If a mismatch is detected, this script notifies the
# FlatPark release webhook to trigger an automatic update.

set -euo pipefail

APP_ID="io.github.Antux912012.Imladris"
REPO="Antux912012/imladris"
FLATPARK_RAW_URL="https://raw.githubusercontent.com/flatpark/flatpark/main/registry/${APP_ID}/${APP_ID}.yml"
WEBHOOK_URL="https://hooks.flatpark.org/release"

echo "[1/3] Querying the latest GitHub release for ${REPO}..."
RELEASE_JSON="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
  "https://api.github.com/repos/${REPO}/releases/latest")"

LATEST_TAG="$(jq -r '.tag_name' <<<"$RELEASE_JSON")"
LATEST_VERSION="$(jq -r '.tag_name | ltrimstr("v")' <<<"$RELEASE_JSON")"
echo "  Latest GitHub Release: ${LATEST_TAG} (version: ${LATEST_VERSION})"

echo "[2/3] Checking the active package version and format on FlatPark..."
FLATPARK_MANIFEST="$(curl -fsSL "${FLATPARK_RAW_URL}")"
FLATPARK_URL="$(grep -E 'url: https://github.com/.*/releases/download/' <<<"$FLATPARK_MANIFEST" | head -n1 | awk '{print $2}')"

FORMAT_ERROR=0
if [[ "$FLATPARK_URL" == *.deb ]]; then
  echo "  ERROR: FlatPark manifest points to a .deb package (${FLATPARK_URL}) instead of the Flatpak format!" >&2
  FORMAT_ERROR=1
fi

if [[ "$FLATPARK_URL" =~ /v([^/]+)/ ]]; then
  FLATPARK_VERSION="${BASH_REMATCH[1]}"
  echo "  Active FlatPark Version: ${FLATPARK_VERSION} (${FLATPARK_URL})"
else
  echo "  Warning: Could not parse version from FlatPark manifest URL: ${FLATPARK_URL}"
  FLATPARK_VERSION="unknown"
fi

echo "[3/3] Comparing release versions and format..."
if [ "${FORMAT_ERROR}" -eq 0 ] && [ "${LATEST_VERSION}" = "${FLATPARK_VERSION}" ]; then
  echo "SUCCESS: FlatPark is synchronized with ${LATEST_VERSION} using the Flatpak format."
  exit 0
else
  echo "MISMATCH DETECTED: GitHub=${LATEST_VERSION}, FlatPark=${FLATPARK_VERSION}, format_error=${FORMAT_ERROR}."
  echo "Sending release notification to FlatPark webhook..."

  PAYLOAD="$(jq -n --arg a "$APP_ID" --arg t "$LATEST_TAG" --arg r "$REPO" \
    '{app_id: $a, tag: $t, repository: $r}')"

  RESPONSE="$(curl -sS --fail-with-body --retry 3 --max-time 30 \
    -H 'content-type: application/json' \
    -d "$PAYLOAD" "$WEBHOOK_URL")"

  echo "FlatPark response: ${RESPONSE}"
  echo "FlatPark received the notification and is updating the package."

  if [ "${FORMAT_ERROR}" -ne 0 ]; then
    echo "WARNING: Active FlatPark registry entry (${FLATPARK_VERSION}) currently points to .deb; awaiting FlatPark webhook update to ${LATEST_TAG} (${APP_ID}-flatpak-x86_64.tar.gz)." >&2
  fi
fi
