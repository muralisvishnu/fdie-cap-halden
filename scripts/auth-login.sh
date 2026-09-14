#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

echo "Watching cap-web logs for email OTP (Ctrl+C to stop)"
# shellcheck disable=SC2086
${KUBECTL} -n "${CAP_NAMESPACE}" logs -f deploy/cap-web 2>/dev/null \
  | grep --line-buffered -E 'code|otp|OTP|magic|token' || true
