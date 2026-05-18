import {
  BarChart,
  Callout,
  Card,
  CardBody,
  CardHeader,
  Code,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  LineChart,
  Link,
  Row,
  Stack,
  Stat,
  Table,
  Text,
  useHostTheme,
} from "cursor/canvas";

// --- BigQuery verbatim SQL (mirror of sql/*.sql; regenerate if queries change)

const AcquisitionCohortM1ByMonth_LINES: string[] = [  "-- Acquisition M+1 % by first-SUCCESS calendar month.",  "-- Cohort month = month of each user\u2019s FIRST qualifying SUCCESS (same filters as volume cohort SQL).",  "-- Active in M+1 = \u22651 SUCCESS in the calendar month immediately after cohort month.",  "-- Adjust date filters at the bottom.",  "",  "WITH success_txns AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    DATE(created_at) AS d,",  "    DATE_TRUNC(DATE(created_at), MONTH) AS ym",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH)",  "),",  "user_first AS (",  "  SELECT",  "    pid,",  "    DATE_TRUNC(MIN(d), MONTH) AS cohort_month",  "  FROM success_txns",  "  GROUP BY pid",  "),",  "cohorts AS (",  "  SELECT cohort_month, COUNT(*) AS cohort_users",  "  FROM user_first",  "  GROUP BY cohort_month",  "),",  "month_active AS (",  "  SELECT DISTINCT pid, ym AS activity_month FROM success_txns",  "),",  "m1 AS (",  "  SELECT",  "    f.cohort_month,",  "    COUNT(DISTINCT f.pid) AS m1_active",  "  FROM user_first f",  "  JOIN month_active m ON f.pid = m.pid AND m.activity_month >= f.cohort_month",  "  WHERE DATE_DIFF(m.activity_month, f.cohort_month, MONTH) = 1",  "  GROUP BY f.cohort_month",  ")",  "SELECT",  "  c.cohort_month,",  "  c.cohort_users,",  "  IFNULL(m.m1_active, 0) AS m1_active_users,",  "  ROUND(100 * IFNULL(m.m1_active, 0) / NULLIF(c.cohort_users, 0), 2) AS m1_retention_pct",  "FROM cohorts c",  "LEFT JOIN m1 m ON c.cohort_month = m.cohort_month",  "WHERE c.cohort_month BETWEEN '2025-09-01' AND '2026-04-01'",  "ORDER BY c.cohort_month;",];
const AcquisitionCohortM1ByMonth_SOURCE = AcquisitionCohortM1ByMonth_LINES.join('\n');

const BqDistinctPayerVpaFromTransactions_LINES: string[] = [  "-- Distinct payer_vpa on SUCCESS rows in upi_transactions (transaction fact).",  "-- This counts distinct VPAs observed as PAYER in at least one SUCCESS txn \u2014 not \u201cVPA registered\u201d, not user_profile_id.",  "-- Use ONLY to reconcile \u201chow many unique paying VPAs touch the fact table\u201d vs other definitions.",  "",  "SELECT COUNT(DISTINCT payer_vpa) AS distinct_payer_vpa_success",  "FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "WHERE status = 'SUCCESS'",  "  AND payer_vpa IS NOT NULL",  "  AND TRIM(payer_vpa) != ''",  "  AND IFNULL(__deleted, 'false') = 'false';",];
const BqDistinctPayerVpaFromTransactions_SOURCE = BqDistinctPayerVpaFromTransactions_LINES.join('\n');

const BqFactTableRowCounts_LINES: string[] = [  "-- Warehouse row counts for FACT / DIM tables (sanity check in BigQuery console).",  "-- \u26a0 These are NOT \u201cVPA addresses created\u201d totals. \u201c6.3M+ users\u201d on the deck = COUNT(*) on upi.users below.",  "-- \u26a0 \u201cVPA created\u201d (e.g. ~3M registry) must be taken from the VPA registration mart / product table \u2014 not this file.",  "",  "SELECT 'upi_transactions' AS table_id, COUNT(*) AS row_count",  "FROM `bharatpe-analytics-prod.upi.upi_transactions`;",  "",  "SELECT 'users' AS table_id, COUNT(*) AS row_count",  "FROM `bharatpe-analytics-prod.upi.users`;",];
const BqFactTableRowCounts_SOURCE = BqFactTableRowCounts_LINES.join('\n');

const BqVpaRegisteredCountPlaceholder_LINES: string[] = [  "-- Placeholder \u2014 \u201ctotal VPA created\u201d (~3M, etc.)",  "-- \u26a0\ufe0f The `upi` dataset INFORMATION_SCHEMA scan did not list a dedicated VPA registration table name.",  "-- Point this query at the authoritative mart once known (often different dataset),",  "-- or list tables: SELECT table_name FROM `project.dataset.INFORMATION_SCHEMA.TABLES` WHERE LOWER(table_name) LIKE '%vpa%'",  "",  "-- Example skeleton (REPLACE table + column names after discovery):",  "--",  "-- SELECT COUNT(*) AS vpas_registered",  "-- FROM `bharatpe-analytics-prod.<YOUR_DATASET>.<YOUR_VPA_REGISTRY_TABLE>`",  "-- WHERE <active_row_predicate>;",  "",  "SELECT 1 AS replace_with_real_vpa_registry_query;",];
const BqVpaRegisteredCountPlaceholder_SOURCE = BqVpaRegisteredCountPlaceholder_LINES.join('\n');

const CohortVolumeRetention_LINES: string[] = [  "-- UPI volume cohort retention & engagement (bharatpe-analytics-prod.upi)",  "-- Filters: SUCCESS, non-null user_profile_id, __deleted = 'false'",  "-- Adjust date windows; partition on created_at reduces scan cost.",  "",  "WITH success_txns AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    created_at,",  "    DATE(created_at) AS d,",  "    amount",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 MONTH)",  "),",  "user_first AS (",  "  SELECT",  "    pid,",  "    DATE_TRUNC(MIN(d), MONTH) AS cohort_month,",  "    MIN(created_at) AS first_ts",  "  FROM success_txns",  "  GROUP BY pid",  "),",  "first_30d AS (",  "  SELECT s.pid, COUNT(*) AS txns_first_30d",  "  FROM success_txns s",  "  JOIN user_first f ON s.pid = f.pid",  "    AND s.d BETWEEN DATE(f.first_ts) AND DATE_ADD(DATE(f.first_ts), INTERVAL 30 DAY)",  "  GROUP BY s.pid",  "),",  "user_dim AS (",  "  SELECT",  "    f.pid,",  "    f.cohort_month,",  "    CASE",  "      WHEN IFNULL(t30.txns_first_30d, 0) <= 1 THEN 'Light'",  "      WHEN t30.txns_first_30d BETWEEN 2 AND 5 THEN 'Medium'",  "      WHEN t30.txns_first_30d BETWEEN 6 AND 20 THEN 'Heavy'",  "      ELSE 'Power'",  "    END AS volume_segment",  "  FROM user_first f",  "  LEFT JOIN first_30d t30 ON f.pid = t30.pid",  "),",  "monthly_active AS (",  "  SELECT",  "    pid,",  "    DATE_TRUNC(d, MONTH) AS activity_month,",  "    COUNT(*) AS txns,",  "    SUM(ABS(IFNULL(amount, 0))) AS vol",  "  FROM success_txns",  "  GROUP BY pid, DATE_TRUNC(d, MONTH)",  "),",  "retention AS (",  "  SELECT",  "    u.cohort_month,",  "    u.volume_segment,",  "    DATE_DIFF(m.activity_month, u.cohort_month, MONTH) AS period_n,",  "    COUNT(DISTINCT u.pid) AS active_users,",  "    SUM(m.txns) AS total_txns,",  "    SUM(m.vol) AS total_amount",  "  FROM user_dim u",  "  JOIN monthly_active m ON u.pid = m.pid AND m.activity_month >= u.cohort_month",  "  WHERE DATE_DIFF(m.activity_month, u.cohort_month, MONTH) BETWEEN 0 AND 6",  "  GROUP BY 1, 2, 3",  "),",  "cohort_sizes AS (",  "  SELECT cohort_month, volume_segment, COUNT(*) AS cohort_users",  "  FROM user_dim",  "  WHERE cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)",  "  GROUP BY 1, 2",  ")",  "SELECT",  "  r.cohort_month,",  "  r.volume_segment,",  "  r.period_n,",  "  r.active_users,",  "  cs.cohort_users,",  "  SAFE_DIVIDE(r.active_users, cs.cohort_users) AS retention_rate,",  "  SAFE_DIVIDE(r.total_txns, r.active_users) AS avg_txns_per_active_user,",  "  SAFE_DIVIDE(r.total_amount, r.active_users) AS avg_amount_per_active_user",  "FROM retention r",  "JOIN cohort_sizes cs",  "  ON r.cohort_month = cs.cohort_month AND r.volume_segment = cs.volume_segment",  "WHERE r.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)",  "ORDER BY r.cohort_month, r.volume_segment, r.period_n;",];
const CohortVolumeRetention_SOURCE = CohortVolumeRetention_LINES.join('\n');

const RetentionByAvgOutgoingAmount_LINES: string[] = [  "-- Outgoing retention by average outgoing amount in first 30 days after first outgoing SUCCESS.",  "-- Outgoing = subType IS NULL OR subType != 'RECEIVE_EXTERNAL'",  "-- Amount bucket is AVG(ABS(amount)) over those outgoing txns in the 30d window.",  "-- Adjust cohort window filters at the bottom.",  "",  "WITH succ AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    DATE(created_at) AS d,",  "    DATE_TRUNC(DATE(created_at), MONTH) AS ym,",  "    subType AS st,",  "    ABS(SAFE_CAST(amount AS FLOAT64)) AS amt",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)",  "),",  "out_tx AS (",  "  SELECT * FROM succ",  "  WHERE st IS NULL OR st != 'RECEIVE_EXTERNAL'",  "),",  "first_out AS (",  "  SELECT pid, MIN(d) AS fd",  "  FROM out_tx",  "  GROUP BY pid",  "),",  "avg30 AS (",  "  SELECT",  "    o.pid,",  "    AVG(o.amt) AS avg_out_amt",  "  FROM out_tx o",  "  JOIN first_out f ON o.pid = f.pid",  "  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)",  "  GROUP BY o.pid",  "),",  "amt_bucket AS (",  "  SELECT",  "    pid,",  "    CASE",  "      WHEN avg_out_amt < 100 THEN 'avg_lt_100'",  "      WHEN avg_out_amt < 500 THEN 'avg_100_500'",  "      WHEN avg_out_amt < 2000 THEN 'avg_500_2000'",  "      ELSE 'avg_ge_2000'",  "    END AS amt_seg",  "  FROM avg30",  "),",  "cohort AS (",  "  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month",  "  FROM first_out f",  "),",  "labeled AS (",  "  SELECT c.pid, c.cohort_month, a.amt_seg",  "  FROM cohort c",  "  JOIN amt_bucket a ON c.pid = a.pid",  "  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)",  "    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)",  "),",  "cohort_sizes AS (",  "  SELECT cohort_month, amt_seg, COUNT(*) AS cohort_users",  "  FROM labeled",  "  GROUP BY 1, 2",  "),",  "month_activity AS (",  "  SELECT DISTINCT pid, ym AS activity_month",  "  FROM out_tx",  "),",  "ret AS (",  "  SELECT",  "    l.cohort_month,",  "    l.amt_seg,",  "    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,",  "    COUNT(DISTINCT l.pid) AS active_users",  "  FROM labeled l",  "  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month",  "  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 2",  "  GROUP BY 1, 2, 3",  ")",  "SELECT",  "  r.cohort_month,",  "  r.amt_seg,",  "  r.period_n,",  "  r.active_users,",  "  cs.cohort_users,",  "  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct",  "FROM ret r",  "JOIN cohort_sizes cs",  "  ON r.cohort_month = cs.cohort_month AND r.amt_seg = cs.amt_seg",  "ORDER BY r.cohort_month, r.amt_seg, r.period_n;",];
const RetentionByAvgOutgoingAmount_SOURCE = RetentionByAvgOutgoingAmount_LINES.join('\n');

