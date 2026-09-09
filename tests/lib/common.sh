#!/usr/bin/env bash
# Shared helpers for Halden Cap smoke / e2e tests.

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log() { echo "[test] $*"; }

setup_test_env() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
  CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"
  TARGET="${TARGET:-cage}"
  REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
  PUBLIC_URL="${PUBLIC_URL:-http://127.0.0.1:30080}"
  S3_URL="${S3_URL:-http://127.0.0.1:30900}"
  PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-cage}"

  if [[ "${TARGET}" == "gke" || "${TARGET}" == "byoc" ]]; then
    KUBECTL="${KUBECTL:-kubectl}"
  else
    KUBECTL="${KUBECTL:-kubectl --context kind-${CLUSTER_NAME}}"
  fi
}

kubectl_cmd() {
  # shellcheck disable=SC2086
  ${KUBECTL} "$@"
}

assert_http_ok() {
  local url="$1"
  local label="${2:-${url}}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if curl -fsS "${url}" >/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log "PASS ${label}"
    return 0
  fi
  TESTS_FAILED=$((TESTS_FAILED + 1))
  log "FAIL ${label}"
  return 1
}

assert_cmd() {
  local label="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if "$@"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log "PASS ${label}"
    return 0
  fi
  TESTS_FAILED=$((TESTS_FAILED + 1))
  log "FAIL ${label}"
  return 1
}

report_summary() {
  log "Results: ${TESTS_PASSED}/${TESTS_RUN} passed (${TESTS_FAILED} failed)"
  [[ "${TESTS_FAILED}" -eq 0 ]]
}
