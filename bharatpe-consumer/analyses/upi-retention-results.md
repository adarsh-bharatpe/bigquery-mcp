# UPI retention — results

**Project:** `bharatpe-analytics-prod` · **Dataset:** `upi`  
**Run date:** 2026-05-20 (BigQuery MCP; lenses **(p)** installed apps, **(q)** UPI Lite added)  
**Queries:** [`../sql/upi-retention-queries.sql`](../sql/upi-retention-queries.sql)  
**Deck SQL modal:** [`sql-sources.json`](sql-sources.json) (keys `6`–`22` → presentation slides 6–22)  
**Schema:** [`../upi-schema-reference.md`](../upi-schema-reference.md)

**Scope:** Retention outcomes use **payout** activity (`subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'`). **(e)** pay-in count; **(f)** exclusive subType rails; **(g)** dominant MCC; **(h)** BharatPe QR; **(i)** Zillion redemption; **(j)** Zillion earn; **(k)** platform; **(l)** first outward status; **(m)** first-5 SUCCESS count; **(n)** linked **bank-account** count; **(o)** linked **account type**; **(p)** installed apps (`consumer_psp.appDetails` × `users.client_reference_id`); **(q)** UPI Lite enabled (`upi_transactions.note`).

---

## Sources & query map

| Lens | Section | Primary table(s) | Deck slide | `sql-sources.json` key |
|------|---------|------------------|------------|------------------------|
| 5.1 | (a) | `upi_transactions` | 6 | `6` |
| 5.2 | (b) | `upi_transactions` | 7 | `7` |
| 5.3 | (c) | `users`, `upi_transactions` | 8 | `8` |
| 5.4 | (d) | `upi_transactions` | 9 | `9` |
| 5.5 | (e) | `upi_transactions` | 10 | `10` |
| 5.6 | (f) | `upi_transactions` | 11 | `11` |
| 5.7 | (g) | `upi_transactions` | 12 | `12` |
| 5.8 | (h) | `upi_transactions` | 13 | `13` |
| 5.9 | (i) | `upi_transactions` | 14 | `14` |
| 5.10 | (j) | `upi_transactions` | 15 | `15` |
| 5.11 | (k) | `upi_transactions` | 16 | `16` |
| 5.12 | (l) | `upi_transactions` | 17 | `17` |
| 5.13 | (m) | `upi_transactions` | 18 | `18` |
| 5.14 | (n) | `users`, `user_bank_accounts`, `upi_transactions` | 19 | `19` |
| 5.15 | (p) | `consumer_psp`, `users`, `upi_transactions` | 20 | `20` |
| 5.16 | (o) | `user_bank_accounts`, `users`, `upi_transactions` | 21 | `21` |
| **5.17** | **(q)** | **`upi_transactions` (`note`)** | **22** | **`22`** |
| **5.18** | — | **Google Play review logs** (qualitative) | **23** | — |
| **5.19** | — | **Play Store verbatim reviews** (qualitative) | **24** | — |

**Standard filters (all payout lenses):** `status = 'SUCCESS'`, `user_profile_id` present, `IFNULL(__deleted,'false') = 'false'`, payout = `subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'`, pool = first payout SUCCESS **Aug 2025–Jan 2026** unless noted.

**Refresh:** run [`../sql/upi-retention-queries.sql`](../sql/upi-retention-queries.sql), update tables below, then re-export [`sql-sources.json`](sql-sources.json) into the HTML deck (`#sql-sources-data`).

---

## (a) M+1 payout transaction retention from first-month payout SUCCESS

### Definition

| Term | Rule |
|------|------|
| **Payout / outward** | `status = 'SUCCESS'` and `subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'` |
| **Cohort month** | Calendar month of the user’s **first** payout SUCCESS |
| **M+1 active** | ≥1 payout SUCCESS in the **next** calendar month |
| **M+1 retention %** | `m1_active_users ÷ cohort_users × 100` |

Cohort window: last 14 complete cohort months (excludes current calendar month).

### Results by cohort month

| Cohort month | Cohort users | M+1 active users | M+1 retention % |
|--------------|-------------:|-----------------:|----------------:|
| 2025-03 | 89,560 | 18,776 | 20.96 |
| 2025-04 | 46,650 | 8,737 | 18.73 |
| 2025-05 | 53,342 | 9,163 | 17.18 |
| 2025-06 | 33,687 | 8,267 | 24.54 |
| 2025-07 | 118,467 | 23,312 | 19.68 |
| 2025-08 | 152,360 | 32,670 | 21.44 |
| 2025-09 | 131,904 | 29,070 | 22.04 |
| 2025-10 | 128,500 | 40,328 | 31.38 |
| 2025-11 | 109,520 | 35,988 | 32.86 |
| 2025-12 | 99,360 | 31,842 | 32.05 |
| 2026-01 | 94,433 | 29,106 | 30.82 |
| 2026-02 | 112,961 | 34,150 | 30.23 |
| 2026-03 | 108,799 | 30,612 | 28.14 |
| 2026-04 | 88,317 | 24,956 | 28.26 |

**Readout:** M+1 payout retention rises from ~17–24% (Mar–Sep 2025) to ~28–33% (Oct 2025 onward). Re-check **2026-04** after May 2026 closes if running mid-month.

---

## (b) Volume cohort retention (Light / Medium / Heavy / Power) — payout only

### Definition

| Term | Rule |
|------|------|
| **Qualifying txn** | Payout SUCCESS: `subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'` + standard row filters |
| **First payout success** | Earliest payout SUCCESS timestamp per `user_profile_id` |
| **30-day volume count** | Number of **payout** SUCCESS rows from `DATE(first_ts)` through `DATE(first_ts) + 30 days` (inclusive) |
| **Volume bucket** | See table below |
| **Cohort month** | Calendar month of **first payout** SUCCESS |
| **Retention M+k** | % of users in bucket (with that cohort month) who have ≥1 **payout** SUCCESS in calendar month `cohort_month + k` |

### Volume buckets

| Segment | Payout SUCCESS count in first 30 days after first payout SUCCESS |
|---------|------------------------------------------------------------------|
| **Light** | 1 |
| **Medium** | 2–5 |
| **Heavy** | 6–20 |
| **Power** | 21+ |

---

### Results — pooled (cohort months 2025-08-01 to 2026-01-31)

Users whose **first payout SUCCESS month** falls in the pool window; retention summed across those cohort months.

#### Cohort sizes (pool)

| Segment | Users in pool |
|---------|--------------:|
| Light | 286,756 |
| Medium | 239,635 |
| Heavy | 125,309 |
| Power | 78,103 |
| **Total** | **729,803** |

#### Retention % by segment and period

| Segment | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|----:|----:|----:|----:|----:|----:|----:|
| **Light** | 100.00 | 2.56 | 3.99 | 3.52 | 2.99 | 2.33 | 1.77 |
| **Medium** | 100.00 | 22.92 | 10.34 | 8.18 | 6.65 | 4.77 | 3.41 |
| **Heavy** | 100.00 | 57.68 | 29.36 | 21.80 | 17.15 | 12.21 | 8.40 |
| **Power** | 100.00 | 88.27 | 61.25 | 46.39 | 37.26 | 26.70 | 18.43 |

#### Active users (pool) — same periods

| Segment | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|----:|----:|----:|----:|----:|----:|----:|
| Light | 286,756 | 7,340 | 11,439 | 10,085 | 8,584 | 6,671 | 5,074 |
| Medium | 239,635 | 54,923 | 24,768 | 19,601 | 15,936 | 11,427 | 8,174 |
| Heavy | 125,309 | 72,274 | 36,793 | 27,317 | 21,493 | 15,304 | 10,526 |
| Power | 78,103 | 68,942 | 47,836 | 36,230 | 29,105 | 20,853 | 14,392 |

**Readout (payout-only):**

- **Power** ~88% M+1 vs **Light** ~2.6% M+1 — first-30d payout intensity remains the main retention driver.
- **Light** still shows **M+2 slightly above M+1** (~4.0% vs ~2.6%); modest skip-a-month return, weaker than the all-SUCCESS version.
- Pool is **~730k** first-payout users (Aug 2025–Jan 2026) vs ~999k when pay-ins were included in the earlier (incorrect) run.
- For cohort-month × segment detail, run section **(b) BY cohort_month** in [`upi-retention-queries.sql`](../sql/upi-retention-queries.sql).

---

### Results — single cohort month example (2025-09-01)

First **payout** SUCCESS month = Sep 2025 (not pooled).

#### Cohort sizes (Sep 2025)

| Segment | Users |
|---------|------:|
| Light | 58,144 |
| Medium | 45,503 |
| Heavy | 20,200 |
| Power | 10,764 |

#### Retention % (Sep 2025 cohort)

| Segment | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|----:|----:|----:|----:|----:|----:|----:|
| Light | 100.00 | 2.25 | 3.33 | 3.03 | 2.71 | 2.54 | 2.31 |
| Medium | 100.00 | 19.10 | 8.51 | 7.13 | 5.88 | 4.93 | 4.42 |
| Heavy | 100.00 | 52.59 | 26.60 | 19.82 | 15.87 | 13.08 | 11.50 |
| Power | 100.00 | 86.41 | 59.32 | 46.70 | 38.03 | 30.67 | 26.98 |

