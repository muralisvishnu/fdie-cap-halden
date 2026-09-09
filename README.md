# fdie-cap-halden

BYOC install for [Cap](https://github.com/CapSoftware/Cap) under Halden Pharma-style constraints.

## Quick start (local cage)

```bash
make ensure-colima
make up
make mirror
make install-addons-dockerhub   # after GKE Docker Hub mirror (see supply-chain/dockerhub/)
make install-ingress
make status
make airgap-test
```

Open **http://127.0.0.1:30080** (no `/etc/hosts` required).

Sign in: enter email on login page, then `make auth-login` for the 6-digit OTP in logs.

Docs: `docs/runbook.md`, `docs/decisions.md`, `docs/security-review.md`

## Targets

| Target | Description |
|--------|-------------|
| `cage` | Local kind cluster on Colima (full constraint cage) |
| `gke`  | Shared GKE `sre-play` namespace deploy (after local verified) |

## Harness-inspired mechanisms (patterns only)

| Mechanism | Implementation |
|-----------|----------------|
| Outbound-only runner | `environment/manifests/runner/outbound-runner.yaml` |
| Air-gap image relocation | `supply-chain/mirror.sh` |
| Policy-as-code | Kyverno + `governance/policies/` |
| Change-window freeze | `governance/scripts/freeze-guard.sh` |
| GitOps reconciliation | `governance/gitops-app.yaml` (optional) |

No Harness product is installed.
