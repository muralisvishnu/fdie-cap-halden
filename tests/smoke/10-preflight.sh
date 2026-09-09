#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
setup_test_env

log "Running preflight (${PREFLIGHT_PROFILE})"
assert_cmd "preflight" bash "${ROOT}/scripts/preflight.sh"
report_summary
