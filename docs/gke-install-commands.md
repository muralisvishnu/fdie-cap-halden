# Vendor: dedicated GKE lab (`halden-cage-gke`)

**Audience:** FDIE vendor only. Customers use [`customer-install.md`](customer-install.md) with `TARGET=byoc`.

This is the Terraform cluster `halden-cage-gke` in `sre-play` / `us-west1`. It is **not** shared `gke_sre-play_us-west1_infra` (`make install-gke` — see [`gke-infra-deploy.md`](gke-infra-deploy.md)).

## Prerequisites

```bash
cd fdie-cap-halden

gcloud auth application-default login
gcloud config set project sre-play

export TARGET=gke
export GKE_PROJECT=sre-play
export GKE_REGION=us-west1
export DOCKERHUB_USER=muralisvishnu
# PAT in the environment only — never commit, never paste into docs
```

## Apple Silicon (this Mac)

GKE nodes are `linux/amd64`. QEMU Cap builds OOM on Mac. **Skip `make mirror TARGET=gke`.**

Kubelet cannot pull the in-cluster **HTTP** registry. Cap and addons pull **HTTPS Docker Hub**: `docker.io/muralisvishnu/halden-cage:*` plus Secret `dockerhub-creds`.

```bash
export TARGET=gke GKE_PROJECT=sre-play GKE_REGION=us-west1
export DOCKERHUB_USER=muralisvishnu

make up TARGET=gke
make dockerhub-login TARGET=gke
make install-addons TARGET=gke
ALLOW_NON_THURSDAY=1 make install-ingress TARGET=gke
make test-smoke TARGET=gke
make airgap-test TARGET=gke
```

Mirror on **amd64 Linux** only if you need the in-cluster registry path (not used for Hub installs).

## After install

```bash
bash environment/scripts/port-forwards.sh start-ingress TARGET=gke
open http://127.0.0.1:30080
make auth-login TARGET=gke
```

## Teardown

```bash
make uninstall TARGET=gke   # Helm release only
make down TARGET=gke        # terraform destroy
```

`make gke-full` recreates the cluster. On Apple Silicon do **not** rely on it to build Cap images.

## Policy stack (vendor lab)

| Control | Notes |
|---------|--------|
| Kyverno | `environment/manifests/kyverno/` — allowlist includes Hub `halden-cage` |
| Cilium | GKE mode (`gke.enabled=true`), not kind chaining |
| Squid / NetworkPolicy / runner | Same intent as kind; images from Hub on this cluster |

## vs kind

| | kind (`TARGET=cage`) | Dedicated GKE (`TARGET=gke`) |
|--|----------------------|------------------------------|
| Cluster | `kind create` | Terraform `install/terraform/gke-cluster/` |
| Platform | host arch (arm64 on Apple Silicon) | `linux/amd64` |
| Cap images | `localhost:5001/cap/*` after `make mirror` | Hub `halden-cage:<role>-latest` |
| Addons | `make install-addons` (kind registry or Hub preload) | Hub + `dockerhub-creds` |
