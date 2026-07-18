#!/usr/bin/env bash
# Shared pipeline: FEC load → dbt run/test → viz export.
# Local:  ./run_pipeline.sh (activates .venv, then execs this)
# Cloud:  Docker ENTRYPOINT / Cloud Run Job (CLOUD_RUN_JOB set)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAX_RECORDS="${MAX_RECORDS:-10000}"
LOOKBACK_DAYS="${LOOKBACK_DAYS:-7}"
SAVE_SAMPLE=false
SINCE_WATERMARK=true
DBT_TARGET=""

# Cloud Run Jobs set CLOUD_RUN_JOB — use ADC profile + watermark defaults.
IN_CLOUD=false
if [[ -n "${CLOUD_RUN_JOB:-}" ]]; then
  IN_CLOUD=true
  DBT_TARGET="prod"
fi

usage() {
  cat <<EOF
Usage: scripts/pipeline.sh [options]

  Fetch contributions and committees from the FEC API, load to BigQuery,
  then run dbt run + dbt test and export viz JSON to GCS.

Options:
  --max-records N     Contribution fetch limit (default: 10000 or MAX_RECORDS)
  --lookback-days N   Overlap when using watermark (default: 7)
  --full-refresh      Fetch from cycle start (no watermark); ignored in Cloud Run
  --save-sample       Update data/samples/*.ndjson (local only)
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-records)
      MAX_RECORDS="$2"
      shift 2
      ;;
    --lookback-days)
      LOOKBACK_DAYS="$2"
      shift 2
      ;;
    --full-refresh)
      if $IN_CLOUD; then
        echo "WARNING: --full-refresh ignored in Cloud Run (use DBT_FULL_REFRESH_DAILY for dbt)" >&2
      else
        SINCE_WATERMARK=false
      fi
      shift
      ;;
    --save-sample)
      SAVE_SAMPLE=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if $IN_CLOUD; then
  PROJECT="${GCP_PROJECT:?GCP_PROJECT is required}"
  BQ_LOCATION="${BQ_LOCATION:-${GCP_REGION:-US}}"
  mkdir -p /tmp/dbt
  export DBT_PROFILES_DIR=/tmp/dbt
  cat > /tmp/dbt/profiles.yml <<EOF
pad_lab:
  target: prod
  outputs:
    prod:
      type: bigquery
      method: oauth
      project: ${PROJECT}
      dataset: pad_lab_staging
      location: ${BQ_LOCATION}
      threads: 4
      timeout_seconds: 600
      priority: interactive
EOF
  SINCE_WATERMARK=true
fi

CONTRIB_ARGS=(--max-records "$MAX_RECORDS")
if $SINCE_WATERMARK; then
  CONTRIB_ARGS+=(--since-watermark --lookback-days "$LOOKBACK_DAYS")
fi
COMMITTEE_ARGS=(--from-contributions)
if $SAVE_SAMPLE && ! $IN_CLOUD; then
  CONTRIB_ARGS+=(--save-sample)
  COMMITTEE_ARGS+=(--save-sample)
fi

echo "==> Loading FEC contributions (max=${MAX_RECORDS}, watermark=${SINCE_WATERMARK}, lookback=${LOOKBACK_DAYS}d)..."
python -m loaders.load_contributions "${CONTRIB_ARGS[@]}"

echo "==> Loading FEC committees (from contributions)..."
python -m loaders.load_committees "${COMMITTEE_ARGS[@]}"

echo "==> Running dbt..."
(
  cd "${ROOT}/dbt"
  DBT_ARGS=()
  if [[ -n "$DBT_TARGET" ]]; then
    DBT_ARGS+=(--target "$DBT_TARGET")
  fi
  if [[ "${DBT_FULL_REFRESH_DAILY:-0}" == "1" || "${DBT_FULL_REFRESH_DAILY:-0}" == "true" ]]; then
    echo "==> DBT_FULL_REFRESH_DAILY set — rebuild staging, full-refresh daily_contributions"
    dbt run "${DBT_ARGS[@]}" --select +daily_contributions --full-refresh
    dbt run "${DBT_ARGS[@]}" --select committee_summary
  else
    dbt run "${DBT_ARGS[@]}"
  fi
  dbt test "${DBT_ARGS[@]}"
)

echo "==> Exporting viz data to GCS..."
python scripts/export_viz_data.py --upload

echo "==> Pipeline complete."
