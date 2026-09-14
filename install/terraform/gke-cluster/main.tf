provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_container_cluster" "cage" {
  name     = var.cluster_name
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = "default"
  subnetwork = "default"

  # Lab cluster in sre-play — destroy after testing (make down TARGET=gke).
  deletion_protection = false

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Allow Cilium + Kubernetes NetworkPolicy (same constraint stack as kind cage).
  network_policy {
    enabled = true
  }
}

resource "google_container_node_pool" "cage" {
  name       = "${var.cluster_name}-pool"
  location   = var.region
  cluster    = google_container_cluster.cage.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
    tags = ["halden-cage-nodeport"]
    labels = {
      "halden.cap/role" = "cage-gke"
    }
  }
}

# NodePort smoke (30080, 30900) when not using port-forward — lab only.
resource "google_compute_firewall" "cage_nodeport" {
  name    = "${var.cluster_name}-nodeport"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["30080", "30900"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["halden-cage-nodeport"]
}
