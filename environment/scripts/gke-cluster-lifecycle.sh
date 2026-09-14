#!/usr/bin/env bash
# Create or destroy the dedicated GKE cage cluster (terraform or gcloud fallback).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[gke-cluster] $*"; }

kube_context_name() {
  echo "gke_${GKE_PROJECT}_${GKE_REGION}_${GKE_CLUSTER_NAME}"
}

cluster_exists_gcloud() {
  gcloud container clusters describe "${GKE_CLUSTER_NAME}" \
    --region "${GKE_REGION}" \
    --project "${GKE_PROJECT}" >/dev/null 2>&1
}

create_with_gcloud() {
  if cluster_exists_gcloud; then
    log "Cluster ${GKE_CLUSTER_NAME} already exists in ${GKE_PROJECT}/${GKE_REGION}"
    return 0
  fi
  log "Creating cluster with gcloud (terraform not installed)"
  gcloud config set project "${GKE_PROJECT}" >/dev/null
  gcloud container clusters create "${GKE_CLUSTER_NAME}" \
    --project="${GKE_PROJECT}" \
    --region="${GKE_REGION}" \
    --num-nodes="${GKE_NODE_COUNT:-2}" \
    --machine-type="${GKE_MACHINE_TYPE:-e2-standard-4}" \
    --enable-network-policy \
    --tags=halden-cage-nodeport \
    --no-enable-autoupgrade \
    --no-enable-autorepair \
    --quiet
}

destroy_with_gcloud() {
  if ! cluster_exists_gcloud; then
    log "Cluster ${GKE_CLUSTER_NAME} not found — nothing to delete"
    return 0
  fi
  log "Deleting cluster with gcloud"
  gcloud container clusters delete "${GKE_CLUSTER_NAME}" \
    --region="${GKE_REGION}" \
    --project="${GKE_PROJECT}" \
    --quiet
}

create_with_terraform() {
  run_terraform -chdir="${TERRAFORM_GKE_DIR}" init -input=false
  run_terraform -chdir="${TERRAFORM_GKE_DIR}" apply -auto-approve -input=false \
    -var="project_id=${GKE_PROJECT}" \
    -var="region=${GKE_REGION}" \
    -var="cluster_name=${GKE_CLUSTER_NAME}"
}

destroy_with_terraform() {
  if [[ ! -f "${TERRAFORM_GKE_DIR}/terraform.tfstate" ]]; then
    log "No terraform state — skipping terraform destroy"
    return 0
  fi
  run_terraform -chdir="${TERRAFORM_GKE_DIR}" destroy -auto-approve -input=false \
    -var="project_id=${GKE_PROJECT}" \
    -var="region=${GKE_REGION}" \
    -var="cluster_name=${GKE_CLUSTER_NAME}" || true
}

terraform_bin() {
  if command -v terraform >/dev/null 2>&1; then
    command -v terraform
    return 0
  fi
  local bundled
  bundled="$(bash "${ROOT}/environment/scripts/ensure-terraform.sh" 2>/dev/null || true)"
  if [[ -n "${bundled}" && -x "${bundled}" ]]; then
    echo "${bundled}"
    return 0
  fi
  return 1
}

require_tooling() {
  if terraform_bin >/dev/null 2>&1; then
    echo terraform
    return 0
  fi
  if command -v gcloud >/dev/null 2>&1; then
    echo gcloud
    return 0
  fi
  log "FAIL: need terraform or gcloud for TARGET=gke"
  log "  bundled:  bash environment/scripts/ensure-terraform.sh"
  log "  gcloud:   https://cloud.google.com/sdk/docs/install"
  exit 1
}

run_terraform() {
  local tf
  tf="$(terraform_bin)"
  "${tf}" "$@"
}

fetch_credentials() {
  export KUBE_CONTEXT
  KUBE_CONTEXT="$(kube_context_name)"
  gcloud config set project "${GKE_PROJECT}" >/dev/null
  gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --region "${GKE_REGION}" \
    --project "${GKE_PROJECT}"
  export KUBE_CONTEXT
}

case "${1:-}" in
  create)
    case "$(require_tooling)" in
      terraform) create_with_terraform ;;
      gcloud)    create_with_gcloud ;;
    esac
    fetch_credentials
    echo "${KUBE_CONTEXT}"
    ;;
  destroy)
    case "$(require_tooling)" in
      terraform)
        destroy_with_terraform
        destroy_with_gcloud
        ;;
      gcloud)
        destroy_with_gcloud
        ;;
    esac
    ;;
  context)
    kube_context_name
    ;;
  *)
    echo "Usage: $0 {create|destroy|context}" >&2
    exit 1
    ;;
esac
