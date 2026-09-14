#!/usr/bin/env bash
# Install contract preflight — cage (kind), dedicated gke, or customer BYOC.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[preflight] $*"; }

# Push/mirror host uses localhost:5001 on both kind and gke (port-forward on gke).
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
  case "${TARGET}" in
    cage)
      if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
        log "FAIL: kind cluster ${CLUSTER_NAME} not found"
        exit 1
      fi
      ;;
    gke|byoc)
      log "Cluster check (${TARGET}) — context: ${KUBE_CONTEXT:-current}"
      # shellcheck disable=SC2086
      if ! ${KUBECTL} cluster-info >/dev/null 2>&1; then
        log "FAIL: kubectl cannot reach cluster"
        exit 1
      fi
      ;;
  esac
}

# GKE Cap pulls docker.io/muralisvishnu/halden-cage:* (HTTPS). Do not require
# localhost:5001/cap/* — kubelet cannot use that path, and another cluster
# will not have laptop extraPortMappings.
gke_uses_hub() {
  [[ "${TARGET}" == "gke" ]]
}

check_registry() {
  if gke_uses_hub; then
    log "GKE: skipping localhost:5001 catalog (Cap/addons pull from Docker Hub)"
    return 0
  fi
  local kind
  kind="$(registry_type)"
  log "Checking registry (${kind}) at ${REGISTRY_HOST}"

  case "${kind}" in
    local)
      if ! curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
        log "FAIL: bootstrap registry not reachable at ${REGISTRY_HOST}"
        if [[ "${TARGET}" == "gke" ]]; then
          log "  Hint: run 'make up TARGET=gke' (starts registry port-forward)"
        else
          log "  Hint: run 'make up'"
        fi
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

check_gke_hub_images() {
  local repo="${DOCKERHUB_ADDON_REPO:-docker.io/muralisvishnu/halden-cage}"
  local tag
  log "Checking Cap images on Docker Hub (${repo})"
  for tag in cap-web-latest media-server-latest mysql-8.0 minio-latest minio-mc-latest; do
    if image_exists_remote "${repo}:${tag}"; then
      log "  OK ${repo}:${tag}"
    else
      log "WARN: cannot verify ${repo}:${tag} (crane/docker missing or private); continuing"
    fi
  done
}

check_images() {
  if gke_uses_hub; then
    # shellcheck disable=SC2086
    if ${KUBECTL} -n "${CAP_NAMESPACE}" get deployment cap-web >/dev/null 2>&1; then
      log "GKE: Cap already installed — skip image catalog"
      return 0
    fi
    check_gke_hub_images
    return 0
  fi
  local repos tags i repo tag ref kind
  kind="$(registry_type)"

  if [[ "${PREFLIGHT_PROFILE}" == "cage" ]] || [[ "${TARGET}" == "cage" ]]; then
    repos=("${CAGE_IMAGE_REPOS[@]}")
    tags=("${CAGE_IMAGE_TAGS[@]}")
  else
    repos=("${REMOTE_IMAGE_REPOS[@]}")
    tags=("${REMOTE_IMAGE_TAGS[@]}")
  fi

  log "Checking Cap images in ${REGISTRY_HOST} (Tier 1: vendor build + import — see docs/image-supply-model.md)"

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
  # shellcheck disable=SC2086
  if ! ${KUBECTL} -n egress-system get svc egress-proxy >/dev/null 2>&1; then
    log "FAIL: egress proxy missing (run make up)"
    exit 1
  fi
}

check_cap_installed() {
  # shellcheck disable=SC2086
  if ${KUBECTL} -n "${CAP_NAMESPACE}" get deployment cap-web >/dev/null 2>&1; then
    log "Cap release detected in ${CAP_NAMESPACE}"
  else
    log "Cap not installed yet — registry/image checks only"
  fi
}

main() {
  export TARGET REGISTRY_HOST REGISTRY_INCLUSTER CAP_NAMESPACE PREFLIGHT_PROFILE KUBE_CONTEXT
  check_cluster
  check_registry
  check_images
  check_cage_policies
  check_cap_installed
  log "Preflight passed (${TARGET}/${PREFLIGHT_PROFILE})"

  if [[ "${PREFLIGHT_PROFILE}" == "cage" ]]; then
    log "Deploying outbound-only runner (post-mirror)"
    # shellcheck disable=SC2086
    if [[ "${TARGET}" == "gke" ]]; then
      sed "s|cage-registry.cage-system.svc.cluster.local:5000/cap/minio-mc:latest|docker.io/muralisvishnu/halden-cage:minio-mc-latest|g" \
        "${ROOT}/environment/manifests/runner/outbound-runner.yaml" \
        | sed "s|http://cage-registry.cage-system.svc.cluster.local:5000/v2/|http://cage-registry.cage-system.svc.cluster.local:5000/v2/|g" \
        | ${KUBECTL} apply -f -
      ${KUBECTL} -n "${CAP_NAMESPACE}" patch deployment outbound-runner --type=json \
        -p '[{"op":"add","path":"/spec/template/spec/imagePullSecrets","value":[{"name":"dockerhub-creds"}]}]' 2>/dev/null \
        || ${KUBECTL} -n "${CAP_NAMESPACE}" patch deployment outbound-runner --type=merge \
        -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"dockerhub-creds"}]}}}}'
    else
      ${KUBECTL} apply -f "${ROOT}/environment/manifests/runner/"
    fi
  fi
}

main "$@"
