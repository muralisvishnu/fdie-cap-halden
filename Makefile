SHELL := /bin/bash
ROOT := $(shell pwd)
CLUSTER_NAME ?= halden-cage
TARGET ?= cage
CAP_NAMESPACE ?= cap
REGISTRY_HOST ?= localhost:5001
REGISTRY_INCLUSTER ?= localhost:5001
GKE_CLUSTER_NAME ?= halden-cage-gke
GKE_PROJECT ?= sre-play
GKE_REGION ?= us-west1
GKE_REGISTRY_NODEPORT ?= 30500
# Legacy shared-infra context (namespace-only terraform at install/terraform/gke/)
GKE_CONTEXT ?= gke_sre-play_us-west1_infra
GKE_REGISTRY ?= docker.io/muralisvishnu

export ROOT TARGET CLUSTER_NAME CAP_NAMESPACE REGISTRY_HOST REGISTRY_INCLUSTER
export GKE_CLUSTER_NAME GKE_PROJECT GKE_REGION GKE_REGISTRY_NODEPORT

.PHONY: help ensure-colima up down mirror mirror-to-registry export-release-images attest install install-ingress install-gke install-addons install-addons-dockerhub install-addons-gke install-addons-local restore-egress auth-login uninstall rollback airgap-test preflight preflight-gke status status-gke destroy package verify-proof test-smoke test-e2e test-all smoke-test gke-full dockerhub-login capture-denials capture-constraints record-install

_install_deps:
ifeq ($(TARGET),cage)
	@$(MAKE) ensure-colima
endif

help:
	@echo "Halden Cap BYOC — unified install (TARGET=cage|gke|byoc)"
	@echo ""
	@echo "  Same commands for kind and dedicated GKE — only TARGET changes:"
	@echo "    make up && make mirror && make install-addons"
	@echo "    ALLOW_NON_THURSDAY=1 make install-ingress && make test-smoke"
	@echo ""
	@echo "  make ensure-colima   Start Colima if stopped (cage + mirror)"
	@echo "  make up              Bootstrap cluster (kind or GKE via terraform)"
	@echo "  make down            Tear down (kind delete or terraform destroy)"
	@echo "  make mirror          Colima build → push to in-cluster private registry (kind/GKE)"
	@echo "  make install-ingress Install Cap via Helm + ingress"
	@echo "  make install-addons  Cilium/Kyverno/ingress via private registry (no Docker Hub)"
	@echo "  make gke-full        Full GKE proof: up → install → smoke → down"
	@echo "  make status          Show cluster + Cap health"
	@echo "  make airgap-test     Prove Cap serves with egress fully denied"
	@echo "  make capture-constraints Refresh freeze/Kyverno/TLS/registry proof logs"
	@echo "  make record-install  asciinema uncut install (proof/*.cast)"
	@echo "  make package         BYOC customer bundle"

ensure-colima:
	@if ! colima status 2>/dev/null | grep -q "Running"; then \
		echo "Starting Colima..."; \
		colima start --cpu 6 --memory 16 --disk 60; \
	fi
	@docker info >/dev/null

up:
ifeq ($(TARGET),cage)
	@$(MAKE) ensure-colima
endif
	@bash environment/scripts/up.sh

down:
	@bash environment/scripts/down.sh

mirror: ensure-colima
	@TARGET=$(TARGET) bash environment/scripts/sync-colima-to-registry.sh

mirror-direct: ensure-colima
	@REGISTRY_HOST=$(REGISTRY_HOST) TARGET=$(TARGET) bash supply-chain/mirror.sh

attest: ensure-colima
	@REGISTRY_HOST=$(REGISTRY_HOST) bash supply-chain/attest.sh

restore-egress:
	@bash scripts/restore-egress-proxy.sh

auth-login:
	@bash scripts/auth-login.sh

preflight:
	@bash scripts/preflight.sh

preflight-gke:
	@TARGET=gke bash scripts/preflight.sh

mirror-to-registry:
	@REGISTRY_HOST=$(GKE_REGISTRY) bash supply-chain/mirror-to-registry.sh

export-release-images: ensure-colima
	@bash supply-chain/export-release-images.sh

install: _install_deps
	@ALLOW_NON_THURSDAY=1 bash scripts/install.sh

install-ingress: _install_deps
	@ALLOW_NON_THURSDAY=1 USE_INGRESS=1 bash scripts/install.sh