---

## (c) Payout retention from month of onboarding (`users` × `upi_transactions`)

### Definition

| Term | Rule |
|------|------|
| **Cohort** | `upi.users` row with `profile_id`; **onboarding month** = `DATE_TRUNC(DATE(users.created_at), MONTH)` |
| **Cohort size** | Count of users onboarded that month (`IFNULL(__deleted,'false')='false'`) |
| **Payout activity** | `upi_transactions` payout SUCCESS (`subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'`) |
| **Join** | `users.profile_id` = `upi_transactions.user_profile_id` |
| **M+0** | ≥1 payout SUCCESS in the **same** calendar month as onboarding |
| **M+k** | ≥1 payout SUCCESS in calendar month `onboarding_month + k` months |
| **Retention %** | `active_users ÷ cohort_users × 100` |

Periods reported: **M+0, M+1, M+2, M+3, M+6** (not every month in between).

### Results — retention % by onboarding month

| Onboarding month | Cohort users | M+0 (same mo.) | M+1 | M+2 | M+3 | M+6 |
|------------------|-------------:|---------------:|----:|----:|----:|----:|
| 2025-03 | 298,764 | 26.91 | 7.68 | 3.76 | 1.61 | 1.83 |
| 2025-04 | 145,252 | 26.09 | 6.69 | 3.00 | 2.26 | 2.14 |
| 2025-05 | 174,247 | 26.45 | 5.68 | 3.29 | 2.65 | 2.10 |
| 2025-06 | 112,109 | 25.54 | 9.03 | 4.43 | 3.49 | 2.77 |
| 2025-07 | 313,677 | 34.79 | 9.84 | 4.94 | 3.92 | 2.97 |
| 2025-08 | 347,187 | 38.36 | 11.01 | 5.75 | 4.64 | 3.27 |
| 2025-09 | 286,581 | 38.45 | 11.33 | 6.62 | 5.41 | 3.48 |
| 2025-10 | 302,642 | 35.00 | 15.09 | 9.16 | 7.27 | 4.16 |
| 2025-11 | 255,741 | 32.69 | 14.50 | 9.05 | 6.68 | 3.88 |
| 2025-12 | 249,631 | 30.16 | 13.23 | 7.63 | 6.11 | — |
| 2026-01 | 254,952 | 27.55 | 11.90 | 7.28 | 5.42 | — |
| 2026-02 | 281,793 | 31.67 | 12.96 | 7.41 | 5.29 | — |
| 2026-03 | 286,418 | 29.26 | 11.38 | 6.62 | — | — |
| 2026-04 | 255,950 | 25.32 | 10.18 | — | — | — |

**Completeness (run date 2026-05-25):** “—” = target calendar month not yet complete or no activity month observed yet. Examples: **M+6** needs onboarding_month + 6 months (Dec 2025 → Jun 2026); **M+3** for Mar 2026 needs Jun 2026. Re-run after those months close.

### Active payout users (selected months)

| Onboarding month | M+0 users | M+1 users | M+2 users | M+3 users |
|------------------|----------:|----------:|----------:|----------:|
| 2025-10 | 105,920 | 45,678 | 27,714 | 21,990 |
| 2025-11 | 83,594 | 37,076 | 23,136 | 17,081 |
| 2026-02 | 89,245 | 36,530 | 20,893 | 14,894 |

### Readout

- **~26–38% M+0:** share of onboarded users who pay out in their signup month (activation in onboarding month).
- **Step-up from Oct 2025:** M+1 rises from ~6–11% (H1 2025) to **~12–15%** (Oct–Nov 2025); M+3 reaches **~7%** for Oct 2025 cohort.
- **Onboarding ≠ first payout:** M+0 well below 100% — many users register before first outward payment.
- Compare to **(a)** (first-**payout** month cohort) for payer-centric retention; **(c)** is registration-centric.

---

## (d) Retention lens — average payout TPV bucket (first 30 days)

### Definition

| Term | Rule |
|------|------|
| **Anchor** | First payout SUCCESS per `user_profile_id` |
| **Cohort month** | Calendar month of that first payout |
| **First-30d window** | `[DATE(first_payout), DATE(first_payout) + 30 days]` inclusive |
| **Avg payout TPV bucket** | `AVG(ABS(amount))` over payout SUCCESS txns in that window (per user) |
| **Total TPV (context)** | `SUM(ABS(amount))` in same window — reported as mean across users in pool |
| **Retention M+k** | % with ≥1 payout SUCCESS in calendar month `cohort_month + k` |

### TPV buckets (avg ticket in first 30d)

| Bucket key | Label | Avg payout amount (₹) |
|------------|-------|-------------------------|
| `avg_lt_100` | &lt; ₹100 | [0, 100) |
| `avg_100_500` | ₹100–₹500 | [100, 500) |
| `avg_500_2000` | ₹500–₹2,000 | [500, 2,000) |
| `avg_ge_2000` | ≥ ₹2,000 | [2,000, ∞) |

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (same as (b) pooled).

---

### Results — pooled retention % by bucket (M+0…M+6)

| Avg TPV bucket | Cohort users | Mean avg ₹/txn | Mean 30d TPV ₹ | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|----------------|-------------:|---------------:|---------------:|----:|----:|----:|----:|----:|----:|----:|
| &lt; ₹100 | 378,977 | 24 | 212 | 100 | **13.0** | 7.0 | 5.4 | 4.3 | 3.1 | 2.3 |
| ₹100–₹500 | 197,180 | 234 | 3,432 | 100 | **42.3** | 24.7 | 18.5 | 14.6 | 10.4 | 7.2 |
| ₹500–₹2,000 | 106,014 | 953 | 13,729 | 100 | **48.0** | 30.5 | 24.0 | 19.8 | 14.5 | 9.9 |
| ≥ ₹2,000 | 37,765 | 5,137 | 45,402 | 100 | **44.2** | 29.7 | 24.3 | 20.6 | 14.9 | 9.9 |
| **Total** | **719,936** | — | — | — | — | — | — | — | — | — |

#### Active users (pooled)

| Bucket | M+1 | M+2 | M+3 | M+6 |
|--------|----:|----:|----:|----:|
| &lt; ₹100 | 49,314 | 26,509 | 20,470 | 8,787 |
| ₹100–₹500 | 83,415 | 48,755 | 36,370 | 14,223 |
| ₹500–₹2,000 | 50,870 | 32,287 | 25,486 | 10,540 |
| ≥ ₹2,000 | 16,684 | 11,231 | 9,172 | 3,753 |

**Readout:**

- **M+1 spreads ~13% → ~48%** from lowest to mid-high avg ticket; **₹500–₹2k** peaks (~48% M+1), not the highest ticket bucket.
- **&lt; ₹100 avg** (~53% of pooled first-payout users) drives **~13% M+1** — largest segment, weakest retention.
- **≥ ₹2k** (~5% of users): strong TPV (~₹45k mean 30d sum) with **~44% M+1**, slightly below ₹500–₹2k band.

---

### Results — Sep 2025 first-payout cohort (by bucket)

First payout month = **2025-09-01** (132,684 users across buckets).

| Avg TPV bucket | Cohort users | M+0 | M+1 | M+2 | M+3 | M+6 |
|----------------|-------------:|----:|----:|----:|----:|----:|
| &lt; ₹100 | 80,874 | 100 | **10.1** | 5.7 | 4.6 | 2.8 |
| ₹100–₹500 | 31,020 | 100 | **38.9** | 22.2 | 17.2 | 9.8 |
| ₹500–₹2,000 | 15,621 | 100 | **44.7** | 27.8 | 22.4 | 14.3 |
| ≥ ₹2,000 | 5,169 | 100 | **40.4** | 26.6 | 21.9 | 14.6 |

Aligns with prior deck snapshot (`OUTGOING_AMOUNT_SEP_2025`); small drift vs older export due to refresh date / filters.

---

## (e) Pay-in volume cohort retention (Light / Medium / Heavy / Power) — first 30 days after first payout

### Definition

| Term | Rule |
|------|------|
| **First payout** | Earliest payout SUCCESS per `user_profile_id` (`subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'`) |
| **Pay-in** | `subType = 'RECEIVE_EXTERNAL'` SUCCESS in `[first_payout_day, first_payout_day + 30 days]` |
| **Pay-in bucket** | Count of pay-in SUCCESS rows in that window (see table below) |
| **Cohort month** | Calendar month of **first payout** SUCCESS |
| **Retention M+k** | % with ≥1 **payout** SUCCESS in calendar month `cohort_month + k` |

Extends the legacy three-bucket lens (`retention_by_payin_bucket_first_30d.sql`: &lt;5, 5–20, &gt;20) to four tiers aligned with payout volume naming.

### Pay-in buckets (first 30d after first payout)

| Segment | Pay-in SUCCESS count (`RECEIVE_EXTERNAL`) |
|---------|-------------------------------------------|
| **Light** | 0–4 (&lt; 5) |
| **Medium** | 5–20 |
| **Heavy** | 21–50 |
| **Power** | 51+ |

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (same as (b) pooled / (d)).

---

### Results — pooled retention % by pay-in segment (M+0…M+6)

