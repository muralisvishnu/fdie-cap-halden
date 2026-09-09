#!/usr/bin/env bash
# Verify proof artifacts ship with the BYOC bundle (FDIE evidence).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROOF="${ROOT}/proof"
MAX_AGE_DAYS="${PROOF_MAX_AGE_DAYS:-90}"

log() { echo "[verify-proof] $*"; }
fail() { log "FAIL: $*"; exit 1; }

required=(
  "${PROOF}/security-checklist.md"
  "${PROOF}/README.md"
)

for f in "${required[@]}"; do
  [[ -f "${f}" ]] || fail "missing ${f}"
done

if [[ -f "${PROOF}/airgap-test.log" ]]; then
  log "airgap-test.log present"
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "${PROOF}/airgap-test.log"; then
    log "airgap timestamp OK"
  else
    fail "airgap-test.log missing ISO timestamp"
  fi
else
  log "WARN: airgap-test.log missing — run 'make airgap-test' on reference cage"
fi

if [[ -f "${PROOF}/airgap-response.html" ]]; then
  log "airgap-response.html present"
else
  log "WARN: airgap-response.html missing"
fi

# Optional freshness check
if [[ -f "${PROOF}/airgap-test.log" ]] && command -v python3 >/dev/null 2>&1; then
  age_days="$(PROOF_LOG="${PROOF}/airgap-test.log" python3 - <<'PY'
import datetime, re, pathlib, os
p = pathlib.Path(os.environ["PROOF_LOG"])
text = p.read_text()
m = re.search(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)", text)
if not m:
    print(-1); raise SystemExit
ts = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ")
print((datetime.datetime.utcnow() - ts).days)
PY
)"
  if [[ "${age_days}" -ge 0 && "${age_days}" -gt "${MAX_AGE_DAYS}" ]]; then
    log "WARN: airgap proof is ${age_days} days old (max ${MAX_AGE_DAYS})"
  fi
fi

log "Proof verification passed"
