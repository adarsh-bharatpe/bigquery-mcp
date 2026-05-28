UPI Engagement & Retention — portable slide deck
================================================

This folder is the only copy of the deck (no duplicate HTML elsewhere).

Files
-----
  upi-retention-results.html   Presentation (32 navigable slides; CSS, JS, SQL all inline)
  assets/logos/*.svg           Competitor logos (paths: assets/logos/…)
  serve.py                     Optional local server (recommended)
  start.sh / start.bat         Launch server + browser

Run
---
  macOS / Linux:  ./start.sh
  Windows:        start.bat
  Manual:         python3 serve.py  →  http://127.0.0.1:8765/upi-retention-results.html

Offline: double-click upi-retention-results.html (keep assets/ beside it).

Navigation: ← → Space · Home/End · lens index slide 26 · Source on slides 6–22 · Play Store 5.18–5.20 slides 23–25.

SQL sources JSON (canonical): ../sql-sources.json (synced into HTML #sql-sources-data).

Word export (full slide content, no data removed):
  .export-venv/bin/python export_to_docx.py
  → upi-retention-results.docx

Rebuild zip (from parent analyses/ folder):
  ./pack-presentation.sh
