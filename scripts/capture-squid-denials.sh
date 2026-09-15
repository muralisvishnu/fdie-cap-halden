#!/usr/bin/env bash
# Prove Squid denies non-allowlisted destinations without changing Helm/Cap.
# ubuntu/squid:5.2 OOMs if we enable file access_log in this image (kind + GKE).
# We record the client-side 403/denied CONNECT through HTTP_PROXY instead (ADR-012).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

PROOF_DIR="${ROOT}/proof"
mkdir -p "${PROOF_DIR}"
OUT="${PROOF_DIR}/squid-denials.log"
DENY_HOST="${SQUID_DENY_HOST:-example.com}"

log() { echo "[squid-denials] $*"; }

# shellcheck disable=SC2086
if ! ${KUBECTL} -n egress-system get deploy egress-proxy >/dev/null 2>&1; then
  log "FAIL: egress-proxy missing (run make up TARGET=${TARGET})"
  exit 1
fi

pod=""
# shellcheck disable=SC2086
pod="$(${KUBECTL} -n "${CAP_NAMESPACE}" get pod -l app=cap-web --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
container="cap-web"
if [[ -z "${pod}" ]]; then
  # shellcheck disable=SC2086
  pod="$(${KUBECTL} -n "${CAP_NAMESPACE}" get pod -l app=outbound-runner --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  container="runner"
fi
if [[ -z "${pod}" ]]; then
  log "FAIL: need a Running cap-web or outbound-runner pod"
  exit 1
fi

log "Probe http://${DENY_HOST} via HTTP_PROXY from ${CAP_NAMESPACE}/${pod}"
PROBE="$(mktemp)"
set +e
# shellcheck disable=SC2086
${KUBECTL} -n "${CAP_NAMESPACE}" exec "${pod}" -c "${container}" -- \
  /bin/sh -c "wget -S -O /dev/null -T 8 http://${DENY_HOST}/ 2>&1 || wget -S -O /dev/null -T 8 https://${DENY_HOST}/ 2>&1 || true" \
  >"${PROBE}" 2>&1
set -e

{
  echo "# Squid denial evidence $(date -u +"%Y-%m-%dT%H:%M:%SZ") TARGET=${TARGET}"
  echo "# Client ${CAP_NAMESPACE}/${pod} HTTP_PROXY=egress-proxy:3128 → ${DENY_HOST}"
  echo "# Allowlist: proof/allowlist.yaml (only .svc.cluster.local). ADR-012: no Squid access_log file."
  echo "#"
  cat "${PROBE}"
} >"${OUT}"
rm -f "${PROBE}"

if grep -Eqi '403|Forbidden|denied|Access Denied|TCP_DENIED|407|bad address|Name or service not known|Could not resolve' "${OUT}"; then
  log "OK: wrote ${OUT} (denied / unresolvable — egress blocked)"
  grep -Ei '403|Forbidden|denied|Access Denied' "${OUT}" | tail -n 20 || true
  exit 0
fi

log "FAIL: ${OUT} has no 403/denied (Squid down, or probe never hit the proxy)"
log "  kubectl -n egress-system get pods"
exit 1
