#!/bin/bash
set -e

# This script is a wrapper around the Makefile targets
# to maintain compatibility with the existing CI/CD or user workflows.

case "$1" in
    clean)
        make clean
        ;;
    start)
        make start
        ;;
    test)
        make test
        ;;
    full)
        make full
        ;;
    *)
        echo "Usage: $0 {clean|start|test|full}"
        exit 1
        ;;
esac
