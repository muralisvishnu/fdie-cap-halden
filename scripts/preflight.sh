#!/usr/bin/env bash
# BYOC install contract: verify registry, images, and (optionally) cage policies before helm install.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
TARGET="${TARGET:-cage}"
PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-cage}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"

if [[ "${TARGET}" == "gke" || "${TARGET}" == "byoc" ]]; then
  KUBECTL="${KUBECTL:-kubectl}"
else
  KUBECTL="${KUBECTL:-kubectl --context kind-${CLUSTER_NAME}}"
fi

CAP_IMAGES=(
  cap/cap-web:latest
  cap/media-server:latest
  cap/mysql:8.0
  cap/minio:latest
  cap/minio-mc:latest
)

log() { echo "[preflight] $*"; }

check_cluster() {
  if [[ "${PREFLIGHT_PROFILE}" == "byoc" ]]; then
    log "BYOC profile — using current kubectl context"
    if ! ${KUBECTL} cluster-info >/dev/null 2>&1; then
      log "FAIL: kubectl cannot reach cluster"
      exit 1
    fi
    return
  fi

  if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    log "FAIL: kind cluster ${CLUSTER_NAME} not found"
    exit 1
  fi
}

check_registry() {
  log "Checking private registry at ${REGISTRY_HOST}"
  local registry_url="http://${REGISTRY_HOST}/v2/"
  if [[ "${REGISTRY_HOST}" == *":"* ]] && [[ "${REGISTRY_HOST}" != http* ]]; then
    registry_url="http://${REGISTRY_HOST}/v2/"
  fi
  if ! curl -fsS "${registry_url}" >/dev/null 2>&1; then
    log "FAIL: registry not reachable at ${REGISTRY_HOST}"
    exit 1
  fi
}

check_images() {
  log "Checking mirrored Cap images in ${REGISTRY_HOST}"
  for img in "${CAP_IMAGES[@]}"; do
    repo="${img%:*}"
    tag="${img#*:}"
    if ! curl -fsS "http://${REGISTRY_HOST}/v2/${repo}/tags/list" | grep -q "\"${tag}\""; then
      log "FAIL: missing ${REGISTRY_HOST}/${img} — run mirror into your private registry"
      exit 1
    fi
  done
}

check_cage_policies() {
  if [[ "${PREFLIGHT_PROFILE}" == "byoc" ]]; then
    log "Skipping cage-only policy checks (set PREFLIGHT_PROFILE=cage to enforce)"
    return
  fi
  if ! ${KUBECTL} -n egress-system get svc egress-proxy >/dev/null 2>&1; then
    log "FAIL: egress proxy missing (run make up)"
    exit 1
  fi
}

check_cap_installed() {
  if ${KUBECTL} -n "${CAP_NAMESPACE}" get deployment cap-web >/dev/null 2>&1; then
    log "Cap release detected in ${CAP_NAMESPACE}"
  else
    log "Cap not installed yet — image/registry checks only"
  fi
}

main() {
  check_cluster
  check_registry
  check_images
  check_cage_policies
  check_cap_installed
  log "Preflight passed"

  if [[ "${PREFLIGHT_PROFILE}" == "cage" ]]; then
    log "Deploying outbound-only runner (post-mirror)"
    ${KUBECTL} apply -f "${ROOT}/environment/manifests/runner/"
  fi
}

main "$@"
