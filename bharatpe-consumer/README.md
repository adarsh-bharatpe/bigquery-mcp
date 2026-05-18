# BharatPe consumer — UPI cohort & retention context

This folder holds **BigQuery + Mixpanel** analysis artifacts for the consumer app (`bharatpe-consumer` in Mixpanel; warehouse tables under `bharatpe-analytics-prod.upi`).

## Contents

| Path | Description |
|------|-------------|
| `upi-cohort-retention.canvas.tsx` | Cursor **Canvas** presentation: warehouse volume cohorts, acquisition M+1, engagement tables, Mixpanel weekly benchmarks, regional BBPS & wealth intent, playbook, links. |
| `upi-cohort-retention.html` | Standalone **web page** version of the deck (brand `#0049CF`, Chart.js charts). Open in any browser; no build step. |
| `sql/cohort_volume_retention.sql` | Reproducible BigQuery SQL for volume-segment retention & engagement (adjust date windows). |

## Canvas preview in Cursor

Cursor loads `.canvas.tsx` from the project `canvases/` directory. Keep the copy under `bigquery-mcp/bharatpe-consumer/` as the source of truth; mirror to the workspace root when you want the live preview:

- **Canonical:** `bigquery-mcp/bharatpe-consumer/upi-cohort-retention.canvas.tsx`
- **Preview (this workspace):** `canvases/upi-cohort-retention.canvas.tsx`

## Related tables (BigQuery MCP)

- `upi.upi_transactions` — partition: `created_at`
- `upi.users` — join `users.profile_id` ↔ `upi_transactions.user_profile_id`

## Mixpanel

- Project: **bharatpe-consumer** (id `3987072`)
- Pay / cross-sell / intent events are listed inside the canvas deck.

Add more per-table notes in this folder as you document Metabase/BigQuery fields (see parent `README.md`).
