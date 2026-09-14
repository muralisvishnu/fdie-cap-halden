# Docker Hub relay: `muralisvishnu/halden-cage`

**Vendor lab only.** Kind can preload these tags; dedicated GKE `TARGET=gke` pulls them over HTTPS. Customers import **pinned** images into **their** registry — see [`docs/customer-install.md`](../../docs/customer-install.md).

## Image tags

All images: `docker.io/muralisvishnu/halden-cage:<tag>`

| Tag | Component |
|-----|-----------|
| `cilium-v1.20.1` | Cilium agent |
| `cilium-operator-v1.20.1` | Cilium operator |
| `cilium-envoy-v1.20.1` | Cilium envoy |
| `kyvernopre-v1.13.2` | Kyverno init |
| `kyverno-v1.13.2` | Kyverno admission |
| `kyverno-bg-v1.13.2` | Kyverno background controller |
| `kyverno-cleanup-v1.13.2` | Kyverno cleanup controller |
| `kyverno-reports-v1.13.2` | Kyverno reports controller |
| `ingress-controller-v1.15.1` | ingress-nginx controller |
| `ingress-certgen-v1.6.9` | ingress-nginx admission webhook certgen |

Full mapping: [`tags.yaml`](tags.yaml)

## 1. GKE — mirror to Docker Hub

```bash
kubectl config use-context gke_sre-play_us-west1_infra

kubectl apply -f supply-chain/dockerhub/manifests/namespace.yaml

kubectl -n vishnusmurali create secret docker-registry dockerhub-creds \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=muralisvishnu \
  --docker-password="$DOCKERHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# Run crane mirror job
make mirror-gke-dockerhub
kubectl -n vishnusmurali logs -f job/halden-image-mirror
```

Verify on Docker Hub: `muralisvishnu/halden-cage` should show 10 tags.

## 2. Laptop — pull from Docker Hub → kind → install addons

```bash
docker login -u muralisvishnu

make install-addons-dockerhub
# = pull muralisvishnu/halden-cage:* from Docker Hub
#   import into kind with upstream retags
#   helm install cilium + kyverno + ingress-nginx
```

## 3. Optional — also copy into local registry `localhost:5001`

```bash
make mirror-dockerhub-to-local
```

Pulls each tag from Docker Hub and pushes to `localhost:5001/halden-cage:<tag>` for fully air-gapped local registry use.

## 4. Cleanup GKE

```bash
kubectl -n vishnusmurali delete job halden-image-mirror
```