| Pay-in segment | Cohort users | Mean pay-ins (30d) | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|----------------|-------------:|-------------------:|----:|----:|----:|----:|----:|----:|----:|
| **Light** | 543,651 | 0.54 | 100 | **22.4** | 13.0 | 10.2 | 8.3 | 6.1 | 4.4 |
| **Medium** | 128,950 | 10.2 | 100 | **43.2** | 26.3 | 19.8 | 15.7 | 11.0 | 7.5 |
| **Heavy** | 36,603 | 30.6 | 100 | **47.2** | 29.7 | 22.1 | 17.4 | 12.1 | 8.1 |
| **Power** | 10,732 | 98.1 | 100 | **51.6** | 32.9 | 25.3 | 19.8 | 14.2 | 9.2 |
| **Total** | **719,936** | — | — | — | — | — | — | — | — |

#### Active users (pooled)

| Segment | M+1 | M+2 | M+3 | M+6 |
|---------|----:|----:|----:|----:|
| Light | 121,815 | 70,533 | 55,222 | 23,744 |
| Medium | 55,670 | 33,854 | 25,469 | 9,626 |
| Heavy | 17,261 | 10,860 | 8,087 | 2,951 |
| Power | 5,537 | 3,535 | 2,720 | 982 |

#### Pay-in count distribution (pool; quartiles)

| Segment | Users | p0 | p25 | p50 | p75 | p100 |
|---------|------:|---:|----:|----:|----:|-----:|
| Light | 543,651 | 0 | 0 | 0 | 1 | 4 |
| Medium | 128,950 | 5 | 6 | 9 | 13 | 20 |
| Heavy | 36,603 | 21 | 24 | 29 | 36 | 50 |
| Power | 10,732 | 51 | 59 | 73 | 104 | 1,284 |

**Readout:**

- **M+1 payout retention rises ~22% → ~52%** as first-30d pay-in intensity increases; lift is steep from Light to Medium, then flattens Heavy vs Power.
- **Light** is **~76%** of the pooled first-payout base (543k / 720k) with **~0.5 mean pay-ins** — largest segment, weakest payout retention.
- **Power** is **~1.5%** of users but **~52% M+1** — high inbound funding correlates with sustained payout activity.
- Pool **719,936** users matches **(d)** avg-TPV pool (same first-payout window); comparable to **(b)** payout-count pool (~730k) with different segmentation logic.

---

### Results — Sep 2025 first-payout cohort (by pay-in segment)

First payout month = **2025-09-01** (133,684 users).

| Pay-in segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+6 |
|----------------|-------------:|----:|----:|----:|----:|----:|
| **Light** | 105,019 | 100 | **16.8** | 9.9 | 8.0 | 5.1 |
| **Medium** | 20,441 | 100 | **41.0** | 23.5 | 18.4 | 10.4 |
| **Heavy** | 5,597 | 100 | **43.8** | 26.6 | 20.7 | 12.2 |
| **Power** | 1,627 | 100 | **50.0** | 31.2 | 24.2 | 14.3 |

Aligns with the deck’s three-bucket Sep snapshot (`payin_lt_5` **16.8%**, `payin_5_to_20` **41.0%**, `payin_gt_20` **45.2%** combined); splitting &gt;20 into Heavy + Power shows most lift in the **51+** tier.

---

## (f) Exclusive outgoing subType lens (first 30 days after first payout)

### Definition

| Term | Rule |
|------|------|
| **First payout** | Earliest payout SUCCESS per `user_profile_id` |
| **30d window** | Payout SUCCESS rows from `first_payout_day` through `+30 days` (inclusive) |
| **subType label** | `IFNULL(subType, 'NULL')` on each payout row |
| **Exclusive segment** | Distinct subTypes in the window — see table below |
| **Retention M+k** | % with ≥1 payout SUCCESS in calendar month `cohort_month + k` |

This is **not** the dominant-subType lens (`retention_by_dominant_outgoing_subtype.sql`: max txn count wins). Here, **Only QR** means every payout txn in the window is `QR` and no other subType appears.

### Rail segments (first 30d payout subTypes)

| Segment | Rule |
|---------|------|
| **Only QR** | Exactly one distinct subType, and it is `QR` |
| **Only UPI_ID** | Exactly one distinct subType, and it is `UPI_ID` |
| **Only CONTACT** | Exactly one distinct subType, and it is `CONTACT` |
| **Only INTENT** | Exactly one distinct subType, and it is `INTENT` |
| **Mixture** | Two or more distinct subTypes in the window (any rails) |

Users with **one** subType outside the four rails above (e.g. only `UPI_NUMBER`, only `NULL`) are tagged **Other only** in SQL (~3.9% of pool) and omitted from the main table below.

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (719,936 users).

---

### Results — pooled retention % (five requested segments)

| Rail segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|--------------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **Only QR** | 279,713 | 100 | **15.1** | 8.3 | 6.5 | 5.2 | 3.8 | 2.7 |
| **Only UPI_ID** | 90,990 | 100 | **8.9** | 6.9 | 5.9 | 4.9 | 4.0 | 2.8 |
| **Only CONTACT** | 41,192 | 100 | **2.3** | 2.8 | 2.5 | 2.2 | 1.8 | 1.8 |
| **Only INTENT** | 11,609 | 100 | **13.4** | 10.5 | 8.3 | 6.9 | 4.0 | 2.6 |
| **Mixture** | 268,615 | 100 | **54.3** | 31.7 | 24.0 | 19.3 | 13.8 | 9.5 |

#### Active users (pooled) — M+1 / M+6

| Segment | M+1 | M+6 |
|---------|----:|----:|
| Only QR | 42,084 | 7,612 |
| Only UPI_ID | 8,058 | 2,570 |
| Only CONTACT | 954 | 733 |
| Only INTENT | 1,551 | 302 |
| Mixture | 145,977 | 25,538 |

**Readout:**

- **Mixture** (~37% of pool) has **~54% M+1** — multi-rail first-month behaviour strongly predicts continued payout activity (often QR + UPI_ID + others).
- **Only QR** is the largest single-rail segment (**~39%** of pool) at **~15% M+1** — weaker than **dominant-QR** in the deck (~27% M+1 Sep) because exclusivity selects lighter, single-surface users.
- **Only CONTACT** is **~2.3% M+1** — thin P2P-only pattern; treat as behavioural signal, not a growth lever without context.
- **Only INTENT** sits between QR and UPI_ID on M+1 (**~13%** pooled).

#### Appendix — Other only (not in five-segment table)

| Segment | Users | M+1 | M+6 |
|---------|------:|----:|----:|
| Other only | 27,817 | 6.0% | 2.0% |

---

### Results — Sep 2025 first-payout cohort

| Rail segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+6 |
|--------------|-------------:|----:|----:|----:|----:|----:|
| **Only QR** | 50,049 | 100 | **12.2** | 7.0 | 5.7 | 3.6 |
| **Only UPI_ID** | 22,040 | 100 | **6.4** | 4.7 | 4.4 | 3.1 |
| **Only CONTACT** | 10,313 | 100 | **2.6** | 2.8 | 2.4 | 1.8 |
| **Only INTENT** | 1,496 | 100 | **7.2** | 6.6 | 6.0 | 4.3 |
| **Mixture** | 45,239 | 100 | **47.0** | 26.8 | 20.8 | 12.2 |

Compare to deck **dominant** subType Sep 2025 (same month, different label): QR-dominant **27.3%** M+1 vs **Only QR 12.2%**; mixture users here are **47%** M+1 vs no direct deck row.

---

## (g) Dominant payout MCC lens (global top 20 by txn volume)

### Definition

| Term | Rule |
|------|------|
| **First payout** | Earliest payout SUCCESS per `user_profile_id` |
| **30d window** | Payout SUCCESS rows from `first_payout_day` through `+30 days` (inclusive) |
| **Dominant MCC** | `subType`/MCC with the **highest txn count** in that window per user (ties: lexicographic `mcc`) |
| **Global top 20** | The 20 `mcc` values with highest **payout** SUCCESS row count in the 16-month scan window (not cohort-specific) |
| **Segment label** | Dominant MCC code if in top 20; else **`OTHER`** |
| **Retention M+k** | % with ≥1 payout SUCCESS in calendar month `cohort_month + k` |

Matches [`retention_by_top20_mcc.sql`](../sql/retention_by_top20_mcc.sql) and deck Part Ib “dominant MCC vs global top-20.”

**Global top 20 MCCs (payout txn volume, 16m scan):**  
`0000`, `5411`, `5814`, `5812`, `4814`, `5541`, `5993`, `5912`, `5462`, `7322`, `5451`, `7407`, `5921`, `4900`, `5412`, `5441`, `5732`, `5651`, `5422`, `7622`

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (719,936 users).

---

### Results — pooled retention % by dominant MCC (top 20 + OTHER)

