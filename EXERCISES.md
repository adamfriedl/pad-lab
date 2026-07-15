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
SELECT 'raw' AS layer, COUNT(*) AS rows
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
# Fetch 200 more records from a different state
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

**Takeaway:** "The loader appends to raw. dbt's incremental strategy only recalculates date/committee keys that received new data — not a full refresh every cycle."

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

Alerts you'd want on this pipeline in production:

| Signal        | Alert                       | First check                                |
| ------------- | --------------------------- | ------------------------------------------ |
| Freshness     | Raw table stale > 6h        | Airbyte/loader job status                  |
| Volume        | Contributions drop >30% DoD | Source API health, date filter drift       |
| Join coverage | >5% orphan committee_ids    | Dimension sync timing                      |
| Cost          | Bytes scanned spike >2x     | Query history, missing partition filter    |
| Job failure   | dbt run/test failed         | Recent model change, upstream schema drift |

**Takeaway:** "Every alert links to what to check first. On-call shouldn't be grepping Slack at 2am."

---

## 7. Cleanup

```bash
./teardown.sh
```
