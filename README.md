# HealthTrack Core - Kubernetes Infrastructure & Monitoring

This repository contains the Kubernetes deployment manifests and Prometheus/Grafana monitoring setup for **HealthTrack Core**.

---

## 📁 Repository Structure

```
healthtrack-core/
├── k8s/
│   ├── namespace.yaml      # Defines `sample-app` & `monitoring` namespaces
│   ├── deployment.yaml     # High-availability web-app Deployment (2 replicas)
│   └── service.yaml        # ClusterIP Service for web-app
└── monitoring/
    └── servicemonitor.yaml # Prometheus ServiceMonitor configuration
```

---

## 🚀 Quick Start

### 1. Deploy Core Application Manifests

Apply the namespaces, deployment, and service to your Kubernetes cluster:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

Check the status of running pods:

```bash
kubectl get pods -n sample-app
```

---

## 📊 Monitoring Setup (Prometheus & Grafana)

### 1. Install kube-prometheus-stack via Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring-stack prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### 2. Apply ServiceMonitor

```bash
kubectl apply -f monitoring/servicemonitor.yaml
```

### 3. Access Grafana Dashboard

Forward port 3000 to Grafana service:

```bash
kubectl port-forward svc/monitoring-stack-grafana 3000:80 -n monitoring
```

Access Grafana at `http://localhost:3000`.

- **Default Username:** `admin`
- **Retrieve Password:**
  ```bash
  kubectl get secret -n monitoring monitoring-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
  ```

---

## 🛠️ Verification Commands

```bash
# Check all resources across namespaces
kubectl get all -n sample-app
kubectl get all -n monitoring
```
