#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
NODE="halden-cage-control-plane"

log() { echo "[preload] $*"; }

import_image() {
  local image="$1"
  log "Import ${image} into kind node"
  docker pull "${image}"
  docker save "${image}" | docker exec -i "${NODE}" ctr -n=k8s.io images import - >/dev/null
}

main() {
  import_image "registry:2"
  import_image "ubuntu/squid:5.2-22.04_beta"
  log "Infra images imported"
}

main "$@"
