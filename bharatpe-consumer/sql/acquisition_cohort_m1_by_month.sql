-- Acquisition M+1 % by first-SUCCESS calendar month.
-- Cohort month = month of each user’s FIRST qualifying SUCCESS (same filters as volume cohort SQL).
-- Active in M+1 = ≥1 SUCCESS in the calendar month immediately after cohort month.
-- Adjust date filters at the bottom.

WITH success_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
),
user_first AS (
  SELECT
    pid,
    DATE_TRUNC(MIN(d), MONTH) AS cohort_month
  FROM success_txns
  GROUP BY pid
),
cohorts AS (
  SELECT cohort_month, COUNT(*) AS cohort_users
  FROM user_first
  GROUP BY cohort_month
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month FROM success_txns
),
m1 AS (
  SELECT
    f.cohort_month,
    COUNT(DISTINCT f.pid) AS m1_active
  FROM user_first f
  JOIN month_active m ON f.pid = m.pid AND m.activity_month >= f.cohort_month
  WHERE DATE_DIFF(m.activity_month, f.cohort_month, MONTH) = 1
  GROUP BY f.cohort_month
)
SELECT
  c.cohort_month,
  c.cohort_users,
  IFNULL(m.m1_active, 0) AS m1_active_users,
  ROUND(100 * IFNULL(m.m1_active, 0) / NULLIF(c.cohort_users, 0), 2) AS m1_retention_pct
FROM cohorts c
LEFT JOIN m1 m ON c.cohort_month = m.cohort_month
WHERE c.cohort_month BETWEEN '2025-09-01' AND '2026-04-01'
ORDER BY c.cohort_month;
