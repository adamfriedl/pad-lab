#!/usr/bin/env bash
# Build and push the pipeline image via Cloud Build (cached layers from Artifact Registry).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
TAG="${IMAGE_TAG:-latest}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/pad-lab/pipeline:${TAG}"

if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set GCP_PROJECT or gcloud config set project" >&2
  exit 1
fi

echo "==> Cloud Build: push ${IMAGE} (build only, no job run)"
gcloud builds submit "${ROOT}" \
  --project="$PROJECT" \
  --config="${ROOT}/cloudbuild.yaml" \
  --substitutions="_REGION=${REGION},_IMAGE=${IMAGE},_RUN_JOB=false" \
  --timeout=1800s \
  --quiet

echo "==> Image ready: ${IMAGE}"
