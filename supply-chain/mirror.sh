#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
ARTIFACTS="${ROOT}/supply-chain/artifacts"
BUILD_DIR="${ROOT}/.build/cap-src"
CAP_REPO="${CAP_REPO:-https://github.com/CapSoftware/Cap.git}"
CAP_REF="${CAP_REF:-main}"

log() { echo "[mirror] $*"; }

mkdir -p "${ARTIFACTS}" "${BUILD_DIR}"

ensure_cap_source() {
  if [[ -d "${BUILD_DIR}/.git" ]]; then
    git -C "${BUILD_DIR}" fetch --depth 1 origin "${CAP_REF}"
    git -C "${BUILD_DIR}" checkout "${CAP_REF}"
  else
    git clone --depth 1 --branch "${CAP_REF}" "${CAP_REPO}" "${BUILD_DIR}"
  fi
}

mirror_image() {
  local source="$1"
  local target="$2"
  local full_target="${REGISTRY_HOST}/${target}"
  log "Mirroring ${source} -> ${full_target}"
  docker pull "${source}"
  docker tag "${source}" "${full_target}"
  docker push "${full_target}"
  docker inspect --format='{{index .RepoDigests 0}}' "${full_target}" | tee "${ARTIFACTS}/$(echo "${target}" | tr '/:' '_').digest" || true
}

build_and_push() {
  local dockerfile="$1"
  local context="$2"
  local target="$3"
  local full_target="${REGISTRY_HOST}/${target}"
  log "Building ${full_target} from ${dockerfile}"
  docker build -f "${dockerfile}" -t "${full_target}" "${context}"
  docker push "${full_target}"
}

main() {
  log "Bootstrap mirror into private registry ${REGISTRY_HOST}"
  ensure_cap_source

  build_and_push "${ROOT}/supply-chain/docker/Dockerfile.cap-web.bootstrap" "${BUILD_DIR}" "cap/cap-web:latest"
  build_and_push "${BUILD_DIR}/apps/media-server/Dockerfile.standalone" "${BUILD_DIR}/apps/media-server" "cap/media-server:latest"

  mirror_image "mysql:8.0" "cap/mysql:8.0"
  mirror_image "minio/minio:latest" "cap/minio:latest"
  mirror_image "minio/mc:latest" "cap/minio-mc:latest"

  log "Mirror complete. Digests in ${ARTIFACTS}/"
  if command -v syft >/dev/null 2>&1 || command -v cosign >/dev/null 2>&1; then
    bash "${ROOT}/supply-chain/attest.sh"
  else
    log "Optional: install syft/cosign and run: make attest"
  fi
}

main "$@"
