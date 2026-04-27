.PHONY: help check-prereqs create-cluster destroy-cluster \
	deploy-all deploy-vault deploy-platform deploy-apps \
	init-vault configure-vault \
	verify clean clean-charts teardown build-images

# Default environment
ENV ?= local
VERSION ?= latest

# Cluster configuration
CLUSTER_NAME ?= ttrpg-$(ENV)
REGISTRY_NAME ?= k3d-registry.localhost
REGISTRY_PORT ?= 5000
REGISTRY_HOST ?= localhost:$(REGISTRY_PORT)

# Colors for output
COLOR_RESET := \033[0m
COLOR_BOLD := \033[1m
COLOR_GREEN := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE := \033[34m
COLOR_RED := \033[31m

# Helper functions
define print_message
	echo "$(COLOR_BOLD)$(COLOR_BLUE)==> $(1)$(COLOR_RESET)"
endef

define print_success
	echo "$(COLOR_BOLD)$(COLOR_GREEN)✓ $(1)$(COLOR_RESET)"
endef

define print_warning
	echo "$(COLOR_BOLD)$(COLOR_YELLOW)⚠ $(1)$(COLOR_RESET)"
endef

define print_error
	echo "$(COLOR_BOLD)$(COLOR_RED)✗ $(1)$(COLOR_RESET)"
endef

##@ General

help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\n$(COLOR_BOLD)Usage:$(COLOR_RESET)\n  make $(COLOR_BLUE)<target>$(COLOR_RESET)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(COLOR_BLUE)%-25s$(COLOR_RESET) %s\n", $$1, $$2 } /^##@/ { printf "\n$(COLOR_BOLD)%s$(COLOR_RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

check-prereqs: ## Check if required tools are installed
	@$(call print_message,Checking prerequisites...)
	@command -v kubectl >/dev/null 2>&1 || { $(call print_error,kubectl is not installed); exit 1; }
	@command -v helm >/dev/null 2>&1 || { $(call print_error,helm is not installed); exit 1; }
	@command -v vault >/dev/null 2>&1 || { $(call print_error,vault CLI is not installed); exit 1; }
	@command -v k3d >/dev/null 2>&1 || { $(call print_error,k3d is not installed); exit 1; }
	@$(call print_success,All prerequisites are installed)

##@ Cluster Management

create-cluster: check-prereqs ## Create k3d cluster with registry
	$(call print_message,Creating k3d cluster: $(CLUSTER_NAME))
	@if k3d cluster list | grep -q $(CLUSTER_NAME); then \
		$(call print_warning,Cluster $(CLUSTER_NAME) already exists); \
	else \
		k3d registry create $(REGISTRY_NAME) --port $(REGISTRY_PORT) || true; \
		k3d cluster create $(CLUSTER_NAME) \
			--registry-use k3d-$(REGISTRY_NAME):$(REGISTRY_PORT) \
			--api-port 6550 \
			--port "8080:80@loadbalancer" \
			--port "8443:443@loadbalancer" \
			--port "8200:8200@loadbalancer" \
			--k3s-arg "--disable=traefik@server:*" \
			--agents 2 \
			--wait; \
		$(call print_success,Cluster $(CLUSTER_NAME) created successfully); \
	fi

destroy-cluster: ## Destroy k3d cluster
	$(call print_message,Destroying k3d cluster: $(CLUSTER_NAME))
	@k3d cluster delete $(CLUSTER_NAME) || $(call print_warning,Cluster $(CLUSTER_NAME) not found)
	$(call print_success,Cluster destroyed)

teardown: check-prereqs ## Teardown and recreate cluster
	$(call print_message,Tearing down cluster: $(CLUSTER_NAME))
	@k3d cluster delete $(CLUSTER_NAME) || $(call print_warning,Cluster $(CLUSTER_NAME) not found)
	$(call print_success,Cluster deleted)
	@echo ""
	$(call print_message,Creating fresh cluster: $(CLUSTER_NAME))
	@k3d registry create $(REGISTRY_NAME) --port $(REGISTRY_PORT) || $(call print_warning,Registry already exists)
	@k3d cluster create $(CLUSTER_NAME) \
		--registry-use k3d-$(REGISTRY_NAME):$(REGISTRY_PORT) \
		--api-port 6550 \
		--port "8080:80@loadbalancer" \
		--port "8443:443@loadbalancer" \
		--port "8200:8200@loadbalancer" \
		--k3s-arg "--disable=traefik@server:*" \
		--agents 2 \
		--wait
	$(call print_success,Fresh cluster created)

##@ Build Images

build-images: check-prereqs ## Build and load all Docker images
	$(call print_message,Building Docker images with version: $(VERSION))
	@echo ""
	@echo "$(COLOR_BOLD)Building go-auth...$(COLOR_RESET)"
	@docker build -t $(REGISTRY_HOST)/go-auth:$(VERSION) ../ttrpg-api/go_auth
	@k3d image import $(REGISTRY_HOST)/go-auth:$(VERSION) -c $(CLUSTER_NAME)
	$(call print_success,go-auth image built and loaded)
	@echo ""
	@echo "$(COLOR_BOLD)Building go-sprint...$(COLOR_RESET)"
	@docker build -f ../ttrpg-api/go_sprint/Dockerfile -t $(REGISTRY_HOST)/go-sprint:$(VERSION) ../ttrpg-api
	@k3d image import $(REGISTRY_HOST)/go-sprint:$(VERSION) -c $(CLUSTER_NAME)
	$(call print_success,go-sprint image built and loaded)
	@echo ""
	@echo "$(COLOR_BOLD)Building py-dnd...$(COLOR_RESET)"
	@docker build --target development -f ../ttrpg-api/py_dnd/deploy/Dockerfile -t $(REGISTRY_HOST)/py-dnd:$(VERSION) ../ttrpg-api/py_dnd
	@k3d image import $(REGISTRY_HOST)/py-dnd:$(VERSION) -c $(CLUSTER_NAME)
	$(call print_success,py-dnd image built and loaded)
	@echo ""
	@echo "$(COLOR_BOLD)Building ui-dnd...$(COLOR_RESET)"
	@docker build -f ../ttrpg-ui/apps/dnd/deploy/Dockerfile -t $(REGISTRY_HOST)/ui-dnd:$(VERSION) --build-arg APP_NAME=dnd --build-arg BUILD_BASE_HREF=/ttrpg/dnd/ ../ttrpg-ui
	@k3d image import $(REGISTRY_HOST)/ui-dnd:$(VERSION) -c $(CLUSTER_NAME)
	$(call print_success,ui-dnd image built and loaded)
	@echo ""
	@echo "$(COLOR_BOLD)Building ui-sprint-management...$(COLOR_RESET)"
	@docker build -f ../ttrpg-ui/apps/sprint-management/deploy/Dockerfile -t $(REGISTRY_HOST)/ui-sprint-management:$(VERSION) --build-arg APP_NAME=sprint-management --build-arg BUILD_BASE_HREF=/ttrpg/sprint-management/ ../ttrpg-ui
	@k3d image import $(REGISTRY_HOST)/ui-sprint-management:$(VERSION) -c $(CLUSTER_NAME)
	$(call print_success,ui-sprint-management image built and loaded)
	@echo ""
	$(call print_success,All images built and loaded)

##@ Deploy

deploy-all: check-prereqs ## Deploy all components (vault, platform, apps)
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)========================================$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)  Deploying All Components$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)========================================$(COLOR_RESET)"
	@echo ""
	@$(MAKE) deploy-vault ENV=$(ENV)
	@echo ""
	@$(MAKE) deploy-platform ENV=$(ENV)
	@echo ""
	@$(MAKE) configure-keycloak ENV=$(ENV)
	@echo ""
	@$(MAKE) init-vault ENV=$(ENV)
	@echo ""
	@$(MAKE) configure-vault ENV=$(ENV)
	@echo ""
	@$(MAKE) deploy-apps ENV=$(ENV) VERSION=$(VERSION)
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)========================================$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)  Deployment Complete!$(COLOR_RESET)"
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)========================================$(COLOR_RESET)"

