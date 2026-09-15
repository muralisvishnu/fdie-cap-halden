# Corporate TLS + cage addons (Cilium, Kyverno, Ingress)

## Why addons were skipped initially

kind nodes pull images from the internet. On a laptop behind a **TLS-intercepting corporate proxy**, pulls from `quay.io`, `ghcr.io`, and `registry.k8s.io` fail with:

```
x509: certificate signed by unknown authority
```

We **do not** run Squid `ssl_bump` in the cage (**ADR-009**). Proof packet: [`proof/constraints.md`](../proof/constraints.md).

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
USE_DOCKERHUB_ADDONS=1 make install-addons TARGET=cage
```

3. Optional: install Cap via Helm with Ingress enabled (Catch-All on 30080 per ADR-005 — no `/etc/hosts` required):

```bash
ALLOW_NON_THURSDAY=1 USE_INGRESS=1 helm upgrade --install cap ./install/helm/cap \
  --kube-context kind-halden-cage \
  --namespace cap --create-namespace \
  -f ./install/helm/cap/values-cage.yaml \
  -f ./install/helm/cap/values-cage-ingress-localhost.yaml \
  --set global.registry=docker.io/muralisvishnu \
  --set capWeb.image=halden-cage \
  --set capWeb.tag=cap-web-latest \
  --set mediaServer.image=halden-cage \
  --set mediaServer.tag=media-server-latest \
  --set mysql.image=halden-cage \
  --set mysql.tag=mysql-8.0 \
  --set minio.image=halden-cage \
  --set minio.tag=minio-latest \
  --set minio.mcImage=halden-cage \
  --set minio.mcTag=minio-mc-latest \
  --timeout 30m \
  --wait

# Open http://127.0.0.1:30080 in your browser
```

## Cilium without cluster recreate

`install-addons.sh` installs Cilium in **chaining mode** (`cni.exclusive=false`) so it coexists with kindnet on an existing cluster — no `make down` required.

For full kube-proxy replacement, recreate the cage with `disableDefaultCNI` in `environment/kind/kind-config.yaml`.
