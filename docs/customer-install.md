# Customer install guide — Halden Cap BYOC

This is the **customer-facing** half of the install contract. For what “contract” means and who does what, see [install-contract.md](install-contract.md). For how the vendor cuts a release, see [release.md](release.md). **AI assistants:** start at [AGENTS.md](../AGENTS.md) or [ai-protocol.md](ai-protocol.md) Protocol 2.

**Summary:** Halden mirrors images, applies policies, installs the Helm chart in **your** cluster, and runs smoke tests in **your** lab. If `preflight.sh` and `smoke-test.sh` both exit 0, the install meets spec.

## 1. Receive the bundle

From a release tag (`v0.1.0`) you get `halden-cap-bundle-<version>.tar.gz` containing:

| Artifact | Purpose |
|----------|---------|
| `chart/cap-<version>.tgz` | Helm chart |
| `image-manifest.yaml` | Image list + digests (after vendor mirror) |
| `values-customer.example.yaml` | Required values template |
| `manifests/` | Kyverno, Cilium, egress proxy, RBAC |
| `scripts/install.sh`, `preflight.sh`, `smoke-test.sh` | Install contract |
| `tests/` | Smoke / e2e framework for your lab |
| `proof/` | Reference air-gap proof + security checklist |

Verify checksum: `shasum -a 256 -c halden-cap-bundle-*.tar.gz.sha256`

## 2. Mirror images into your private registry

Use `image-manifest.yaml` and `supply-chain/mirror.sh` (in the full repo) as patterns. Every Cap pod image must resolve under your registry prefix, e.g. `registry.halden.pharma/cap/cap-web:latest`.

Kyverno policy enforces approved registries only — update `environment/manifests/kyverno/policies.yaml` for your registry host before apply.

Optional: generate SBOM + cosign signatures (`make attest`) and record digests in your change ticket.

## 3. Required Helm values

Copy `values-customer.example.yaml` → `values-halden.yaml` and set:

| Value | Required | Notes |
|-------|----------|-------|
| `global.registry` | Yes | Private registry host/path prefix |
| `publicUrl` | Yes | Cap UI URL (desktop app uses this) |
| `s3PublicUrl` | Yes | Minio/S3 API URL |
| `secrets.*` | Yes | Rotate all defaults; use External Secrets in prod |
| `ingress.className` | If ingress enabled | Match your ingress controller |

Install:

```bash
export TARGET=byoc
export REGISTRY_HOST=registry.halden.pharma/cap
export KUBECTL="kubectl --context your-cluster"

bash scripts/preflight.sh   # registry + images only (PREFLIGHT_PROFILE=byoc)

helm upgrade --install cap chart/cap-0.1.0.tgz \
  --namespace cap --create-namespace \
  -f values-halden.yaml \
  --set global.registry="${REGISTRY_HOST}" \
  --wait --timeout 25m
```

Or use `scripts/install.sh` with `TARGET=gke` and your values file paths.

## 4. Lab smoke test (customer)

After install:

```bash
export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export PUBLIC_URL=https://cap.halden.pharma
export S3_URL=https://s3.cap.halden.pharma
export REGISTRY_HOST=registry.halden.pharma/cap

bash scripts/smoke-test.sh
```

This runs `preflight` + smoke suite: `/login` HTTP 200, pod rollouts, Minio health.

## 5. Proof artifacts (vendor reference)

The bundle includes **reference** proof from the vendor cage (`proof/airgap-test.log`, `security-checklist.md`). These demonstrate the pattern works — they do not prove your production cluster.

Re-run in your lab if required:

```bash
bash scripts/verify-proof.sh
```

## 6. Change control

`governance/scripts/freeze-guard.sh` blocks installs outside Thursday unless `ALLOW_NON_THURSDAY=1`. Adapt or remove for your change window.

## 7. Support checklist

- [ ] Images mirrored to private registry
- [ ] Kyverno / Cilium / egress policies applied (or equivalent)
- [ ] `preflight.sh` passes
- [ ] `helm install` completes
- [ ] `smoke-test.sh` passes
- [ ] Desktop app pointed at `publicUrl`
- [ ] Secrets rotated from example values