const RetentionByBharatpeQrShare_LINES: string[] = [  "-- Outgoing retention by share of BharatPe QR in first 30d outgoing txns after first outgoing.",  "-- qr_share_30d = COUNT(is_bharatpe_qr=1) / COUNT(outgoing txns) in that window.",  "-- Segments: no_bharatpe_qr (0%), mixed_qr (0<share<0.5), mostly_bharatpe_qr (>=0.5).",  "-- Validate is_bharatpe_qr population and semantics before using for product decisions.",  "",  "WITH succ AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    DATE(created_at) AS d,",  "    DATE_TRUNC(DATE(created_at), MONTH) AS ym,",  "    subType AS st,",  "    IFNULL(is_bharatpe_qr, 0) AS bp_qr",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)",  "),",  "out_tx AS (",  "  SELECT * FROM succ",  "  WHERE st IS NULL OR st != 'RECEIVE_EXTERNAL'",  "),",  "first_out AS (",  "  SELECT pid, MIN(d) AS fd",  "  FROM out_tx",  "  GROUP BY pid",  "),",  "qr_share AS (",  "  SELECT",  "    o.pid,",  "    SAFE_DIVIDE(COUNTIF(o.bp_qr = 1), COUNT(*)) AS qr_share_30d",  "  FROM out_tx o",  "  JOIN first_out f ON o.pid = f.pid",  "  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)",  "  GROUP BY o.pid",  "),",  "qr_bucket AS (",  "  SELECT",  "    pid,",  "    CASE",  "      WHEN qr_share_30d = 0 THEN 'no_bharatpe_qr'",  "      WHEN qr_share_30d < 0.5 THEN 'mixed_qr'",  "      ELSE 'mostly_bharatpe_qr'",  "    END AS qr_seg",  "  FROM qr_share",  "),",  "cohort AS (",  "  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month",  "  FROM first_out f",  "),",  "labeled AS (",  "  SELECT c.pid, c.cohort_month, q.qr_seg",  "  FROM cohort c",  "  JOIN qr_bucket q ON c.pid = q.pid",  "  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)",  "    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)",  "),",  "cohort_sizes AS (",  "  SELECT cohort_month, qr_seg, COUNT(*) AS cohort_users",  "  FROM labeled",  "  GROUP BY 1, 2",  "),",  "month_activity AS (",  "  SELECT DISTINCT pid, ym AS activity_month",  "  FROM out_tx",  "),",  "ret AS (",  "  SELECT",  "    l.cohort_month,",  "    l.qr_seg,",  "    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,",  "    COUNT(DISTINCT l.pid) AS active_users",  "  FROM labeled l",  "  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month",  "  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 2",  "  GROUP BY 1, 2, 3",  ")",  "SELECT",  "  r.cohort_month,",  "  r.qr_seg,",  "  r.period_n,",  "  r.active_users,",  "  cs.cohort_users,",  "  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct",  "FROM ret r",  "JOIN cohort_sizes cs",  "  ON r.cohort_month = cs.cohort_month AND r.qr_seg = cs.qr_seg",  "ORDER BY r.cohort_month, r.qr_seg, r.period_n;",];
const RetentionByBharatpeQrShare_SOURCE = RetentionByBharatpeQrShare_LINES.join('\n');

const RetentionByDominantOutgoingSubtype_LINES: string[] = [  "-- Outgoing retention by dominant outgoing subType in the first 30 days after first outgoing",  "-- SUCCESS. Dominant = max count of outgoing txns by subType in that window (ties broken by st).",  "-- Incoming RECEIVE_EXTERNAL is excluded from outgoing and from this label.",  "",  "WITH succ AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    DATE(created_at) AS d,",  "    DATE_TRUNC(DATE(created_at), MONTH) AS ym,",  "    subType AS st",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)",  "),",  "out_tx AS (",  "  SELECT * FROM succ",  "  WHERE st IS NULL OR st != 'RECEIVE_EXTERNAL'",  "),",  "first_out AS (",  "  SELECT pid, MIN(d) AS fd",  "  FROM out_tx",  "  GROUP BY pid",  "),",  "sub_counts AS (",  "  SELECT",  "    o.pid,",  "    IFNULL(o.st, 'NULL_ST') AS dom_subtype,",  "    COUNT(*) AS n",  "  FROM out_tx o",  "  JOIN first_out f ON o.pid = f.pid",  "  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)",  "  GROUP BY o.pid, o.st",  "),",  "ranked AS (",  "  SELECT",  "    pid,",  "    dom_subtype,",  "    ROW_NUMBER() OVER (PARTITION BY pid ORDER BY n DESC, dom_subtype) AS rn",  "  FROM sub_counts",  "),",  "dominant AS (",  "  SELECT pid, dom_subtype",  "  FROM ranked",  "  WHERE rn = 1",  "),",  "cohort AS (",  "  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month",  "  FROM first_out f",  "),",  "labeled AS (",  "  SELECT c.pid, c.cohort_month, d.dom_subtype",  "  FROM cohort c",  "  JOIN dominant d ON c.pid = d.pid",  "  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)",  "    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)",  "),",  "cohort_sizes AS (",  "  SELECT cohort_month, dom_subtype, COUNT(*) AS cohort_users",  "  FROM labeled",  "  GROUP BY 1, 2",  "),",  "month_activity AS (",  "  SELECT DISTINCT pid, ym AS activity_month",  "  FROM out_tx",  "),",  "ret AS (",  "  SELECT",  "    l.cohort_month,",  "    l.dom_subtype,",  "    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,",  "    COUNT(DISTINCT l.pid) AS active_users",  "  FROM labeled l",  "  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month",  "  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 3",  "  GROUP BY 1, 2, 3",  ")",  "SELECT",  "  r.cohort_month,",  "  r.dom_subtype,",  "  r.period_n,",  "  r.active_users,",  "  cs.cohort_users,",  "  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct",  "FROM ret r",  "JOIN cohort_sizes cs",  "  ON r.cohort_month = cs.cohort_month AND r.dom_subtype = cs.dom_subtype",  "ORDER BY r.cohort_month, r.dom_subtype, r.period_n;",];
const RetentionByDominantOutgoingSubtype_SOURCE = RetentionByDominantOutgoingSubtype_LINES.join('\n');

const RetentionByPayinBucketFirst30d_LINES: string[] = [  "-- Outgoing retention by count of incoming pay-ins (RECEIVE_EXTERNAL) in the first 30 days after",  "-- first outgoing SUCCESS. Buckets: <5, 5\u201320 inclusive, >20. Retention = calendar-month outgoing",  "-- activity (same outgoing definition as other lenses).",  "",  "WITH succ AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    DATE(created_at) AS d,",  "    DATE_TRUNC(DATE(created_at), MONTH) AS ym,",  "    subType AS st",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)",  "),",  "out_tx AS (",  "  SELECT * FROM succ",  "  WHERE st IS NULL OR st != 'RECEIVE_EXTERNAL'",  "),",  "first_out AS (",  "  SELECT pid, MIN(d) AS fd",  "  FROM out_tx",  "  GROUP BY pid",  "),",  "payin_counts AS (",  "  SELECT",  "    f.pid,",  "    COUNTIF(s.st = 'RECEIVE_EXTERNAL'",  "      AND s.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)) AS payin_n",  "  FROM first_out f",  "  JOIN succ s ON s.pid = f.pid",  "  GROUP BY f.pid",  "),",  "payin_bucket AS (",  "  SELECT",  "    pid,",  "    CASE",  "      WHEN payin_n < 5 THEN 'payin_lt_5'",  "      WHEN payin_n BETWEEN 5 AND 20 THEN 'payin_5_to_20'",  "      ELSE 'payin_gt_20'",  "    END AS payin_seg",  "  FROM payin_counts",  "),",  "cohort AS (",  "  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month",  "  FROM first_out f",  "),",  "labeled AS (",  "  SELECT c.pid, c.cohort_month, p.payin_seg",  "  FROM cohort c",  "  JOIN payin_bucket p ON c.pid = p.pid",  "  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)",  "    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)",  "),",  "cohort_sizes AS (",  "  SELECT cohort_month, payin_seg, COUNT(*) AS cohort_users",  "  FROM labeled",  "  GROUP BY 1, 2",  "),",  "month_activity AS (",  "  SELECT DISTINCT pid, ym AS activity_month",  "  FROM out_tx",  "),",  "ret AS (",  "  SELECT",  "    l.cohort_month,",  "    l.payin_seg,",  "    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,",  "    COUNT(DISTINCT l.pid) AS active_users",  "  FROM labeled l",  "  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month",  "  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 3",  "  GROUP BY 1, 2, 3",  ")",  "SELECT",  "  r.cohort_month,",  "  r.payin_seg,",  "  r.period_n,",  "  r.active_users,",  "  cs.cohort_users,",  "  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct",  "FROM ret r",  "JOIN cohort_sizes cs",  "  ON r.cohort_month = cs.cohort_month AND r.payin_seg = cs.payin_seg",  "ORDER BY r.cohort_month, r.payin_seg, r.period_n;",];
const RetentionByPayinBucketFirst30d_SOURCE = RetentionByPayinBucketFirst30d_LINES.join('\n');

