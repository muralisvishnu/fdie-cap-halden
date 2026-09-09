#!/usr/bin/env bash
# Self-hosted Cap prints the 6-digit OTP to cap-web logs when RESEND_API_KEY is unset.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"
EMAIL="${1:-test@halden.local}"

echo "Request a code at http://127.0.0.1:30080/login using: ${EMAIL}"
echo "Then watch for the verification code:"
echo ""
kubectl --context "kind-${CLUSTER_NAME}" -n "${CAP_NAMESPACE}" logs -f deploy/cap-web 2>/dev/null \
  | grep --line-buffered -E 'VERIFICATION CODE|Email:|Code:|🔢'
