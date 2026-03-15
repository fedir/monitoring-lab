#!/bin/bash

# Configuration
NAMESPACE="${NAMESPACE:-monitoring}"
GRAFANA_HOST="${GRAFANA_HOST:-localhost}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
DEMO_APP_HOST="${DEMO_APP_HOST:-localhost}"
DEMO_APP_PORT="${DEMO_APP_PORT:-8080}"
DEMO_NGINX_HOST="${DEMO_NGINX_HOST:-localhost}"
DEMO_NGINX_PORT="${DEMO_NGINX_PORT:-8081}"
PROM_HOST="${PROM_HOST:-localhost}"
PROM_PORT="${PROM_PORT:-9090}"
LOKI_HOST="${LOKI_HOST:-localhost}"
LOKI_PORT="${LOKI_PORT:-3100}"
TEMPO_HOST="${TEMPO_HOST:-localhost}"
TEMPO_PORT="${TEMPO_PORT:-3200}"
ALLOY_HOST="${ALLOY_HOST:-localhost}"
ALLOY_PORT="${ALLOY_PORT:-12345}"
ALERTMANAGER_HOST="${ALERTMANAGER_HOST:-localhost}"
ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
WEBHOOK_HOST="${WEBHOOK_HOST:-localhost}"
WEBHOOK_PORT="${WEBHOOK_PORT:-8082}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURL_DIR="${SCRIPT_DIR}/curl"

PF_PIDS=()
FAILURES=0

echo "🚀 Starting load generation and verification..."

ensure_port_forward() {
    local name="$1"
    local svc="$2"
    local local_port="$3"
    local target_port="$4"
    shift 4
    local cmd=("$@")
    local attempts=15

    if "${cmd[@]}" >/dev/null 2>&1; then
        return
    fi

    kubectl port-forward -n "$NAMESPACE" "svc/$svc" "$local_port:$target_port" > /dev/null 2>&1 &
    PF_PIDS+=("$!")

    for i in $(seq 1 "$attempts"); do
        sleep 2
        if "${cmd[@]}" >/dev/null 2>&1; then
            return
        fi
    done

    echo "❌ Failed to reach $name"
    FAILURES=$((FAILURES + 1))
}

check_endpoint() {
    local name="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        echo "✅ $name reachable"
    else
        echo "❌ $name not reachable"
        FAILURES=$((FAILURES + 1))
    fi
}

cleanup() {
    for pid in "${PF_PIDS[@]}"; do
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill "$pid"
        fi
    done
    echo "Cleanup done."
}

trap cleanup EXIT

# 1. Start Port-Forwards (if missing)
echo "📡 Ensuring port-forwards..."
ensure_port_forward "Grafana" "grafana" 3000 3000 "$CURL_DIR/grafana-health.sh" --host "$GRAFANA_HOST" --port "$GRAFANA_PORT"
ensure_port_forward "Demo App" "demo-app" 8080 80 "$CURL_DIR/demo-app-getquote.sh" --host "$DEMO_APP_HOST" --port "$DEMO_APP_PORT"
ensure_port_forward "Demo Nginx" "demo-nginx" 8081 80 "$CURL_DIR/demo-nginx-getquote.sh" --host "$DEMO_NGINX_HOST" --port "$DEMO_NGINX_PORT"
ensure_port_forward "Prometheus" "prometheus" 9090 9090 "$CURL_DIR/prometheus-ready.sh" --host "$PROM_HOST" --port "$PROM_PORT"
ensure_port_forward "Loki" "loki" 3100 3100 "$CURL_DIR/loki-ready.sh" --host "$LOKI_HOST" --port "$LOKI_PORT"
ensure_port_forward "Tempo" "tempo" 3200 3200 "$CURL_DIR/tempo-ready.sh" --host "$TEMPO_HOST" --port "$TEMPO_PORT"
ensure_port_forward "Alloy" "alloy" 12345 12345 "$CURL_DIR/alloy-metrics.sh" --host "$ALLOY_HOST" --port "$ALLOY_PORT"
ensure_port_forward "Alertmanager" "alertmanager" 9093 9093 "$CURL_DIR/alertmanager-ready.sh" --host "$ALERTMANAGER_HOST" --port "$ALERTMANAGER_PORT"
ensure_port_forward "Alert Webhook" "alert-webhook" 8082 8080 "$CURL_DIR/alert-webhook-health.sh" --host "$WEBHOOK_HOST" --port "$WEBHOOK_PORT"

