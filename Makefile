# HealthTrack Core — Makefile
# Usage: make <target>
# Run `make help` to see all available targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- Configuration ---
NAMESPACE       := sample-app
MONITORING_NS   := monitoring
HELM_RELEASE    := monitoring-stack
HELM_CHART      := prometheus-community/kube-prometheus-stack
KUSTOMIZE_ENV   ?= staging
KUBECONFORM_VER := v0.6.4

# Colours
GREEN  := \033[0;32m
YELLOW := \033[0;33m
CYAN   := \033[0;36m
RESET  := \033[0m

.PHONY: help setup deploy deploy-dev deploy-staging deploy-production \
        monitoring monitoring-teardown teardown status logs \
        lint validate helm-lint helm-install helm-upgrade \
        port-forward-grafana port-forward-prometheus \
        rollout-status clean

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help: ## Show this help message
	@echo ""
	@echo "  $(CYAN)HealthTrack Core — Makefile$(RESET)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-28s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# ---------------------------------------------------------------------------
# Setup: install prerequisites
# ---------------------------------------------------------------------------
setup: ## Install Helm repos and tool prerequisites
	@echo "$(CYAN)→ Adding Helm repos...$(RESET)"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	@echo "$(GREEN)✓ Setup complete$(RESET)"

# ---------------------------------------------------------------------------
# Deploy: apply Kustomize overlays
# ---------------------------------------------------------------------------
deploy: deploy-$(KUSTOMIZE_ENV) ## Deploy using KUSTOMIZE_ENV overlay (default: staging)

deploy-dev: ## Deploy dev overlay (1 replica, reduced resources)
	@echo "$(CYAN)→ Deploying dev overlay...$(RESET)"
	kubectl apply -k k8s/overlays/dev
	@echo "$(GREEN)✓ Dev deployment applied$(RESET)"

deploy-staging: ## Deploy staging overlay (2 replicas)
	@echo "$(CYAN)→ Deploying staging overlay...$(RESET)"
	kubectl apply -k k8s/overlays/staging
	@echo "$(GREEN)✓ Staging deployment applied$(RESET)"

deploy-production: ## Deploy production overlay (4 replicas, nginx:stable)
	@echo "$(YELLOW)→ Deploying PRODUCTION overlay...$(RESET)"
	kubectl apply -k k8s/overlays/production
	@echo "$(GREEN)✓ Production deployment applied$(RESET)"

# ---------------------------------------------------------------------------
# Monitoring stack
# ---------------------------------------------------------------------------
monitoring: ## Install kube-prometheus-stack + apply ServiceMonitor and PrometheusRules
	@echo "$(CYAN)→ Installing monitoring stack via Helm...$(RESET)"
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(MONITORING_NS) \
		--create-namespace \
		--wait
	@echo "$(CYAN)→ Applying ServiceMonitor and PrometheusRules...$(RESET)"
	kubectl apply -f monitoring/servicemonitor.yaml
	kubectl apply -f monitoring/prometheus-rules.yaml
	kubectl apply -f monitoring/dashboards/configmap.yaml
	@echo "$(GREEN)✓ Monitoring stack ready$(RESET)"

monitoring-teardown: ## Uninstall the monitoring Helm release
	@echo "$(YELLOW)→ Removing monitoring stack...$(RESET)"
	helm uninstall $(HELM_RELEASE) -n $(MONITORING_NS) || true
	@echo "$(GREEN)✓ Monitoring stack removed$(RESET)"

# ---------------------------------------------------------------------------
# Helm chart
# ---------------------------------------------------------------------------
helm-install: ## Install the HealthTrack Helm chart into sample-app namespace
	@echo "$(CYAN)→ Installing HealthTrack Helm chart...$(RESET)"
	helm install healthtrack ./charts/healthtrack \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--wait
	@echo "$(GREEN)✓ Helm chart installed$(RESET)"

helm-upgrade: ## Upgrade the existing HealthTrack Helm release
	@echo "$(CYAN)→ Upgrading HealthTrack Helm chart...$(RESET)"
	helm upgrade healthtrack ./charts/healthtrack \
		--namespace $(NAMESPACE) \
		--wait
	@echo "$(GREEN)✓ Helm chart upgraded$(RESET)"

# ---------------------------------------------------------------------------
# Status & Debugging
# ---------------------------------------------------------------------------
status: ## Show status of all resources in sample-app and monitoring namespaces
	@echo "$(CYAN)=== sample-app namespace ===$(RESET)"
	kubectl get all,hpa,pdb,networkpolicies -n $(NAMESPACE)
	@echo ""
	@echo "$(CYAN)=== monitoring namespace ===$(RESET)"
	kubectl get all -n $(MONITORING_NS)

rollout-status: ## Watch rollout status of the web-app deployment
	kubectl rollout status deployment/web-app -n $(NAMESPACE) --timeout=120s

logs: ## Tail logs from web-app pods (Ctrl+C to stop)
	kubectl logs -n $(NAMESPACE) -l app=web-app -f --max-log-requests=10

# ---------------------------------------------------------------------------
# Port-forwarding
# ---------------------------------------------------------------------------
port-forward-grafana: ## Forward Grafana to http://localhost:3000
	@echo "$(CYAN)→ Grafana available at http://localhost:3000$(RESET)"
	@echo "$(YELLOW)  Username: admin$(RESET)"
	@echo "$(YELLOW)  Password: $(shell kubectl get secret -n $(MONITORING_NS) $(HELM_RELEASE)-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || echo 'run: kubectl get secret -n monitoring monitoring-stack-grafana -o jsonpath={.data.admin-password} | base64 --decode')$(RESET)"
	kubectl port-forward svc/$(HELM_RELEASE)-grafana 3000:80 -n $(MONITORING_NS)

port-forward-prometheus: ## Forward Prometheus to http://localhost:9090
	@echo "$(CYAN)→ Prometheus available at http://localhost:9090$(RESET)"
	kubectl port-forward svc/$(HELM_RELEASE)-kube-prom-prometheus 9090:9090 -n $(MONITORING_NS)

# ---------------------------------------------------------------------------
# Linting & Validation
# ---------------------------------------------------------------------------
lint: helm-lint validate ## Run all linters (Helm + kubeconform)

helm-lint: ## Lint the HealthTrack Helm chart
	@echo "$(CYAN)→ Linting Helm chart...$(RESET)"
	helm lint ./charts/healthtrack
	@echo "$(GREEN)✓ Helm lint passed$(RESET)"

validate: ## Validate all k8s manifests with kubeconform
	@echo "$(CYAN)→ Validating Kubernetes manifests with kubeconform...$(RESET)"
	@if ! command -v kubeconform &>/dev/null; then \
		echo "$(YELLOW)kubeconform not found. Install from: https://github.com/yannh/kubeconform/releases$(RESET)"; \
	else \
		kubeconform -strict -summary k8s/base/*.yaml k8s/base/postgres/*.yaml; \
		echo "$(GREEN)✓ All manifests valid$(RESET)"; \
	fi

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
teardown: ## Delete all HealthTrack resources from the cluster
	@echo "$(YELLOW)→ Tearing down HealthTrack resources...$(RESET)"
	kubectl delete namespace $(NAMESPACE) --ignore-not-found
	$(MAKE) monitoring-teardown
	@echo "$(GREEN)✓ All resources removed$(RESET)"

clean: ## Remove local build artifacts
	@echo "$(CYAN)→ Cleaning local artifacts...$(RESET)"
	find . -name "*.bak" -delete
	@echo "$(GREEN)✓ Clean complete$(RESET)"
