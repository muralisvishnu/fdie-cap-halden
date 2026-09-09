#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
REGISTRY_NAME="${REGISTRY_NAME:-cage-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"
KUBECTL="kubectl --context kind-${CLUSTER_NAME}"

log() { echo "[cage] $*"; }

ensure_registry() {
  if ! docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
    log "Starting local private registry on :${REGISTRY_PORT}"
    docker run -d --restart=always \
      -p "${REGISTRY_PORT}:5000" \
      --name "${REGISTRY_NAME}" \
      registry:2
  else
    docker start "${REGISTRY_NAME}" >/dev/null 2>&1 || true
  fi
}

create_cluster() {
  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    log "kind cluster ${CLUSTER_NAME} already exists"
    return
  fi
  log "Creating kind cluster ${CLUSTER_NAME}"
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT}/environment/kind/kind-config.yaml" --wait 300s
}

connect_registry_to_kind() {
  if docker inspect -f '{{json .NetworkSettings.Networks}}' "${REGISTRY_NAME}" | grep -q "kind"; then
    return
  fi
  log "Connecting ${REGISTRY_NAME} to kind network"
  docker network connect kind "${REGISTRY_NAME}" 2>/dev/null || true
}

preload_images() {
  log "Preloading infra images (host pull -> kind load)"
  bash "${ROOT}/environment/scripts/preload-infra.sh"
}

install_cilium() {
  if [[ "${INSTALL_ADDONS:-0}" == "1" ]]; then
    bash "${ROOT}/environment/scripts/install-addons.sh"
    return
  fi
  log "Skipping Cilium/Kyverno/Ingress (run: make install-addons)"
}

install_ingress() { :; }

install_kyverno() { :; }

apply_manifests() {
  log "Applying cage manifests"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/proxy/"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/rbac/"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/noise/"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/network/"
}

wait_ready() {
  log "Waiting for egress-system pods"
  ${KUBECTL} -n egress-system wait --for=condition=ready pod -l app=egress-proxy --timeout=180s
}

main() {
  ensure_registry
  create_cluster
  connect_registry_to_kind
  preload_images
  install_cilium
  install_ingress
  install_kyverno
  apply_manifests
  wait_ready
  log "Cage is up. Context: kind-${CLUSTER_NAME}"
  log "Private registry (bootstrap): localhost:${REGISTRY_PORT}"
  log "Private registry (in-cluster): cage-registry:5000"
}

main "$@"
