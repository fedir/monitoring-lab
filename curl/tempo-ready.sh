#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tempo-ready.sh [options]

Options:
  --host <host>  Hostname (default: localhost)
  --port <port>  Port (default: 3200)
  --help         Show this help
EOF
}

host=localhost
port=3200

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

curl -sS "http://${host}:${port}/ready"
