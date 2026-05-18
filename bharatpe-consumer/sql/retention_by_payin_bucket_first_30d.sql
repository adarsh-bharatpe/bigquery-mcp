-- Outgoing retention by count of incoming pay-ins (RECEIVE_EXTERNAL) in the first 30 days after
-- first outgoing SUCCESS. Buckets: <5, 5–20 inclusive, >20. Retention = calendar-month outgoing
-- activity (same outgoing definition as other lenses).

WITH succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st
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
payin_counts AS (
  SELECT
    f.pid,
    COUNTIF(s.st = 'RECEIVE_EXTERNAL'
      AND s.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)) AS payin_n
  FROM first_out f
  JOIN succ s ON s.pid = f.pid
  GROUP BY f.pid
),
payin_bucket AS (
  SELECT
    pid,
    CASE
      WHEN payin_n < 5 THEN 'payin_lt_5'
      WHEN payin_n BETWEEN 5 AND 20 THEN 'payin_5_to_20'
      ELSE 'payin_gt_20'
    END AS payin_seg
  FROM payin_counts
),
cohort AS (
  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month
  FROM first_out f
),
labeled AS (
  SELECT c.pid, c.cohort_month, p.payin_seg
  FROM cohort c
  JOIN payin_bucket p ON c.pid = p.pid
  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
cohort_sizes AS (
  SELECT cohort_month, payin_seg, COUNT(*) AS cohort_users
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
    l.payin_seg,
    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month
  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 3
  GROUP BY 1, 2, 3
)
SELECT
  r.cohort_month,
  r.payin_seg,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.payin_seg = cs.payin_seg
ORDER BY r.cohort_month, r.payin_seg, r.period_n;
