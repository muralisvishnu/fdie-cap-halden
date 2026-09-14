# Legacy: namespace on shared GKE `gke_sre-play_us-west1_infra`

Not the dedicated lab cluster (`install/terraform/gke-cluster/`). Not the customer SOP.

```bash
cd install/terraform/gke
terraform init
terraform apply
```

Cap install: `make install-gke` (Helm `TARGET=byoc` + `USE_GKE_INFRA_VALUES=1`). Details: [`docs/gke-infra-deploy.md`](../../../docs/gke-infra-deploy.md).
