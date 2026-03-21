# Local Fixes Roadmap

Issues identified during analysis on 2026-03-19. Priority ordered.

---

## 1. Fix OTLP log export in demo-app and demo-nginx

**Symptom**: Both pods continuously log:
```
Export failure: cURL error 7: Failed to connect to localhost port 4318 for http://localhost:4318/v1/logs
```
**Root cause**: `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` is not set. The PHP OTEL autoload defaults to `localhost:4318` for logs since only the traces and metrics endpoints are explicitly configured.

**Fix**: Add the following env vars to both `demo-app` and `demo-nginx` pod templates in `yaml/`:
```yaml
- name: OTEL_LOGS_EXPORTER
  value: "otlp"
- name: OTEL_EXPORTER_OTLP_LOGS_ENDPOINT
  value: "http://otel-metrics.monitoring:4318/v1/logs"
- name: OTEL_EXPORTER_OTLP_LOGS_PROTOCOL
  value: "http/protobuf"
```

**Impact**: OTLP logs from the apps will flow to otel-metrics → Alloy → Loki, enabling structured log correlation with traces via `traceID`. Currently only stdout logs are collected (via Alloy pod scraping).

---

## 2. Drop high-cardinality OTLP resource labels from quotes_total

**Symptom**: `quotes_total` carries ~20 OTLP resource-attribute labels including `container_id`, `process_pid`, `os_version`, `process_command_args`, `telemetry_distro_*`, etc.

**Root cause**: The otel-metrics collector forwards all OTLP resource attributes as Prometheus labels without filtering.

**Risk**: `container_id` changes on every pod restart, creating a new time series per restart. At scale this causes unbounded cardinality growth. Currently benign (2 pods, 8 804 total series) but will compound.

**Fix**: Add a `resource_to_telemetry_conversion` disable or a `transform` processor in the otel-metrics collector config to drop non-essential resource attributes before remote-writing. Keep only: `app`, `service_name`, `service_namespace`.

Example processor block (otel-metrics `ConfigMap`):
```yaml
processors:
  resource:
    attributes:
      - action: delete
        key: container_id
      - action: delete
        key: process_pid
      - action: delete
        key: process_command_args
      - action: delete
        key: os_version
      - action: delete
        key: os_description
      - action: delete
        key: host_arch
      - action: delete
        key: telemetry_distro_name
      - action: delete
        key: telemetry_distro_version
      - action: delete
        key: telemetry_sdk_name
      - action: delete
        key: telemetry_sdk_version
      - action: delete
        key: telemetry_sdk_language
      - action: delete
        key: process_command
      - action: delete
        key: process_executable_path
      - action: delete
        key: process_owner
      - action: delete
        key: process_runtime_name
      - action: delete
        key: process_runtime_version
```
Add `resource` to the `service.pipelines.metrics.processors` list.

---

## 3. Supervise port-forwards in make start

**Symptom**: Port-forwards started with `& sleep 5` in `make start` are not supervised. After a pod restart or idle period they die silently, causing `make test` / `make checkload` to time out or fail mid-run.

**Fix**: Replace the fire-and-forget background port-forwards with a wrapper that retries on failure, or use a `while true; do kubectl port-forward ...; sleep 2; done &` loop per service. Alternatively add a `make portforward` target that kills and restarts all forwards, and call it at the start of `make test`.

Minimal example:
```makefile
define pf
  while true; do kubectl port-forward -n $(NAMESPACE) svc/$(1) $(2):$(3) 2>/dev/null; sleep 2; done &
endef

portforward:
  -pkill -f "kubectl port-forward"
  @sleep 1
  $(call pf,grafana,3000,3000)
  $(call pf,prometheus,9090,9090)
  $(call pf,loki,3100,3100)
  $(call pf,tempo,3200,3200)
  $(call pf,alloy,12345,12345)
  $(call pf,alertmanager,9093,9093)
  $(call pf,alert-webhook,8082,8080)
  $(call pf,demo-app,8080,80)
  $(call pf,demo-nginx,8081,80)
  @sleep 3
```

---

## 4. Fix rate-based metric queries for slow-push OTLP counters

**Symptom**: `rate(quotes_total[5m])` returns `0` between PHP OTLP push cycles (~60 s interval), making rate panels in Grafana show flat zero during idle periods.

**Root cause**: The PHP OTEL SDK periodic exporter pushes metrics every 60 s. Prometheus scrapes the remote-write endpoint at a different cadence. Between pushes the counter is flat.

**Fix options** (pick one):
- Use `increase(quotes_total[2m])` with a `min_step` of 60 s on dashboard panels instead of `rate`.
- Set `OTEL_METRIC_EXPORT_INTERVAL=15000` (15 s, in milliseconds) on the demo app deployments to push more frequently.
- Use `irate` with a short window only for real-time panels.

Recommended: add `OTEL_METRIC_EXPORT_INTERVAL=15000` to both demo deployments so the counter updates every 15 s, making `rate(...[1m])` reliable.
