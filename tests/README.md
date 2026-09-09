# Halden Cap test framework

Lightweight bash smoke/e2e tests for FDIE BYOC proof — no cluster deploy in CI.

## Suites

| Suite | When to run | What it checks |
|-------|-------------|----------------|
| `smoke` | After customer `helm install` in their lab | preflight, `/login`, pod rollouts, Minio health |
| `e2e` | Reference cage only | air-gap egress deny + proof artifacts |

## Usage (local reference cage)

```bash
make install-ingress
make test-smoke          # smoke suite
make test-e2e            # includes airgap (mutates egress proxy, then restores)
make test-all
```

## Usage (customer lab)

```bash
export TARGET=byoc
export REGISTRY_HOST=registry.halden.local/cap
export PUBLIC_URL=https://cap.halden.pharma
export S3_URL=https://s3.cap.halden.pharma
export PREFLIGHT_PROFILE=byoc

bash scripts/preflight.sh
bash scripts/smoke-test.sh
# Optional e2e only if customer replicated egress-system cage
```

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TARGET` | `cage` | `cage`, `byoc`, or `gke` — selects kubectl context |
| `PUBLIC_URL` | `http://127.0.0.1:30080` | Cap UI base URL |
| `S3_URL` | `http://127.0.0.1:30900` | Minio health endpoint |
| `REGISTRY_HOST` | `localhost:5001` | Private registry for image preflight |
| `PREFLIGHT_PROFILE` | `cage` | `cage` (full cage) or `byoc` (customer cluster) |
| `CAP_NAMESPACE` | `cap` | Cap namespace |

## Adding tests

1. Add `tests/smoke/NN-name.sh` (numbered for order).
2. Source `tests/lib/common.sh`, call `setup_test_env`.
3. Use `assert_http_ok` / `assert_cmd`, end with `report_summary`.
