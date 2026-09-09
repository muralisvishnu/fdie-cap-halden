# AI agent guide — Halden Cap BYOC

This file is the **entry point for AI assistants** (Cursor, Claude Code, Copilot, etc.) working in this repo or helping deploy Cap in customer infrastructure.

**Read first:** [`docs/install-contract.md`](docs/install-contract.md) — what “contract” means.  
**Detailed playbooks:** [`docs/ai-protocol.md`](docs/ai-protocol.md).

---

## Project in one sentence

BYOC packaging for [Cap](https://github.com/CapSoftware/Cap) under pharma-style constraints: private registry only, egress proxy, Kyverno, Cilium, network policies. **No Harness product.**

---

## Critical rules for AI

1. **Never deploy to customer prod from this repo's CI.** CI validates charts only. Customer runs install in their cluster.
2. **Never echo or commit secrets.** Use K8s Secret names, placeholders, or prompt the human to set values offline.
3. **Follow the install contract:** inputs → `preflight.sh` → `install.sh` → `smoke-test.sh`.
4. **Do not skip policy stack** on the reference cage (Cilium, Kyverno, egress proxy) unless the human explicitly asks for a minimal debug install.
5. **Registry is always private.** Update Kyverno `halden-private-registry-only` if the customer registry host differs from `localhost:5001`.
6. **Do not hand-edit generated Helm values per cluster** — edit `install/helm/cap/values.yaml` + overlays, or customer `values-halden.yaml`.

---

## Two modes — ask which one applies

| Mode | Who | Cluster | Start here |
|------|-----|---------|------------|
| **VENDOR** | FDIE implementer | Local kind cage (`halden-cage`) | `make up` → `make mirror` → addons → `make install-ingress` |
| **CUSTOMER** | Halden / BYOC customer | Their GKE / on-prem K8s | Extract bundle → mirror images → `TARGET=byoc` preflight → helm install |

If unclear, ask: *"Are we on the reference cage or installing in customer infrastructure?"*

---

## Doc map (read before acting)

| Doc | When to read |
|-----|--------------|
| [`docs/install-contract.md`](docs/install-contract.md) | What contract means; vendor vs customer responsibilities |
| [`docs/customer-install.md`](docs/customer-install.md) | Customer step-by-step install |
| [`docs/release.md`](docs/release.md) | Cutting a release bundle (vendor) |
| [`docs/ai-protocol.md`](docs/ai-protocol.md) | AI playbooks with exact commands |
| [`docs/runbook.md`](docs/runbook.md) | Reference cage day-to-day |
| [`docs/decisions.md`](docs/decisions.md) | ADRs (Cilium chaining, ingress, etc.) |
| [`tests/README.md`](tests/README.md) | Smoke / e2e test framework |

---

## Vendor workflow (reference cage)

```bash
make ensure-colima && make up && make mirror
make install-addons-dockerhub   # or install-addons-local
ALLOW_NON_THURSDAY=1 make install-ingress
make test-smoke
make airgap-test && make verify-proof
make package                    # dist/halden-cap-bundle-<version>.tar.gz
```

Open: http://127.0.0.1:30080 — OTP via `make auth-login`.

---

## Customer workflow (their infra)

```bash
# After extracting halden-cap-bundle-*.tar.gz
export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export REGISTRY_HOST=registry.customer.example/cap
export PUBLIC_URL=https://cap.customer.example
export S3_URL=https://s3.cap.customer.example
export KUBECTL="kubectl --context <their-context>"

# 1. Mirror images (customer runs crane/skopeo — see image-manifest.yaml)
# 2. Patch manifests/kyverno/ for their registry host
# 3. Apply policies (Cilium, Kyverno, proxy) if not already present
bash scripts/preflight.sh
helm upgrade --install cap chart/cap-*.tgz -n cap --create-namespace \
  -f values-halden.yaml --set global.registry="${REGISTRY_HOST}" --wait
bash scripts/smoke-test.sh
```

Pass = `preflight` and `smoke-test` both exit 0.

---

## Key environment variables

| Variable | Default | CUSTOMER set to |
|----------|---------|-----------------|
| `TARGET` | `cage` | `byoc` or `gke` |
| `PREFLIGHT_PROFILE` | `cage` | `byoc` |
| `REGISTRY_HOST` | `localhost:5001` | Customer private registry prefix |
| `PUBLIC_URL` | `http://127.0.0.1:30080` | Customer Cap URL |
| `S3_URL` | `http://127.0.0.1:30900` | Customer Minio URL |
| `ALLOW_NON_THURSDAY` | — | `1` to bypass freeze guard |
| `USE_INGRESS` | — | `1` for ingress-based install |

---

## Repository layout (high signal)

```
install/helm/cap/          Helm chart + values overlays
environment/manifests/     Kyverno, Cilium, egress proxy, RBAC
environment/scripts/       kind cage up, addons install
supply-chain/              mirror.sh, package-release.sh, images.yaml
scripts/                   install.sh, preflight.sh, smoke-test.sh (contract)
tests/smoke/               Acceptance tests
tests/e2e/                 Airgap e2e (reference cage)
proof/                     Airgap log + security checklist
governance/scripts/        freeze-guard.sh
docs/                      Human + AI documentation
```

---

## Common mistakes AI should avoid

| Mistake | Why it's wrong |
|---------|----------------|
| Adding GHA deploy-to-kind CD | BYOC — customer deploys, not vendor CI |
| Disabling Kyverno/Cilium “for speed” | Defeats the FDIE security story |
| Using public Docker Hub in `cap` namespace | Kyverno blocks it |
| HTTP kubelet probes on cap-web | NetworkPolicy blocks them — chart uses exec probes |
| Hardcoding `localhost:5001` in customer values | Customer registry differs |
| Committing `values-halden.yaml` with real secrets | Security incident |

---

## Troubleshooting quick ref

| Symptom | Check |
|---------|-------|
| Kyverno blocks pod | Image registry not in policy — patch `manifests/kyverno/policies.yaml` |
| cap-web CrashLoop | `kubectl logs -n cap deployment/cap-web`; proxy env vars |
| Helm timeout | Exec probes + netpol — see ADR-007 in `docs/decisions.md` |
| preflight fails registry | Images not mirrored to `REGISTRY_HOST` |
| egress-proxy CrashLoop | Run `make restore-egress` (reference cage) |
| OTP not received | Expected air-gap — `make auth-login` reads cap-web logs |

---

## Release (vendor only)

Bump `install/helm/cap/Chart.yaml` version → pre-release checklist in `docs/release.md` → `make package` → `git tag vX.Y.Z && git push origin vX.Y.Z`.

---

## For AI in the customer bundle only

If you only have `halden-cap-bundle-*.tar.gz` (no full repo), read `AGENTS.md`, `customer-install.md`, and `ai-protocol.md` inside the bundle. Do not assume `make up` or kind exist.