| MCC | Label (ISO summary) | Cohort users | M+1 | M+2 | M+3 | M+6 |
|-----|---------------------|-------------:|----:|----:|----:|----:|
| **0000** | P2P / unclassified | 443,567 | **26.9** | 16.1 | 12.4 | 5.2 |
| **5411** | Grocery / supermarkets | 103,390 | **34.8** | 19.3 | 14.5 | 5.8 |
| **OTHER** | Outside global top 20 | 53,111 | **20.2** | 12.8 | 10.2 | 4.0 |
| **4814** | Telecom | 32,099 | **35.2** | 22.2 | 17.5 | 6.2 |
| **5814** | Fast food | 23,642 | **27.1** | 15.5 | 11.9 | 4.6 |
| **5812** | Restaurants | 15,573 | **25.8** | 14.5 | 10.8 | 4.4 |
| **5541** | Fuel / service stations | 8,563 | **32.8** | 18.7 | 13.6 | 5.4 |
| **5993** | Misc retail (5993) | 7,420 | **23.1** | 13.0 | 9.5 | 4.0 |
| **7322** | Debt / collections (7322) | 4,541 | **34.5** | 24.5 | 19.3 | 6.9 |
| **4900** | Utilities | 3,748 | **28.0** | 18.6 | 14.5 | 6.6 |
| **5912** | Pharmacies | 3,488 | **21.8** | 13.9 | 11.1 | 4.8 |
| **5462** | Bakeries | 3,262 | **21.8** | 12.1 | 9.1 | 4.2 |
| **5451** | Dairy / specialty food | 2,873 | **25.0** | 15.5 | 12.0 | 4.8 |
| **7407** | — | 2,423 | **15.6** | 10.1 | 7.0 | 3.3 |
| **5651** | Family clothing | 2,379 | **19.6** | 11.2 | 9.8 | 4.5 |
| **5732** | Electronics | 2,318 | **14.7** | 11.5 | 9.0 | 3.8 |
| **5921** | Liquor / package stores | 1,627 | **37.7** | 20.7 | 13.6 | 5.1 |
| **5441** | Candy / confectionery | 1,620 | **17.0** | 10.9 | 8.7 | 3.6 |
| **7622** | Appliance repair | 1,517 | **16.9** | 10.3 | 8.6 | 4.2 |
| **5422** | Meat / freezer provisioners | 1,494 | **16.3** | 10.0 | 6.9 | 2.8 |
| **5412** | Convenience / mini-mart | 1,281 | **47.2** | 33.7 | 27.3 | 12.0 |

**Readout:**

- **M+1 spread ~15% → ~47%** across dominant MCCs; **4814 (telecom)** and **5411 (grocery)** are large segments with **~35% M+1**.
- **0000 (P2P)** is **~62%** of the pool (443k users) at **~27% M+1** — default/unclassified merchant bucket; interpret with product context.
- **OTHER** (~7% of users): dominant MCC not in global top 20 → **~20% M+1**.
- **5412** shows the highest M+1 (**~47%**) but **&lt;0.2%** of users — directional only at this size.
- Long-tail MCCs (e.g. **7407**, **5732**) sit **~15% M+1** pooled.

---

### Results — Sep 2025 first-payout cohort (selected MCCs)

| MCC | Label | Cohort users | M+1 | M+3 | M+6 |
|-----|-------|-------------:|----:|----:|----:|
| **0000** | P2P / unclassified | 87,618 | **20.3** | 12.1 | 6.0 |
| **5411** | Grocery | 18,045 | **30.1** | 16.4 | 6.9 |
| **OTHER** | Outside top 20 | 8,394 | **17.2** | 10.1 | 5.4 |
| **4814** | Telecom | 4,107 | **36.3** | 21.9 | 11.7 |
| **5814** | Fast food | 3,918 | **22.4** | 12.9 | 5.7 |

Aligns with deck `OUTGOING_MCC_SEP_2025_TOP` (0000 **20.3%**, 5411 **30.1%**, 4814 **36.3%**, OTHER **17.2%**).

---

## (h) BharatPe QR exclusivity lens (`is_bharatpe_qr`) — first 30d payout txns

### Definition

| Term | Rule |
|------|------|
| **First payout** | Earliest payout SUCCESS per `user_profile_id` |
| **30d window** | Payout SUCCESS rows from `first_payout_day` through `+30 days` (inclusive) |
| **Flag** | `IFNULL(is_bharatpe_qr, 0)` — NULL treated as **non–BharatPe QR** |
| **Only BharatPe QR** | Every payout txn in the window has `is_bharatpe_qr = 1` |
| **Only non-BharatPe QR** | Every payout txn has `is_bharatpe_qr = 0` (incl. NULL) |
| **Mixed** | At least one txn with `= 1` and at least one with `= 0` |
| **Retention M+k** | % with ≥1 payout SUCCESS in calendar month `cohort_month + k` |

Differs from [`retention_by_bharatpe_qr_share.sql`](../sql/retention_by_bharatpe_qr_share.sql), which buckets by **share** (0%, 0–50%, ≥50%). Section **(h)** uses **exclusive** rails (same idea as **(f)** for subType).

**Coverage note (last 90d payout SUCCESS):** ~494k rows with `is_bharatpe_qr = 1` vs ~7.7M payout rows (~6.4%); flag is sparse outside QR-heavy flows — interpret **Only BharatPe QR** as a narrow, flag-positive population.

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (719,936 users).

---

### Results — pooled retention % (three segments)

| QR segment | Cohort users | Mean BP-QR share (30d) | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|------------|-------------:|------------------------:|----:|----:|----:|----:|----:|----:|----:|
| **Only non-BharatPe QR** | 589,891 | 0% | 100 | **21.4** | 12.3 | 9.5 | 7.7 | 5.5 | 3.9 |
| **Mixed** | 109,936 | 20.3% | 100 | **65.9** | 40.8 | 31.1 | 24.9 | 18.1 | 12.6 |
| **Only BharatPe QR** | 20,109 | 100% | 100 | **7.0** | 6.5 | 5.5 | 4.9 | 3.8 | 2.9 |

#### Active users (pooled) — M+1 / M+6

| Segment | M+1 | M+6 |
|---------|----:|----:|
| Only non-BharatPe QR | 126,478 | 22,894 |
| Mixed | 72,393 | 13,833 |
| Only BharatPe QR | 1,412 | 578 |

**Readout:**

- **Mixed** (~15% of pool) shows **~66% M+1** — users who combine BharatPe QR and other payout surfaces in month one retain far more than single-flag users.
- **Only non-BharatPe QR** is **~82%** of users at **~21% M+1** — aligns with deck “0% BharatPe QR share” directionally.
- **Only BharatPe QR** (**~2.8%** of users) is **~7% M+1**, below the deck’s “≥50% share” bucket (~16% M+1) because exclusivity requires **100%** flagged txns, a stricter slice.
- Do not read **Mixed** M+1 as purely “BharatPe QR effect” without coverage audit; many mixed users are multi-rail power payers (see **(f)**).

---

### Results — Sep 2025 first-payout cohort

| QR segment | Cohort users | M+1 | M+2 | M+3 | M+6 |
|------------|-------------:|----:|----:|----:|----:|
| **Only non-BharatPe QR** | 111,780 | **16.7** | 9.5 | 7.7 | 4.7 |
| **Mixed** | 17,233 | **60.1** | 36.8 | 28.8 | 16.8 |
| **Only BharatPe QR** | 3,671 | **6.7** | 6.1 | 5.3 | 3.9 |

Sep **Only non-BharatPe** M+1 **16.7%** matches deck `OUTGOING_QR_SEP_2025` “No BharatPe QR (0%)” **16.74%** (111,586 users — share-bucket definition, similar size). **Mixed** here (**60%** M+1) is share-bucket “0–50%” (**66%**) with a broader mixed-exclusive label.

---

## (i) Zillion coin redemption lens (`reward_amount > 0` on payout txns)

### Definition

| Term | Rule |
|------|------|
| **First payout** | Earliest payout SUCCESS per `user_profile_id` |
| **30d window** | Payout SUCCESS rows from `first_payout_day` through `+30 days` (inclusive) |
| **Redemption proxy** | `SAFE_CAST(reward_amount AS FLOAT64) > 0` on a payout row (Zillion coins redeemed on that txn) |
| **Ever redeemed** | ≥1 payout txn in the window with `reward_amount > 0` |
| **Never redeemed** | No payout txn in the window with `reward_amount > 0` |
| **Retention M+k** | % with ≥1 payout SUCCESS in calendar month `cohort_month + k` |

Labeling uses **first-30d** redemption behaviour (same window as **(e)–(h)**). “Ever” means ever **within that window**, not lifetime across all payout history.

**Coverage (16m payout SUCCESS):** ~393k rows with `reward_amount > 0` (~1.4% of payout txns). Only **~3.0%** of pooled first-payout users redeem in the first 30d.

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (719,936 users).

---

### Results — pooled retention % (two segments)

| Segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **Never redeemed** | 698,150 | 100 | **26.3** | 15.3 | 11.8 | 9.5 | 6.9 | 4.8 |
| **Ever redeemed** | 21,786 | 100 | **78.0** | 53.5 | 41.8 | 34.4 | 24.2 | 16.9 |

#### Active users (pooled) — M+1 / M+6

| Segment | M+1 | M+6 |
|---------|----:|----:|
| Never redeemed | 183,281 | 33,626 |
| Ever redeemed | 17,002 | 3,679 |

**Readout:**

