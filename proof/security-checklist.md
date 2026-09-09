# Security checklist — Halden Cap BYOC

Use this checklist for FDIE sign-off and customer handoff. Mark each item in your change ticket.

## Supply chain

- [ ] All Cap images mirrored to private registry (`make mirror` or customer equivalent)
- [ ] Image digests recorded in `image-manifest.yaml` / change ticket
- [ ] SBOM generated (`make attest` when syft available)
- [ ] Optional: cosign signatures on mirrored images

## Admission & policy

- [ ] Kyverno policies applied (`manifests/kyverno/`)
- [ ] Private-registry-only enforced for `cap` namespace
- [ ] No privileged pods (`halden-disallow-privileged`)
- [ ] Resource limits enforced

## Network

- [ ] Cilium default-deny egress (`manifests/cilium/`)
- [ ] Kubernetes NetworkPolicy on Cap workloads
- [ ] Squid egress proxy with allowlist (`manifests/proxy/`)
- [ ] Cap pods use `HTTP_PROXY` to egress proxy

## Install contract

- [ ] `preflight.sh` passes in customer lab
- [ ] `global.registry`, `publicUrl`, `s3PublicUrl` set correctly
- [ ] All `secrets.*` rotated from example values
- [ ] `helm install` / `upgrade` completes with `--wait`

## Smoke & e2e

- [ ] `scripts/smoke-test.sh` passes (`/login`, pods ready, Minio health)
- [ ] Reference cage: `make test-e2e` / airgap proof fresh (`proof/airgap-test.log`)
- [ ] `scripts/verify-proof.sh` passes before release bundle

## Known gaps (document for customer)

| Gap | Mitigation |
|-----|------------|
| Default secrets in examples | External Secrets / Sealed Secrets |
| No TLS in kind reference | Terminate TLS at corp ingress |
| OTP in logs (air-gap dev) | Configure Resend/SMTP in prod |

## Sign-off

| Role | Status | Date |
|------|--------|------|
| Implementer | | |
| Halden security | | |
