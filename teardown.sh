#!/usr/bin/env bash
# Destroy pad-lab GCP resources via Terraform.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
TFSTATE_BUCKET="pad-lab-${PROJECT}-tfstate"
TF_DIR="${ROOT}/infra"
DELETE_TFSTATE=false

usage() {
  cat <<EOF
Usage: ./teardown.sh [options]

  terraform destroy for pad-lab resources.

Options:
  --delete-tfstate  Also delete the Terraform state bucket
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-tfstate) DELETE_TFSTATE=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

echo "==> Tearing down PAD lab resources in ${PROJECT}"

if [[ -d "${TF_DIR}/.terraform" ]]; then
  (
    cd "$TF_DIR"
    terraform destroy -input=false -auto-approve
  )
else
  echo "    No terraform state initialized — falling back to legacy gcloud cleanup..."
  BUCKET="pad-lab-${PROJECT}"
  SA_PIPELINE="pad-lab-pipeline@${PROJECT}.iam.gserviceaccount.com"
  SA_SCHEDULER="pad-lab-scheduler@${PROJECT}.iam.gserviceaccount.com"

  for ds in pad_lab_mart pad_lab_staging pad_lab_raw; do
    bq rm -r -f -d "${PROJECT}:${ds}" 2>/dev/null || true
  done
  gcloud storage rm --recursive "gs://${BUCKET}" --quiet 2>/dev/null || true
  for sa in "$SA_PIPELINE" "$SA_SCHEDULER"; do
    gcloud iam service-accounts delete "$sa" --project="$PROJECT" --quiet 2>/dev/null || true
  done
fi

rm -f "${ROOT}/dbt/profiles.yml"

if $DELETE_TFSTATE; then
  echo "    Deleting Terraform state bucket gs://${TFSTATE_BUCKET}..."
  gcloud storage rm --recursive "gs://${TFSTATE_BUCKET}" --quiet 2>/dev/null || true
fi

echo "==> Teardown complete."
