#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
setup_test_env
ensure_http_urls

assert_http_ok "${S3_URL}/minio/health/live" "Minio health"
report_summary
