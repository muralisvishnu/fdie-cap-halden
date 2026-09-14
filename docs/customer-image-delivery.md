# Customer image delivery — air-gap and secure transfer

How Halden receives **two packages** per release when there is **no internet** in production (and often no GitHub access).

| Package | Contents | Typical size |
|---------|----------|--------------|
| `halden-cap-bundle-<ver>.tar.gz` | Chart, scripts, manifest, proof, policies | Small (MB) |
| `halden-cap-images-<ver>.tar.gz` | Offline `docker save` tarballs + checksums | Large (GB) |

Docker Hub and public registries are **lab/vendor relay only** — not the production delivery path.

See also: [image-supply-model.md](image-supply-model.md), [customer-install.md](customer-install.md), [release.md](release.md).

---

## Vendor: produce both packages

After reference cage build:

```bash
cd fdie-cap-halden
make mirror
make attest                    # optional: SBOM + cosign
make package                   # halden-cap-bundle-<ver>.tar.gz
make export-release-images     # halden-cap-images-<ver>.tar.gz
```

Outputs in `dist/`:

```
halden-cap-bundle-0.1.0.tar.gz
halden-cap-bundle-0.1.0.tar.gz.sha256
halden-cap-images-0.1.0.tar.gz
halden-cap-images-0.1.0.tar.gz.sha256
```

Record digests from `dist/halden-cap-bundle-*/image-manifest.yaml` in the change ticket.

---

## How packages reach Halden (delivery channels)

Pick **Halden-approved** channel(s) — not defined in software:

| Channel | Air-gap | Typical use |
|---------|---------|-------------|
| **Secure SFTP / vendor portal** | ✅ | Encrypted upload; Halden downloads on import bastion |
| **Encrypted USB / physical media** | ✅ | True air-gap sites |
| **Halden IT ticket attachment** | ✅ | Pilot / small releases |
| **Private artifact repo** (Artifactory/Harbor) | ✅ | Halden mirrors vendor drop internally |
| **DMZ staging host** | ✅ | One-way import then internal sync (see below) |
| **GitHub Release** | ⚠️ | FDIE / vendor dev only — often blocked in pharma prod |

**Always send:** both `.tar.gz` files **and** matching `.sha256` checksum files.

---

## DMZ import pattern (no internet in prod zone)

```
┌─────────────────┐     secure drop      ┌──────────────────┐     internal only    ┌─────────────────────┐
│ Vendor (you)    │ ──────────────────►  │ DMZ import host  │ ──────────────────►  │ registry.halden...  │
│ bundle + images │   SFTP / USB         │ docker load/push │                      │ (air-gapped zone)   │
└─────────────────┘                      └──────────────────┘                      └─────────────────────┘
                                                    │
                                                    ▼
                                         K8s pulls only private registry
```

1. DMZ host may have **one-way** or **controlled** inbound from vendor.  
2. No outbound internet from production cluster or registry.  
3. Change ticket records tarball SHA-256 + image digests from manifest.

---

## Customer: receive and verify

### 1. Verify checksums

```bash
shasum -a 256 -c halden-cap-bundle-0.1.0.tar.gz.sha256
shasum -a 256 -c halden-cap-images-0.1.0.tar.gz.sha256
```

### 2. Extract

```bash
tar -xzf halden-cap-bundle-0.1.0.tar.gz
tar -xzf halden-cap-images-0.1.0.tar.gz
```

### 3. Import images (bastion with registry access, no public internet required)

```bash
cd halden-cap-images-0.1.0
shasum -a 256 -c SHA256SUMS

export REGISTRY_HOST=registry.halden.pharma/cap
bash import-release-images.sh .
```

### 4. Deploy from bundle

```bash
cd halden-cap-bundle-0.1.0
cp values-customer.example.yaml values-halden.yaml
# edit registry, URLs, secrets

export TARGET=byoc
export PREFLIGHT_PROFILE=byoc
export REGISTRY_HOST=registry.halden.pharma/cap
export KUBE_CONTEXT=<halden-lab-context>

bash scripts/preflight.sh
helm upgrade --install cap chart/cap-0.1.0.tgz \
  -n halden-cap --create-namespace \
  -f values-halden.yaml \
  --set global.registry="${REGISTRY_HOST}" \
  --wait
bash scripts/smoke-test.sh
```

---

## USB workflow (field checklist)

| Step | Action |
|------|--------|
| 1 | Vendor copies 4 files to encrypted USB: both `.tar.gz` + both `.sha256` |
| 2 | Halden security scans media per policy |
| 3 | Import bastion verifies checksums |
| 4 | Import images → private registry |
| 5 | Extract bundle → lab cluster install + smoke |
| 6 | Sign `proof/security-checklist.md` for prod promotion |

---

## SFTP workflow (field checklist)

| Step | Action |
|------|--------|
| 1 | Vendor uploads to `sftp.vendor.example/releases/0.1.0/` |
| 2 | Halden ticket references version + SHA-256 from vendor email |
| 3 | Import team downloads on DMZ host only |
| 4 | Same verify → import → deploy as above |

---

## What is NOT in the bundle

- Container image layers (separate `halden-cap-images-*.tar.gz`)
- Halden secrets or registry credentials
- Live deploy into Halden prod (customer runs install contract)

---

## Vendor GitHub Release (optional)

Tag `v0.1.0` uploads **bundle only** via `.github/workflows/release.yml`.  
For FDIE handoff, also export and deliver **images package** through Halden's secure channel.

```bash
git tag v0.1.0 && git push origin v0.1.0   # bundle on GitHub Releases
# Still ship halden-cap-images-*.tar.gz via SFTP/USB
```

---

## Troubleshooting

| Issue | Check |
|-------|--------|
| `preflight` missing images | Re-run `import-release-images.sh`; confirm `REGISTRY_HOST` |
| SHA256 mismatch | Re-download; do not extract corrupted tarballs |
| `docker push` denied | Registry credentials on bastion; repo path matches Kyverno policy |
| Digest mismatch vs manifest | Wrong image package version — bundle and images versions must match |
