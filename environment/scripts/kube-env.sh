#!/usr/bin/env bash
# Shared cluster context for cage (kind) and gke (dedicated Terraform cluster).
# Usage: ROOT must be set; then: source "${ROOT}/environment/scripts/kube-env.sh"

: "${ROOT:?ROOT must be set before sourcing kube-env.sh}"

TARGET="${TARGET:-cage}"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
REGISTRY_INCLUSTER="${REGISTRY_INCLUSTER:-}"
PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-}"

GKE_CLUSTER_NAME="${GKE_CLUSTER_NAME:-halden-cage-gke}"
GKE_PROJECT="${GKE_PROJECT:-sre-play}"
GKE_REGION="${GKE_REGION:-us-west1}"
GKE_ZONE="${GKE_ZONE:-}"
GKE_REGISTRY_NODEPORT="${GKE_REGISTRY_NODEPORT:-30500}"
TERRAFORM_GKE_DIR="${TERRAFORM_GKE_DIR:-${ROOT}/install/terraform/gke-cluster}"

REGISTRY_PULL_HOST="${REGISTRY_PULL_HOST:-cage-registry.cage-system.svc.cluster.local:5000}"

# GKE nodes are linux/amd64. kind on Apple Silicon uses linux/arm64.
resolve_image_platform() {
  if [[ -n "${IMAGE_PLATFORM:-}" ]]; then
    echo "${IMAGE_PLATFORM}"
    return 0
  fi
  case "${TARGET:-cage}" in
    gke) echo "linux/amd64" ;;
    *)
      case "$(uname -m)" in
        arm64|aarch64) echo "linux/arm64" ;;
        *)             echo "linux/amd64" ;;
      esac
      ;;
  esac
}
IMAGE_PLATFORM="${IMAGE_PLATFORM:-$(resolve_image_platform)}"

resolve_gke_context() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    return 0
  fi
  if [[ -z "${KUBE_CONTEXT:-}" ]] && [[ -f "${TERRAFORM_GKE_DIR}/terraform.tfstate" ]] \
    && command -v terraform >/dev/null 2>&1; then
    KUBE_CONTEXT="$(terraform -chdir="${TERRAFORM_GKE_DIR}" output -raw kube_context 2>/dev/null || true)"
  fi
  if [[ -z "${KUBE_CONTEXT:-}" ]]; then
    KUBE_CONTEXT="gke_${GKE_PROJECT}_${GKE_REGION}_${GKE_CLUSTER_NAME}"
  fi
}

case "${TARGET}" in
  gke)
    resolve_gke_context
    KUBECTL="${KUBECTL:-kubectl --context ${KUBE_CONTEXT}}"
    HELM="${HELM:-helm --kube-context ${KUBE_CONTEXT}}"
    HELM_CTX="${KUBE_CONTEXT}"
    # Laptop push stays REGISTRY_HOST=localhost:5001 (port-forward).
    # GKE kubelet cannot use localhost:30500 (NodePort is not on loopback) or
    # *.svc.cluster.local (no pod DNS). Pull via ClusterIP:5000 over HTTP.
    # Call kubectl directly (not ${KUBECTL}) so this works when sourced from zsh.
    _gke_reg_ip="$(kubectl --context "${KUBE_CONTEXT}" -n cage-system get svc cage-registry -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
    if [[ -n "${_gke_reg_ip}" ]]; then
      REGISTRY_INCLUSTER="${_gke_reg_ip}:5000"
      REGISTRY_PULL_HOST="${_gke_reg_ip}:5000"
    elif [[ -z "${REGISTRY_INCLUSTER:-}" ]] || [[ "${REGISTRY_INCLUSTER}" == localhost:* ]]; then
      REGISTRY_INCLUSTER="localhost:${GKE_REGISTRY_NODEPORT}"
      REGISTRY_PULL_HOST="localhost:${GKE_REGISTRY_NODEPORT}"
    fi
    unset _gke_reg_ip
    PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-cage}"
    ;;
  cage)
    KUBE_CONTEXT="${KUBE_CONTEXT:-kind-${CLUSTER_NAME}}"
    KUBECTL="${KUBECTL:-kubectl --context ${KUBE_CONTEXT}}"
    HELM="${HELM:-helm --kube-context ${KUBE_CONTEXT}}"
    HELM_CTX="${KUBE_CONTEXT}"
    REGISTRY_INCLUSTER="${REGISTRY_INCLUSTER:-${REGISTRY_PULL_HOST}}"
    PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-cage}"
    ;;
  byoc)
    CAP_NAMESPACE="${CAP_NAMESPACE:-halden-cap}"
    REGISTRY_HOST="${REGISTRY_HOST:-docker.io/muralisvishnu}"
    PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-byoc}"
    KUBECTL="${KUBECTL:-kubectl}"
    HELM="${HELM:-helm}"
    HELM_CTX="${KUBE_CONTEXT:-}"
    REGISTRY_INCLUSTER="${REGISTRY_INCLUSTER:-${REGISTRY_HOST}}"
    ;;
  *)
    echo "[kube-env] Unknown TARGET=${TARGET} (use cage, gke, or byoc)" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

export TARGET CLUSTER_NAME CAP_NAMESPACE REGISTRY_HOST REGISTRY_INCLUSTER
export PREFLIGHT_PROFILE KUBE_CONTEXT KUBECTL HELM HELM_CTX
export GKE_CLUSTER_NAME GKE_PROJECT GKE_REGION GKE_ZONE GKE_REGISTRY_NODEPORT TERRAFORM_GKE_DIR REGISTRY_PULL_HOST IMAGE_PLATFORM
