#!/usr/bin/env bash
# Preload cage addon images onto the kind node via host pull -> ctr import.
# Works around in-cluster TLS pull failures (corporate MITM proxy on the laptop).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
NODE="${CLUSTER_NAME}-control-plane"

log() { echo "[preload-addons] $*"; }

import_image() {
  local image="$1"
  local pull_image="${image%%@*}"
  log "Import ${pull_image}"
  if ! docker pull "${pull_image}"; then
    log "WARN: host pull failed for ${pull_image}"
    return 1
  fi
  docker save "${pull_image}" | docker exec -i "${NODE}" ctr -n=k8s.io images import - >/dev/null
}

main() {
  if ! docker inspect "${NODE}" >/dev/null 2>&1; then
    log "kind node ${NODE} not found"
    exit 1
  fi

  local failed=0

  # Cilium (chaining mode — coexists with kindnet on existing clusters)
  import_image "quay.io/cilium/cilium:v1.20.1" || failed=1
  import_image "quay.io/cilium/operator-generic:v1.20.1" || failed=1
  import_image "quay.io/cilium/cilium-envoy:v1.37.5-1786810558-766ccfb37260a43e9d228837aa84ce3faf9f64e7" || failed=1

  # Kyverno
  local kv="v1.13.2"
  import_image "ghcr.io/kyverno/kyvernopre:${kv}" || failed=1
  import_image "ghcr.io/kyverno/kyverno:${kv}" || failed=1
  import_image "ghcr.io/kyverno/background-controller:${kv}" || failed=1
  import_image "ghcr.io/kyverno/cleanup-controller:${kv}" || failed=1
  import_image "ghcr.io/kyverno/reports-controller:${kv}" || failed=1
  import_image "bitnami/kubectl:1.30.2" || failed=1

  # ingress-nginx
  import_image "registry.k8s.io/ingress-nginx/controller:v1.15.1" || failed=1
  import_image "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9" || failed=1

  if [[ "${failed}" -ne 0 ]]; then
    log "Some images failed to preload — install may still fail until corp CA/admin access is fixed"
    exit 1
  fi

  log "Addon images preloaded"
}

main "$@"
