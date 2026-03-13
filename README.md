# Local Grafana Monitoring Stack

This stack provides a complete monitoring solution for your Kubernetes cluster, including metrics collection, log aggregation, and visualization.

## Components
- **Grafana**: Visualization and dashboards (pre-provisioned).
- **Prometheus**: Metrics database (with remote-write, persistence, and cluster-wide visibility).
- **Loki**: Log aggregation system (with structured metadata and persistence).
- **Tempo**: Distributed tracing backend (with persistence).
- **Alloy**: Grafana's OpenTelemetry-collector based agent for scraping metrics, logs, and traces.

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
- Features: Service health status (up/down) and real-time logs for the `monitoring` namespace.

## URLs & Credentials
| Component | Internal URL | External Access (via PF) | Credentials |
| :--- | :--- | :--- | :--- |
| **Grafana** | `http://grafana.monitoring:3000` | [http://localhost:3000](http://localhost:3000) | **Admin** (Anonymous) |
| **Prometheus** | `http://prometheus.monitoring:9090` | [http://localhost:9090](http://localhost:9090) | None |
| **Loki** | `http://loki.monitoring:3100` | [http://localhost:3100](http://localhost:3100) | None |
| **Alloy** | `http://alloy.monitoring:12345` | [http://localhost:12345](http://localhost:12345) | None |

## Verification & Testing

### Manual Testing in Grafana
- **Metrics**: Select **Prometheus** and query `up`. You should see `demo-app`, `demo-nginx`, and `grafana`.
- **Logs**: Select **Loki** and query `{namespace="monitoring"}`.

## Stop and Cleanup

### Stop the Stack
```bash
make stop
```

### Full Cleanup
```bash
make clean
```
