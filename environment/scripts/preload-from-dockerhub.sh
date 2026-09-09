#!/usr/bin/env bash
# Pull mirrored images from private Docker Hub into the kind node.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
NODE="${CLUSTER_NAME}-control-plane"
DOCKERHUB_USER="${DOCKERHUB_USER:-muralisvishnu}"
REPO="${DOCKERHUB_REPO:-halden-cage}"
PREFIX="docker.io/${DOCKERHUB_USER}/${REPO}"

log() { echo "[dockerhub-preload] $*"; }

import_tag() {
  local tag="$1"
  local image="${PREFIX}:${tag}"
  log "Import ${image}"
  docker pull "${image}"
  docker save "${image}" | docker exec -i "${NODE}" ctr -n=k8s.io images import - >/dev/null
  # Retag to upstream names expected by helm charts
  case "${tag}" in
    cilium-v1.20.1)           docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" quay.io/cilium/cilium:v1.20.1 ;;
    cilium-operator-v1.20.1)  docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" quay.io/cilium/operator-generic:v1.20.1 ;;
    cilium-envoy-v1.20.1)     docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" quay.io/cilium/cilium-envoy:v1.37.5-1786810558-766ccfb37260a43e9d228837aa84ce3faf9f64e7 ;;
    kyvernopre-v1.13.2)       docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" ghcr.io/kyverno/kyvernopre:v1.13.2 ;;
    kyverno-v1.13.2)          docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" ghcr.io/kyverno/kyverno:v1.13.2 ;;
    kyverno-bg-v1.13.2)       docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" ghcr.io/kyverno/background-controller:v1.13.2 ;;
    kyverno-cleanup-v1.13.2)  docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" ghcr.io/kyverno/cleanup-controller:v1.13.2 ;;
    kyverno-reports-v1.13.2)  docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" ghcr.io/kyverno/reports-controller:v1.13.2 ;;
    ingress-controller-v1.15.1) docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" registry.k8s.io/ingress-nginx/controller:v1.15.1 ;;
    ingress-certgen-v1.6.9)   docker exec -i "${NODE}" ctr -n=k8s.io images tag "${image}" registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9 ;;
  esac
}

main() {
  if ! docker inspect "${NODE}" >/dev/null 2>&1; then
    log "kind node ${NODE} not found — run make up first"
    exit 1
  fi

  log "Using private Docker Hub repo ${PREFIX}"
  log "Ensure: docker login -u ${DOCKERHUB_USER}"

  for tag in \
    cilium-v1.20.1 cilium-operator-v1.20.1 cilium-envoy-v1.20.1 \
    kyvernopre-v1.13.2 kyverno-v1.13.2 kyverno-bg-v1.13.2 kyverno-cleanup-v1.13.2 kyverno-reports-v1.13.2 \
    ingress-controller-v1.15.1 ingress-certgen-v1.6.9; do
    import_tag "${tag}"
  done

  log "Done — run: make install-addons"
}

main "$@"
