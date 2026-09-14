# fdie-cap-halden

BYOC packaging for [Cap](https://github.com/CapSoftware/Cap) under Halden-style constraints (private registry, policies, smoke gates). **No Harness product is installed.**

This README is a **map**. Use the table below, then open only the doc for your job. Do not mix vendor cage commands with a customer cluster.

## Which docs should I read?

| I am… | Goal | Start here | Then |
|-------|------|------------|------|
| **Customer (Halden)** installing Cap in **our** cluster | Import images, Helm, smoke | [`docs/customer-install.md`](docs/customer-install.md) | [`docs/install-contract.md`](docs/install-contract.md) · [`docs/customer-image-delivery.md`](docs/customer-image-delivery.md) · copy [`install/helm/cap/values-customer.example.yaml`](install/helm/cap/values-customer.example.yaml) |
| Customer receiving a tarball | Air-gap image drop | [`docs/customer-image-delivery.md`](docs/customer-image-delivery.md) | Same install guide as above |
| Customer / auditor | What “pass” means | [`docs/install-contract.md`](docs/install-contract.md) | [`proof/security-checklist.md`](proof/security-checklist.md) |
| **Vendor** proving the stack on a laptop | kind cage | This README → *Vendor: kind* | [`docs/runbook.md`](docs/runbook.md) |
| Vendor proving on **dedicated** GKE `halden-cage-gke` | Terraform cluster in `sre-play` | [`docs/gke-install-commands.md`](docs/gke-install-commands.md) | Not the shared infra cluster |
| Vendor cutting a customer bundle | Tag + tarball | [`docs/release.md`](docs/release.md) | [`docs/image-supply-model.md`](docs/image-supply-model.md) |
| AI assistant | Orient before running commands | [`AGENTS.md`](AGENTS.md) | [`docs/ai-protocol.md`](docs/ai-protocol.md) |

**Customers never run** `make up`, `make mirror`, or `TARGET=gke`. Those are vendor lab clusters. Customer install is always **`TARGET=byoc`** against **your** kubectl context and **your** private registry.

## Customer — how to use the docs (short)

1. Read [`docs/install-contract.md`](docs/install-contract.md) so you know the three gates: inputs → `preflight.sh` → install → `smoke-test.sh`.
2. Follow [`docs/customer-install.md`](docs/customer-install.md) in order (do not skip Kyverno registry allowlist).
3. Fill **your** `values-halden.yaml` from `values-customer.example.yaml` (registry, URLs, secrets, ingress class).
4. Import **pinned** images per [`docs/customer-image-delivery.md`](docs/customer-image-delivery.md) (Tier 1) or build only if policy requires Tier 2 ([`docs/image-supply-model.md`](docs/image-supply-model.md)).
5. Apply **adapted** policy examples from the bundle — not kind-specific Cilium chaining and not the vendor Docker Hub allowlist as-is.
6. Pass = `preflight.sh` and `smoke-test.sh` both exit 0 in **your** lab.

## Customer: install Cap (`TARGET=byoc`)

`TARGET=byoc` does **not** create a cluster. It uses **whatever kubectl already talks to**, skips kind/GKE lab wiring, and Helm-installs Cap. It does **not** run `make up`, `make mirror`, addons, or Docker Hub `halden-cage:*`.

**You must already have:** a reachable cluster, images in **your** registry (`cap-web`, `media-server`, `mysql`, `minio`, `minio-mc` under `REGISTRY_HOST`), filled `values-halden.yaml`, and adapted policies (Kyverno allowlist for **your** registry — not kind Cilium chaining).

`KUBE_CONTEXT` is not passed to kubectl automatically. Switch context first.

```bash
cd fdie-cap-halden   # or the extracted customer bundle

kubectl config use-context YOUR_CONTEXT
kubectl cluster-info

cp install/helm/cap/values-customer.example.yaml values-halden.yaml
# edit: global.registry, publicUrl, s3PublicUrl, secrets, ingress.className

export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export REGISTRY_HOST=registry.halden.pharma/cap   # must match imported images
export VALUES_FILE="$(pwd)/values-halden.yaml"
export ALLOW_NON_THURSDAY=1                      # required unless it is Thursday

bash scripts/preflight.sh
bash scripts/install.sh
```

Smoke (use **your** URLs from values, not `http://127.0.0.1:30080`):

```bash
export TARGET=byoc
export PUBLIC_URL=https://cap.halden.pharma
export S3_URL=https://s3.cap.halden.pharma
bash scripts/smoke-test.sh
```

Same Helm as `install.sh` (no freeze-guard):

```bash
helm upgrade --install cap install/helm/cap \
  --namespace halden-cap --create-namespace \
  -f values-halden.yaml \
  --set global.registry="${REGISTRY_HOST}" \
  --wait --timeout 25m
```

From a release tarball, use `chart/cap-*.tgz` instead of `install/helm/cap`. Full SOP: [`docs/customer-install.md`](docs/customer-install.md).

**Do not run** with `TARGET=byoc`: `make up`, `make mirror`, `make install-addons`, `make install-ingress`.

If you omit `REGISTRY_HOST` / `VALUES_FILE`, preflight looks for `docker.io/muralisvishnu/cap-web:latest` (wrong for Halden and for Hub `halden-cage:*` tags).

`make install-gke` is a **different** `byoc` path (shared `gke_sre-play_us-west1_infra`). See [`docs/gke-infra-deploy.md`](docs/gke-infra-deploy.md).

## Vendor: kind (reference cage)

```bash
export TARGET=cage
make ensure-colima
make up
make mirror
make install-addons
ALLOW_NON_THURSDAY=1 make install-ingress
make test-smoke
make airgap-test
```

Open **http://127.0.0.1:30080**. OTP: `make auth-login`. If `make mirror` skips Cap, force: `CAP_MIRROR_FORCE=1 make mirror TARGET=cage`.

## Vendor: dedicated GKE lab (`halden-cage-gke`)

Same Make target names, `TARGET=gke`. On Apple Silicon **do not** `make mirror` (amd64 QEMU OOM). Pull Cap/addons from Docker Hub `muralisvishnu/halden-cage:*`. Full sequence: [`docs/gke-install-commands.md`](docs/gke-install-commands.md).

**Not the same cluster** as shared `gke_sre-play_us-west1_infra` (`make install-gke`). That path is legacy: [`docs/gke-infra-deploy.md`](docs/gke-infra-deploy.md).

## Make `TARGET` values

| `TARGET` | Who | Cluster |
|----------|-----|---------|
| `cage` | Vendor | Local kind `halden-cage` |
| `gke` | Vendor | Dedicated Terraform GKE `halden-cage-gke` |
| `byoc` | **Customer** | Their cluster (`PREFLIGHT_PROFILE=byoc`) |

## Related (optional)

| Doc | Audience |
|-----|----------|
| [`docs/decisions.md`](docs/decisions.md) | ADRs |
| [`docs/security-review.md`](docs/security-review.md) | Threat model |
| [`tests/README.md`](tests/README.md) | Smoke / e2e |
| [`docs/gke-install-commands.md`](docs/gke-install-commands.md) | Vendor dedicated GKE only |
