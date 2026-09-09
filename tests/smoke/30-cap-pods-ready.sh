#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
setup_test_env

assert_cmd "cap-web ready" kubectl_cmd -n "${CAP_NAMESPACE}" rollout status deployment/cap-web --timeout=120s
assert_cmd "media-server ready" kubectl_cmd -n "${CAP_NAMESPACE}" rollout status deployment/cap-media-server --timeout=120s
report_summary
