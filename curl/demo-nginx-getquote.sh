#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: demo-nginx-getquote.sh [options]

Options:
  --number <n>   Number of items (default: 2)
  --host <host>  Hostname (default: localhost)
  --port <port>  Port (default: 8081)
  --help         Show this help
EOF
}

number=2
host=localhost
port=8081

while [ "$#" -gt 0 ]; do
  case "$1" in
    --number)
      number="${2:-}"
      shift 2
      ;;
    --host)
      host="${2:-}"
      shift 2
      ;;
    --port)
      port="${2:-}"
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

curl -sS -X POST -H "Content-Type: application/json" -d "{\"numberOfItems\":${number}}" "http://${host}:${port}/getquote"
