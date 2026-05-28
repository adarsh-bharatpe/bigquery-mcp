-- =============================================================================
-- UPI retention queries — bharatpe-analytics-prod.upi
-- =============================================================================
-- Table: upi_transactions (primary fact). See upi-schema-reference.md.
-- Standard row filters (all sections unless noted):
--   status = 'SUCCESS'
--   user_profile_id IS NOT NULL AND user_profile_id != ''
--   IFNULL(__deleted, 'false') = 'false'
-- Partition: filter DATE(created_at) in every query for cost control.
-- Payout filter (sections a & b): subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
-- =============================================================================


-- =============================================================================
-- (a) M+1 payout transaction retention from first-month payout SUCCESS
-- =============================================================================
-- Payout: subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
-- Cohort month: calendar month of first payout SUCCESS per user
-- M+1: ≥1 payout SUCCESS in the next calendar month
-- Output: cohort_month, cohort_users, m1_active_users, m1_retention_pct

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
),
user_first_payout AS (
  SELECT
    pid,
    DATE_TRUNC(MIN(d), MONTH) AS cohort_month
  FROM payout_txns
  GROUP BY pid
),
cohorts AS (
  SELECT cohort_month, COUNT(*) AS cohort_users
  FROM user_first_payout
  GROUP BY cohort_month
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
m1 AS (
  SELECT
    f.cohort_month,
    COUNT(DISTINCT f.pid) AS m1_active_users
  FROM user_first_payout f
  JOIN month_active m
    ON f.pid = m.pid
   AND DATE_DIFF(m.activity_month, f.cohort_month, MONTH) = 1
  GROUP BY f.cohort_month
)
SELECT
  c.cohort_month,
  c.cohort_users,
  IFNULL(m.m1_active_users, 0) AS m1_active_users,
  ROUND(100 * IFNULL(m.m1_active_users, 0) / NULLIF(c.cohort_users, 0), 2) AS m1_retention_pct
FROM cohorts c
LEFT JOIN m1 m ON c.cohort_month = m.cohort_month
WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 14 MONTH), MONTH)
  AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)
ORDER BY c.cohort_month;


-- =============================================================================
-- (b) Volume cohort retention M+0..M+6 — POOLED across cohort months (PAYOUT ONLY)
-- =============================================================================
-- Payout: subType IS DISTINCT FROM 'RECEIVE_EXTERNAL' (same as section a).
-- After first qualifying PAYOUT SUCCESS, count further PAYOUT SUCCESS txns in the
-- next 30 days (inclusive of first-payout day). Bucket → Light / Medium / Heavy / Power.
-- Cohort month = month of first PAYOUT SUCCESS. Retention M+k = share with ≥1 PAYOUT
-- SUCCESS in calendar month cohort_month + k months.
--
-- Buckets:
--   Light:  1 payout SUCCESS in first 30d
--   Medium: 2–5
--   Heavy:  6–20
--   Power:  21+
--
-- Adjust pool window in user_dim WHERE (default Aug 2025–Jan 2026).

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    created_at,
    DATE(created_at) AS d
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 MONTH)
),
user_first AS (
  SELECT
    pid,
    DATE_TRUNC(MIN(d), MONTH) AS cohort_month,
    MIN(created_at) AS first_ts
  FROM payout_txns
  GROUP BY pid
),
first_30d AS (
  SELECT s.pid, COUNT(*) AS txns_first_30d
  FROM payout_txns s
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
  WHERE f.cohort_month >= DATE('2025-08-01')
    AND f.cohort_month < DATE('2026-02-01')
),
monthly_active AS (
  SELECT DISTINCT pid, DATE_TRUNC(d, MONTH) AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.volume_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_dim u
  JOIN monthly_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT volume_segment, COUNT(*) AS cohort_users
  FROM user_dim
  GROUP BY 1
)
SELECT
  r.volume_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.volume_segment = cs.volume_segment
ORDER BY
  CASE r.volume_segment
    WHEN 'Light' THEN 1 WHEN 'Medium' THEN 2 WHEN 'Heavy' THEN 3 WHEN 'Power' THEN 4
  END,
  r.period_n;


-- =============================================================================
-- (b) Volume cohort retention M+0..M+6 — BY cohort_month × segment (PAYOUT ONLY)
-- =============================================================================
-- Same definitions as pooled (b); one row per cohort_month, volume_segment, period_n.
-- Includes engagement: avg payout txns and amount per active user in that month.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    created_at,
    DATE(created_at) AS d,
    amount
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 MONTH)
),
user_first AS (
  SELECT
    pid,
    DATE_TRUNC(MIN(d), MONTH) AS cohort_month,
    MIN(created_at) AS first_ts
  FROM payout_txns
  GROUP BY pid
),
first_30d AS (
  SELECT s.pid, COUNT(*) AS txns_first_30d
  FROM payout_txns s
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
  FROM payout_txns
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
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct,
  ROUND(SAFE_DIVIDE(r.total_txns, r.active_users), 2) AS avg_txns_per_active_user,
  ROUND(SAFE_DIVIDE(r.total_amount, r.active_users), 2) AS avg_amount_per_active_user
FROM retention r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.volume_segment = cs.volume_segment
WHERE r.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
ORDER BY r.cohort_month, r.volume_segment, r.period_n;


-- =============================================================================
-- (c) Payout retention from month of onboarding (users × upi_transactions)
-- =============================================================================
-- Onboarding month: calendar month of upi.users.created_at (profile_id cohort).
-- Activity: payout SUCCESS on upi_transactions (subType not RECEIVE_EXTERNAL).
-- Join: users.profile_id = upi_transactions.user_profile_id
-- Periods: M+0 (same month as onboarding), M+1, M+2, M+3, M+6
-- Retention %: users with ≥1 payout SUCCESS in that calendar month ÷ cohort size
--
-- Note: Later periods are blank/incomplete until that calendar month has elapsed
-- (e.g. M+6 for Dec 2025 needs activity in Jun 2026).

WITH users_dim AS (
  SELECT
    profile_id AS pid,
    DATE_TRUNC(DATE(created_at), MONTH) AS onboarding_month
  FROM `bharatpe-analytics-prod.upi.users`
  WHERE IFNULL(__deleted, 'false') = 'false'
    AND profile_id IS NOT NULL AND profile_id != ''
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
),
payout_months AS (
  SELECT DISTINCT
    user_profile_id AS pid,
    DATE_TRUNC(DATE(created_at), MONTH) AS activity_month
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)
),
cohort_sizes AS (
  SELECT onboarding_month, COUNT(*) AS cohort_users
  FROM users_dim
  GROUP BY 1
),
retention AS (
  SELECT
    u.onboarding_month,
    DATE_DIFF(p.activity_month, u.onboarding_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM users_dim u
  JOIN payout_months p ON u.pid = p.pid
  WHERE DATE_DIFF(p.activity_month, u.onboarding_month, MONTH) IN (0, 1, 2, 3, 6)
  GROUP BY 1, 2
)
SELECT
  c.onboarding_month,
  c.cohort_users,
  per AS period_n,
  IFNULL(r.active_users, 0) AS active_users,
  ROUND(100 * IFNULL(r.active_users, 0) / c.cohort_users, 2) AS retention_pct
FROM cohort_sizes c
CROSS JOIN UNNEST([0, 1, 2, 3, 6]) AS per
LEFT JOIN retention r
  ON c.onboarding_month = r.onboarding_month AND per = r.period_n
WHERE c.onboarding_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 14 MONTH), MONTH)
  AND c.onboarding_month < DATE_TRUNC(CURRENT_DATE(), MONTH)
ORDER BY c.onboarding_month, per;


