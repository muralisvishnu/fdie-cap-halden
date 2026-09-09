#!/usr/bin/env bash
# Run smoke or e2e test suites: bash tests/runner.sh [smoke|e2e|all]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="${1:-smoke}"
FAILED=0

log() { echo "[runner] $*"; }

run_suite() {
  local name="$1"
  local dir="${ROOT}/tests/${name}"
  if [[ ! -d "${dir}" ]]; then
    log "No suite directory: ${dir}"
    return 1
  fi
  log "=== Suite: ${name} ==="
  local tests=()
  shopt -s nullglob
  tests=("${dir}"/*.sh)
  shopt -u nullglob
  if [[ ${#tests[@]} -eq 0 ]]; then
    log "No tests in ${name}"
    return 0
  fi
  for test in "${tests[@]}"; do
    log "Running $(basename "${test}")"
    if ! bash "${test}"; then
      FAILED=1
    fi
  done
}

case "${SUITE}" in
  smoke|e2e)
    run_suite "${SUITE}"
    ;;
  all)
    run_suite smoke
    run_suite e2e
    ;;
  *)
    log "Unknown suite: ${SUITE} (use smoke, e2e, or all)"
    exit 1
    ;;
esac

if [[ "${FAILED}" -ne 0 ]]; then
  log "Suite ${SUITE} FAILED"
  exit 1
fi
log "Suite ${SUITE} passed"
