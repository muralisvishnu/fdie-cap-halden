#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[install] $*"; }

case "${TARGET}" in
  cage)
    if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
      log "Cage not found; run 'make up' first"
      exit 1
    fi
    ;;
  gke)
    if ! ${KUBECTL} cluster-info >/dev/null 2>&1; then
      log "GKE cluster not reachable; run 'make up TARGET=gke' first"
      exit 1
    fi
    ;;
  byoc)
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

export TARGET REGISTRY_HOST REGISTRY_INCLUSTER CAP_NAMESPACE PREFLIGHT_PROFILE KUBE_CONTEXT
bash "${ROOT}/scripts/preflight.sh"

VALUES=()
if [[ "${TARGET}" == "byoc" ]]; then
  if [[ "${USE_GKE_INFRA_VALUES:-}" == "1" ]]; then
    # Legacy vendor path: shared gke_sre-play_us-west1_infra (make install-gke)
    VALUES=(-f "${ROOT}/install/helm/cap/values-gke.yaml")
    if [[ -f "${ROOT}/install/helm/cap/values-gke-infra.yaml" ]]; then
      VALUES+=(-f "${ROOT}/install/helm/cap/values-gke-infra.yaml")
    fi
  else
    VALUES=(-f "${VALUES_FILE:-${ROOT}/install/helm/cap/values-customer.example.yaml}")
  fi
  if [[ -n "${VALUES_EXTRA:-}" ]]; then
    # shellcheck disable=SC2206
    VALUES+=(${VALUES_EXTRA})
  fi
else
  # cage and gke dedicated cluster share the same Helm overlays
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
log "Image pull registry (in-cluster only): ${REGISTRY_INCLUSTER}"

HELM_EXTRA=()
if [[ "${TARGET}" == "gke" ]]; then
  # GKE COS kubelet speaks HTTPS to ClusterIP HTTP registries. Pull Cap from Docker Hub.
  bash "${ROOT}/environment/scripts/dockerhub-login.sh"
  HELM_EXTRA=(
    --set global.registry=docker.io/muralisvishnu
    --set global.imagePullPolicy=Always
    --set capWeb.image=halden-cage
    --set capWeb.tag=cap-web-latest
    --set mediaServer.image=halden-cage
    --set mediaServer.tag=media-server-latest
    --set mysql.image=halden-cage
    --set mysql.tag=mysql-8.0
    --set minio.image=halden-cage
    --set minio.tag=minio-latest
    --set minio.mcImage=halden-cage
    --set minio.mcTag=minio-mc-latest
    --set global.imagePullSecrets[0].name=dockerhub-creds
  )
  log "GKE Cap images: docker.io/muralisvishnu/halden-cage:<cap-*-tags>"
fi

# macOS /bin/bash 3.2 + set -u: empty "${HELM_EXTRA[@]}" is "unbound variable"
# shellcheck disable=SC2086
${HELM} upgrade --install cap "${ROOT}/install/helm/cap" \
  --namespace "${CAP_NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout 25m \
  "${VALUES[@]}" \
  --set global.registry="${REGISTRY_INCLUSTER}" \
  ${HELM_EXTRA[@]+"${HELM_EXTRA[@]}"}

log "Waiting for Cap pods"
# shellcheck disable=SC2086
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status deployment/cap-web --timeout=300s
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status deployment/cap-media-server --timeout=300s
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status statefulset/cap-mysql --timeout=300s
${KUBECTL} -n "${CAP_NAMESPACE}" rollout status statefulset/cap-minio --timeout=300s

if [[ "${TARGET}" == "byoc" ]]; then
  log "Install complete. Open publicUrl from ${VALUES_FILE:-values-customer.example.yaml} (set DNS / TLS first)"
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
