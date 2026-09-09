SHELL := /bin/bash
ROOT := $(shell pwd)
CLUSTER_NAME ?= halden-cage
KUBECTL := kubectl --context kind-$(CLUSTER_NAME)
HELM := helm --kube-context kind-$(CLUSTER_NAME)
REGISTRY_HOST ?= localhost:5001
REGISTRY_INCLUSTER ?= localhost:5001
CAP_NAMESPACE ?= cap
TARGET ?= cage

.PHONY: help ensure-colima up down mirror attest install install-ingress install-addons restore-egress auth-login uninstall rollback airgap-test preflight status destroy ci-kind-deploy

help:
	@echo "Halden Cap BYOC — local-first targets"
	@echo ""
	@echo "  make ensure-colima   Start Colima if stopped"
	@echo "  make up              Build the local kind cage"
	@echo "  make mirror          Mirror Cap images into private registry (bootstrap host)"
	@echo "  make install         Install Cap into the cage (TARGET=cage)"
	@echo "  make install-ingress Switch Cap to ingress-nginx (http://127.0.0.1:30080)"
	@echo "  make status          Show cage + Cap health"
	@echo "  make airgap-test     Prove Cap serves with egress proxy fully denied"
	@echo "  make restore-egress  Restore Squid allowlist after airgap test"
	@echo "  make auth-login      Watch cap-web logs for email OTP codes"
	@echo "  make attest          SBOM + cosign (requires syft/cosign)"
	@echo "  make ci-kind-deploy  kind + mirror + helm install/upgrade (CI parity)"
	@echo "  make rollback        Helm rollback Cap release"
	@echo "  make uninstall       Remove Cap release and namespace workloads"
	@echo "  make down            Tear down kind cluster + local registry"
	@echo "  make preflight       Run allowlist / policy preflight checks"

ensure-colima:
	@if ! colima status 2>/dev/null | grep -q "Running"; then \
		echo "Starting Colima..."; \
		colima start --cpu 4 --memory 8 --disk 60; \
	fi
	@docker info >/dev/null

up: ensure-colima
	@bash environment/scripts/up.sh

down:
	@bash environment/scripts/down.sh

mirror: ensure-colima
	@REGISTRY_HOST=$(REGISTRY_HOST) bash supply-chain/mirror.sh

attest: ensure-colima
	@REGISTRY_HOST=$(REGISTRY_HOST) bash supply-chain/attest.sh

restore-egress:
	@bash scripts/restore-egress-proxy.sh

auth-login:
	@bash scripts/auth-login.sh

preflight:
	@bash scripts/preflight.sh

install: ensure-colima
	@ALLOW_NON_THURSDAY=1 TARGET=$(TARGET) REGISTRY_HOST=$(REGISTRY_INCLUSTER) bash scripts/install.sh

install-ingress: ensure-colima
	@ALLOW_NON_THURSDAY=1 TARGET=$(TARGET) REGISTRY_HOST=$(REGISTRY_INCLUSTER) USE_INGRESS=1 bash scripts/install.sh

install-addons: ensure-colima
	@bash environment/scripts/install-addons.sh

mirror-gke-dockerhub:
	@kubectl config use-context gke_sre-play_us-west1_infra
	@kubectl apply -f supply-chain/dockerhub/manifests/namespace.yaml
	@kubectl delete job halden-image-mirror -n vishnusmurali --ignore-not-found
	@kubectl apply -f supply-chain/dockerhub/manifests/mirror-job.yaml
	@echo "Watch: kubectl -n vishnusmurali logs -f job/halden-image-mirror"
	@echo "Target: docker.io/muralisvishnu/halden-cage:<tag>"

mirror-dockerhub-to-local: ensure-colima
	@bash supply-chain/dockerhub/mirror-dockerhub-to-local.sh

mirror-addons-local: ensure-colima
	@bash supply-chain/mirror-addons-local.sh

preload-from-dockerhub: ensure-colima
	@USE_DOCKERHUB_MIRROR=1 bash environment/scripts/preload-from-dockerhub.sh

install-addons-dockerhub: ensure-colima
	@USE_DOCKERHUB_MIRROR=1 bash environment/scripts/install-addons.sh

install-addons-local: ensure-colima
	@USE_LOCAL_REGISTRY=1 bash environment/scripts/install-addons.sh

status:
	@echo "=== Nodes ==="
	@$(KUBECTL) get nodes -o wide 2>/dev/null || echo "cluster not up"
	@echo "=== Cap ==="
	@$(KUBECTL) -n $(CAP_NAMESPACE) get pods,svc,ingress 2>/dev/null || true

rollback:
	@$(HELM) rollback cap -n $(CAP_NAMESPACE) || true

uninstall:
	@$(HELM) uninstall cap -n $(CAP_NAMESPACE) 2>/dev/null || true
	@$(KUBECTL) -n $(CAP_NAMESPACE) delete job --all --ignore-not-found
	@$(KUBECTL) -n $(CAP_NAMESPACE) delete pvc --all --ignore-not-found

airgap-test:
	@bash scripts/airgap-test.sh

ci-kind-deploy:
	@CI_KIND=1 ALLOW_NON_THURSDAY=1 USE_INGRESS=1 REGISTRY_HOST=$(REGISTRY_HOST) REGISTRY_INCLUSTER=$(REGISTRY_INCLUSTER) bash scripts/ci-kind-deploy.sh

destroy:
	@echo "GKE destroy is a separate step (make -C install/terraform/gke destroy)"
