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

Scheduled path (professional twin of `./run_pipeline.sh`):

```
Cloud Scheduler (daily cron)
  → Cloud Run Job (pad-lab-pipeline SA)
      → loaders → GCS → BigQuery raw → dbt run/test
  → Cloud Monitoring alerts on failure / missed success
```

| Layer    | Resource                               | Production equivalent       |
| -------- | -------------------------------------- | --------------------------- |
| Source   | FEC OpenFEC API                        | ActBlue / VAN / vendor APIs |
| Landing  | `gs://pad-lab-{project}/landing/`      | Airbyte → GCS (PADdle)      |
| Raw      | `pad_lab_raw.fec_contributions`        | PAD raw tables              |
| Raw      | `pad_lab_raw.fec_committees`           | PAD dimension tables        |
| Staging  | `pad_lab_staging.stg_contributions`    | dbt staging models          |
| Staging  | `pad_lab_staging.stg_committees`       | dbt staging models          |
| Mart     | `pad_lab_mart.daily_contributions`     | dbt marts → SketchPAD       |
| Mart     | `pad_lab_mart.committee_summary`       | dbt marts → SketchPAD       |
| Infra    | Terraform (`infra/`)                   | IaC for datasets, IAM, jobs |
| Schedule | Cloud Scheduler → Cloud Run Job        | Airflow / Composer DAGs     |
| Secrets  | Secret Manager (`pad-lab-fec-api-key`) | Vault / SM                  |
| Monitor  | Cloud Monitoring alert policies        | PADLock / on-call           |

## Data

Uses real FEC (Federal Election Commission) data:

- **Individual contributions** — Schedule A filings: who gave how much to which committee, when, from where. ~10,000 records by default.
- **Committees** — campaign committees, PACs, party committees. Dimension table joined to contributions for party/type enrichment.

