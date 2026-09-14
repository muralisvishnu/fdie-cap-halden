#!/usr/bin/env bash
# Colima (vendor laptop) builds/pulls images → push to in-cluster private registry.
# On GKE: localhost:5001 is kubectl port-forward into cage-registry on the cluster.
# Helm and all cap-namespace pods pull from REGISTRY_INCLUSTER only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[sync] $*"; }

case "${TARGET}" in
  cage|gke) ;;
  *)
    log "FAIL: sync-colima-to-registry supports TARGET=cage|gke (got ${TARGET})"
    exit 1
    ;;
esac

if ! docker info >/dev/null 2>&1; then
  log "FAIL: Docker/Colima not running — run: make ensure-colima"
  exit 1
fi

if ! ${KUBECTL} -n cage-system get deployment cage-registry >/dev/null 2>&1; then
  log "FAIL: in-cluster registry not deployed — run: make up TARGET=${TARGET}"
  exit 1
fi

bash "${ROOT}/environment/scripts/wait-registry.sh"
TARGET="${TARGET}" KUBE_CONTEXT="${KUBE_CONTEXT}" \
  bash "${ROOT}/environment/scripts/port-forwards.sh" start-registry

log "Colima build platform: ${IMAGE_PLATFORM}"
log "Colima push ${REGISTRY_HOST} (port-forward) -> ${REGISTRY_PULL_HOST} (in-cluster private registry)"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}" TARGET="${TARGET}" \
  bash "${ROOT}/supply-chain/mirror.sh"

log "Verifying cap/cap-web tag via registry API (localhost push path)"
if curl -fsS "http://${REGISTRY_HOST}/v2/cap/cap-web/tags/list" 2>/dev/null | grep -q '"latest"'; then
  log "OK cap/cap-web:latest in private registry"
else
  log "FAIL: cap/cap-web:latest not in ${REGISTRY_HOST}"
  log "  Kind registry catalog is empty or Colima docker push did not hit kubectl :5001"
  log "  Retry: CAP_MIRROR_FORCE=1 make mirror TARGET=${TARGET}"
  log "  Do not run install-ingress until this check passes"
  exit 1
fi

log "Helm install will use: global.registry=${REGISTRY_INCLUSTER}"
log "Sync complete"
