-- Distinct payer_vpa on SUCCESS rows in upi_transactions (transaction fact).
-- This counts distinct VPAs observed as PAYER in at least one SUCCESS txn — not “VPA registered”, not user_profile_id.
-- Use ONLY to reconcile “how many unique paying VPAs touch the fact table” vs other definitions.

SELECT COUNT(DISTINCT payer_vpa) AS distinct_payer_vpa_success
FROM `bharatpe-analytics-prod.upi.upi_transactions`
WHERE status = 'SUCCESS'
  AND payer_vpa IS NOT NULL
  AND TRIM(payer_vpa) != ''
  AND IFNULL(__deleted, 'false') = 'false';
