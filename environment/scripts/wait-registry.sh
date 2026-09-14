#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[registry] $*"; }

log "Waiting for in-cluster private registry (cage-system/cage-registry)"
if ! ${KUBECTL} -n cage-system wait --for=condition=available deployment/cage-registry --timeout=300s; then
  log "FAIL: cage-registry deployment not available — recent events:"
  # shellcheck disable=SC2086
  ${KUBECTL} -n cage-system get events --sort-by=.lastTimestamp 2>/dev/null | tail -8
  log "Hint: kubectl -n cage-system describe deploy cage-registry"
  exit 1
fi
# shellcheck disable=SC2086
${KUBECTL} -n cage-system wait --for=condition=ready pod -l app=cage-registry --timeout=300s
log "In-cluster registry ready at ${REGISTRY_PULL_HOST}"
