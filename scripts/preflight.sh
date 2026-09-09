#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
KUBECTL="kubectl --context kind-${CLUSTER_NAME}"

log() { echo "[preflight] $*"; }

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "FAIL: kind cluster ${CLUSTER_NAME} not found"
  exit 1
fi

log "Checking private registry endpoint"
if ! curl -fsS "http://${REGISTRY_HOST:-localhost:5001}/v2/" >/dev/null 2>&1; then
  log "FAIL: bootstrap registry not reachable at ${REGISTRY_HOST:-localhost:5001}"
  exit 1
fi

log "Checking mirrored images exist in bootstrap registry"
if ! ${KUBECTL} -n egress-system get svc egress-proxy >/dev/null 2>&1; then
  log "FAIL: egress proxy missing"
  exit 1
fi

log "Checking mirrored images exist in bootstrap registry"
for img in cap/cap-web:latest cap/media-server:latest cap/mysql:8.0 cap/minio:latest cap/minio-mc:latest; do
  repo="${img%:*}"
  tag="${img#*:}"
  if ! curl -fsS "http://localhost:5001/v2/${repo}/tags/list" | grep -q "\"${tag}\""; then
    log "FAIL: missing mirrored image localhost:5001/${img} — run 'make mirror'"
    exit 1
  fi
done

log "Preflight passed"

log "Deploying outbound-only runner (post-mirror)"
${KUBECTL} apply -f "${ROOT}/environment/manifests/runner/"
