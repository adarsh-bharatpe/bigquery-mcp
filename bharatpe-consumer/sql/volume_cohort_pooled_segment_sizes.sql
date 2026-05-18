-- Pooled Light / Medium / Heavy / Power cohort USER counts (Σ over cohort months in range).
-- Matches `cohort_volume_retention.sql` volume-segment rules:
--   Light: 1 SUCCESS in first 30d after each user’s first SUCCESS
--   Medium: 2–5, Heavy: 6–20, Power: 21+
-- Change the cohort_month window in the final WHERE to reproduce deck “pool” totals.

WITH success_txns AS (
  SELECT
    user_profile_id AS pid,
    created_at,
    DATE(created_at) AS d
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 MONTH)
),
user_first AS (
  SELECT
    pid,
    DATE_TRUNC(MIN(d), MONTH) AS cohort_month,
    MIN(created_at) AS first_ts
  FROM success_txns
  GROUP BY pid
),
first_30d AS (
  SELECT s.pid, COUNT(*) AS txns_first_30d
  FROM success_txns s
  JOIN user_first f ON s.pid = f.pid
    AND s.d BETWEEN DATE(f.first_ts) AND DATE_ADD(DATE(f.first_ts), INTERVAL 30 DAY)
  GROUP BY s.pid
),
user_dim AS (
  SELECT
    f.pid,
    f.cohort_month,
    CASE
      WHEN IFNULL(t30.txns_first_30d, 0) <= 1 THEN 'Light'
      WHEN t30.txns_first_30d BETWEEN 2 AND 5 THEN 'Medium'
      WHEN t30.txns_first_30d BETWEEN 6 AND 20 THEN 'Heavy'
      ELSE 'Power'
    END AS volume_segment
  FROM user_first f
  LEFT JOIN first_30d t30 ON f.pid = t30.pid
)
SELECT
  volume_segment,
  COUNT(*) AS pooled_users_in_window
FROM user_dim
WHERE cohort_month >= DATE('2025-08-01')
  AND cohort_month < DATE('2026-02-01')
GROUP BY volume_segment
ORDER BY
  CASE volume_segment
    WHEN 'Light' THEN 1
    WHEN 'Medium' THEN 2
    WHEN 'Heavy' THEN 3
    WHEN 'Power' THEN 4
  END;
