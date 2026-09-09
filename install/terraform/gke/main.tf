terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

variable "kube_context" {
  description = "kubectl context for sre-play GKE"
  type        = string
  default     = "gke_sre-play_us-west1_infra"
}

variable "namespace" {
  description = "Tenant namespace on shared GKE"
  type        = string
  default     = "halden-cap"
}

provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = var.kube_context
}

resource "kubernetes_namespace" "cap" {
  metadata {
    name = var.namespace
    labels = {
      "halden.cap/tenant"  = "halden-pharma"
      "halden.cap/purpose" = "cap-byoc"
    }
  }
}

resource "kubernetes_resource_quota" "cap" {
  metadata {
    name      = "halden-cap-quota"
    namespace = kubernetes_namespace.cap.metadata[0].name
  }
  spec {
    hard = {
      "pods"             = "30"
      "requests.cpu"     = "8"
      "requests.memory"  = "16Gi"
      "persistentvolumeclaims" = "10"
    }
  }
}

output "namespace" {
  value = kubernetes_namespace.cap.metadata[0].name
}
