-- Outgoing retention by dominant outgoing subType in the first 30 days after first outgoing
-- SUCCESS. Dominant = max count of outgoing txns by subType in that window (ties broken by st).
-- Incoming RECEIVE_EXTERNAL is excluded from outgoing and from this label.

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
sub_counts AS (
  SELECT
    o.pid,
    IFNULL(o.st, 'NULL_ST') AS dom_subtype,
    COUNT(*) AS n
  FROM out_tx o
  JOIN first_out f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid, o.st
),
ranked AS (
  SELECT
    pid,
    dom_subtype,
    ROW_NUMBER() OVER (PARTITION BY pid ORDER BY n DESC, dom_subtype) AS rn
  FROM sub_counts
),
dominant AS (
  SELECT pid, dom_subtype
  FROM ranked
  WHERE rn = 1
),
cohort AS (
  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month
  FROM first_out f
),
labeled AS (
  SELECT c.pid, c.cohort_month, d.dom_subtype
  FROM cohort c
  JOIN dominant d ON c.pid = d.pid
  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
cohort_sizes AS (
  SELECT cohort_month, dom_subtype, COUNT(*) AS cohort_users
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
    l.dom_subtype,
    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month
  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 3
  GROUP BY 1, 2, 3
)
SELECT
  r.cohort_month,
  r.dom_subtype,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.dom_subtype = cs.dom_subtype
ORDER BY r.cohort_month, r.dom_subtype, r.period_n;
