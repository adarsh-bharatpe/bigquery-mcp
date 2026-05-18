-- Warehouse row counts for FACT / DIM tables (sanity check in BigQuery console).
-- ⚠ These are NOT “VPA addresses created” totals. “6.3M+ users” on the deck = COUNT(*) on upi.users below.
-- ⚠ “VPA created” (e.g. ~3M registry) must be taken from the VPA registration mart / product table — not this file.

SELECT 'upi_transactions' AS table_id, COUNT(*) AS row_count
FROM `bharatpe-analytics-prod.upi.upi_transactions`;

SELECT 'users' AS table_id, COUNT(*) AS row_count
FROM `bharatpe-analytics-prod.upi.users`;
