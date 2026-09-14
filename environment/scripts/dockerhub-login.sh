#!/usr/bin/env bash
# Login to Docker Hub with a PAT and create cluster imagePullSecrets.
# Never prints the token.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

DOCKERHUB_USER="${DOCKERHUB_USER:-muralisvishnu}"
DOCKERHUB_SERVER="${DOCKERHUB_SERVER:-https://index.docker.io/v1/}"
SECRET_NAME="${DOCKERHUB_PULL_SECRET:-dockerhub-creds}"
NAMESPACES=(kube-system kyverno ingress-nginx cap)

log() { echo "[dockerhub] $*"; }

login_laptop() {
  if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
    log "docker login as ${DOCKERHUB_USER} (password from DOCKERHUB_TOKEN, not printed)"
    printf '%s' "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USER}" --password-stdin
    return 0
  fi
  if docker info >/dev/null 2>&1 && grep -q "index.docker.io" "${HOME}/.docker/config.json" 2>/dev/null; then
    log "Using existing Docker Hub login in ~/.docker/config.json"
    return 0
  fi
  log "FAIL: set DOCKERHUB_TOKEN to a Docker Hub Personal Access Token"
  log "  Create: https://hub.docker.com/settings/security  (Read-only is enough to pull)"
  log "  Then:"
  log "    export DOCKERHUB_USER=${DOCKERHUB_USER}"
  log "    export DOCKERHUB_TOKEN"
  log "    make dockerhub-login TARGET=${TARGET}"
  exit 1
}

ensure_namespace() {
  local ns="$1"
  # shellcheck disable=SC2086
  ${KUBECTL} get ns "${ns}" >/dev/null 2>&1 || ${KUBECTL} create ns "${ns}"
}

apply_pull_secret() {
  local ns="$1"
  ensure_namespace "${ns}"
  if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
    # shellcheck disable=SC2086
    ${KUBECTL} -n "${ns}" create secret docker-registry "${SECRET_NAME}" \
      --docker-server="${DOCKERHUB_SERVER}" \
      --docker-username="${DOCKERHUB_USER}" \
      --docker-password="${DOCKERHUB_TOKEN}" \
      --docker-email="${DOCKERHUB_USER}@users.noreply.github.com" \
      --dry-run=client -o yaml | ${KUBECTL} apply -f -
  else
    # shellcheck disable=SC2086
    ${KUBECTL} -n "${ns}" create secret generic "${SECRET_NAME}" \
      --type=kubernetes.io/dockerconfigjson \
      --from-file=.dockerconfigjson="${HOME}/.docker/config.json" \
      --dry-run=client -o yaml | ${KUBECTL} apply -f -
  fi
  log "imagePullSecret ${SECRET_NAME} in ${ns}"
}

main() {
  if ! docker info >/dev/null 2>&1; then
    log "FAIL: Docker/Colima not running"
    exit 1
  fi
  login_laptop
  local ns
  for ns in "${NAMESPACES[@]}"; do
    apply_pull_secret "${ns}"
  done
  log "Done. Helm will use imagePullSecrets: ${SECRET_NAME}"
}

main "$@"
