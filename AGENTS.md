# AI Agents Development Guide

This document outlines the architecture and workflows for AI agents working on the Grafana Monitoring Stack.

## Project Architecture
The project consists of a local Kubernetes monitoring stack:
- **Grafana**: Visualization (Anonymous Admin access enabled).
- **Prometheus**: Metrics storage (Remote-write enabled).
- **Loki**: Log aggregation.
- **Tempo**: Traces storage (OTLP ingest enabled).
- **Alloy**: Data collection agent (configured with dynamic discovery via annotations).
- **OTel Metrics Gateway**: OTLP receiver for app metrics and traces; remote-writes metrics to Prometheus and forwards traces to Alloy.

## Agent Workflows

### 0. Load Testing and Verification
Before and after making changes, use the following commands to verify the system:
- `make generateload`: Triggers traffic to demo apps to produce metrics and logs.
- `make checkload`: Verifies the end-to-end data pipeline (Alloy -> DB -> Grafana API).
- `make full`: Executes a complete clean-start-test-clean cycle.

All new features should include at least one `curl` debug script in `curl/` to exercise the feature and generate traffic. Use the naming format `app-action.sh`, provide defaults with optional overrides via flags, and include a `--help` description so the script can be used for quick verification and load generation.

### 1. Extending Monitoring
When adding new services to be monitored:
- **Deployment**: Add standard Prometheus annotations to the Pod template:
  ```yaml
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
  ```
- **Verification**: Use `make checkhealth` and verify the target appears in Grafana Explore (`up` metric).

If the service is exporting OTLP metrics instead of being scraped, send OTLP metrics to `otel-metrics` and verify with service-specific metrics (not `up`).

### 2. Modifying Alloy Configuration
Alloy uses a `.alloy` configuration file stored in a `ConfigMap`.
- **Location**: `yaml/alloy.yaml`
- **Pattern**: 
  - `discovery.kubernetes` for finding resources.
  - `discovery.relabel` for filtering/relabeling.
  - `prometheus.scrape` and `loki.source.kubernetes` for collection.
- **Logs Metadata**: We use `loki.relabel` to add structured labels (`namespace`, `pod`, `container`, `app`) to all collected logs.

### 3. OpenTelemetry Instrumentation (OTLP)
- **Collector endpoints**:
  - App metrics and traces: `otel-metrics.monitoring:4318` (OTLP HTTP, use `/v1/metrics` and `/v1/traces`).
  - Traces forwarding: `otel-metrics` sends traces to Alloy, and Alloy forwards to Tempo.
- **Traces**: `demo-app` and `demo-nginx` emit OTLP traces to `otel-metrics`, which forwards to Alloy and then Tempo.
- **Metrics**: `demo-app` and `demo-nginx` emit OTLP metrics to `otel-metrics`, which remote-writes to Prometheus.
- **Example**: The `alert-webhook` deployment is auto-instrumented and exports OTLP traces.

### 3.1 Demo App Traffic
- `demo-app` and `demo-nginx` are OTEL-instrumented quote services.
- Generate traffic with POST `getquote` payloads (e.g., `{"numberOfItems":3}`) so traces + metrics are emitted.

### 4. Dashboard Provisioning
Dashboards are provisioned via ConfigMaps and providers.
- **Provider**: `yaml/grafana.yaml` contains the `grafana-dashboards-provider` ConfigMap.
- **Dashboard JSON**: Dashboards are embedded in `yaml/grafana.yaml` as ConfigMaps and mounted to `/var/lib/grafana/dashboards`.
- **Datasources**: Use fixed UIDs (`prometheus`, `loki`) in provisioning to ensure dashboards work immediately.
- **Adding a new dashboard**: Create a new ConfigMap in `yaml/grafana.yaml`, add a provider entry pointing to its mount path, and add a volumeMount + volume to the Grafana Deployment. Then `kubectl apply -f yaml/grafana.yaml` and `kubectl rollout restart deployment/grafana -n monitoring`.

#### Provisioned dashboards

| Dashboard | UID | Folder | ConfigMap | Mount path |
|---|---|---|---|---|
| Stack Overview | `stack-overview` | root | `grafana-dashboard-demo` | `/var/lib/grafana/dashboards` |
| Cluster Nodes — CPU Usage & Load | `cluster-nodes-cpu` | Infrastructure | `grafana-dashboard-nodes` | `/var/lib/grafana/dashboards/nodes` |
| Alert History | `alert-history` | Alerts | `grafana-dashboard-alerts` | `/var/lib/grafana/dashboards/alerts` |

#### Cluster Nodes — CPU Usage & Load
- **Panels**: current utilisation % stat, current load5 stat, utilisation timeseries, load average timeseries (load1/5/15 + core count), CPU mode breakdown (user/system/iowait), CPU resource allocation (requested vs limits vs capacity), utilisation heatmap, per-core load contribution timeseries, per-core load contribution heatmap.
- **Key metrics**: `node_cpu_seconds_total`, `node_load1`, `node_load5`, `node_load15` (node-exporter); `kube_pod_container_resource_requests`, `kube_pod_container_resource_limits` (kube-state-metrics).
- **CPU Usage vs CPU Load**: utilisation panels use `1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))` (% of time CPUs were busy). Load average panels use `node_load1/5/15` (queue depth; saturated when value ≥ core count).
- **Per-core detail**: panels 8 and 9 use `1 - rate(node_cpu_seconds_total{mode="idle"}[5m])` grouped `by (instance, cpu)` — this is the correct way to express per-core load contribution since Unix load average is system-wide and cannot be split per core. Legend format: `core {{cpu}} — {{instance}}`.

