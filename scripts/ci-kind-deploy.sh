#!/usr/bin/env bash
# CI/CD smoke test: kind cage + mirror + helm install + helm upgrade.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
REGISTRY_INCLUSTER="${REGISTRY_INCLUSTER:-localhost:5001}"
KUBECTL="kubectl --context kind-${CLUSTER_NAME}"
HELM="helm --kube-context kind-${CLUSTER_NAME}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"

log() { echo "[ci-kind] $*"; }

smoke_login() {
  curl -fsS "http://127.0.0.1:30080/login" >/dev/null
}

wait_for_smoke() {
  local label="$1"
  for _ in $(seq 1 36); do
    if smoke_login; then
      log "${label} smoke test passed"
      return 0
    fi
    sleep 5
  done
  log "FAIL: ${label} smoke test (http://127.0.0.1:30080/login)"
  ${KUBECTL} -n "${CAP_NAMESPACE}" get pods -o wide || true
  ${KUBECTL} -n "${CAP_NAMESPACE}" logs deployment/cap-web --tail=40 || true
  return 1
}

log "Bringing up kind cage (no Colima)"
bash "${ROOT}/environment/scripts/up.sh"

log "Mirroring Cap images into ${REGISTRY_HOST}"
REGISTRY_HOST="${REGISTRY_HOST}" bash "${ROOT}/supply-chain/mirror.sh"

log "Mirroring addon images (Cilium, Kyverno, ingress) into private registry"
REGISTRY="${REGISTRY_HOST}" bash "${ROOT}/supply-chain/mirror-addons-local.sh"

log "Installing Cilium, Kyverno, ingress-nginx from private registry"
USE_LOCAL_REGISTRY=1 bash "${ROOT}/environment/scripts/install-addons.sh"

log "Verifying policy stack is up"
${KUBECTL} -n kube-system wait --for=condition=ready pod -l k8s-app=cilium --timeout=180s
${KUBECTL} -n kyverno wait --for=condition=Available deployment/kyverno-admission-controller --timeout=180s

log "Helm install (ingress + network policies under Kyverno)"
CI_KIND=1 ALLOW_NON_THURSDAY=1 TARGET=cage USE_INGRESS=1 REGISTRY_HOST="${REGISTRY_INCLUSTER}" \
  bash "${ROOT}/scripts/install.sh"

wait_for_smoke "install"

log "Helm upgrade (ci.revision bump triggers rollout)"
${HELM} upgrade cap "${ROOT}/install/helm/cap" \
  --namespace "${CAP_NAMESPACE}" \
  --wait \
  --timeout 25m \
  -f "${ROOT}/install/helm/cap/values-cage.yaml" \
  -f "${ROOT}/install/helm/cap/values-cage-ingress-localhost.yaml" \
  -f "${ROOT}/install/helm/cap/values-ci.yaml" \
  --set global.registry="${REGISTRY_INCLUSTER}" \
  --set ci.revision=2

${KUBECTL} -n "${CAP_NAMESPACE}" rollout status deployment/cap-web --timeout=300s
wait_for_smoke "upgrade"

log "CD kind test complete"
