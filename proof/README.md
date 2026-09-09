# Proof artifacts — Halden Cap BYOC

Evidence for the FDIE round that the **reference cage pattern** works. Customers receive copies in the release bundle; production proof is their responsibility.

| File | Meaning |
|------|---------|
| `airgap-test.log` | Timestamp when Cap served with egress proxy fully denied |
| `airgap-response.html` | HTTP body captured during air-gap test |
| `security-checklist.md` | Controls verification checklist |

## Regenerate (reference cage)

```bash
make install-ingress
make airgap-test
bash scripts/verify-proof.sh
```

## Verify before release

```bash
make verify-proof
make package   # includes proof/ in bundle
```
