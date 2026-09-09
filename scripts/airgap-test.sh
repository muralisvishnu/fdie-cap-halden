#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
CAP_NAMESPACE="${CAP_NAMESPACE:-cap}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL="kubectl --context kind-${CLUSTER_NAME}"
PROOF_DIR="${ROOT}/proof"

log() { echo "[airgap] $*"; }

log "Switching egress proxy to full deny"
${KUBECTL} -n egress-system patch configmap egress-proxy-config --type merge -p '{
  "data": {
    "squid.conf": "http_port 3128\nacl SSL_ports port 443\nacl Safe_ports port 80 443 1025-65535\nacl CONNECT method CONNECT\nhttp_access deny !Safe_ports\nhttp_access deny CONNECT !SSL_ports\nhttp_access deny all\naccess_log stdio:/dev/stdout\ncache_log stdio:/dev/stderr\ncache deny all\n"
  }
}'
${KUBECTL} -n egress-system rollout restart deployment/egress-proxy
${KUBECTL} -n egress-system rollout status deployment/egress-proxy --timeout=120s

log "Probing Cap ingress while egress is fully denied"
sleep 5
if curl -fsS http://127.0.0.1:30080/ >/tmp/cap-airgap-body.html; then
  log "PASS: Cap still serving under full egress deny"
  cp /tmp/cap-airgap-body.html "${PROOF_DIR}/airgap-response.html"
  date -u +"%Y-%m-%dT%H:%M:%SZ Cap responded under full egress deny" | tee "${PROOF_DIR}/airgap-test.log"
else
  log "FAIL: Cap not reachable under full egress deny"
  bash "${ROOT}/scripts/restore-egress-proxy.sh"
  exit 1
fi

log "Restoring egress proxy allowlist"
bash "${ROOT}/scripts/restore-egress-proxy.sh"
