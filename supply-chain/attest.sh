#!/usr/bin/env bash
# Generate SPDX SBOMs and cosign signatures for mirrored images (optional tools).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}"
ARTIFACTS="${ROOT}/supply-chain/artifacts"
IMAGES=(
  "cap/cap-web:latest"
  "cap/media-server:latest"
  "cap/mysql:8.0"
  "cap/minio:latest"
  "cap/minio-mc:latest"
)

log() { echo "[attest] $*"; }
mkdir -p "${ARTIFACTS}"

have() { command -v "$1" >/dev/null 2>&1; }

if ! have syft; then
  log "syft not installed — skip SBOM (brew install syft)"
else
  for img in "${IMAGES[@]}"; do
    ref="${REGISTRY_HOST}/${img}"
    out="${ARTIFACTS}/$(echo "${img}" | tr '/:' '_').spdx.json"
    log "SBOM ${ref} -> ${out}"
    syft "${ref}" -o spdx-json > "${out}"
  done
fi

if ! have cosign; then
  log "cosign not installed — skip signatures (brew install cosign)"
else
  if [[ -z "${COSIGN_PASSWORD:-}" ]]; then
    log "Set COSIGN_PASSWORD for keyless/ephemeral signing, or COSIGN_KEY for key-based"
  fi
  for img in "${IMAGES[@]}"; do
    ref="${REGISTRY_HOST}/${img}"
    log "Signing ${ref}"
    cosign sign --yes "${ref}" 2>/dev/null || log "WARN: cosign sign failed for ${ref}"
  done
fi

log "Artifacts in ${ARTIFACTS}/"
