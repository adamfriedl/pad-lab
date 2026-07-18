#!/usr/bin/env bash
# Bootstrap GCP via Terraform, install local Python/dbt deps, optionally load data.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${CLOUD_RUN_REGION:-us-central1}"
BQ_LOCATION="${GCP_REGION:-US}"
TFSTATE_BUCKET="pad-lab-${PROJECT}-tfstate"
SKIP_PIPELINE=false
SKIP_IMAGE=false

usage() {
  cat <<EOF
Usage: ./setup.sh [options]

  Bootstrap pad-lab infra with Terraform, install local deps, build the
  pipeline image, and optionally run an initial local data load.

Options:
  --skip-pipeline   Skip local ./run_pipeline.sh after apply
  --skip-image      Skip Cloud Build image push
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pipeline) SKIP_PIPELINE=true; shift ;;
    --skip-image) SKIP_IMAGE=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found on PATH." >&2
    exit 1
  }
}

echo "==> PAD Lab setup (Terraform)"
echo "    Project:     ${PROJECT}"
echo "    Region:      ${REGION}"
echo "    BQ location: ${BQ_LOCATION}"
echo "    FEC key:     $([ -n "${FEC_API_KEY:-}" ] && echo set || echo unset)"
echo

require_cmd gcloud
require_cmd bq
require_cmd terraform

if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "ERROR: set GCP_PROJECT or gcloud config set project" >&2
  exit 1
fi

# ---- Python venv (local loaders + dbt) ----------------------------------
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

# ---- Terraform state bucket + apply ------------------------------------
"${ROOT}/scripts/bootstrap_tfstate.sh"

TF_DIR="${ROOT}/infra"
TFVARS_FILE="${TF_DIR}/terraform.tfvars"

if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "==> Writing ${TFVARS_FILE} from environment..."
  {
    echo "project_id  = \"${PROJECT}\""
    echo "region      = \"${REGION}\""
    echo "bq_location = \"${BQ_LOCATION}\""
    if [[ -n "${ALERT_EMAIL:-}" ]]; then
      echo "alert_email = \"${ALERT_EMAIL}\""
    elif [[ -n "${DIGEST_EMAIL_TO:-}" ]]; then
      echo "alert_email = \"${DIGEST_EMAIL_TO}\""
    fi
    if [[ -n "${BILLING_ACCOUNT_ID:-}" ]]; then
      echo "billing_account_id = \"${BILLING_ACCOUNT_ID}\""
    fi
  } >"$TFVARS_FILE"
fi

export TF_VAR_project_id="$PROJECT"

TF_TARGETS=(
  -target=google_project_service.apis
  -target=google_storage_bucket.landing
  -target=google_bigquery_dataset.raw
  -target=google_bigquery_dataset.staging
  -target=google_bigquery_dataset.mart
  -target=google_service_account.pipeline
  -target=google_service_account.scheduler
  -target=google_project_iam_member.pipeline_bq_job_user
  -target=google_bigquery_dataset_iam_member.pipeline_raw
  -target=google_bigquery_dataset_iam_member.pipeline_staging
  -target=google_bigquery_dataset_iam_member.pipeline_mart
  -target=google_storage_bucket_iam_member.pipeline_landing
  -target=google_secret_manager_secret.fec_api_key
  -target=google_secret_manager_secret_iam_member.pipeline_fec_key
  -target=google_artifact_registry_repository.pad_lab
  -target=data.google_project.current
  -target=google_artifact_registry_repository_iam_member.cloudbuild_writer
  -target=google_project_service_identity.cloudscheduler
)

echo "==> terraform init / apply (foundation — AR repo, no Cloud Run yet)..."
(
  cd "$TF_DIR"
  terraform init -input=false -backend-config="bucket=${TFSTATE_BUCKET}"
  terraform apply -input=false -auto-approve "${TF_TARGETS[@]}"
)

# ---- Secret Manager version (out-of-band so TF never destroys the key) ----
if [[ -n "${FEC_API_KEY:-}" ]]; then
  echo "==> Adding FEC API key to Secret Manager..."
  printf '%s' "$FEC_API_KEY" | gcloud secrets versions add pad-lab-fec-api-key \
    --project="$PROJECT" \
    --data-file=-
else
  echo "==> WARNING: FEC_API_KEY unset — add a secret version before running the Cloud Run Job:"
  echo "    printf '%s' \"\$FEC_API_KEY\" | gcloud secrets versions add pad-lab-fec-api-key --data-file=-"
fi

# ---- Local dbt profile (laptop OAuth) ----------------------------------
echo "==> Writing dbt/profiles.yml (local oauth)..."
cat > "${ROOT}/dbt/profiles.yml" <<EOF
pad_lab:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: ${PROJECT}
      dataset: pad_lab_staging
      location: ${BQ_LOCATION}
      threads: 4
      timeout_seconds: 300
      priority: interactive
    prod:
      type: bigquery
      method: oauth
      project: ${PROJECT}
      dataset: pad_lab_staging
      location: ${BQ_LOCATION}
      threads: 4
      timeout_seconds: 600
      priority: interactive
EOF

(
  cd "${ROOT}/dbt"
  dbt deps
)

# ---- Container image (must exist before Cloud Run Job) -------------------
if ! $SKIP_IMAGE; then
  "${ROOT}/scripts/build_image.sh"
else
  echo "==> Skipping image build (--skip-image)"
  echo "    WARNING: Cloud Run Job apply will fail without an image in Artifact Registry."
fi

echo "==> terraform apply (Cloud Run Job, Scheduler, monitoring)..."
(
  cd "$TF_DIR"
  terraform apply -input=false -auto-approve
)

# ---- Initial local load ------------------------------------------------
if ! $SKIP_PIPELINE; then
  "${ROOT}/run_pipeline.sh" --save-sample
else
  echo "==> Skipping local pipeline (--skip-pipeline)"
fi

echo
echo "==> Setup complete."
terraform -chdir="$TF_DIR" output
echo
echo "    Manual Cloud Run Job:  ./scripts/run_job.sh"
echo "    Cleanup:               ./teardown.sh"
