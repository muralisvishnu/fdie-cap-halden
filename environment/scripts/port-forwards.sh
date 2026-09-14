#!/usr/bin/env bash
# Background port-forwards (registry push on :5001, ingress/minio for smoke).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

PID_DIR="${ROOT}/.build/port-forwards"
REGISTRY_PID="${PID_DIR}/registry.pid"
INGRESS_PID="${PID_DIR}/ingress.pid"
MINIO_PID="${PID_DIR}/minio.pid"
INGRESS_URL_FILE="${PID_DIR}/ingress.url"
MINIO_URL_FILE="${PID_DIR}/minio.url"

log() { echo "[port-forward] $*" >&2; }

mkdir -p "${PID_DIR}"

stop_pidfile() {
  local pidfile="$1"
  if [[ -f "${pidfile}" ]]; then
    local pid
    pid="$(cat "${pidfile}")"
    kill "${pid}" 2>/dev/null || true
    rm -f "${pidfile}"
  fi
}

http_ok() {
  curl -fsS --max-time 3 "$1" >/dev/null 2>&1
}

port_in_use() {
  (echo >/dev/tcp/127.0.0.1/"$1") >/dev/null 2>&1
}

first_free_port() {
  local p
  for p in "$@"; do
    if ! port_in_use "${p}"; then
      echo "${p}"
      return 0
    fi
  done
  return 1
}

wait_http() {
  local url="$1"
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if http_ok "${url}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_registry() {
  local deadline=$((SECONDS + 120))
  while (( SECONDS < deadline )); do
    # shellcheck disable=SC2086
    if ${KUBECTL} -n cage-system get svc cage-registry >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      ${KUBECTL} -n cage-system wait --for=condition=ready pod -l app=cage-registry --timeout=120s 2>/dev/null && return 0
    fi
    sleep 3
  done
  log "WARN: cage-registry not ready yet"
}

start_registry() {
  stop_pidfile "${REGISTRY_PID}"
  wait_registry
  log "localhost:5001 -> cage-registry.cage-system:5000 (${KUBE_CONTEXT})"
  # shellcheck disable=SC2086
  nohup ${KUBECTL} -n cage-system port-forward svc/cage-registry 5001:5000 \
    >/dev/null 2>&1 &
  echo $! >"${REGISTRY_PID}"
  sleep 2
}

start_ingress_on() {
  local port="$1"
  stop_pidfile "${INGRESS_PID}"
  log "localhost:${port} -> ingress-nginx-controller:80 (${KUBE_CONTEXT})"
  # shellcheck disable=SC2086
  nohup ${KUBECTL} -n ingress-nginx port-forward svc/ingress-nginx-controller "${port}:80" \
    >/dev/null 2>&1 &
  echo $! >"${INGRESS_PID}"
}

start_minio_on() {
  local port="$1"
  stop_pidfile "${MINIO_PID}"
  log "localhost:${port} -> minio.${CAP_NAMESPACE}:9000 (${KUBE_CONTEXT})"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${CAP_NAMESPACE}" wait --for=condition=ready pod -l app=cap-minio --timeout=120s >/dev/null
  # shellcheck disable=SC2086
  nohup ${KUBECTL} -n "${CAP_NAMESPACE}" port-forward svc/minio "${port}:9000" \
    >/dev/null 2>&1 &
  echo $! >"${MINIO_PID}"
}

start_ingress() {
  local port
  port="$(first_free_port 30080 13080 14080 || true)"
  if [[ -z "${port}" ]]; then
    log "FAIL: no free port for ingress (tried 30080 13080 14080)"
    exit 1
  fi
  start_ingress_on "${port}"
  sleep 2
}

# Pick laptop URLs that actually reach this TARGET cluster.
# kind: hostPort 30080/30900. GKE: kubectl port-forward (never 30900 — Colima often owns it).
ensure_test_urls() {
  local ingress_url minio_url port

  ingress_url="${PUBLIC_URL:-}"
  if [[ -z "${ingress_url}" ]] && [[ -f "${INGRESS_URL_FILE}" ]]; then
    ingress_url="$(cat "${INGRESS_URL_FILE}")"
  fi
  ingress_url="${ingress_url:-http://127.0.0.1:30080}"

  if http_ok "${ingress_url}/login" || http_ok "${ingress_url}/"; then
    log "Cap already reachable at ${ingress_url}"
  else
    port="$(first_free_port 30080 13080 14080 || true)"
    [[ -n "${port}" ]] || { log "FAIL: no free local port for ingress"; exit 1; }
    start_ingress_on "${port}"
    ingress_url="http://127.0.0.1:${port}"
    if ! wait_http "${ingress_url}/login" && ! wait_http "${ingress_url}/"; then
      log "FAIL: Cap ingress not reachable at ${ingress_url} (context ${KUBE_CONTEXT})"
      exit 1
    fi
  fi
  printf '%s\n' "${ingress_url}" >"${INGRESS_URL_FILE}"
  PUBLIC_URL="${ingress_url}"

  minio_url="${S3_URL:-}"
  if [[ -z "${minio_url}" ]] && [[ -f "${MINIO_URL_FILE}" ]]; then
    minio_url="$(cat "${MINIO_URL_FILE}")"
  fi
  if [[ "${TARGET}" == "gke" ]]; then
    minio_url=""
  else
    minio_url="${minio_url:-http://127.0.0.1:30900}"
  fi

  if [[ -n "${minio_url}" ]] && http_ok "${minio_url}/minio/health/live"; then
    log "Minio already reachable at ${minio_url}"
  else
    port="$(first_free_port 13090 13190 13290 || true)"
    [[ -n "${port}" ]] || { log "FAIL: no free local port for Minio"; exit 1; }
    start_minio_on "${port}"
    minio_url="http://127.0.0.1:${port}"
    if ! wait_http "${minio_url}/minio/health/live"; then
      log "FAIL: Minio not reachable at ${minio_url} (context ${KUBE_CONTEXT})"
      exit 1
    fi
  fi
  printf '%s\n' "${minio_url}" >"${MINIO_URL_FILE}"
  S3_URL="${minio_url}"
  export PUBLIC_URL S3_URL
}

print_test_env() {
  ensure_test_urls
  printf 'export PUBLIC_URL=%q\n' "${PUBLIC_URL}"
  printf 'export S3_URL=%q\n' "${S3_URL}"
}

stop_all() {
  stop_pidfile "${REGISTRY_PID}"
  stop_pidfile "${INGRESS_PID}"
  stop_pidfile "${MINIO_PID}"
  log "Stopped port-forwards"
}

case "${1:-}" in
  start-registry) start_registry ;;
  start-ingress)  start_ingress ;;
  start-minio)
    port="$(first_free_port 13090 13190 13290 || true)"
    [[ -n "${port}" ]] || { log "FAIL: no free local port for Minio"; exit 1; }
    start_minio_on "${port}"
    sleep 2
    ;;
  start-test|env-test) print_test_env ;;
  start)          start_registry ;;
  stop)           stop_all ;;
  *)
    echo "Usage: $0 {start|start-registry|start-ingress|start-minio|start-test|env-test|stop}" >&2
    exit 1
    ;;
esac
