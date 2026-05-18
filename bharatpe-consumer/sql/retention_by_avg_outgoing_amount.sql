-- Outgoing retention by average outgoing amount in first 30 days after first outgoing SUCCESS.
-- Outgoing = subType IS NULL OR subType != 'RECEIVE_EXTERNAL'
-- Amount bucket is AVG(ABS(amount)) over those outgoing txns in the 30d window.
-- Adjust cohort window filters at the bottom.

WITH succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st,
    ABS(SAFE_CAST(amount AS FLOAT64)) AS amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
out_tx AS (
  SELECT * FROM succ
  WHERE st IS NULL OR st != 'RECEIVE_EXTERNAL'
),
first_out AS (
  SELECT pid, MIN(d) AS fd
  FROM out_tx
  GROUP BY pid
),
avg30 AS (
  SELECT
    o.pid,
    AVG(o.amt) AS avg_out_amt
  FROM out_tx o
  JOIN first_out f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
amt_bucket AS (
  SELECT
    pid,
    CASE
      WHEN avg_out_amt < 100 THEN 'avg_lt_100'
      WHEN avg_out_amt < 500 THEN 'avg_100_500'
      WHEN avg_out_amt < 2000 THEN 'avg_500_2000'
      ELSE 'avg_ge_2000'
    END AS amt_seg
  FROM avg30
),
cohort AS (
  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month
  FROM first_out f
),
labeled AS (
  SELECT c.pid, c.cohort_month, a.amt_seg
  FROM cohort c
  JOIN amt_bucket a ON c.pid = a.pid
  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
cohort_sizes AS (
  SELECT cohort_month, amt_seg, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
),
month_activity AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM out_tx
),
ret AS (
  SELECT
    l.cohort_month,
    l.amt_seg,
    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month
  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 2
  GROUP BY 1, 2, 3
)
SELECT
  r.cohort_month,
  r.amt_seg,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.amt_seg = cs.amt_seg
ORDER BY r.cohort_month, r.amt_seg, r.period_n;
