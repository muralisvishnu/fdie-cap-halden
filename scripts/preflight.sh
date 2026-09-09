#!/usr/bin/env bash
# Install contract preflight — cage (kind), GKE, or customer BYOC.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-cage}"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"

# Default profile + namespace per target
case "${TARGET}" in
  gke|byoc)
    PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-gke}"
    CAP_NAMESPACE="${CAP_NAMESPACE:-halden-cap}"
    REGISTRY_HOST="${REGISTRY_HOST:-docker.io/muralisvishnu}"
    ;;
  *)
    PREFLIGHT_PROFILE="${PREFLIGHT_PROFILE:-cage}"
    REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
    ;;
esac

if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL="kubectl --context ${KUBE_CONTEXT}"
elif [[ "${TARGET}" == "gke" || "${TARGET}" == "byoc" ]]; then
  KUBECTL="${KUBECTL:-kubectl}"
else
  KUBECTL="${KUBECTL:-kubectl --context kind-${CLUSTER_NAME}}"
fi

log() { echo "[preflight] $*"; }

# Cage: cap/cap-web under localhost:5001. GKE/BYOC: cap-web under registry prefix.
CAGE_IMAGE_REPOS=(cap/cap-web cap/media-server cap/mysql cap/minio cap/minio-mc)
CAGE_IMAGE_TAGS=(latest latest 8.0 latest latest)
REMOTE_IMAGE_REPOS=(cap-web media-server mysql minio minio-mc)
REMOTE_IMAGE_TAGS=(latest latest 8.0 latest latest)

registry_type() {
  if [[ "${REGISTRY_HOST}" == localhost:* ]] || [[ "${REGISTRY_HOST}" == *:5001 ]]; then
    echo "local"
  elif [[ "${REGISTRY_HOST}" == docker.io/* ]] || [[ "${REGISTRY_HOST}" == index.docker.io* ]]; then
    echo "dockerhub"
  elif [[ "${REGISTRY_HOST}" == docker.io ]] || [[ "${REGISTRY_HOST}" == */muralisvishnu ]]; then
    echo "dockerhub"
  else
    echo "generic"
  fi
}

check_cluster() {
  case "${PREFLIGHT_PROFILE}" in
    cage)
      if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
        log "FAIL: kind cluster ${CLUSTER_NAME} not found"
        exit 1
      fi
      ;;
    gke|byoc)
      log "Cluster check (${TARGET}) — context: ${KUBE_CONTEXT:-current}"
      if ! ${KUBECTL} cluster-info >/dev/null 2>&1; then
        log "FAIL: kubectl cannot reach cluster"
        exit 1
      fi
      ;;
  esac
}

check_registry() {
  local kind
  kind="$(registry_type)"
  log "Checking registry (${kind}) at ${REGISTRY_HOST}"

  case "${kind}" in
    local)
      if ! curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
        log "FAIL: bootstrap registry not reachable at ${REGISTRY_HOST}"
        exit 1
      fi
      ;;
    dockerhub)
      if ! curl -fsS "https://index.docker.io/v2/" >/dev/null 2>&1; then
        log "FAIL: cannot reach Docker Hub registry API"
        exit 1
      fi
      ;;
    generic)
      if curl -fsS "https://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
        return 0
      fi
      if curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
        return 0
      fi
      log "FAIL: registry not reachable at ${REGISTRY_HOST}"
      exit 1
      ;;
  esac
}

image_ref() {
  local repo="$1"
  local tag="$2"
  printf '%s/%s:%s' "${REGISTRY_HOST}" "${repo}" "${tag}"
}

image_exists_local() {
  local repo="$1"
  local tag="$2"
  curl -fsS "http://${REGISTRY_HOST}/v2/${repo}/tags/list" | grep -q "\"${tag}\""
}

image_exists_remote() {
  local ref="$1"
  if command -v crane >/dev/null 2>&1; then
    crane digest "${ref}" >/dev/null 2>&1
    return $?
  fi
  if command -v docker >/dev/null 2>&1; then
    docker manifest inspect "${ref}" >/dev/null 2>&1
    return $?
  fi
  log "WARN: install crane or docker to verify remote image ${ref}"
  return 1
}

check_images() {
  local repos tags i repo tag ref kind
  kind="$(registry_type)"

  if [[ "${PREFLIGHT_PROFILE}" == "cage" ]]; then
    repos=("${CAGE_IMAGE_REPOS[@]}")
    tags=("${CAGE_IMAGE_TAGS[@]}")
  else
    repos=("${REMOTE_IMAGE_REPOS[@]}")
    tags=("${REMOTE_IMAGE_TAGS[@]}")
  fi

  log "Checking Cap images in ${REGISTRY_HOST} (built/mirrored in your infra — run supply-chain/mirror.sh)"

  for i in "${!repos[@]}"; do
    repo="${repos[$i]}"
    tag="${tags[$i]}"
    ref="$(image_ref "${repo}" "${tag}")"
    if [[ "${kind}" == "local" ]]; then
      if ! image_exists_local "${repo}" "${tag}"; then
        log "FAIL: missing ${ref} — run 'make mirror'"
        exit 1
      fi
    else
      if ! image_exists_remote "${ref}"; then
        log "FAIL: missing ${ref}"
        log "  Build/mirror in your infra: REGISTRY_HOST=${REGISTRY_HOST} bash supply-chain/mirror.sh"
        log "  Then tag/push to ${REGISTRY_HOST}/<image>:<tag> (see install/helm/cap/values-gke.yaml)"
        exit 1
      fi
    fi
    log "  OK ${ref}"
  done
}

check_cage_policies() {
  if [[ "${PREFLIGHT_PROFILE}" != "cage" ]]; then
    log "Skipping cage egress-proxy check (${PREFLIGHT_PROFILE})"
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
    log "Cap not installed yet — registry/image checks only"
  fi
}

main() {
  export TARGET REGISTRY_HOST CAP_NAMESPACE PREFLIGHT_PROFILE
  check_cluster
  check_registry
  check_images
  check_cage_policies
  check_cap_installed
  log "Preflight passed (${TARGET}/${PREFLIGHT_PROFILE})"

  if [[ "${PREFLIGHT_PROFILE}" == "cage" ]]; then
    log "Deploying outbound-only runner (post-mirror)"
    ${KUBECTL} apply -f "${ROOT}/environment/manifests/runner/"
  fi
}

main "$@"
