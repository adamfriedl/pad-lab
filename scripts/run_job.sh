#!/usr/bin/env bash
# Trigger pad-lab-pipeline on Cloud Run (prod path: container, pipeline SA, Secret Manager).
# Blocks until the execution finishes (--wait). Safe for initial load — watermark bootstraps
# when raw is empty.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
JOB="pad-lab-pipeline"

echo "==> Executing Cloud Run Job ${JOB} in ${PROJECT}/${REGION}"
gcloud run jobs execute "$JOB" \
  --project="$PROJECT" \
  --region="$REGION" \
  --wait
