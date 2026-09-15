# Runbook — Halden Cap

Standard Operating Procedures (SOP) for bringing up, testing, rolling back, and tearing down Halden Cap across the three deployment targets:
1. **Local kind cage (`TARGET=cage`)** — Local development & testing on Mac/Linux
2. **Dedicated GKE lab (`TARGET=gke`)** — Cloud lab cluster in GCP (`sre-play`)
3. **Customer Bring-Your-Own-Cloud (`TARGET=byoc`)** — Customer production/staging cluster

---

## 1. Local kind cage (`TARGET=cage`)

Local development and testing using a kind cluster on Docker (Colima on macOS or Docker Desktop).

### Bring-Up & Install Steps

```bash
# 1. Tear down any existing local cage cluster
make down TARGET=cage

# 2. Bootstrap the kind cluster
make up TARGET=cage

# 3. Install CNI & Addons (Cilium, Kyverno, ingress-nginx) using Docker Hub images
USE_DOCKERHUB_ADDONS=1 make install-addons TARGET=cage

# 4. Install Cap via Helm pulling flat images from Docker Hub
ALLOW_NON_THURSDAY=1 USE_INGRESS=1 helm upgrade --install cap ./install/helm/cap \
  --kube-context kind-halden-cage \
  --namespace cap --create-namespace \
  -f ./install/helm/cap/values-cage.yaml \
  -f ./install/helm/cap/values-cage-ingress-localhost.yaml \
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

### Verification & Testing Steps

```bash
# Smoke test (preflight, pod readiness, login API check)
make test-smoke TARGET=cage

# End-to-end user workflows
make test-e2e TARGET=cage

# Airgap network policy test (verifies operation with egress denied)
make airgap-test TARGET=cage

# Run all test suites
make test-all TARGET=cage
```

### Rollback Steps

If an upgrade or release fails or exhibits unexpected behavior, roll back to the previous Helm revision:

```bash
# Check release history to identify revision numbers
helm history cap -n cap --kube-context kind-halden-cage

# Roll back to the previous revision
helm rollback cap -n cap --kube-context kind-halden-cage

# Alternatively, rollback to a specific revision (e.g. revision 1)
helm rollback cap 1 -n cap --kube-context kind-halden-cage

# Or use Makefile target:
make rollback TARGET=cage

# Verify rollout status after rollback
make test-smoke TARGET=cage
```

### Helm Uninstall & Teardown Steps

```bash
# Uninstall the Cap Helm release
helm uninstall cap -n cap --kube-context kind-halden-cage

# Clean up remaining Jobs and PVCs in cap namespace
kubectl --context kind-halden-cage -n cap delete job --all --ignore-not-found
kubectl --context kind-halden-cage -n cap delete pvc --all --ignore-not-found

# Or perform complete workload uninstall via Makefile:
make uninstall TARGET=cage

# Complete cluster teardown (deletes kind cluster)
make down TARGET=cage
```

---

## 2. Dedicated GKE Lab (`TARGET=gke`)

Cloud testing in GCP `sre-play` project (`halden-cage-gke` cluster).

### Environment Setup & Prerequisites

```bash
export TARGET=gke
export GKE_PROJECT=sre-play
export GKE_REGION=us-west1
export DOCKERHUB_USER=muralisvishnu

# Ensure GCP application credentials are standard
gcloud auth application-default login
gcloud config set project sre-play
```

### Bring-Up & Install Steps

```bash
# 1. Tear down existing GKE cluster (if present)
make down TARGET=gke

# 2. Bootstrap GKE cluster via Terraform
make up TARGET=gke

# 3. Configure Docker Hub credentials & Install Addons
make dockerhub-login TARGET=gke
USE_DOCKERHUB_ADDONS=1 make install-addons TARGET=gke

# 4. Install Cap via Helm using Docker Hub images
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

### Verification & Testing Steps

```bash
# Smoke test
make test-smoke TARGET=gke

# End-to-end tests
make test-e2e TARGET=gke

# Airgap test
make airgap-test TARGET=gke

# All test suites
make test-all TARGET=gke
```

### Rollback Steps

```bash
# Check Helm revision history
helm history cap -n cap --kube-context gke_sre-play_us-west1_halden-cage-gke

# Roll back to the previous revision
helm rollback cap -n cap --kube-context gke_sre-play_us-west1_halden-cage-gke

# Or use Makefile target:
make rollback TARGET=gke

# Re-verify cluster health
make test-smoke TARGET=gke
```

### Helm Uninstall & Teardown Steps

```bash
# Uninstall Cap workload
make uninstall TARGET=gke

# Complete cluster teardown (destroys GKE Terraform resources)
make down TARGET=gke
```

---

## 3. Customer Bring-Your-Own-Cloud (`TARGET=byoc`)

Customer deployment into customer-managed Kubernetes infrastructure.

> **Note:** Customers do not run `make up`, `make down`, `make mirror`, or lab Make targets.

### Preconditions & Setup

1. kubectl context pointed to **your** cluster (`kubectl cluster-info`).
2. Private container registry populated with images (`REGISTRY_HOST`).
3. Customer values file created from `values-customer.example.yaml`.

```bash
kubectl config use-context YOUR_CUSTOMER_CONTEXT

cp install/helm/cap/values-customer.example.yaml values-halden.yaml
# Edit values-halden.yaml: set global.registry, publicUrl, s3PublicUrl, secrets, ingress

export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export CAP_NAMESPACE=halden-cap
export REGISTRY_HOST=registry.halden.pharma/cap
export VALUES_FILE="$(pwd)/values-halden.yaml"
export ALLOW_NON_THURSDAY=1
```

### Bring-Up & Install Steps

```bash
# 1. Execute Preflight check
bash scripts/preflight.sh

# 2. Install Cap via script or direct Helm command
bash scripts/install.sh

# Concrete Helm upgrade/install example pulling flat images from customer registry:
# Constructs:
#   registry.halden.pharma/cap/cap-web:latest
#   registry.halden.pharma/cap/media-server:latest
#   registry.halden.pharma/cap/mysql:8.0
#   registry.halden.pharma/cap/minio:latest
#   registry.halden.pharma/cap/minio-mc:latest
helm upgrade --install cap ./install/helm/cap \
  --kube-context YOUR_CUSTOMER_CONTEXT \
  --namespace halden-cap --create-namespace \
  -f values-halden.yaml \
  --set global.registry=registry.halden.pharma/cap \
  --set capWeb.image=cap-web \
  --set capWeb.tag=latest \
  --set mediaServer.image=media-server \
  --set mediaServer.tag=latest \
  --set mysql.image=mysql \
  --set mysql.tag="8.0" \
  --set minio.image=minio \
  --set minio.tag=latest \
  --set minio.mcImage=minio-mc \
  --set minio.mcTag=latest \
  --timeout 25m \
  --wait
```

### Verification & Testing Steps

```bash
export PUBLIC_URL=https://cap.halden.pharma
export S3_URL=https://s3.cap.halden.pharma

bash scripts/smoke-test.sh
```

### Rollback Steps

```bash
# View deployment revision history
helm history cap -n halden-cap

# Roll back to prior revision
helm rollback cap -n halden-cap

# Verify status after rollback
bash scripts/smoke-test.sh
```

### Helm Uninstall Steps

```bash
# Uninstall Helm release
helm uninstall cap -n halden-cap

# Remove remaining Jobs and PVCs in customer namespace
kubectl -n halden-cap delete job --all --ignore-not-found
kubectl -n halden-cap delete pvc --all --ignore-not-found
```
