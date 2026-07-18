#!/usr/bin/env bash
# Optional SQL freshness check — max(_loaded_at) on raw contributions.
# Exit 1 if older than FRESHNESS_HOURS (default 24).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
HOURS="${FRESHNESS_HOURS:-24}"

RESULT="$(bq query --use_legacy_sql=false --format=csv --quiet "
SELECT
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(_loaded_at), HOUR) AS hours_since_load,
  MAX(_loaded_at) AS last_loaded_at
FROM \`${PROJECT}.pad_lab_raw.fec_contributions\`
" | tail -n 1)"

HOURS_SINCE="$(echo "$RESULT" | cut -d, -f1)"
LAST="$(echo "$RESULT" | cut -d, -f2)"

echo "Last load: ${LAST} (${HOURS_SINCE}h ago)"

if [[ -z "$HOURS_SINCE" || "$HOURS_SINCE" == "null" ]]; then
  echo "ERROR: no rows in raw contributions" >&2
  exit 1
fi

if (( HOURS_SINCE > HOURS )); then
  echo "ERROR: raw table stale (> ${HOURS}h)" >&2
  exit 1
fi

echo "OK: fresh within ${HOURS}h"
