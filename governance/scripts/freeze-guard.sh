#!/usr/bin/env bash
set -euo pipefail

# Harness-inspired change-window freeze mechanism (open-tool implementation).
# Refuses install/upgrade outside Thursday unless --break-glass is passed.

if [[ "${1:-}" == "--break-glass" ]]; then
  echo "[freeze-guard] break-glass override accepted"
  exit 0
fi

DOW=$(date -u +%u) # 1=Mon ... 4=Thu
if [[ "${DOW}" != "4" && "${ALLOW_NON_THURSDAY:-}" != "1" ]]; then
  echo "[freeze-guard] BLOCKED: Halden change window is Thursday only."
  echo "[freeze-guard] Re-run with --break-glass for emergency installs."
  exit 1
fi

echo "[freeze-guard] change window OK (Thursday or ALLOW_NON_THURSDAY=1)"
