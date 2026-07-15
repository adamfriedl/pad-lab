# pad-lab

A hands-on data pipeline lab built on real [FEC campaign finance data](https://www.fec.gov/data/), mirroring [Community Tech Alliance's PAD stack](https://communitytechalliance.org/) — Python loaders fetching from a public API, landing in GCS, flowing through BigQuery raw → dbt staging → dbt marts.

**What this is:** A learning project I built to understand PAD/PADdle architecture hands-on. Not production code, not affiliated with CTA.

**What this is not:** A claim of production data-engineering experience. I haven't operated BigQuery/Airbyte/dbt pipelines at PAD scale — this lab let me walk the layers and reason about observability, cost, and data quality on a real dataset.

## Architecture

```
FEC API (real political contribution data)
  → Python loaders        # Airbyte would handle this in production
  → GCS landing bucket    # append-only NDJSON files
  → pad_lab_raw (BQ)      # partitioned, append-only
  → pad_lab_staging (dbt) # clean, dedupe, type coercion
  → pad_lab_mart (dbt)    # incremental aggregates, joined dimensions
```

| Layer   | Resource                            | Production equivalent       |
| ------- | ----------------------------------- | --------------------------- |
| Source  | FEC OpenFEC API                     | ActBlue / VAN / vendor APIs |
| Landing | `gs://pad-lab-{project}/landing/`   | Airbyte → GCS (PADdle)      |
| Raw     | `pad_lab_raw.fec_contributions`     | PAD raw tables              |
| Raw     | `pad_lab_raw.fec_committees`        | PAD dimension tables        |
| Staging | `pad_lab_staging.stg_contributions` | dbt staging models          |
| Staging | `pad_lab_staging.stg_committees`    | dbt staging models          |
| Mart    | `pad_lab_mart.daily_contributions`  | dbt marts → SketchPAD       |
| Mart    | `pad_lab_mart.committee_summary`    | dbt marts → SketchPAD       |

## Data

Uses real FEC (Federal Election Commission) data:

- **Individual contributions** — Schedule A filings: who gave how much to which committee, when, from where. ~1,000 records by default.
- **Committees** — campaign committees, PACs, party committees. Dimension table joined to contributions for party/type enrichment.

No PII concerns — all FEC data is [public record](https://www.fec.gov/introduction-campaign-finance/how-to-research-public-records/).

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated (`gcloud auth login` + `gcloud auth application-default login`)
- Active GCP project with billing enabled
- Python 3.11+
- FEC API key (free — [register here](https://api.data.gov/signup/))

## Quick start

```bash
# 1. Configure
cp .env.example .env
# Edit .env — add your FEC_API_KEY and optionally set GCP_PROJECT

# 2. Bootstrap GCP resources, fetch data, run dbt
./setup.sh

# 3. Work through the exercises
open EXERCISES.md
```

## Project layout

```
pad-lab/
├── README.md
├── EXERCISES.md
├── requirements.txt
├── setup.sh                    # Bootstrap everything
├── teardown.sh                 # Remove all GCP resources
├── .env.example                # FEC_API_KEY, GCP_PROJECT
├── loaders/
│   ├── fec.py                  # FEC API client (pagination, rate limiting)
│   ├── load_contributions.py   # contributions → GCS → BigQuery
│   └── load_committees.py      # committees → BigQuery (direct)
└── dbt/
    ├── models/
    │   ├── sources.yml
    │   ├── staging/
    │   │   ├── stg_contributions.sql   # dedupe, clean, type cast
    │   │   └── stg_committees.sql      # committee dimension
    │   └── marts/
    │       ├── daily_contributions.sql  # incremental daily aggregates
    │       └── committee_summary.sql    # committee totals + party join
    ├── tests/
    │   └── assert_positive_contribution_count.sql
    └── macros/
        └── generate_schema_name.sql
```

## Loaders

Python scripts that fetch from the FEC API, normalize records, and load to BigQuery.

### Contributions (fact table)

```bash
# Fetch 1000 contributions from the 2024 cycle
python -m loaders.load_contributions --max-records 1000

# Filter to Oregon contributors
python -m loaders.load_contributions --state OR --max-records 500

# Dry run (validate only, no BQ load)
python -m loaders.load_contributions --dry-run

# Use cached data (no API call)
python -m loaders.load_contributions --input-file data/samples/contributions.ndjson
```

Contributions flow through GCS before loading to BigQuery — mirroring how Airbyte syncs vendor data through a GCS landing zone in production.

### Committees (dimension table)

```bash
# Fetch committees that appear in loaded contributions
python -m loaders.load_committees --from-contributions

# Fetch by cycle
python -m loaders.load_committees --cycle 2024 --max-records 200
```

Committees load directly to BigQuery (no GCS step) — dimension tables are small and often come from a different sync pattern than fact data.

## Key design choices

- **Real data, real patterns** — FEC contribution data has the same shape as ActBlue/VAN data flowing through PAD: timestamped transactions, committee dimensions, state and occupation attributes.
- **Partitioned raw table** on `contribution_receipt_date` — cost control via partition pruning.
- **Incremental mart** with merge on `(date, committee_id)` — nightly dbt runs without full refresh.
- **Two loading patterns** — GCS landing for fact data (production ETL pattern), direct load for dimensions.
- **Dedup in staging** — raw table is append-only; staging handles duplicates via `sub_id` / `committee_id` with latest-wins logic.
- **Cross-source join** — `committee_summary` mart joins contribution facts with the committee dimension for party/type enrichment.
- **dbt tests** on staging (unique IDs, not-null) and marts (aggregates, singular test for positive counts).
- **Dataset-scoped IAM** on a dedicated pipeline service account.
- **Sample data cached** in `data/samples/` for offline use without hitting the API.

## Cleanup

```bash
./teardown.sh
```

## Stack mapping

| This lab                       | CTA production                  |
| ------------------------------ | ------------------------------- |
| Python loaders + FEC API       | Airbyte connectors (PADdle)     |
| GCS landing zone               | Airbyte → GCS sync              |
| dbt views + incremental tables | dbt staging/mart models         |
| `python -m loaders.load_*`     | Scheduled Airflow/Composer jobs |
| Manual `bq query`              | SketchPAD / Looker dashboards   |
| (not implemented)              | PADLock monitoring              |

## License

MIT — uses public FEC data for educational purposes.
