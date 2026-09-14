#!/usr/bin/env bash
# Pull addon images from docker.io/muralisvishnu/halden-cage and push into the
# in-cluster private registry via localhost:5001 (port-forward).
# GKE uses this path; kind uses preload-from-dockerhub.sh (ctr import) instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

DOCKERHUB_USER="${DOCKERHUB_USER:-muralisvishnu}"
DOCKERHUB_REPO="${DOCKERHUB_REPO:-halden-cage}"
DH_PREFIX="docker.io/${DOCKERHUB_USER}/${DOCKERHUB_REPO}"
PUSH_PREFIX="${REGISTRY_HOST}/halden"

log() { echo "[dockerhub-sync] $*"; }

ensure_registry_push() {
  if ! curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
    log "Registry not reachable at ${REGISTRY_HOST} — starting port-forward"
    TARGET="${TARGET}" KUBE_CONTEXT="${KUBE_CONTEXT}" \
      bash "${ROOT}/environment/scripts/port-forwards.sh" start-registry
    sleep 2
  fi
  if ! curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
    log "FAIL: cannot push to ${REGISTRY_HOST} — run 'make up TARGET=${TARGET}' first"
    exit 1
  fi
}

push_mapped() {
  local dh_tag="$1"
  local name="$2"
  local tag="$3"
  local src="${DH_PREFIX}:${dh_tag}"
  local dest="${PUSH_PREFIX}/${name}:${tag}"
  log "${src} -> ${dest}"
  docker pull --platform "${IMAGE_PLATFORM:-linux/amd64}" "${src}"
  docker tag "${src}" "${dest}"
  docker push "${dest}"
}

main() {
  log "Syncing Docker Hub relay ${DH_PREFIX} -> ${PUSH_PREFIX}/*"
  log "Ensure: docker login -u ${DOCKERHUB_USER}"
  ensure_registry_push

  push_mapped cilium-v1.20.1 cilium v1.20.1
  push_mapped cilium-operator-v1.20.1 cilium-operator v1.20.1
  push_mapped cilium-envoy-v1.20.1 cilium-envoy v1.20.1

  push_mapped kyvernopre-v1.13.2 kyvernopre v1.13.2
  push_mapped kyverno-v1.13.2 kyverno v1.13.2
  push_mapped kyverno-bg-v1.13.2 kyverno-background v1.13.2
  push_mapped kyverno-cleanup-v1.13.2 kyverno-cleanup v1.13.2
  push_mapped kyverno-reports-v1.13.2 kyverno-reports v1.13.2

  push_mapped ingress-controller-v1.15.1 ingress-controller v1.15.1
  push_mapped ingress-certgen-v1.6.9 ingress-certgen v1.6.9

  log "Done — cluster pulls addons from ${REGISTRY_INCLUSTER}/halden/*"
}

main "$@"
