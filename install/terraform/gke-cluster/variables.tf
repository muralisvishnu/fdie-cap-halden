variable "project_id" {
  description = "GCP project for the dedicated Halden cage GKE cluster"
  type        = string
  default     = "sre-play"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-west1"
}

variable "cluster_name" {
  description = "GKE cluster name (lab — destroy after testing)"
  type        = string
  default     = "halden-cage-gke"
}

variable "node_count" {
  description = "Worker nodes"
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "Node machine type"
  type        = string
  default     = "e2-standard-4"
}
