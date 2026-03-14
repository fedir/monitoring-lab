#!/bin/bash

# Configuration
NAMESPACE="${NAMESPACE:-monitoring}"
GRAFANA_URL="http://localhost:3000"
DEMO_APP_URL="http://localhost:8080"
NGINX_URL="http://localhost:8081"

echo "🚀 Starting load generation and verification..."

# 1. Start Port-Forwards for Demo Apps (Grafana is already handled by Makefile)
echo "📡 Setting up temporary port-forwards for demo apps..."
kubectl port-forward -n $NAMESPACE svc/demo-app 8080:80 > /dev/null 2>&1 &
APP_PF_PID=$!
kubectl port-forward -n $NAMESPACE svc/demo-nginx 8081:80 > /dev/null 2>&1 &
NGINX_PF_PID=$!

# Cleanup on exit
cleanup() {
    for pid in "$APP_PF_PID" "$NGINX_PF_PID"; do
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill "$pid"
        fi
    done
    echo "Cleanup done."
}

trap cleanup EXIT

sleep 2 # Wait for PF to stabilize

# 2. Generate Load
echo "traffic 📈 Generating traffic to demo apps..."
for i in {1..20}; do
    curl -s $DEMO_APP_URL > /dev/null
    curl -s $NGINX_URL > /dev/null
    echo -n "."
    sleep 0.5
done
echo " Done."

# 3. Verify via Grafana API
echo "🔍 Verifying data in Grafana..."

# Helper to get UID
get_uid() {
    curl -s "$GRAFANA_URL/api/datasources" | jq -r ".[] | select(.type==\"$1\") | .uid"
}

# Check Prometheus Metrics
PROM_UID=$(get_uid "prometheus")
echo ">> Found Prometheus UID: $PROM_UID"
echo -n ">> Querying 'up{app=\"demo-nginx\"}'... "
METRIC_QUERY='up{app="demo-nginx"}'
RESPONSE=$(curl -s -G "$GRAFANA_URL/api/datasources/proxy/uid/$PROM_UID/api/v1/query" --data-urlencode "query=$METRIC_QUERY")

if echo "$RESPONSE" | jq -e '.data.result | length > 0' > /dev/null; then
    VAL=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1]')
    echo "✅ SUCCESS (Status: $VAL)"
else
    echo "❌ FAILED (No metrics found)"
    echo "Full Response: $RESPONSE"
fi

# Check Loki Logs
LOKI_UID=$(get_uid "loki")
echo ">> Found Loki UID: $LOKI_UID"
echo -n ">> Querying logs for 'demo-app'... "
LOKI_QUERY='{instance=~"monitoring/demo-app.*"}'
RESPONSE=$(curl -s -G "$GRAFANA_URL/api/datasources/proxy/uid/$LOKI_UID/loki/api/v1/query_range" --data-urlencode "query=$LOKI_QUERY")


if echo "$RESPONSE" | jq -e '.data.result | length > 0' > /dev/null; then
    COUNT=$(echo "$RESPONSE" | jq -r '.data.result | length')
    echo "✅ SUCCESS (Found $COUNT log streams)"
else
    echo "❌ FAILED (No logs found)"
    echo "Full Response: $RESPONSE"
fi

echo "🏁 Test complete."
