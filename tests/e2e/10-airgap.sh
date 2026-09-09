#!/usr/bin/env bash
# E2E: Cap serves while egress proxy is fully denied (reference cage only).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
setup_test_env

if [[ "${TARGET}" != "cage" ]]; then
  log "SKIP airgap e2e (requires reference kind cage + egress-system)"
  exit 0
fi

assert_cmd "airgap-test" bash "${ROOT}/scripts/airgap-test.sh"
assert_cmd "proof log exists" test -f "${ROOT}/proof/airgap-test.log"
report_summary
