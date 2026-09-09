#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
CTX="kind-${CLUSTER_NAME}"
KUBECTL="kubectl --context ${CTX}"

log() { echo "[addons] $*"; }

wait_for_cilium_crds() {
  log "Waiting for Cilium CRDs (helm --wait can finish before CRDs are Established)"
  local deadline=$((SECONDS + 300))
  while (( SECONDS < deadline )); do
    if ${KUBECTL} get crd ciliumclusterwidenetworkpolicies.cilium.io &>/dev/null; then
      ${KUBECTL} wait --for=condition=Established \
        crd/ciliumclusterwidenetworkpolicies.cilium.io --timeout=120s
      return 0
    fi
    sleep 3
  done
  log "ERROR: timed out waiting for ciliumclusterwidenetworkpolicies.cilium.io"
  return 1
}

install_cilium() {
  log "Installing Cilium (chaining mode — no cluster recreate required)"
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/cilium/kind-cni-chaining.yaml"
  helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
  helm repo update cilium >/dev/null
  helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --kube-context "${CTX}" \
    --version 1.20.1 \
    --wait --timeout 15m \
    --set kubeProxyReplacement=false \
    --set cni.chainingMode=generic-veth \
    --set cni.customConf=true \
    --set cni.configMap=cilium-kind-cni-chaining \
    --set cni.exclusive=false \
    --set routingMode=native \
    --set enableIPv4Masquerade=false \
    --set operator.replicas=1 \
    --set hubble.enabled=false \
    --set image.pullPolicy=IfNotPresent \
    --set operator.image.pullPolicy=IfNotPresent
  wait_for_cilium_crds
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/cilium/default-deny-egress.yaml"
}

wait_for_kyverno() {
  log "Waiting for Kyverno admission webhook"
  ${KUBECTL} wait --for=condition=Available \
    deployment/kyverno-admission-controller -n kyverno --timeout=300s
  local deadline=$((SECONDS + 120))
  while (( SECONDS < deadline )); do
    if ${KUBECTL} get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg \
      &>/dev/null; then
      sleep 5
      return 0
    fi
    sleep 3
  done
  log "WARN: Kyverno webhook CRD not found; continuing"
}

install_kyverno() {
  log "Installing Kyverno"
  helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
  helm repo update kyverno >/dev/null
  helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno --create-namespace \
    --kube-context "${CTX}" \
    --version 3.3.4 \
    --wait --timeout 15m \
    --set admissionController.replicas=1 \
    --set backgroundController.replicas=1 \
    --set cleanupController.replicas=1 \
    --set reportsController.replicas=1 \
    --set admissionController.container.image.tag=v1.13.2 \
    --set backgroundController.image.tag=v1.13.2 \
    --set cleanupController.image.tag=v1.13.2 \
    --set reportsController.image.tag=v1.13.2 \
    --set admissionController.container.image.pullPolicy=IfNotPresent \
    --set backgroundController.image.pullPolicy=IfNotPresent \
    --set cleanupController.image.pullPolicy=IfNotPresent \
    --set reportsController.image.pullPolicy=IfNotPresent
  wait_for_kyverno
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/kyverno/"
}

install_ingress() {
  log "Installing ingress-nginx (NodePort 30080 -> cap.local)"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update ingress-nginx >/dev/null
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --kube-context "${CTX}" \
    --version 4.15.1 \
    --wait --timeout 15m \
    --set controller.image.pullPolicy=IfNotPresent \
    --set controller.hostPort.enabled=false \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.admissionWebhooks.patch.image.pullPolicy=IfNotPresent
}

main() {
  if [[ "${USE_LOCAL_REGISTRY:-0}" == "1" ]]; then
    bash "${ROOT}/environment/scripts/preload-from-local-registry.sh"
  elif [[ "${USE_DOCKERHUB_MIRROR:-0}" == "1" ]]; then
    bash "${ROOT}/environment/scripts/preload-from-dockerhub.sh"
  else
    bash "${ROOT}/environment/scripts/preload-addons.sh"
  fi
  install_cilium
  install_kyverno
  install_ingress
  log "Addons installed"
}

main "$@"
