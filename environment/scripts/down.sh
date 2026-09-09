#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-halden-cage}"
REGISTRY_NAME="${REGISTRY_NAME:-cage-registry}"

echo "[cage] Deleting kind cluster ${CLUSTER_NAME}"
kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true

if docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
  echo "[cage] Stopping local registry ${REGISTRY_NAME}"
  docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1 || true
fi

echo "[cage] Done"