# 2. Generate Load
echo "traffic 📈 Generating traffic to demo apps..."
for i in {1..20}; do
    "$CURL_DIR/demo-app-getquote.sh" --host "$DEMO_APP_HOST" --port "$DEMO_APP_PORT" > /dev/null
    "$CURL_DIR/demo-nginx-getquote.sh" --host "$DEMO_NGINX_HOST" --port "$DEMO_NGINX_PORT" > /dev/null
    printf "."
    sleep 0.5
done
echo " Done."

# 3. Verify service endpoints
echo "🔍 Verifying service endpoints..."
check_endpoint "Grafana" "$CURL_DIR/grafana-health.sh" --host "$GRAFANA_HOST" --port "$GRAFANA_PORT"
check_endpoint "Prometheus" "$CURL_DIR/prometheus-ready.sh" --host "$PROM_HOST" --port "$PROM_PORT"
check_endpoint "Loki" "$CURL_DIR/loki-ready.sh" --host "$LOKI_HOST" --port "$LOKI_PORT"
check_endpoint "Tempo" "$CURL_DIR/tempo-ready.sh" --host "$TEMPO_HOST" --port "$TEMPO_PORT"
check_endpoint "Alloy" "$CURL_DIR/alloy-metrics.sh" --host "$ALLOY_HOST" --port "$ALLOY_PORT"
check_endpoint "Alertmanager" "$CURL_DIR/alertmanager-ready.sh" --host "$ALERTMANAGER_HOST" --port "$ALERTMANAGER_PORT"
check_endpoint "Alert Webhook" "$CURL_DIR/alert-webhook-health.sh" --host "$WEBHOOK_HOST" --port "$WEBHOOK_PORT"

# 4. Verify via Grafana API
echo "🔍 Verifying data in Grafana..."

# Helper to get UID
get_uid() {
    "$CURL_DIR/grafana-datasources.sh" --host "$GRAFANA_HOST" --port "$GRAFANA_PORT" | jq -r ".[] | select(.type==\"$1\") | .uid"
}

# Check Prometheus Metrics
PROM_UID=$(get_uid "prometheus")
if [ -z "$PROM_UID" ]; then
    echo "❌ Prometheus datasource not found"
    FAILURES=$((FAILURES + 1))
else
    echo ">> Found Prometheus UID: $PROM_UID"
fi
echo -n ">> Querying metrics for demo-app... "
FOUND_METRIC=0
for i in $(seq 1 10); do
    RESPONSE=$("$CURL_DIR/prometheus-query-quotes.sh" --host "$PROM_HOST" --port "$PROM_PORT" --query 'sum(quotes_total{app="demo-app"})')
    if echo "$RESPONSE" | jq -e '(.data.result // empty | length) > 0 and (try (.data.result[0].value[1] | tonumber) catch 0) > 0' > /dev/null; then
        VAL=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1] // "0"')
        echo "✅ SUCCESS (Series: $VAL)"
        FOUND_METRIC=1
        break
    fi
    sleep 2
done

if [ "$FOUND_METRIC" -eq 0 ]; then
    echo "❌ FAILED (No metrics found)"
    echo "Full Response: $RESPONSE"
    FAILURES=$((FAILURES + 1))
fi

