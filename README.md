# Local Grafana Monitoring Stack

This stack provides a complete monitoring solution for your Kubernetes cluster, including metrics collection, log aggregation, and visualization.

## Components
- **Grafana**: Visualization and dashboards (pre-provisioned).
- **Prometheus**: Metrics database (with remote-write, persistence, and cluster-wide visibility).
- **Loki**: Log aggregation system (with structured metadata and persistence).
- **Tempo**: Distributed tracing backend (with persistence).
- **Alloy**: Grafana's OpenTelemetry-collector based agent for scraping metrics, logs, and traces.
- **OTel Metrics Gateway**: OTLP receiver for app metrics and traces; remote-writes metrics to Prometheus and forwards traces to Alloy.
- **Alertmanager**: Alert routing and notification fan-out.
- **Alert Webhook**: Lightweight alert history receiver with persistent storage.

## OpenTelemetry (OTLP)
- **Ingestion**: Apps export OTLP to `otel-metrics.monitoring:4318` (HTTP, use `/v1/metrics` and `/v1/traces`).
- **Traces**: `demo-app`, `demo-nginx`, and `alert-webhook` ship OTLP traces to `otel-metrics`; traces are forwarded to Alloy and then to Tempo.
- **Metrics**: `demo-app` and `demo-nginx` emit OTLP metrics to `otel-metrics`, which remote-writes to Prometheus.
- **Safe rollout**: Prometheus scraping and Loki log collection remain unchanged for other workloads.

## Resource Management & Security

### Resource Limits
All workloads include CPU/memory requests and limits to keep the stack predictable.

### Network Policies
Ingress to Prometheus, Loki, and Tempo is restricted to Alloy and Grafana (Tempo is also allowed to reach Prometheus for remote-write).
Policies are defined in `yaml/network-policy.yaml` and require a CNI that enforces NetworkPolicy.

## Quick Start

### 1. Using the Makefile
The easiest way to manage the stack is using the provided `Makefile`:

```bash
make start          # Creates namespace, applies manifests, starts ALL port-forwards
make generateload   # Generates HTTP traffic to demo apps
make checkload      # Verifies data in Prometheus and Loki
make full           # Performs a full clean-start-test-clean cycle
make stop           # Deletes resources (keeps namespace)
make clean          # Deletes namespace and stops all port-forwards
```

### Debug Curl Scripts
The `curl/` folder contains one-command debug scripts to generate traffic and verify each service. Each script supports `--help` with optional overrides (host, port, query).
- Example: `./curl/demo-app-getquote.sh --number 5`

### 2. Manual Launch
If you prefer manual commands:
```bash
kubectl create namespace monitoring
kubectl apply -f yaml/
```

### 3. Access Grafana
Since this is a local cluster, you need to port-forward the Grafana service:

**Using the Makefile (Recommended):**
```bash
make start
```

**Manual Port-forwarding:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

### 4. Provisioned Dashboards
Grafana comes pre-configured with the **Stack Overview** dashboard.
- URL: [http://localhost:3000/d/stack-overview/stack-overview](http://localhost:3000/d/stack-overview/stack-overview)
- Features: Deployment health (kube-state-metrics), app request rate + p95 latency, trace activity, and logs for the `monitoring` namespace.
- Includes an **Alert History** panel with a quick link to the webhook UI.

Grafana also includes a dedicated **Alert History** dashboard in the **Alerts** folder.
- URL: [http://localhost:3000/d/alert-history/alert-history](http://localhost:3000/d/alert-history/alert-history)

### Demo Apps
The demo apps run OTEL-instrumented quote services.
- `demo-app`: POST `http://localhost:8080/getquote` with JSON payload, e.g. `{"numberOfItems":3}`.
- `demo-nginx`: POST `http://localhost:8081/getquote` with JSON payload, e.g. `{"numberOfItems":2}`.

## URLs & Credentials
| Component | Internal URL | External Access (via PF) | Credentials |
| :--- | :--- | :--- | :--- |
| **Grafana** | `http://grafana.monitoring:3000` | [http://localhost:3000](http://localhost:3000) | **Admin** (Anonymous) |
| **Prometheus** | `http://prometheus.monitoring:9090` | [http://localhost:9090](http://localhost:9090) | None |
| **Loki** | `http://loki.monitoring:3100` | [http://localhost:3100](http://localhost:3100) | None |
| **Tempo** | `http://tempo.monitoring:3200` | [http://localhost:3200](http://localhost:3200) | None |
| **Alloy** | `http://alloy.monitoring:12345` | [http://localhost:12345](http://localhost:12345) | None |
| **Alertmanager** | `http://alertmanager.monitoring:9093` | [http://localhost:9093](http://localhost:9093) | None |
| **Alert Webhook** | `http://alert-webhook.monitoring:8080` | [http://localhost:8082](http://localhost:8082) | None |
| **Demo App** | `http://demo-app.monitoring` | `POST http://localhost:8080/getquote` | None |
| **Demo Nginx** | `http://demo-nginx.monitoring` | `POST http://localhost:8081/getquote` | None |

## Verification & Testing

### Manual Testing in Grafana
- **Metrics**: Select **Prometheus** and query `kube_deployment_status_replicas_available{namespace="monitoring"}` or `rate(quotes_total[5m])`.
- **Logs**: Select **Loki** and query `{namespace="monitoring"}`.

## Alerting

Alerts flow from Prometheus -> Alertmanager -> Alert Webhook, and Grafana also sends alerts to the webhook via its provisioning.

### View Alert History
The webhook receiver stores alerts in a PVC and shows them in a simple UI.

```bash
kubectl port-forward -n monitoring svc/alert-webhook 8082:8080
```

Open [http://localhost:8082](http://localhost:8082)

### Trigger a Test Alert
Scale a demo app to zero replicas and wait ~30-60s for the alert to fire.

```bash
kubectl scale deployment/demo-app -n monitoring --replicas=0
```

Then scale back:

```bash
kubectl scale deployment/demo-app -n monitoring --replicas=2
```

## Stop and Cleanup

### Stop the Stack
```bash
make stop
```

### Full Cleanup
```bash
make clean
```
