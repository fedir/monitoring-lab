#!/bin/bash
set -e

NAMESPACE="${2:-monitoring}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function clean() {
    echo "--- [CLEANING PHASE] ---"
    echo ">> Removing namespace: $NAMESPACE (if exists)"
    kubectl delete namespace $NAMESPACE --ignore-not-found || true
    echo ">> Killing any existing port-forwards"
    pkill -f "kubectl port-forward" || true
    echo -n ">> Waiting for namespace $NAMESPACE to be fully removed"
    MAX_RETRIES=15
    COUNT=0
    while kubectl get ns $NAMESPACE >/dev/null 2>&1; do
        echo -n "."
        sleep 2
        COUNT=$((COUNT+1))
        if [ $COUNT -ge $MAX_RETRIES ]; then
            echo -e "\n!! Namespace is taking too long to delete. Continuing anyway..."
            break
        fi
    done
    echo -e "\n✅ Environment cleaned."
}

function start() {
    echo "--- [STARTING PHASE] ---"
    echo ">> Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE || echo "Namespace already exists or being created"
    echo ">> Applying all manifests to namespace $NAMESPACE"
    # We use -n $NAMESPACE to override whatever is in the YAML files
    # Note: This works for namespaced resources. ClusterRoles/Bindings need care.
    kubectl apply -f "$SCRIPT_DIR/" -n $NAMESPACE
    
    echo ">> Waiting for Grafana pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=grafana -n $NAMESPACE --timeout=120s
    echo ">> Waiting for Demo App pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=demo-app -n $NAMESPACE --timeout=120s
    echo ">> Waiting for Demo Nginx pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=demo-nginx -n $NAMESPACE --timeout=120s

    echo ">> Setting up port-forwarding tunnels..."
    # We need to use -n $NAMESPACE here too
    kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000 > /dev/null 2>&1 &
    kubectl port-forward -n $NAMESPACE svc/demo-app 8080:80 > /dev/null 2>&1 &
    kubectl port-forward -n $NAMESPACE svc/demo-nginx 8081:80 > /dev/null 2>&1 &
    
    echo ">> Giving tunnels 5 seconds to stabilize..."
    sleep 5
    echo "✅ Stack is up and reachable in namespace $NAMESPACE."
}

function test() {
    echo "--- [TESTING PHASE] ---"
    echo ">> Executing test-stack.sh for load generation and verification"
    # Export NAMESPACE so test-stack.sh picks it up
    export NAMESPACE=$NAMESPACE
    "$SCRIPT_DIR/test-stack.sh"
    echo "✅ Testing phase complete."
}

function start() {
    echo "--- [STARTING PHASE] ---"
    echo ">> Creating namespace: $NAMESPACE"
    kubectl create namespace $NAMESPACE
    echo ">> Applying all manifests from $SCRIPT_DIR"
    kubectl apply -f "$SCRIPT_DIR/"
    
    echo ">> Waiting for Grafana pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=grafana -n $NAMESPACE --timeout=120s
    echo ">> Waiting for Demo App pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=demo-app -n $NAMESPACE --timeout=120s
    echo ">> Waiting for Demo Nginx pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=demo-nginx -n $NAMESPACE --timeout=120s

    echo ">> Setting up port-forwarding tunnels..."
    kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000 > /dev/null 2>&1 &
    echo "   - Grafana: http://localhost:3000"
    kubectl port-forward -n $NAMESPACE svc/demo-app 8080:80 > /dev/null 2>&1 &
    echo "   - Demo App: http://localhost:8080"
    kubectl port-forward -n $NAMESPACE svc/demo-nginx 8081:80 > /dev/null 2>&1 &
    echo "   - Demo Nginx: http://localhost:8081"
    
    echo ">> Giving tunnels 5 seconds to stabilize..."
    sleep 5
    echo "✅ Stack is up and reachable."
}

function test() {
    echo "--- [TESTING PHASE] ---"
    echo ">> Executing test-stack.sh for load generation and verification"
    "$SCRIPT_DIR/test-stack.sh"
    echo "✅ Testing phase complete."
}

case "$1" in
    clean) clean ;;
    start) start ;;
    test) test ;;
    full)
        clean
        start
        test
        clean
        ;;
    *)
        echo "Usage: $0 {clean|start|test|full}"
        exit 1
        ;;
esac
