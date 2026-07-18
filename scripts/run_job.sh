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

if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set GCP_PROJECT or gcloud config set project" >&2
  exit 1
fi

echo "==> Cloud Build: ${IMAGE} → execute ${JOB} in ${PROJECT}/${REGION}"
gcloud builds submit "${ROOT}" \
  --project="$PROJECT" \
  --config="${ROOT}/cloudbuild.yaml" \
  --substitutions="_REGION=${REGION},_IMAGE=${IMAGE},_JOB=${JOB},_RUN_JOB=true" \
  --timeout=1800s \
  --quiet
