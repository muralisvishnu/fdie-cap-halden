#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="kubectl --context kind-${CLUSTER_NAME}"

log() { echo "[egress-restore] $*"; }

log "Restoring baseline Squid allowlist"
${KUBECTL} apply -f "${ROOT}/environment/manifests/proxy/egress-proxy.yaml"
${KUBECTL} -n egress-system rollout restart deployment/egress-proxy
${KUBECTL} -n egress-system rollout status deployment/egress-proxy --timeout=120s
log "Egress proxy restored"
