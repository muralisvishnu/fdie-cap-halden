# Corporate TLS + cage addons (Cilium, Kyverno, Ingress)

## Why addons were skipped initially

kind nodes pull images from the internet. On a laptop behind a **TLS-intercepting corporate proxy**, pulls from `quay.io`, `ghcr.io`, and `registry.k8s.io` fail with:

```
x509: certificate signed by unknown authority
```

This is the same class of problem Halden describes ("proxy terminates TLS; our CA is on the wiki"). Docker Hub (`mysql`, `minio`) often works; other registries do not until the **corporate CA is trusted**.

## What works without admin access

| Component | Works? | How |
|-----------|--------|-----|
| Cap stack | Yes | Build from git + mirror via `localhost:5001` |
| K8s NetworkPolicies | Yes | Native networking |
| Squid egress proxy | Yes | Preloaded via `docker save \| ctr import` |
| **Cilium** | No (yet) | Images on `quay.io` |
| **Kyverno** | No (yet) | Images on `ghcr.io` |
| **ingress-nginx** | No (yet) | Images on `registry.k8s.io` |

## After admin access / corp CA is installed

1. Trust the corporate CA in Colima/Docker (platform team provides the PEM):

```bash
# Example — adjust path to your corp CA file
COLIMA=1 docker run --rm -v /path/to/corp-ca.pem:/usr/local/share/ca-certificates/corp-ca.crt:ro \
  alpine sh -c 'cat /usr/local/share/ca-certificates/corp-ca.crt >> /etc/ssl/certs/ca-certificates.crt'
# Or configure Docker Desktop / Colima daemon.json with insecure-registries ONLY as last resort
```

2. Preload and install addons:

```bash
cd fdie-cap-halden
make install-addons
```

3. Optional: switch Cap to Ingress instead of NodePort:

```bash
make install-ingress
# Add to /etc/hosts: 127.0.0.1 cap.local s3.cap.local
# Open http://cap.local:30080
```

## Cilium without cluster recreate

`install-addons.sh` installs Cilium in **chaining mode** (`cni.exclusive=false`) so it coexists with kindnet on an existing cluster — no `make down` required.

For full kube-proxy replacement, recreate the cage with `disableDefaultCNI` in `environment/kind/kind-config.yaml`.
