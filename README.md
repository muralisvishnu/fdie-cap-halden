# fdie-cap-halden

BYOC install for [Cap](https://github.com/CapSoftware/Cap) under Halden Pharma-style constraints.

## Quick start (local reference cage)

```bash
make ensure-colima
make up
make mirror
make install-addons-dockerhub   # after GKE Docker Hub mirror (see supply-chain/dockerhub/)
make install-ingress
make status
make test-smoke
make airgap-test
make verify-proof
```

Open **http://127.0.0.1:30080** (no `/etc/hosts` required).

Sign in: enter email on login page, then `make auth-login` for the 6-digit OTP in logs.

## Customer handoff (BYOC bundle)

CI validates the chart; **customers** deploy in their own cluster. Release packaging:

```bash
make mirror && make attest    # optional SBOM + cosign
make airgap-test && make verify-proof
make package                # dist/halden-cap-bundle-<version>.tar.gz
```

| Doc | Audience |
|-----|----------|
| [`docs/release.md`](docs/release.md) | Vendor — how to cut a release bundle |
| [`docs/install-contract.md`](docs/install-contract.md) | Both — what “contract” means in BYOC |
| [`docs/customer-install.md`](docs/customer-install.md) | Customer — step-by-step install guide |

| Deliverable | Location |
|-------------|----------|
| Helm chart | `install/helm/cap/` → packaged in bundle |
| Image manifest + digests | `supply-chain/generate-image-manifest.sh` |
| Policy manifests | `environment/manifests/` |
| Smoke / e2e tests | `tests/` — `make test-smoke`, `make test-e2e` |
| Proof artifacts | `proof/` — airgap log, security checklist |

Tag `v0.1.0` triggers `.github/workflows/release.yml` to attach the bundle to GitHub Releases.

## AI assistants

- **`AGENTS.md`** — start here (Cursor, Claude Code, Copilot)
- `docs/ai-protocol.md` — vendor + customer playbooks with gates and commands
- `.cursor/rules/halden-byoc.mdc` — Cursor always-on rule

## Docs

- `docs/release.md` — release process (vendor)
- `docs/install-contract.md` — BYOC install contract explained
- `docs/customer-install.md` — customer install guide
- `docs/image-supply-model.md` — Tier 1 (vendor build + customer import) vs Tier 2
- `docs/customer-image-delivery.md` — air-gap bundle + images via SFTP/USB/DMZ
- `docs/gke-infra-deploy.md` — GKE infra cluster deploy (Tier 1)
- `docs/runbook.md` — reference cage operations
- `docs/decisions.md` — ADRs
- `docs/security-review.md` — threat model
- `tests/README.md` — smoke/e2e framework

## Targets

| Target | Description |
|--------|-------------|
| `cage` | Local kind cluster on Colima (full constraint cage) |
| `byoc` | Customer cluster (`PREFLIGHT_PROFILE=byoc`) |
| `gke`  | `gke_sre-play_us-west1_infra` — see `docs/gke-infra-deploy.md` |

## Harness-inspired mechanisms (patterns only)

| Mechanism | Implementation |
|-----------|----------------|
| Outbound-only runner | `environment/manifests/runner/outbound-runner.yaml` |
| Air-gap image relocation | `supply-chain/mirror.sh` |
| Policy-as-code | Kyverno + `environment/manifests/kyverno/` |
| Change-window freeze | `governance/scripts/freeze-guard.sh` |
| Release bundle | `supply-chain/package-release.sh` |

No Harness product is installed.
