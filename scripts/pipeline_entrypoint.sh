#!/usr/bin/env bash
# Cloud Run Job entrypoint: FEC load → dbt run/test.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT:?GCP_PROJECT is required}"
BQ_LOCATION="${GCP_REGION:-US}"
MAX_RECORDS="${MAX_RECORDS:-10000}"
LOOKBACK_DAYS="${LOOKBACK_DAYS:-7}"

# dbt profile using ADC (Cloud Run attaches pad-lab-pipeline SA).
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

echo "==> Loading FEC contributions (max=${MAX_RECORDS}, since-watermark, lookback=${LOOKBACK_DAYS}d)..."
python -m loaders.load_contributions \
  --max-records "$MAX_RECORDS" \
  --since-watermark \
  --lookback-days "$LOOKBACK_DAYS"

echo "==> Loading FEC committees..."
python -m loaders.load_committees --from-contributions

echo "==> Running dbt..."
(
  cd "${ROOT}/dbt"
  dbt deps
  if [[ "${DBT_FULL_REFRESH_DAILY:-0}" == "1" || "${DBT_FULL_REFRESH_DAILY:-0}" == "true" ]]; then
    echo "==> DBT_FULL_REFRESH_DAILY set — full-refresh daily_contributions"
    dbt run --target prod --select daily_contributions --full-refresh
    dbt run --target prod --exclude daily_contributions
  else
    dbt run --target prod
  fi
  dbt test --target prod
)

echo "==> Pipeline complete."