const RetentionByTop20Mcc_LINES: string[] = [  "-- Outgoing retention by dominant MCC in first 30 days after first outgoing SUCCESS.",  "-- Global top 20 MCCs = highest outgoing (non-RECEIVE_EXTERNAL) txn count in the scan window.",  "-- Users whose dominant MCC is not in that set \u2192 OTHER.",  "",  "WITH succ AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    DATE(created_at) AS d,",  "    DATE_TRUNC(DATE(created_at), MONTH) AS ym,",  "    subType AS st,",  "    mcc",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 16 MONTH)",  "),",  "out_tx AS (",  "  SELECT * FROM succ",  "  WHERE st IS NULL OR st != 'RECEIVE_EXTERNAL'",  "),",  "first_out AS (",  "  SELECT pid, MIN(d) AS fd",  "  FROM out_tx",  "  GROUP BY pid",  "),",  "top20_mcc AS (",  "  SELECT mcc",  "  FROM (",  "    SELECT mcc, COUNT(*) AS cnt",  "    FROM out_tx",  "    GROUP BY mcc",  "  )",  "  QUALIFY ROW_NUMBER() OVER (ORDER BY cnt DESC) <= 20",  "),",  "mcc_counts AS (",  "  SELECT",  "    o.pid,",  "    o.mcc,",  "    COUNT(*) AS n",  "  FROM out_tx o",  "  JOIN first_out f ON o.pid = f.pid",  "  WHERE o.d BETWEEN f.fd AND DATE_ADD(f.fd, INTERVAL 30 DAY)",  "  GROUP BY o.pid, o.mcc",  "),",  "ranked_mcc AS (",  "  SELECT",  "    pid,",  "    mcc AS dom_mcc,",  "    ROW_NUMBER() OVER (",  "      PARTITION BY pid",  "      ORDER BY n DESC, COALESCE(CAST(mcc AS STRING), '')",  "    ) AS rn",  "  FROM mcc_counts",  "),",  "dominant AS (",  "  SELECT pid, dom_mcc",  "  FROM ranked_mcc",  "  WHERE rn = 1",  "),",  "mcc_seg AS (",  "  SELECT",  "    d.pid,",  "    CASE",  "      WHEN t.mcc IS NOT NULL THEN CAST(d.dom_mcc AS STRING)",  "      ELSE 'OTHER'",  "    END AS mcc_seg",  "  FROM dominant d",  "  LEFT JOIN top20_mcc t ON d.dom_mcc IS NOT DISTINCT FROM t.mcc",  "),",  "cohort AS (",  "  SELECT f.pid, DATE_TRUNC(f.fd, MONTH) AS cohort_month",  "  FROM first_out f",  "),",  "labeled AS (",  "  SELECT c.pid, c.cohort_month, m.mcc_seg",  "  FROM cohort c",  "  JOIN mcc_seg m ON c.pid = m.pid",  "  WHERE c.cohort_month >= DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH), MONTH)",  "    AND c.cohort_month < DATE_TRUNC(CURRENT_DATE(), MONTH)",  "),",  "cohort_sizes AS (",  "  SELECT cohort_month, mcc_seg, COUNT(*) AS cohort_users",  "  FROM labeled",  "  GROUP BY 1, 2",  "),",  "month_activity AS (",  "  SELECT DISTINCT pid, ym AS activity_month",  "  FROM out_tx",  "),",  "ret AS (",  "  SELECT",  "    l.cohort_month,",  "    l.mcc_seg,",  "    DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) AS period_n,",  "    COUNT(DISTINCT l.pid) AS active_users",  "  FROM labeled l",  "  JOIN month_activity ma ON l.pid = ma.pid AND ma.activity_month >= l.cohort_month",  "  WHERE DATE_DIFF(ma.activity_month, l.cohort_month, MONTH) BETWEEN 0 AND 3",  "  GROUP BY 1, 2, 3",  ")",  "SELECT",  "  r.cohort_month,",  "  r.mcc_seg,",  "  r.period_n,",  "  r.active_users,",  "  cs.cohort_users,",  "  ROUND(100 * r.active_users / cs.cohort_users, 2) AS retention_pct",  "FROM ret r",  "JOIN cohort_sizes cs",  "  ON r.cohort_month = cs.cohort_month AND r.mcc_seg = cs.mcc_seg",  "ORDER BY r.cohort_month, r.mcc_seg, r.period_n;",];
const RetentionByTop20Mcc_SOURCE = RetentionByTop20Mcc_LINES.join('\n');

const VolumeCohortPooledSegmentSizes_LINES: string[] = [  "-- Pooled Light / Medium / Heavy / Power cohort USER counts (\u03a3 over cohort months in range).",  "-- Matches `cohort_volume_retention.sql` volume-segment rules:",  "--   Light: 1 SUCCESS in first 30d after each user\u2019s first SUCCESS",  "--   Medium: 2\u20135, Heavy: 6\u201320, Power: 21+",  "-- Change the cohort_month window in the final WHERE to reproduce deck \u201cpool\u201d totals.",  "",  "WITH success_txns AS (",  "  SELECT",  "    user_profile_id AS pid,",  "    created_at,",  "    DATE(created_at) AS d",  "  FROM `bharatpe-analytics-prod.upi.upi_transactions`",  "  WHERE status = 'SUCCESS'",  "    AND user_profile_id IS NOT NULL AND user_profile_id != ''",  "    AND IFNULL(__deleted, 'false') = 'false'",  "    AND DATE(created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 MONTH)",  "),",  "user_first AS (",  "  SELECT",  "    pid,",  "    DATE_TRUNC(MIN(d), MONTH) AS cohort_month,",  "    MIN(created_at) AS first_ts",  "  FROM success_txns",  "  GROUP BY pid",  "),",  "first_30d AS (",  "  SELECT s.pid, COUNT(*) AS txns_first_30d",  "  FROM success_txns s",  "  JOIN user_first f ON s.pid = f.pid",  "    AND s.d BETWEEN DATE(f.first_ts) AND DATE_ADD(DATE(f.first_ts), INTERVAL 30 DAY)",  "  GROUP BY s.pid",  "),",  "user_dim AS (",  "  SELECT",  "    f.pid,",  "    f.cohort_month,",  "    CASE",  "      WHEN IFNULL(t30.txns_first_30d, 0) <= 1 THEN 'Light'",  "      WHEN t30.txns_first_30d BETWEEN 2 AND 5 THEN 'Medium'",  "      WHEN t30.txns_first_30d BETWEEN 6 AND 20 THEN 'Heavy'",  "      ELSE 'Power'",  "    END AS volume_segment",  "  FROM user_first f",  "  LEFT JOIN first_30d t30 ON f.pid = t30.pid",  ")",  "SELECT",  "  volume_segment,",  "  COUNT(*) AS pooled_users_in_window",  "FROM user_dim",  "WHERE cohort_month >= DATE('2025-08-01')",  "  AND cohort_month < DATE('2026-02-01')",  "GROUP BY volume_segment",  "ORDER BY",  "  CASE volume_segment",  "    WHEN 'Light' THEN 1",  "    WHEN 'Medium' THEN 2",  "    WHEN 'Heavy' THEN 3",  "    WHEN 'Power' THEN 4",  "  END;",];
const VolumeCohortPooledSegmentSizes_SOURCE = VolumeCohortPooledSegmentSizes_LINES.join('\n');

/** ─── Meta (deck) ─────────────────────────────────────────────────────────── */
const PRESENTATION_DATE = "May 2026";
const GCP_PROJECT = "bharatpe-analytics-prod";
const BQ_DATASET = "upi";
const MIXPANEL_PROJECT = "bharatpe-consumer";
const MIXPANEL_PROJECT_ID = 3987072;
const MP_BASE = `https://in.mixpanel.com/project/${MIXPANEL_PROJECT_ID}/view/4482865/app/insights`;

const MIXPANEL_REPORTS: Array<{ label: string; hash: string }> = [
  { label: "UPI success → UPI success (weekly retention)", hash: "YQHXsxnUfN29" },
  { label: "UPI success → BBPS bill pay", hash: "d3STiNnpYSdM" },
  { label: "UPI success → voucher payment", hash: "fwVDC635agwo" },
  { label: "UPI success → MF explore landed", hash: "77EaQuqsDPx7" },
  { label: "Failed native UPI flow → later UPI success", hash: "H8WmDzVLYPBS" },
  { label: "Wealth intent events by region (90d table)", hash: "L8shzwVdT4RD" },
];

/** ─── BigQuery warehouse facts (table metadata, May 2026) ─────────────────── */
const BQ_TABLE_FACTS = {
  upiTransactionsRows: "78.2M+",
  upiTransactionsPartition: "created_at (DAY)",
  upiUsersRows: "6.3M+",
  location: "asia-south1",
};

/** Pooled volume cohort sizes (users whose first-success month in poolwindow; used in retention math). */
const BQ_VOLUME_COHORT_SIZES = [
  { segment: "Light", users: 240_494, note: "1 SUCCESS in first 30d after first SUCCESS" },
  { segment: "Medium", users: 293_215, note: "2–5 SUCCESS txns / first 30d" },
  { segment: "Heavy", users: 284_931, note: "6–20 / first 30d" },
  { segment: "Power", users: 178_015, note: "21+ / first 30d" },
];

/** Pool: first SUCCESS month ~Aug 2025–Jan 2026 (9–4 months before analysis). */
const PERIODS = ["M+0", "M+1", "M+2", "M+3", "M+4", "M+5", "M+6"];

const SEGMENT_RETENTION_PCT: Record<string, number[]> = {
  Light: [100, 4.65, 7.86, 7.77, 7.06, 5.73, 4.54],
  Medium: [100, 35.59, 24.34, 21.67, 18.89, 14.16, 10.17],
  Heavy: [100, 76.64, 56.84, 48.59, 42.17, 30.95, 21.78],
  Power: [100, 93.32, 76.38, 65.27, 56.94, 42.41, 29.98],
};

const ACQUISITION_M1 = [
  { month: "2025-09", m1: 43.18 },
  { month: "2025-10", m1: 58.69 },
  { month: "2025-11", m1: 59.55 },
  { month: "2025-12", m1: 57.73 },
  { month: "2026-01", m1: 57.14 },
  { month: "2026-02", m1: 56.23 },
  { month: "2026-03", m1: 55.39 },
];

const ENGAGEMENT_AVG_TXNS: Record<string, number[]> = {
  Light: [1, 3.72, 6.94, 8.29, 9.31, 9.93, 10.56],
  Medium: [2.63, 3.11, 6.03, 6.83, 7.04, 7.41, 7.71],
  Heavy: [7.36, 8.98, 10.48, 10.75, 10, 10.01, 9.79],
  Power: [28.13, 39.67, 33.05, 30.72, 26.98, 25.42, 23.27],
};

/** Mixpanel: weekly curves from report $average row, 90d cohort window. */
const WEEK_LBL9 = ["W+0", "W+1", "W+2", "W+3", "W+4", "W+5", "W+6", "W+7", "W+8"];

const MIXPANEL_ALL_INDIA_WEEKLY_AVG = {
  upiToUpiRates: [0.85, 0.69, 0.62, 0.57, 0.54, 0.5, 0.47, 0.45, 0.43, 0.4, 0.39, 0.37, 0.25],
  upiToBbpsW1: 0.17,
  upiToVoucherW1: 0.01,
  failedFlowToUpiW1: 0.73,
};

const MIXPANEL_REGION_UPI_RETURN: Record<string, number[]> = {
  North: [84, 68, 62, 57, 53, 50, 47, 45, 43],
  South: [85, 70, 64, 59, 55, 51, 49, 47, 45],
  East: [85, 68, 61, 56, 52, 48, 45, 43, 41],
  West: [85, 70, 63, 59, 55, 51, 48, 46, 44],
};

const MIXPANEL_BBPS_REGION_PCT: Array<{ region: string; w1: number; w4: number; w8: number }> = [
  { region: "North", w1: 18, w4: 10, w8: 8 },
  { region: "South", w1: 13, w4: 7, w8: 6 },
  { region: "East", w1: 17, w4: 9, w8: 7 },
  { region: "West", w1: 17, w4: 9, w8: 7 },
];

