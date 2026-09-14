# Dedicated GKE cage cluster

Ephemeral GKE cluster for the **vendor** lab (`TARGET=gke`). Customers do not use this module — see [`docs/customer-install.md`](../../../docs/customer-install.md).

Command reference: [`docs/gke-install-commands.md`](../../../docs/gke-install-commands.md).

## Lifecycle (Apple Silicon: skip mirror)

```bash
export TARGET=gke GKE_PROJECT=sre-play GKE_REGION=us-west1
export DOCKERHUB_USER=muralisvishnu

make up TARGET=gke
make dockerhub-login TARGET=gke
make install-addons TARGET=gke
ALLOW_NON_THURSDAY=1 make install-ingress TARGET=gke
make test-smoke TARGET=gke

make uninstall TARGET=gke
make down TARGET=gke
```

Do **not** `make mirror TARGET=gke` on Apple Silicon (amd64 QEMU OOM). Cap/addons pull Hub `muralisvishnu/halden-cage:*`.

## Note on shared infra

`install/terraform/gke/` (namespace-only on `gke_sre-play_us-west1_infra`) is **legacy**. See [`docs/gke-infra-deploy.md`](../../../docs/gke-infra-deploy.md).
