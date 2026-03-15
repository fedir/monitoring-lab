#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: demo-app-getquote.sh [options]

Options:
  --number <n>   Number of items (default: 3)
  --host <host>  Hostname (default: localhost)
  --port <port>  Port (default: 8080)
  --help         Show this help
EOF
}

number=3
host=localhost
port=8080

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
