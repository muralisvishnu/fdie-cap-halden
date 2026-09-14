#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[cage] $*"; }

down_cage() {
  bash "${ROOT}/environment/scripts/port-forwards.sh" stop || true
  log "Deleting kind cluster ${CLUSTER_NAME}"
  kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
}

down_gke() {
  bash "${ROOT}/environment/scripts/port-forwards.sh" stop || true
  log "Destroying GKE cluster ${GKE_CLUSTER_NAME}"
  TARGET=gke bash "${ROOT}/environment/scripts/gke-cluster-lifecycle.sh" destroy || true
}

main() {
  case "${TARGET}" in
    cage) down_cage ;;
    gke)  down_gke ;;
    *)
      log "Unknown TARGET=${TARGET} for down (use cage or gke)"
      exit 1
      ;;
  esac
  log "Done"
}

main "$@"
