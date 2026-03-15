#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: loki-query-demo-app.sh [options]

Options:
  --host <host>   Hostname (default: localhost)
  --port <port>   Port (default: 3100)
  --query <expr>  LogQL expression override
  --help          Show this help
EOF
}

host=localhost
port=3100
query='{namespace="monitoring",app="demo-app"}'

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

curl -sS -G "http://${host}:${port}/loki/api/v1/query_range" --data-urlencode "query=${query}"
