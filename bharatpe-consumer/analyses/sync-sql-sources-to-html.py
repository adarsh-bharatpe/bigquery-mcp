#!/usr/bin/env python3
"""Embed analyses/sql-sources.json into the deck (#sql-sources-data) as valid JSON."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
JSON_PATH = ROOT / "sql-sources.json"
HTML_PATH = ROOT / "upi-retention-presentation" / "upi-retention-results.html"
PATTERN = re.compile(
    r'(<script id="sql-sources-data" type="application/json">)(.*?)(</script>)',
    re.DOTALL,
)


def main() -> int:
    if not JSON_PATH.is_file():
        print(f"Missing {JSON_PATH}", file=sys.stderr)
        return 1
    if not HTML_PATH.is_file():
        print(f"Missing {HTML_PATH}", file=sys.stderr)
        return 1

    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    payload = json.dumps(data, ensure_ascii=False)
    html = HTML_PATH.read_text(encoding="utf-8")
    m = PATTERN.search(html)
    if not m:
        print("Could not find #sql-sources-data in HTML", file=sys.stderr)
        return 1

    HTML_PATH.write_text(html[: m.start()] + m.group(1) + payload + m.group(3) + html[m.end() :], encoding="utf-8")
    json.loads(PATTERN.search(HTML_PATH.read_text(encoding="utf-8")).group(2))
    print(f"Synced {len(data)} SQL entries into {HTML_PATH.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
