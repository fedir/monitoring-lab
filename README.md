# Local Grafana Monitoring Stack

This stack provides a complete monitoring solution for your Kubernetes cluster, including metrics collection, log aggregation, and visualization.

## Components
- **Grafana**: Visualization and dashboards.
- **Prometheus**: Metrics database (with remote-write enabled).
- **Loki**: Log aggregation system.
- **Alloy**: Grafana's OpenTelemetry-collector based agent for scraping metrics and logs.

## Quick Start

### 1. Using the Makefile
The easiest way to manage the stack is using the provided `Makefile` in the `monitoring-stack/` directory:

```bash
cd monitoring-stack
make start          # Creates namespace, applies manifests, starts ALL port-forwards
make generateload   # Generates HTTP traffic to demo apps
make checkload      # Verifies data in Prometheus and Loki
make stop           # Deletes resources (keeps namespace)
make clean          # Deletes namespace and stops all port-forwards
```

### 2. Full Cycle Script
For a fully automated, progressive test that cleans, starts, and verifies the stack with detailed logs:
```bash
./run-full-cycle.sh full
```


### 2. Manual Launch
If you prefer manual commands:
```bash
kubectl create namespace monitoring
kubectl apply -f monitoring-stack/
```


### 2. Access Grafana
Since this is a local cluster, you need to port-forward the Grafana service to access it from your host machine.

**Using the Makefile (Recommended):**
```bash
make start
```
This will apply the manifests and start the port-forwarding in the background.

**Manual Port-forwarding:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```
This command must remain running while you use Grafana.


### 3. URLs & Credentials
| Component | Internal URL | External Access (via port-forward) | Credentials |
| :--- | :--- | :--- | :--- |
| **Grafana** | `http://grafana.monitoring:3000` | [http://localhost:3000](http://localhost:3000) | **Admin** (Anonymous Access) |
| **Prometheus** | `http://prometheus.monitoring:9090` | [http://localhost:9090](http://localhost:9090) | None |
| **Loki** | `http://loki.monitoring:3100` | [http://localhost:3100](http://localhost:3100) | None |
| **Alloy** | `http://alloy.monitoring:12345` | [http://localhost:12345](http://localhost:12345) | None |

*Note: Anonymous access is enabled for Grafana for local convenience. You are automatically logged in as an Admin.*

### 3. Verification & Testing

#### Makefile Commands
The `Makefile` provides high-level commands for testing:
- `make generateload`: Sends HTTP requests to the demo applications to generate metrics and logs.
- `make checkload`: Runs the automated test script to verify data presence in Prometheus and Loki via Grafana API.

#### Automatic Testing Script
The stack includes a verification script that generates load and queries the Grafana API:
```bash
./test-stack.sh
```

#### Manual Testing
You can also verify the data manually through the Grafana UI:

1. **Check Health**:
   ```bash
   make checkhealth
   ```

2. **Verify Data in Grafana**:
   - Open [http://localhost:3000](http://localhost:3000).
   - Go to **Explore** in the sidebar.
    - **Metrics**: Select **Prometheus** and query `up`. You should see `demo-app`, `demo-nginx`, and `grafana`.
    - **Logs**: Select **Loki** and query `{instance=~"monitoring/demo-app.*"}` or `{job="loki.source.kubernetes.pod_logs"}`.


## Stop and Cleanup

### Stop the Stack (Delete Resources)
To remove the monitoring stack but keep the namespace:
```bash
kubectl delete -f monitoring-stack/
```

### Full Cleanup
To remove everything, including the namespace:
```bash
kubectl delete namespace monitoring
```
