#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Update docs/index.html, docs/install.sh, and README.md to a release version."""

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")


def fetch_latest_github_release_version(repo: str, token: str | None) -> str:
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    tag = str(data.get("tag_name", "")).strip()
    return tag.lstrip("v")


def detect_current_landing_version(index_html: Path, install_sh: Path) -> str | None:
    if install_sh.exists():
        m = re.search(r'^VERSION="([^"]+)"', install_sh.read_text(encoding="utf-8"), re.MULTILINE)
        if m:
            return m.group(1).strip()
    if index_html.exists():
        m = re.search(r'<span class="ver">v([^<]+)</span>', index_html.read_text(encoding="utf-8"))
        if m:
            return m.group(1).strip()
    return None


def replace_version_in_file(path: Path, old_ver: str, new_ver: str) -> bool:
    if not path.exists():
        return False
    original = path.read_text(encoding="utf-8")
    updated = original.replace(old_ver, new_ver)
    if updated == original:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync landing page version from GitHub release tag.")
    parser.add_argument("--version", help="Target version or tag (e.g. 0.32.0 or v0.32.0)")
    parser.add_argument("--repo", default="Antux912012/imladris", help="GitHub owner/repo")
    parser.add_argument("--root", default=".", help="Repository root path")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    index_html = root / "docs" / "index.html"
    install_sh = root / "docs" / "install.sh"
    readme_md = root / "README.md"

    target = (args.version or "").strip().lstrip("v")
    if not target:
        target = fetch_latest_github_release_version(args.repo, os.environ.get("GITHUB_TOKEN"))

    if not SEMVER_RE.match(target):
        print(f"Invalid version string: {target!r}", file=sys.stderr)
        return 1

    old_ver = detect_current_landing_version(index_html, install_sh)
    if not old_ver:
        print("Could not detect current version in docs/index.html or docs/install.sh", file=sys.stderr)
        return 1

    if old_ver == target:
        print(f"Landing page is already at v{target}.")
        return 0

    changed = []
    for f in (index_html, install_sh, readme_md):
        if replace_version_in_file(f, old_ver, target):
            changed.append(str(f.relative_to(root)))

    print(f"Updated landing page version {old_ver} -> {target}: {', '.join(changed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
