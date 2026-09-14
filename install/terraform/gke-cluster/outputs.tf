output "kube_context" {
  description = "kubectl context name for this cluster"
  value       = "gke_${var.project_id}_${var.region}_${var.cluster_name}"
}

output "cluster_name" {
  value = google_container_cluster.cage.name
}

output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}