-- =============================================================================
-- (d) Retention lens — average payout TPV bucket (first 30 days after first payout)
-- =============================================================================
-- Bucket = AVG(ABS(amount)) on payout SUCCESS txns in [first_payout_day, +30d].
-- Cohort month = month of first payout SUCCESS. Retention M+0..M+6 on payout activity.
-- TPV buckets: avg_lt_100 | avg_100_500 | avg_500_2000 | avg_ge_2000

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    ABS(SAFE_CAST(amount AS FLOAT64)) AS amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
avg30 AS (
  SELECT
    o.pid,
    AVG(o.amt) AS avg_payout_amt,
    SUM(o.amt) AS tpv_30d,
    COUNT(*) AS txn_cnt_30d
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
user_cohort AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.avg_payout_amt < 100 THEN 'avg_lt_100'
      WHEN a.avg_payout_amt < 500 THEN 'avg_100_500'
      WHEN a.avg_payout_amt < 2000 THEN 'avg_500_2000'
      ELSE 'avg_ge_2000'
    END AS tpv_bucket,
    a.avg_payout_amt,
    a.tpv_30d
  FROM first_payout f
  JOIN avg30 a ON f.pid = a.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.tpv_bucket,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT
    tpv_bucket,
    COUNT(*) AS cohort_users,
    ROUND(AVG(avg_payout_amt), 2) AS mean_avg_amt,
    ROUND(AVG(tpv_30d), 2) AS mean_tpv_30d
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.tpv_bucket,
  r.period_n,
  cs.cohort_users,
  cs.mean_avg_amt,
  cs.mean_tpv_30d,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.tpv_bucket = cs.tpv_bucket
ORDER BY
  CASE r.tpv_bucket
    WHEN 'avg_lt_100' THEN 1
    WHEN 'avg_100_500' THEN 2
    WHEN 'avg_500_2000' THEN 3
    ELSE 4
  END,
  r.period_n;


-- =============================================================================
-- (d) Same lens — BY cohort_month × TPV bucket (detail; adjust cohort filter)
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    ABS(SAFE_CAST(amount AS FLOAT64)) AS amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
avg30 AS (
  SELECT o.pid, AVG(o.amt) AS avg_payout_amt
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
labeled AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.avg_payout_amt < 100 THEN 'avg_lt_100'
      WHEN a.avg_payout_amt < 500 THEN 'avg_100_500'
      WHEN a.avg_payout_amt < 2000 THEN 'avg_500_2000'
      ELSE 'avg_ge_2000'
    END AS tpv_bucket
  FROM first_payout f
  JOIN avg30 a ON f.pid = a.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.tpv_bucket,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, tpv_bucket, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.tpv_bucket,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.tpv_bucket = cs.tpv_bucket
ORDER BY r.cohort_month, r.tpv_bucket, r.period_n;


-- =============================================================================
-- (e) Retention lens — first 30d pay-in count bucket (Light / Medium / Heavy / Power)
-- =============================================================================
-- Pay-in: subType = 'RECEIVE_EXTERNAL' SUCCESS in [first_payout_day, +30d].
-- Bucket on pay-in count; cohort month = month of first payout SUCCESS.
-- Retention M+0..M+6 = payout activity (subType IS DISTINCT FROM 'RECEIVE_EXTERNAL').
-- Pay-in buckets: Light <5 | Medium 5-20 | Heavy 21-50 | Power 51+

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
all_succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    subType AS st
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
payin_30d AS (
  SELECT
    f.pid,
    f.fd,
    COUNTIF(
      s.st = 'RECEIVE_EXTERNAL'
      AND s.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
    ) AS payin_n
  FROM first_payout f
  INNER JOIN all_succ s ON f.pid = s.pid
  GROUP BY f.pid, f.fd
),
user_cohort AS (
  SELECT
    p.pid,
    DATE_TRUNC(p.fd, MONTH) AS cohort_month,
    p.payin_n,
    CASE
      WHEN p.payin_n < 5 THEN 'Light'
      WHEN p.payin_n BETWEEN 5 AND 20 THEN 'Medium'
      WHEN p.payin_n BETWEEN 21 AND 50 THEN 'Heavy'
      ELSE 'Power'
    END AS payin_segment
  FROM payin_30d p
  WHERE p.fd >= DATE('2025-08-01')
    AND p.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.payin_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT
    payin_segment,
    COUNT(*) AS cohort_users,
    ROUND(AVG(payin_n), 2) AS mean_payin
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.payin_segment,
  r.period_n,
  cs.cohort_users,
  cs.mean_payin,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.payin_segment = cs.payin_segment
ORDER BY
  CASE r.payin_segment
    WHEN 'Light' THEN 1
    WHEN 'Medium' THEN 2
    WHEN 'Heavy' THEN 3
    ELSE 4
  END,
  r.period_n;


-- =============================================================================
-- (e) Same lens — BY cohort_month × pay-in segment
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
all_succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    subType AS st
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
payin_30d AS (
  SELECT
    f.pid,
    f.fd,
    COUNTIF(
      s.st = 'RECEIVE_EXTERNAL'
      AND s.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
    ) AS payin_n
  FROM first_payout f
  INNER JOIN all_succ s ON f.pid = s.pid
  GROUP BY f.pid, f.fd
),
labeled AS (
  SELECT
    p.pid,
    DATE_TRUNC(p.fd, MONTH) AS cohort_month,
    CASE
      WHEN p.payin_n < 5 THEN 'Light'
      WHEN p.payin_n BETWEEN 5 AND 20 THEN 'Medium'
      WHEN p.payin_n BETWEEN 21 AND 50 THEN 'Heavy'
      ELSE 'Power'
    END AS payin_segment
  FROM payin_30d p
  WHERE DATE_TRUNC(p.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(p.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.payin_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, payin_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.payin_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.payin_segment = cs.payin_segment
ORDER BY r.cohort_month, r.payin_segment, r.period_n;


-- =============================================================================
-- (f) Retention lens — exclusive outgoing subType in first 30d (QR / UPI_ID / …)
-- =============================================================================
-- After first payout SUCCESS, label users by distinct payout subTypes in [fd, +30d]:
--   Only QR | Only UPI_ID | Only CONTACT | Only INTENT | Mixture (2+ distinct)
--   Other only = single subType not in the four rails (excluded from POOLED SELECT)
-- Retention M+0..M+6 = payout activity. NULL subType stored as 'NULL'.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
win AS (
  SELECT
    o.pid,
    IFNULL(o.st, 'NULL') AS st
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
),
subtype_agg AS (
  SELECT
    pid,
    COUNT(DISTINCT st) AS n_distinct_st,
    ARRAY_AGG(DISTINCT st ORDER BY st) AS sts
  FROM win
  GROUP BY pid
),
user_cohort AS (
  SELECT
    a.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'QR' THEN 'Only QR'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'UPI_ID' THEN 'Only UPI_ID'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'CONTACT' THEN 'Only CONTACT'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'INTENT' THEN 'Only INTENT'
      WHEN a.n_distinct_st >= 2 THEN 'Mixture'
      ELSE 'Other only'
    END AS rail_segment
  FROM subtype_agg a
  JOIN first_payout f ON a.pid = f.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.rail_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT rail_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.rail_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.rail_segment = cs.rail_segment
WHERE r.rail_segment != 'Other only'
ORDER BY
  CASE r.rail_segment
    WHEN 'Only QR' THEN 1
    WHEN 'Only UPI_ID' THEN 2
    WHEN 'Only CONTACT' THEN 3
    WHEN 'Only INTENT' THEN 4
    WHEN 'Mixture' THEN 5
    ELSE 6
  END,
  r.period_n;


-- =============================================================================
-- (f) Same lens — BY cohort_month × rail segment (includes Other only)
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
win AS (
  SELECT
    o.pid,
    IFNULL(o.st, 'NULL') AS st
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
),
subtype_agg AS (
  SELECT
    pid,
    COUNT(DISTINCT st) AS n_distinct_st,
    ARRAY_AGG(DISTINCT st ORDER BY st) AS sts
  FROM win
  GROUP BY pid
),
labeled AS (
  SELECT
    a.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'QR' THEN 'Only QR'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'UPI_ID' THEN 'Only UPI_ID'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'CONTACT' THEN 'Only CONTACT'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'INTENT' THEN 'Only INTENT'
      WHEN a.n_distinct_st >= 2 THEN 'Mixture'
      ELSE 'Other only'
    END AS rail_segment
  FROM subtype_agg a
  JOIN first_payout f ON a.pid = f.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.rail_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, rail_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.rail_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.rail_segment = cs.rail_segment
ORDER BY r.cohort_month, r.rail_segment, r.period_n;


-- =============================================================================
-- (f) Retention lens — exclusive outgoing subType in first 30d (QR / UPI_ID / …)
-- =============================================================================
-- After first payout SUCCESS, label users by distinct payout subTypes in [fd, +30d]:
--   Only QR | Only UPI_ID | Only CONTACT | Only INTENT | Mixture (2+ distinct)
--   Other only = single subType not in the four rails (excluded from POOLED SELECT)
-- Retention M+0..M+6 = payout activity. NULL subType stored as 'NULL'.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
win AS (
  SELECT
    o.pid,
    IFNULL(o.st, 'NULL') AS st
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
),
subtype_agg AS (
  SELECT
    pid,
    COUNT(DISTINCT st) AS n_distinct_st,
    ARRAY_AGG(DISTINCT st ORDER BY st) AS sts
  FROM win
  GROUP BY pid
),
user_cohort AS (
  SELECT
    a.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'QR' THEN 'Only QR'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'UPI_ID' THEN 'Only UPI_ID'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'CONTACT' THEN 'Only CONTACT'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'INTENT' THEN 'Only INTENT'
      WHEN a.n_distinct_st >= 2 THEN 'Mixture'
      ELSE 'Other only'
    END AS rail_segment
  FROM subtype_agg a
  JOIN first_payout f ON a.pid = f.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.rail_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT rail_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.rail_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.rail_segment = cs.rail_segment
WHERE r.rail_segment != 'Other only'
ORDER BY
  CASE r.rail_segment
    WHEN 'Only QR' THEN 1
    WHEN 'Only UPI_ID' THEN 2
    WHEN 'Only CONTACT' THEN 3
    WHEN 'Only INTENT' THEN 4
    WHEN 'Mixture' THEN 5
    ELSE 6
  END,
  r.period_n;


-- =============================================================================
-- (f) Same lens — BY cohort_month × rail segment (includes Other only)
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    subType AS st
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
win AS (
  SELECT
    o.pid,
    IFNULL(o.st, 'NULL') AS st
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
),
subtype_agg AS (
  SELECT
    pid,
    COUNT(DISTINCT st) AS n_distinct_st,
    ARRAY_AGG(DISTINCT st ORDER BY st) AS sts
  FROM win
  GROUP BY pid
),
labeled AS (
  SELECT
    a.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'QR' THEN 'Only QR'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'UPI_ID' THEN 'Only UPI_ID'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'CONTACT' THEN 'Only CONTACT'
      WHEN a.n_distinct_st = 1 AND a.sts[OFFSET(0)] = 'INTENT' THEN 'Only INTENT'
      WHEN a.n_distinct_st >= 2 THEN 'Mixture'
      ELSE 'Other only'
    END AS rail_segment
  FROM subtype_agg a
  JOIN first_payout f ON a.pid = f.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.rail_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, rail_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.rail_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.rail_segment = cs.rail_segment
ORDER BY r.cohort_month, r.rail_segment, r.period_n;


-- =============================================================================
-- (g) Retention lens — dominant payout MCC in first 30d (global top 20 + OTHER)
-- =============================================================================
-- Top 20 MCCs = highest payout SUCCESS txn count in 16-month scan window.
-- Per user: dominant MCC = max txn count in [first_payout_day, +30d]; ties by mcc.
-- Retention M+0..M+6 on payout activity. See retention_by_top20_mcc.sql (legacy).

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    mcc
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
top20_mcc AS (
  SELECT mcc
  FROM (
    SELECT mcc, COUNT(*) AS cnt
    FROM payout_txns
    GROUP BY mcc
  )
  QUALIFY ROW_NUMBER() OVER (ORDER BY cnt DESC) <= 20
),
mcc_counts AS (
  SELECT
    o.pid,
    o.mcc,
    COUNT(*) AS n
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid, o.mcc
),
dominant AS (
  SELECT pid, mcc AS dom_mcc
  FROM (
    SELECT
      pid,
      mcc,
      ROW_NUMBER() OVER (
        PARTITION BY pid
        ORDER BY n DESC, COALESCE(CAST(mcc AS STRING), '')
      ) AS rn
    FROM mcc_counts
  )
  WHERE rn = 1
),
user_cohort AS (
  SELECT
    d.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN t.mcc IS NOT NULL THEN COALESCE(CAST(d.dom_mcc AS STRING), 'NULL')
      ELSE 'OTHER'
    END AS mcc_seg
  FROM dominant d
  JOIN first_payout f ON d.pid = f.pid
  LEFT JOIN top20_mcc t ON d.dom_mcc IS NOT DISTINCT FROM t.mcc
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.mcc_seg,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT mcc_seg, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.mcc_seg,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.mcc_seg = cs.mcc_seg
ORDER BY cs.cohort_users DESC, r.mcc_seg, r.period_n;


-- =============================================================================
-- (g) Same lens — BY cohort_month × mcc_seg
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    mcc
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
top20_mcc AS (
  SELECT mcc
  FROM (
    SELECT mcc, COUNT(*) AS cnt
    FROM payout_txns
    GROUP BY mcc
  )
  QUALIFY ROW_NUMBER() OVER (ORDER BY cnt DESC) <= 20
),
mcc_counts AS (
  SELECT
    o.pid,
    o.mcc,
    COUNT(*) AS n
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid, o.mcc
),
dominant AS (
  SELECT pid, mcc AS dom_mcc
  FROM (
    SELECT
      pid,
      mcc,
      ROW_NUMBER() OVER (
        PARTITION BY pid
        ORDER BY n DESC, COALESCE(CAST(mcc AS STRING), '')
      ) AS rn
    FROM mcc_counts
  )
  WHERE rn = 1
),
labeled AS (
  SELECT
    d.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN t.mcc IS NOT NULL THEN COALESCE(CAST(d.dom_mcc AS STRING), 'NULL')
      ELSE 'OTHER'
    END AS mcc_seg
  FROM dominant d
  JOIN first_payout f ON d.pid = f.pid
  LEFT JOIN top20_mcc t ON d.dom_mcc IS NOT DISTINCT FROM t.mcc
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.mcc_seg,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, mcc_seg, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
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
ORDER BY r.cohort_month, cs.cohort_users DESC, r.mcc_seg, r.period_n;


-- =============================================================================
-- (h) Retention lens — exclusive BharatPe QR on first 30d payout txns
-- =============================================================================
-- is_bharatpe_qr: IFNULL(..., 0). Segments:
--   Only BharatPe QR (all txns = 1) | Only non-BharatPe QR (all = 0) | Mixed (both)
-- Retention M+0..M+6 on payout activity. See retention_by_bharatpe_qr_share.sql (share buckets).

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    IFNULL(is_bharatpe_qr, 0) AS bp_qr
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
qr_30d AS (
  SELECT
    o.pid,
    COUNT(*) AS n_txn,
    COUNTIF(o.bp_qr = 1) AS n_bp,
    COUNTIF(o.bp_qr = 0) AS n_non_bp
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
user_cohort AS (
  SELECT
    q.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN q.n_bp = q.n_txn AND q.n_txn > 0 THEN 'Only BharatPe QR'
      WHEN q.n_non_bp = q.n_txn AND q.n_txn > 0 THEN 'Only non-BharatPe QR'
      WHEN q.n_bp > 0 AND q.n_non_bp > 0 THEN 'Mixed'
      ELSE 'No payout in window'
    END AS qr_segment
  FROM qr_30d q
  JOIN first_payout f ON q.pid = f.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.qr_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
    AND u.qr_segment IN ('Only BharatPe QR', 'Only non-BharatPe QR', 'Mixed')
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT qr_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  WHERE qr_segment IN ('Only BharatPe QR', 'Only non-BharatPe QR', 'Mixed')
  GROUP BY 1
)
SELECT
  r.qr_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.qr_segment = cs.qr_segment
ORDER BY
  CASE r.qr_segment
    WHEN 'Only non-BharatPe QR' THEN 1
    WHEN 'Mixed' THEN 2
    ELSE 3
  END,
  r.period_n;


-- =============================================================================
-- (h) Same lens — BY cohort_month × qr_segment
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    IFNULL(is_bharatpe_qr, 0) AS bp_qr
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
qr_30d AS (
  SELECT
    o.pid,
    COUNT(*) AS n_txn,
    COUNTIF(o.bp_qr = 1) AS n_bp,
    COUNTIF(o.bp_qr = 0) AS n_non_bp
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
labeled AS (
  SELECT
    q.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN q.n_bp = q.n_txn AND q.n_txn > 0 THEN 'Only BharatPe QR'
      WHEN q.n_non_bp = q.n_txn AND q.n_txn > 0 THEN 'Only non-BharatPe QR'
      WHEN q.n_bp > 0 AND q.n_non_bp > 0 THEN 'Mixed'
      ELSE 'No payout in window'
    END AS qr_segment
  FROM qr_30d q
  JOIN first_payout f ON q.pid = f.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.qr_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
    AND l.qr_segment IN ('Only BharatPe QR', 'Only non-BharatPe QR', 'Mixed')
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, qr_segment, COUNT(*) AS cohort_users
  FROM labeled
  WHERE qr_segment IN ('Only BharatPe QR', 'Only non-BharatPe QR', 'Mixed')
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.qr_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.qr_segment = cs.qr_segment
ORDER BY r.cohort_month, r.qr_segment, r.period_n;


-- =============================================================================
-- (i) Retention lens — Zillion redemption on payout (reward_amount > 0, first 30d)
-- =============================================================================
-- Ever redeemed = >=1 payout SUCCESS in [first_payout_day, +30d] with reward_amount > 0
-- Never redeemed = no such txn in window. Retention M+0..M+6 on payout activity.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    SAFE_CAST(reward_amount AS FLOAT64) AS reward_amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
reward_30d AS (
  SELECT
    o.pid,
    COUNTIF(o.reward_amt > 0) AS n_redeem
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
user_cohort AS (
  SELECT
    q.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN q.n_redeem > 0 THEN 'Ever redeemed'
      ELSE 'Never redeemed'
    END AS reward_segment
  FROM reward_30d q
  JOIN first_payout f ON q.pid = f.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.reward_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT reward_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.reward_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.reward_segment = cs.reward_segment
ORDER BY
  CASE r.reward_segment WHEN 'Never redeemed' THEN 1 ELSE 2 END,
  r.period_n;


-- =============================================================================
-- (i) Same lens — BY cohort_month × reward_segment
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    SAFE_CAST(reward_amount AS FLOAT64) AS reward_amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
reward_30d AS (
  SELECT
    o.pid,
    COUNTIF(o.reward_amt > 0) AS n_redeem
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
labeled AS (
  SELECT
    q.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN q.n_redeem > 0 THEN 'Ever redeemed'
      ELSE 'Never redeemed'
    END AS reward_segment
  FROM reward_30d q
  JOIN first_payout f ON q.pid = f.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.reward_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, reward_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.reward_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.reward_segment = cs.reward_segment
ORDER BY r.cohort_month, r.reward_segment, r.period_n;


-- =============================================================================
-- (j) Retention lens — Zillion earn (SUCCESS, amount > 50, type != RECEIVE_EXTERNAL)
-- =============================================================================
-- Earn in first 30d after first payout: user-specified type rule on ALL SUCCESS txns.
-- Cohort anchor: first payout (subType not RECEIVE_EXTERNAL). Retention on payout M+0..M+6.
-- See upi-schema-reference.md: type never = RECEIVE_EXTERNAL; pay-ins can satisfy type rule.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
all_succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    type,
    SAFE_CAST(amount AS FLOAT64) AS amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
earn_30d AS (
  SELECT
    f.pid,
    COUNTIF(s.type IS DISTINCT FROM 'RECEIVE_EXTERNAL' AND s.amt > 50) AS n_earn
  FROM first_payout f
  JOIN all_succ s
    ON f.pid = s.pid
   AND s.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY f.pid
),
user_cohort AS (
  SELECT
    e.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN e.n_earn > 0 THEN 'Ever earned'
      ELSE 'Never earned'
    END AS earn_segment
  FROM earn_30d e
  JOIN first_payout f ON e.pid = f.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.earn_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT earn_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.earn_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.earn_segment = cs.earn_segment
ORDER BY CASE r.earn_segment WHEN 'Never earned' THEN 1 ELSE 2 END, r.period_n;


-- =============================================================================
-- (j) Same lens — payout-only earn (subType outward, amount > 50) — POOLED
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    SAFE_CAST(amount AS FLOAT64) AS amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
earn_30d AS (
  SELECT
    o.pid,
    COUNTIF(o.amt > 50) AS n_earn
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY o.pid
),
user_cohort AS (
  SELECT
    e.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN e.n_earn > 0 THEN 'Ever earned (payout only)'
      ELSE 'Never earned (payout only)'
    END AS earn_segment
  FROM earn_30d e
  JOIN first_payout f ON e.pid = f.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.earn_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT earn_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.earn_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.earn_segment = cs.earn_segment
ORDER BY r.earn_segment, r.period_n;


-- =============================================================================
-- (j) User type rule — BY cohort_month × earn_segment
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
all_succ AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    type,
    SAFE_CAST(amount AS FLOAT64) AS amt
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
earn_30d AS (
  SELECT
    f.pid,
    COUNTIF(s.type IS DISTINCT FROM 'RECEIVE_EXTERNAL' AND s.amt > 50) AS n_earn
  FROM first_payout f
  JOIN all_succ s
    ON f.pid = s.pid
   AND s.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY f.pid
),
labeled AS (
  SELECT
    e.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN e.n_earn > 0 THEN 'Ever earned'
      ELSE 'Never earned'
    END AS earn_segment
  FROM earn_30d e
  JOIN first_payout f ON e.pid = f.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.earn_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, earn_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.earn_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.earn_segment = cs.earn_segment
ORDER BY r.cohort_month, r.earn_segment, r.period_n;


-- =============================================================================
-- (k) Retention lens — outward platform (attributes.platform: Android / Ios)
-- =============================================================================
-- Platform = JSON_VALUE(attributes, '$.platform') on payout SUCCESS in first 30d.
-- Segments: Only Android | Only iOS (Ios) | Mixed (both) | Unknown (excluded from POOLED)
-- Retention M+0..M+6 on payout activity.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    JSON_VALUE(attributes, '$.platform') AS platform
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
win AS (
  SELECT
    o.pid,
    o.platform
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
),
platform_agg AS (
  SELECT
    pid,
    COUNTIF(platform = 'Android') AS n_android,
    COUNTIF(platform = 'Ios') AS n_ios,
    COUNT(*) AS n_txn
  FROM win
  GROUP BY pid
),
user_cohort AS (
  SELECT
    a.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.n_android = a.n_txn AND a.n_txn > 0 THEN 'Only Android'
      WHEN a.n_ios = a.n_txn AND a.n_txn > 0 THEN 'Only iOS'
      WHEN a.n_android > 0 AND a.n_ios > 0 THEN 'Mixed (Android + iOS)'
      ELSE 'Unknown / other platform'
    END AS platform_segment
  FROM platform_agg a
  JOIN first_payout f ON a.pid = f.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.platform_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
    AND u.platform_segment IN ('Only Android', 'Only iOS', 'Mixed (Android + iOS)')
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT platform_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  WHERE platform_segment IN ('Only Android', 'Only iOS', 'Mixed (Android + iOS)')
  GROUP BY 1
)
SELECT
  r.platform_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.platform_segment = cs.platform_segment
ORDER BY
  CASE r.platform_segment
    WHEN 'Only Android' THEN 1
    WHEN 'Only iOS' THEN 2
    ELSE 3
  END,
  r.period_n;


-- =============================================================================
-- (k) Same lens — BY cohort_month (includes Unknown / other platform)
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    JSON_VALUE(attributes, '$.platform') AS platform
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
win AS (
  SELECT
    o.pid,
    o.platform
  FROM payout_txns o
  JOIN first_payout f ON o.pid = f.pid
  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
),
platform_agg AS (
  SELECT
    pid,
    COUNTIF(platform = 'Android') AS n_android,
    COUNTIF(platform = 'Ios') AS n_ios,
    COUNT(*) AS n_txn
  FROM win
  GROUP BY pid
),
labeled AS (
  SELECT
    a.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN a.n_android = a.n_txn AND a.n_txn > 0 THEN 'Only Android'
      WHEN a.n_ios = a.n_txn AND a.n_txn > 0 THEN 'Only iOS'
      WHEN a.n_android > 0 AND a.n_ios > 0 THEN 'Mixed (Android + iOS)'
      ELSE 'Unknown / other platform'
    END AS platform_segment
  FROM platform_agg a
  JOIN first_payout f ON a.pid = f.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.platform_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, platform_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.platform_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.platform_segment = cs.platform_segment
ORDER BY r.cohort_month, r.platform_segment, r.period_n;


-- =============================================================================
-- (l) Retention lens — status of first outward transaction (any status)
-- =============================================================================
-- First outward row = earliest payout-direction txn per user (subType not RECEIVE_EXTERNAL).
-- Cohort month = month of that first attempt. Segments: SUCCESS | FAILED | INITIALIZED
--   (INITIALIZED = INITIALIZED, PENDING, AUTH_PENDING). Retention = payout SUCCESS M+0..M+6.

WITH out_tx AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym,
    status,
    id,
    created_at
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_out AS (
  SELECT
    pid,
    d AS fd,
    status AS first_status
  FROM out_tx
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pid ORDER BY created_at, id) = 1
),
user_cohort AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN f.first_status = 'SUCCESS' THEN 'SUCCESS'
      WHEN f.first_status = 'FAILED' THEN 'FAILED'
      WHEN f.first_status IN ('INITIALIZED', 'PENDING', 'AUTH_PENDING') THEN 'INITIALIZED'
      ELSE 'OTHER'
    END AS status_segment
  FROM first_out f
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
payout_succ AS (
  SELECT
    user_profile_id AS pid,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_succ
),
retention AS (
  SELECT
    u.status_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
    AND u.status_segment IN ('SUCCESS', 'FAILED', 'INITIALIZED')
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT status_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  WHERE status_segment IN ('SUCCESS', 'FAILED', 'INITIALIZED')
  GROUP BY 1
)
SELECT
  r.status_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.status_segment = cs.status_segment
ORDER BY
  CASE r.status_segment
    WHEN 'SUCCESS' THEN 1
    WHEN 'FAILED' THEN 2
    ELSE 3
  END,
  r.period_n;


-- =============================================================================
-- (l) Same lens — BY cohort_month (includes OTHER)
-- =============================================================================

WITH out_tx AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    status,
    id,
    created_at
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_out AS (
  SELECT
    pid,
    d AS fd,
    status AS first_status
  FROM out_tx
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pid ORDER BY created_at, id) = 1
),
labeled AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN f.first_status = 'SUCCESS' THEN 'SUCCESS'
      WHEN f.first_status = 'FAILED' THEN 'FAILED'
      WHEN f.first_status IN ('INITIALIZED', 'PENDING', 'AUTH_PENDING') THEN 'INITIALIZED'
      ELSE 'OTHER'
    END AS status_segment
  FROM first_out f
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
payout_succ AS (
  SELECT
    user_profile_id AS pid,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_succ
),
ret AS (
  SELECT
    l.cohort_month,
    l.status_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, status_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.status_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.status_segment = cs.status_segment
ORDER BY r.cohort_month, r.status_segment, r.period_n;


-- =============================================================================
-- (m) Retention lens — SUCCESS count in first 5 payout attempts (0–5)
-- =============================================================================
-- First 5 outward attempts per user (any status); bucket = count SUCCESS in those 5.
-- Requires exactly 5 attempts. Cohort month = first payout SUCCESS month.
-- Retention M+0..M+6 on payout SUCCESS activity. Buckets 0–5.

WITH out_tx AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    status,
    id,
    created_at
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first5_ranked AS (
  SELECT
    pid,
    status
  FROM out_tx
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pid ORDER BY created_at, id) <= 5
),
first5 AS (
  SELECT
    pid,
    COUNTIF(status = 'SUCCESS') AS succ_in_first5
  FROM first5_ranked
  GROUP BY pid
  HAVING COUNT(*) = 5
),
first_payout_succ AS (
  SELECT
    pid,
    MIN(d) AS fd
  FROM out_tx
  WHERE status = 'SUCCESS'
  GROUP BY pid
),
user_cohort AS (
  SELECT
    f.pid,
    DATE_TRUNC(p.fd, MONTH) AS cohort_month,
    CAST(f.succ_in_first5 AS INT64) AS success_bucket
  FROM first5 f
  JOIN first_payout_succ p ON f.pid = p.pid
  WHERE p.fd >= DATE('2025-08-01')
    AND p.fd < DATE('2026-02-01')
    AND f.succ_in_first5 BETWEEN 0 AND 5
),
payout_succ AS (
  SELECT
    pid,
    DATE_TRUNC(d, MONTH) AS ym
  FROM out_tx
  WHERE status = 'SUCCESS'
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_succ
),
retention AS (
  SELECT
    u.success_bucket,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT success_bucket, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.success_bucket,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.success_bucket = cs.success_bucket
ORDER BY r.success_bucket DESC, r.period_n;


-- =============================================================================
-- (m) Same lens — BY cohort_month (buckets 0–5)
-- =============================================================================

WITH out_tx AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    status,
    id,
    created_at
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first5_ranked AS (
  SELECT
    pid,
    status
  FROM out_tx
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pid ORDER BY created_at, id) <= 5
),
first5 AS (
  SELECT
    pid,
    COUNTIF(status = 'SUCCESS') AS succ_in_first5
  FROM first5_ranked
  GROUP BY pid
  HAVING COUNT(*) = 5
),
first_payout_succ AS (
  SELECT
    pid,
    MIN(d) AS fd
  FROM out_tx
  WHERE status = 'SUCCESS'
  GROUP BY pid
),
labeled AS (
  SELECT
    f.pid,
    DATE_TRUNC(p.fd, MONTH) AS cohort_month,
    CAST(f.succ_in_first5 AS INT64) AS success_bucket
  FROM first5 f
  JOIN first_payout_succ p ON f.pid = p.pid
  WHERE DATE_TRUNC(p.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(p.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
payout_succ AS (
  SELECT
    pid,
    DATE_TRUNC(d, MONTH) AS ym
  FROM out_tx
  WHERE status = 'SUCCESS'
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_succ
),
ret AS (
  SELECT
    l.cohort_month,
    l.success_bucket,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, success_bucket, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.success_bucket,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.success_bucket = cs.success_bucket
ORDER BY r.cohort_month, r.success_bucket DESC, r.period_n;


-- =============================================================================
-- (n) Retention lens — count of linked bank accounts (user_bank_accounts x users x txns)
-- =============================================================================
-- Linkage count = DISTINCT user_bank_accounts.id for user, linked by end of first 30d
-- after first payout SUCCESS. Join: transactions.user_profile_id -> users.profile_id
--   -> user_bank_accounts.user_id = users.id
-- Segments: 1 | 2 | 3 | 4+ accounts. Retention M+0..M+6 on payout SUCCESS.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
linkages AS (
  SELECT
    u.profile_id AS pid,
    COUNT(DISTINCT b.id) AS n_linked
  FROM `bharatpe-analytics-prod.upi.user_bank_accounts` b
  JOIN `bharatpe-analytics-prod.upi.users` u
    ON b.user_id = u.id
  JOIN first_payout f
    ON u.profile_id = f.pid
  WHERE IFNULL(b.__deleted, 'false') = 'false'
    AND IFNULL(u.__deleted, 'false') = 'false'
    AND DATE(b.created_at) <= DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY u.profile_id
),
user_cohort AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    COALESCE(l.n_linked, 0) AS n_linked,
    CASE
      WHEN COALESCE(l.n_linked, 0) = 1 THEN '1 account'
      WHEN COALESCE(l.n_linked, 0) = 2 THEN '2 accounts'
      WHEN COALESCE(l.n_linked, 0) = 3 THEN '3 accounts'
      WHEN COALESCE(l.n_linked, 0) >= 4 THEN '4+ accounts'
      ELSE '0 accounts'
    END AS linkage_segment
  FROM first_payout f
  LEFT JOIN linkages l ON f.pid = l.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.linkage_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
    AND u.linkage_segment IN ('1 account', '2 accounts', '3 accounts', '4+ accounts')
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT linkage_segment, COUNT(*) AS cohort_users, ROUND(AVG(n_linked), 2) AS mean_linked
  FROM user_cohort
  WHERE linkage_segment IN ('1 account', '2 accounts', '3 accounts', '4+ accounts')
  GROUP BY 1
)
SELECT
  r.linkage_segment,
  r.period_n,
  cs.cohort_users,
  cs.mean_linked,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.linkage_segment = cs.linkage_segment
ORDER BY cs.mean_linked, r.period_n;


-- =============================================================================
-- (n) Same lens — BY cohort_month (includes 0 accounts)
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
linkages AS (
  SELECT
    u.profile_id AS pid,
    COUNT(DISTINCT b.id) AS n_linked
  FROM `bharatpe-analytics-prod.upi.user_bank_accounts` b
  JOIN `bharatpe-analytics-prod.upi.users` u
    ON b.user_id = u.id
  JOIN first_payout f
    ON u.profile_id = f.pid
  WHERE IFNULL(b.__deleted, 'false') = 'false'
    AND IFNULL(u.__deleted, 'false') = 'false'
    AND DATE(b.created_at) <= DATE_ADD(f.fd, INTERVAL 30 DAY)
  GROUP BY u.profile_id
),
labeled AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN COALESCE(l.n_linked, 0) = 0 THEN '0 accounts'
      WHEN COALESCE(l.n_linked, 0) = 1 THEN '1 account'
      WHEN COALESCE(l.n_linked, 0) = 2 THEN '2 accounts'
      WHEN COALESCE(l.n_linked, 0) = 3 THEN '3 accounts'
      ELSE '4+ accounts'
    END AS linkage_segment
  FROM first_payout f
  LEFT JOIN linkages l ON f.pid = l.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.linkage_segment,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, linkage_segment, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.linkage_segment,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.linkage_segment = cs.linkage_segment
ORDER BY r.cohort_month, r.linkage_segment, r.period_n;


-- =============================================================================
-- (o) Retention lens — linked account type (user_bank_accounts x users x txns)
-- =============================================================================
-- Dominant account_type = type with most linked account rows by end of first 30d
-- after first payout SUCCESS (tie-break: account_type ASC).
-- Segments: SAVINGS | CURRENT | CREDIT | CREDITLINE | OTHER dominant | No linked.
-- Retention M+0..M+6 on payout SUCCESS. Pool: first-payout SUCCESS 2025-08..2026-01.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
linked AS (
  SELECT
    u.profile_id AS pid,
    COALESCE(b.account_type, 'UNKNOWN') AS account_type
  FROM `bharatpe-analytics-prod.upi.user_bank_accounts` b
  JOIN `bharatpe-analytics-prod.upi.users` u
    ON b.user_id = u.id
  JOIN first_payout f
    ON u.profile_id = f.pid
  WHERE IFNULL(b.__deleted, 'false') = 'false'
    AND IFNULL(u.__deleted, 'false') = 'false'
    AND DATE(b.created_at) <= DATE_ADD(f.fd, INTERVAL 30 DAY)
),
type_counts AS (
  SELECT pid, account_type, COUNT(*) AS n
  FROM linked
  GROUP BY 1, 2
),
dominant AS (
  SELECT pid, account_type AS dominant_account_type
  FROM type_counts
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pid ORDER BY n DESC, account_type) = 1
),
user_cohort AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN d.dominant_account_type IN ('SAVINGS', 'CURRENT', 'CREDIT', 'CREDITLINE')
        THEN d.dominant_account_type
      WHEN d.pid IS NULL THEN 'No linked account (30d)'
      ELSE 'OTHER dominant'
    END AS dominant_type
  FROM first_payout f
  LEFT JOIN dominant d ON f.pid = d.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.dominant_type,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT dominant_type, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.dominant_type,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.dominant_type = cs.dominant_type
ORDER BY cs.cohort_users DESC, r.period_n;


-- =============================================================================
-- (o) Same lens — BY cohort_month (dominant account_type)
-- =============================================================================

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
linked AS (
  SELECT
    u.profile_id AS pid,
    COALESCE(b.account_type, 'UNKNOWN') AS account_type
  FROM `bharatpe-analytics-prod.upi.user_bank_accounts` b
  JOIN `bharatpe-analytics-prod.upi.users` u
    ON b.user_id = u.id
  JOIN first_payout f
    ON u.profile_id = f.pid
  WHERE IFNULL(b.__deleted, 'false') = 'false'
    AND IFNULL(u.__deleted, 'false') = 'false'
    AND DATE(b.created_at) <= DATE_ADD(f.fd, INTERVAL 30 DAY)
),
type_counts AS (
  SELECT pid, account_type, COUNT(*) AS n
  FROM linked
  GROUP BY 1, 2
),
dominant AS (
  SELECT pid, account_type AS dominant_account_type
  FROM type_counts
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pid ORDER BY n DESC, account_type) = 1
),
labeled AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN d.dominant_account_type IN ('SAVINGS', 'CURRENT', 'CREDIT', 'CREDITLINE')
        THEN d.dominant_account_type
      WHEN d.pid IS NULL THEN 'No linked account (30d)'
      ELSE 'OTHER dominant'
    END AS dominant_type
  FROM first_payout f
  LEFT JOIN dominant d ON f.pid = d.pid
  WHERE DATE_TRUNC(f.fd, MONTH) >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)
    AND DATE_TRUNC(f.fd, MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
ret AS (
  SELECT
    l.cohort_month,
    l.dominant_type,
    DATE_DIFF(m.activity_month, l.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT l.pid) AS active_users
  FROM labeled l
  JOIN month_active m ON l.pid = m.pid AND m.activity_month >= l.cohort_month
  WHERE DATE_DIFF(m.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2, 3
),
cohort_sizes AS (
  SELECT cohort_month, dominant_type, COUNT(*) AS cohort_users
  FROM labeled
  GROUP BY 1, 2
)
SELECT
  r.cohort_month,
  r.dominant_type,
  r.period_n,
  r.active_users,
  cs.cohort_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM ret r
JOIN cohort_sizes cs
  ON r.cohort_month = cs.cohort_month AND r.dominant_type = cs.dominant_type
ORDER BY r.cohort_month, cs.cohort_users DESC, r.period_n;


-- =============================================================================
-- (o) Appendix — exclusive single account_type linked in first 30d (POOLED)
-- =============================================================================
-- Users with exactly one distinct account_type among linked rows in window.
-- "Mixed account types" = 2+ distinct types. Retention M+0..M+6.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
linked AS (
  SELECT
    u.profile_id AS pid,
    COALESCE(b.account_type, 'UNKNOWN') AS account_type
  FROM `bharatpe-analytics-prod.upi.user_bank_accounts` b
  JOIN `bharatpe-analytics-prod.upi.users` u
    ON b.user_id = u.id
  JOIN first_payout f
    ON u.profile_id = f.pid
  WHERE IFNULL(b.__deleted, 'false') = 'false'
    AND IFNULL(u.__deleted, 'false') = 'false'
    AND DATE(b.created_at) <= DATE_ADD(f.fd, INTERVAL 30 DAY)
),
type_counts AS (
  SELECT pid, account_type, COUNT(*) AS n
  FROM linked
  GROUP BY 1, 2
),
user_agg AS (
  SELECT pid, COUNT(DISTINCT account_type) AS n_distinct_types
  FROM type_counts
  GROUP BY pid
),
only_type AS (
  SELECT t.pid, t.account_type
  FROM type_counts t
  JOIN user_agg u ON t.pid = u.pid AND u.n_distinct_types = 1
),
mixed AS (
  SELECT pid FROM user_agg WHERE n_distinct_types >= 2
),
user_cohort AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    CASE
      WHEN m.pid IS NOT NULL THEN 'Mixed account types'
      WHEN o.account_type = 'SAVINGS' THEN 'SAVINGS only'
      WHEN o.account_type = 'CURRENT' THEN 'CURRENT only'
      WHEN o.pid IS NOT NULL THEN 'Other type only'
      ELSE 'No linked account (30d)'
    END AS account_type_segment
  FROM first_payout f
  LEFT JOIN only_type o ON f.pid = o.pid
  LEFT JOIN mixed m ON f.pid = m.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.account_type_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
    AND u.account_type_segment IN (
      'SAVINGS only', 'CURRENT only', 'Mixed account types', 'Other type only'
    )
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT account_type_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  WHERE account_type_segment IN (
    'SAVINGS only', 'CURRENT only', 'Mixed account types', 'Other type only'
  )
  GROUP BY 1
)
SELECT
  r.account_type_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.account_type_segment = cs.account_type_segment
ORDER BY cs.cohort_users DESC, r.period_n;


-- =============================================================================
-- (p) Retention lens — installed apps (consumer_psp.appDetails × upi.users)
-- =============================================================================
-- Join: CAST(upi.users.client_reference_id AS INT64) = consumer_psp.customerId
-- PSP row: latest per customerId (ORDER BY updatedAt DESC), non-empty appDetails
-- Partition: DATE(consumer_psp.createdAt) >= '2024-01-01' (required)
-- Cohort: first payout SUCCESS 2025-08-01 .. 2026-01-31 (same pool as b–o)
-- Retention: payout SUCCESS M+0..M+6; segments below are PSP-matched users only.
--
-- UPI wallet count uses DISTINCT core payment brands (not raw package IDs, not
-- BNPL/lending/broking apps). See brand CASE in upi_brand CTE below.
-- Category flags: ecommerce / quick-commerce / travel / food-delivery allowlists.


-- -----------------------------------------------------------------------------
-- (p) UPI wallet count on device — POOLED
-- Segments: Single UPI app | 2-4 UPI apps | 5+ UPI apps
-- -----------------------------------------------------------------------------

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
user_first AS (
  SELECT
    pid,
    DATE_TRUNC(MIN(d), MONTH) AS cohort_month,
    MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
psp AS (
  SELECT
    customerId,
    appDetails,
    ROW_NUMBER() OVER (PARTITION BY customerId ORDER BY updatedAt DESC) AS rn
  FROM `bharatpe-analytics-prod.bharatpe_mongo_data.consumer_psp`
  WHERE IFNULL(__deleted, 'false') = 'false'
    AND appDetails IS NOT NULL AND appDetails != ''
    AND DATE(createdAt) >= DATE('2024-01-01')
),
user_base AS (
  SELECT
    f.pid,
    f.cohort_month,
    p.appDetails
  FROM user_first f
  JOIN `bharatpe-analytics-prod.upi.users` u
    ON f.pid = u.profile_id
   AND IFNULL(u.__deleted, 'false') = 'false'
  INNER JOIN psp p
    ON CAST(u.client_reference_id AS INT64) = p.customerId
   AND p.rn = 1
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
apps AS (
  SELECT
    b.pid,
    LOWER(TRIM(COALESCE(
      JSON_VALUE(elem, '$.name'),
      TRIM(JSON_VALUE(elem, '$'), '"')
    ))) AS app_name
  FROM user_base b,
  UNNEST(JSON_QUERY_ARRAY(b.appDetails)) AS elem
),
upi_brand AS (
  SELECT DISTINCT
    pid,
    CASE
      WHEN app_name IN ('paytm', 'paytm payments bank') THEN 'paytm'
      WHEN app_name = 'phonepe'
        OR REGEXP_CONTAINS(app_name, r'^com\.phonepe') THEN 'phonepe'
      WHEN app_name IN ('google pay', 'gpay')
        OR REGEXP_CONTAINS(app_name, r'nbu\.paisa') THEN 'gpay'
      WHEN app_name = 'bhim'
        OR REGEXP_CONTAINS(app_name, r'bhim\.upi|npci\.bhim') THEN 'bhim'
      WHEN app_name = 'cred'
        OR REGEXP_CONTAINS(app_name, r'dreamplug') THEN 'cred'
      WHEN app_name = 'navi'
        OR REGEXP_CONTAINS(app_name, r'^com\.navi') THEN 'navi'
      WHEN app_name IN ('super.money', 'supermoney', 'super money')
        OR REGEXP_CONTAINS(app_name, r'super\.money|money\.super') THEN 'supermoney'
      WHEN app_name = 'mobikwik'
        OR REGEXP_CONTAINS(app_name, r'mobikwik') THEN 'mobikwik'
      WHEN app_name = 'amazon pay' THEN 'amazonpay'
      WHEN app_name = 'whatsapp' THEN 'whatsapp'
      WHEN app_name = 'slice' THEN 'slice'
      WHEN app_name = 'jupiter' THEN 'jupiter'
      WHEN app_name = 'fi money' THEN 'fi'
      WHEN app_name = 'freecharge' THEN 'freecharge'
      WHEN app_name IN ('payzapp', 'hdfc payzapp') THEN 'payzapp'
      WHEN app_name = 'yono sbi' THEN 'yono'
      WHEN app_name = 'icici imobile' THEN 'icici'
      WHEN app_name = 'axis pay' THEN 'axis'
      WHEN app_name = 'kotak 811' THEN 'kotak'
      WHEN app_name IN ('bharatpe', 'bharatpe for business') THEN 'bharatpe'
      WHEN app_name IN (
        'postpe', 'lazy pay', 'simpl', 'airtel thanks',
        'jiofinance', 'jio payments bank', 'yespay', 'popclub', 'twid'
      ) THEN 'other_wallet'
      ELSE NULL
    END AS upi_brand
  FROM apps
),
user_upi AS (
  SELECT
    b.pid,
    b.cohort_month,
    COUNT(DISTINCT ub.upi_brand) AS upi_n
  FROM user_base b
  LEFT JOIN upi_brand ub ON b.pid = ub.pid
  GROUP BY 1, 2
),
user_cohort AS (
  SELECT
    pid,
    cohort_month,
    CASE
      WHEN upi_n = 1 THEN 'Single UPI app'
      WHEN upi_n BETWEEN 2 AND 4 THEN '2-4 UPI apps'
      WHEN upi_n >= 5 THEN '5+ UPI apps'
      ELSE 'No core UPI wallet detected'
    END AS upi_segment
  FROM user_upi
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.upi_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m
    ON u.pid = m.pid
   AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
    AND u.upi_segment IN ('Single UPI app', '2-4 UPI apps', '5+ UPI apps')
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT upi_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  WHERE upi_segment IN ('Single UPI app', '2-4 UPI apps', '5+ UPI apps')
  GROUP BY 1
)
SELECT
  r.upi_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.upi_segment = cs.upi_segment
ORDER BY
  CASE r.upi_segment
    WHEN 'Single UPI app' THEN 1
    WHEN '2-4 UPI apps' THEN 2
    ELSE 3
  END,
  r.period_n;


-- -----------------------------------------------------------------------------
-- (p) Installed app category flags — POOLED (Has / No per category)
-- -----------------------------------------------------------------------------

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
user_first AS (
  SELECT
    pid,
    DATE_TRUNC(MIN(d), MONTH) AS cohort_month,
    MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
psp AS (
  SELECT
    customerId,
    appDetails,
    ROW_NUMBER() OVER (PARTITION BY customerId ORDER BY updatedAt DESC) AS rn
  FROM `bharatpe-analytics-prod.bharatpe_mongo_data.consumer_psp`
  WHERE IFNULL(__deleted, 'false') = 'false'
    AND appDetails IS NOT NULL AND appDetails != ''
    AND DATE(createdAt) >= DATE('2024-01-01')
),
user_base AS (
  SELECT
    f.pid,
    f.cohort_month,
    p.appDetails
  FROM user_first f
  JOIN `bharatpe-analytics-prod.upi.users` u
    ON f.pid = u.profile_id
   AND IFNULL(u.__deleted, 'false') = 'false'
  INNER JOIN psp p
    ON CAST(u.client_reference_id AS INT64) = p.customerId
   AND p.rn = 1
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
apps AS (
  SELECT
    b.pid,
    LOWER(TRIM(COALESCE(
      JSON_VALUE(elem, '$.name'),
      TRIM(JSON_VALUE(elem, '$'), '"')
    ))) AS app_name
  FROM user_base b,
  UNNEST(JSON_QUERY_ARRAY(b.appDetails)) AS elem
),
flags AS (
  SELECT
    b.pid,
    b.cohort_month,
    LOGICAL_OR(REGEXP_CONTAINS(
      a.app_name,
      r'^(flipkart|amazon|myntra|meesho|ajio|nykaa)$'
    )) AS has_ecommerce,
    LOGICAL_OR(REGEXP_CONTAINS(
      a.app_name,
      r'^(blinkit|zepto|bigbasket|jiomart)$'
    )) AS has_qcommerce,
    LOGICAL_OR(REGEXP_CONTAINS(
      a.app_name,
      r'^(uber|ola|rapido|makemytrip|goibibo|irctc rail connect|redbus|ixigo|yatra)$'
    )) AS has_travel,
    LOGICAL_OR(REGEXP_CONTAINS(
      a.app_name,
      r'^(swiggy|zomato)$'
    )) AS has_food
  FROM user_base b
  LEFT JOIN apps a ON b.pid = a.pid
  GROUP BY 1, 2
),
segments AS (
  SELECT pid, cohort_month, 'Has ecommerce app' AS app_segment
  FROM flags WHERE has_ecommerce
  UNION ALL
  SELECT pid, cohort_month, 'No ecommerce app'
  FROM flags WHERE NOT has_ecommerce
  UNION ALL
  SELECT pid, cohort_month, 'Has quick-commerce app'
  FROM flags WHERE has_qcommerce
  UNION ALL
  SELECT pid, cohort_month, 'No quick-commerce app'
  FROM flags WHERE NOT has_qcommerce
  UNION ALL
  SELECT pid, cohort_month, 'Has travel app'
  FROM flags WHERE has_travel
  UNION ALL
  SELECT pid, cohort_month, 'No travel app'
  FROM flags WHERE NOT has_travel
  UNION ALL
  SELECT pid, cohort_month, 'Has food-delivery app'
  FROM flags WHERE has_food
  UNION ALL
  SELECT pid, cohort_month, 'No food-delivery app'
  FROM flags WHERE NOT has_food
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    s.app_segment,
    DATE_DIFF(m.activity_month, s.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT s.pid) AS active_users
  FROM segments s
  JOIN month_active m
    ON s.pid = m.pid
   AND m.activity_month >= s.cohort_month
  WHERE DATE_DIFF(m.activity_month, s.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT app_segment, COUNT(DISTINCT pid) AS cohort_users
  FROM segments
  GROUP BY 1
)
SELECT
  r.app_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.app_segment = cs.app_segment
ORDER BY r.app_segment, r.period_n;


-- =============================================================================
-- (q) Retention lens — UPI Lite enabled (`upi_transactions.note`)
-- =============================================================================
-- UPI Lite signal: ≥1 SUCCESS txn with UPPER(note) LIKE '%UPI LITE%' in the
-- first 30 calendar days after first payout SUCCESS (setup, topup, payment,
-- closure, etc.). Retention M+0..M+6 on payout SUCCESS (subType not RECEIVE_EXTERNAL).
-- Pool: first-payout SUCCESS cohort months 2025-08-01 → 2026-01-31.

WITH payout_txns AS (
  SELECT
    user_profile_id AS pid,
    DATE(created_at) AS d,
    DATE_TRUNC(DATE(created_at), MONTH) AS ym
  FROM `bharatpe-analytics-prod.upi.upi_transactions`
  WHERE status = 'SUCCESS'
    AND user_profile_id IS NOT NULL AND user_profile_id != ''
    AND IFNULL(__deleted, 'false') = 'false'
    AND subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'
    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)
),
first_payout AS (
  SELECT pid, MIN(d) AS fd
  FROM payout_txns
  GROUP BY pid
),
lite_in_30d AS (
  SELECT DISTINCT f.pid
  FROM first_payout f
  INNER JOIN `bharatpe-analytics-prod.upi.upi_transactions` t
    ON t.user_profile_id = f.pid
  WHERE t.status = 'SUCCESS'
    AND IFNULL(t.__deleted, 'false') = 'false'
    AND UPPER(t.note) LIKE '%UPI LITE%'
    AND DATE(t.created_at) BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)
),
user_cohort AS (
  SELECT
    f.pid,
    DATE_TRUNC(f.fd, MONTH) AS cohort_month,
    IF(l.pid IS NOT NULL, 'UPI Lite enabled (30d)', 'Not enabled (30d)') AS lite_segment
  FROM first_payout f
  LEFT JOIN lite_in_30d l ON f.pid = l.pid
  WHERE f.fd >= DATE('2025-08-01')
    AND f.fd < DATE('2026-02-01')
),
month_active AS (
  SELECT DISTINCT pid, ym AS activity_month
  FROM payout_txns
),
retention AS (
  SELECT
    u.lite_segment,
    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,
    COUNT(DISTINCT u.pid) AS active_users
  FROM user_cohort u
  JOIN month_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month
  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6
  GROUP BY 1, 2
),
cohort_sizes AS (
  SELECT lite_segment, COUNT(*) AS cohort_users
  FROM user_cohort
  GROUP BY 1
)
SELECT
  r.lite_segment,
  r.period_n,
  cs.cohort_users,
  r.active_users,
  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct
FROM retention r
JOIN cohort_sizes cs ON r.lite_segment = cs.lite_segment
ORDER BY
  CASE r.lite_segment WHEN 'Not enabled (30d)' THEN 1 ELSE 2 END,
  r.period_n;
