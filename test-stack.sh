#!/bin/bash

# Configuration
NAMESPACE="${NAMESPACE:-monitoring}"
GRAFANA_URL="http://localhost:3000"
DEMO_APP_URL="http://localhost:8080"
NGINX_URL="http://localhost:8081"
PROM_URL="http://localhost:9090"
LOKI_URL="http://localhost:3100"
TEMPO_URL="http://localhost:3200"
ALLOY_URL="http://localhost:12345"
ALERTMANAGER_URL="http://localhost:9093"
WEBHOOK_URL="http://localhost:8082"

PF_PIDS=()
FAILURES=0

echo "🚀 Starting load generation and verification..."

ensure_port_forward() {
    local name="$1"
    local svc="$2"
    local local_port="$3"
    local target_port="$4"
    local health_url="$5"
    local post_data="$6"
    local attempts=15

    if [ -n "$post_data" ]; then
        if curl -sf --max-time 2 -X POST -H "Content-Type: application/json" -d "$post_data" "$health_url" >/dev/null; then
            return
        fi
    elif curl -sf --max-time 2 "$health_url" >/dev/null; then
        return
    fi

    kubectl port-forward -n "$NAMESPACE" "svc/$svc" "$local_port:$target_port" > /dev/null 2>&1 &
    PF_PIDS+=("$!")

    for i in $(seq 1 "$attempts"); do
        sleep 2
        if [ -n "$post_data" ]; then
            if curl -sf --max-time 2 -X POST -H "Content-Type: application/json" -d "$post_data" "$health_url" >/dev/null; then
                return
            fi
        elif curl -sf --max-time 2 "$health_url" >/dev/null; then
            return
        fi
    done

    echo "❌ Failed to reach $name at $health_url"
    FAILURES=$((FAILURES + 1))
}

check_endpoint() {
    local name="$1"
    local url="$2"

    if curl -sf --max-time 3 "$url" >/dev/null; then
        echo "✅ $name reachable"
    else
        echo "❌ $name not reachable ($url)"
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
ensure_port_forward "Grafana" "grafana" 3000 3000 "$GRAFANA_URL/api/health"
ensure_port_forward "Demo App" "demo-app" 8080 80 "$DEMO_APP_URL/getquote" '{"numberOfItems":3}'
ensure_port_forward "Demo Nginx" "demo-nginx" 8081 80 "$NGINX_URL/getquote" '{"numberOfItems":2}'
ensure_port_forward "Prometheus" "prometheus" 9090 9090 "$PROM_URL/-/ready"
ensure_port_forward "Loki" "loki" 3100 3100 "$LOKI_URL/ready"
ensure_port_forward "Tempo" "tempo" 3200 3200 "$TEMPO_URL/ready"
ensure_port_forward "Alloy" "alloy" 12345 12345 "$ALLOY_URL/metrics"
ensure_port_forward "Alertmanager" "alertmanager" 9093 9093 "$ALERTMANAGER_URL/-/ready"
ensure_port_forward "Alert Webhook" "alert-webhook" 8082 8080 "$WEBHOOK_URL/healthz"

# 2. Generate Load
echo "traffic 📈 Generating traffic to demo apps..."
for i in {1..20}; do
    curl -s -X POST -H "Content-Type: application/json" -d '{"numberOfItems":3}' "$DEMO_APP_URL/getquote" > /dev/null
    curl -s -X POST -H "Content-Type: application/json" -d '{"numberOfItems":2}' "$NGINX_URL/getquote" > /dev/null
    printf "."
    sleep 0.5
done
echo " Done."

# 3. Verify service endpoints
echo "🔍 Verifying service endpoints..."
check_endpoint "Grafana" "$GRAFANA_URL/api/health"
check_endpoint "Prometheus" "$PROM_URL/-/ready"
check_endpoint "Loki" "$LOKI_URL/ready"
check_endpoint "Tempo" "$TEMPO_URL/ready"
check_endpoint "Alloy" "$ALLOY_URL/metrics"
check_endpoint "Alertmanager" "$ALERTMANAGER_URL/-/ready"
check_endpoint "Alert Webhook" "$WEBHOOK_URL/healthz"

# 4. Verify via Grafana API
echo "🔍 Verifying data in Grafana..."

# Helper to get UID
get_uid() {
    curl -s "$GRAFANA_URL/api/datasources" | jq -r ".[] | select(.type==\"$1\") | .uid"
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
METRIC_QUERY='count({service_name="demo-app"})'
RESPONSE=$(curl -s -G "$GRAFANA_URL/api/datasources/proxy/uid/$PROM_UID/api/v1/query" --data-urlencode "query=$METRIC_QUERY")

if echo "$RESPONSE" | jq -e '(.data.result // empty | length) > 0 and (try (.data.result[0].value[1] | tonumber) catch 0) > 0' > /dev/null; then
    VAL=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1] // "0"')
    echo "✅ SUCCESS (Series: $VAL)"
else
    echo "❌ FAILED (No metrics found)"
    echo "Full Response: $RESPONSE"
    FAILURES=$((FAILURES + 1))
fi

echo -n ">> Querying metrics for demo-nginx... "
METRIC_QUERY='count({service_name="demo-nginx"})'
RESPONSE=$(curl -s -G "$GRAFANA_URL/api/datasources/proxy/uid/$PROM_UID/api/v1/query" --data-urlencode "query=$METRIC_QUERY")

if echo "$RESPONSE" | jq -e '(.data.result // empty | length) > 0 and (try (.data.result[0].value[1] | tonumber) catch 0) > 0' > /dev/null; then
    VAL=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1] // "0"')
    echo "✅ SUCCESS (Series: $VAL)"
else
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
LOKI_QUERY='{instance=~"monitoring/demo-app.*"}'
RESPONSE=$(curl -s -G "$GRAFANA_URL/api/datasources/proxy/uid/$LOKI_UID/loki/api/v1/query_range" --data-urlencode "query=$LOKI_QUERY")


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
    RESPONSE=$(curl -s -G "$PROM_URL/api/v1/query" --data-urlencode "query=$TEMPO_METRIC_QUERY")
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

if curl -s -o /dev/null -w "%{http_code}" -X POST "$ALERTMANAGER_URL/api/v2/alerts" -H "Content-Type: application/json" -d "$TEST_ALERT_PAYLOAD" | grep -Eq "200|202"; then
    echo "✅ SENT"
else
    echo "❌ FAILED to send"
    FAILURES=$((FAILURES + 1))
fi

echo -n ">> Checking webhook for TestAlert... "
FOUND_ALERT=0
for i in $(seq 1 20); do
    WEBHOOK_RESPONSE=$(curl -s "$WEBHOOK_URL/alerts")
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
