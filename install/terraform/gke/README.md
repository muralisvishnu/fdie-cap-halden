# GKE deploy — sre-play

Provisions the **namespace + quota** on shared GKE. Cap itself is installed via Helm (`TARGET=gke`).

## Prerequisites

- `kubectl` context: `gke_sre-play_us-west1_infra`
- Images on Docker Hub: `make mirror-gke-dockerhub`

## Apply

```bash
cd install/terraform/gke
terraform init
terraform apply
```

## Build + push Cap images (customer infra)

```bash
make mirror
docker login
make mirror-to-registry GKE_REGISTRY=docker.io/muralisvishnu
make preflight-gke
```

## Install Cap

```bash
make install-gke
```

See [`docs/gke-infra-deploy.md`](../../docs/gke-infra-deploy.md) for full steps. Adjust `values-gke.yaml` / `values-gke-infra.yaml` for registry and ingress hostnames.
