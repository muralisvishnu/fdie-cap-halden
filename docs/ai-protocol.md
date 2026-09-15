# AI protocol — Halden Cap BYOC

Structured playbooks for AI assistants helping with **vendor reference cage** work or **customer infrastructure** installs.

**Entry point:** [`AGENTS.md`](../AGENTS.md)  
**Human docs:** [`install-contract.md`](install-contract.md), [`customer-install.md`](customer-install.md), [`release.md`](release.md)

---

## Protocol 0 — Orient (always first)

Before running commands, determine:

```
1. MODE: vendor | customer
2. CLUSTER ACCESS: kind-halden-cage | customer kubectl context
3. GOAL: dev | release | customer-install | debug | proof
4. REGISTRY: localhost:5001 | customer private registry
```

Ask the human for missing items. **Do not guess** `REGISTRY_HOST`, `PUBLIC_URL`, or secrets.

---

## Protocol 1 — Vendor reference cage (full stack)

**Goal:** Reproduce the FDIE constraint cage locally.

### Preconditions
- Colima/Docker running
- `kubectl`, `helm`, `kind` installed

### Steps (in order — do not skip)

| Step | Command | Pass criteria |
|------|---------|---------------|
| 1. Cage | `make ensure-colima && make up` | `kubectl --context kind-halden-cage get nodes` Ready |
| 2. Mirror Cap | `make mirror` | 5 images in `localhost:5001` (cap-web, media-server, mysql, minio, minio-mc) |
| 3. Addons | `USE_DOCKERHUB_ADDONS=1 make install-addons TARGET=cage` | Cilium, Kyverno, ingress-nginx pods Running |
| 4. Install Cap | `helm upgrade --install cap ./install/helm/cap ...` (see `runbook.md`) | `curl -fsS http://127.0.0.1:30080/login` |
| 5. Smoke | `make test-smoke` | Exit 0 |
| 6. Proof (optional) | `make airgap-test && make verify-proof` | `proof/airgap-test.log` updated |

### AI must not
- Skip addons unless human says "minimal debug"
- Commit secrets from Helm values
- Run `make destroy` without confirmation

---

## Protocol 2 — Customer infrastructure install

**Goal:** Install Cap in Halden's cluster using the release bundle.

### Preconditions (collect from human)

| Input | Example | Required |
|-------|---------|----------|
| `REGISTRY_HOST` | `registry.halden.pharma/cap` | Yes |
| `KUBECTL` context | `kubectl --context halden-gke-prod` | Yes |
| `PUBLIC_URL` | `https://cap.halden.pharma` | Yes |
| `S3_URL` | `https://s3.cap.halden.pharma` | Yes |
| `values-halden.yaml` path | Customer-created from example | Yes |
| Ingress class | `nginx` / `gce` | If ingress enabled |

### Steps (in order)

#### 2a. Extract and verify bundle

```bash
shasum -a 256 -c halden-cap-bundle-*.tar.gz.sha256
tar -xzf halden-cap-bundle-*.tar.gz
cd halden-cap-bundle-*/
```

#### 2b. Mirror images (customer network)

Use `image-manifest.yaml`. Every Cap image must exist at `${REGISTRY_HOST}/<repo>:<tag>`.

Pattern (customer adapts tool — crane, skopeo, harbor sync):

```bash
# Example — customer replaces SRC/DEST
crane copy localhost:5001/cap/cap-web:latest "${REGISTRY_HOST}/cap/cap-web:latest"
```

AI should **generate a mirror script** from `image-manifest.yaml`, not pull from public internet into customer prod without approval.

#### 2c. Patch Kyverno registry policy

