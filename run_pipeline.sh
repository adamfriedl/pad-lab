#!/usr/bin/env bash
# Fetch FEC data, load to BigQuery, run dbt. Use after initial ./setup.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

MAX_RECORDS=1000
SAVE_SAMPLE=false

usage() {
  cat <<EOF
Usage: ./run_pipeline.sh [options]

  Fetch contributions and committees from the FEC API, load to BigQuery,
  then run dbt run + dbt test.

Options:
  --max-records N   Contribution fetch limit (default: 1000)
  --save-sample     Update data/samples/*.ndjson
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-records)
      MAX_RECORDS="$2"
      shift 2
      ;;
    --save-sample)
      SAVE_SAMPLE=true
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

if [[ ! -x "${ROOT}/.venv/bin/python" ]]; then
  echo "ERROR: venv not found — run ./setup.sh first." >&2
  exit 1
fi
export PATH="${ROOT}/.venv/bin:${PATH}"

CONTRIB_ARGS=(--max-records "$MAX_RECORDS")
COMMITTEE_ARGS=(--from-contributions)
if $SAVE_SAMPLE; then
  CONTRIB_ARGS+=(--save-sample)
  COMMITTEE_ARGS+=(--save-sample)
fi

echo "==> Loading FEC contributions..."
(cd "$ROOT" && python -m loaders.load_contributions "${CONTRIB_ARGS[@]}")

echo "==> Loading FEC committees (from contributions)..."
(cd "$ROOT" && python -m loaders.load_committees "${COMMITTEE_ARGS[@]}")

echo "==> Running dbt pipeline..."
(
  cd "${ROOT}/dbt"
  dbt run
  dbt test
)

echo
echo "==> Pipeline complete."
