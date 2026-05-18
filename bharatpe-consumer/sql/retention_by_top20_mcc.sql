-- Outgoing retention by dominant MCC in first 30 days after first outgoing SUCCESS.
-- Global top 20 MCCs = highest outgoing (non-RECEIVE_EXTERNAL) txn count in the scan window.
-- Users whose dominant MCC is not in that set → OTHER.

WITH succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st,
    mcc
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
top20_mcc AS (
  SELECT mcc
  FROM (
    SELECT mcc, COUNT(*) AS cnt
    FROM out_tx
    GROUP BY mcc
  )
  QUALIFY ROW_NUMBER() OVER (ORDER BY cnt DESC) <= 20
),
mcc_counts AS (
  SELECT
    o.pid,
    o.mcc,
    COUNT(*) AS n
  FROM out_tx o
  JOIN first_out f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid, o.mcc
),
ranked_mcc AS (
  SELECT
    pid,
    mcc AS dom_mcc,
    ROW_NUMBER() OVER (
      PARTITION BY pid
      ORDER BY n DESC, COALESCE(CAST(mcc AS STRING), '')
    ) AS rn
  FROM mcc_counts
),
dominant AS (
  SELECT pid, dom_mcc
  FROM ranked_mcc
  WHERE rn = 1
),
mcc_seg AS (
  SELECT
    d.pid,
    CASE
      WHEN t.mcc IS NOT NULL THEN CAST(d.dom_mcc AS STRING)
      ELSE 'OTHER'
    END AS mcc_seg
  FROM dominant d
  LEFT JOIN top20_mcc t ON d.dom_mcc IS NOT DISTINCT FROM t.mcc
),
cohort AS (
  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month
  FROM first_out f
),
labeled AS (
  SELECT c.pid, c.cohort_month, m.mcc_seg
  FROM cohort c
  JOIN mcc_seg m ON c.pid = m.pid
  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
cohort_sizes AS (
  SELECT cohort_month, mcc_seg, COUNT(*) AS cohort_users
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
    l.mcc_seg,
    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month
  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 3
  GROUP BY 1, 2, 3
)
SELECT
  r.cohort_month,
  r.mcc_seg,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.mcc_seg = cs.mcc_seg
ORDER BY r.cohort_month, r.mcc_seg, r.period_n;
