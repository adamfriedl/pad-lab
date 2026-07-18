#!/usr/bin/env bash
# Cloud helpers: build pipeline image and/or execute the Cloud Run Job.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
JOB="pad-lab-pipeline"
TAG="${IMAGE_TAG:-latest}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/pad-lab/pipeline:${TAG}"

DO_BUILD=false
DO_RUN=false
DBT_FULL_REFRESH_DAILY="${DBT_FULL_REFRESH_DAILY:-false}"

usage() {
  cat <<EOF
Usage: ./scripts/run_job.sh [--build] [--run] [--build-only]

  --build       Build/push image via Cloud Build, then execute the job
  --run         Execute the Cloud Run Job (default if no flags)
  --build-only  Build/push image only (same as ./scripts/build_image.sh)

  Env: DBT_FULL_REFRESH_DAILY=true adds a one-shot env override on execute.
EOF
}

if [[ $# -eq 0 ]]; then
  DO_RUN=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      DO_BUILD=true
      DO_RUN=true
      shift
      ;;
    --run)
      DO_RUN=true
      shift
      ;;
    --build-only)
      DO_BUILD=true
      DO_RUN=false
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set GCP_PROJECT or gcloud config set project" >&2
  exit 1
fi

if $DO_BUILD; then
  echo "==> Cloud Build: push ${IMAGE}"
  gcloud builds submit "${ROOT}" \
    --project="$PROJECT" \
    --config="${ROOT}/cloudbuild.yaml" \
    --substitutions="_REGION=${REGION},_IMAGE=${IMAGE},_CACHE=${REGION}-docker.pkg.dev/${PROJECT}/pad-lab/pipeline:buildcache" \
    --timeout=1800s \
    --quiet
  echo "==> Image ready: ${IMAGE}"
fi

if $DO_RUN; then
  EXEC_ARGS=(
    run jobs execute "$JOB"
    --project="$PROJECT"
    --region="$REGION"
    --wait
  )
  if [[ "$DBT_FULL_REFRESH_DAILY" == "1" || "$DBT_FULL_REFRESH_DAILY" == "true" ]]; then
    echo "==> Execute ${JOB} (DBT_FULL_REFRESH_DAILY)"
    EXEC_ARGS+=(--update-env-vars=DBT_FULL_REFRESH_DAILY=1)
  else
    echo "==> Execute ${JOB} in ${PROJECT}/${REGION}"
  fi
  gcloud "${EXEC_ARGS[@]}"
fi
