#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[cage] $*"; }

apply_registry() {
  log "Deploying in-cluster private registry (cage-system)"
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/registry/registry.yaml"
  if [[ "${TARGET}" == "gke" ]]; then
    ${KUBECTL} apply -f "${ROOT}/environment/manifests/registry/registry-gke.yaml"
    # Replace emptyDir with PVC for image persistence across pod restarts.
    # shellcheck disable=SC2086
    ${KUBECTL} patch deployment cage-registry -n cage-system --type=json -p='[
      {"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"data","persistentVolumeClaim":{"claimName":"cage-registry-data"}}}
    ]' 2>/dev/null || true
    ${KUBECTL} rollout restart deployment/cage-registry -n cage-system
  fi
  bash "${ROOT}/environment/scripts/wait-registry.sh"
  if [[ "${TARGET}" == "gke" ]]; then
    bash "${ROOT}/environment/scripts/configure-gke-registry-pull.sh"
  fi
  TARGET="${TARGET}" KUBE_CONTEXT="${KUBE_CONTEXT}" \
    bash "${ROOT}/environment/scripts/port-forwards.sh" start-registry
}

apply_cage_manifests() {
  log "Applying cage manifests (proxy, RBAC, noise, network)"
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/proxy/"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/rbac/"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/noise/"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/network/"
}

wait_ready() {
  log "Waiting for egress-system pods"
  # shellcheck disable=SC2086
  ${KUBECTL} -n egress-system wait --for=condition=ready pod -l app=egress-proxy --timeout=300s
}

create_kind_cluster() {
  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    log "kind cluster ${CLUSTER_NAME} already exists"
    return
  fi
  log "Creating kind cluster ${CLUSTER_NAME}"
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT}/environment/kind/kind-config.yaml" --wait 300s
}

preload_kind_images() {
  log "Preloading infra images (host pull -> kind load)"
  bash "${ROOT}/environment/scripts/preload-infra.sh"
}

up_cage() {
  create_kind_cluster
  preload_kind_images
  apply_registry
  apply_cage_manifests
  wait_ready
  if [[ "${INSTALL_ADDONS:-0}" == "1" ]]; then
    bash "${ROOT}/environment/scripts/install-addons.sh"
  else
    log "Next: make mirror && make install-addons"
  fi
  log "Cage is up. Context: ${KUBE_CONTEXT}"
  log "Colima push:  localhost:5001  →  in-cluster ${REGISTRY_PULL_HOST}"
  log "Helm pull:    ${REGISTRY_INCLUSTER}/cap/*"
}

up_gke() {
  log "Provisioning dedicated GKE cluster (${GKE_CLUSTER_NAME} in ${GKE_PROJECT}/${GKE_REGION})"
  export KUBE_CONTEXT
  KUBE_CONTEXT="$(TARGET=gke bash "${ROOT}/environment/scripts/gke-cluster-lifecycle.sh" create)"
  # shellcheck source=environment/scripts/kube-env.sh
  source "${ROOT}/environment/scripts/kube-env.sh"

  log "Waiting for nodes"
  # shellcheck disable=SC2086
  ${KUBECTL} wait --for=condition=Ready node --all --timeout=600s

  apply_registry
  apply_cage_manifests
  wait_ready
  if [[ "${INSTALL_ADDONS:-0}" == "1" ]]; then
    bash "${ROOT}/environment/scripts/install-addons.sh"
  else
    log "Next: make mirror && make install-addons"
  fi

  log "GKE cage is up. Context: ${KUBE_CONTEXT}"
  log "Colima push:  localhost:5001  →  GKE registry ${REGISTRY_PULL_HOST}"
  log "Helm pull:    ${REGISTRY_INCLUSTER}/cap/*"
  log "Teardown: make down TARGET=gke"
}

main() {
  case "${TARGET}" in
    cage) up_cage ;;
    gke)  up_gke ;;
    *)
      log "Unknown TARGET=${TARGET} for up (use cage or gke)"
      exit 1
      ;;
  esac
}

main "$@"
