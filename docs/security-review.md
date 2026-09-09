# Security review — Halden Cap BYOC (local cage)

## Threat model (abbreviated)

| Asset | Risk | Mitigation |
|-------|------|------------|
| Container images | Supply-chain tampering | Private registry only; Kyverno `halden-private-registry-only`; digest capture in `supply-chain/artifacts/` |
| Egress | Data exfiltration | Squid allowlist; Cilium default-deny; Cap pods use `HTTP_PROXY` |
| Lateral movement | Cross-namespace access | NetworkPolicies; namespace-scoped RBAC |
| Privileged workloads | Container escape | Kyverno `halden-disallow-privileged`; PodSecurity baseline on `cap` ns |
| Change control | Unapproved deploys | Thursday freeze guard; Helm revision history |

## Controls implemented

- **Admission:** Kyverno (registry, limits, no privileged)
- **Network:** Kubernetes NetworkPolicy + CiliumClusterwideNetworkPolicy
- **Egress:** Squid proxy with domain allowlist (`environment/manifests/proxy/`)
- **Secrets:** K8s Secret `cap-secrets` (placeholder values for local dev — rotate for real deploys)
- **RBAC:** `environment/manifests/rbac/cap-namespace.yaml`

## Known gaps (local dev)

| Gap | Severity | Notes |
|-----|----------|-------|
| Default secrets in Helm values | High for prod | Replace with External Secrets / Sealed Secrets on GKE |
| `allowExternalIngress: true` in localhost ingress overlay | Low | Required for NodePort Minio without `/etc/hosts` |
| No TLS on ingress | Medium | Acceptable for kind; terminate TLS at corp ingress on GKE |
| cosign/SBOM optional | Medium | Run `make attest` when `syft`/`cosign` installed |
| Email OTP in logs | Low (dev) | Expected for air-gap; disable in prod with Resend |

## Verification checklist

- [ ] `make preflight` passes
- [ ] Kyverno policies `Enforce` in `cap` namespace
- [ ] `make airgap-test` passes with fresh proof timestamp
- [ ] No pods running as `privileged: true`
- [ ] Images only from `localhost:5001/*` (local) or approved Docker Hub tags

## Sign-off

| Role | Status | Date |
|------|--------|------|
| FDIE implementer | Local cage verified | 2026-09-09 |
| Halden security review | Pending formal review | — |
