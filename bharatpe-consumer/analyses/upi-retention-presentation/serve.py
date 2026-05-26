#!/usr/bin/env python3
"""Serve the UPI retention HTML deck from this folder only."""
from __future__ import annotations

import http.server
import os
import socketserver
import sys
import webbrowser
from functools import partial

PORT = 8765
ROOT = os.path.dirname(os.path.abspath(__file__))
DECK = "upi-retention-results.html"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)


def main() -> int:
    if not os.path.isfile(os.path.join(ROOT, DECK)):
        print(f"Missing {DECK} in {ROOT}", file=sys.stderr)
        return 1
    url = f"http://127.0.0.1:{PORT}/{DECK}"
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"Serving {ROOT}\nOpen: {url}\nCtrl+C to stop.")
        webbrowser.open(url)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
