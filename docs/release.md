# Release process — Halden Cap BYOC

This doc is for **you (the vendor / FDIE implementer)** cutting a customer handoff. Customers receive a tarball; they do not clone this repo or run your CI.

## What a release is

A **release** is a versioned, immutable bundle:

```
dist/halden-cap-bundle-<version>.tar.gz
dist/halden-cap-bundle-<version>.tar.gz.sha256
```

It contains everything Halden needs to install Cap in **their** cluster: Helm chart, image manifest (pinned digests from **vendor** `make mirror`), policy manifests, install scripts, smoke tests, and reference proof artifacts.

**Tier 1 (default):** bundle does **not** include image layers — Halden imports from the manifest. See [image-supply-model.md](image-supply-model.md).

| Not a release | Is a release |
|---------------|--------------|
| `git push` to `main` | Tagged `v0.1.0` + attached bundle |
| CI passing on GitHub | Checksum-verified tarball you email / upload |
| Your local kind cage running | Frozen chart version + manifest + proof snapshot |

CI on `main` only **validates** the chart packages correctly. A **release** is the artifact you hand to the customer.

## Version numbering

Chart version lives in `install/helm/cap/Chart.yaml`:

```yaml
version: 0.1.0
```

Release tag must match: `v0.1.0` → bundle `halden-cap-bundle-0.1.0.tar.gz`.

Bump `version` in `Chart.yaml` before tagging a new release.

## Pre-release checklist (reference cage)

Run on your local kind cage to refresh proof and digests:

```bash
make ensure-colima
make up
make mirror
make install-addons
make install-ingress

make test-smoke                 # smoke suite
make test-e2e                   # airgap e2e (optional but recommended)
make airgap-test                # refreshes proof/airgap-test.log

make attest                     # optional: SPDX SBOM + cosign (needs syft/cosign)
make verify-proof               # proof/security-checklist present + airgap timestamp
make package                    # dist/halden-cap-bundle-<version>.tar.gz
```

Verify the bundle:

```bash
cd dist
shasum -a 256 -c halden-cap-bundle-*.tar.gz.sha256
tar -tzf halden-cap-bundle-*.tar.gz | head
```

Commit proof updates if airgap was re-run:

```bash
git add proof/airgap-test.log proof/airgap-response.html
git commit -m "Refresh airgap proof for release"
```

## Cut a release locally

```bash
# 1. Bump Chart.yaml version (e.g. 0.1.0 → 0.1.1)
# 2. Complete pre-release checklist above
make package

# 3. Tag and push
git tag v0.1.0
git push origin main --tags
```

## Cut a release via GitHub Actions

Pushing a tag triggers `.github/workflows/release.yml`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow:

1. Runs `supply-chain/package-release.sh`
2. Runs `scripts/verify-proof.sh` (warns if proof is missing)
3. Uploads `halden-cap-bundle-*.tar.gz` + `.sha256` to [GitHub Releases](https://github.com/muralisvishnu/fdie-cap-halden/releases)

You can also trigger manually: **Actions → release → Run workflow**.

**Note:** The GitHub workflow does not run `make mirror` or airgap tests — proof and digests must already be in the repo (or manifest will show `digest: null`). Refresh proof on your reference cage before tagging.

## Bundle contents

| Path in bundle | Source in repo |
|----------------|----------------|
| `chart/cap-<version>.tgz` | `helm package install/helm/cap` |
| `image-manifest.yaml` | `supply-chain/generate-image-manifest.sh` |
| `values-customer.example.yaml` | `install/helm/cap/values-customer.example.yaml` |
| `manifests/` | `environment/manifests/{kyverno,cilium,proxy,network,rbac}` |
| `scripts/` | `install.sh`, `preflight.sh`, `smoke-test.sh`, `verify-proof.sh` |
| `tests/` | `tests/{smoke,e2e,lib,runner.sh}` |
| `proof/` | `proof/airgap-test.log`, `security-checklist.md`, etc. |
| `sbom/` | `supply-chain/artifacts/*.spdx.json` (if `make attest` was run) |
| `README-BUNDLE.md` | Generated index for the customer |

## What to send Halden

1. `halden-cap-bundle-<version>.tar.gz` + `.sha256`
2. `halden-cap-images-<version>.tar.gz` + `.sha256` (`make export-release-images`)
3. `docs/customer-image-delivery.md` (in bundle) — SFTP/USB/DMZ playbook
4. Change ticket referencing digests from `image-manifest.yaml`

See [customer-image-delivery.md](customer-image-delivery.md) for secure transfer options.

## CI vs release

| | CI (`ci.yml` on PR/main) | Release (`release.yml` on tag) |
|--|--------------------------|--------------------------------|
| Purpose | Catch broken charts early | Ship customer artifact |
| Cluster | None | None |
| Output | Pass/fail | GitHub Release attachment |
| Proof | Not generated | Bundles existing `proof/` |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `digest: null` in manifest | Run `make mirror` on reference cage; digests land in `supply-chain/artifacts/` |
| `verify-proof` warns on old airgap log | Re-run `make airgap-test` |
| Bundle missing SBOMs | Install `syft`, run `make attest` before `make package` |
| Tag push but no Release asset | Check Actions tab; ensure `contents: write` permission on workflow |

## Related docs

- [AGENTS.md](../AGENTS.md) — AI entry point (included in bundle)
- [AI protocol](ai-protocol.md) — vendor + customer playbooks for AI
- [Customer install contract](customer-install.md) — what Halden must do with the bundle
- [Install contract explained](install-contract.md) — what “contract” means in BYOC
- [Runbook](runbook.md) — reference cage day-to-day ops
