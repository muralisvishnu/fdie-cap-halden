#!/usr/bin/env bash
# Shared helpers for Halden Cap smoke / e2e tests.

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log() { echo "[test] $*"; }

setup_test_env() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  # shellcheck source=environment/scripts/kube-env.sh
  source "${ROOT}/environment/scripts/kube-env.sh"

  PUBLIC_URL="${PUBLIC_URL:-http://127.0.0.1:30080}"
  S3_URL="${S3_URL:-http://127.0.0.1:30900}"
}

# kind hostPorts vs GKE kubectl port-forward. Call from HTTP tests, not preflight.
ensure_http_urls() {
  if [[ "${TARGET}" == "byoc" ]]; then
    log "TARGET=byoc PUBLIC_URL=${PUBLIC_URL} S3_URL=${S3_URL}"
    return 0
  fi
  eval "$(TARGET="${TARGET}" KUBE_CONTEXT="${KUBE_CONTEXT:-}" bash "${ROOT}/environment/scripts/port-forwards.sh" env-test)"
  log "TARGET=${TARGET} context=${KUBE_CONTEXT} PUBLIC_URL=${PUBLIC_URL} S3_URL=${S3_URL}"
}

kubectl_cmd() {
  # shellcheck disable=SC2086
  ${KUBECTL} "$@"
}

assert_http_ok() {
  local url="$1"
  local label="${2:-${url}}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if curl -fsS --max-time 10 "${url}" >/dev/null; then
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
