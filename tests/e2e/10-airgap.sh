#!/usr/bin/env bash
# E2E: Cap serves while egress proxy is fully denied (kind cage or dedicated GKE).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
setup_test_env

if ! kubectl_cmd -n egress-system get svc egress-proxy >/dev/null 2>&1; then
  log "SKIP airgap e2e (no egress-system on TARGET=${TARGET} context=${KUBE_CONTEXT})"
  exit 0
fi

ensure_http_urls

assert_cmd "airgap-test" env PUBLIC_URL="${PUBLIC_URL}" S3_URL="${S3_URL}" bash "${ROOT}/scripts/airgap-test.sh"
assert_cmd "proof log exists" test -f "${ROOT}/proof/airgap-test.log"
report_summary
