#!/usr/bin/env python3
"""Resolve internal href/src on the Vire homepage. Exit 1 on a miss."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
INDEX = ROOT / "index.html"
ATTR = re.compile(r"""(?:href|src)=["']([^"']+)["']""", re.I)
ID_ATTR = re.compile(r"""\bid=["']([^"']+)["']""", re.I)


def main() -> int:
    html = INDEX.read_text(encoding="utf-8")
    ids = set(ID_ATTR.findall(html))
    missing = []
    checked = 0
    for raw in ATTR.findall(html):
        url = raw.strip()
        if not url or url.startswith(("http://", "https://", "mailto:")):
            continue
        checked += 1
        if url.startswith("#"):
            name = url[1:]
            if name and name not in ids:
                missing.append(f"missing id {url}")
            continue
        path = (INDEX.parent / url.split("#", 1)[0]).resolve()
        if not path.exists():
            missing.append(f"missing file {url} -> {path}")
            continue
        if "#" in url:
            frag = url.split("#", 1)[1]
            if path.suffix.lower() in {".html", ".htm"}:
                other = path.read_text(encoding="utf-8")
                other_ids = set(ID_ATTR.findall(other))
                if frag not in other_ids:
                    missing.append(f"missing id {url}")
    css = (ROOT / "css" / "vire.css").read_text(encoding="utf-8")
    for raw in ATTR.findall(css):
        if raw.startswith(("http://", "https://", "data:")):
            missing.append(f"external css url {raw}")
    js = (ROOT / "js" / "vire.js").read_text(encoding="utf-8")
    if "http://" in js or "https://" in js:
        missing.append("external url in js")
    if "http://" in html or "https://fonts" in html or "cdn." in html:
        # GitHub repo links are expected https. Flag fonts/cdns only.
        if "fonts.googleapis" in html or "cdn." in html or "googletag" in html:
            missing.append("disallowed third-party asset")
    print(f"checked {checked} internal refs, {len(ids)} ids")
    if missing:
        print("\n".join(missing))
        return 1
    print("site links ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
