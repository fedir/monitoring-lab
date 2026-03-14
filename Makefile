NAMESPACE=monitoring
MANIFESTS_DIR=yaml

.PHONY: start checkhealth stop clean test full generateload

start:
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f $(MANIFESTS_DIR)/
	@echo "Waiting for Grafana and Demo Apps to be ready..."
	kubectl wait --for=condition=ready pod -l app=grafana -n $(NAMESPACE) --timeout=60s
	kubectl wait --for=condition=ready pod -l app=demo-app -n $(NAMESPACE) --timeout=60s
	kubectl wait --for=condition=ready pod -l app=demo-nginx -n $(NAMESPACE) --timeout=60s
	@echo "Starting port-forwarding for Grafana (http://localhost:3000)..."
	kubectl port-forward -n $(NAMESPACE) svc/grafana 3000:3000 > /dev/null 2>&1 &
	@echo "Starting port-forwarding for Demo Apps (8080, 8081)..."
	kubectl port-forward -n $(NAMESPACE) svc/demo-app 8080:80 > /dev/null 2>&1 &
	kubectl port-forward -n $(NAMESPACE) svc/demo-nginx 8081:80 > /dev/null 2>&1 &
	@echo "Starting port-forwarding for core services (Prometheus, Loki, Tempo, Alloy)..."
	kubectl port-forward -n $(NAMESPACE) svc/prometheus 9090:9090 > /dev/null 2>&1 &
	kubectl port-forward -n $(NAMESPACE) svc/loki 3100:3100 > /dev/null 2>&1 &
	kubectl port-forward -n $(NAMESPACE) svc/tempo 3200:3200 > /dev/null 2>&1 &
	kubectl port-forward -n $(NAMESPACE) svc/alloy 12345:12345 > /dev/null 2>&1 &
	@echo "Starting port-forwarding for alerting services (Alertmanager, Webhook)..."
	kubectl port-forward -n $(NAMESPACE) svc/alertmanager 9093:9093 > /dev/null 2>&1 &
	kubectl port-forward -n $(NAMESPACE) svc/alert-webhook 8082:8080 > /dev/null 2>&1 &
	@sleep 5

generateload:
	@echo "📈 Generating traffic to demo apps..."
	@for i in {1..20}; do \
		curl -s http://localhost:8080 > /dev/null; \
		curl -s http://localhost:8081 > /dev/null; \
		printf "."; \
		sleep 0.2; \
	done
	@printf "\n✅ Load generation complete.\n"

checkload:
	@./test-stack.sh

test: checkload

full:
	$(MAKE) clean
	$(MAKE) start
	@echo "Waiting for metrics to be collected..."
	@sleep 20
	$(MAKE) test
	$(MAKE) clean

checkhealth:
	@echo "Checking status of pods in $(NAMESPACE) namespace:"
	kubectl get pods -n $(NAMESPACE)
	@echo "\nChecking status of services in $(NAMESPACE) namespace:"
	kubectl get svc -n $(NAMESPACE)

stop:
	kubectl delete -f $(MANIFESTS_DIR)/

clean:
	@echo ">> Removing namespace: $(NAMESPACE) (if exists)"
	-kubectl delete namespace $(NAMESPACE) --ignore-not-found
	@echo ">> Killing any existing port-forwards"
	-pkill -f "kubectl port-forward"
	@echo "Waiting for namespace to be fully removed..."
	@while kubectl get ns $(NAMESPACE) >/dev/null 2>&1; do sleep 2; done
	@echo "✅ Environment cleaned."