- **Ever redeemed** in first 30d (**~3%** of pool) shows **~78% M+1** vs **~26%** for **never redeemed** — strongest single-factor lift among outward lenses; likely mixes engagement, rewards eligibility, and spend intensity.
- **Never redeemed** is the bulk population; M+1 is in line with overall pooled payout retention for low-intensity users.
- Treat as **observational**: `reward_amount` is sparse and may not capture all Zillion flows; validate product mapping before causal claims.

---

### Results — Sep 2025 first-payout cohort

| Segment | Cohort users | M+1 | M+2 | M+3 | M+6 |
|---------|-------------:|----:|----:|----:|----:|
| **Never redeemed** | 129,954 | **21.0** | 12.2 | 9.7 | 5.9 |
| **Ever redeemed** | 2,730 | **75.6** | 51.1 | 41.9 | 25.9 |

---

## (j) Zillion coin earn lens (`amount > 50`, `type` ≠ `RECEIVE_EXTERNAL`)

### Definition

| Term | Rule |
|------|------|
| **Cohort anchor** | Users with first **payout** SUCCESS (`subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'`) in pool month |
| **30d window** | Calendar days from `first_payout_day` through `+30 days` (inclusive) |
| **Earn event (your spec)** | `status = 'SUCCESS'` AND `SAFE_CAST(amount AS FLOAT64) > 50` AND `type IS DISTINCT FROM 'RECEIVE_EXTERNAL'` |
| **Ever earned** | ≥1 earn-event txn in the window (any direction matching the rule) |
| **Never earned** | No earn-event txn in the window |
| **Retention M+k** | % with ≥1 **payout** SUCCESS in calendar month `cohort_month + k` |

“Ever” = within the **first-30d** window after first payout (same as **(e)–(i)**).

### Warehouse note on `type` vs pay-in

On SUCCESS rows, **`type = 'RECEIVE_EXTERNAL'` never appears** (0 rows in recent data). Pay-ins use `type = 'PAY'` and `subType = 'RECEIVE_EXTERNAL'`. So your **`type` filter does not exclude pay-ins** — large pay-ins (`amount > 50`) count as “earned” under this rule. See [`upi-schema-reference.md`](../upi-schema-reference.md).

For **payout-only** earn (outward), use `subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'` instead; appendix below.

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (719,936 users).

---

### Results — pooled retention % (your `type` rule)

| Segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **Ever earned** | 506,477 | 100 | **37.6** | 22.1 | 16.8 | 13.5 | 9.7 | 6.7 |
| **Never earned** | 213,459 | 100 | **4.7** | 3.3 | 2.9 | 2.5 | 2.0 | 1.6 |

#### Active users (pooled) — M+1

| Segment | M+1 active users |
|---------|-----------------:|
| Ever earned | 190,170 |
| Never earned | 10,113 |

**Readout:**

- **~70%** of first-payout users **ever earn** under the `type` rule (includes pay-in ≥ ₹50 in the 30d window).
- **M+1 payout retention ~38%** (ever) vs **~5%** (never) — wide gap; “never earned” is a low-activity slice (~30% of pool).
- Compare **(i)** redemption (**~3%** ever, **~78%** M+1) vs **(j)** earn (**~70%** ever, **~38%** M+1) — different proxies and populations.

---

### Appendix — payout-only earn (`subType` outward, `amount > 50`)

Same cohort pool; earn = payout SUCCESS only in first 30d:

| Segment | Cohort users | M+1 | M+2 | M+3 | M+6 |
|---------|-------------:|----:|----:|----:|----:|
| **Ever earned (payout only)** | 433,388 | **42.4** | 24.8 | 18.9 | 7.5 |
| **Never earned (payout only)** | 286,548 | **5.8** | 4.0 | 3.4 | 1.7 |

Use this appendix when the product question is **outward spend ≥ ₹50**, not pay-in volume.

---

### Results — Sep 2025 first-payout cohort (`type` rule)

| Segment | Cohort users | M+1 | M+2 | M+3 | M+6 |
|---------|-------------:|----:|----:|----:|----:|
| **Ever earned** | 82,861 | **33.1** | 19.0 | 14.9 | 8.9 |
| **Never earned** | 49,823 | **3.8** | 3.0 | 2.7 | 2.0 |

---

## (k) Outward platform lens (`attributes.platform`: Android / iOS)

### Definition

| Term | Rule |
|------|------|
| **First payout** | Earliest payout SUCCESS per `user_profile_id` |
| **30d window** | Payout SUCCESS rows from `first_payout_day` through `+30 days` (inclusive) |
| **Platform** | `JSON_VALUE(attributes, '$.platform')` — values in data: **`Android`**, **`Ios`** (exact casing) |
| **Only Android** | Every payout txn in the window has `platform = 'Android'` |
| **Only iOS** | Every payout txn has `platform = 'Ios'` |
| **Mixed** | At least one Android and one iOS txn in the window |
| **Retention M+k** | % with ≥1 payout SUCCESS in calendar month `cohort_month + k` |

Users with no `platform` key on any first-30d payout txn (or only other values) → **Unknown / other platform** (~2.8% of pool); omitted from the main table.

**Coverage:** ~99% of first-30d payout txns have a non-null `platform` in `attributes` (pool window).

**Pool window:** first-payout cohort months **2025-08-01 → 2026-01-31** (719,936 users; **699,804** in Android / iOS / Mixed table below).

---

### Results — pooled retention % (Android / iOS / Mixed)

| Platform segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|------------------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **Only Android** | 682,742 | 100 | **26.9** | 15.7 | 12.1 | 9.7 | 6.9 | 4.9 |
| **Only iOS** | 16,310 | 100 | **23.5** | 14.3 | 11.4 | 9.5 | 7.2 | 5.6 |
| **Mixed (Android + iOS)** | 752 | 100 | **72.7** | 46.4 | 37.0 | 30.3 | 20.0 | 15.2 |

#### Active users (pooled) — M+1

| Segment | M+1 |
|---------|----:|
| Only Android | 183,432 |
| Only iOS | 3,827 |
| Mixed | 547 |

**Readout:**

- **Only Android** is **~95%** of tagged users (**683k** / **700k**); M+1 **~27%**, in line with broad pooled payout retention.
- **Only iOS** is **~2.3%** of tagged users with **~23.5%** M+1 — slightly below Android on M+1, similar on M+6 (~5.6% vs ~4.9%).
- **Mixed** is tiny (**752** users) but **~73%** M+1 — multi-platform payers in month one behave like other “mixed rail” super-users (**(f)**, **(h)**).
- **Unknown** segment (**20,132** users, not in table above): **~62%** M+1 — likely missing `platform` in `attributes` correlates with different txn paths; audit before product use.

---

### Results — Sep 2025 first-payout cohort

| Platform segment | Cohort users | M+1 | M+2 | M+3 | M+6 |
|------------------|-------------:|----:|----:|----:|----:|
| **Only Android** | 126,361 | **21.5** | 12.5 | 9.9 | 6.0 |
| **Only iOS** | 3,710 | **17.6** | 9.3 | 8.0 | 6.0 |
| **Mixed** | 132 | **71.2** | 50.8 | 37.9 | 25.8 |

---

## (l) First outward transaction status lens (SUCCESS / FAILED / INITIALIZED)

### Definition

| Term | Rule |
|------|------|
| **Outward / payout row** | `subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'` (same outward definition as other sections) |
| **First outward attempt** | Earliest outward row per `user_profile_id` by `created_at`, `id` (any `status`) |
| **Cohort month** | Calendar month of that **first outward** timestamp |
| **Segment** | `status` on that first row — bucketed below |
| **Retention M+k** | % with ≥1 **payout SUCCESS** in calendar month `cohort_month + k` |

**Unlike (a)–(k):** Cohort is **not** “first payout SUCCESS month.” Users whose first outward try is **FAILED** may have **M+0 &lt; 100%** because M+0 requires a **SUCCESS** in the cohort month, not merely the first attempt.

### Status buckets

| Segment | Warehouse `status` on first outward row |
|---------|------------------------------------------|
| **SUCCESS** | `SUCCESS` |
| **FAILED** | `FAILED` |
| **INITIALIZED** | `INITIALIZED`, `PENDING`, or `AUTH_PENDING` (no literal `INITIALISED` in data; US spelling `INITIALIZED` is used) |

First outward `COLLECT_EXPIRED`, `COLLECT_REJECTED`, etc. → **OTHER** (~11.7k users); see appendix.

**Pool window:** first-outward attempt date **2025-08-01 → 2026-01-31** (**831,689** users total; **819,971** in table below).

---

### Results — pooled retention % (three requested statuses)

| First outward status | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|----------------------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **SUCCESS** | 633,993 | 100 | **28.0** | 16.6 | 12.8 | 10.3 | 7.4 | 5.2 |
| **FAILED** | 185,570 | **37.7** | **13.4** | 7.8 | 6.1 | 4.9 | 3.5 | 2.6 |
| **INITIALIZED** | 408 | **31.4** | **20.8** | 9.1 | 9.3 | 7.1 | 3.7 | 1.0 |

#### Active users (pooled) — M+1

| Segment | M+1 payout SUCCESS |
|---------|-------------------:|
| SUCCESS | 177,465 |
| FAILED | 24,934 |
| INITIALIZED | 85 |

