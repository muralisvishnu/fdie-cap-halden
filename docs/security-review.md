# Security review — Halden Cap BYOC

For a reviewer with **veto power**. Approving this should not require a call: every egress, every namespaced permission, what data can leave, and how to check images yourself.

Reference cage: kind `halden-cage`. Policies are files under `environment/manifests/`. Allowlist: `proof/allowlist.yaml`. Hit-and-log packet: [`proof/constraints.md`](../proof/constraints.md).

## What data could leave, and why it does not

| Data | Path | Control |
|------|------|---------|
| Screen recordings | Minio in-cluster (`minio.cap:9000`) | NetworkPolicy + Squid; `S3_INTERNAL_ENDPOINT` is cluster-local |
| Auth OTP | `cap-web` logs (dev) | No Resend key; no SMTP egress |
| Telemetry / license | Cap Next.js | `RESEND_*` empty; `NEXT_TELEMETRY_DISABLED=1` at **build**; Squid deny non-`.svc.cluster.local` |
| Image pulls at runtime | Registry | kind: in-cluster HTTP registry. GKE lab: Hub `halden-cage:*` (ADR-010) — **not** the customer story |

`make airgap-test` sets Squid to `http_access deny all` and still serves `/login`. Proof: `proof/airgap-test.log`.

## Egress (line by line)

Allowed destinations are **only** what is `allowed: true` in `proof/allowlist.yaml`. Summary:

| FQDN | Port | Who | Phase | Why |
|------|------|-----|-------|-----|
| `*.svc.cluster.local` (registry, squid, mysql, minio, media-server) | 5000/3128/3306/9000/3456 | Cap / kubelet | install + runtime | App + pulls |
| `github.com` | 443 | Vendor `mirror.sh` only | install-time | Clone Cap |
| `registry-1.docker.io` / `index.docker.io` | 443 | Vendor mirror / GKE lab | install-time | Hub relay |
| `quay.io`, `ghcr.io`, `registry.k8s.io` | 443 | — | **denied** | Corp MITM; we do not allow them |
| `example.com` | 443 | denial probe | **denied** | Proof of `TCP_DENIED` |

Squid: `environment/manifests/proxy/egress-proxy.yaml` — `dstdomain .svc.cluster.local` then `http_access deny all`. `access_log none` (this image OOMs with file logs — ADR-012). Denial proof: `make capture-denials` → `proof/squid-denials.log` (HTTP 403 through `HTTP_PROXY`).

Cap pods: `HTTP_PROXY`/`HTTPS_PROXY` → Squid; `NO_PROXY` for in-cluster names (`install/helm/cap/templates/cap-web.yaml`).

Cilium CCNP `default-deny-egress` plus namespace NetworkPolicy: DNS, Squid 3128, registry 5000, same-namespace.

## TLS intercept (what we did not put in the cage)

Halden: proxy terminates TLS; CA on the wiki. We **did not** implement Squid `ssl_bump` (ADR-009). Evidence of intercept is **laptop** `x509` to quay/ghcr (`docs/corp-tls-addons.md`) and the Hub relay. Runtime Cap **verifies** TLS (runner image does not set `NODE_TLS_REJECT_UNAUTHORIZED`).

## Permissions (namespace `cap` Role `cap-deployer`)

From `environment/manifests/rbac/cap-namespace.yaml`. No ClusterRole.

| API group | Resources | Verbs | Why |
|-----------|-----------|-------|-----|
| `""` | configmaps, secrets, services, PVCs, pods, pods/log | get, list, watch, create, update, patch, delete | Helm workload + debug |
| `apps` | deployments, statefulsets | same | cap-web, media-server, mysql, minio |
| `batch` | jobs | same | one-shot jobs |
| `networking.k8s.io` | ingresses, networkpolicies | same | Ingress + NP |

The Role `cap-deployer` is bound to ServiceAccount `deployer` in namespace `cap`. **Vendor `helm` during lab setup uses your user kubeconfig** (which has cluster-admin on kind/GKE for initial CNI/admission/namespace setup).

**Least Privilege Enforcement:** The application deployment identity is strictly namespaced and forbidden at cluster scope. On customer/Halden environments, deployment pipelines run as `system:serviceaccount:cap:deployer`.
* **Blocked:** Cluster-scoped actions (`kubectl get nodes`), reading secrets in other namespaces (`kube-system`).
* **Allowed:** Full CRUD on Cap workloads within `cap` namespace only.
* **Proof:** `proof/rbac-deployer-forbidden.log` (Constraint C17).

Cluster-scoped setup (vendor cage only, needs cluster-admin once during bootstrap): Kyverno ClusterPolicies, Cilium CCNP, namespaces `cage-system` / `egress-system`. Customer already has CNI/admission — they apply **adapted** copies, not kind chaining.

## Verify images without trusting us

1. `supply-chain/images.yaml` — names we believe we ship.
2. After `make mirror`, digests in `supply-chain/artifacts/*.digest` and release `image-manifest.yaml`.
3. Independently: `crane digest $REGISTRY/cap-web:latest` (or your imported tag) and compare to the manifest **you** imported.
4. Optional: `make attest` (syft SPDX + cosign) when those tools exist.
5. Kyverno `halden-private-registry-only` must list **your** registry, not our Hub allowlist, in customer clusters.

## Admission

| Policy | File | Effect |
|--------|------|--------|
| `halden-private-registry-only` | `environment/manifests/kyverno/policies.yaml` | Enforce image prefix in `cap` |
| `halden-require-limits` | same | CPU/memory limits |
| `halden-disallow-privileged` | same | no privileged |

Kind Kyverno also allows `docker.io/muralisvishnu/halden-cage:*` for the GKE lab (ADR-010). **Do not ship that allowlist to Halden.**

## Secrets

Helm `values.yaml` contains **lab** passwords. Production: rotate all `secrets.*`; prefer External Secrets. This document cannot be approved for prod until those values are not the defaults.

## How to re-verify on the cage

```bash
make preflight
make capture-denials          # proof/squid-denials.log contains TCP_DENIED
make airgap-test              # proof/airgap-test.log timestamp
kubectl -n cap get networkpolicy
kubectl get clusterpolicy
# no privileged:
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].securityContext.privileged==true) | .metadata.name'
```

## Known gaps

| Gap | Severity | Why it is acceptable for the cage |
|-----|----------|-----------------------------------|
| Lab secrets in git | High for prod | Cage only; customer `values-halden.yaml` |
| No ingress TLS on kind | Medium | Customer terminates TLS |
| OTP in logs | Low (dev) | No mail in air-gap |
| GKE lab Hub pulls | Medium vs “private registry only” | ADR-010; kind is the air-gap proof |
| Build-arg insecure TLS | Medium | Builder stage only; ADR-011 |
| deployer SA unused by Helm | Low | Role exists for least-privilege handoff |

## Sign-off

| Role | Status | Date |
|------|--------|------|
| FDIE implementer | Cage controls as in this file | 2026-09-14 |
| Halden security | Pending — they re-run verify steps in **their** cluster | — |
