#!/usr/bin/env bash
# Build and push the pipeline image via Cloud Build (no job execute).
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/run_job.sh" --build-only "$@"
