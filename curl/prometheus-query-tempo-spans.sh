#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prometheus-query-tempo-spans.sh [options]

Options:
  --host <host>   Hostname (default: localhost)
  --port <port>   Port (default: 9090)
  --query <expr>  PromQL expression override
  --help          Show this help
EOF
}

host=localhost
port=9090
query='sum(tempo_distributor_spans_received_total)'

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
    --query)
      query="${2:-}"
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

curl -sS -G "http://${host}:${port}/api/v1/query" --data-urlencode "query=${query}"