**Readout:**

- **First try SUCCESS** (~76% of pool): M+1 **~28%** — close to **(a)** / first-payout-success cohorts (~22–33% by month).
- **First try FAILED** (~22%): Only **~38%** convert to payout SUCCESS in **M+0**; M+1 **~13%** on the full FAILED-first cohort.
- **INITIALIZED** is **&lt;0.05%** of users (408); high M+0 **~31%** is noisy at this size.
- Compare pool size **~832k** (first outward date window) vs **~720k** in **(b)–(k)** (first **payout SUCCESS** window) — different cohort anchors.

---

### Appendix — OTHER first-outward statuses (pooled)

| Segment | Cohort users | M+1 |
|---------|-------------:|----:|
| OTHER (e.g. COLLECT_EXPIRED) | 11,718 | 7.6% |

---

### Results — Sep 2025 (first outward month = 2025-09-01)

| First outward status | Cohort users | M+1 | M+2 | M+3 | M+6 |
|----------------------|-------------:|----:|----:|----:|----:|
| **SUCCESS** | 116,433 | **22.2** | 13.0 | 10.4 | 6.3 |
| **FAILED** | 35,593 | **11.3** | 6.7 | 5.3 | 3.3 |
| **INITIALIZED** | 12 | **25.0** | — | 8.3 | — |

---

## (m) SUCCESS count in first 5 payout attempts (0 / 1 / 2 / 3 / 4 / 5)

### Definition

| Term | Rule |
|------|------|
| **Payout attempt** | Outward row: `subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'` (any `status`) |
| **First 5 attempts** | Earliest five payout attempts per user (`ORDER BY created_at, id`) |
| **SUCCESS bucket** | Count of rows with `status = 'SUCCESS'` among those five (integer **0–5**) |
| **Eligibility** | User must have **≥5** payout attempts; analysis uses exactly the first five |
| **Cohort month** | Calendar month of **first payout SUCCESS** (same anchor as **(b)–(k)**) |
| **Retention M+k** | % with ≥1 **payout SUCCESS** in calendar month `cohort_month + k` |

**0 / 5:** All five first attempts are non-SUCCESS; user still has first payout SUCCESS in the pool window (succeeds on attempt 6+). **M+0 = 100%** by cohort definition (first SUCCESS month = cohort month).

Users with **&lt;5** lifetime payout attempts are excluded entirely.

**Pool window:** first-payout SUCCESS cohort months **2025-08-01 → 2026-01-31** (**303,955** users with exactly five attempts).

---

### Results — pooled retention % by SUCCESS count (of first 5)

| SUCCESS in first 5 | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|-------------------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **5 / 5** | 183,540 | 100 | **64.0** | 40.6 | 31.3 | 25.3 | 18.2 | 12.8 |
| **4 / 5** | 60,600 | 100 | **57.0** | 35.5 | 27.6 | 22.5 | 16.5 | 11.6 |
| **3 / 5** | 30,221 | 100 | **49.8** | 30.8 | 24.1 | 19.7 | 14.4 | 10.0 |
| **2 / 5** | 16,114 | 100 | **38.8** | 23.8 | 19.0 | 15.7 | 11.5 | 8.3 |
| **1 / 5** | 10,337 | 100 | **24.5** | 15.4 | 12.8 | 10.2 | 7.4 | 5.3 |
| **0 / 5** | 3,143 | 100 | **32.6** | 21.1 | 17.1 | 13.6 | 9.0 | 6.3 |

#### Active users (pooled) — M+1

| SUCCESS in first 5 | M+1 |
|-------------------|----:|
| 5 | 117,374 |
| 4 | 34,538 |
| 3 | 15,057 |
| 2 | 6,258 |
| 1 | 2,529 |
| 0 | 1,025 |

**Readout:**

- **M+1 scales ~25% → ~64%** for buckets **1–5** as early payout success rate rises — strongest monotonic lens alongside **(b)** volume.
- **0 / 5** (**~1%** of eligible pool): **~32.6% M+1** — above **1/5** (**~24.5%**): users who fail five times then convert can still retain moderately once they reach first SUCCESS.
- **5/5** (**~60%** of eligible pool) at **~64% M+1**.

---

### Results — Sep 2025 first-payout cohort

| SUCCESS in first 5 | Cohort users | M+1 | M+2 | M+3 | M+6 |
|-------------------|-------------:|----:|----:|----:|----:|
| **5 / 5** | 28,189 | **58.1** | 36.6 | 29.2 | 17.8 |
| **4 / 5** | 10,516 | **51.3** | 31.9 | 25.6 | 15.8 |
| **3 / 5** | 5,399 | **43.8** | 26.7 | 21.6 | 13.5 |
| **2 / 5** | 3,002 | **33.7** | 19.7 | 16.5 | 10.6 |
| **1 / 5** | 1,983 | **19.0** | 11.9 | 9.8 | 5.9 |
| **0 / 5** | 513 | **25.2** | 17.4 | 15.2 | 8.8 |

---

## (n) Bank-account linkage count (`user_bank_accounts` × `upi_transactions`)

### Definition

| Term | Rule |
|------|------|
| **Cohort anchor** | First **payout SUCCESS** per `user_profile_id` (same as **(b)–(m)**) |
| **Linkage count** | `COUNT(DISTINCT user_bank_accounts.id)` linked to the user by end of **first 30 days** after first payout SUCCESS |
| **Join path** | `upi_transactions.user_profile_id` → `users.profile_id` → `user_bank_accounts.user_id` = `users.id` |
| **Account filter** | `IFNULL(__deleted, 'false') = 'false'` on `users` and `user_bank_accounts`; `DATE(b.created_at) <= first_payout_day + 30` |
| **Linkage segment** | **1** / **2** / **3** / **4+** linked accounts |
| **Retention M+k** | % with ≥1 **payout SUCCESS** in calendar month `cohort_month + k` |

Outward payout rows use `payer_bank_account_id` → `user_bank_accounts.id` when funding account is populated; this lens uses the **dimension table** (accounts linked to the user), not only accounts seen on txn rows.

**Pool window:** first-payout SUCCESS cohort months **2025-08-01 → 2026-01-31** (**719,936** users).

---

### Results — pooled retention % by linked-account count

| Linked accounts (by 30d) | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|--------------------------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **1 account** | 596,426 | 100 | **25.4** | 14.9 | 11.5 | 9.1 | 6.6 | 4.7 |
| **2 accounts** | 89,297 | 100 | **36.9** | 22.1 | 16.9 | 13.8 | 9.9 | 6.9 |
| **3 accounts** | 20,581 | 100 | **44.5** | 28.1 | 21.9 | 18.3 | 13.2 | 9.1 |
| **4+ accounts** | 13,517 | 100 | **50.4** | 33.0 | 26.2 | 22.3 | 15.8 | 11.1 |

#### Active users (pooled) — M+1

| Segment | M+1 |
|---------|----:|
| 1 account | 151,381 |
| 2 accounts | 32,925 |
| 3 accounts | 9,151 |
| 4+ accounts | 6,812 |

**Readout:**

- **M+1 rises ~25% → ~50%** as linked-account count increases — more linked banks correlate with stronger payout retention.
- **~83%** of users have **1** linked account by day 30; **~2%** have **4+**.
- Multi-account users are a smaller but higher-retention slice.

---

### Appendix — 0 linked accounts by day 30 (pooled)

| Segment | Cohort users | M+1 | M+6 |
|---------|-------------:|----:|----:|
| 0 accounts | 115 | 12.2% | 2.6% |

Users with payout SUCCESS in the pool but no `user_bank_accounts` row with `created_at` within 30d of first payout (timing / join edge cases).

---

### Appendix — distinct `payer_bank_account_id` on payout SUCCESS (first 30d)

Txn-only view (does not require account row in `user_bank_accounts` by day 30):

| Distinct payer accounts used (30d) | Users |
|-----------------------------------|------:|
| 1 | 655,849 |
| 2 | 51,682 |
| 3+ | 12,165 |
| 0 (null payer id) | 240 |

---

### Results — Sep 2025 first-payout cohort

| Linked accounts | Cohort users | M+1 | M+2 | M+3 | M+6 |
|-----------------|-------------:|----:|----:|----:|----:|
| **1 account** | 112,722 | **20.0** | 11.6 | 9.3 | 5.6 |
| **2 accounts** | 14,697 | **31.7** | 18.4 | 14.3 | 9.0 |
| **3 accounts** | 3,169 | **37.4** | 23.9 | 19.9 | 11.9 |
| **4+ accounts** | 2,067 | **46.4** | 30.3 | 23.3 | 16.0 |

---

## (o) Linked account type (`user_bank_accounts` × `upi_transactions`)

### Definition

