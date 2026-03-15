#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: alertmanager-send-test-alert.sh [options]

Options:
  --host <host>       Hostname (default: localhost)
  --port <port>       Port (default: 9093)
  --alertname <name>  Alert name (default: TestAlert)
  --severity <level>  Severity label (default: info)
  --app <name>        App label (default: test)
  --namespace <ns>    Namespace label (default: monitoring)
  --help              Show this help
EOF
}

host=localhost
port=9093
alertname=TestAlert
severity=info
app=test
namespace=monitoring

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)
      host="${2:-}"
      shift 2
      ;;
    --port)
      port="${2:-}"
      shift 2
      ;;
    --alertname)
      alertname="${2:-}"
      shift 2
      ;;
    --severity)
      severity="${2:-}"
      shift 2
      ;;
    --app)
      app="${2:-}"
      shift 2
      ;;
    --namespace)
      namespace="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

payload=$(cat <<EOF
[{
  "labels": {
    "alertname": "${alertname}",
    "severity": "${severity}",
    "app": "${app}",
    "namespace": "${namespace}"
  },
  "annotations": {
    "summary": "Alertmanager routing test"
  },
  "startsAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}]
EOF
)

curl -sS -o /dev/null -w "%{http_code}" -X POST "http://${host}:${port}/api/v2/alerts" -H "Content-Type: application/json" -d "$payload" | grep -Eq "200|202"
