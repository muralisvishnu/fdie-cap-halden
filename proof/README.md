# Proof artifacts — Halden Cap BYOC

**Start here for “hit it and logged it”:** [`constraints.md`](constraints.md)

| File | Meaning |
|------|---------|
| `constraints.md` | Index of constraints, logs, workarounds |
| `allowlist.yaml` | Egress allow/deny entries |
| `airgap-test.log` | Cap still serving under Squid full deny |
| `squid-denials.log` | Cap → HTTP_PROXY → example.com blocked |
| `corp-tls-quay-pull.log` | Live `docker pull` quay.io (MITM or success) |
| `freeze-guard-blocked.log` | Non-Thursday install refused |
| `kyverno-deny-public-image.log` | Public nginx denied in `cap` |
| `registry-catalog.log` | In-cluster registry `_catalog` |
| `squid-access-log-oom.log` | File access_log OOM’d Squid |
| `gke-http-registry.log` | COS kubelet HTTP vs HTTPS |
| `security-checklist.md` | Sign-off |

```bash
make capture-constraints
make capture-denials
make airgap-test
make record-install    # still need uncut .cast
bash scripts/verify-proof.sh
```
