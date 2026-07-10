#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET="pad-lab-${PROJECT}"
RAW_DS="pad_lab_raw"
RAW_TABLE="actblue_donations"
SCHEMA="donation_id:STRING,amount:FLOAT,created_at:TIMESTAMP,campaign_id:STRING,donor_hash:STRING,_loaded_at:TIMESTAMP"

echo "==> Loading batch 2 (simulated nightly ActBlue sync)..."

gsutil cp "${ROOT}/data/actblue_donations_batch2.csv" "gs://${BUCKET}/landing/batch2/actblue_donations.csv"

bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --replace=false \
  "${PROJECT}:${RAW_DS}.${RAW_TABLE}" \
  "gs://${BUCKET}/landing/batch2/actblue_donations.csv" \
  "$SCHEMA"

echo "==> Running dbt..."
(
  cd "${ROOT}/dbt"
  export PATH="${ROOT}/.venv/bin:${PATH}"
  dbt run
  dbt test
)

echo
echo "==> Batch 2 loaded. Compare mart totals by campaign."
echo "    gotv_march should have no new rows from batch 2."
