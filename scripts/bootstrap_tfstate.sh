#!/usr/bin/env bash
# Create the GCS bucket used for Terraform remote state (chicken-and-egg).
set -euo pipefail

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
LOCATION="${TFSTATE_LOCATION:-US}"
BUCKET="pad-lab-${PROJECT}-tfstate"

if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set GCP_PROJECT or gcloud config set project" >&2
  exit 1
fi

echo "==> Ensuring Terraform state bucket gs://${BUCKET}"
if gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT" >/dev/null 2>&1; then
  echo "    Already exists."
else
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="$PROJECT" \
    --location="$LOCATION" \
    --uniform-bucket-level-access
  gcloud storage buckets update "gs://${BUCKET}" --versioning
  echo "    Created with object versioning."
fi

echo "    Use: (cd infra && terraform init -backend-config=\"bucket=${BUCKET}\")"
