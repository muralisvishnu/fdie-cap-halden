#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
setup_test_env

assert_http_ok "${S3_URL}/minio/health/live" "Minio health"
report_summary
