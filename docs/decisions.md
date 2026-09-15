# Architecture decisions — Halden Cap BYOC

Format per brief: what we chose, what we rejected, the tradeoff, what we cut.

## ADR-001: Local-first kind cage before GKE

**Chose:** Prove the full constraint stack on Colima + kind (`halden-cage`) before a real cloud.

**Rejected:** GKE-only from day one; minikube; k3d.

**Tradeoff:** kind CNI is kindnet, so Cilium is chaining (ADR-004), not a full kube-proxy replacement.

**Cut:** Reproducing Halden’s exact GKE version / node pools.

## ADR-002: Private registry at `localhost:5001`

**Chose:** In-cluster registry; kind nodes pull via `containerdConfigPatches`.

**Rejected:** Pushing Cap straight from Docker Hub into the `cap` namespace (Kyverno would fight us; Halden said private registry).

**Tradeoff:** Registry is emptyDir — `make mirror` after every `make up`.

**Cut:** TLS for the in-cluster registry (HTTP). GKE COS kubelet cannot pull that HTTP registry — see ADR-010.

## ADR-003: Docker Hub relay for addon images

**Chose:** Mirror Cilium/Kyverno/ingress to `docker.io/muralisvishnu/halden-cage:<tag>`, then preload into kind.

**Rejected:** Trusting quay.io / ghcr.io / registry.k8s.io from the laptop; asking Halden for their wiki CA on day one (they would not have answered).

**Tradeoff:** One extra hop and a vendor Hub repo. Addons are still *relocated* images, not live pulls from upstream at runtime on kind.

**Cut:** Running a second in-cluster Harbor.

**Evidence:** `docs/corp-tls-addons.md` (`x509: certificate signed by unknown authority`).

## ADR-004: Cilium chaining on kind

**Chose:** Cilium `generic-veth` chaining over kindnet so we get CCNP without recreating the cluster.

**Rejected:** `disableDefaultCNI` + full Cilium (would force `make down`); relying on Kubernetes NetworkPolicy alone.

**Tradeoff:** Not identical to GKE Dataplane V2. Dedicated GKE uses `gke.enabled=true` instead of chaining.

**Cut:** kube-proxy replacement.

## ADR-005: Ingress without `/etc/hosts`

**Chose:** Catch-all Ingress on NodePort 30080; `publicUrl=http://127.0.0.1:30080`.

**Rejected:** Requiring sudo `/etc/hosts` for `cap.local`.

**Tradeoff:** `allowExternalIngress: true` on the localhost overlay (documented in security-review).

**Cut:** Let’s Encrypt in the cage.

## ADR-006: Passwordless email via logs

**Chose:** Empty `RESEND_API_KEY`; OTP in `cap-web` logs (upstream air-gap behavior).

**Rejected:** Patching Cap to skip auth; standing up SMTP in the cage.

**Tradeoff:** OTP in logs is a known gap for prod.

**Cut:** Real IdP (Halden never named one).

## ADR-007: Exec-based health probes

**Chose:** in-container `wget` probes.

**Rejected:** kubelet HTTP probes (NetworkPolicy drops node→pod HTTP when ingress is locked down).

**Tradeoff:** Probe runs as the container user; needs wget in the image.

**Cut:** Service mesh mTLS for probes.

## ADR-008: Thursday change window

**Chose:** `freeze-guard.sh` blocks non-Thursday unless `ALLOW_NON_THURSDAY=1` or `--break-glass`.

**Rejected:** No freeze (would ignore the kickoff); blocking demos with no override.

**Tradeoff:** Every documented vendor install sets `ALLOW_NON_THURSDAY=1` — the guard is the artifact, the override is break-glass.

**Cut:** Integrating a real change-ticket API.

## ADR-009: TLS interception = customer edge, not Squid ssl_bump

**Chose:** Interpret *“the proxy terminates TLS; our CA is on the wiki”* as **Halden’s perimeter MITM**. We proved it on the **laptop** (quay/ghcr x509). Cage Squid is a **default-deny forward proxy** (CONNECT allow/deny to `.svc.cluster.local` only). No `ssl_bump`.

**Rejected:** In-cluster Squid SSL bump + cage CA in every trust store. That would force a Squid-with-OpenSSL image, a generated CA Secret, and trusting that CA in Cap — or `NODE_TLS_REJECT_UNAUTHORIZED=0` **at runtime**, which is a worse “modified app path.”