| Term | Rule |
|------|------|
| **Cohort anchor** | First **payout SUCCESS** per `user_profile_id` (same as **(b)–(n)**) |
| **Linked accounts** | Rows in `user_bank_accounts` for the user with `DATE(created_at) <= first_payout_day + 30` |
| **Join path** | `upi_transactions.user_profile_id` → `users.profile_id` → `user_bank_accounts.user_id` = `users.id` |
| **Hygiene** | `IFNULL(__deleted, 'false') = 'false'` on `users` and `user_bank_accounts` |
| **Main segment — dominant type** | Among linked accounts in the 30d window, the `account_type` with the **most** linked rows (tie-break: `account_type` ASC). Buckets: **SAVINGS** / **CURRENT** / **CREDIT** / **CREDITLINE** / **OTHER dominant** / **No linked account (30d)** |
| **Retention M+k** | % with ≥1 **payout SUCCESS** in calendar month `cohort_month + k` |

**Why dominant (not exclusive-only):** Many users link **multiple** `account_type` values in the first 30d (~**31k**, **~4%** of the pool). Exclusive “CREDIT only” is tiny (**11** users); **CREDIT** as **dominant** type captures **~18k** users who linked credit alongside savings/current.

**Pool window:** first-payout SUCCESS cohort months **2025-08-01 → 2026-01-31** (**719,936** users).

---

### Results — pooled retention % by **dominant** linked `account_type`

| Dominant type | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **SAVINGS** | 688,383 | 100 | **27.3** | 16.0 | 12.3 | 9.8 | 7.1 | 5.0 |
| **CREDIT** | 18,271 | 100 | **44.7** | 30.3 | 24.8 | 21.6 | 16.0 | 11.5 |
| **CURRENT** | 12,288 | 100 | **31.4** | 20.4 | 17.1 | 14.4 | 10.8 | 7.2 |
| **CREDITLINE** | 550 | 100 | **74.7** | 71.1 | 66.4 | 60.5 | 18.4 | 2.7 |
| **OTHER dominant** | 329 | 100 | **31.9** | 17.6 | 15.8 | 12.8 | 6.7 | 6.7 |
| **No linked account (30d)** | 115 | 100 | **12.2** | 7.0 | 5.2 | 7.0 | 5.2 | 2.6 |

#### Active users (pooled) — M+1

| Dominant type | M+1 |
|---------------|----:|
| SAVINGS | 187,732 |
| CREDIT | 8,168 |
| CURRENT | 3,853 |
| CREDITLINE | 411 |
| OTHER dominant | 105 |

**Readout:**

- **CREDIT-dominant** users (**~2.5%** of pool) show **~45% M+1** vs **~27%** for **SAVINGS-dominant** — materially higher retention than the savings-majority base.
- **CURRENT-dominant** sits between savings and credit (**~31% M+1**).
- **CREDITLINE-dominant** is a small cohort (**550**); early months look very high (**~75% M+1**) but **M+5/M+6** collapse — treat as directional only given size and right-censoring.
- Dominant type correlates with **(n)** multi-account linkage: mixed-type linkers often land in **CREDIT** or **CURRENT** dominant buckets.

---

### Appendix — **exclusive** single `account_type` in first 30d (pooled)

Users with exactly **one** distinct `account_type` among linked accounts; **Mixed** = 2+ types.

| Segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **SAVINGS only** | 679,559 | 100 | **27.0** | 15.8 | 12.1 | 9.6 | 7.0 | 4.9 |
| **Mixed account types** | 31,068 | 100 | **46.4** | 31.7 | 25.6 | 22.3 | 15.7 | 10.9 |
| **CURRENT only** | 8,937 | 100 | **28.8** | 19.2 | 16.6 | 14.0 | 10.3 | 7.2 |
| **Other type only** | 246 | 100 | **28.5** | 14.2 | 11.8 | 9.4 | 4.5 | 5.7 |

**Mixed** (**~4%** of pool) aligns with **(n)** 2+ linked accounts and retains at **~46% M+1** — similar lift to multi-account segments in **(n)**.

---

### Results — Sep 2025 first-payout cohort (dominant type)

| Dominant type | Cohort users | M+1 | M+2 | M+3 | M+6 |
|---------------|-------------:|----:|----:|----:|----:|
| **SAVINGS** | 128,161 | **21.6** | 12.6 | 10.0 | 6.0 |
| **CREDIT** | 2,366 | **44.3** | 29.0 | 23.5 | 17.8 |
| **CURRENT** | 2,073 | **27.1** | 16.2 | 14.2 | 10.3 |

### Results — Sep 2025 (exclusive single type)

| Segment | Cohort users | M+1 | M+2 | M+3 | M+6 |
|---------|-------------:|----:|----:|----:|----:|
| **SAVINGS only** | 126,949 | **21.4** | 12.4 | 9.9 | 5.9 |
| **Mixed account types** | 4,124 | **43.7** | 29.2 | 23.7 | 16.8 |
| **CURRENT only** | 1,542 | **24.1** | 14.3 | 12.6 | 9.9 |

---

## (p) Installed-app lens (`consumer_psp.appDetails` × `users`)

### Definition

| Term | Rule |
|------|------|
| **PSP snapshot** | Latest `consumer_psp` row per `customerId` (`ORDER BY updatedAt DESC`) with non-empty `appDetails` |
| **Join** | `CAST(upi.users.client_reference_id AS INT64) = consumer_psp.customerId` |
| **Cohort** | First **payout SUCCESS** date **2025-08-01 → 2026-01-31** (same ~720k pool as **(b)–(o)**) |
| **PSP coverage** | **646,496** users with a PSP snapshot (**89.7%** of cohort); **74,417** with **no** matching PSP row |
| **Partition** | `DATE(consumer_psp.createdAt) >= '2024-01-01'` (required on `consumer_psp`) |
| **Retention M+k** | % with ≥1 payout SUCCESS in calendar month `cohort_month + k` |

`appDetails` is a JSON array of installed app **display names** (sometimes package IDs). Analysis uses **display-name** matching unless noted.

**Important:** Retention tables below are for users **with** a PSP snapshot only. Do **not** pool “No install snapshot” users into UPI-count buckets — they lack `appDetails` and would confound M+1 (~43% if mis-mixed vs ~28% PSP cohort average).

### UPI wallet count (distinct **core** brands)

Count **distinct** mapped brands among major UPI / wallet apps (Paytm, PhonePe, GPay, BHIM, CRED, Navi, super.money, MobiKwik, Amazon Pay, WhatsApp, bank wallets, BharatPe, etc.). **Excluded** from the count: lending/BNPL (KreditBee, Moneyview, …), investing (Groww, Upstox, …), Truecaller, and duplicate BharatPe variants (consumer + business → one **bharatpe** brand).

| UPI wallets on device | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|----------------------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **Single UPI app** | 493 | 100 | **12.4** | 6.5 | 6.1 | 3.5 | 3.0 | 1.4 |
| **2–4 UPI apps** | 123,406 | 100 | **21.3** | 11.4 | 8.6 | 6.8 | 4.8 | 3.2 |
| **5+ UPI apps** | 520,559 | 100 | **29.0** | 17.4 | 13.4 | 10.8 | 7.8 | 5.5 |
| *(No core UPI wallet detected)* | *38* | — | — | — | — | — | — | — |

#### Active users (pooled) — M+1

| Segment | M+1 |
|---------|----:|
| Single UPI app | 61 |
| 2–4 UPI apps | 26,335 |
| 5+ UPI apps | 151,131 |

**Readout:** More **competitor UPI wallets** on the device correlates with **higher** payout retention (M+1 **~12% → ~21% → ~29%**). The **single-wallet** slice is small (**493** users) — directional only. Most PSP users (**~81%**) show **5+** distinct core UPI brands (heavy multi-app install lists are common in `appDetails`).

### Lifestyle / commerce app flags (PSP users, non-exclusive)

Binary flags from display-name allowlists (any match in `appDetails`).

| Segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **Has ecommerce app** | 564,207 | 100 | **28.9** | 17.3 | 13.4 | 10.8 | 7.7 | 5.4 |
| **No ecommerce app** | 80,289 | 100 | **17.8** | 8.6 | 6.2 | 4.8 | 3.2 | 2.1 |
| **Has quick-commerce app** | 174,735 | 100 | **36.1** | 23.6 | 18.9 | 15.7 | 11.6 | 8.2 |
| **No quick-commerce app** | 469,761 | 100 | **24.4** | 13.5 | 10.1 | 7.9 | 5.6 | 3.8 |
| **Has travel app** | 232,532 | 100 | **34.4** | 21.9 | 17.3 | 14.2 | 10.4 | 7.4 |
| **No travel app** | 411,964 | 100 | **23.7** | 13.1 | 9.7 | 7.6 | 5.4 | 3.7 |
| **Has food-delivery app** | 140,893 | 100 | **34.6** | 22.4 | 17.7 | 14.8 | 10.9 | 7.7 |
| **No food-delivery app** | 503,603 | 100 | **25.6** | 14.5 | 11.0 | 8.7 | 6.2 | 4.3 |

**Ecommerce allowlist:** Flipkart, Amazon, Myntra, Meesho, Ajio, Nykaa.  
**Quick-commerce:** Blinkit, Zepto, BigBasket, JioMart.  
**Travel:** Uber, Ola, Rapido, MakeMyTrip, Goibibo, IRCTC Rail Connect, Redbus, ixigo, Yatra.  
**Food delivery:** Swiggy, Zomato.

**Readout:**

