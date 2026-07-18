# PAD Lab Exercises

Guided walkthrough of the pipeline (~45 min). Each section ends with a **takeaway** summarizing the concept.

```bash
PROJECT=$(gcloud config get-value project)
```

---

## 1. Walk the pipeline (8 min)

Row counts across layers:

```bash
bq query --use_legacy_sql=false "
SELECT 'raw' AS layer, COUNT(*) AS row_count
FROM \`${PROJECT}.pad_lab_raw.fec_contributions\`
UNION ALL
SELECT 'staging', COUNT(*)
FROM \`${PROJECT}.pad_lab_staging.stg_contributions\`
UNION ALL
SELECT 'mart (daily)', COUNT(*)
FROM \`${PROJECT}.pad_lab_mart.daily_contributions\`
UNION ALL
SELECT 'mart (committee)', COUNT(*)
FROM \`${PROJECT}.pad_lab_mart.committee_summary\`"
```

Top committees by total raised:

```bash
bq query --use_legacy_sql=false "
SELECT committee_name, party, total_contributions,
       ROUND(total_raised, 2) AS total_raised
FROM \`${PROJECT}.pad_lab_mart.committee_summary\`
ORDER BY total_raised DESC
LIMIT 10"
```

Verify staging dedupe (should return 0):

```bash
bq query --use_legacy_sql=false "
SELECT COUNT(*) AS duplicate_sub_ids
FROM (
  SELECT sub_id
  FROM \`${PROJECT}.pad_lab_staging.stg_contributions\`
  GROUP BY 1
  HAVING COUNT(*) > 1
)"
```

**Takeaway:** "Vendor data lands in raw via API sync, dbt builds staging views for cleaning and marts for aggregation. Dashboards read from marts, never raw."

---

## 2. Cost control — partition pruning (10 min)

Compare bytes scanned with and without a partition filter:

```bash
# Full table scan
bq query --use_legacy_sql=false --dry_run "
SELECT SUM(contribution_receipt_amount)
FROM \`${PROJECT}.pad_lab_raw.fec_contributions\`"

# Partition-pruned (single month)
bq query --use_legacy_sql=false --dry_run "
SELECT SUM(contribution_receipt_amount)
FROM \`${PROJECT}.pad_lab_raw.fec_contributions\`
WHERE contribution_receipt_date BETWEEN '2024-06-01' AND '2024-06-30'"
```

Look for `This query will process X bytes` in each output.

**Takeaway:** "BigQuery cost control is culture plus guardrails — partition filters, curated views for common queries, exploration sandboxes separate from production tables, and cost-spike postmortems."

---

## 3. Simulate incremental load (10 min)

Fetch a new batch of contributions and run dbt incrementally:

```bash
# Watermark sync — only pulls since last raw max date (minus 7d overlap)
python -m loaders.load_contributions --since-watermark --max-records 200

# Or an explicit backfill window / state filter:
python -m loaders.load_contributions --max-records 200 --state CA

# Run dbt (incremental — only recalculates affected keys)
(cd dbt && dbt run && dbt test)
```

Check that mart totals updated:

```bash
bq query --use_legacy_sql=false "
SELECT committee_id,
       SUM(contribution_count) AS contributions,
       ROUND(SUM(total_amount), 2) AS total
FROM \`${PROJECT}.pad_lab_mart.daily_contributions\`
GROUP BY 1 ORDER BY total DESC LIMIT 10"
```

**Takeaway:** "The loader appends to raw using a high-water mark plus overlap for late filings. dbt's incremental strategy only recalculates date/committee keys that received new data — not a full refresh every cycle."

---

## 4. Cross-source join (5 min)

The `committee_summary` mart joins contributions with the committee dimension:

```bash
bq query --use_legacy_sql=false "
SELECT party_full,
       COUNT(*) AS committees,
       SUM(total_contributions) AS contributions,
       ROUND(SUM(total_raised), 2) AS total_raised
FROM \`${PROJECT}.pad_lab_mart.committee_summary\`
WHERE party_full != ''
GROUP BY 1 ORDER BY total_raised DESC"
```

