#!/usr/bin/env bash
# Vendor: export Cap images as offline tarballs for air-gap customer delivery.
# Prerequisite: make mirror (images in SOURCE_REGISTRY, default localhost:5001).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${ROOT}/install/helm/cap"
DIST="${ROOT}/dist"
VERSION="${RELEASE_VERSION:-$(awk '/^version:/ {print $2}' "${CHART_DIR}/Chart.yaml")}"
SOURCE_REGISTRY="${SOURCE_REGISTRY:-localhost:5001}"
PACK="halden-cap-images-${VERSION}"
OUT="${DIST}/${PACK}"

# source_ref|archive_filename|dest_repository|dest_tag
EXPORT_SPECS=(
  "cap/cap-web:latest|cap-web_latest.tar.gz|cap-web|latest"
  "cap/media-server:latest|media-server_latest.tar.gz|media-server|latest"
  "cap/mysql:8.0|mysql_8.0.tar.gz|mysql|8.0"
  "cap/minio:latest|minio_latest.tar.gz|minio|latest"
  "cap/minio-mc:latest|minio-mc_latest.tar.gz|minio-mc|latest"
)

log() { echo "[export-images] $*"; }

export_one() {
  local src_ref="$1"
  local archive="$2"
  local image="${SOURCE_REGISTRY}/${src_ref}"
  local path="${OUT}/${archive}"
  log "Export ${image} -> ${archive}"
  docker pull "${image}"
  docker save "${image}" | gzip -c > "${path}"
}

checksums() {
  if command -v shasum >/dev/null 2>&1; then
    (cd "${OUT}" && shasum -a 256 *.tar.gz > SHA256SUMS)
  else
    (cd "${OUT}" && sha256sum *.tar.gz > SHA256SUMS)
  fi
  log "Wrote ${OUT}/SHA256SUMS"
}

write_index() {
  local example_registry="${CUSTOMER_REGISTRY:-registry.halden.pharma/cap}"
  {
    echo "# Halden Cap offline image index v${VERSION}"
    echo "version: \"${VERSION}\""
    echo "example_customer_registry: ${example_registry}"
    echo "images:"
    local spec src archive repo tag
    for spec in "${EXPORT_SPECS[@]}"; do
      IFS='|' read -r src archive repo tag <<< "${spec}"
      echo "  - archive: ${archive}"
      echo "    repository: ${repo}"
      echo "    tag: ${tag}"
      echo "    source: ${SOURCE_REGISTRY}/${src}"
    done
  } > "${OUT}/INDEX.yaml"
}

main() {
  docker info >/dev/null
  rm -rf "${OUT}"
  mkdir -p "${OUT}"

  log "Exporting Cap images v${VERSION} from ${SOURCE_REGISTRY}"
  local spec src archive _repo _tag
  for spec in "${EXPORT_SPECS[@]}"; do
    IFS='|' read -r src archive _repo _tag <<< "${spec}"
    export_one "${src}" "${archive}"
  done

  write_index

  cat > "${OUT}/README.txt" <<EOF
Halden Cap offline image package ${VERSION}
==========================================

1. Verify checksums:
     cd ${PACK} && shasum -a 256 -c SHA256SUMS

2. Import into private registry (on customer bastion):
     export REGISTRY_HOST=registry.halden.pharma/cap
     bash import-release-images.sh .

3. Pair with bundle: halden-cap-bundle-${VERSION}.tar.gz

See docs/customer-image-delivery.md in the release bundle.
EOF

  cp "${ROOT}/supply-chain/import-release-images.sh" "${OUT}/import-release-images.sh"
  chmod +x "${OUT}/import-release-images.sh"

  checksums

  (
    cd "${DIST}"
    tar -czf "${PACK}.tar.gz" "${PACK}"
    if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "${PACK}.tar.gz" > "${PACK}.tar.gz.sha256"
    else
      sha256sum "${PACK}.tar.gz" > "${PACK}.tar.gz.sha256"
    fi
  )

  log "Offline images: ${DIST}/${PACK}.tar.gz"
  log "Checksum: ${DIST}/${PACK}.tar.gz.sha256"
}

main "$@"
