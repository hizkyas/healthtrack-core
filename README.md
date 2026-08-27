# HealthTrack Core — Kubernetes Infrastructure

[![CI — Lint & Validate](https://github.com/hizkyas/healthtrack-core/actions/workflows/ci.yaml/badge.svg)](https://github.com/hizkyas/healthtrack-core/actions/workflows/ci.yaml)
[![CD — Deploy to Cluster](https://github.com/hizkyas/healthtrack-core/actions/workflows/deploy.yaml/badge.svg)](https://github.com/hizkyas/healthtrack-core/actions/workflows/deploy.yaml)

Production-grade Kubernetes infrastructure for **HealthTrack Core** — featuring multi-environment Kustomize overlays, Helm packaging, autoscaling, security hardening, Prometheus/Grafana monitoring, and a full GitHub Actions CI/CD pipeline.

---

## 📁 Repository Structure

```
healthtrack-core/
├── .github/
│   └── workflows/
│       ├── ci.yaml          # PR validation: kubeconform, Helm lint, Kustomize build, yamllint
│       └── deploy.yaml      # CD: deploy overlay, monitoring stack, smoke test
├── charts/
│   └── healthtrack/         # Helm chart for the full application stack
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── hpa.yaml
│           └── ingress.yaml
├── k8s/
│   ├── base/                # Kustomize base — all core manifests
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml  # nginx, 2 replicas, securityContext, health probes
│   │   ├── service.yaml
│   │   ├── hpa.yaml         # Autoscale 2–10 replicas (CPU 70% / Mem 80%)
│   │   ├── pdb.yaml         # minAvailable: 1
│   │   ├── rbac.yaml        # ServiceAccount + Role + RoleBinding
│   │   ├── networkpolicy.yaml # deny-all + explicit allow rules
│   │   ├── ingress.yaml     # NGINX Ingress + cert-manager TLS
│   │   ├── cert-manager-issuer.yaml # Let's Encrypt prod + staging issuers
│   │   └── postgres/
│   │       ├── statefulset.yaml # postgres:15-alpine, PVC mount, health probes
│   │       ├── service.yaml     # Headless ClusterIP for DNS
│   │       ├── pvc.yaml         # 5Gi ReadWriteOnce
│   │       └── secret.yaml      # DB credentials (use secret manager in prod)
│   └── overlays/
│       ├── dev/             # 1 replica, reduced CPU/mem
│       ├── staging/         # 2 replicas, standard resources
│       └── production/      # 4 replicas, nginx:stable, increased limits
└── monitoring/
    ├── servicemonitor.yaml  # Prometheus scrape config for web-app
    ├── prometheus-rules.yaml # 7 alert rules across 3 groups
    └── dashboards/
        ├── web-app-dashboard.json # Grafana dashboard (CPU, mem, restarts, HPA)
        └── configmap.yaml         # Auto-provisioned via grafana_dashboard label
```

---

## 🚀 Quick Start

### Prerequisites
- `kubectl` + a running Kubernetes cluster (minikube, k3s, EKS, GKE, etc.)
- `helm` v3.x
- `kustomize` (bundled in kubectl v1.14+)
- `make`

### 1. One-command setup
```bash
make setup
```

### 2. Deploy the application
```bash
# Deploy to staging (default)
make deploy

# Deploy to a specific environment
make deploy-dev
make deploy-staging
make deploy-production
```

### 3. Install monitoring stack
```bash
make monitoring
```

### 4. Access Grafana
```bash
make port-forward-grafana
# Open: http://localhost:3000
```

---

## 🌍 Environments (Kustomize Overlays)

| Environment | Replicas | CPU Limit | Memory Limit | Image |
|-------------|----------|-----------|--------------|-------|
| `dev` | 1 | 100m | 128Mi | nginx:latest |
| `staging` | 2 | 250m | 256Mi | nginx:latest |
| `production` | 4 | 500m | 512Mi | nginx:stable |

```bash
kubectl apply -k k8s/overlays/production
```

---

## 📦 Helm Chart

```bash
# Install
helm install healthtrack ./charts/healthtrack -n sample-app --create-namespace

# Upgrade with custom values
helm upgrade healthtrack ./charts/healthtrack \
  --set replicaCount=4 \
  --set image.tag=stable \
  --set ingress.enabled=true
```

---

## 🔒 Security Features

| Feature | Implementation |
|---------|---------------|
| Non-root container | `runAsUser: 1000`, `runAsNonRoot: true` |
| Drop all capabilities | `capabilities.drop: [ALL]` + add `NET_BIND_SERVICE` |
| Seccomp profile | `seccompProfile: RuntimeDefault` |
| Least-privilege RBAC | ServiceAccount + Role (pods:get/list, configmaps:get) |
| Network isolation | Default deny-all + explicit allow for port 80 + DNS |
| No token auto-mount | `automountServiceAccountToken: false` |

---

## 📊 Monitoring & Alerting

### Prometheus Alert Rules (7 alerts across 3 groups)

| Alert | Condition | Severity |
|-------|-----------|----------|
| `WebAppPodCrashLooping` | Restart rate > 0 for 2m | critical |
| `WebAppDeploymentUnavailable` | Unavailable replicas > 0 for 5m | warning |
| `WebAppPodsNotReady` | No ready pods for 3m | critical |
| `WebAppHighCPUUsage` | CPU > 85% of limit for 5m | warning |
| `WebAppHighMemoryUsage` | Memory > 85% of limit for 5m | warning |
| `WebAppOOMKilled` | Container OOMKilled | critical |
| `WebAppHPAMaxReplicas` | HPA at maxReplicas for 10m | warning |

### Grafana Dashboard
Auto-provisioned via ConfigMap with `grafana_dashboard: "1"` label.
Panels: ready replicas, unavailable replicas, HPA current replicas, CPU/memory per pod, restart rate, HPA scale history.

---

## ⚙️ GitHub Actions CI/CD

### CI Pipeline (`ci.yaml`) — triggers on PRs and feature branches
| Job | Tool | Checks |
|-----|------|--------|
| Kubeconform | kubeconform | Validates all base manifests against Kubernetes schemas |
| Helm Lint | helm lint | Default values + ingress enabled |
| Kustomize Build | kubectl kustomize | Matrix: dev, staging, production |
| YAML Lint | yamllint | All YAML files (relaxed, max 160 chars) |

### CD Pipeline (`deploy.yaml`) — triggers on merge to `main`
1. Determine environment (push → staging, manual dispatch → selectable)
2. Apply Kustomize overlay via `kubectl apply -k`
3. Wait for rollout to complete (`kubectl rollout status --timeout=180s`)
4. Deploy kube-prometheus-stack via Helm + apply monitoring resources
5. Smoke test: assert ≥1 ready replica

> **Secret required:** Add `KUBECONFIG` (base64-encoded kubeconfig) to GitHub repo secrets.

---

## 🛠️ All Make Targets

```bash
make help               # Show all targets
make setup              # Add Helm repos
make deploy             # Deploy KUSTOMIZE_ENV overlay (default: staging)
make deploy-dev         # Dev overlay
make deploy-staging     # Staging overlay
make deploy-production  # Production overlay
make monitoring         # Install kube-prometheus-stack + monitoring resources
make monitoring-teardown
make helm-install       # Install ./charts/healthtrack
make helm-upgrade       # Upgrade existing Helm release
make status             # Show all resources in both namespaces
make rollout-status     # Watch web-app rollout
make logs               # Tail web-app pod logs
make port-forward-grafana    # http://localhost:3000
make port-forward-prometheus # http://localhost:9090
make lint               # Run Helm lint + kubeconform
make teardown           # Delete all resources
make clean              # Remove local artifacts
```