No PII concerns — all FEC data is [public record](https://www.fec.gov/introduction-campaign-finance/how-to-research-public-records/).

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated (`gcloud auth login` + `gcloud auth application-default login`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- Active GCP project with billing enabled
- Python 3.11+
- FEC API key (free — [register here](https://api.data.gov/signup/))

## Quick start

```bash
# 1. Configure
cp .env.example .env
# Edit .env — add FEC_API_KEY and optionally GCP_PROJECT / ALERT_EMAIL

# 2. Bootstrap Terraform state bucket, apply infra, build image, load data
./setup.sh

# 3. Work through the exercises
open EXERCISES.md
```

`./setup.sh` will:

1. Create `gs://pad-lab-{project}-tfstate` (remote Terraform state)
2. `terraform apply` — datasets, landing bucket, dual service accounts, Secret Manager, Artifact Registry, Cloud Run Job, Scheduler, alerts
3. Install local Python/dbt deps and write `dbt/profiles.yml` (laptop OAuth)
4. Build/push `{region}-docker.pkg.dev/{project}/pad-lab/pipeline:latest`
5. Run `./run_pipeline.sh --save-sample` once locally

Options: `--skip-image`, `--skip-pipeline`.

## Project layout

```
pad-lab/
├── README.md
├── EXERCISES.md
├── requirements.txt
├── Dockerfile                  # Cloud Run Job image
├── setup.sh                    # Terraform apply + local deps + image
├── run_pipeline.sh             # Local: FEC fetch → BQ load → dbt
├── teardown.sh                 # terraform destroy
├── .env.example
├── infra/                      # Terraform (GCS backend)
│   ├── apis.tf
│   ├── storage_bq.tf
│   ├── iam.tf
│   ├── secrets.tf
│   ├── artifact_registry.tf
│   ├── cloud_run.tf
│   ├── monitoring.tf
│   └── terraform.tfvars.example
├── scripts/
│   ├── bootstrap_tfstate.sh
│   ├── build_image.sh
│   ├── run_job.sh              # Manually execute Cloud Run Job
│   ├── check_freshness.sh      # SQL freshness check
│   └── pipeline_entrypoint.sh  # Container entrypoint
├── loaders/
│   ├── fec.py
│   ├── load_contributions.py
│   └── load_committees.py
└── dbt/
    ├── models/
    │   ├── sources.yml
    │   ├── staging/
    │   └── marts/
    ├── tests/
    └── macros/
```

## Loaders

Python scripts that fetch from the FEC API, normalize records, and load to BigQuery.

### Contributions (fact table)

```bash
# Fetch 10000 contributions from the 2024 cycle (default)
python -m loaders.load_contributions

# Or cap lower for a quick test
python -m loaders.load_contributions --max-records 1000

# Filter to Oregon contributors
python -m loaders.load_contributions --state OR --max-records 500

# Incremental sync (since raw high-water mark minus 7-day overlap)
python -m loaders.load_contributions --since-watermark --lookback-days 7

# Backfill a date window
python -m loaders.load_contributions --min-date 2024-06-01 --max-date 2024-06-30

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

### Local refresh

```bash
./run_pipeline.sh              # incremental (watermark + 7d lookback)
./run_pipeline.sh --full-refresh # re-fetch from cycle start (cap: max-records)
```

### Scheduled / Cloud Run refresh

```bash
./scripts/build_image.sh    # after loader/dbt changes
./scripts/run_job.sh        # execute now (waits for completion)
./scripts/check_freshness.sh
```

Daily schedule defaults to `0 14 * * *` UTC (Cloud Scheduler → Cloud Run Job). The job runs as `pad-lab-pipeline`; Scheduler triggers as `pad-lab-scheduler` (`roles/run.invoker` only).

## IAM model

| Identity            | Purpose                            | Privileges                                                                           |
| ------------------- | ---------------------------------- | ------------------------------------------------------------------------------------ |
| `pad-lab-pipeline`  | Cloud Run Job runtime              | BQ jobUser + dataEditor on lab datasets, GCS objectAdmin on landing, Secret accessor |
| `pad-lab-scheduler` | Cloud Scheduler OIDC/OAuth trigger | `roles/run.invoker` on the job only                                                  |

## Monitoring

When `alert_email` / `ALERT_EMAIL` is set in Terraform:

**Pipeline (Cloud Monitoring — `infra/monitoring.tf`)**

- **Job failed** — Cloud Run Job `completed_execution_count{result=failed}` > 0
- **Stale pipeline** — no successful execution for 24h (covers missed schedules)

**Data quality (dbt tests — fail the job → same job-failed alert)**

- `assert_orphan_committee_ratio` — >5% of contributions missing from `stg_committees`
- `assert_minimum_staging_volume` — staging row count below 100 (catastrophic load failure)
- Plus column tests (unique, not_null) and `assert_positive_contribution_count` on marts

**Cost (optional — `infra/billing.tf`)**

Set `billing_account_id` in `infra/terraform.tfvars` to add a **project-scoped** monthly budget. This is **separate** from any account-wide budget you already have — same billing account, different filter (pad-lab project only). Alerts at 50%, 90%, and forecasted 100% of `monthly_budget_usd` (default $25).

Optional manual SQL check: `./scripts/check_freshness.sh`.

## Why not Cloud Composer / Airflow?

Cloud Composer 3 keeps a managed Airflow environment running 24/7. A small env typically costs **~$300–400/month idle** before any DAGs run. This lab uses **Cloud Scheduler + Cloud Run Job** (~$0–2/month for orchestration) to learn the same scheduling / failure-alerting patterns without that floor. Composer is the right CTA-shaped choice when you already pay for multi-DAG orchestration with sensors and a team operating Airflow.

## Key design choices

- **Terraform + GCS state** — reproducible infra; state in `gs://pad-lab-{project}-tfstate`.
- **Real data, real patterns** — FEC contribution data has the same shape as ActBlue/VAN data flowing through PAD.
- **Partitioned raw table** on `contribution_receipt_date` — cost control via partition pruning.
- **Incremental ingest** — scheduled runs use `--since-watermark`: `MAX(contribution_receipt_date)` in raw minus a 7-day overlap, then staging dedupes by `sub_id`.
- **Incremental mart** with merge on `(date, committee_id)` — nightly dbt runs without full refresh.
- **Two loading patterns** — GCS landing for fact data, direct load for dimensions.
- **Dedup in staging** — raw is append-only; staging handles duplicates via latest-wins.
- **Split runtime vs trigger SAs** — least privilege for data work vs job invocation.
- **Sample data cached** in `data/samples/` for offline use without hitting the API.

## Cleanup

```bash
./teardown.sh                 # terraform destroy
./teardown.sh --delete-tfstate  # also delete the state bucket
```

## Stack mapping

| This lab                        | CTA production                  |
| ------------------------------- | ------------------------------- |
| Python loaders + FEC API        | Airbyte connectors (PADdle)     |
| GCS landing zone                | Airbyte → GCS sync              |
| dbt views + incremental tables  | dbt staging/mart models         |
| Cloud Scheduler + Cloud Run Job | Scheduled Airflow/Composer jobs |
| Manual `bq query`               | SketchPAD / Looker dashboards   |
| Cloud Monitoring alerts         | PADLock monitoring              |
| Terraform (`infra/`)            | Platform IaC                    |

## License

MIT — uses public FEC data for educational purposes.
