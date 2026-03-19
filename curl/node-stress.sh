#!/usr/bin/env bash
# node-stress.sh — 30-second CPU stress test designed to push node_load1 > 1
# Deploys a temporary stress pod on the cluster, polls Prometheus for live
# load-average readings, and cleans up on exit (or Ctrl-C).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: node-stress.sh [options]

Runs a 30-second CPU stress test on the Kubernetes node by launching a
temporary pod with stress-ng. Polls Prometheus every 5 s and prints the
live node_load1 value so you can confirm the load charge exceeds 1.

Options:
  --workers  <n>     Number of CPU stress workers (default: 2)
  --duration <s>     Stress duration in seconds (default: 30)
  --prom-host <h>    Prometheus host (default: localhost)
  --prom-port <p>    Prometheus port (default: 9090)
  --namespace <ns>   Kubernetes namespace to run the pod in (default: monitoring)
  --help             Show this help
EOF
}

workers=2
duration=30
prom_host=localhost
prom_port=9090
namespace=monitoring
pod_name="node-stress-$(date +%s)"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workers)   workers="${2:-}";   shift 2 ;;
    --duration)  duration="${2:-}";  shift 2 ;;
    --prom-host) prom_host="${2:-}"; shift 2 ;;
    --prom-port) prom_port="${2:-}"; shift 2 ;;
    --namespace) namespace="${2:-}"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# -- helpers ------------------------------------------------------------------

query_load1() {
  curl -sS -G "http://${prom_host}:${prom_port}/api/v1/query" \
    --data-urlencode 'query=node_load1' \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
if not results:
    print('  load1: (no data yet)')
else:
    for r in results:
        inst = r['metric'].get('instance', 'node')
        val  = float(r['value'][1])
        flag = ' <-- ABOVE 1 !' if val > 1 else ''
        print(f'  load1 [{inst}]: {val:.3f}{flag}')
" 2>/dev/null || echo "  load1: (prometheus unreachable)"
}

cleanup() {
  echo ""
  echo "[*] Cleaning up stress pod '${pod_name}' ..."
  kubectl delete pod "${pod_name}" -n "${namespace}" --ignore-not-found --grace-period=0 >/dev/null 2>&1 || true
  echo "[*] Done."
}
trap cleanup EXIT INT TERM

# -- launch stress pod --------------------------------------------------------

echo "[*] Launching stress pod '${pod_name}' in namespace '${namespace}'"
echo "    workers=${workers}  duration=${duration}s"
echo ""

kubectl run "${pod_name}" \
  --image=polinux/stress \
  --restart=Never \
  --namespace="${namespace}" \
  --labels="app=node-stress,temporary=true" \
  --requests="cpu=0" \
  --limits="cpu=0" \
  -- stress --cpu "${workers}" --timeout "${duration}s" \
  >/dev/null 2>&1

# Wait for the pod to reach Running
echo "[*] Waiting for pod to start ..."
kubectl wait pod "${pod_name}" \
  -n "${namespace}" \
  --for=condition=Ready \
  --timeout=60s >/dev/null 2>&1 || true

echo "[*] Stress pod is running. Polling node_load1 every 5 s for ${duration} s ..."
echo "    (Open the 'Cluster Nodes — CPU Usage & Load' dashboard in Grafana to visualise)"
echo ""

elapsed=0
while [ "${elapsed}" -lt "${duration}" ]; do
  printf "[%3ds / %ds]\n" "${elapsed}" "${duration}"
  query_load1
  sleep 5
  elapsed=$(( elapsed + 5 ))
done

# Final reading after stress completes
echo ""
echo "[*] Stress period over. Final load1 reading:"
query_load1
echo ""
echo "[*] Stress test complete."
