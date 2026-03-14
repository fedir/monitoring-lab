# AI Agents Development Guide

This document outlines the architecture and workflows for AI agents working on the Grafana Monitoring Stack.

## Project Architecture
The project consists of a local Kubernetes monitoring stack:
- **Grafana**: Visualization (Anonymous Admin access enabled).
- **Prometheus**: Metrics storage (Remote-write enabled).
- **Loki**: Log aggregation.
- **Alloy**: Data collection agent (configured with dynamic discovery via annotations).

## Agent Workflows

### 0. Load Testing and Verification
Before and after making changes, use the following commands to verify the system:
- `make generateload`: Triggers traffic to demo apps to produce metrics and logs.
- `make checkload`: Verifies the end-to-end data pipeline (Alloy -> DB -> Grafana API).
- `make full`: Executes a complete clean-start-test-clean cycle.

### 1. Extending Monitoring
When adding new services to be monitored:
- **Deployment**: Add standard Prometheus annotations to the Pod template:
  ```yaml
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
  ```
- **Verification**: Use `make checkhealth` and verify the target appears in Grafana Explore (`up` metric).

### 2. Modifying Alloy Configuration
Alloy uses a `.alloy` configuration file stored in a `ConfigMap`.
- **Location**: `yaml/alloy.yaml`
- **Pattern**: 
  - `discovery.kubernetes` for finding resources.
  - `discovery.relabel` for filtering/relabeling.
  - `prometheus.scrape` and `loki.source.kubernetes` for collection.
- **Logs Metadata**: We use `loki.relabel` to add structured labels (`namespace`, `pod`, `container`, `app`) to all collected logs.

### 3. Dashboard Provisioning
Dashboards are provisioned via ConfigMaps and providers.
- **Provider**: `yaml/grafana.yaml` contains the `grafana-dashboards-provider` ConfigMap.
- **Dashboard JSON**: Dashboards are embedded in `yaml/grafana.yaml` as ConfigMaps and mounted to `/var/lib/grafana/dashboards`.
- **Alerts Dashboard**: The Alert History dashboard is provisioned under `/var/lib/grafana/dashboards/alerts` and shows a quick link to the webhook UI.
- **Datasources**: Use fixed UIDs (`prometheus`, `loki`) in provisioning to ensure dashboards work immediately.

### 4. Alerting & Notifications
Alerting is handled by Prometheus + Alertmanager, and Grafana alerting is provisioned to the same webhook receiver.
- **Alertmanager**: `yaml/alertmanager.yaml`
- **Prometheus rules**: `yaml/prometheus.yaml` (`rules.yml`)
- **Webhook receiver**: `yaml/webhook-receiver.yaml`
- **Grafana alerting provisioning**: `yaml/grafana.yaml` (`/etc/grafana/provisioning/alerting`)
- **Verification**: Scale a demo app to zero replicas and confirm alert history at the webhook UI.
- **ServiceDown rule**: Based on `kube-state-metrics` deployment/daemonset availability metrics to catch scaled-to-zero workloads quickly.

### 5. Resource Management & Security
- **Resource limits**: All workloads define CPU/memory requests and limits in their manifests.
- **Network policies**: `yaml/network-policy.yaml` restricts ingress to Prometheus/Loki/Tempo to Alloy and Grafana.

## Common Troubleshooting
- **Port-forwarding fails**: Run `make clean` then `make start` to reset background processes.
- **Namespace stuck in Terminating**: If `make clean` hangs, use:
  ```bash
  kubectl get namespace monitoring -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/monitoring/finalize" -f -
  ```
- **Loki "No data"**: Ensure Alloy is labeling logs correctly. Check `discovery.relabel` for logs in `yaml/alloy.yaml`.
- **Alerts not firing**: Confirm Prometheus has loaded rules and Alertmanager is reachable from Prometheus (`alertmanager:9093`).

## Roadmap for Future Agents
- [x] Implement Grafana Dashboard provisioning for the Stack.
- [x] Add Tempo for Distributed Tracing.
- [x] Implement Cluster-Wide Visibility (node-exporter, kube-state-metrics).
- [x] Add Persistent Volume support for Prometheus/Loki data.
