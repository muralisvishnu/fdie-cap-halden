#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

PROOF_DIR="${ROOT}/proof"
mkdir -p "${PROOF_DIR}"

log() { echo "[airgap] $*"; }

# shellcheck disable=SC2086
if ! ${KUBECTL} -n egress-system get svc egress-proxy >/dev/null 2>&1; then
  log "FAIL: egress-system/egress-proxy missing (TARGET=${TARGET} context=${KUBE_CONTEXT:-})"
  log "  Dedicated cage/GKE: run make up TARGET=${TARGET}"
  exit 1
fi

if [[ -z "${PUBLIC_URL:-}" ]]; then
  eval "$(TARGET="${TARGET}" KUBE_CONTEXT="${KUBE_CONTEXT:-}" bash "${ROOT}/environment/scripts/port-forwards.sh" env-test)"
fi
PUBLIC_URL="${PUBLIC_URL:-http://127.0.0.1:30080}"

log "Switching egress proxy to full deny (TARGET=${TARGET} context=${KUBE_CONTEXT})"
# shellcheck disable=SC2086
${KUBECTL} -n egress-system patch configmap egress-proxy-config --type merge -p '{
  "data": {
    "squid.conf": "http_port 3128\nacl SSL_ports port 443\nacl Safe_ports port 80 443 1025-65535\nacl CONNECT method CONNECT\nhttp_access deny !Safe_ports\nhttp_access deny CONNECT !SSL_ports\nhttp_access deny all\naccess_log stdio:/dev/stdout\ncache_log stdio:/dev/stderr\ncache deny all\n"
  }
}'
# shellcheck disable=SC2086
${KUBECTL} -n egress-system rollout restart deployment/egress-proxy
# shellcheck disable=SC2086
${KUBECTL} -n egress-system rollout status deployment/egress-proxy --timeout=120s

log "Probing Cap at ${PUBLIC_URL} while egress is fully denied"
sleep 5
if curl -fsS --max-time 15 "${PUBLIC_URL}/login" >/tmp/cap-airgap-body.html \
  || curl -fsS --max-time 15 "${PUBLIC_URL}/" >/tmp/cap-airgap-body.html; then
  log "PASS: Cap still serving under full egress deny"
  cp /tmp/cap-airgap-body.html "${PROOF_DIR}/airgap-response.html"
  date -u +"%Y-%m-%dT%H:%M:%SZ Cap responded under full egress deny TARGET=${TARGET}" | tee "${PROOF_DIR}/airgap-test.log"
else
  log "FAIL: Cap not reachable under full egress deny (${PUBLIC_URL})"
  bash "${ROOT}/scripts/restore-egress-proxy.sh"
  exit 1
fi

bash "${ROOT}/scripts/restore-egress-proxy.sh"
log "Airgap test complete"
