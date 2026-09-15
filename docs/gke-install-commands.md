# Vendor: dedicated GKE lab (`halden-cage-gke`)

**Audience:** FDIE vendor only. Customers use [`customer-install.md`](customer-install.md) with `TARGET=byoc`.

This is the Terraform cluster `halden-cage-gke` in `sre-play` / `us-west1`. It is **not** shared `gke_sre-play_us-west1_infra` (`make install-gke` — see [`gke-infra-deploy.md`](gke-infra-deploy.md)).

## Prerequisites & Environment Setup

```bash
cd fdie-cap-halden

gcloud auth application-default login
gcloud config set project sre-play

export TARGET=gke
export GKE_PROJECT=sre-play
export GKE_REGION=us-west1
export DOCKERHUB_USER=muralisvishnu
```

## Step-by-Step Lifecycle

### 1. Teardown & Cluster Up

```bash
make down TARGET=gke
make up TARGET=gke
```

### 2. Docker Hub Authentication & Addons

```bash
make dockerhub-login TARGET=gke
USE_DOCKERHUB_ADDONS=1 make install-addons TARGET=gke
```

### 3. Cap Helm Installation (Docker Hub Images)

```bash
ALLOW_NON_THURSDAY=1 USE_INGRESS=1 helm upgrade --install cap ./install/helm/cap \
  --kube-context gke_sre-play_us-west1_halden-cage-gke \
  --namespace cap --create-namespace \
  -f ./install/helm/cap/values-gke.yaml \
  --set global.registry=docker.io/muralisvishnu \
  --set capWeb.image=halden-cage \
  --set capWeb.tag=cap-web-latest \
  --set mediaServer.image=halden-cage \
  --set mediaServer.tag=media-server-latest \
  --set mysql.image=halden-cage \
  --set mysql.tag=mysql-8.0 \
  --set minio.image=halden-cage \
  --set minio.tag=minio-latest \
  --set minio.mcImage=halden-cage \
  --set minio.mcTag=minio-mc-latest \
  --timeout 30m \
  --wait
```

### 4. Verification & Testing

```bash
make test-smoke TARGET=gke
make test-e2e TARGET=gke
make airgap-test TARGET=gke
make test-all TARGET=gke
```

### 5. Rollback Steps

```bash
helm history cap -n cap --kube-context gke_sre-play_us-west1_halden-cage-gke
helm rollback cap -n cap --kube-context gke_sre-play_us-west1_halden-cage-gke
# or: make rollback TARGET=gke
```

### 6. Helm Uninstall & Teardown

```bash
make uninstall TARGET=gke
make down TARGET=gke
```