Edit `manifests/kyverno/policies.yaml` (or customer's fork):

```yaml
# Change pattern from:
image: "localhost:5001/* | docker.io/muralisvishnu/halden-cage:*"
# To:
image: "registry.halden.pharma/cap/*"
```

Apply: `kubectl apply -f manifests/kyverno/`

#### 2d. Apply policy stack (if not already present)

Adapt bundle `manifests/` to the customer CNI (do **not** apply kind Cilium chaining on GKE Dataplane V2). Patch Kyverno registry allowlist to their host. Apply NetworkPolicy / egress / RBAC only after review. If they already have equivalent controls, document equivalency — do not duplicate.

#### 2e. Preflight gate

```bash
export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export REGISTRY_HOST=registry.halden.pharma/cap
export KUBECTL="kubectl --context halden-gke-lab"

bash scripts/preflight.sh   # must exit 0
```

#### 2f. Helm install

```bash
helm upgrade --install cap chart/cap-*.tgz \
  --namespace cap --create-namespace \
  -f values-halden.yaml \
  --set global.registry="${REGISTRY_HOST}" \
  --wait --timeout 25m
```

Or with full repo: `TARGET=byoc PREFLIGHT_PROFILE=byoc VALUES_FILE=values-halden.yaml REGISTRY_HOST=... bash scripts/install.sh`

#### 2g. Acceptance

```bash
export PUBLIC_URL=https://cap.halden.pharma
export S3_URL=https://s3.cap.halden.pharma
bash scripts/smoke-test.sh   # must exit 0
```

#### 2h. Sign-off

Walk human through `proof/security-checklist.md` items relevant to their environment.

### AI must not
- Assume kind or Colima exist on customer side
- Push images to customer registry without explicit credentials handling
- Disable network policies "to get it working" without documenting as temporary exception
- Store generated secrets in chat logs or git

---

## Protocol 3 — Release bundle (vendor)

**Goal:** Ship `halden-cap-bundle-<version>.tar.gz` to customer.

See [`release.md`](release.md). AI checklist:

- [ ] `install/helm/cap/Chart.yaml` version bumped
- [ ] `make test-smoke` passed on reference cage
- [ ] `make verify-proof` passed
- [ ] `make package` produced tarball + sha256
- [ ] `image-manifest.yaml` in bundle has digests (or document that customer must verify after mirror)
- [ ] Tag `vX.Y.Z` pushed → GitHub Release workflow

---

## Protocol 4 — Debug failing install

Run diagnostics in order:

```bash
kubectl -n cap get pods -o wide
kubectl -n cap describe pod -l app=cap-web
kubectl -n cap logs deployment/cap-web --tail=100
kubectl -n kyverno get clusterpolicy
kubectl get events -n cap --sort-by='.lastTimestamp' | tail -20
```

| Failure class | Likely cause | Fix |
|---------------|--------------|-----|
| ImagePullBackOff | Registry / Kyverno | Mirror image; fix registry in values + policy |
| Kyverno reject | Privileged / wrong registry | Check policy violations in events |
| Probe failures | NetworkPolicy | Chart uses exec probes — check pod logs |
| 502 on ingress | Service not ready | `kubectl -n cap rollout status deployment/cap-web` |
| Minio smoke fail | Wrong S3_URL or NodePort | Align `s3PublicUrl` with actual endpoint |

---

## Prompt templates for humans

### Start customer install session

```
I'm installing Halden Cap BYOC in [lab/prod].
- Registry: registry.example.com/cap
- Cluster context: my-gke-context
- Cap URL: https://cap.example.com
- Bundle version: 0.1.0
Follow docs/ai-protocol.md Protocol 2.
```

### Start vendor cage session

```
Bring up the reference cage and run smoke tests.
Follow docs/ai-protocol.md Protocol 1.
```

### Cut a release

```
Prepare release v0.1.1: refresh proof, package bundle, list what to send Halden.
Follow docs/ai-protocol.md Protocol 3.
```

---

## Acceptance criteria summary

| Gate | Command | Exit code |
|------|---------|-----------|
| Registry + images | `bash scripts/preflight.sh` | 0 |
| Install complete | `helm upgrade --install ... --wait` | 0 |
| Smoke | `bash scripts/smoke-test.sh` | 0 |
| Proof (vendor) | `bash scripts/verify-proof.sh` | 0 |
| Human sign-off | `proof/security-checklist.md` | All relevant boxes checked |

---

## Security protocol for AI

1. **Secrets:** Never print `values-halden.yaml` contents if they contain real passwords. Reference key names only.
2. **Credentials:** Tell human to export registry creds locally; use `kubectl create secret` or External Secrets — do not embed in commands you log.
3. **Proof vs prod:** `proof/airgap-test.log` is reference-cage evidence — customer must re-run equivalent tests in their lab if required.
4. **Change control:** `governance/scripts/freeze-guard.sh` may block install — use `ALLOW_NON_THURSDAY=1` only when human approves.
