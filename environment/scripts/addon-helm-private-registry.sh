#!/usr/bin/env bash
# Helm --set fragments for addon charts pulling from the in-cluster private registry.
# shellcheck shell=bash
set -euo pipefail

: "${REGISTRY_INCLUSTER:?REGISTRY_INCLUSTER required}"

ADDON_REGISTRY="${REGISTRY_INCLUSTER}/halden"

cilium_private_registry_sets() {
  cat <<EOF
--set image.repository=${ADDON_REGISTRY}/cilium
--set image.tag=v1.20.1
--set operator.image.repository=${ADDON_REGISTRY}/cilium-operator
--set operator.image.suffix=
--set operator.image.tag=v1.20.1
--set envoy.image.repository=${ADDON_REGISTRY}/cilium-envoy
--set envoy.image.tag=v1.20.1
EOF
}

kyverno_private_registry_sets() {
  local r="${ADDON_REGISTRY}"
  cat <<EOF
--set admissionController.container.image.registry=
--set admissionController.container.image.repository=${r}/kyverno
--set admissionController.container.image.tag=v1.13.2
--set backgroundController.image.registry=
--set backgroundController.image.repository=${r}/kyverno-background
--set backgroundController.image.tag=v1.13.2
--set cleanupController.image.registry=
--set cleanupController.image.repository=${r}/kyverno-cleanup
--set cleanupController.image.tag=v1.13.2
--set reportsController.image.registry=
--set reportsController.image.repository=${r}/kyverno-reports
--set reportsController.image.tag=v1.13.2
--set admissionController.initContainer.image.registry=
--set admissionController.initContainer.image.repository=${r}/kyvernopre
--set admissionController.initContainer.image.tag=v1.13.2
--set crds.migration.image.registry=
--set crds.migration.image.repository=${r}/kyverno-cli
--set crds.migration.image.tag=v1.13.2
--set test.image.registry=
--set test.image.repository=${r}/busybox
--set test.image.tag=1.35
--set webhooksCleanup.image.registry=
--set webhooksCleanup.image.repository=${r}/kubectl
--set webhooksCleanup.image.tag=v1.30.2
--set policyReportsCleanup.image.registry=
--set policyReportsCleanup.image.repository=${r}/kubectl
--set policyReportsCleanup.image.tag=v1.30.2
EOF
}

ingress_private_registry_sets() {
  cat <<EOF
--set controller.image.repository=${ADDON_REGISTRY}/ingress-controller
--set controller.image.tag=v1.15.1
--set controller.admissionWebhooks.patch.image.repository=${ADDON_REGISTRY}/ingress-certgen
--set controller.admissionWebhooks.patch.image.tag=v1.6.9
EOF
}

# GKE kubelet cannot pull HTTP in-cluster registry. Docker Hub is HTTPS.
# Single repo docker.io/muralisvishnu/halden-cage with per-image tags.
DOCKERHUB_ADDON_REPO="${DOCKERHUB_ADDON_REPO:-docker.io/muralisvishnu/halden-cage}"

DOCKERHUB_PULL_SECRET="${DOCKERHUB_PULL_SECRET:-dockerhub-creds}"

cilium_dockerhub_sets() {
  # image.override bypasses the chart's suffix/digest assembly. The operator
  # template always injects a "-<cloud>" segment (e.g. -generic) unless
  # operator.image.override is set, which would point at a repo that does not exist.
  cat <<EOF
--set image.override=${DOCKERHUB_ADDON_REPO}:cilium-v1.20.1
--set image.useDigest=false
--set operator.image.override=${DOCKERHUB_ADDON_REPO}:cilium-operator-v1.20.1
--set operator.image.useDigest=false
--set envoy.image.override=${DOCKERHUB_ADDON_REPO}:cilium-envoy-v1.20.1
--set envoy.image.useDigest=false
--set imagePullSecrets[0].name=${DOCKERHUB_PULL_SECRET}
EOF
}

kyverno_dockerhub_sets() {
  # An empty image.registry is falsy in the chart's `default` chain, so it falls
  # back to the per-image defaultRegistry (ghcr.io). global.image.registry
  # overrides every component instead.
  local reg="${DOCKERHUB_ADDON_REPO%%/*}"
  local r="${DOCKERHUB_ADDON_REPO#*/}"
  cat <<EOF
--set global.image.registry=${reg}
--set admissionController.container.image.repository=${r}
--set admissionController.container.image.tag=kyverno-v1.13.2
--set backgroundController.image.repository=${r}
--set backgroundController.image.tag=kyverno-bg-v1.13.2
--set cleanupController.image.repository=${r}
--set cleanupController.image.tag=kyverno-cleanup-v1.13.2
--set reportsController.image.repository=${r}
--set reportsController.image.tag=kyverno-reports-v1.13.2
--set admissionController.initContainer.image.repository=${r}
--set admissionController.initContainer.image.tag=kyvernopre-v1.13.2
--set crds.migration.image.registry=${reg}
--set crds.migration.image.repository=${r}
--set crds.migration.image.tag=kyverno-cli-v1.13.2
--set test.image.registry=${reg}
--set test.image.repository=${r}
--set test.image.tag=busybox-1.35
--set webhooksCleanup.image.repository=${r}
--set webhooksCleanup.image.tag=kubectl-helper-v1.30.2
--set webhooksCleanup.image.pullPolicy=IfNotPresent
--set policyReportsCleanup.image.repository=${r}
--set policyReportsCleanup.image.tag=kubectl-helper-v1.30.2
--set policyReportsCleanup.image.pullPolicy=IfNotPresent
--set global.imagePullSecrets[0].name=${DOCKERHUB_PULL_SECRET}
EOF
}

ingress_dockerhub_sets() {
  cat <<EOF
--set controller.image.registry=docker.io
--set controller.image.image=muralisvishnu/halden-cage
--set controller.image.tag=ingress-controller-v1.15.1
--set controller.image.digest=
--set controller.admissionWebhooks.patch.image.registry=docker.io
--set controller.admissionWebhooks.patch.image.image=muralisvishnu/halden-cage
--set controller.admissionWebhooks.patch.image.tag=ingress-certgen-v1.6.9
--set controller.admissionWebhooks.patch.image.digest=
--set controller.imagePullSecrets[0].name=${DOCKERHUB_PULL_SECRET}
--set controller.admissionWebhooks.patch.imagePullSecrets[0].name=${DOCKERHUB_PULL_SECRET}
EOF
}
