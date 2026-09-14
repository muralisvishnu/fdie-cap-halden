#!/usr/bin/env bash
# Mirror addon images into the private registry (localhost:5001 port-forward).
# Wrapper around sync-laptop-addons-to-registry.sh (no Docker Hub).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-cage}"
export TARGET

if [[ "${TARGET}" == "gke" ]]; then
  exec bash "${ROOT}/environment/scripts/sync-laptop-addons-to-registry.sh"
fi

# kind: push to port-forwarded registry then import into kind node on install
exec bash "${ROOT}/environment/scripts/sync-laptop-addons-to-registry.sh"
