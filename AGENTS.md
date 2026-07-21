# AGENTS.md

Repo-specific guidance for AI coding agents. Cross-repo Definition of Done: Cursor rule `forge-agent-dod` + `verify` skill.

## What this repo is

Hands-on **data pipeline lab** on real FEC contribution data, shaped like a miniature PAD/PADdle stack:

```
FEC API → Python loaders → GCS landing → BigQuery raw
  → dbt staging → dbt marts → viz JSON / dashboard
```

Learning project — not production PAD, not affiliated with Community Tech Alliance.

## Stack conventions

- **Python 3.11+** loaders under `loaders/` — match existing CLI flags, NDJSON shapes, and watermark patterns.
- **dbt** under `dbt/` — staging cleans/dedupes one source; marts aggregate/join. Use `{{ ref() }}` / `{{ source() }}`.
- **BigQuery** — raw is append-only and partitioned; think about partition filters and bytes scanned.
- **Terraform** under `infra/` — datasets, IAM, Cloud Run Job, Scheduler, alerts. Don't invent prod Composer unless asked.
- **Viz** under `viz/` — static React dashboard; reads **mart JSON only**, never raw.

## When scaffolding code

1. Match a neighbor file before inventing a pattern (`stg_contributions.sql`, `loaders/load_contributions.py`).
2. Staging dedupe: `ROW_NUMBER() OVER (PARTITION BY <natural_key> ORDER BY loaded_at DESC) = 1`.
3. Prefer CTEs: `source` → `cleaned` → `deduped` → final select.
4. Add or extend dbt tests when changing models (`not_null`, `unique`, custom SQL under `dbt/tests/`).
5. Secrets stay local: `.env`, `dbt/profiles.yml`, `infra/terraform.tfvars`, API keys — gitignored.

## Verify

Before claiming done, run the `verify` skill or:

- Row counts across raw / staging / mart (see `EXERCISES.md`) when grain/semantics change
- `cd dbt && dbt run -s <model> && dbt test` for model changes
- BigQuery `--dry_run` when cost/partition pruning matters
- Prefer sample/cached inputs (`data/samples/`, `--input-file`, `--dry-run`) over live API spam

## Gotchas

- Don't claim this lab operated multi-tenant production PAD pipelines.
- Explain tradeoffs when changing pipeline semantics (grain, incremental vs full refresh, join coverage).
