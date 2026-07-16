#!/usr/bin/env bash
set -euo pipefail

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
BUCKET="pad-lab-${PROJECT}"
SA_NAME="pad-lab-pipeline"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "==> Tearing down PAD lab resources in ${PROJECT}"

for ds in pad_lab_mart pad_lab_staging pad_lab_raw; do
  echo "    Dropping dataset ${ds}..."
  bq rm -r -f -d "${PROJECT}:${ds}" 2>/dev/null || true
done

if gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT" >/dev/null 2>&1; then
  echo "    Deleting landing bucket gs://${BUCKET}..."
  gcloud storage rm --recursive "gs://${BUCKET}" --quiet || true
fi

if gcloud iam service-accounts describe "$SA_EMAIL" \
  --project="$PROJECT" >/dev/null 2>&1; then
  echo "    Deleting service account ${SA_EMAIL}..."
  gcloud iam service-accounts delete "$SA_EMAIL" \
    --project="$PROJECT" --quiet
fi

rm -f "${ROOT}/dbt/profiles.yml"

echo "==> Teardown complete."
