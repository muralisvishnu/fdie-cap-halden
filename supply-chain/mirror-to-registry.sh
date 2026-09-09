#!/usr/bin/env bash
# Push Cap images built by mirror.sh to a remote registry (GKE / customer BYOC).
# Images are built in customer infra — this tags and pushes from the local bootstrap mirror.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REGISTRY="${SOURCE_REGISTRY:-localhost:5001}"
DEST_REGISTRY="${REGISTRY_HOST:?Set REGISTRY_HOST to destination, e.g. docker.io/muralisvishnu}"

log() { echo "[mirror-to-registry] $*"; }

# cage layout on SOURCE -> flat repos on DEST (matches values-gke.yaml)
push_image() {
  local src_repo="$1"
  local src_tag="$2"
  local dest_name="$3"
  local dest_tag="${4:-$src_tag}"
  local src="${SOURCE_REGISTRY}/${src_repo}:${src_tag}"
  local dest="${DEST_REGISTRY}/${dest_name}:${dest_tag}"
  log "${src} -> ${dest}"
  docker pull "${src}"
  docker tag "${src}" "${dest}"
  docker push "${dest}"
}

main() {
  log "Pushing Cap images from ${SOURCE_REGISTRY} to ${DEST_REGISTRY}"
  docker info >/dev/null

  push_image cap/cap-web latest cap-web latest
  push_image cap/media-server latest media-server latest
  push_image cap/mysql 8.0 mysql 8.0
  push_image cap/minio latest minio latest
  push_image cap/minio-mc latest minio-mc latest

  log "Done. Run: TARGET=gke REGISTRY_HOST=${DEST_REGISTRY} make preflight-gke"
}

main "$@"
