-- Outgoing retention by share of BharatPe QR in first 30d outgoing txns after first outgoing.
-- qr_share_30d = COUNT(is_bharatpe_qr=1) / COUNT(outgoing txns) in that window.
-- Segments: no_bharatpe_qr (0%), mixed_qr (0<share<0.5), mostly_bharatpe_qr (>=0.5).
-- Validate is_bharatpe_qr population and semantics before using for product decisions.

WITH succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st,
    IFNULL(is_bharatpe_qr, 0) AS bp_qr
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
qr_share AS (
  SELECT
    o.pid,
    SAFE_DIVIDE(COUNTIF(o.bp_qr = 1), COUNT(*)) AS qr_share_30d
  FROM out_tx o
  JOIN first_out f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
qr_bucket AS (
  SELECT
    pid,
    CASE
      WHEN qr_share_30d = 0 THEN 'no_bharatpe_qr'
      WHEN qr_share_30d < 0.5 THEN 'mixed_qr'
      ELSE 'mostly_bharatpe_qr'
    END AS qr_seg
  FROM qr_share
),
cohort AS (
  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month
  FROM first_out f
),
labeled AS (
  SELECT c.pid, c.cohort_month, q.qr_seg
  FROM cohort c
  JOIN qr_bucket q ON c.pid = q.pid
  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
cohort_sizes AS (
  SELECT cohort_month, qr_seg, COUNT(*) AS cohort_users
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
    l.qr_seg,
    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month
  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 2
  GROUP BY 1, 2, 3
)
SELECT
  r.cohort_month,
  r.qr_seg,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.qr_seg = cs.qr_seg
ORDER BY r.cohort_month, r.qr_seg, r.period_n;
