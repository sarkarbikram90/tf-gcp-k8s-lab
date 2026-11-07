# ==============================================================================
# Self-Managed Kubernetes Reference Platform & IDP on GCP (`tf-gcp-k8s-lab`)
# Root Developer & SRE Automation Makefile
# ==============================================================================

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ORDER_API_IMAGE   ?= ghcr.io/sarkarbikram90/order-api:v1.4.2
SRE_COPILOT_IMAGE ?= ghcr.io/sarkarbikram90/sre-copilot:v1.1.0
KIND_CLUSTER_NAME ?= tf-gcp-k8s-lab

.PHONY: help test test-order-api test-sre-copilot verify-policies e2e-local \
        build-images kind-up kind-test kind-e2e kind-down fmt-check ci

help: ## Display available platform, microservice, and local kind targets
	@echo "=============================================================================="
	@echo " tf-gcp-k8s-lab — SRE, Platform IDP & AI Infrastructure Automation"
	@echo "=============================================================================="
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test: test-order-api test-sre-copilot ## Run Go vet and unit tests (-race) for all microservices

test-order-api: ## Run Go vet and unit tests for services/order-api
	cd services/order-api && go vet ./... && go test -v -race ./...

test-sre-copilot: ## Run Go vet and unit tests for services/sre-copilot
	cd services/sre-copilot && go vet ./... && go test -v -race ./...

verify-policies: ## Run shift-left Kustomize Golden Path & Kyverno policy verification
	chmod +x scripts/platform/verify-platform-policies.sh
	./scripts/platform/verify-platform-policies.sh

e2e-local: ## Run zero-Docker standalone E2E pipeline (order-api -> sre-copilot -> Markdown RCA)
	chmod +x scripts/local/kind-e2e-harness.sh
	./scripts/local/kind-e2e-harness.sh standalone-test

build-images: ## Build multi-stage distroless container images for order-api and sre-copilot
	docker build -t $(ORDER_API_IMAGE) services/order-api
	docker build -t $(SRE_COPILOT_IMAGE) services/sre-copilot

kind-up: ## Bootstrap 3-node local kind cluster, load images, and deploy workloads
	chmod +x scripts/local/kind-e2e-harness.sh
	KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) ./scripts/local/kind-e2e-harness.sh up

kind-test: ## Run closed-loop E2E smoke test against the local kind cluster
	chmod +x scripts/local/kind-e2e-harness.sh
	KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) ./scripts/local/kind-e2e-harness.sh test

kind-e2e: ## Provision local kind cluster and run full E2E verification ('up' + 'test')
	chmod +x scripts/local/kind-e2e-harness.sh
	KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) ./scripts/local/kind-e2e-harness.sh all

kind-down: ## Delete the local kind cluster
	chmod +x scripts/local/kind-e2e-harness.sh
	KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) ./scripts/local/kind-e2e-harness.sh down

fmt-check: ## Check Terraform and Go formatting across the repository
	terraform fmt -check -recursive
	@unformatted=$$(gofmt -l services/); \
	if [ -n "$$unformatted" ]; then \
		echo "Unformatted Go files: $$unformatted"; \
		exit 1; \
	fi

ci: test verify-policies e2e-local ## Execute the full local CI verification suite (tests + policies + E2E)
