#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[egress] $*"; }

log "Restoring egress proxy allowlist"
# shellcheck disable=SC2086
${KUBECTL} apply -f "${ROOT}/environment/manifests/proxy/"
# shellcheck disable=SC2086
${KUBECTL} -n egress-system rollout restart deployment/egress-proxy
# shellcheck disable=SC2086
${KUBECTL} -n egress-system rollout status deployment/egress-proxy --timeout=120s
