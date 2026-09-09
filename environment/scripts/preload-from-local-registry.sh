#!/usr/bin/env bash
# Import addon images from localhost:5001 into kind, retagged to upstream names for helm.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
NODE="${CLUSTER_NAME}-control-plane"
REGISTRY="${REGISTRY:-localhost:5001}"
PREFIX="${REGISTRY}/halden"

log() { echo "[preload-local-registry] $*"; }

import_mirror() {
  local name="$1"
  local tag="$2"
  local upstream="$3"
  local local_image="${PREFIX}/${name}:${tag}"
  log "${local_image} -> ${upstream}"
  docker pull "${local_image}"
  docker save "${local_image}" | docker exec -i "${NODE}" ctr -n=k8s.io images import - >/dev/null
  docker exec -i "${NODE}" ctr -n=k8s.io images tag "${local_image}" "${upstream}" 2>/dev/null || true
}

main() {
  import_mirror cilium v1.20.1 quay.io/cilium/cilium:v1.20.1
  import_mirror cilium-operator v1.20.1 quay.io/cilium/operator-generic:v1.20.1
  import_mirror cilium-envoy v1.20.1 quay.io/cilium/cilium-envoy:v1.37.5-1786810558-766ccfb37260a43e9d228837aa84ce3faf9f64e7
  import_mirror kyvernopre v1.13.2 ghcr.io/kyverno/kyvernopre:v1.13.2
  import_mirror kyverno v1.13.2 ghcr.io/kyverno/kyverno:v1.13.2
  import_mirror kyverno-background v1.13.2 ghcr.io/kyverno/background-controller:v1.13.2
  import_mirror kyverno-cleanup v1.13.2 ghcr.io/kyverno/cleanup-controller:v1.13.2
  import_mirror kyverno-reports v1.13.2 ghcr.io/kyverno/reports-controller:v1.13.2
  import_mirror ingress-controller v1.15.1 registry.k8s.io/ingress-nginx/controller:v1.15.1
  import_mirror ingress-certgen v1.6.9 registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9
  log "Imported into kind-${CLUSTER_NAME}"
}

main "$@"
