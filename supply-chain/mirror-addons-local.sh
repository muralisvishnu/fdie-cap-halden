#!/usr/bin/env bash
# Mirror cage addon images into the local private registry (bootstrap host).
# Prerequisite: host can docker pull the source images (use hotspot / corp CA if quay/ghcr fail).
set -euo pipefail

REGISTRY="${REGISTRY:-localhost:5001}"
PREFIX="${REGISTRY}/halden"

log() { echo "[mirror-addons-local] $*"; }

mirror() {
  local source="$1"
  local name="$2"
  local tag="$3"
  local dest="${PREFIX}/${name}:${tag}"
  log "${source} -> ${dest}"
  docker pull "${source}"
  docker tag "${source}" "${dest}"
  docker push "${dest}"
}

main() {
  log "Mirroring addon images to ${PREFIX}/*"
  docker start cage-registry >/dev/null 2>&1 || true

  mirror quay.io/cilium/cilium:v1.20.1 cilium v1.20.1
  mirror quay.io/cilium/operator-generic:v1.20.1 cilium-operator v1.20.1
  mirror quay.io/cilium/cilium-envoy:v1.37.5-1786810558-766ccfb37260a43e9d228837aa84ce3faf9f64e7 cilium-envoy v1.20.1

  KV=v1.13.2
  mirror ghcr.io/kyverno/kyvernopre:${KV} kyvernopre ${KV}
  mirror ghcr.io/kyverno/kyverno:${KV} kyverno ${KV}
  mirror ghcr.io/kyverno/background-controller:${KV} kyverno-background ${KV}
  mirror ghcr.io/kyverno/cleanup-controller:${KV} kyverno-cleanup ${KV}
  mirror ghcr.io/kyverno/reports-controller:${KV} kyverno-reports ${KV}

  mirror registry.k8s.io/ingress-nginx/controller:v1.15.1 ingress-controller v1.15.1
  mirror registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9 ingress-certgen v1.6.9

  log "Done. Images in ${PREFIX}/"
  log "Next: USE_LOCAL_REGISTRY=1 make install-addons"
}

main "$@"
