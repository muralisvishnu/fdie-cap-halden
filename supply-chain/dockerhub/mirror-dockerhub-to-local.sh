#!/usr/bin/env bash
# Pull addon images from muralisvishnu/halden-cage on Docker Hub into localhost:5001.
set -euo pipefail

DOCKERHUB_USER="${DOCKERHUB_USER:-muralisvishnu}"
REPO="${DOCKERHUB_REPO:-halden-cage}"
LOCAL_REGISTRY="${LOCAL_REGISTRY:-localhost:5001}"
SRC="docker.io/${DOCKERHUB_USER}/${REPO}"

TAGS=(
  cilium-v1.20.1 cilium-operator-v1.20.1 cilium-envoy-v1.20.1
  kyvernopre-v1.13.2 kyverno-v1.13.2 kyverno-bg-v1.13.2 kyverno-cleanup-v1.13.2 kyverno-reports-v1.13.2
  ingress-controller-v1.15.1 ingress-certgen-v1.6.9
)

log() { echo "[dockerhub-to-local] $*"; }

main() {
  log "Ensure: docker login -u ${DOCKERHUB_USER}"
  docker start cage-registry >/dev/null 2>&1 || true

  for tag in "${TAGS[@]}"; do
    log "${SRC}:${tag} -> ${LOCAL_REGISTRY}/halden-cage:${tag}"
    docker pull "${SRC}:${tag}"
    docker tag "${SRC}:${tag}" "${LOCAL_REGISTRY}/halden-cage:${tag}"
    docker push "${LOCAL_REGISTRY}/halden-cage:${tag}"
  done

  log "Done — local registry has halden-cage addon tags"
}

main "$@"
