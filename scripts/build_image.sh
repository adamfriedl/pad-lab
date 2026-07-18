#!/usr/bin/env bash
# Build and push the pipeline image to Artifact Registry.
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

echo "==> Configuring Docker auth for Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

echo "==> Building and pushing ${IMAGE}"
gcloud builds submit "${ROOT}" \
  --project="$PROJECT" \
  --tag="$IMAGE" \
  --quiet

echo "==> Image ready: ${IMAGE}"