**Tradeoff:** Reviewers who want literal ssl_bump will not see MITM inside kind. They will see the same *class* of failure plus Hub relay (ADR-003) and this ADR.

**Cut:** Shipping a wiki CA we do not have.

## ADR-010: Dedicated GKE lab pulls Hub HTTPS, not HTTP ClusterIP registry

**Chose:** On `TARGET=gke`, Cap/addons use `docker.io/muralisvishnu/halden-cage:*` + `imagePullSecret dockerhub-creds`. Skip `make mirror` on Apple Silicon (QEMU OOM).

**Rejected:** Pretending GKE COS kubelet can pull `http://ClusterIP:5000` without node containerd hacks; QEMU amd64 Cap builds on this Mac.

**Tradeoff:** Dedicated GKE is a **second real cloud target** for Helm/Make, not a bit-for-bit copy of the kind private-registry cage. Kind remains the air-gap proof.

**Cut:** Artifact Registry in `sre-play` (would be cleaner TLS; not done).

## ADR-011: `NODE_TLS_REJECT_UNAUTHORIZED=0` is build-stage only

**Chose:** Keep insecure TLS **only** on the Cap **builder** stage so `bun install` survives laptop MITM. The **runner** image does not set it. Override: `--build-arg CAP_BUILD_INSECURE_TLS=` plus `NODE_EXTRA_CA_CERTS` when the wiki CA exists.

**Rejected:** Disabling TLS verify in the running `cap-web` container; forking Cap.

**Tradeoff:** Vendor laptop builds are still a TLS cheat. Customer/Halden builders should not use the default arg.

**Cut:** Baking an unknown corp CA into CI.

## ADR-013: Proof packet for “hit it and logged it”

**Chose:** `proof/constraints.md` indexes live and session logs (TLS pull, freeze-guard, Kyverno deny, Squid OOM, GKE HTTP, QEMU, emptyDir catalog).

**Rejected:** Inventing Squid `TCP_DENIED` lines after `access_log` OOM’d the proxy.

**Tradeoff:** Some logs are kubectl transcripts / session notes, not a single uncut asciinema (still `make record-install`).

**Cut:** Replacing Squid just to get native access logs.

## ADR-014: Extra admission — no hostNetwork / hostPath in `cap`

**Chose:** ClusterPolicies `halden-disallow-host-namespaces` and `halden-disallow-hostpath` (harder than “we installed Kyverno”).

**Rejected:** Privileged node-agent sidecars in `cap` to “debug networking.”

**Tradeoff:** Breaks any future DaemonSet in `cap` that needs the host. Cap does not.

**Cut:** ValidatingAdmissionPolicy-only (no Kyverno CRDs) — we already depend on Kyverno.

## ADR-012: Squid denial proof is client 403, not access_log

**Chose:** Keep `access_log none` on ubuntu/squid:5.2. `make capture-denials` execs `cap-web` (HTTP_PROXY) to `example.com` and commits the **403 / Access Denied** body as `proof/squid-denials.log`.

**Rejected:** `access_log` to stdout (GKE non-root), file, or `stdio:/tmp` — this image **OOMKilled** in kind when logging was enabled, which would break cage and GKE.

**Tradeoff:** Reviewers see client `403` or `wget: bad address` (DNS also blocked by default-deny), not Squid `TCP_DENIED` native format.

**Cut:** Replacing Squid with a custom Envoy image just to get access logs.

## ADR-015: Namespaced least-privilege deployment Role (`cap-deployer`) vs cluster-admin

**Chose:** Define a namespaced Role `cap-deployer` bound to `ServiceAccount:cap:deployer` for all Cap application resources. Application deployment tools operate under least-privilege namespaced permissions.

**Rejected:** Granting `cluster-admin` or cluster-scoped `ClusterRoleBinding` to application deployment pipelines.

**Tradeoff:** Initial cluster-level bootstrapping (installing Cilium CCNP, Kyverno ClusterPolicies, `ingress-nginx`, and namespaces `cage-system`/`egress-system`) still requires cluster-admin permissions once during cluster setup, but application lifecycle management is restricted to `cap` / `halden-cap`.

**Evidence:** `proof/rbac-deployer-forbidden.log` (Constraint C17 — attempts to access `nodes` or `kube-system` secrets as `cap:deployer` are rejected with HTTP 403 Forbidden).