const MIXPANEL_INTENT_PENETRATION_PCT: Array<{
  region: string;
  goldOt: number;
  mf: number;
  fd: number;
}> = [
  { region: "North", goldOt: 19.97, mf: 6.7, fd: 8.75 },
  { region: "South", goldOt: 21.55, mf: 6.53, fd: 8.15 },
  { region: "East", goldOt: 16.83, mf: 5.77, fd: 7.38 },
  { region: "West", goldOt: 22.29, mf: 7.17, fd: 9.16 },
];

/** 90d unique users, all-India ($overall). */
const MIXPANEL_INTENT_TOTALS_90D = {
  upiSuccess: 442_563,
  goldOnetime: 88_332,
  goldSip: 97_195,
  fdDashboard: 37_276,
  mfExplore: 29_101,
  silverOnetime: 1_288,
  silverSip: 604,
};

/** Regional uniques — same 90d, Mixpanel Insights breakdown (macro-groups on $region). */
const REGION_UNIQUES_90D: Array<{
  macro: string;
  mpLabel: string;
  upi: number;
  goldOt: number;
  goldSip: number;
  fd: number;
  mf: number;
}> = [
  {
    macro: "North",
    mpLabel: "Punjab, Haryana, Delhi, UP, UK, RJ, HP, JK, CH …",
    upi: 168_595,
    goldOt: 33_662,
    goldSip: 37_732,
    fd: 14_755,
    mf: 11_293,
  },
  {
    macro: "West",
    mpLabel: "MH, GJ, MP, GA, CT …",
    upi: 91_228,
    goldOt: 20_331,
    goldSip: 21_919,
    fd: 8_353,
    mf: 6_544,
  },
  {
    macro: "South",
    mpLabel: "TG, KA, TN, KL, AP …",
    upi: 64_205,
    goldOt: 13_838,
    goldSip: 14_129,
    fd: 5_234,
    mf: 4_194,
  },
  {
    macro: "East",
    mpLabel: "WB, BR, OD, JH, AS …",
    upi: 109_007,
    goldOt: 18_348,
    goldSip: 21_193,
    fd: 8_049,
    mf: 6_288,
  },
];

const WEALTH_INTENT_EVENTS = [
  "wealthtech_gold_buy_onetime_landed",
  "wealthtech_gold_buy_SIP_landed",
  "wealthtech_fd_buy_dashboard_landed",
  "wealthtech_mf_explore_new_screen_landed",
  "wealthtech_silver_buy_one_time_landed",
  "wealthtech_silver_buy_sip_landed",
];

const GLOSSARY: Array<[string, string]> = [
  [
    "Cohort month (BQ)",
    "Calendar month of the user’s first SUCCESS transaction meeting row filters.",
  ],
  [
    "Volume cohort",
    "Label from the count of SUCCESS txns in the 30 days after that first success.",
  ],
  ["M+k / W+k", "Months or weeks after cohort / anchor event; retention = active in that period."],
  ["Macro-region (MP)", "Custom buckets on Mixpanel user property $region (IP → state)."],
  ["Penetration", "Unique intent users ÷ unique UPI success users in the same date window (not deduped across intents)."],
];

/** Outgoing-first cohort = month of first outgoing SUCCESS; outgoing excludes RECEIVE_EXTERNAL (pay-in). */
const OUTGOING_LENS_NOTE =
  "Figures below are from BigQuery (`upi.upi_transactions`); illustrative cohort month 2025-09-01 unless noted. Re-run `sql/*.sql` for fresh months.";

const OUTGOING_AMOUNT_SEP_2025 = [
  { bucket: "< ₹100 avg", key: "avg_lt_100", users: 80726, m1: 10.11, m2: 5.66 },
  { bucket: "₹100–₹500 avg", key: "avg_100_500", users: 30952, m1: 38.87, m2: 22.21 },
  { bucket: "₹500–₹2,000 avg", key: "avg_500_2000", users: 15586, m1: 44.69, m2: 27.79 },
  { bucket: "≥ ₹2,000 avg", key: "avg_ge_2000", users: 5156, m1: 40.46, m2: 26.59 },
];

const OUTGOING_PAYIN_SEP_2025 = [
  { seg: "< 5 pay-ins", key: "payin_lt_5", users: 104816, m1: 16.82, m2: 9.9 },
  { seg: "5–20 pay-ins", key: "payin_5_to_20", users: 20402, m1: 41.0, m2: 23.46 },
  { seg: "> 20 pay-ins", key: "payin_gt_20", users: 7202, m1: 45.15, m2: 27.62 },
];

const OUTGOING_SUBTYPE_SEP_2025 = [
  { st: "QR", users: 82095, m1: 27.28, m2: 15.6 },
  { st: "UPI_ID", users: 27777, m1: 17.47, m2: 10.62 },
  { st: "CONTACT", users: 14717, m1: 4.55, m2: 3.99 },
  { st: "INTENT", users: 2870, m1: 24.98, m2: 14.32 },
];

const OUTGOING_MCC_SEP_2025_TOP = [
  { mcc: "0000", label: "Generic / missing bucket (largest)", users: 87482, m1: 20.34 },
  { mcc: "5411", label: "Grocery stores", users: 18010, m1: 30.05 },
  { mcc: "OTHER (not top-20 vol.)", label: "Dominant MCC outside global top 20", users: 8374, m1: 17.2 },
  { mcc: "4814", label: "Telecom", users: 4091, m1: 36.25 },
  { mcc: "5814", label: "Fast food", users: 3909, m1: 22.33 },
];

const OUTGOING_QR_SEP_2025 = [
  { seg: "No BharatPe QR share (0%)", users: 111586, m1: 16.74, m2: 9.5 },
  { seg: "Mixed (0–50% QR share)", users: 14270, m1: 66.49, m2: 41.3 },
  { seg: "Mostly BharatPe QR (≥50%)", users: 6564, m1: 16.36, m2: 9.9 },
];

const OUTGOING_GLOSSARY: Array<[string, string]> = [
  [
    "Outgoing (BQ)",
    "SUCCESS rows where subType is null or not RECEIVE_EXTERNAL; incoming pay-in uses RECEIVE_EXTERNAL only.",
  ],
  [
    "Outgoing cohort month",
    "Month of the user’s first qualifying outgoing SUCCESS (not first pay-in).",
  ],
  [
    "First 30d window",
    "From first outgoing day: label dominant subtype/MCC, pay-in counts, avg amount, QR share — retention is still outgoing-month activity.",
  ],
  [
    "MCC segment",
    "Global top 20 merchant categories by outgoing txn count; users tagged by dominant outgoing MCC in the 30d window, else OTHER.",
  ],
];

const PLAYBOOK_ROWS: Array<[string, string, string, string]> = [
  [
    "North",
    "Largest UPI & wealth raw counts; strongest UPI→BBPS attach.",
    "Wealth penetration vs base mid vs West; optimise yield on scale.",
    "BBPS growth, biller coverage, reminders; cross-sell FD/MF to high-RFM payers.",
  ],
  [
    "West",
    "Highest gold / MF / FD penetration vs UPI base.",
    "Slightly smaller UPI counts than North.",
    "Double down on wealth funnels; mirror best journeys to other regions.",
  ],
  [
    "South",
    "Strong UPI weekly return; solid wealth penetration.",
    "Weakest BBPS W+1 vs other macro-regions.",
    "Diagnose BBPS awareness & use-cases (education, default tab, seasonality).",
  ],
  [
    "East",
    "Material UPI base.",
    "Lowest gold / MF / FD penetration; BBPS mid-pack.",
    "Trust, localisation, partner depth; segment before performance creative tests.",
  ],
];

/** BBPS segment impact assessment — velocity / retention / scale (internal longitudinal analysis, 2024–Mar 2026). */
const BBPS_VELOCITY_PEAK_MARCH_2026: Array<[string, string, string]> = [
  ["BBPS User", "17.78", "2.72×"],
  ["Pure UPI Cohort", "7.62", "1.16×"],
  ["Non-BBPS User (baseline)", "6.54", "1.00×"],
];

const EXEC_SUMMARY_POINTS: Array<{ kicker: string; detail: string }> = [
  {
    kicker: "Outgoing-first BigQuery lenses",
    detail:
      "After first outgoing SUCCESS, ticket size, pay-ins, rail/MCC, and QR share in the next 30 days drive large spreads in monthly outgoing retention — Sep 2025 cohort ~10% M+1 when avg ticket < ₹100 vs ~45% in the ₹500–2k band (Part Ib).",
  },
  {
    kicker: "Volume cohort lever",
    detail:
      "Power ~93% M+1 vs Light ~5% — different lifecycle programmes, not one blanket campaign.",
  },
  {
    kicker: "Light cohort nuance",
    detail:
      "Often higher M+3 than M+1 (skip-a-month then return); win-back timing should not assume steady decay.",
  },
  {
    kicker: "Mixpanel return paths",
    detail:
      "~85% weekly return to upi_transactions_success; ~73% of FAILED native_upi_txns_flow users later succeed — failures are recoverable, not final churn.",
  },
  {
    kicker: "Bill pay attach",
    detail: "~17% W+1 from UPI (all-India); North ~18%, South ~13% — regional playbook differs.",
  },
  {
    kicker: "Wealth intent (landings)",
    detail:
      "West leads penetration vs UPI base; East lags on gold, MF, FD — trust, supply, relevance, not only UI.",
  },
  {
    kicker: "Silver / SIP",
    detail:
      "Landings are two orders of magnitude smaller than gold (90d uniques) — separate experiments and resourcing vs gold.",
  },
  {
    kicker: "BBPS segment",
    detail:
      "~2.7× txns/user vs Non-BBPS (Mar 2026); retention floor ~64–68% vs under 32% Non-BBPS — utility hub vs discretionary UPI.",
  },
];

