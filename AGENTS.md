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
- `make checkload`: Verifies the end-to-end data pipeline (Alloy -> DB -> Grafana API) by querying for metrics and logs.
- `./run-full-cycle.sh full`: Executes a complete clean-start-test-clean cycle with progressive, detailed output. Useful for CI/CD or deep debugging.

### 1. Extending Monitoring
When adding new services to be monitored:
- **Deployment**: Add standard Prometheus annotations to the Pod template:
  ```yaml
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080" # Replace with actual metrics port
  ```
- **Verification**: Use `make checkhealth` and verify the target appears in Grafana Explore (`up` metric).

### 2. Modifying Alloy Configuration
Alloy uses a `.alloy` configuration file stored in a `ConfigMap`.
- **Location**: `yaml/alloy.yaml`
- **Pattern**: 
  - `discovery.kubernetes` for finding resources.
  - `discovery.relabel` for filtering/relabeling.
  - `prometheus.scrape` and `loki.source.kubernetes` for collection.
- **Warning**: Always ensure the `alloy` `ClusterRole` has permissions for any new resources discovered (e.g., `pods/log` for Loki).

### 3. Dashboard Provisioning
To add permanent dashboards:
- Add a new `ConfigMap` for the dashboard JSON.
- Mount the `ConfigMap` into the Grafana pod under `/etc/grafana/provisioning/dashboards`.
- Update `grafana.yaml` to include a dashboard provider configuration.

## Common Troubleshooting
- **Port-forwarding fails**: Run `make clean` then `make start` to reset background processes.
- **Namespace stuck in Terminating**: If `make clean` hangs, use the following command to force removal:
  ```bash
  kubectl get namespace monitoring -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/monitoring/finalize" -f -
  ```
- **RBAC Errors**: Check Alloy logs (`kubectl logs -l app=alloy -n monitoring`). If you see `403 Forbidden`, update the `ClusterRole` in `yaml/alloy.yaml`.
- **Metrics missing**: Ensure the target pod has the correct `prometheus.io/port` annotation and that the port is actually listening inside the container.

## Roadmap for Future Agents
- [ ] Implement Grafana Dashboard provisioning for the Demo App.
- [ ] Add Tempo for Distributed Tracing.
- [ ] Implement AlertManager rules for system health.
- [ ] Add Persistent Volume support for Prometheus/Loki data.
