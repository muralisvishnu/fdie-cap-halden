#!/usr/bin/env bash
# GKE: kubelet cannot pull from svc.cluster.local or HTTPS-only without node config.
# Fix: NodePort 30500 + localhost:30500 image refs + containerd HTTP + optional preload.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

GKE_REGISTRY_NODEPORT="${GKE_REGISTRY_NODEPORT:-30500}"
# Prefer ClusterIP: kubelet never sees NodePort on 127.0.0.1.
_gke_reg_ip="$(kubectl --context "${KUBE_CONTEXT}" -n cage-system get svc cage-registry -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
if [[ -n "${_gke_reg_ip}" ]]; then
  NODE_PULL_HOST="${_gke_reg_ip}:5000"
else
  NODE_PULL_HOST="localhost:${GKE_REGISTRY_NODEPORT}"
fi
unset _gke_reg_ip

log() { echo "[gke-registry] $*"; }

main() {
  if [[ "${TARGET}" != "gke" ]]; then
    return 0
  fi

  log "Patching cage-registry → NodePort ${GKE_REGISTRY_NODEPORT}"
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/registry/registry-gke-nodeport.yaml"

  log "Kubelet pull host: ${NODE_PULL_HOST} (HTTP via NodePort — same idea as kind localhost:5001)"
  log "Laptop push unchanged: ${REGISTRY_HOST} port-forward"

  # shellcheck disable=SC2086
  ${KUBECTL} get ns cap-build >/dev/null 2>&1 || ${KUBECTL} create ns cap-build
  # shellcheck disable=SC2086
  ${KUBECTL} label ns cap-build pod-security.kubernetes.io/enforce=privileged --overwrite

  # shellcheck disable=SC2086
  ${KUBECTL} -n cap-build create configmap cage-registry-pull \
    --from-literal=endpoint="${NODE_PULL_HOST}" \
    --from-literal=node_port="${GKE_REGISTRY_NODEPORT}" \
    --dry-run=client -o yaml | ${KUBECTL} apply -f -

  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/registry/containerd-insecure-registry.yaml"
  # shellcheck disable=SC2086
  ${KUBECTL} -n cap-build rollout status daemonset/containerd-insecure-registry --timeout=300s

  log "Preloading addon images onto nodes (ctr --plain-http)"
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/registry/preload-node-images.yaml"
  # shellcheck disable=SC2086
  ${KUBECTL} -n cap-build rollout status daemonset/preload-registry-images --timeout=600s

  export REGISTRY_PULL_HOST="${NODE_PULL_HOST}"
  export REGISTRY_INCLUSTER="${NODE_PULL_HOST}"
  log "Helm/images should use: ${REGISTRY_INCLUSTER}"
}

main "$@"
