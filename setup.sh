#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${GCP_REGION:-US}"
BUCKET="pad-lab-${PROJECT}"
SA_NAME="pad-lab-pipeline"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
RAW_DS="pad_lab_raw"
STAGING_DS="pad_lab_staging"
MART_DS="pad_lab_mart"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found on PATH." >&2
    exit 1
  }
}

echo "==> PAD Lab setup"
echo "    Project:  ${PROJECT}"
echo "    Region:   ${REGION}"
echo "    FEC key:  ${FEC_API_KEY:-DEMO_KEY}"
echo

require_cmd gcloud
require_cmd bq

# ---- Python venv (loaders + dbt) ----------------------------------------
if [[ ! -x "${ROOT}/.venv/bin/python" ]]; then
  echo "==> Creating Python venv..."
  py=""
  for c in python3.13 python3.12 python3.11 python3; do
    command -v "$c" >/dev/null 2>&1 && { py="$c"; break; }
  done
  [[ -z "$py" ]] && { echo "ERROR: Python 3.11+ required." >&2; exit 1; }
  "$py" -m venv "${ROOT}/.venv"
fi
echo "==> Installing Python dependencies..."
"${ROOT}/.venv/bin/pip" install -q -r "${ROOT}/requirements.txt"
export PATH="${ROOT}/.venv/bin:${PATH}"

# ---- GCP APIs -----------------------------------------------------------
echo "==> Enabling APIs..."
gcloud services enable bigquery.googleapis.com storage.googleapis.com \
  --project="$PROJECT"
gcloud config set project "$PROJECT" >/dev/null

# ---- GCS bucket ---------------------------------------------------------
echo "==> Creating GCS landing bucket..."
gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="$PROJECT" --location="$REGION" --uniform-bucket-level-access

# ---- BigQuery datasets --------------------------------------------------
echo "==> Creating BigQuery datasets..."
for ds in "$RAW_DS" "$STAGING_DS" "$MART_DS"; do
  bq --location="$REGION" mk --dataset "${PROJECT}:${ds}" 2>/dev/null || true
done

# ---- Pipeline service account -------------------------------------------
echo "==> Configuring pipeline service account..."
if ! gcloud iam service-accounts describe "$SA_EMAIL" \
  --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="PAD lab pipeline" --project="$PROJECT"
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

# ---- dbt profile --------------------------------------------------------
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

# ---- Load FEC data ------------------------------------------------------
echo "==> Loading FEC contributions..."
(cd "$ROOT" && python -m loaders.load_contributions --max-records 1000 --save-sample)

echo "==> Loading FEC committees (from contributions)..."
(cd "$ROOT" && python -m loaders.load_committees --from-contributions --save-sample)

# ---- dbt ----------------------------------------------------------------
echo "==> Running dbt pipeline..."
(
  cd "${ROOT}/dbt"
  dbt deps
  dbt run
  dbt test
)

echo
echo "==> Setup complete."
echo
echo "    Raw contributions:  ${PROJECT}.${RAW_DS}.fec_contributions"
echo "    Raw committees:     ${PROJECT}.${RAW_DS}.fec_committees"
echo "    Staging:            ${PROJECT}.${STAGING_DS}.*"
echo "    Marts:              ${PROJECT}.${MART_DS}.*"
echo "    Landing zone:       gs://${BUCKET}/landing/"
echo "    Pipeline SA:        ${SA_EMAIL}"
echo "    Sample data:        data/samples/"
echo
echo "    Next: work through EXERCISES.md"
echo "    Cleanup: ./teardown.sh"
