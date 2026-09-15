# Constraints we hit — proof index

The brief’s strongest signal: a constraint that **blocked** you, plus a **log**, plus the workaround. This folder is that packet.

| ID | Constraint (harder / real) | Log | Workaround |
|----|----------------------------|-----|------------|
| C1 | Corp TLS MITM on laptop (`x509` to quay/ghcr) | `corp-tls-quay-pull.log` (live `docker pull`) | Hub relay `muralisvishnu/halden-cage:*` — ADR-003, `docs/corp-tls-addons.md` |
| C2 | Default-deny: Cap cannot resolve/reach the internet | `squid-denials.log` | Intended. In-cluster only — `allowlist.yaml` |
| C3 | Air-gap: Squid `deny all`, Cap still serves | `airgap-test.log` | `make airgap-test` |
| C4 | Thursday-only change window | `freeze-guard-blocked.log` | `ALLOW_NON_THURSDAY=1` or `--break-glass` |
| C5 | Kyverno: public images in `cap` | `kyverno-deny-public-image.log` | Private registry / Hub allowlist (lab only) |
| C6 | Squid **file access_log OOMs** this image | `squid-access-log-oom.log` | `access_log none` + client probe — ADR-012 |
| C7 | GKE COS: HTTP ClusterIP registry vs HTTPS kubelet | `gke-http-registry.log` | Hub HTTPS — ADR-010 |
| C8 | Apple Silicon QEMU amd64 Cap build OOM | `qemu-amd64-mac.log` | Skip `make mirror TARGET=gke` on Mac |
| C9 | `minio/minio` gone from Docker Hub | `minio-dockerhub-gone.log` | Vendor Hub minio tags |
| C10 | Kubelet HTTP probes vs NetworkPolicy | `kubelet-http-probe-blocked.log` | Exec probes — ADR-007 |
| C11 | kind registry is emptyDir | `registry-catalog.log` | `make mirror` after every `make up` (log is current catalog; empty after `make up` before mirror) |
| C12 | kindnet already present | `cilium-ccnp.log` | Cilium chaining + CCNP — ADR-004 |
| C13 | Namespace memory quota 8Gi | `quota-exceeded.log` | Size the chart; do not lift quota |
| C14 | Kyverno require-limits vs LimitRange defaults | `kyverno-require-limits.log` | LimitRange fills omitted resources; Kyverno still enforces if they are stripped. Quota is the hard stop (C13) |
| C15 | No hostNetwork / hostPath in `cap` | `kyverno-deny-hostnetwork.log` | PSA **baseline** denied first; extra Kyverno policies also applied (ADR-014) |
| C16 | Direct egress skip HTTP_PROXY | `cilium-deny-direct-egress.log` | wget to 1.1.1.1 **timed out** — Cilium CCNP, not DNS |
| C17 | Least privilege: `deployer` SA blocked at cluster scope | `rbac-deployer-forbidden.log` | Use namespaced `cap-deployer` Role for workload deployments (blocks cluster-admin) |

Refresh: `make capture-constraints` and `make capture-denials`.

C6 is a kubectl transcript from 2026-09-14. C7–C10 are session notes. C13–C16 are live dry-run/exec against the kind cage.
