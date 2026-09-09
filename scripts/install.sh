#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-cage}"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
KUBECTL="kubectl --context kind-${CLUSTER_NAME}"
HELM="helm --kube-context kind-${CLUSTER_NAME}"

log() { echo "[install] $*"; }

case "${TARGET}" in
  gke|byoc)
    CAP_NAMESPACE="${CAP_NAMESPACE:-halden-cap}"
    REGISTRY_HOST="${REGISTRY_HOST:-docker.io/muralisvishnu}"
    PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-gke}"
    if [[ -n "${KUBE_CONTEXT:-}" ]]; then
      KUBECTL="kubectl --context ${KUBE_CONTEXT}"
      HELM="helm --kube-context ${KUBE_CONTEXT}"
    else
      KUBECTL="kubectl"
      HELM="helm"
    fi
    ;;
  cage)
    REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
    PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-cage}"
    if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
      log "Cage not found; run 'make up' first"
      exit 1
    fi
    ;;
  *)
    log "Unknown TARGET=${TARGET} (use cage, gke, or byoc)"
    exit 1
    ;;
esac

bash "${ROOT}/governance/scripts/freeze-guard.sh" "$@" || {
  if [[ "${ALLOW_NON_THURSDAY:-}" == "1" ]]; then
    log "Non-Thursday install allowed via ALLOW_NON_THURSDAY=1"
  else
    exit 1
  fi
}

export TARGET REGISTRY_HOST CAP_NAMESPACE PREFLIGHT_PROFILE KUBE_CONTEXT
bash "${ROOT}/scripts/preflight.sh"

VALUES=()
if [[ "${TARGET}" == "gke" || "${TARGET}" == "byoc" ]]; then
  VALUES=(-f "${ROOT}/install/helm/cap/values-gke.yaml")
  if [[ "${USE_GKE_INFRA_VALUES:-}" == "1" ]] && [[ -f "${ROOT}/install/helm/cap/values-gke-infra.yaml" ]]; then
    VALUES+=(-f "${ROOT}/install/helm/cap/values-gke-infra.yaml")
  fi
  if [[ -n "${VALUES_EXTRA:-}" ]]; then
    # shellcheck disable=SC2206
    VALUES+=(${VALUES_EXTRA})
  fi
else
  VALUES=(-f "${ROOT}/install/helm/cap/values-cage.yaml")
  if [[ "${USE_INGRESS:-}" == "1" ]]; then
    if [[ "${INGRESS_USE_HOSTS:-}" == "1" ]]; then
      VALUES+=(-f "${ROOT}/install/helm/cap/values-cage-ingress.yaml")
    else
      VALUES+=(-f "${ROOT}/install/helm/cap/values-cage-ingress-localhost.yaml")
    fi
  fi
fi

log "Installing Cap via Helm (TARGET=${TARGET}) into namespace ${CAP_NAMESPACE}"
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

if [[ "${TARGET}" == "gke" || "${TARGET}" == "byoc" ]]; then
  log "Install complete. Open publicUrl from values-gke.yaml (set DNS / TLS first)"
  log "Smoke: TARGET=${TARGET} PUBLIC_URL=<url> bash scripts/smoke-test.sh"
elif [[ "${USE_INGRESS:-}" == "1" ]]; then
  if [[ "${INGRESS_USE_HOSTS:-}" == "1" ]]; then
    log "Install complete. Add to /etc/hosts: 127.0.0.1 cap.local s3.cap.local"
    log "Open http://cap.local:30080"
  else
    log "Install complete. Open http://127.0.0.1:30080 (no /etc/hosts required)"
  fi
else
  log "Install complete. Open http://localhost:30080"
fi
