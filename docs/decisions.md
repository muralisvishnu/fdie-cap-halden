# Architecture decisions — Halden Cap BYOC

## ADR-001: Local-first kind cage before GKE

**Decision:** Prove the full constraint stack on Colima + kind (`halden-cage`) before deploying to shared GKE `sre-play`.

**Rationale:** Faster iteration, no corp VPN dependency for daily dev, mirrors Halden’s “lab cage” pattern.

## ADR-002: Private registry at `localhost:5001`

**Decision:** Bootstrap registry on the host; kind nodes pull via `containerdConfigPatches`.

**Rationale:** Simulates Halden’s private-registry-only policy; Kyverno enforces `localhost:5001/*` in the `cap` namespace.

## ADR-003: Docker Hub relay for addon images

**Decision:** Mirror Cilium/Kyverno/Ingress images to `docker.io/muralisvishnu/halden-cage:<tag>` via a GKE crane Job, then preload into kind.

**Rationale:** Corp TLS MITM blocks `quay.io` / `ghcr.io` on laptops; Docker Hub and GKE egress work.

## ADR-004: Cilium chaining on kind (no cluster recreate)

**Decision:** Install Cilium in `generic-veth` chaining mode with a custom CNI ConfigMap over kindnet.

**Rationale:** Avoid `disableDefaultCNI` cluster rebuild while still enabling `CiliumClusterwideNetworkPolicy`.

## ADR-005: Ingress without `/etc/hosts`

**Decision:** Catch-all Ingress on NodePort 30080; `publicUrl` = `http://127.0.0.1:30080`; Minio S3 on NodePort 30900.

**Rationale:** Developers without sudo cannot edit `/etc/hosts`.

## ADR-006: Passwordless email auth via server logs

**Decision:** Leave `RESEND_API_KEY` empty; Cap prints OTP codes to `cap-web` logs (upstream dev mode).

**Rationale:** Air-gapped cage has no outbound SMTP; matches Cap self-hosting docs.

## ADR-007: Exec-based health probes

**Decision:** `cap-web` and `media-server` use in-container `wget` probes instead of kubelet HTTP probes.

**Rationale:** Strict NetworkPolicy blocks node→pod HTTP when `allowExternalIngress: false`.

## ADR-008: Thursday change window

**Decision:** `governance/scripts/freeze-guard.sh` blocks installs except Thursday or `ALLOW_NON_THURSDAY=1`.

**Rationale:** Harness-inspired change control for Halden Pharma demo.