/** Deck figure → warehouse lens; third column matches `sql/*.sql` on disk. */
const BIGQUERY_METRIC_SOURCE_ROWS: Array<[string, string, string]> = [
  [
    "`78.2M+` upi_transactions (hero shorthand)",
    "`COUNT(*)` on `bharatpe-analytics-prod.upi.upi_transactions` — raw fact rows.",
    "`sql/bq_fact_table_row_counts.sql`",
  ],
  [
    "`6.3M+ users` (hero shorthand)",
    "`COUNT(*)` on `bharatpe-analytics-prod.upi.users` — dim row count, not “VPA created”.",
    "`sql/bq_fact_table_row_counts.sql`",
  ],
  [
    "Product KPI ~3M “VPA created”",
    "Registry / mart definition — unrelated to `users` row count or txn-fact VPAs; wire real table in placeholder.",
    "`sql/bq_vpa_registered_count_placeholder.sql`",
  ],
  [
    "Distinct payer VPAs touching the fact table (sanity / reconciliation)",
    "`COUNT(DISTINCT payer_vpa)` on SUCCESS — who paid as payer at least once, not registration totals.",
    "`sql/bq_distinct_payer_vpa_from_transactions.sql`",
  ],
  [
    "Acquisition cohort M+1 % by calendar month (`ACQUISITION_M1` table)",
    "First QUALIFYING SUCCESS month = cohort_month; active M+1 = ≥1 SUCCESS in next calendar month.",
    "`sql/acquisition_cohort_m1_by_month.sql`",
  ],
  [
    "Pooled volume cohort sizes (`BQ_VOLUME_COHORT_SIZES`; Aug 2025–Jan 2026 window)",
    "Light/Medium/Heavy/Power counts Σ over cohort months; same first-30d rules as retention SQL.",
    "`sql/volume_cohort_pooled_segment_sizes.sql`",
  ],
  [
    "`SEGMENT_RETENTION_PCT` & `ENGAGEMENT_AVG_TXNS` line charts",
    "Per-cohort-month volume segment retention / intensity — rerun for refreshed deck numbers.",
    "`sql/cohort_volume_retention.sql`",
  ],
  [
    "Outgoing-first cohort: Sep 2025 M+1 by avg outgoing amount bucket",
    "Bars/table `OUTGOING_AMOUNT_SEP_2025`; filter cohort month + bucket in query output.",
    "`sql/retention_by_avg_outgoing_amount.sql`",
  ],
  [
    "Outgoing-first: Sep 2025 M+1 by incoming pay-in count bucket (first 30d)",
    "`OUTGOING_PAYIN_SEP_2025`",
    "`sql/retention_by_payin_bucket_first_30d.sql`",
  ],
  [
    "Outgoing-first: Sep 2025 M+1 by dominant outgoing subType",
    "`OUTGOING_SUBTYPE_SEP_2025`",
    "`sql/retention_by_dominant_outgoing_subtype.sql`",
  ],
  [
    "Outgoing-first: Sep 2025 M+1 by dominant MCC (global top 20 vs OTHER)",
    "`OUTGOING_MCC_SEP_2025_TOP`",
    "`sql/retention_by_top20_mcc.sql`",
  ],
  [
    "Outgoing-first: Sep 2025 M+1 by BharatPe QR share bucket",
    "`OUTGOING_QR_SEP_2025`",
    "`sql/retention_by_bharatpe_qr_share.sql`",
  ],
  [
    "BBPS velocity / retention / × lift (Part VII)",
    "Internal longitudinal analysis (2024–Mar 2026); not produced by the SQL appendix below.",
    "—",
  ],
];

const BIGQUERY_SQL_CARD_SPECS: ReadonlyArray<{
  title: string;
  file: string;
  body: string;
}> = [
  {
    title: "Fact sanity: txn rows vs users dim (not “VPA created”)",
    file: "bq_fact_table_row_counts.sql",
    body: BqFactTableRowCounts_SOURCE,
  },
  {
    title: "Distinct payer_vpa on SUCCESS (fact-table lens)",
    file: "bq_distinct_payer_vpa_from_transactions.sql",
    body: BqDistinctPayerVpaFromTransactions_SOURCE,
  },
  {
    title: "Placeholder for authoritative “VPA registered” count",
    file: "bq_vpa_registered_count_placeholder.sql",
    body: BqVpaRegisteredCountPlaceholder_SOURCE,
  },
  {
    title: "Acquisition M+1 % by first-SUCCESS cohort month",
    file: "acquisition_cohort_m1_by_month.sql",
    body: AcquisitionCohortM1ByMonth_SOURCE,
  },
  {
    title: "Pooled Light/Medium/Heavy/Power cohort user counts",
    file: "volume_cohort_pooled_segment_sizes.sql",
    body: VolumeCohortPooledSegmentSizes_SOURCE,
  },
  {
    title: "Volume cohort retention & engagement (segment curves)",
    file: "cohort_volume_retention.sql",
    body: CohortVolumeRetention_SOURCE,
  },
  {
    title: "Outgoing retention by avg outgoing amount (first 30d window)",
    file: "retention_by_avg_outgoing_amount.sql",
    body: RetentionByAvgOutgoingAmount_SOURCE,
  },
  {
    title: "Outgoing retention by pay-in count bucket",
    file: "retention_by_payin_bucket_first_30d.sql",
    body: RetentionByPayinBucketFirst30d_SOURCE,
  },
  {
    title: "Outgoing retention by dominant outgoing subType",
    file: "retention_by_dominant_outgoing_subtype.sql",
    body: RetentionByDominantOutgoingSubtype_SOURCE,
  },
  {
    title: "Outgoing retention by dominant MCC (global top 20)",
    file: "retention_by_top20_mcc.sql",
    body: RetentionByTop20Mcc_SOURCE,
  },
  {
    title: "Outgoing retention by BharatPe QR share bucket",
    file: "retention_by_bharatpe_qr_share.sql",
    body: RetentionByBharatpeQrShare_SOURCE,
  },
];

function SqlSourceCard(props: {
  title: string;
  file: string;
  body: string;
  fg: string;
  fgMuted: string;
  fill: string;
  stroke: string;
}) {
  return (
    <Stack
      style={{
        gap: 10,
        padding: 14,
        borderRadius: 10,
        background: props.fill,
        border: `1px solid ${props.stroke}`,
      }}
    >
      <Text
        style={{
          color: props.fgMuted,
          fontSize: 11,
          fontWeight: 700,
          letterSpacing: "0.06em",
          textTransform: "uppercase",
        }}
        as="span"
      >
        BIGQUERY · <Code>{props.file}</Code>
      </Text>
      <Text style={{ color: props.fg, fontWeight: 600, lineHeight: 1.35 }}>{props.title}</Text>
      <pre
        style={{
          margin: 0,
          padding: 12,
          borderRadius: 8,
          background: props.fill,
          border: `1px solid ${props.stroke}`,
          color: props.fg,
          fontSize: 11,
          lineHeight: 1.45,
          whiteSpace: "pre-wrap",
          wordBreak: "break-word",
          overflowX: "auto",
          maxHeight: 480,
          overflowY: "auto",
          fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
        }}
      >
        {props.body}
      </pre>
      <Text style={{ color: props.fgMuted, fontSize: 12, lineHeight: 1.5 }}>
        Paste into BigQuery console for the same verbatim SQL mirrored under{" "}
        <Code>bigquery-mcp/bharatpe-consumer/sql/</Code>.
      </Text>
    </Stack>
  );
}

