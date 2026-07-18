#!/usr/bin/env bash
# Cloud pipeline: rebuild image from local source (cached layers), then run the job.
# Same build+run path as the daily schedule (Scheduler pulls from GitHub instead).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
JOB="pad-lab-pipeline"
TAG="${IMAGE_TAG:-latest}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/pad-lab/pipeline:${TAG}"

DBT_FULL_REFRESH_DAILY="${DBT_FULL_REFRESH_DAILY:-false}"

if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set GCP_PROJECT or gcloud config set project" >&2
  exit 1
fi

if [[ "$DBT_FULL_REFRESH_DAILY" == "1" || "$DBT_FULL_REFRESH_DAILY" == "true" ]]; then
  echo "==> Cloud Build: ${IMAGE} → execute ${JOB} (daily_contributions full-refresh)"
else
  echo "==> Cloud Build: ${IMAGE} → execute ${JOB} in ${PROJECT}/${REGION}"
fi
gcloud builds submit "${ROOT}" \
  --project="$PROJECT" \
  --config="${ROOT}/cloudbuild.yaml" \
  --substitutions="_REGION=${REGION},_IMAGE=${IMAGE},_CACHE=${REGION}-docker.pkg.dev/${PROJECT}/pad-lab/pipeline:buildcache,_JOB=${JOB},_RUN_JOB=true,_DBT_FULL_REFRESH_DAILY=${DBT_FULL_REFRESH_DAILY}" \
  --timeout=1800s \
  --quiet
