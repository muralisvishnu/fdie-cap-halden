#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"
# shellcheck source=environment/scripts/addon-helm-private-registry.sh
source "${ROOT}/environment/scripts/addon-helm-private-registry.sh"

log() { echo "[addons] $*"; }

USE_PRIVATE_REGISTRY_ADDONS="${USE_PRIVATE_REGISTRY_ADDONS:-0}"
USE_DOCKERHUB_ADDONS="${USE_DOCKERHUB_ADDONS:-0}"
# Helm --set extras; empty on TARGET=cage (images already in the kind node).
extra=()

load_helm_sets() {
  # $1 = cilium | kyverno | ingress
  HELM_SET_LINES=()
  local line chart="$1" output=""
  if [[ "${USE_DOCKERHUB_ADDONS}" == "1" ]]; then
    case "${chart}" in
      cilium)  output="$(cilium_dockerhub_sets)" ;;
      kyverno) output="$(kyverno_dockerhub_sets)" ;;
      ingress) output="$(ingress_dockerhub_sets)" ;;
      *) log "unknown chart ${chart}"; exit 1 ;;
    esac
  else
    case "${chart}" in
      cilium)  output="$(cilium_private_registry_sets)" ;;
      kyverno) output="$(kyverno_private_registry_sets)" ;;
      ingress) output="$(ingress_private_registry_sets)" ;;
      *) log "unknown chart ${chart}"; exit 1 ;;
    esac
  fi
  while IFS= read -r line; do
    if [[ -n "${line}" ]]; then
      line="${line#--set }"
      HELM_SET_LINES+=(--set "${line}")
    fi
  done <<EOF
${output}
EOF
}

# TARGET=gke: Hub --set list. TARGET=cage: extra stays empty (node-local images).
# macOS /bin/bash 3.2 + set -u: "${empty[@]}" is "unbound variable".
fill_helm_extra() {
  extra=()
  if [[ "${USE_PRIVATE_REGISTRY_ADDONS}" != "1" ]] && [[ "${USE_DOCKERHUB_ADDONS}" != "1" ]]; then
    return 0
  fi
  load_helm_sets "$1"
  extra=("${HELM_SET_LINES[@]+"${HELM_SET_LINES[@]}"}")
}

wait_for_cilium_crds() {
  log "Waiting for Cilium CRDs (helm --wait can finish before CRDs are Established)"
  local deadline=$((SECONDS + 300))
  while (( SECONDS < deadline )); do
    # shellcheck disable=SC2086
    if ${KUBECTL} get crd ciliumclusterwidenetworkpolicies.cilium.io &>/dev/null; then
      # shellcheck disable=SC2086
      ${KUBECTL} wait --for=condition=Established \
        crd/ciliumclusterwidenetworkpolicies.cilium.io --timeout=120s
      return 0
    fi
    sleep 3
  done
  log "ERROR: timed out waiting for ciliumclusterwidenetworkpolicies.cilium.io"
  return 1
}

install_cilium_cage() {
  log "Installing Cilium (kind chaining mode)"
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/cilium/kind-cni-chaining.yaml"
  helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
  helm repo update cilium >/dev/null
  fill_helm_extra cilium
  helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --kube-context "${HELM_CTX}" \
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
    --set operator.image.pullPolicy=IfNotPresent \
    ${extra[@]+"${extra[@]}"}
}

gke_pod_cidr() {
  if [[ -n "${GKE_POD_CIDR:-}" ]]; then
    echo "${GKE_POD_CIDR}"
    return 0
  fi
  local loc=(--region "${GKE_REGION}")
  [[ -n "${GKE_ZONE:-}" ]] && loc=(--zone "${GKE_ZONE}")
  gcloud container clusters describe "${GKE_CLUSTER_NAME}" \
    "${loc[@]}" --project "${GKE_PROJECT}" \
    --format='value(clusterIpv4Cidr)' 2>/dev/null
}

