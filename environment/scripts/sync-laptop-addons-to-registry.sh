#!/usr/bin/env bash
# Laptop (Colima) → in-cluster private registry (localhost:5001 port-forward).
# No Docker Hub. Pulls linux/amd64 on GKE; uses local docker cache when present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
PREFIX="${REGISTRY_HOST}/halden"

log() { echo "[addon-sync] $*"; }

ensure_registry_push() {
  if curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
    return 0
  fi
  log "Starting registry port-forward"
  TARGET="${TARGET}" KUBE_CONTEXT="${KUBE_CONTEXT}" \
    bash "${ROOT}/environment/scripts/port-forwards.sh" start-registry
  sleep 2
  if ! curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
    log "FAIL: registry not reachable at ${REGISTRY_HOST} — run make up TARGET=${TARGET}"
    exit 1
  fi
}

tag_in_registry() {
  local name="$1"
  local tag="$2"
  curl -fsS "http://${REGISTRY_HOST}/v2/halden/${name}/tags/list" 2>/dev/null | grep -q "\"${tag}\""
}

push_addon() {
  local upstream="$1"
  local name="$2"
  local tag="$3"
  local dest="${PREFIX}/${name}:${tag}"

  if tag_in_registry "${name}" "${tag}"; then
    log "skip ${dest} (already in private registry)"
    return 0
  fi

  if docker image inspect "${upstream}" >/dev/null 2>&1; then
    log "local cache ${upstream} -> ${dest}"
    docker tag "${upstream}" "${dest}"
  else
    log "pull ${upstream} (platform=${IMAGE_PLATFORM}) -> ${dest}"
    docker pull --platform "${IMAGE_PLATFORM}" "${upstream}"
    docker tag "${upstream}" "${dest}"
  fi
  docker push "${dest}"
}

main() {
  if ! docker info >/dev/null 2>&1; then
    log "FAIL: Docker/Colima not running"
    exit 1
  fi

  log "Syncing addons to GKE/kind private registry (platform=${IMAGE_PLATFORM}, no Docker Hub)"
  log "Destination: ${PREFIX}/* -> in-cluster ${REGISTRY_PULL_HOST}/halden/*"
  ensure_registry_push

  push_addon quay.io/cilium/cilium:v1.20.1 cilium v1.20.1
  push_addon quay.io/cilium/operator-generic:v1.20.1 cilium-operator v1.20.1
  push_addon quay.io/cilium/cilium-envoy:v1.37.5-1786810558-766ccfb37260a43e9d228837aa84ce3faf9f64e7 cilium-envoy v1.20.1

  KV=v1.13.2
  push_addon ghcr.io/kyverno/kyvernopre:${KV} kyvernopre ${KV}
  push_addon ghcr.io/kyverno/kyverno:${KV} kyverno ${KV}
  push_addon ghcr.io/kyverno/background-controller:${KV} kyverno-background ${KV}
  push_addon ghcr.io/kyverno/cleanup-controller:${KV} kyverno-cleanup ${KV}
  push_addon ghcr.io/kyverno/reports-controller:${KV} kyverno-reports ${KV}
  push_addon registry.k8s.io/kubectl:v1.30.2 kubectl v1.30.2
  push_addon ghcr.io/kyverno/kyverno-cli:${KV} kyverno-cli ${KV}
  push_addon docker.io/library/busybox:1.35 busybox 1.35

  push_addon registry.k8s.io/ingress-nginx/controller:v1.15.1 ingress-controller v1.15.1
  push_addon registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9 ingress-certgen v1.6.9

  log "Done — Helm will pull from ${REGISTRY_INCLUSTER}/halden/*"
}

main "$@"
