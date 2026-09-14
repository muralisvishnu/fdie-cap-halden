#!/usr/bin/env bash
# Build Cap images natively on GKE (linux/amd64) — avoids QEMU OOM on Apple Silicon laptops.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=environment/scripts/kube-env.sh
source "${ROOT}/environment/scripts/kube-env.sh"

CAP_REPO="${CAP_REPO:-https://github.com/CapSoftware/Cap.git}"
CAP_REF="${CAP_REF:-main}"
KANIKO_IMAGE="${KANIKO_IMAGE:-gcr.io/kaniko-project/executor:v1.23.2}"
REGISTRY_DEST="${REGISTRY_PULL_HOST}"
JOB_NS="${CAP_BUILD_NAMESPACE:-cap-build}"

log() { echo "[cap-build-gke] $*"; }

ensure_build_namespace() {
  # Kaniko needs capabilities beyond PodSecurity restricted (cage-system).
  # shellcheck disable=SC2086
  ${KUBECTL} apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: cap-build
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
EOF
}

git_context_from_repo() {
  local url="${CAP_REPO}"
  url="${url#https://}"
  url="${url#http://}"
  echo "git://${url}#refs/heads/${CAP_REF}"
}

wait_job() {
  local job_name="$1"
  log "Waiting for job/${job_name}"
  # shellcheck disable=SC2086
  if ! ${KUBECTL} -n "${JOB_NS}" wait --for=condition=complete "job/${job_name}" --timeout=3600s; then
    log "FAIL: job/${job_name} did not complete"
    # shellcheck disable=SC2086
    ${KUBECTL} -n "${JOB_NS}" logs "job/${job_name}" --all-containers=true --tail=200 || true
    exit 1
  fi
}

apply_kaniko_job() {
  local job_name="$1"
  local dockerfile_mount="$2"
  local destination="$3"
  local git_ctx="$4"
  local cpu_req="$5"
  local mem_req="$6"
  local cpu_lim="$7"
  local mem_lim="$8"

  log "Kaniko ${job_name} -> ${destination}"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${JOB_NS}" delete job "${job_name}" --ignore-not-found
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${JOB_NS}" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${JOB_NS}
spec:
  ttlSecondsAfterFinished: 900
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      volumes:
        - name: dockerfiles
          configMap:
            name: cap-kaniko-dockerfiles
      containers:
        - name: kaniko
          image: ${KANIKO_IMAGE}
          volumeMounts:
            - name: dockerfiles
              mountPath: /dockerfiles
          args:
            - --context=${git_ctx}
            - --dockerfile=${dockerfile_mount}
            - --destination=${destination}
            - --insecure
            - --skip-tls-verify
            - --skip-tls-verify-registry
            - --insecure-pull
            - --single-snapshot
            - --verbosity=info
          resources:
            requests:
              cpu: "${cpu_req}"
              memory: ${mem_req}
            limits:
              cpu: "${cpu_lim}"
              memory: ${mem_lim}
EOF
  wait_job "${job_name}"
}

main() {
  if [[ "${TARGET}" != "gke" ]]; then
    log "FAIL: build-cap-on-gke.sh requires TARGET=gke"
    exit 1
  fi

  local git_ctx
  git_ctx="$(git_context_from_repo)"
  log "Building Cap on GKE (${IMAGE_PLATFORM}) from ${git_ctx}"

  ensure_build_namespace

  # shellcheck disable=SC2086
  ${KUBECTL} -n "${JOB_NS}" create configmap cap-kaniko-dockerfiles \
    --from-file=Dockerfile.cap-web="${ROOT}/supply-chain/docker/Dockerfile.cap-web.bootstrap" \
    --from-file=Dockerfile.media-server="${ROOT}/supply-chain/docker/Dockerfile.media-server.bootstrap" \
    --dry-run=client -o yaml | ${KUBECTL} apply -f -

  apply_kaniko_job cap-web-kaniko \
    "/dockerfiles/Dockerfile.cap-web" \
    "${REGISTRY_DEST}/cap/cap-web:latest" \
    "${git_ctx}" \
    "2" "6Gi" "4" "10Gi"

  apply_kaniko_job cap-media-kaniko \
    "/dockerfiles/Dockerfile.media-server" \
    "${REGISTRY_DEST}/cap/media-server:latest" \
    "${git_ctx}" \
    "1" "2Gi" "2" "4Gi"

  log "Cap images built on GKE and pushed to ${REGISTRY_DEST}/cap/*"
}

main "$@"