install_cilium_gke() {
  log "Installing Cilium (GKE native mode)"
  helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
  helm repo update cilium >/dev/null
  helm --kube-context "${HELM_CTX}" uninstall cilium -n kube-system >/dev/null 2>&1 || true
  local pod_cidr
  pod_cidr="$(gke_pod_cidr)"
  [[ -n "${pod_cidr}" ]] || { log "cannot determine GKE pod CIDR; set GKE_POD_CIDR"; exit 1; }
  log "Native routing CIDR ${pod_cidr}"
  fill_helm_extra cilium
  helm upgrade --install cilium cilium/cilium \
    --namespace kube-system \
    --kube-context "${HELM_CTX}" \
    --version 1.20.1 \
    --wait --timeout 8m \
    --set gke.enabled=true \
    --set kubeProxyReplacement=false \
    --set ipam.mode=kubernetes \
    --set ipv4NativeRoutingCIDR="${pod_cidr}" \
    --set cni.exclusive=false \
    --set cni.binPath=/home/kubernetes/bin \
    --set cgroup.autoMount.enabled=false \
    --set operator.replicas=1 \
    --set hubble.enabled=false \
    --set image.pullPolicy=IfNotPresent \
    --set operator.image.pullPolicy=IfNotPresent \
    ${extra[@]+"${extra[@]}"}
}

install_cilium() {
  case "${TARGET}" in
    gke) install_cilium_gke ;;
    *)   install_cilium_cage ;;
  esac
  wait_for_cilium_crds
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/cilium/default-deny-egress.yaml"
}

wait_for_kyverno() {
  log "Waiting for Kyverno admission webhook"
  # shellcheck disable=SC2086
  ${KUBECTL} wait --for=condition=Available \
    deployment/kyverno-admission-controller -n kyverno --timeout=300s
  local deadline=$((SECONDS + 120))
  while (( SECONDS < deadline )); do
    # shellcheck disable=SC2086
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
  fill_helm_extra kyverno
  helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno --create-namespace \
    --kube-context "${HELM_CTX}" \
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
    --set reportsController.image.pullPolicy=IfNotPresent \
    ${extra[@]+"${extra[@]}"}
  wait_for_kyverno
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f "${ROOT}/environment/manifests/kyverno/"
}

install_ingress() {
  log "Installing ingress-nginx (NodePort 30080)"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update ingress-nginx >/dev/null
  fill_helm_extra ingress
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --kube-context "${HELM_CTX}" \
    --version 4.15.1 \
    --wait --timeout 15m \
    --set controller.image.pullPolicy=IfNotPresent \
    --set controller.hostPort.enabled=false \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.admissionWebhooks.patch.image.pullPolicy=IfNotPresent \
    ${extra[@]+"${extra[@]}"}
}

preload_addons() {
  case "${TARGET}" in
    gke)
      if [[ "${USE_LOCAL_REGISTRY:-0}" == "1" ]]; then
        log "TARGET=gke: laptop -> in-cluster registry (platform=${IMAGE_PLATFORM})"
        bash "${ROOT}/environment/scripts/sync-laptop-addons-to-registry.sh"
        bash "${ROOT}/environment/scripts/configure-gke-registry-pull.sh"
        source "${ROOT}/environment/scripts/kube-env.sh"
        USE_PRIVATE_REGISTRY_ADDONS=1
      else
        log "TARGET=gke: Helm pulls addons from Docker Hub ${DOCKERHUB_ADDON_REPO:-docker.io/muralisvishnu/halden-cage}"
        bash "${ROOT}/environment/scripts/dockerhub-login.sh"
        USE_DOCKERHUB_ADDONS=1
      fi
      ;;
    cage)
      if [[ "${USE_LOCAL_REGISTRY:-0}" == "1" ]]; then
        log "TARGET=cage: laptop registry -> kind node (retagged to upstream names)"
        bash "${ROOT}/environment/scripts/sync-laptop-addons-to-registry.sh"
        bash "${ROOT}/environment/scripts/preload-from-local-registry.sh"
      else
        log "TARGET=cage: Docker Hub -> kind node (retagged to upstream names); Helm uses chart defaults"
        bash "${ROOT}/environment/scripts/preload-from-dockerhub.sh"
      fi
      ;;
    *)
      log "Unknown TARGET=${TARGET} (use cage or gke)"
      exit 1
      ;;
  esac
  export USE_PRIVATE_REGISTRY_ADDONS USE_DOCKERHUB_ADDONS
}

main() {
  preload_addons
  install_cilium
  install_kyverno
  install_ingress
  TARGET="${TARGET}" KUBE_CONTEXT="${KUBE_CONTEXT}" bash "${ROOT}/environment/scripts/port-forwards.sh" start-ingress
  log "Addons installed (private=${USE_PRIVATE_REGISTRY_ADDONS} dockerhub=${USE_DOCKERHUB_ADDONS})"
}

main "$@"
