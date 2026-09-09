# Image supply model — Halden Cap BYOC

How Cap container images reach the customer cluster. **Default for FDIE: Tier 1.**

## Tier 1 — Vendor-qualified build, customer import (default)

| Step | Who | What |
|------|-----|------|
| 1. Build + mirror | **Vendor** (reference build host) | `make mirror` — builds `cap-web` / `media-server` from Cap source; mirrors `mysql` / `minio` |
| 2. Attest (optional) | **Vendor** | `make attest` — SBOM + cosign; digests in `supply-chain/artifacts/` |
| 3. Publish | **Vendor** | Release bundle (`make package`) + `image-manifest.yaml` with pinned digests |
| 4. Import | **Customer** | `crane copy` / `skopeo` / registry sync into `registry.halden.pharma` — **no compile** |
| 5. Deploy | **Customer** | `preflight` → `helm install` → `smoke-test` in their lab |

**What the release bundle contains:** Helm chart, policies, scripts, image manifest, proof — **not** the image layers themselves.

**What the customer does NOT do:** Clone Cap source, run `docker build`, or pull from public Docker Hub in production.

**Audit story:** One vendor-qualified build; customer change ticket records import of pinned digests into private registry.

### Vendor commands (reference)

```bash
make mirror
make attest                              # optional
make package                             # bundle for handoff
# Or push to a relay registry for lab/GKE:
make mirror-to-registry GKE_REGISTRY=docker.io/muralisvishnu
```

### Customer commands (import)

```bash
# Example: import vendor-published images into private registry
crane copy docker.io/vendor/cap-web@sha256:abc... \
  registry.halden.pharma/cap/cap-web:latest

# Then deploy (see customer-install.md)
bash scripts/preflight.sh
bash scripts/install.sh
bash scripts/smoke-test.sh
```

Use `image-manifest.yaml` from the release bundle as the import checklist.

---

## Tier 2 — Customer build (optional)

Use when Halden policy requires **all production images built only on Halden-controlled builders**.

| Step | Who | What |
|------|-----|------|
| 1. Build | **Customer** | Run `supply-chain/mirror.sh` on Halden build farm (`REGISTRY_HOST=registry.halden.pharma/cap`) |
| 2. Deploy | **Customer** | Same install contract: preflight → helm → smoke |

**Vendor still provides:** Dockerfiles (`supply-chain/docker/`), chart, policies, smoke tests — not a certified binary unless separately engaged.

**Trade-off:** Stronger “we built it ourselves” story; slower, more customer effort, harder to keep digest parity across sites.

---

## Addon images (Cilium, Kyverno, ingress)

Separate from Cap app images. On the **reference kind cage**, addons are **mirrored only** (no build):

- GKE relay job → `docker.io/muralisvishnu/halden-cage:<tag>` (see `supply-chain/dockerhub/`)
- Laptop/kind preloads from Docker Hub

On **shared GKE infra** (`sre-play`), use platform ingress/CNI unless approved — do not reinstall cluster-wide Cilium/Kyverno.

---

## What `mirror.sh` actually does

| Image | Action in script |
|-------|------------------|
| `cap-web`, `media-server` | **Build** from Cap git source |
| `mysql`, `minio`, `minio-mc` | **Mirror** (`docker pull` → retag → push) |

Whoever runs `mirror.sh` performs the build. In Tier 1 that is the **vendor**; in Tier 2 the **customer** runs the same script.

---

## Current FDIE practice

| Environment | Tier | Who runs `make mirror` |
|-------------|------|------------------------|
| Local kind cage | 1 (vendor) | Vendor laptop → `localhost:5001` |
| GKE `sre-play` infra | 1 (vendor) | Vendor laptop → `mirror-to-registry` → Docker Hub → GKE |
| Halden production (handoff) | 1 (default) | Vendor builds; Halden **imports** into private registry |
| Halden (if policy requires) | 2 | Halden build farm runs `mirror.sh` |

---

## Related docs

- [Customer install](customer-install.md) — Tier 1 import + deploy
- [GKE infra deploy](gke-infra-deploy.md) — Tier 1 on `gke_sre-play_us-west1_infra`
- [Release process](release.md) — packaging the bundle
- [Install contract](install-contract.md) — preflight / smoke gates