export default function UpiCohortRetentionCanvas() {
  const theme = useHostTheme();
  const t = theme.tokens;

  const segmentSeries = Object.entries(SEGMENT_RETENTION_PCT).map(([name, data]) => ({ name, data }));
  const segmentTones = ["neutral" as const, "info" as const, "warning" as const, "success" as const];
  const lineSeriesWithTone = segmentSeries.map((s, i) => ({ ...s, tone: segmentTones[i % segmentTones.length] }));

  const regionUpiSeries = Object.entries(MIXPANEL_REGION_UPI_RETURN).map(([name, data], i) => ({
    name,
    data,
    tone: segmentTones[i % segmentTones.length],
  }));

  const fullRetentionRows = ["Light", "Medium", "Heavy", "Power"].map((seg) => [
    `${seg} (${BQ_VOLUME_COHORT_SIZES.find((b) => b.segment === seg)?.note ?? ""})`,
    ...SEGMENT_RETENTION_PCT[seg].map((v) => `${v.toFixed(2)}%`),
  ]);

  const acqMean =
    ACQUISITION_M1.reduce((s, r) => s + r.m1, 0) / Math.max(1, ACQUISITION_M1.length);

  const totalVolumePoolUsers = BQ_VOLUME_COHORT_SIZES.reduce((s, r) => s + r.users, 0);
  const blendedVolumeWeightedM1 =
    BQ_VOLUME_COHORT_SIZES.reduce((sum, row) => {
      const m1 = SEGMENT_RETENTION_PCT[row.segment][1];
      return sum + row.users * m1;
    }, 0) / Math.max(1, totalVolumePoolUsers);

  const barM1BySegment = {
    categories: ["Light", "Medium", "Heavy", "Power"],
    series: [{ name: "Monthly M+1 retention %", data: [4.65, 35.59, 76.64, 93.32], tone: "info" as const }],
  };

  const barBbpsW1 = {
    categories: MIXPANEL_BBPS_REGION_PCT.map((r) => r.region),
    series: [{ name: "BBPS W+1 % of cohort", data: MIXPANEL_BBPS_REGION_PCT.map((r) => r.w1), tone: "warning" as const }],
  };

  const barGoldPen = {
    categories: MIXPANEL_INTENT_PENETRATION_PCT.map((r) => r.region),
    series: [
      {
        name: "Gold one-time penetration %",
        data: MIXPANEL_INTENT_PENETRATION_PCT.map((r) => r.goldOt),
        tone: "success" as const,
      },
    ],
  };

  const barOutgoingAmountM1 = {
    categories: OUTGOING_AMOUNT_SEP_2025.map((b) => b.bucket),
    series: [
      {
        name: "Outgoing M+1 % (Sep 2025 cohort)",
        data: OUTGOING_AMOUNT_SEP_2025.map((b) => b.m1),
        tone: "info" as const,
      },
    ],
  };

  const barOutgoingPayinM1 = {
    categories: OUTGOING_PAYIN_SEP_2025.map((b) => b.seg),
    series: [
      {
        name: "Outgoing M+1 % (Sep 2025 cohort)",
        data: OUTGOING_PAYIN_SEP_2025.map((b) => b.m1),
        tone: "success" as const,
      },
    ],
  };

  return (
    <Stack style={{ padding: t.spacingLg, gap: t.spacingXl, maxWidth: 1040 }}>
      {/* Title slide */}
      <Card>
        <CardHeader>UPI retention, cross-sell & wealth intent — {PRESENTATION_DATE}</CardHeader>
        <CardBody>
          <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.6 }}>
            Warehouse cohorts (<span style={{ fontWeight: 600 }}>{GCP_PROJECT}</span> ·{" "}
            <span style={{ fontWeight: 600 }}>{BQ_DATASET}</span>) plus behavioural analytics (
            <span style={{ fontWeight: 600 }}>Mixpanel {MIXPANEL_PROJECT}</span> · project id{" "}
            {MIXPANEL_PROJECT_ID}). Single narrative for product, growth, and CRM: who pays again, who pays bills, who
            expresses investment intent, and how that differs by region.
          </Text>
        </CardBody>
      </Card>

      {/* Agenda */}
      <Stack style={{ gap: t.spacingSm }}>
        <H2 style={{ color: t.colorForeground }}>Agenda</H2>
        <Grid columns={2} gap={24}>
          <Stack style={{ gap: 8 }}>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              1. Executive summary
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              2. Data sources & definitions
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              3. BigQuery — pooled baseline, then acquisition & volume cohorts
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              4. BigQuery — engagement intensity by volume cohort
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              4b. BigQuery — outgoing-first cohort (subtype, pay-in, MCC, amount, QR)
            </Text>
          </Stack>
          <Stack style={{ gap: 8 }}>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              5. Mixpanel — all-India benchmarks & 90d scale
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              6. Mixpanel — geography (macro-region breakdowns)
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              7. BBPS segment impact — velocity, retention & scale
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              8. Regional playbook & limitations
            </Text>
            <Text style={{ color: t.colorForegroundSecondary }} as="span">
              9. References, glossary & next steps
            </Text>
          </Stack>
        </Grid>
      </Stack>

      {/* Executive summary */}
      <Callout tone="success" title="Executive summary — what to say in 2 minutes">
        <Stack style={{ gap: 14 }}>
          <Text style={{ color: t.colorForegroundSecondary, fontSize: 11, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase" }}>
            At a glance
          </Text>
          {EXEC_SUMMARY_POINTS.map((row, i) => (
            <Row
              key={i}
              style={{
                alignItems: "flex-start",
                gap: 12,
                padding: "12px 14px",
                background: theme.fill.secondary,
                border: `1px solid ${theme.stroke.secondary}`,
                borderRadius: 8,
              }}
            >
              <div
                style={{
                  width: 4,
                  minHeight: 18,
                  marginTop: 3,
                  flexShrink: 0,
                  background: theme.accent.primary,
                  borderRadius: 2,
                }}
                aria-hidden
              />
              <Text style={{ flex: 1, color: t.colorForeground, lineHeight: 1.55 }}>
                <span style={{ fontWeight: 600 }}>{row.kicker}: </span>
                {row.detail}
              </Text>
            </Row>
          ))}
        </Stack>
      </Callout>

      <Divider />

      {/* Part: definitions */}
      <H2 style={{ color: t.colorForeground }}>Data sources & definitions</H2>
      <Grid columns={2} gap={20}>
        <Card>
          <CardHeader>BigQuery</CardHeader>
          <CardBody>
            <Table
              headers={["Item", "Detail"]}
              rows={[
                ["Project / dataset", `${GCP_PROJECT} · ${BQ_DATASET}`],
                ["Primary fact table", "upi_transactions"],
                ["Users dimension", "users (join profile_id ↔ user_profile_id)"],
                ["Row filters", "status = SUCCESS, user_profile_id set, __deleted = false"],
                ["upi_transactions scale", `${BQ_TABLE_FACTS.upiTransactionsRows} rows; partition ${BQ_TABLE_FACTS.upiTransactionsPartition}`],
                ["users scale", `${BQ_TABLE_FACTS.upiUsersRows} rows`],
                ["Region", BQ_TABLE_FACTS.location],
              ]}
              columnAlign={["left", "left"]}
            />
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Mixpanel</CardHeader>
          <CardBody>
            <Table
              headers={["Item", "Detail"]}
              rows={[
                ["Project", `${MIXPANEL_PROJECT} (${MIXPANEL_PROJECT_ID})`],
                ["Pay & funnel events", "upi_transactions_success, native_upi_txns_flow, BBPS_bill_payment_success, voucher_payment_success"],
                ["Failure filter", "transaction_status = FAILED on native_upi_txns_flow"],
                ["Analysis window", "90 days rolling for most cross-sell & intent tables"],
                ["Geography", "$region (IP → state); custom North/South/East/West buckets"],
                ["Tier cities", "Not available as a standard user property in lookup — use BQ tier join if required"],
              ]}
              columnAlign={["left", "left"]}
            />
          </CardBody>
        </Card>
      </Grid>

      <Callout tone="info" title="How to read this deck">
        <Text style={{ lineHeight: 1.55 }}>
          Pooled / all-India (or warehouse-wide) figures come first; segmented views — volume cohorts and macro-regions —
          come next so benchmarks are anchored before the splits.
        </Text>
      </Callout>

      {/* BigQuery overall */}
      <H2 style={{ color: t.colorForeground }}>Part I — BigQuery: overall (pooled baseline)</H2>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Same SUCCESS / user_filters apply to every slice. The volume pool counts users whose first SUCCESS falls in the
        analysis window; <span style={{ fontWeight: 600 }}>blended M+1</span> weights segment-level M+1 by users in each
        Light→Power bucket (headline “typical” retention before you open the segments).
      </Text>
      <Row wrap gap={16}>
        <Stat label="upi_transactions (fact rows)" value={BQ_TABLE_FACTS.upiTransactionsRows} tone="neutral" />
        <Stat label="users dimension (rows)" value={BQ_TABLE_FACTS.upiUsersRows} tone="neutral" />
        <Stat label="Users in volume pool" value={totalVolumePoolUsers.toLocaleString("en-IN")} tone="info" />
        <Stat
          label="Blended M+1 (volume-weighted)"
          value={`${blendedVolumeWeightedM1.toFixed(1)}%`}
          tone="success"
        />
        <Stat label="Mean acquisition M+1 (monthly cohorts)" value={`${acqMean.toFixed(1)}%`} tone="info" />
      </Row>
      <Table
        headers={["Metric", "Value"]}
        rows={[
          ["Project / dataset", `${GCP_PROJECT} · ${BQ_DATASET}`],
          ["Partition (fact)", BQ_TABLE_FACTS.upiTransactionsPartition],
          ["Users in volume pool (Σ segments)", totalVolumePoolUsers.toLocaleString("en-IN")],
          ["Blended M+1", `${blendedVolumeWeightedM1.toFixed(2)}% (= Σ(users × segment M+1) / Σ users)`],
          ["Mean M+1 by first-success month", `${acqMean.toFixed(2)}% (see acquisition cohort)`],
        ]}
        columnAlign={["left", "left"]}
        striped
      />

      {/* Acquisition — time-based cohort before volume split */}
      <H2 style={{ color: t.colorForeground }}>Part I — BigQuery: acquisition cohort (first SUCCESS month)</H2>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Every user is placed in the month of their first SUCCESS. <span style={{ fontWeight: 600 }}>M+1 retention</span>{" "}
        is the share of that month’s starters who have ≥1 SUCCESS in the following calendar month. Cohort mean M+1 ≈{" "}
        <span style={{ fontWeight: 600 }}>{acqMean.toFixed(1)}%</span>. September 2025 is a clear negative outlier.
      </Text>
      <Table
        headers={["First-success month", "M+1 %", "Δ vs mean (pp)"]}
        rows={ACQUISITION_M1.map((r) => {
          const d = r.m1 - acqMean;
          const sign = d >= 0 ? "+" : "";
          return [r.month, `${r.m1.toFixed(2)}%`, `${sign}${d.toFixed(2)}`];
        })}
        columnAlign={["left", "right", "right"]}
        striped
      />
      <LineChart
        categories={ACQUISITION_M1.map((r) => r.month)}
        series={[{ name: "M+1 %", data: ACQUISITION_M1.map((r) => r.m1), tone: "info" }]}
        height={240}
        valueSuffix="%"
      />
      <Text style={{ color: t.colorForegroundSecondary, fontSize: "0.9em", lineHeight: 1.5 }}>
        Chart series matches the acquisition M+1 table above (same months and percentages).
      </Text>

      {/* Volume cohorts */}
      <H2 style={{ color: t.colorForeground }}>Part I — BigQuery: volume cohorts (Light → Power)</H2>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        After the first qualifying SUCCESS, we count how many further SUCCESS events occur within 30 days. That count
        maps to <span style={{ fontWeight: 600 }}>Light / Medium / Heavy / Power</span>. Retention{" "}
        <span style={{ fontWeight: 600 }}>M+k</span>: share of users in that volume bucket whose cohort month is the
        month of first success, with at least one SUCCESS in the calendar month k months later.
      </Text>
      <Table
        headers={["Segment", "Users in pool", "Rule"]}
        rows={BQ_VOLUME_COHORT_SIZES.map((r) => [r.segment, r.users.toLocaleString("en-IN"), r.note])}
        columnAlign={["left", "right", "left"]}
        striped
      />

      <Row wrap gap={16}>
        <Stat label="Power — M+1" value="93.3%" tone="success" />
        <Stat label="Heavy — M+1" value="76.6%" tone="warning" />
        <Stat label="Medium — M+1" value="35.6%" tone="info" />
        <Stat label="Light — M+1" value="4.7%" tone="neutral" />
      </Row>

      <H3 style={{ color: t.colorForeground }}>M+1 vs segment (ranking)</H3>
      <Table
        headers={["Segment", "Monthly M+1 retention %"]}
        rows={barM1BySegment.categories.map((c, i) => [
          c,
          `${barM1BySegment.series[0].data[i].toFixed(2)}%`,
        ])}
        columnAlign={["left", "right"]}
        striped
      />
      <BarChart
        categories={barM1BySegment.categories}
        series={barM1BySegment.series}
        height={240}
        valueSuffix="%"
      />

      <H3 style={{ color: t.colorForeground }}>Full monthly retention matrix (% of cohort active in M+k)</H3>
      <Table
        headers={["Segment (pool rule)", ...PERIODS]}
        rows={fullRetentionRows}
        columnAlign={["left", ...PERIODS.map(() => "right" as const)]}
        striped
      />

      <LineChart categories={PERIODS} series={lineSeriesWithTone} height={300} fill valueSuffix="%" />
      <Text style={{ color: t.colorForegroundSecondary, fontSize: "0.9em", lineHeight: 1.5 }}>
        Chart series matches the full monthly retention matrix above (one line per segment).
      </Text>

      <H3 style={{ color: t.colorForeground }}>Engagement depth — avg SUCCESS txns among users active in that month</H3>
      <Table
        headers={["Volume cohort", ...PERIODS]}
        rows={Object.keys(ENGAGEMENT_AVG_TXNS).map((seg) => [seg, ...ENGAGEMENT_AVG_TXNS[seg].map(String)])}
        columnAlign={["left", ...PERIODS.map(() => "right" as const)]}
        striped
      />
      <Callout tone="neutral" title="Narrative cue">
        Power users sustain high counts per active month even late in the curve; Light users who return climb toward
        double-digit monthly txns among actives — the segment is “low frequency” not “low value” for those who reactivate.
      </Callout>

      <H2 style={{ color: t.colorForeground }}>Part Ib — BigQuery: outgoing-first cohort (multi-lens)</H2>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        {OUTGOING_LENS_NOTE} Retention in this block is{" "}
        <span style={{ fontWeight: 600 }}>calendar-month outgoing activity</span> (≥1 outgoing SUCCESS in month{" "}
        <span style={{ fontWeight: 600 }}>M+k</span>) after an{" "}
        <span style={{ fontWeight: 600 }}>outgoing</span>-anchored cohort month. Incoming pay-ins use{" "}
        <Code>RECEIVE_EXTERNAL</Code> only; all other subTypes (and null) count as outgoing for activity and dominant-rail
        labelling.
      </Text>

      <Callout tone="info" title="Headline insights (Sep 2025 cohort, warehouse)">
        <Stack style={{ gap: 8 }}>
          <Text style={{ lineHeight: 1.55 }}>
            <span style={{ fontWeight: 600 }}>Ticket size:</span> users with{" "}
            <span style={{ fontWeight: 600 }}>average outgoing &lt; ₹100</span> in the first 30 days after first
            outgoing are a long-tail with <span style={{ fontWeight: 600 }}>~10% M+1</span> outgoing retention vs{" "}
            <span style={{ fontWeight: 600 }}>~39–45%</span> for ₹100+ averages — the ₹500–2k band is strongest in this
            month.
          </Text>
          <Text style={{ lineHeight: 1.55 }}>
            <span style={{ fontWeight: 600 }}>Pay-ins:</span> more <Code>RECEIVE_EXTERNAL</Code> events in that same 30d
            window lines up with higher subsequent <span style={{ fontWeight: 600 }}>outgoing</span> M+1 (
            <span style={{ fontWeight: 600 }}>~45%</span> for &gt;20 pay-ins vs <span style={{ fontWeight: 600 }}>~17%</span>{" "}
            when pay-ins &lt;5).
          </Text>
          <Text style={{ lineHeight: 1.55 }}>
            <span style={{ fontWeight: 600 }}>Rails:</span> dominant <span style={{ fontWeight: 600 }}>QR</span> in the
            first 30d aligns with higher M+1 than <span style={{ fontWeight: 600 }}>UPI ID</span>;{" "}
            <span style={{ fontWeight: 600 }}>CONTACT</span>-dominant users are a thin, infrequent-merchant pattern in
            this slice (very low M+1 — validate use-case, not just UI).
          </Text>
          <Text style={{ lineHeight: 1.55 }}>
            <span style={{ fontWeight: 600 }}>MCC:</span> material spread across dominant categories (e.g. telecom{" "}
            <span style={{ fontWeight: 600 }}>4814 ~36% M+1</span> vs generic <span style={{ fontWeight: 600 }}>0000 ~20%</span>){" "}
            — use for merchant-led programmes once sampled on fresh months.
          </Text>
          <Text style={{ lineHeight: 1.55 }}>
            <span style={{ fontWeight: 600 }}>BharatPe QR flag:</span> segments with some BharatPe QR in the mix show
            very high M+1 in this extract — treat as{" "}
            <span style={{ fontWeight: 600 }}>hypothesis-grade</span> until coverage of <Code>is_bharatpe_qr</Code> is
            audited (flag may be sparse or flow-specific).
          </Text>
        </Stack>
      </Callout>

      <Grid columns={2} gap={16}>
        <Stat label="Sep 2025 — lt ₹100 avg → outgoing M+1" value="10.1%" tone="neutral" />
        <Stat label="Sep 2025 — ₹500–2k avg → outgoing M+1" value="44.7%" tone="success" />
        <Stat label="Sep 2025 — pay-in &gt;20 → outgoing M+1" value="45.2%" tone="success" />
        <Stat label="Sep 2025 — pay-in &lt;5 → outgoing M+1" value="16.8%" tone="neutral" />
      </Grid>

      <H3 style={{ color: t.colorForeground }}>A) Average outgoing ticket (first 30d after first outgoing)</H3>
      <Table
        headers={["Avg amount bucket", "Users (cohort)", "M+1 %", "M+2 %"]}
        rows={OUTGOING_AMOUNT_SEP_2025.map((r) => [
          r.bucket,
          r.users.toLocaleString("en-IN"),
          `${r.m1.toFixed(2)}%`,
          `${r.m2.toFixed(2)}%`,
        ])}
        columnAlign={["left", "right", "right", "right"]}
        striped
      />
      <BarChart
        categories={barOutgoingAmountM1.categories}
        series={barOutgoingAmountM1.series}
        height={220}
        valueSuffix="%"
      />

      <H3 style={{ color: t.colorForeground }}>B) Pay-in volume (RECEIVE_EXTERNAL count, same 30d window)</H3>
      <Table
        headers={["Pay-in bucket", "Users", "M+1 %", "M+2 %"]}
        rows={OUTGOING_PAYIN_SEP_2025.map((r) => [
          r.seg,
          r.users.toLocaleString("en-IN"),
          `${r.m1.toFixed(2)}%`,
          `${r.m2.toFixed(2)}%`,
        ])}
        columnAlign={["left", "right", "right", "right"]}
        striped
      />
      <BarChart
        categories={barOutgoingPayinM1.categories}
        series={barOutgoingPayinM1.series}
        height={220}
        valueSuffix="%"
      />

      <H3 style={{ color: t.colorForeground }}>C) Dominant outgoing subType (first 30d)</H3>
      <Table
        headers={["Dominant subType", "Users", "M+1 %", "M+2 %"]}
        rows={OUTGOING_SUBTYPE_SEP_2025.map((r) => [
          r.st,
          r.users.toLocaleString("en-IN"),
          `${r.m1.toFixed(2)}%`,
          `${r.m2.toFixed(2)}%`,
        ])}
        columnAlign={["left", "right", "right", "right"]}
        striped
      />

      <H3 style={{ color: t.colorForeground }}>D) Dominant MCC vs global top-20 (first 30d)</H3>
      <Table
        headers={["MCC", "Comment", "Users", "M+1 %"]}
        rows={OUTGOING_MCC_SEP_2025_TOP.map((r) => [
          r.mcc,
          r.label,
          r.users.toLocaleString("en-IN"),
          `${r.m1.toFixed(2)}%`,
        ])}
        columnAlign={["left", "left", "right", "right"]}
        striped
      />

      <H3 style={{ color: t.colorForeground }}>E) BharatPe QR share of outgoing txns (first 30d)</H3>
      <Table
        headers={["Segment", "Users", "M+1 %", "M+2 %"]}
        rows={OUTGOING_QR_SEP_2025.map((r) => [
          r.seg,
          r.users.toLocaleString("en-IN"),
          `${r.m1.toFixed(2)}%`,
          `${r.m2.toFixed(2)}%`,
        ])}
        columnAlign={["left", "right", "right", "right"]}
        striped
      />

      <Text style={{ color: t.colorForegroundSecondary, fontSize: "0.9em", lineHeight: 1.5 }}>
        SQL: <Code>sql/retention_by_avg_outgoing_amount.sql</Code>, <Code>sql/retention_by_payin_bucket_first_30d.sql</Code>,{" "}
        <Code>sql/retention_by_dominant_outgoing_subtype.sql</Code>, <Code>sql/retention_by_top20_mcc.sql</Code>,{" "}
        <Code>sql/retention_by_bharatpe_qr_share.sql</Code>.
      </Text>

      <Divider />

      {/* Mixpanel — all-India first */}
      <H2 style={{ color: t.colorForeground }}>Part II — Mixpanel: all-India (overall)</H2>
      <Row wrap gap={16}>
        <Stat label="UPI success → UPI success (W+1)" value="~85%" tone="info" />
        <Stat label="FAILED native flow → later UPI success (W+1)" value="~73%" tone="success" />
        <Stat label="UPI success → BBPS (W+1)" value="~17%" tone="neutral" />
        <Stat label="UPI success → voucher (W+1)" value="~1%" tone="neutral" />
      </Row>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.5 }}>
        Optional 13-point UPI→UPI curve (report $average): first values ≈{" "}
        {MIXPANEL_ALL_INDIA_WEEKLY_AVG.upiToUpiRates.slice(0, 6).map((x) => `${(x * 100).toFixed(0)}%`).join(", ")} …
        (trailing incomplete weeks compress the tail in the UI).
      </Text>

      <H3 style={{ color: t.colorForeground }}>Investment intent — event inventory (landings, not purchases)</H3>
      <Table headers={["Mixpanel event name"]} rows={WEALTH_INTENT_EVENTS.map((e) => [e])} />

      <H3 style={{ color: t.colorForeground }}>90d unique users — all-India totals</H3>
      <Table
        headers={["Event", "Unique users (90d)"]}
        rows={[
          ["upi_transactions_success", MIXPANEL_INTENT_TOTALS_90D.upiSuccess.toLocaleString("en-IN")],
          ["wealthtech_gold_buy_onetime_landed", MIXPANEL_INTENT_TOTALS_90D.goldOnetime.toLocaleString("en-IN")],
          ["wealthtech_gold_buy_SIP_landed", MIXPANEL_INTENT_TOTALS_90D.goldSip.toLocaleString("en-IN")],
          ["wealthtech_fd_buy_dashboard_landed", MIXPANEL_INTENT_TOTALS_90D.fdDashboard.toLocaleString("en-IN")],
          ["wealthtech_mf_explore_new_screen_landed", MIXPANEL_INTENT_TOTALS_90D.mfExplore.toLocaleString("en-IN")],
          ["wealthtech_silver_buy_one_time_landed", MIXPANEL_INTENT_TOTALS_90D.silverOnetime.toLocaleString("en-IN")],
          ["wealthtech_silver_buy_sip_landed", MIXPANEL_INTENT_TOTALS_90D.silverSip.toLocaleString("en-IN")],
        ]}
        columnAlign={["left", "right"]}
        striped
      />

      <H2 style={{ color: t.colorForeground }}>Part II — Mixpanel: by macro-region</H2>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Geography uses custom North / South / East / West buckets on <span style={{ fontWeight: 600 }}>$region</span>{" "}
        (IP → state). Read national benchmarks above first, then compare how attach and intent vary.
      </Text>

      <H3 style={{ color: t.colorForeground }}>UPI return by macro-region (same-event weekly retention, %)</H3>
      <Table
        headers={["Macro-region", ...WEEK_LBL9]}
        rows={Object.entries(MIXPANEL_REGION_UPI_RETURN).map(([reg, vals]) => [
          reg,
          ...vals.map((v) => `${v}%`),
        ])}
        columnAlign={["left", ...WEEK_LBL9.map(() => "right" as const)]}
        striped
      />
      <LineChart categories={WEEK_LBL9} series={regionUpiSeries} height={280} fill valueSuffix="%" />

      <H3 style={{ color: t.colorForeground }}>UPI → BBPS bill pay (by region)</H3>
      <Table
        headers={["Region", "W+1", "W+4", "W+8", "Comment"]}
        rows={[
          ["North", "18%", "10%", "8%", "Strongest bill-pay attach after pay"],
          ["South", "13%", "7%", "6%", "Weakest — investigate despite solid UPI return"],
          ["East", "17%", "9%", "7%", "Mid-pack"],
          ["West", "17%", "9%", "7%", "Mid-pack"],
        ]}
        columnAlign={["left", "right", "right", "right", "left"]}
        striped
      />
      <BarChart categories={barBbpsW1.categories} series={barBbpsW1.series} height={220} valueSuffix="%" />

      <H3 style={{ color: t.colorForeground }}>Wealth: penetration vs regional UPI base (90d)</H3>
      <Table
        headers={["Region", "Gold OT %", "MF %", "FD %"]}
        rows={MIXPANEL_INTENT_PENETRATION_PCT.map((r) => [
          r.region,
          `${r.goldOt.toFixed(2)}`,
          `${r.mf.toFixed(2)}`,
          `${r.fd.toFixed(2)}`,
        ])}
        columnAlign={["left", "right", "right", "right"]}
        striped
      />
      <BarChart categories={barGoldPen.categories} series={barGoldPen.series} height={220} valueSuffix="%" />

      <H3 style={{ color: t.colorForeground }}>Regional scale — raw uniques (90d, same window)</H3>
      <Table
        headers={["Macro-region", "Mixpanel bucket (abbrev.)", "UPI success", "Gold OT", "Gold SIP", "FD dash", "MF explore"]}
        rows={REGION_UNIQUES_90D.map((r) => [
          r.macro,
          r.mpLabel,
          r.upi.toLocaleString("en-IN"),
          r.goldOt.toLocaleString("en-IN"),
          r.goldSip.toLocaleString("en-IN"),
          r.fd.toLocaleString("en-IN"),
          r.mf.toLocaleString("en-IN"),
        ])}
        columnAlign={["left", "left", "right", "right", "right", "right", "right"]}
        striped
      />

      <Callout tone="neutral" title="MF explore — retention curve caveat (speaker note)">
        Do not read weekly <Code>UPI → wealthtech_mf_explore_new_screen_landed</Code> like a pay retention curve —
        intent can appear many weeks after first pay. Pair with funnels, paths, and time-to-event in Mixpanel.
      </Callout>

      <Divider />

      <H2 style={{ color: t.colorForeground }}>Part III — BBPS segment impact assessment</H2>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55, fontWeight: 600 }}>
        The BBPS catalyst for user retention and transactional velocity
      </Text>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55, marginTop: 10 }}>
        Integrating Bharat Bill Payment System (BBPS) is a strategic lever for platform stickiness: utility bill
        payments anchor users in the ecosystem and move them from discretionary transactors toward habitual use. This
        section contrasts BBPS users with Non-BBPS and Pure UPI cohorts on velocity and retention.
      </Text>

      <H3 style={{ color: t.colorForeground }}>1. Strategic overview — segment definitions</H3>
      <Table
        headers={["Segment", "Definition"]}
        rows={[
          [
            "BBPS users",
            "Active users paying utility / biller flows integrated via the BBPS framework.",
          ],
          [
            "Non-BBPS users",
            "Active platform users who have not used the BBPS module (mixed services).",
          ],
          [
            "Pure UPI cohort",
            "Control group: activity limited to UPI transactions — baseline for incremental value of biller integration.",
          ],
        ]}
        columnAlign={["left", "left"]}
        striped
      />
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Segmentation shows a clear trajectory: recurring utility payments accelerate transactional velocity versus
        non-biller baselines.
      </Text>

      <H3 style={{ color: t.colorForeground }}>2. Transactional velocity (txns per user)</H3>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        <span style={{ fontWeight: 600 }}>Transactional velocity</span> — average transactions per user (
        <Code>txns_per_user</Code>) — signals “top-of-wallet” depth. Longitudinal data (2025–Q1 2026): Non-BBPS users
        ranged ~6.39–7.08 txns/user (Nov 2025–Feb 2026); the BBPS segment ran at ~17.75–18.41 in the same window — a
        material engagement gap, not a marginal bump.
      </Text>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        <span style={{ fontWeight: 600 }}>The BBPS velocity multiplier (peak — March 2026)</span>
      </Text>
      <Table
        headers={["Segment", "Peak txns / user (Mar 2026)", "Multiplier vs Non-BBPS"]}
        rows={BBPS_VELOCITY_PEAK_MARCH_2026}
        columnAlign={["left", "right", "right"]}
        striped
      />
      <Callout tone="info" title="Utility hub vs payment tool">
        <Text style={{ lineHeight: 1.55 }}>
          In Mar 2026, Pure UPI averaged ~7.62 txns/user vs ~18.49 for the BBPS cohort — roughly a{" "}
          <span style={{ fontWeight: 600 }}>142% delta</span>. UPI enables easy payments; BBPS turns the app into a{" "}
          <span style={{ fontWeight: 600 }}>high-frequency utility hub</span> by capturing recurring, essential bills —
          graduating users from occasional P2P to utility-dependent power usage. That consistency underpins the retention
          architecture.
        </Text>
      </Callout>

      <H3 style={{ color: t.colorForeground }}>3. Stickiness & retention architecture</H3>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Growth leans on retention efficiency. In the six months ending Mar 2026, the BBPS segment held a retention{" "}
        <span style={{ fontWeight: 600 }}>floor above ~64%</span>, peaking at <span style={{ fontWeight: 600 }}>67.59%</span>{" "}
        (Feb 2026). Non-BBPS struggled to exceed <span style={{ fontWeight: 600 }}>~32%</span> — a stickiness gap of{" "}
        <span style={{ fontWeight: 600 }}>35+ percentage points</span>.
      </Text>
      <Table
        headers={["Insight", "Detail"]}
        rows={[
          [
            "~2× churn differential",
            "BBPS churn ~32.4–35.6%; Non-BBPS churn up to ~70.25% (Nov 2025) — non-biller users far likelier to exit.",
          ],
          [
            "Cohort stability at scale",
            "BBPS actives grew from 59,705 (Oct 2025) to 83,253 (Mar 2026) while retention stayed stable (67.52% → 65.39%) — scalable proposition without typical dilution.",
          ],
        ]}
        columnAlign={["left", "left"]}
        striped
      />
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Managing life services via BBPS builds a digital habit and raises switching costs vs competitors.
      </Text>

      <H3 style={{ color: t.colorForeground }}>4. Growth trajectory & scale evolution</H3>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        From <span style={{ fontWeight: 600 }}>6 active BBPS users (Jun 2024)</span> to{" "}
        <span style={{ fontWeight: 600 }}>103,855 active users (Mar 2026)</span> — exceptional volume scaling. Per-capita
        intensity also rose: ~6.88 txns/user (Jan 2025) to a peak of ~18.41 (Feb 2026) —{" "}
        <span style={{ fontWeight: 600 }}>dual growth</span> in base and density.
      </Text>
      <Callout tone="warning" title="Data note — May 2026">
        <Text style={{ lineHeight: 1.55 }}>
          May 2026 figures (~44k BBPS users, ~5.55 txns/user) are treated as <span style={{ fontWeight: 600 }}>provisional</span>{" "}
          (partial month) — not a segment collapse.
        </Text>
      </Callout>

      <H3 style={{ color: t.colorForeground }}>5. Synthesis & strategic recommendations</H3>
      <Table
        headers={["Pillar", "Takeaway"]}
        rows={[
          [
            "Retention dominance",
            "A ~60%+ BBPS retention floor reduces reliance on raw acquisition; prioritise high-LTV utility users.",
          ],
          [
            "Transaction intensity",
            "Shift from occasional UPI to mandatory recurring bills powers the move to “power user” behaviour.",
          ],
          [
            "Cross-segment superiority",
            "BBPS consistently beats Pure UPI — biller integration differentiates payment tool vs primary financial utility.",
          ],
          [
            "Strategic imperative",
            "Migrate Pure UPI and Non-BBPS users into the biller ecosystem to capture upside in retention and density.",
          ],
        ]}
        columnAlign={["left", "left"]}
      />
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Empirical summary: <span style={{ fontWeight: 600 }}>~2×</span> retention lift and{" "}
        <span style={{ fontWeight: 600 }}>~2.7×</span> transaction frequency vs Non-BBPS baseline — BBPS is a primary
        catalyst for long-term loyalty; resource allocation should reflect migration into bill pay.
      </Text>

      <Divider />

      <H2 style={{ color: t.colorForeground }}>Part IV — Synthesis: regional playbook</H2>
      <Table
        headers={["Region", "Strength", "Risk / gap", "Priority moves"]}
        rows={PLAYBOOK_ROWS}
        columnAlign={["left", "left", "left", "left"]}
      />

      <H3 style={{ color: t.colorForeground }}>Limitations & caveats</H3>
      <Stack style={{ gap: 6 }}>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          • BQ vs MP timings differ — do not expect point-identical user counts across systems.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          • Mixpanel geography is IP-derived state; VPNs and travel distort $region.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          • Intent landings are not conversions; downstream funnel needed for revenue.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          • Penetration rates double-count users who hit multiple intent events when reading columns side-by-side.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          • POSTPE dominance in BQ users limits client-level story — use other attributes for app variants.
        </Text>
      </Stack>

      <H3 style={{ color: t.colorForeground }}>Suggested next steps</H3>
      <Stack style={{ gap: 6 }}>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          1. Explain Sep 2025 M+1 dip (data quality, onboarding, seasonality).
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          2. South BBPS deep-dive: qualitative + competitive + biller catalogue vs North.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          3. East wealth: trust / education creative test, agent/partner presence, and FD vs MF offer mix.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          4. Tie census city-tier from BigQuery onto Mixpanel distinct_id for tier slides.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          5. Build one Cohort in Mixpanel for “any wealth intent” with OR across the six landings.
        </Text>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          6. Refresh outgoing-first lens outputs monthly; reconcile <Code>is_bharatpe_qr</Code> population before
          product bets.
        </Text>
      </Stack>

      <H3 style={{ color: t.colorForeground }}>Glossary</H3>
      <Table
        headers={["Term", "Meaning"]}
        rows={[...GLOSSARY, ...OUTGOING_GLOSSARY]}
        columnAlign={["left", "left"]}
        striped
      />

      <Divider />

      <H3 style={{ color: t.colorForeground }}>Appendix — BigQuery metric → SQL</H3>
      <Callout tone="warning" title={`“Users” (${BQ_TABLE_FACTS.upiUsersRows}) ≠ “VPA created” (~3M product KPI)`}>
        <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
          The deck headline figure <Code>6.3M+ users</Code> is <Code>COUNT(*)</Code> on <Code>upi.users</Code>{" "}
          (warehouse dim rows). Total VPA created is a registry definition — use the authoritative mart wired in{" "}
          <Code>bq_vpa_registered_count_placeholder.sql</Code>. Distinct payer VPAs from the transaction fact (
          <Code>bq_distinct_payer_vpa_from_transactions.sql</Code>) are a separate reconciliation lens, not comparable
          to either headline without aligning definitions.
        </Text>
      </Callout>
      <Table
        headers={["Deck figure / constant", "What it measures", "Source file (`sql/`)"]}
        rows={BIGQUERY_METRIC_SOURCE_ROWS}
        columnAlign={["left", "left", "left"]}
        striped
      />
      <H3 style={{ color: t.colorForeground }}>Verbatim BigQuery SQL (copy-paste)</H3>
      <Text style={{ color: t.colorForegroundSecondary, lineHeight: 1.55 }}>
        Each block mirrors the repo file of the same name — same audit posture as Mixpanel report links below; open the
        file or paste this SQL in the BigQuery console to reproduce.
      </Text>
      <Stack style={{ gap: t.spacingLg }}>
        {BIGQUERY_SQL_CARD_SPECS.map((spec) => (
          <SqlSourceCard
            key={spec.file}
            title={spec.title}
            file={spec.file}
            body={spec.body}
            fg={t.colorForeground}
            fgMuted={t.colorForegroundSecondary}
            fill={theme.fill.secondary}
            stroke={theme.stroke.secondary}
          />
        ))}
      </Stack>

      <H3 style={{ color: t.colorForeground }}>Mixpanel report links</H3>
      <Stack style={{ gap: t.spacingSm }}>
        {MIXPANEL_REPORTS.map((r) => (
          <Text key={r.hash} style={{ color: t.colorForegroundSecondary }} as="span">
            <Link href={`${MP_BASE}#${r.hash}`}>{r.label}</Link>
          </Text>
        ))}
      </Stack>

      <Text style={{ color: t.colorForegroundSecondary, fontSize: "0.9em" }}>
        Source: <Code>bigquery-mcp/bharatpe-consumer/upi-cohort-retention.canvas.tsx</Code>
        {" · "}
        <Code>upi-cohort-retention.html</Code> (same content). Mirror:{" "}
        <Code>~/.cursor/projects/.../canvases/upi-cohort-retention.canvas.tsx</Code>. SQL lenses under{" "}
        <Code>bigquery-mcp/bharatpe-consumer/sql/</Code>. Refresh figures when re-running warehouse & Mixpanel exports.
      </Text>
    </Stack>
  );
}
