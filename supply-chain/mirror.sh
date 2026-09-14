#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
ARTIFACTS="${ROOT}/supply-chain/artifacts"
BUILD_DIR="${ROOT}/.build/cap-src"
CAP_REPO="${CAP_REPO:-https://github.com/CapSoftware/Cap.git}"
CAP_REF="${CAP_REF:-main}"

TARGET="${TARGET:-cage}"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

log() { echo "[mirror] $*"; }

mkdir -p "${ARTIFACTS}" "${BUILD_DIR}"

ensure_registry_push() {
  if curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
    return 0
  fi
  log "Registry not reachable at ${REGISTRY_HOST} - starting port-forward (run make up first)"
  TARGET="${TARGET}" bash "${ROOT}/environment/scripts/port-forwards.sh" start-registry
  sleep 2
  if ! curl -fsS "http://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
    log "FAIL: cannot push to ${REGISTRY_HOST}. Run: make up TARGET=${TARGET}"
    exit 1
  fi
}

ensure_cap_source() {
  if [[ -d "${BUILD_DIR}/.git" ]]; then
    # Shallow fetch replaces origin/${CAP_REF}. checkout without reset leaves a
    # diverged local main (ahead/behind 1) and bun.lock that does not match npm.
    git -C "${BUILD_DIR}" fetch --depth 1 origin "${CAP_REF}"
    git -C "${BUILD_DIR}" checkout -B "${CAP_REF}" FETCH_HEAD
    git -C "${BUILD_DIR}" reset --hard FETCH_HEAD
  else
    git clone --depth 1 --branch "${CAP_REF}" "${CAP_REPO}" "${BUILD_DIR}"
  fi
  log "Cap source $(git -C "${BUILD_DIR}" rev-parse --short HEAD) (${CAP_REF})"
}

mirror_image() {
  local source="$1"
  local target="$2"
  local full_target="${REGISTRY_HOST}/${target}"
  log "Mirroring ${source} -> ${full_target} (platform=${IMAGE_PLATFORM})"
  docker pull --platform "${IMAGE_PLATFORM}" "${source}"
  docker tag "${source}" "${full_target}"
  docker push "${full_target}"
  docker inspect --format='{{index .RepoDigests 0}}' "${full_target}" \
    | tee "${ARTIFACTS}/$(echo "${target}" | tr '/:' '_').digest" || true
}

build_and_push() {
  local dockerfile="$1"
  local context="$2"
  local target="$3"
  local full_target="${REGISTRY_HOST}/${target}"
  log "Building ${full_target} from ${dockerfile} (platform=${IMAGE_PLATFORM})"
  docker build --platform "${IMAGE_PLATFORM}" -f "${dockerfile}" -t "${full_target}" "${context}"
  docker push "${full_target}"
}

host_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    *)             echo amd64 ;;
  esac
}

image_in_registry() {
  local repo="$1"
  local tag="$2"
  local body
  body="$(curl -fsS "http://${REGISTRY_HOST}/v2/${repo}/tags/list" 2>/dev/null || true)"
  [[ -n "${body}" ]] || return 1
  echo "${body}" | grep -q '"tags"' || return 1
  echo "${body}" | grep -q "\"${tag}\""
}

needs_gke_native_cap_build() {
  [[ "${TARGET}" == "gke" ]] \
    && [[ "${IMAGE_PLATFORM}" == "linux/amd64" ]] \
    && [[ "$(host_arch)" == "arm64" ]] \
    && [[ "${CAP_BUILD_ON_GKE:-0}" == "1" ]]
}

is_cross_platform_cap_build() {
  [[ "${IMAGE_PLATFORM}" == "linux/amd64" ]] && [[ "$(host_arch)" == "arm64" ]]
}

build_cap_images() {
  if [[ "${CAP_MIRROR_SKIP_BUILD:-0}" == "1" ]]; then
    log "CAP_MIRROR_SKIP_BUILD=1 — assuming cap/cap-web and cap/media-server already in registry"
    return 0
  fi

  if [[ "${CAP_MIRROR_FORCE:-0}" != "1" ]] \
    && image_in_registry cap/cap-web latest && image_in_registry cap/media-server latest \
    && [[ "${CAP_BUILD_ON_GKE:-0}" != "1" ]]; then
    log "cap/cap-web:latest and cap/media-server:latest already in registry — skipping build"
    return 0
  fi

  if needs_gke_native_cap_build; then
    log "Apple Silicon + GKE: building Cap on cluster via Kaniko (slow — opt-in with CAP_BUILD_ON_GKE=1)"
    bash "${ROOT}/environment/scripts/build-cap-on-gke.sh"
    return 0
  fi

  if is_cross_platform_cap_build && [[ "${TARGET}" == "gke" ]]; then
    log "FAIL: cannot build linux/amd64 Cap images on Apple Silicon (Docker/QEMU OOM on Next.js build)"
    log "  Fast options:"
    log "    1. make mirror TARGET=cage          # native arm64 build on Mac (~10 min), then use kind"
    log "    2. CAP_MIRROR_SKIP_BUILD=1          # if cap/* images already in GKE private registry"
    log "    3. CAP_BUILD_ON_GKE=1 make mirror   # slow Kaniko build on GKE (~30-45 min, not recommended)"
    log "    4. Run mirror on an amd64 Linux host or CI"
    exit 1
  fi

  ensure_cap_source
  build_and_push "${ROOT}/supply-chain/docker/Dockerfile.cap-web.bootstrap" "${BUILD_DIR}" "cap/cap-web:latest"
  build_and_push "${BUILD_DIR}/apps/media-server/Dockerfile.standalone" "${BUILD_DIR}/apps/media-server" "cap/media-server:latest"
}

main() {
  log "Bootstrap mirror into private registry ${REGISTRY_HOST} (TARGET=${TARGET})"
  log "Image platform: ${IMAGE_PLATFORM} (GKE requires linux/amd64; kind uses host arch)"
  log "Vendor laptop builds here - cluster only pulls from private registry after push"
  ensure_registry_push

  build_cap_images

  mirror_image "mysql:8.0" "cap/mysql:8.0"
  # Docker Hub minio/minio and minio/mc were pulled in 2025 (upstream is source-only).
  # Reuse the same Hub copies GKE Cap already pulls.
  mirror_image "docker.io/muralisvishnu/halden-cage:minio-latest" "cap/minio:latest"
  mirror_image "docker.io/muralisvishnu/halden-cage:minio-mc-latest" "cap/minio-mc:latest"

  log "Mirror complete. Digests in ${ARTIFACTS}/"
  if command -v syft >/dev/null 2>&1 || command -v cosign >/dev/null 2>&1; then
    bash "${ROOT}/supply-chain/attest.sh"
  else
    log "Optional: install syft/cosign and run: make attest"
  fi
}

main "$@"
