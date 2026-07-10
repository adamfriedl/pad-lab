#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${GCP_REGION:-US}"
BUCKET="pad-lab-${PROJECT}"
SA_NAME="pad-lab-pipeline"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
RAW_DS="pad_lab_raw"
STAGING_DS="pad_lab_staging"
MART_DS="pad_lab_mart"
RAW_TABLE="actblue_donations"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found on PATH." >&2
    exit 1
  }
}

ensure_dbt() {
  if [[ -x "${ROOT}/.venv/bin/dbt" ]]; then
    export PATH="${ROOT}/.venv/bin:${PATH}"
    return
  fi

  echo "==> Creating local dbt venv..."
  local py=""
  for candidate in python3.13 python3.12 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      py="$candidate"
      break
    fi
  done

  if [[ -z "$py" ]]; then
    echo "ERROR: Python 3.11+ required." >&2
    exit 1
  fi

  "$py" -m venv "${ROOT}/.venv"
  "${ROOT}/.venv/bin/pip" install -q dbt-bigquery
  export PATH="${ROOT}/.venv/bin:${PATH}"
}

echo "==> PAD lab setup"
echo "    Project: ${PROJECT}"
echo "    Region:  ${REGION}"

require_cmd gcloud
require_cmd bq
require_cmd gsutil
ensure_dbt

gcloud config set project "$PROJECT" >/dev/null

echo "==> Enabling APIs..."
gcloud services enable bigquery.googleapis.com storage.googleapis.com --project="$PROJECT"

echo "==> Creating GCS landing bucket..."
if ! gsutil ls -b "gs://${BUCKET}" >/dev/null 2>&1; then
  gsutil mb -p "$PROJECT" -l "$REGION" -b on "gs://${BUCKET}"
fi

echo "==> Uploading sample CSVs..."
gsutil cp "${ROOT}/data/actblue_donations_batch1.csv" "gs://${BUCKET}/landing/batch1/actblue_donations.csv"
gsutil cp "${ROOT}/data/actblue_donations_batch2.csv" "gs://${BUCKET}/landing/batch2/actblue_donations.csv"

echo "==> Creating BigQuery datasets..."
for ds in "$RAW_DS" "$STAGING_DS" "$MART_DS"; do
  bq --location="$REGION" mk --dataset "${PROJECT}:${ds}" 2>/dev/null || true
done

echo "==> Creating partitioned raw table and loading batch 1..."
SCHEMA="donation_id:STRING,amount:FLOAT,created_at:TIMESTAMP,campaign_id:STRING,donor_hash:STRING,_loaded_at:TIMESTAMP"
bq rm -f -t "${PROJECT}:${RAW_DS}.${RAW_TABLE}" 2>/dev/null || true
bq mk --table \
  --time_partitioning_field=created_at \
  --time_partitioning_type=DAY \
  "${PROJECT}:${RAW_DS}.${RAW_TABLE}" \
  "$SCHEMA"

bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --replace=false \
  "${PROJECT}:${RAW_DS}.${RAW_TABLE}" \
  "gs://${BUCKET}/landing/batch1/actblue_donations.csv" \
  "$SCHEMA"

echo "==> Creating pipeline service account..."
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="PAD lab pipeline" \
    --project="$PROJECT"
fi

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/bigquery.jobUser" \
  --condition=None >/dev/null 2>&1 || true

for ds in "$RAW_DS" "$STAGING_DS" "$MART_DS"; do
  bq add-iam-policy-binding \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/bigquery.dataEditor" \
    "${PROJECT}:${ds}" >/dev/null 2>&1 || true
done

echo "==> Writing dbt profiles.yml..."
cat > "${ROOT}/dbt/profiles.yml" <<EOF
pad_lab:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: ${PROJECT}
      dataset: ${STAGING_DS}
      location: ${REGION}
      threads: 4
      timeout_seconds: 300
      priority: interactive
EOF

echo "==> Running dbt pipeline..."
(
  cd "${ROOT}/dbt"
  export PATH="${ROOT}/.venv/bin:${PATH}"
  dbt deps
  dbt run
  dbt test
)

echo
echo "==> Setup complete."
echo
echo "    Raw table:     ${PROJECT}.${RAW_DS}.${RAW_TABLE}"
echo "    Staging view:  ${PROJECT}.${STAGING_DS}.stg_donations"
echo "    Mart table:    ${PROJECT}.${MART_DS}.daily_donation_totals"
echo "    Landing zone:  gs://${BUCKET}/landing/"
echo "    Pipeline SA:   ${SA_EMAIL}"
echo
echo "    Next: read README.md, then work through EXERCISES.md"
echo "    Teardown: ./teardown.sh"