- **Ecommerce** installed (**~87%** of PSP cohort) vs not: M+1 **~29%** vs **~18%** — ecommerce-heavy devices align with stickier payers (likely confounded with overall app engagement).
- **Quick-commerce** and **food-delivery** show the largest M+1 lift (**~36%** / **~35%** vs **~24–26%** without).
- **Travel** apps: **~34%** M+1 with vs **~24%** without.

### Methodology notes

1. **Latest PSP row** — reflects most recent device scan, not necessarily within 30d of first payout; sensitivity analysis can filter `psp.updatedAt <= first_payout + 30d` (reduces matched users to ~318k).
2. **Do not count package IDs as separate UPI apps** without brand mapping — inflates “5+ UPI” (raw package regex can show **>600k** users in 5+).
3. **Do not treat BNPL / lending / broking apps as UPI competitors** — inflates wallet counts and dilutes retention spread.
4. Users **without** `consumer_psp` match (**~74k**, **~10%**) are omitted from tables above; report separately if needed.

---

## (q) UPI Lite enabled (`upi_transactions.note`)

### Definition

| Term | Rule |
|------|------|
| **Cohort anchor** | First **payout SUCCESS** per `user_profile_id` (same pool as **(b)–(p)**) |
| **UPI Lite enabled** | ≥1 **SUCCESS** row in `upi_transactions` with `UPPER(note) LIKE '%UPI LITE%'` between first payout day and **+30 days** |
| **Not enabled** | No such row in that window |
| **Retention M+k** | % with ≥1 **payout SUCCESS** (`subType IS DISTINCT FROM 'RECEIVE_EXTERNAL'`) in calendar month `cohort_month + k` |

**Signal notes (Aug 2025–Jan 2026 pool):** Most Lite rows are pay-in labelled (`subType = 'RECEIVE_EXTERNAL'`) — e.g. **Setup of UPI LITE**, **Topup UPI LITE**, **UPI LITE Closure**; a smaller share are Lite payments. The flag is an **onboarding / wallet-setup** signal in the first 30d, not payout-rail mix. See [`../upi-schema-reference.md`](../upi-schema-reference.md) § UPI Lite.

**Pool window:** first-payout SUCCESS **2025-08-01 → 2026-01-31** (**720,379** users in run).

**Query:** [`../sql/upi-retention-queries.sql`](../sql/upi-retention-queries.sql) section **(q)** · deck modal [`sql-sources.json`](sql-sources.json) key **`22`** (slide **5.17**).

---

### Results — pooled retention %

| Segment | Cohort users | M+0 | M+1 | M+2 | M+3 | M+4 | M+5 | M+6 |
|---------|-------------:|----:|----:|----:|----:|----:|----:|----:|
| **Not enabled (30d)** | 714,787 | 100 | **27.7** | 16.4 | 12.6 | 10.2 | 7.4 | 5.2 |
| **UPI Lite enabled (30d)** | 5,592 | 100 | **49.6** | 29.3 | 21.5 | 16.9 | 11.7 | 7.4 |

**Readout:**

- **~0.8%** of the pooled cohort enable UPI Lite in the first 30d after first payout, but they retain at **~50% M+1** vs **~28%** for users without a Lite signal — roughly **2×** M+1 lift (directionally similar to other “power user” lenses).
- Lite enablement correlates with **higher pay-in / wallet engagement** (setup/topup notes); treat as a **product nudge** after first payout, not as a mass segment today.

---

## 5.18 Play Store review sentiment (qualitative)

**Source:** Google Play review logs · **period analysed for themes:** Jan 2026–May 2026 (negative / performance subset) · **corpus since:** Jan 2025.

### Volume (since Jan 2025)

| Metric | Count |
|--------|------:|
| Total Play Store reviews | **101,116** |
| Reviews with comments | **4,269** |
| Poor ratings (1–3★) with comments | **1,938** |
| Custom reviews (curated) | **1,800** |

### (a) Keyword sentiment themes — negative reviews

| # | Theme | Keywords | Sentiment |
|---|-------|----------|-----------|
| **1** | **Severe app lag & slowness** | slow, very slow, slow motion hanging, too slow to pay, taking much time | Extreme frustration; slower than other UPI apps |
| **2** | **Unfulfilled rewards & missing cashback** | no reward, no cashback, zillion coin not received, fake promises | Betrayal; fake reward promises in 2026 reviews |
| **3** | **App crashing, freezing & not opening** | crashing, getting stuck, error opening app, closed automatically, freeze | Complete utility blockage at open / login |
| **4** | **Scams, fraud & loss of trust** | fraud, scam, fake app, chor, luteri company | Severe distrust; “thieving company” language |
| **5** | **Aggressive loan recovery & harassment** | loan recovery, relatives called, dhamki, bad words | Harassment; threats over small pending amounts |
| **6** | **Network & server failures** | server problem, network failure, internet connection, server service very slowly | Backend instability despite user network OK |

### (b) Month-wise negative performance sentiment (Jun 2025 – May 2026)

| Month | Negative score | Summary |
|-------|----------------:|---------|
| **Jun 2025** | **6/10** | Crash spike, endless loading; “full of bugs,” freeze on first page |
| **Jul 2025** | **8/10** | App won’t open; “device not compatible” popups; laggy UI |
| **Aug 2025** | **10/10** | **Peak** — startup crashes, 10–15s scanner load, 5G incompatibility |
| **Sep 2025** | **8/10** | Error 999, auto-close, QR hang, very slow txns |
| **Oct 2025** | **5/10** | Reload loops, slow speed, restart during payment |
| **Nov 2025** | **4/10** | Transfers up to “5 min” vs ~1s elsewhere; freeze on first screen |
| **Dec 2025** | **2/10** | Low volume; stuck after QR scan, UI lag |
| **Jan 2026** | **2/10** | Popups / auto-close; QR widget → home not scanner |
| **Feb 2026** | **3/10** | Crash on open; login freeze; infinite loading |
| **Mar 2026** | **8/10** | **Speed resurgence** — “too slow to pay,” slow servers, laggy UI |
| **Apr 2026** | **9/10** | “Low speed,” slower than other UPI apps, hanging |
| **May 2026** | **5/10** | Hangs, poor optimization, network stalls |

**Readout:** Play Store voice mirrors BigQuery lenses on **speed** (5.4 TPV, platform), **Zillion/rewards** (5.9–5.10), and **trust/support** — use as qualitative validation for product priorities; deck slide **23**.

### 5.19 Verbatim negative reviews (deck slide 24)

**23 curated quotes** in a scrollable two-column layout (replaces marquee on 5.18 for readability).

| Date | Excerpt |
|------|---------|
| 2026-01-01 – 2026-05-14 | 17 dated reviews (login/OTP stuck, crashes, slow txns, server errors, cashback lag, blank screen, etc.) |
| Undated | 6 additional quotes (slow vs CRED/Paytm, Zillion scratch card, invalid UPI ID, Hindi “slow chal raha hai”, etc.) |

**Deck:** slide **23** = themes + month scores · slide **24** = full verbatim text.

---

## Refresh

1. Run queries in [`../sql/upi-retention-queries.sql`](../sql/upi-retention-queries.sql) (sections **(a)–(q)**).
2. Update tables in this file with new output.

---

## Metric map

| Label | Section | Query block in SQL file |
|-------|---------|------------------------|
| M+1 payout retention | (a) | `(a) M+1 payout…` |
| Volume M+k pooled | (b) | `(b) … POOLED` |
| Volume M+k by month | (b) | `(b) … BY cohort_month` |
| Onboarding-month payout M+k | (c) | `(c) Payout retention from month of onboarding` |
| Avg payout TPV bucket M+k | (d) | `(d) … POOLED` and `(d) … BY cohort_month` |
| Pay-in count bucket M+k | (e) | `(e) … POOLED` and `(e) … BY cohort_month` |
| Exclusive subType rail M+k | (f) | `(f) … POOLED` and `(f) … BY cohort_month` |
| Dominant MCC (top 20 + OTHER) M+k | (g) | `(g) … POOLED` and `(g) … BY cohort_month` |
| Exclusive BharatPe QR M+k | (h) | `(h) … POOLED` and `(h) … BY cohort_month` |
| Zillion redemption (reward_amount) M+k | (i) | `(i) … POOLED` and `(i) … BY cohort_month` |
| Zillion earn (amount > 50, type rule) M+k | (j) | `(j) … POOLED`, `(j) … payout-only`, `(j) … BY cohort_month` |
| Platform Android / iOS M+k | (k) | `(k) … POOLED` and `(k) … BY cohort_month` |
| First outward status M+k | (l) | `(l) … POOLED` and `(l) … BY cohort_month` |
| First-5 payout SUCCESS count M+k | (m) | `(m) … POOLED` and `(m) … BY cohort_month` |
| Bank-account linkage count M+k | (n) | `(n) … POOLED` and `(n) … BY cohort_month` |
| Linked account type (dominant / exclusive) M+k | (o) | `(o) … POOLED`, `(o) … BY cohort_month`, `(o) … exclusive POOLED` |
| Installed UPI wallet count M+k | (p) | `(p) … UPI count POOLED` |
| Installed app category flags M+k | (p) | `(p) … category flags POOLED` |
| UPI Lite enabled (note) M+k | (q) | `(q) … UPI Lite enabled POOLED` |
