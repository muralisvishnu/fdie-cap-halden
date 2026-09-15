# Customer install guide — Halden Cap BYOC

This is the **only** install SOP for Halden (or any BYOC customer). You install into **your** Kubernetes cluster.

Vendor lab commands (`make up`, `make mirror`, `TARGET=gke`, dedicated `halden-cage-gke`) are **not** for you. Those live in the repo README and [`gke-install-commands.md`](gke-install-commands.md).

What “contract” means: [`install-contract.md`](install-contract.md). Air-gap image drop: [`customer-image-delivery.md`](customer-image-delivery.md). Image tiers: [`image-supply-model.md`](image-supply-model.md).

**Done means:** `scripts/preflight.sh` and `scripts/smoke-test.sh` both exit **0** in your lab.

## How to use this document

Work **top to bottom**. Do not Helm-install until preflight passes. Do not apply kind-cage Cilium chaining on GKE Dataplane V2. Patch Kyverno’s registry allowlist **before** you apply policies, or admission will reject your images.

## 1. Receive the bundle

From a release tag (`v0.1.0`) you get `halden-cap-bundle-<version>.tar.gz`:

| Artifact | Purpose |
|----------|---------|
| `chart/cap-<version>.tgz` | Helm chart |
| `image-manifest.yaml` | Image list + digests |
| `values-customer.example.yaml` | Required values template |
| `manifests/` | Example Kyverno, Cilium, egress proxy, RBAC — **adapt** |
| `scripts/install.sh`, `preflight.sh`, `smoke-test.sh` | Install contract |
| `tests/` | Smoke / e2e for your lab |
| `proof/` | Vendor **reference** proof — not your prod evidence |

Verify: `shasum -a 256 -c halden-cap-bundle-*.tar.gz.sha256`

## 2. Images — Tier 1 (default)

Vendor ships **`halden-cap-images-<ver>.tar.gz`** separately (see [customer-image-delivery.md](customer-image-delivery.md)).

```bash
tar -xzf halden-cap-images-0.1.0.tar.gz
cd halden-cap-images-0.1.0
shasum -a 256 -c SHA256SUMS

export REGISTRY_HOST=registry.halden.pharma/cap
bash import-release-images.sh .
```

Connected lab alternative: `crane copy` from the vendor registry using digests in `image-manifest.yaml`.

Record digests in your change ticket.

### Image names

Vendor cage uses `cap/cap-web:latest` on an in-cluster registry. Your Helm values use **flat** names under `global.registry` (see `values-customer.example.yaml`): `registry.halden.pharma/cap/cap-web:latest`, and so on. Import scripts must match those names.

### Tier 2 (optional)

Only if policy requires images built on Halden builders:

```bash
REGISTRY_HOST=registry.halden.pharma/cap bash supply-chain/mirror.sh
```

Digest parity is then Halden’s responsibility.

## 3. Helm values

Copy `values-customer.example.yaml` → `values-halden.yaml`. Day-2 commands and the full field table: [`runbook.md`](runbook.md).

Do **not** start from `values.yaml` / `values-cage*.yaml` / `values-gke*.yaml`. Keep image names **flat** (`cap-web`, not `cap/cap-web`) so Helm `registry/image:tag` matches preflight.

| Value | Required | Notes |
|-------|----------|-------|
| `global.registry` | Yes | Same string as `REGISTRY_HOST` (example `registry.halden.pharma/cap`) |
| `capWeb.image` etc. | Yes | Flat names in the example file |
| `publicUrl` / `s3PublicUrl` | Yes | Cap UI + Minio; desktop app uses `publicUrl` |
| `ingress.className` / `host` / `s3Host` | If ingress enabled | Your class and DNS names (not `cap.local`) |
| `secrets.*` | Yes | Rotate all defaults; External Secrets in prod |

## 4. Policies (adapt — do not copy kind as-is)

| Do | Do not |
|----|--------|
| Add **your** registry host to Kyverno `halden-private-registry-only` (replace `localhost:5001` / vendor Hub allowlist) | Apply kind Cilium **chaining** manifests on a cluster that already runs GKE Dataplane V2 / vendor Cilium |
| Apply NetworkPolicy / egress examples after reviewing CIDRs and namespaces | Point pods at `cage-registry.cage-system:5000` |
| Align freeze-guard with **your** change window, or skip it | Rely on Thursday-only `freeze-guard.sh` unless that is your process |

Kyverno example: allow `registry.halden.pharma/cap/*` (and your ingress/Kyverno images if those charts pull from the same cluster).

## 5. Preflight + install

Same command block lives in the repo [`README.md`](../README.md) under **Customer: install Cap (`TARGET=byoc`)**.

Always `TARGET=byoc`. Switch kubectl to **your** cluster first (`KUBE_CONTEXT` is not applied automatically).

Thursday freeze: `scripts/install.sh` calls `freeze-guard.sh`. If your window is not Thursday, set `ALLOW_NON_THURSDAY=1` or disable that guard in your fork.

```bash
export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export REGISTRY_HOST=registry.halden.pharma/cap
export KUBE_CONTEXT=your-cluster-context
export VALUES_FILE="$(pwd)/values-halden.yaml"
# export ALLOW_NON_THURSDAY=1   # if not installing on Thursday

bash scripts/preflight.sh
```

Then either Helm directly:

```bash
helm upgrade --install cap chart/cap-0.1.0.tgz \
  --namespace halden-cap --create-namespace \
  -f values-halden.yaml \
  --set global.registry="${REGISTRY_HOST}" \
  --wait --timeout 25m
```

Or the contract wrapper (same values file):

```bash
TARGET=byoc PREFLIGHT_PROFILE=byoc \
  REGISTRY_HOST="${REGISTRY_HOST}" KUBE_CONTEXT="${KUBE_CONTEXT}" \
  VALUES_FILE="${VALUES_FILE}" \
  bash scripts/install.sh
```

Do **not** set `TARGET=gke`. That target is the vendor dedicated GKE lab (Docker Hub `halden-cage:*` tags).

## 6. Smoke test

```bash
export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export PUBLIC_URL=https://cap.halden.pharma
export S3_URL=https://s3.cap.halden.pharma
export REGISTRY_HOST=registry.halden.pharma/cap

bash scripts/smoke-test.sh
```

Expect `/login` HTTP 200, Cap pods ready, Minio healthy.

## 7. Proof artifacts

Bundle `proof/` is **vendor cage** evidence. Re-run in your lab if auditors need your cluster:

```bash
bash scripts/verify-proof.sh
```

## 8. Support checklist

- [ ] Images imported; names match `global.registry`
- [ ] Kyverno allowlist includes **your** registry
- [ ] Kind-only Cilium chaining **not** applied on GKE
- [ ] `values-halden.yaml` filled; secrets rotated
- [ ] `preflight.sh` exit 0
- [ ] Helm install complete
- [ ] `smoke-test.sh` exit 0
- [ ] Desktop app pointed at `publicUrl`
