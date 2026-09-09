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

## Install Cap

```bash
export CAP_NAMESPACE=halden-cap
export REGISTRY_INCLUSTER=docker.io/muralisvishnu/halden-cage  # or private registry in-cluster
TARGET=gke ALLOW_NON_THURSDAY=1 make install-ingress
```

Adjust `install/helm/cap/values-gke.yaml` for your registry and ingress hostname.