### 5. Alerting & Notifications
Alerting is handled by Prometheus + Alertmanager, and Grafana alerting is provisioned to the same webhook receiver.
- **Alertmanager**: `yaml/alertmanager.yaml`
- **Prometheus rules**: `yaml/prometheus.yaml` (`rules.yml`)
- **Webhook receiver**: `yaml/webhook-receiver.yaml`
- **Grafana alerting provisioning**: `yaml/grafana.yaml` (`/etc/grafana/provisioning/alerting`)
- **Verification**: Scale a demo app to zero replicas and confirm alert history at the webhook UI.
- **ServiceDown rule**: Based on `kube-state-metrics` deployment/daemonset availability metrics to catch scaled-to-zero workloads quickly.

### 6. Resource Management & Security
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

### Completed
- [x] Implement Grafana Dashboard provisioning for the Stack.
- [x] Add Tempo for Distributed Tracing.
- [x] Implement Cluster-Wide Visibility (node-exporter, kube-state-metrics).
- [x] Add Cluster Nodes — CPU Usage & Load dashboard (utilisation %, load average, mode breakdown, resource allocation, heatmap).
- [x] Add Persistent Volume support for Prometheus/Loki data.
- [x] Add per-core CPU load contribution panels (timeseries + heatmap) to Cluster Nodes dashboard.

### Physical Host — Server Observability
> Cover the bare-metal / VM layer that Kubernetes runs on.
- [ ] **Memory detail**: add node memory dashboard — used/available/cached/buffers, swap usage, page fault rate (`node_memory_*`).
- [ ] **Disk I/O**: throughput (read/write bytes/s), IOPS, await time, saturation per device (`node_disk_*`). Heatmap of per-device utilisation over time.
- [ ] **Network interfaces**: per-NIC throughput, packet rate, error/drop counters (`node_network_*`). Alert on sustained drops or errors.
- [ ] **Filesystem**: per-mount usage %, inode exhaustion, read-only flag (`node_filesystem_*`). Alert at 80% / 95% capacity.
- [ ] **System load context**: per-core CPU mode breakdown (user/system/iowait/steal/softirq) as stacked area — extend the existing mode breakdown panel to per-core granularity.
- [ ] **Hardware / thermal** (if available via IPMI/DCMI exporter): CPU temperature, fan speed, power draw. Alert on thermal throttle threshold.
- [ ] **Process-level top**: integrate `process-exporter` or Alloy process metrics to show top-N CPU/memory consumers on the host outside Kubernetes.

### Virtual Cluster — Kubernetes Observability
> Cover the orchestration and workload layer running on the host.
- [ ] **Namespace resource quotas**: CPU/memory requested vs quota limit per namespace (`kube_resourcequota`). Alert when > 90% of quota consumed.
- [ ] **Pod lifecycle events**: restart counts, OOMKilled events, pending/failed pod counts (`kube_pod_container_status_*`). Dashboard + alert for crash-looping workloads.
- [ ] **Container resource efficiency**: requested vs actual CPU/memory per container (requests vs `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` from cAdvisor). Rightsizing view.
- [ ] **Persistent Volume health**: PVC bound/pending/failed status, volume fill rate, projected time-to-full (`kubelet_volume_stats_*`). Alert when < 20% free.
- [ ] **Kubernetes API server & etcd**: API server request latency, error rate, etcd leader changes, DB size (`apiserver_*`, `etcd_*`). Alert on elevated 5xx rate.
- [ ] **Scheduler & controller-manager**: scheduling latency, queue depth, reconciliation errors.
- [ ] **Network policies / DNS**: CoreDNS request rate, error rate, latency (`coredns_*`). Alert on elevated NXDOMAIN rate.

### Application — Service Observability
> Cover the demo workloads and any future services end-to-end.
- [ ] **Per-service error rate panels and alerts**: use OTEL metrics labels (`app`, `service_name`) for HTTP 5xx rate and gRPC error rate. Alert at > 1% error rate sustained for 5 min.
- [ ] **Latency percentiles**: p50/p95/p99 request latency per service from OTEL histogram metrics. Alert when p99 > SLO threshold.
- [ ] **SLO dashboards**: error budget burn rate for demo services (latency, availability, saturation) — one dashboard per service with 1h/6h/24h burn windows.
- [ ] **Trace context in dashboards**: add Tempo data links from log lines to traces in Stack Overview (correlate `traceID` label in Loki with Tempo).
- [ ] **Exemplars**: enable exemplar support in Prometheus remote-write and surface exemplar links on latency panels (jump from p99 spike directly to a trace).
- [ ] **Dependency map**: service graph panel using Tempo `traces_spanmetrics_*` to visualise call graph and per-edge error/latency.

### Alerting & Reliability
- [ ] **Runbook links**: add `runbook_url` annotations to all Prometheus alert rules pointing to a local markdown runbook in `docs/runbooks/`.
- [ ] **Alert deduplication and grouping**: tune Alertmanager `group_by`, `group_wait`, `repeat_interval` to reduce noise for the demo environment.
- [ ] **Dead man's switch**: add a always-firing `Watchdog` alert so silence of that alert indicates the pipeline itself is broken.
- [ ] **Multi-window SLO alerts**: implement 2% / 5% burn-rate alerts (1h + 6h windows) for the demo services.

### Operational & Tooling
- [ ] **Document podman-based tooling** in troubleshooting and testing sections.
- [ ] **Automated dashboard tests**: script that queries each provisioned dashboard via Grafana API and asserts all panels return data (extend `make checkload`).
- [ ] **Log-based alerting**: add Loki ruler rules for error-level log patterns (e.g., repeated 5xx in nginx access log) forwarded to Alertmanager.
- [ ] **Cardinality guard**: add a Prometheus recording rule or Grafana panel tracking total active time series to catch label explosion early.
