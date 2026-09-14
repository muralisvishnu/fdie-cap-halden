# Runbook — Halden Cap BYOC (local cage)

## Prerequisites

- Colima + Docker
- `kubectl`, `helm`, `kind`
- Optional: `syft`, `cosign` for supply-chain attestation

## Bring up the cage

```bash
make ensure-colima
make up                    # kind + registry + proxy + RBAC
make mirror                # build/push Cap images to localhost:5001
make install-addons        # Cilium, Kyverno, ingress-nginx
make install-ingress       # Cap via ingress at http://127.0.0.1:30080
```

## Access Cap (no /etc/hosts)

| URL | Purpose |
|-----|---------|
| http://127.0.0.1:30080 | Cap web UI |
| http://127.0.0.1:30900 | Minio S3 API |

## Sign in (no email server)

1. Open http://127.0.0.1:30080/login
2. Enter any email (e.g. `you@halden.local`)
3. In another terminal: `make auth-login` (or `bash scripts/auth-login.sh you@halden.local`)
4. Copy the 6-digit code from logs into the UI

## Desktop app (screen recording)

1. Install [Cap desktop](https://cap.so/download)
2. Settings → **Custom server URL**: `http://127.0.0.1:30080`
3. Sign in with the same email OTP flow
4. Record a short clip; verify upload reaches Minio

## Health checks

```bash
make status
curl -fsS http://127.0.0.1:30080/login >/dev/null && echo OK
curl -fsS http://127.0.0.1:30900/minio/health/live && echo OK
kubectl -n egress-system get pods   # egress-proxy should be Running
```

## Air-gap proof

```bash
make airgap-test    # denies all egress, probes Cap, restores proxy automatically
```

Artifacts: `proof/airgap-test.log`, `proof/airgap-response.html`

## Restore egress proxy (if stuck after manual testing)

```bash
bash scripts/restore-egress-proxy.sh
```

## Other clusters (not this runbook)

- Dedicated vendor GKE lab: [`docs/gke-install-commands.md`](gke-install-commands.md) (`TARGET=gke`).
- Legacy shared infra: [`docs/gke-infra-deploy.md`](gke-infra-deploy.md) (`make install-gke`).
- Customer BYOC: [`docs/customer-install.md`](customer-install.md) (`TARGET=byoc`).

## Tear down

```bash
make uninstall
make down
```