deploy-vault: check-prereqs ## Deploy Vault to security namespace
	$(call print_message,Deploying Vault to security namespace)
	@helm dependency update charts/vault-release
	@helm upgrade --install vault charts/vault-release \
		--namespace security \
		--create-namespace \
		--values charts/vault-release/values-$(ENV).yaml \
		--wait \
		--timeout 5m
	$(call print_success,Vault deployed)

deploy-platform: check-prereqs ## Deploy platform infrastructure
	$(call print_message,Deploying platform infrastructure)
	@helm dependency build charts/platform
	@helm upgrade --install platform charts/platform \
		--namespace platform \
		--create-namespace \
		--values charts/platform/values-$(ENV).yaml \
		--wait \
		--timeout 10m
	$(call print_success,Platform deployed)

deploy-apps: check-prereqs ## Deploy application services
	$(call print_message,Deploying applications)
	@helm dependency build charts/apps
	@helm upgrade --install apps charts/apps \
		--namespace apps \
		--create-namespace \
		--values charts/apps/values-$(ENV).yaml \
		--set global.version=$(VERSION) \
		--wait \
		--timeout 10m
	$(call print_success,Applications deployed)

##@ Vault Operations

init-vault: check-prereqs ## Initialize and unseal Vault
	$(call print_message,Initializing Vault...)
	@./scripts/init-vault.sh $(ENV)
	$(call print_success,Vault initialized)

configure-vault: check-prereqs ## Configure Vault database secrets engine
	$(call print_message,Configuring Vault...)
	@./scripts/vault-configure.sh $(ENV)
	$(call print_success,Vault configured)

configure-keycloak: check-prereqs ## Configure Keycloak realm and clients
	$(call print_message,Configuring Keycloak...)
	@./scripts/configure-keycloak.sh $(ENV)
	$(call print_success,Keycloak configured)

##@ Verification

verify: check-prereqs ## Verify deployment health
	$(call print_message,Verifying deployment...)
	@./scripts/verify-deployment.sh $(ENV)

##@ Cleanup

clean: ## Remove generated files
	$(call print_message,Cleaning up...)
	@find . -name "*.tmp" -delete
	@find . -name "*.log" -delete
	@rm -rf charts/*/charts/*.tgz
	$(call print_success,Cleanup completed)

clean-charts: ## Remove packaged chart dependencies (.tgz files) for development
	$(call print_message,Removing packaged chart dependencies...)
	@rm -f charts/vault-release/charts/*.tgz
	@rm -f charts/platform/charts/*.tgz
	@rm -f charts/platform/*/charts/*.tgz
	@rm -f charts/apps/charts/*.tgz
	@rm -f charts/apps/*/charts/*.tgz
	$(call print_success,Packaged charts removed)

##@ Quick Start

quickstart: create-cluster build-images deploy-all verify ## Quick start: create cluster and deploy everything
	@echo ""
	@echo "$(COLOR_BOLD)$(COLOR_GREEN)Quick Start Completed!$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Access your services:$(COLOR_RESET)"
	@echo "  • Ingress:  http://localhost:8080/ttrpg/"
	@echo "  • Vault:    http://localhost:8200"
	@echo "  • Keycloak: http://localhost:8180"
