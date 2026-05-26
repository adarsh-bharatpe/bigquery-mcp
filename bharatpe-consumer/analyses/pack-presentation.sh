#!/usr/bin/env bash
# Zip the presentation folder (no file copies — single source of truth).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
NAME="upi-retention-presentation"
test -f "$ROOT/$NAME/upi-retention-results.html"
rm -f "$ROOT/${NAME}.zip"
(cd "$ROOT" && zip -rq "${NAME}.zip" "$NAME" -x "*.DS_Store")
echo "Created $ROOT/${NAME}.zip ($(du -h "$ROOT/${NAME}.zip" | cut -f1))"
