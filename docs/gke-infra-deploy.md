# GKE deploy — `gke_sre-play_us-west1_infra`

Cap **app images are built/mirrored in your infra** (not pre-shipped by the vendor). The reference flow: build on a machine with Docker → push to a registry GKE can pull → `make preflight-gke` → `make install-gke`.

## Image model (BYOC)

| Step | Where | Command |
|------|-------|---------|
| Build Cap from source | Customer build host / CI | `make mirror` (or `supply-chain/mirror.sh`) |
| Push to cloud registry | Same host | `make mirror-to-registry` or customer crane/skopeo |
| Pull in GKE | Cluster | Helm sets `global.registry` + image names |

Addon images (Cilium, Kyverno) are optional on shared infra — use platform controls unless approved.

## 1. Namespace

```bash
kubectl config use-context gke_sre-play_us-west1_infra
cd install/terraform/gke && terraform init && terraform apply
```

## 2. Build + push Cap images

On a host with Docker (laptop after `make mirror`, or customer build VM):

```bash
make mirror                              # builds to localhost:5001
docker login -u muralisvishnu            # or customer registry creds
make mirror-to-registry GKE_REGISTRY=docker.io/muralisvishnu
```

This pushes: `muralisvishnu/cap-web`, `media-server`, `mysql`, `minio`, `minio-mc`.

For a private registry: `make mirror-to-registry GKE_REGISTRY=registry.example.com/cap`

## 3. Preflight (GKE-aware)

```bash
make preflight-gke
```

Checks: kubectl → cluster, registry API, all five Cap images exist at `docker.io/muralisvishnu/*`.

## 4. Install

```bash
make install-gke
```

Uses `values-gke.yaml` + `values-gke-infra.yaml` (prometheus IngressClass, infra hostnames). Edit hostnames/DNS in `values-gke-infra.yaml` before prod use.

Or manually:

```bash
TARGET=gke KUBE_CONTEXT=gke_sre-play_us-west1_infra \
  REGISTRY_HOST=docker.io/muralisvishnu CAP_NAMESPACE=halden-cap \
  USE_GKE_INFRA_VALUES=1 ALLOW_NON_THURSDAY=1 bash scripts/install.sh
```

## 5. Smoke test

```bash
export TARGET=gke
export CAP_NAMESPACE=halden-cap
export KUBE_CONTEXT=gke_sre-play_us-west1_infra
export PUBLIC_URL=https://cap-halden.infra.harness.io   # match values
export S3_URL=https://s3-cap-halden.infra.harness.io
export REGISTRY_HOST=docker.io/muralisvishnu
export PREFLIGHT_PROFILE=gke

make test-smoke
```

## 6. Status / teardown

```bash
make status-gke
helm uninstall cap -n halden-cap
```

## Targets summary

| `TARGET` | `make install` | Preflight profile | Registry default |
|----------|----------------|-------------------|------------------|
| `cage` | kind + Colima | `cage` | `localhost:5001` |
| `gke` | real GKE | `gke` | `docker.io/muralisvishnu` |
| `byoc` | customer K8s | `gke` | customer `REGISTRY_HOST` |
