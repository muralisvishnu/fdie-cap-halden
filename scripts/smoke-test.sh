#!/usr/bin/env bash
# Customer lab smoke test — run after helm install in their environment.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[smoke] $*"; }

log "Smoke test suite (includes preflight)"
bash "${ROOT}/tests/runner.sh" smoke

log "Smoke test complete"
