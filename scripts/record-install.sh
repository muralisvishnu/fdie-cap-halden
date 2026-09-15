#!/usr/bin/env bash
# Record an uncut kind install (asciinema). Does not change cluster state by itself.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAST="${ROOT}/proof/halden-cap-demo.cast"

echo "[record-install] FDIE wants one uncut install from zero."
echo "  Suggested (kind):"
echo "    make down TARGET=cage && make up TARGET=cage && make mirror TARGET=cage"
echo "    make install-addons TARGET=cage"
echo "    ALLOW_NON_THURSDAY=1 make install-ingress TARGET=cage"
echo "    make capture-denials TARGET=cage && make airgap-test TARGET=cage"
echo "    make test-smoke TARGET=cage"
echo ""

if ! command -v asciinema >/dev/null 2>&1; then
  echo "[record-install] Install: brew install asciinema"
  echo "  Then: asciinema rec -i 1 ${CAST}"
  echo "  Commit ${CAST} (gitignores other *.cast; proof/*.cast is allowed)."
  exit 0
fi

echo "[record-install] Starting asciinema → ${CAST}"
echo "  Run the Make sequence above inside the recording, then exit."
exec asciinema rec -i 1 "${CAST}"
