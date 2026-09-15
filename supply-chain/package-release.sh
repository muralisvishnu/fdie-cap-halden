#!/usr/bin/env bash
# Package the BYOC customer bundle: Helm chart, image manifest, SBOMs, docs, proof.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${ROOT}/install/helm/cap"
DIST="${ROOT}/dist"
VERSION="${RELEASE_VERSION:-$(awk '/^version:/ {print $2}' "${CHART_DIR}/Chart.yaml")}"
BUNDLE="halden-cap-bundle-${VERSION}"
STAGE="${DIST}/${BUNDLE}"

log() { echo "[package] $*"; }

rm -rf "${STAGE}"
mkdir -p "${STAGE}/chart" "${STAGE}/sbom" "${STAGE}/proof" "${STAGE}/scripts" "${STAGE}/manifests"

log "Helm package cap-${VERSION}.tgz"
helm package "${CHART_DIR}" --destination "${STAGE}/chart"

log "Image manifest"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:5001}" bash "${ROOT}/supply-chain/generate-image-manifest.sh" "${STAGE}/image-manifest.yaml"

if [[ -d "${ROOT}/supply-chain/artifacts" ]]; then
  cp "${ROOT}"/supply-chain/artifacts/*.digest "${STAGE}/" 2>/dev/null || true
  cp "${ROOT}"/supply-chain/artifacts/*.spdx.json "${STAGE}/sbom/" 2>/dev/null || true
fi

log "Policy + environment manifests"
cp -R "${ROOT}/environment/manifests/kyverno" "${STAGE}/manifests/"
cp -R "${ROOT}/environment/manifests/cilium" "${STAGE}/manifests/"
cp -R "${ROOT}/environment/manifests/proxy" "${STAGE}/manifests/"
cp -R "${ROOT}/environment/manifests/network" "${STAGE}/manifests/"
cp -R "${ROOT}/environment/manifests/rbac" "${STAGE}/manifests/"

log "Customer scripts and docs"
cp "${ROOT}/scripts/install.sh" "${ROOT}/scripts/preflight.sh" "${ROOT}/scripts/smoke-test.sh" "${STAGE}/scripts/"
cp "${ROOT}/scripts/verify-proof.sh" "${STAGE}/scripts/" 2>/dev/null || true
mkdir -p "${STAGE}/docs"
cp "${ROOT}/AGENTS.md" "${STAGE}/"
cp "${ROOT}/docs/customer-install.md" "${ROOT}/docs/install-contract.md" "${ROOT}/docs/ai-protocol.md" \
  "${ROOT}/docs/image-supply-model.md" "${ROOT}/docs/customer-image-delivery.md" "${STAGE}/docs/"
cp "${ROOT}/supply-chain/import-release-images.sh" "${STAGE}/scripts/"
cp "${ROOT}/install/helm/cap/values-customer.example.yaml" "${STAGE}/values-customer.example.yaml"
cp "${ROOT}/supply-chain/images.yaml" "${STAGE}/"
cp "${ROOT}/proof/security-checklist.md" "${STAGE}/proof/" 2>/dev/null || true
cp "${ROOT}/proof/"*.log "${ROOT}/proof/constraints.md" "${ROOT}/proof/allowlist.yaml" "${STAGE}/proof/" 2>/dev/null || true

log "Test framework (customer lab smoke)"
mkdir -p "${STAGE}/tests"
cp -R "${ROOT}/tests/lib" "${ROOT}/tests/smoke" "${ROOT}/tests/e2e" "${ROOT}/tests/runner.sh" "${ROOT}/tests/README.md" "${STAGE}/tests/"

cat > "${STAGE}/README-BUNDLE.md" <<EOF
# Halden Cap BYOC bundle ${VERSION}

Customer handoff package. AI entry: \`AGENTS.md\`. Install contract: \`docs/customer-install.md\`.

## Contents

| Path | Purpose |
|------|---------|
| \`chart/cap-${VERSION}.tgz\` | Helm chart |
| \`image-manifest.yaml\` | Pinned images (populate digests after mirror) |
| \`values-customer.example.yaml\` | Required values template |
| \`manifests/\` | Kyverno, Cilium, egress proxy, RBAC |
| \`AGENTS.md\` | AI assistant entry point |
| \`docs/ai-protocol.md\` | Step-by-step AI playbooks |
| \`scripts/\` | install, preflight, smoke-test |
| \`tests/\` | Smoke + e2e test framework |
| \`proof/\` | Air-gap proof + security checklist |
| \`sbom/\` | SPDX SBOMs (when \`make attest\` was run) |
| \`docs/customer-image-delivery.md\` | Air-gap SFTP/USB/DMZ playbook |
| \`scripts/import-release-images.sh\` | Load offline image tarballs |

Images tarball (separate): \`halden-cap-images-${VERSION}.tar.gz\` from \`make export-release-images\`

## Quick lab smoke (after install)

\`\`\`bash
export TARGET=byoc
export REGISTRY_HOST=<your-private-registry>
export PUBLIC_URL=https://cap.example.com
bash scripts/preflight.sh
bash scripts/smoke-test.sh
\`\`\`
EOF

(
  cd "${DIST}"
  tar -czf "${BUNDLE}.tar.gz" "${BUNDLE}"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${BUNDLE}.tar.gz" > "${BUNDLE}.tar.gz.sha256"
  else
    sha256sum "${BUNDLE}.tar.gz" > "${BUNDLE}.tar.gz.sha256"
  fi
)

log "Bundle: ${DIST}/${BUNDLE}.tar.gz"
log "Checksum: ${DIST}/${BUNDLE}.tar.gz.sha256"
