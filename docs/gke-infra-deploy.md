# GKE deploy — `gke_sre-play_us-west1_infra`

Deploy Cap on the shared **sre-play infra** GKE cluster. This follows **Tier 1** image supply: **vendor builds, pushes to a registry, GKE pulls** — Halden/customer does not compile Cap for this path.

See [image-supply-model.md](image-supply-model.md) for Tier 1 vs Tier 2.

---

## Image supply on this cluster (Tier 1)

```
Vendor laptop                    Registry                    GKE infra
─────────────                    ────────                    ─────────
make mirror          ──►   localhost:5001
(build cap-web,               (bootstrap)
 mirror mysql/minio)
       │
make mirror-to-registry ──►  docker.io/muralisvishnu
                             /cap-web, /media-server, …
                                      │
make install-gke         ◄────────────┘  (imagePull)
```

| Image type | How it gets there | Who |
|------------|-------------------|-----|
| Cap app (`cap-web`, `media-server`, `mysql`, `minio`) | `mirror.sh` **builds** Cap; `mirror-to-registry.sh` **pushes** | **Vendor** (your laptop) |
| Addon (Cilium, Kyverno, ingress) | GKE crane job → Docker Hub relay (kind cage only) | Not installed on shared infra by default |

The release bundle does **not** ship image layers — only `image-manifest.yaml` + digests after vendor `make mirror`.

**Tier 2 (optional):** Halden runs `mirror.sh` on their build farm — not used for this GKE demo.

---

## Prerequisites

```bash
kubectl config use-context gke_sre-play_us-west1_infra
kubectl cluster-info
docker login -u muralisvishnu   # for mirror-to-registry
```

---

## 1. Namespace + quota

```bash
cd install/terraform/gke
terraform init && terraform apply
kubectl get ns halden-cap
```

---

## 2. Vendor build + push (Tier 1)

On your **vendor** machine with Colima/Docker (not on GKE):

```bash
cd fdie-cap-halden

make ensure-colima
make mirror                              # build Cap + mirror bases → localhost:5001

make mirror-to-registry GKE_REGISTRY=docker.io/muralisvishnu
```

Pushes:

- `docker.io/muralisvishnu/cap-web:latest`
- `docker.io/muralisvishnu/media-server:latest`
- `docker.io/muralisvishnu/mysql:8.0`
- `docker.io/muralisvishnu/minio:latest`
- `docker.io/muralisvishnu/minio-mc:latest`

Optional before handoff: `make attest` for SBOM/digests.

For a private registry instead of Docker Hub:

```bash
make mirror-to-registry GKE_REGISTRY=registry.example.com/cap
```

Update `GKE_REGISTRY` / `values-gke.yaml` `global.registry` to match.

---

## 3. Preflight (GKE-aware)

```bash
make preflight-gke
```

Verifies: kubectl → cluster, registry API, all five Cap images at `docker.io/muralisvishnu/*`.

---

## 4. Install

```bash
make install-gke
```

Uses `values-gke.yaml` + `values-gke-infra.yaml` (`prometheus` IngressClass, infra hostnames). Edit DNS in `values-gke-infra.yaml` before real use.

Manual equivalent:

```bash
TARGET=gke KUBE_CONTEXT=gke_sre-play_us-west1_infra \
  REGISTRY_HOST=docker.io/muralisvishnu CAP_NAMESPACE=halden-cap \
  USE_GKE_INFRA_VALUES=1 ALLOW_NON_THURSDAY=1 bash scripts/install.sh
```

---

## 5. Smoke test

```bash
export TARGET=gke
export CAP_NAMESPACE=halden-cap
export KUBE_CONTEXT=gke_sre-play_us-west1_infra
export PUBLIC_URL=https://cap-halden.infra.harness.io   # match values-gke-infra.yaml
export S3_URL=https://s3-cap-halden.infra.harness.io
export REGISTRY_HOST=docker.io/muralisvishnu
export PREFLIGHT_PROFILE=gke

make test-smoke
```

---

## 6. Status / teardown

```bash
make status-gke
helm uninstall cap -n halden-cap
```

---

## Halden handoff vs this GKE demo

| | GKE infra demo (this doc) | Halden production (Tier 1 handoff) |
|--|---------------------------|-----------------------------------|
| Who builds | Vendor (you) | Vendor (you) |
| Registry | `docker.io/muralisvishnu` (lab relay) | `registry.halden.pharma` (customer import) |
| Customer action | — | Import pinned digests from vendor manifest |
| Bundle | — | `halden-cap-bundle-*.tar.gz` |

Same Tier 1 model — only the registry and cluster change.

---

## Targets summary

| `TARGET` | Install | Preflight | Registry default |
|----------|---------|-----------|------------------|
| `cage` | kind + Colima | `cage` | `localhost:5001` |
| `gke` | this cluster | `gke` | `docker.io/muralisvishnu` |
| `byoc` | customer K8s | `gke` | customer `REGISTRY_HOST` |

---

## Related

- [Image supply model](image-supply-model.md)
- [Customer install](customer-install.md)
- [Release process](release.md)
