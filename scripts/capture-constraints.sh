#!/usr/bin/env bash
# Refresh proof logs for constraints we actually hit (FDIE "harder + a log").
# Does not change Helm/GKE Hub --sets. Safe to re-run.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROOF="${ROOT}/proof"
mkdir -p "${PROOF}"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

log() { echo "[constraints] $*"; }

# --- Thursday freeze (UTC weekday) ---
{
  echo "# freeze-guard ${TS}"
  echo "# Command: bash governance/scripts/freeze-guard.sh"
  echo "#"
  bash "${ROOT}/governance/scripts/freeze-guard.sh" 2>&1 || true
  echo "#"
  echo "# Workaround: ALLOW_NON_THURSDAY=1 or --break-glass"
} >"${PROOF}/freeze-guard-blocked.log"
log "wrote freeze-guard-blocked.log"

# --- Corp TLS: pull a quay image the laptop historically MITMs ---
{
  echo "# docker pull quay.io/cilium/cilium:v1.20.1 ${TS}"
  echo "# Expected on corp MITM laptop: x509: certificate signed by unknown authority"
  echo "#"
  docker pull quay.io/cilium/cilium:v1.20.1 2>&1 || true
} >"${PROOF}/corp-tls-quay-pull.log"
log "wrote corp-tls-quay-pull.log"

# --- Kyverno deny public nginx in cap ns (if cluster + policy exist) ---
{
  echo "# kubectl apply forbidden image in namespace cap ${TS}"
  echo "#"
  kubectl --context kind-halden-cage apply --dry-run=server -f - 2>&1 <<'YAML' || true
apiVersion: v1
kind: Pod
metadata:
  name: kyverno-deny-probe
  namespace: cap
spec:
  restartPolicy: Never
  containers:
    - name: nginx
      image: docker.io/library/nginx:1.27
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
YAML
} >"${PROOF}/kyverno-deny-public-image.log"
log "wrote kyverno-deny-public-image.log"

# --- In-cluster registry catalog (emptyDir wiped after make up without mirror) ---
{
  echo "# curl localhost:5001/v2/_catalog ${TS}"
  echo "# After make up with empty registry: {\"repositories\":[]} — must make mirror"
  echo "#"
  curl -fsS --max-time 5 "http://127.0.0.1:5001/v2/_catalog" 2>&1 || echo "FAIL: registry not on :5001 (kind down or pf missing)"
} >"${PROOF}/registry-catalog.log"
log "wrote registry-catalog.log"

KCTX="${KCTX:-kind-halden-cage}"
K="kubectl --context ${KCTX}"
REG_IMG="cage-registry.cage-system.svc.cluster.local:5000/cap/minio-mc:latest"

# --- ResourceQuota: 32Gi memory vs 8Gi namespace request cap ---
{
  echo "# ResourceQuota exceeded ${TS}"
  echo "# cap-quota requests.memory=8Gi; this pod asks 32Gi"
  echo "#"
  ${K} apply --dry-run=server -f - 2>&1 <<YAML || true
apiVersion: v1
kind: Pod
metadata:
  name: quota-exceed-probe
  namespace: cap
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${REG_IMG}
      securityContext:
        allowPrivilegeEscalation: false
        privileged: false
        capabilities:
          drop: ["ALL"]
      resources:
        requests:
          cpu: "1"
          memory: 32Gi
        limits:
          cpu: "2"
          memory: 32Gi
YAML
  echo "#"
  echo "# Workaround: stay under environment/manifests/noise/quota-limits.yaml"
} >"${PROOF}/quota-exceeded.log"
log "wrote quota-exceeded.log"

# --- Kyverno require-limits: allowed image, no resources ---
{
  echo "# Kyverno halden-require-limits ${TS}"
  echo "#"
  ${K} apply --dry-run=server -f - 2>&1 <<YAML || true
apiVersion: v1
kind: Pod
metadata:
  name: no-limits-probe
  namespace: cap
spec:
  restartPolicy: Never
  containers:
    - name: probe
      image: ${REG_IMG}
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        allowPrivilegeEscalation: false
        privileged: false
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
YAML
} >"${PROOF}/kyverno-require-limits.log"
log "wrote kyverno-require-limits.log"

# --- hostNetwork + hostPath forbidden ---
{
  echo "# Apply extra Kyverno policies then dry-run hostNetwork/hostPath ${TS}"
  echo "#"
  ${K} apply -f "${ROOT}/environment/manifests/kyverno/policies.yaml" 2>&1 || true
  echo "--- hostNetwork ---"
  ${K} apply --dry-run=server -f - 2>&1 <<YAML || true
apiVersion: v1
kind: Pod
metadata:
  name: hostnet-probe
  namespace: cap
spec:
  hostNetwork: true
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${REG_IMG}
      securityContext:
        allowPrivilegeEscalation: false
        privileged: false
        capabilities:
          drop: ["ALL"]
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
YAML
  echo "--- hostPath ---"
  ${K} apply --dry-run=server -f - 2>&1 <<YAML || true
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-probe
  namespace: cap
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${REG_IMG}
      securityContext:
        allowPrivilegeEscalation: false
        privileged: false
        capabilities:
          drop: ["ALL"]
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
      volumeMounts:
        - name: host
          mountPath: /host
  volumes:
    - name: host
      hostPath:
        path: /etc
YAML
} >"${PROOF}/kyverno-deny-hostnetwork.log"
log "wrote kyverno-deny-hostnetwork.log"

# --- Direct egress (bypass HTTP_PROXY) ---
{
  echo "# wget -Y off http://1.1.1.1 from cap-web (no proxy) ${TS}"
  echo "# Cilium default-deny should block internet without Squid"
  echo "#"
  pod="$(${K} -n cap get pod -l app=cap-web --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${pod}" ]]; then
    ${K} -n cap exec "${pod}" -c cap-web -- /bin/sh -c 'wget -Y off -T 6 -O /dev/null http://1.1.1.1/ 2>&1 || true'
  else
    echo "FAIL: no Running cap-web"
  fi
} >"${PROOF}/cilium-deny-direct-egress.log"
log "wrote cilium-deny-direct-egress.log"

{
  echo "# CiliumClusterwideNetworkPolicy ${TS}"
  echo "#"
  ${K} get ciliumclusterwidenetworkpolicy default-deny-egress -o yaml 2>&1 | head -n 40
} >"${PROOF}/cilium-ccnp.log"
log "wrote cilium-ccnp.log"

# --- Least privilege: cap-deployer ServiceAccount blocked at cluster scope ---
{
  echo "# RBAC least privilege probe ${TS}"
  echo "# cap-deployer ServiceAccount attempting cluster-scoped and cross-namespace access"
  echo "#"
  echo "--- 1. Get cluster nodes as cap:deployer ---"
  ${K} get nodes --as=system:serviceaccount:cap:deployer 2>&1 || true
  echo "--- 2. Get secrets in kube-system as cap:deployer ---"
  ${K} get secrets -n kube-system --as=system:serviceaccount:cap:deployer 2>&1 || true
  echo "--- 3. Allowed namespaced action (get pods in cap) ---"
  ${K} get pods -n cap --as=system:serviceaccount:cap:deployer 2>&1 || true
} >"${PROOF}/rbac-deployer-forbidden.log"
log "wrote rbac-deployer-forbidden.log"

exit 0

