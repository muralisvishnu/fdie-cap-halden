# Halden Cap test framework

Lightweight bash smoke/e2e tests. Same Make targets for kind (`TARGET=cage`) and dedicated GKE (`TARGET=gke`).

## Suites

| Suite | When to run | What it checks |
|-------|-------------|----------------|
| `smoke` | After `make install-ingress` | preflight, `/login`, pod rollouts, Minio health |
| `e2e` | After smoke, if `egress-system` exists | air-gap egress deny + proof artifacts |

## Usage

```bash
# kind
make test-smoke TARGET=cage
make test-e2e TARGET=cage
make airgap-test TARGET=cage

# dedicated GKE (any cluster: set context / terraform outputs)
export TARGET=gke GKE_PROJECT=sre-play GKE_REGION=us-west1
# optional: export KUBE_CONTEXT=gke_PROJECT_REGION_CLUSTER
make test-smoke TARGET=gke
make test-e2e TARGET=gke
make airgap-test TARGET=gke
```

kind uses hostPorts `30080` / `30900`. GKE uses `kubectl port-forward` to a free laptop port (Minio avoids `30900`, which Colima often binds).

## Usage (customer lab)

```bash
export TARGET=byoc
export REGISTRY_HOST=registry.halden.local/cap
export PUBLIC_URL=https://cap.halden.pharma
export S3_URL=https://s3.cap.halden.pharma
export PREFLIGHT_PROFILE=byoc

bash scripts/preflight.sh
bash scripts/smoke-test.sh
```

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TARGET` | `cage` | `cage`, `byoc`, or `gke` — selects kubectl context |
| `KUBE_CONTEXT` | kind / terraform / `gke_$PROJECT_$REGION_$CLUSTER` | Override cluster |
| `PUBLIC_URL` | auto (port-forward or kind hostPort) | Cap UI base URL |
| `S3_URL` | auto | Minio health endpoint |
| `REGISTRY_HOST` | `localhost:5001` | Private registry for kind preflight |
| `PREFLIGHT_PROFILE` | `cage` | `cage` (full cage) or `byoc` |
| `CAP_NAMESPACE` | `cap` | Cap namespace |

## Adding tests

1. Add `tests/smoke/NN-name.sh` (numbered for order).
2. Source `tests/lib/common.sh`, call `setup_test_env`.
3. Use `assert_http_ok` / `assert_cmd`, end with `report_summary`.
