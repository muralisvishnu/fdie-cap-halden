#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-cage}"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"
REGISTRY_HOST="${REGISTRY_HOST:-cage-registry:5000}"
KUBECTL="kubectl --context kind-${CLUSTER_NAME}"
HELM="helm --kube-context kind-${CLUSTER_NAME}"

log() { echo "[install] $*"; }

if [[ "${TARGET}" == "cage" ]]; then
  if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    log "Cage not found; run 'make up' first"
    exit 1
  fi
fi

bash "${ROOT}/governance/scripts/freeze-guard.sh" "$@" || {
  if [[ "${ALLOW_NON_THURSDAY:-}" == "1" ]]; then
    log "Non-Thursday install allowed via ALLOW_NON_THURSDAY=1"
  else
    exit 1
  fi
}

bash "${ROOT}/scripts/preflight.sh"

if [[ "${TARGET}" == "gke" ]]; then
  VALUES=(-f "${ROOT}/install/helm/cap/values-gke.yaml")
  KUBECTL="kubectl"
  HELM="helm"
  if [[ "${USE_INGRESS:-}" == "1" ]]; then
    VALUES+=(-f "${ROOT}/install/helm/cap/values-cage-ingress.yaml")
  fi
else
  VALUES=(-f "${ROOT}/install/helm/cap/values-cage.yaml")
  if [[ "${CI_KIND:-}" == "1" ]]; then
    VALUES+=(-f "${ROOT}/install/helm/cap/values-ci.yaml")
  fi
  if [[ "${USE_INGRESS:-}" == "1" ]]; then
    if [[ "${INGRESS_USE_HOSTS:-}" == "1" ]]; then
      VALUES+=(-f "${ROOT}/install/helm/cap/values-cage-ingress.yaml")
    else
      VALUES+=(-f "${ROOT}/install/helm/cap/values-cage-ingress-localhost.yaml")
    fi
  fi
fi

log "Installing Cap via Helm into namespace ${CAP_NAMESPACE}"
${HELM} upgrade --install cap "${ROOT}/install/helm/cap" \
  --namespace "${CAP_NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout 25m \
  "${VALUES[@]}" \
  --set global.registry="${REGISTRY_HOST}"

log "Waiting for Cap pods"
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status deployment/cap-web --timeout=300s
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status deployment/cap-media-server --timeout=300s
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status statefulset/cap-mysql --timeout=300s
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status statefulset/cap-minio --timeout=300s

if [[ "${USE_INGRESS:-}" == "1" ]]; then
  if [[ "${INGRESS_USE_HOSTS:-}" == "1" ]]; then
    log "Install complete. Add to /etc/hosts: 127.0.0.1 cap.local s3.cap.local"
    log "Open http://cap.local:30080"
  else
    log "Install complete. Open http://127.0.0.1:30080 (no /etc/hosts required)"
  fi
else
  log "Install complete. Open http://localhost:30080"
fi