# Legacy: shared sre-play infra (namespace-only). Prefer TARGET=gke make install-ingress.
install-gke:
	@kubectl config use-context $(GKE_CONTEXT)
	@ALLOW_NON_THURSDAY=1 TARGET=byoc PREFLIGHT_PROFILE=gke CAP_NAMESPACE=halden-cap \
		REGISTRY_HOST=$(GKE_REGISTRY) KUBE_CONTEXT=$(GKE_CONTEXT) USE_GKE_INFRA_VALUES=1 \
		bash scripts/install.sh

dockerhub-login: ensure-colima
	@TARGET=$(TARGET) bash environment/scripts/dockerhub-login.sh

install-addons: ensure-colima
	@TARGET=$(TARGET) bash environment/scripts/install-addons.sh

# GKE default is already Docker Hub. Kind: preload muralisvishnu/halden-cage into the node.
install-addons-dockerhub: ensure-colima
	@USE_DOCKERHUB_MIRROR=1 TARGET=$(TARGET) bash environment/scripts/install-addons.sh

install-addons-gke install-addons-local: install-addons
	@true

mirror-gke-dockerhub:
	@kubectl config use-context gke_sre-play_us-west1_infra
	@kubectl apply -f supply-chain/dockerhub/manifests/namespace.yaml
	@kubectl delete job halden-image-mirror -n vishnusmurali --ignore-not-found
	@kubectl apply -f supply-chain/dockerhub/manifests/mirror-job.yaml

mirror-dockerhub-to-local: ensure-colima
	@bash supply-chain/dockerhub/mirror-dockerhub-to-local.sh

mirror-addons-local: ensure-colima
	@TARGET=$(TARGET) bash supply-chain/mirror-addons-local.sh

preload-from-dockerhub: ensure-colima
	@USE_DOCKERHUB_MIRROR=1 bash environment/scripts/preload-from-dockerhub.sh

status:
	@echo "=== TARGET=$(TARGET) ==="
	@bash -c 'source environment/scripts/kube-env.sh && echo "Context: $$KUBE_CONTEXT" && $$KUBECTL get nodes -o wide 2>/dev/null || echo "cluster not up"'
	@echo "=== Cap ==="
	@bash -c 'source environment/scripts/kube-env.sh && $$KUBECTL -n $$CAP_NAMESPACE get pods,svc,ingress 2>/dev/null || true'

status-gke:
	@TARGET=gke $(MAKE) status

rollback:
	@bash -c 'source environment/scripts/kube-env.sh && $$HELM rollback cap -n $$CAP_NAMESPACE' || true

uninstall:
	@bash -c 'source environment/scripts/kube-env.sh && $$HELM uninstall cap -n $$CAP_NAMESPACE 2>/dev/null || true'
	@bash -c 'source environment/scripts/kube-env.sh && $$KUBECTL -n $$CAP_NAMESPACE delete job --all --ignore-not-found'
	@bash -c 'source environment/scripts/kube-env.sh && $$KUBECTL -n $$CAP_NAMESPACE delete pvc --all --ignore-not-found'
	@echo "=== remaining in namespace (cage addons live elsewhere) ==="
	@bash -c 'source environment/scripts/kube-env.sh && $$KUBECTL -n $$CAP_NAMESPACE get all,pvc 2>/dev/null || true'

capture-constraints:
	@bash scripts/capture-constraints.sh

capture-denials:
	@bash scripts/capture-squid-denials.sh

record-install:
	@bash scripts/record-install.sh

airgap-test:
	@bash scripts/airgap-test.sh

package:
	@bash supply-chain/package-release.sh

verify-proof:
	@bash scripts/verify-proof.sh

test-smoke smoke-test:
	@TARGET=$(TARGET) bash scripts/smoke-test.sh

test-e2e:
	@TARGET=$(TARGET) bash tests/runner.sh e2e

test-all:
	@TARGET=$(TARGET) bash tests/runner.sh all

# End-to-end GKE proof using the same command sequence as kind.
gke-full:
	@$(MAKE) down TARGET=gke || true
	@$(MAKE) up TARGET=gke
	@$(MAKE) mirror TARGET=gke
	@$(MAKE) install-addons TARGET=gke
	@ALLOW_NON_THURSDAY=1 $(MAKE) install-ingress TARGET=gke
	@$(MAKE) test-smoke TARGET=gke
	@echo "GKE full proof complete. Run: make down TARGET=gke"

destroy:
ifeq ($(TARGET),gke)
	@$(MAKE) down TARGET=gke
else
	@echo "Run: make down TARGET=cage  (or make down TARGET=gke)"
endif
