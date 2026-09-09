#!/usr/bin/env bash
# Customer: load offline image tarballs and push to private registry (air-gap import).
set -euo pipefail

IMAGES_DIR="${1:-.}"
REGISTRY_HOST="${REGISTRY_HOST:?Set REGISTRY_HOST e.g. registry.halden.pharma/cap}"

# archive|dest_repository|dest_tag
IMPORT_SPECS=(
  "cap-web_latest.tar.gz|cap-web|latest"
  "media-server_latest.tar.gz|media-server|latest"
  "mysql_8.0.tar.gz|mysql|8.0"
  "minio_latest.tar.gz|minio|latest"
  "minio-mc_latest.tar.gz|minio-mc|latest"
)

log() { echo "[import-images] $*"; }

load_archive() {
  local path="$1"
  local output loaded
  output="$(gunzip -c "${path}" | docker load 2>&1)"
  loaded="$(echo "${output}" | sed -n 's/^Loaded image: //p' | tail -1)"
  if [[ -z "${loaded}" ]]; then
    loaded="$(echo "${output}" | grep -oE 'sha256:[a-f0-9]{64}' | tail -1)"
  fi
  if [[ -z "${loaded}" ]]; then
    log "FAIL: could not parse docker load output for ${path}"
    echo "${output}"
    exit 1
  fi
  echo "${loaded}"
}

import_one() {
  local archive="$1"
  local repo="$2"
  local tag="$3"
  local path="${IMAGES_DIR}/${archive}"
  local dest="${REGISTRY_HOST}/${repo}:${tag}"
  if [[ ! -f "${path}" ]]; then
    log "FAIL: missing ${path}"
    exit 1
  fi
  log "Load ${archive} -> push ${dest}"
  local loaded
  loaded="$(load_archive "${path}")"
  docker tag "${loaded}" "${dest}"
  docker push "${dest}"
}

main() {
  docker info >/dev/null
  IMAGES_DIR="$(cd "${IMAGES_DIR}" && pwd)"

  if [[ -f "${IMAGES_DIR}/SHA256SUMS" ]]; then
    log "Verifying SHA256SUMS"
    (cd "${IMAGES_DIR}" && (shasum -a 256 -c SHA256SUMS 2>/dev/null || sha256sum -c SHA256SUMS))
  fi

  log "Importing into ${REGISTRY_HOST}"
  local spec archive repo tag
  for spec in "${IMPORT_SPECS[@]}"; do
    IFS='|' read -r archive repo tag <<< "${spec}"
    import_one "${archive}" "${repo}" "${tag}"
  done

  log "Import complete. Run: TARGET=byoc REGISTRY_HOST=${REGISTRY_HOST} bash scripts/preflight.sh"
}

main "$@"
