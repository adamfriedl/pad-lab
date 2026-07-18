#!/usr/bin/env bash
# Local entry: activate venv, then run the shared pipeline.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

if [[ ! -x "${ROOT}/.venv/bin/python" ]]; then
  echo "ERROR: venv not found — run ./setup.sh first." >&2
  exit 1
fi
export PATH="${ROOT}/.venv/bin:${PATH}"

exec "${ROOT}/scripts/pipeline.sh" "$@"