echo -n ">> Querying metrics for demo-nginx... "
FOUND_METRIC=0
for i in $(seq 1 10); do
    RESPONSE=$("$CURL_DIR/prometheus-query-quotes.sh" --host "$PROM_HOST" --port "$PROM_PORT" --query 'sum(quotes_total{app="demo-nginx"})')
    if echo "$RESPONSE" | jq -e '(.data.result // empty | length) > 0 and (try (.data.result[0].value[1] | tonumber) catch 0) > 0' > /dev/null; then
        VAL=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1] // "0"')
        echo "✅ SUCCESS (Series: $VAL)"
        FOUND_METRIC=1
        break
    fi
    sleep 2
done

if [ "$FOUND_METRIC" -eq 0 ]; then
    echo "❌ FAILED (No metrics found)"
    echo "Full Response: $RESPONSE"
    FAILURES=$((FAILURES + 1))
fi

# Check Loki Logs
LOKI_UID=$(get_uid "loki")
if [ -z "$LOKI_UID" ]; then
    echo "❌ Loki datasource not found"
    FAILURES=$((FAILURES + 1))
else
    echo ">> Found Loki UID: $LOKI_UID"
fi
echo -n ">> Querying logs for 'demo-app'... "
RESPONSE=$("$CURL_DIR/loki-query-demo-app.sh" --host "$LOKI_HOST" --port "$LOKI_PORT")


if echo "$RESPONSE" | jq -e '.data.result | length > 0' > /dev/null; then
    COUNT=$(echo "$RESPONSE" | jq -r '.data.result | length')
    echo "✅ SUCCESS (Found $COUNT log streams)"
else
    echo "❌ FAILED (No logs found)"
    echo "Full Response: $RESPONSE"
    FAILURES=$((FAILURES + 1))
fi

# 5. Verify Tempo traces via Prometheus
echo -n ">> Checking Tempo spans metric... "
TEMPO_METRIC_QUERY='sum(tempo_distributor_spans_received_total)'
FOUND_TEMPO=0
for i in $(seq 1 10); do
    RESPONSE=$("$CURL_DIR/prometheus-query-tempo-spans.sh" --host "$PROM_HOST" --port "$PROM_PORT" --query "$TEMPO_METRIC_QUERY")
    if echo "$RESPONSE" | jq -e '.data.result | length > 0' > /dev/null; then
        VALUE=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1]')
        echo "✅ SUCCESS (Value: $VALUE)"
        FOUND_TEMPO=1
        break
    fi
    sleep 2
done

if [ "$FOUND_TEMPO" -eq 0 ]; then
    echo "❌ FAILED (Tempo spans metric not found)"
    echo "Full Response: $RESPONSE"
    FAILURES=$((FAILURES + 1))
fi

# 6. Verify Alertmanager -> Webhook routing
echo -n ">> Sending test alert to Alertmanager... "
TEST_ALERT_PAYLOAD='[{
  "labels": {
    "alertname": "TestAlert",
    "severity": "info",
    "app": "test",
    "namespace": "monitoring"
  },
  "annotations": {
    "summary": "Alertmanager routing test"
  },
  "startsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"
}]'

if "$CURL_DIR/alertmanager-send-test-alert.sh" --host "$ALERTMANAGER_HOST" --port "$ALERTMANAGER_PORT" --alertname "TestAlert" --severity "info" --app "test" --namespace "monitoring" >/dev/null; then
    echo "✅ SENT"
else
    echo "❌ FAILED to send"
    FAILURES=$((FAILURES + 1))
fi

echo -n ">> Checking webhook for TestAlert... "
FOUND_ALERT=0
for i in $(seq 1 20); do
    WEBHOOK_RESPONSE=$("$CURL_DIR/alert-webhook-alerts.sh" --host "$WEBHOOK_HOST" --port "$WEBHOOK_PORT")
    if echo "$WEBHOOK_RESPONSE" | jq -e '.[] | select(.alert.labels.alertname=="TestAlert")' > /dev/null; then
        FOUND_ALERT=1
        break
    fi
    sleep 2
done

if [ "$FOUND_ALERT" -eq 1 ]; then
    echo "✅ SUCCESS"
else
    echo "❌ FAILED (TestAlert not found)"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "🏁 Test complete with $FAILURES failure(s)."
    exit 1
fi

echo "🏁 Test complete."
