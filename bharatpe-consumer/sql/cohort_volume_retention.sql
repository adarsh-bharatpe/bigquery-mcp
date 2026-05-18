-- UPI volume cohort retention & engagement (bharatpe-analytics-prod.upi)
-- Filters: SUCCESS, non-null user_profile_id, __deleted = 'false'
-- Adjust date windows; partition on created_at reduces scan cost.

WITH success_txns AS (
  SELECT
    user_profile_id AS pid,
    created_at,
    DATE(created_at) AS d,
    amount
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
),
monthly_active AS (
  SELECT
    pid,
    DATE_TRUNC(d, MONTH) AS activity_month,
    COUNT(*) AS txns,
    SUM(ABS(IFNULL(amount, 0))) AS vol
  FROM success_txns
  GROUP BY pid, DATE_TRUNC(d, MONTH)
),
retention AS (
  SELECT
    u.cohort_month,
    u.volume_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users,
    SUM(m.txns) AS total_txns,
    SUM(m.vol) AS total_amount
  FROM user_dim u
  JOIN monthly_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, volume_segment, COUNT(*) AS cohort_users
  FROM user_dim
  WHERE cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.volume_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  SAFE_DIVIDE(r.active_users, cs.cohort_users) AS retention_rate,
  SAFE_DIVIDE(r.total_txns, r.active_users) AS avg_txns_per_active_user,
  SAFE_DIVIDE(r.total_amount, r.active_users) AS avg_amount_per_active_user
FROM retention r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.volume_segment = cs.volume_segment
WHERE r.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
ORDER BY r.cohort_month, r.volume_segment, r.period_n;