**Takeaway:** "This is why dimension tables matter — raw contributions only have committee IDs. Joining with the committee source adds party, type, and state for meaningful aggregation."

---

## 5. Data quality debugging (10 min)

Check for committees in contributions that aren't in the dimension table:

```bash
bq query --use_legacy_sql=false "
SELECT c.committee_id, COUNT(*) AS orphan_contributions
FROM \`${PROJECT}.pad_lab_staging.stg_contributions\` c
LEFT JOIN \`${PROJECT}.pad_lab_staging.stg_committees\` cm
  USING (committee_id)
WHERE cm.committee_id IS NULL
GROUP BY 1 ORDER BY 2 DESC
LIMIT 10"
```

If orphans exist, reload the dimension and rebuild the mart:

```bash
python -m loaders.load_committees --from-contributions
(cd dbt && dbt run --select committee_summary && dbt test)
```

**Takeaway:** "The pipeline succeeded but some committees are missing from the dimension table. I'd compare source vs. destination coverage per dimension and flag gaps before they reach dashboards."

---

## 6. Observability sketch (5 min)

**Pipeline alerts** (Terraform + Cloud Monitoring, when `ALERT_EMAIL` is set):

| Signal      | Alert                       | First check                             |
| ----------- | --------------------------- | --------------------------------------- |
| Freshness   | No successful job > 24h     | Cloud Scheduler → Cloud Run Job history |
| Job failure | Cloud Run Job result=failed | Job logs, FEC API, dbt test output      |
| Cost (opt.) | Project budget thresholds   | Billing → Budgets (pad-lab filter)      |

**Data quality** (dbt tests — run every pipeline; failure fails the job):

| Signal        | Test                                 | First check                 |
| ------------- | ------------------------------------ | --------------------------- |
| Join coverage | `assert_orphan_committee_ratio`      | Reload committees dimension |
| Volume floor  | `assert_minimum_staging_volume`      | Loader filters, FEC API     |
| Mart sanity   | `assert_positive_contribution_count` | Upstream staging dedupe     |

Run tests manually:

```bash
(cd dbt && dbt test)
```

Manual raw freshness SQL:

```bash
./scripts/check_freshness.sh
```

**Takeaway:** "Every alert links to what to check first. On-call shouldn't be grepping Slack at 2am."

---

## 7. Terraform + scheduled run (10 min)

Inspect what Terraform manages:

```bash
cd infra
terraform plan
terraform output
```

Trigger the cloud pipeline once (same path as the daily schedule — execute job):

```bash
./scripts/run_job.sh
```

Rebuild the image from your local tree (or rely on the Cloud Build trigger after pushing pipeline paths to `main`):

```bash
./scripts/build_image.sh
# or: ./scripts/run_job.sh --build
```

**Takeaway:** "Infra is declarative (datasets, IAM, schedule, alerts). Cloud Build ships a new container when pipeline code changes; the scheduled job runs ingest + dbt against `:latest`."

---

## 8. Dashboard (10 min)

Export marts to the static site and open the contribution desk:

```bash
python scripts/export_viz_data.py
python scripts/export_viz_data.py --upload   # also refresh GCS for Pages

cd viz
npm install
npm run dev
# open http://localhost:5173/pad-lab/
```

Confirm KPIs, the committee scatter, top committees, and party breakdown all reflect
`pad_lab_mart` — filter by party and date without touching raw tables.

After a push to `main`, the same build deploys to
https://adamfriedl.github.io/pad-lab/ (repo Settings → Pages → GitHub Actions).
Prod fetches mart JSON from the public GCS viz bucket (`VITE_DATA_BASE_URL`).

**Takeaway:** "Dashboards consume curated marts. Export is the batch twin of a BI extract; the UI should never query raw."

---

## 9. Cleanup

```bash
./teardown.sh
```
