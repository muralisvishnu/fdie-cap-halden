# Legacy: shared GKE `gke_sre-play_us-west1_infra`

**Audience:** vendor only. **Not** the customer SOP. **Not** dedicated `halden-cage-gke`.

| Cluster | How | Doc |
|---------|-----|-----|
| Dedicated lab `halden-cage-gke` | `TARGET=gke` + Terraform | [`gke-install-commands.md`](gke-install-commands.md) |
| Customer cluster | `TARGET=byoc` | [`customer-install.md`](customer-install.md) |
| **This page** — shared infra namespace | `make install-gke` (`TARGET=byoc` + `USE_GKE_INFRA_VALUES=1`) | Below |

Namespace/quota Terraform: `install/terraform/gke/`. Images: vendor `make mirror` then `make mirror-to-registry` to Docker Hub flat names (`cap-web`, …), then:

```bash
kubectl config use-context gke_sre-play_us-west1_infra
make install-gke
```

Helm overlays: `install/helm/cap/values-gke.yaml` + `values-gke-infra.yaml`. Adjust hostnames/registry there. This path does **not** install the full kind policy cage on shared infra by default.
