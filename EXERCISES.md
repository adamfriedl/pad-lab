# PAD Lab Exercises (~45 min)

Guided walkthrough of the pipeline in [README.md](./README.md). Each section includes a **say out loud** line for interview practice.

Set your project once:

```bash
PROJECT=$(gcloud config get-value project)
```

---

## 1. Walk the pipeline (8 min)

Compare row counts across layers:

```bash
bq query --use_legacy_sql=false "
SELECT 'raw' AS layer, COUNT(*) AS row_count
FROM \`${PROJECT}.pad_lab_raw.actblue_donations\`
UNION ALL
SELECT 'staging', COUNT(*)
FROM \`${PROJECT}.pad_lab_staging.stg_donations\`
UNION ALL
SELECT 'mart_groups', COUNT(*)
FROM \`${PROJECT}.pad_lab_mart.daily_donation_totals\`"
```

Campaign totals from the mart:

```bash
bq query --use_legacy_sql=false "
SELECT campaign_id, SUM(donation_count) AS donations, ROUND(SUM(total_amount), 2) AS total
FROM \`${PROJECT}.pad_lab_mart.daily_donation_totals\`
GROUP BY 1 ORDER BY 1"
```

Verify staging dedupe (should return 0):

```bash
bq query --use_legacy_sql=false "
SELECT COUNT(*) AS duplicate_donation_ids
FROM (
  SELECT donation_id
  FROM \`${PROJECT}.pad_lab_staging.stg_donations\`
  GROUP BY 1
  HAVING COUNT(*) > 1
)"
```

**Say out loud:** "This is PADdle's shape — vendor data lands in raw, dbt builds staging and marts, dashboards read from marts."

---

## 2. Cost control (10 min)

Compare bytes scanned with and without a partition filter:

```bash
# Bad — full table scan
bq query --use_legacy_sql=false --dry_run "
SELECT SUM(amount) FROM \`${PROJECT}.pad_lab_raw.actblue_donations\`"

# Good — partition filter
bq query --use_legacy_sql=false --dry_run "
SELECT SUM(amount) FROM \`${PROJECT}.pad_lab_raw.actblue_donations\`
WHERE DATE(created_at) = '2026-01-15'"
```

Look for `running this query will process X bytes of data` in each output.

**Say out loud:** "Cost control on BigQuery is culture plus guardrails — partition filters, curated views, exploration sandboxes separate from production tables, and postmortem cost spikes like outages."

---

## 3. Simulate nightly sync (8 min)

```bash
./scripts/load_batch2.sh
```

Verify totals moved:

```bash
bq query --use_legacy_sql=false "
SELECT campaign_id, SUM(donation_count) AS donations, SUM(total_amount) AS total
FROM \`${PROJECT}.pad_lab_mart.daily_donation_totals\`
GROUP BY 1 ORDER BY 1"
```

**Say out loud:** "Airbyte appends to raw nightly; dbt incrementally merges affected keys. We don't full-refresh every cycle."

---

## 4. Silent failure (10 min)

Batch 2 was generated **without `gotv_march` donations**. The pipeline succeeds but one campaign stops updating.

Raw rows by campaign:

```bash
bq query --use_legacy_sql=false "
SELECT campaign_id, COUNT(*) AS raw_rows
FROM \`${PROJECT}.pad_lab_raw.actblue_donations\`
GROUP BY 1 ORDER BY 1"
```

Batch 2 rows only (gotv_march should be missing):

```bash
bq query --use_legacy_sql=false "
SELECT campaign_id, COUNT(*) AS batch2_rows
FROM \`${PROJECT}.pad_lab_raw.actblue_donations\`
WHERE donation_id LIKE 'AB-2-%'
GROUP BY 1 ORDER BY 1"
```

**Say out loud:** "The job succeeded — that's what makes it dangerous. I'd compare source vs destination counts by campaign and notify the client if dashboards may show wrong totals."

---

## 5. Observability judgment (5 min)

Sketch alerts you'd want on this pipeline:

| Signal | Alert | First check |
|--------|-------|-------------|
| Freshness | Mart stale > 6h | Airbyte/dbt job status |
| Volume | Donations drop >20% DoD | Raw vs staging counts |
| Job failure | dbt run failed | Recent deploy/config change |
| Cost | Bytes scanned spike | Query history |

**Say out loud:** "Every alert links to what to check first — on-call shouldn't grep Slack at 2am."

---

## 6. Cleanup

```bash
./teardown.sh
```
