NAMESPACE=monitoring
MANIFESTS_DIR=.

.PHONY: start checkhealth stop clean

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

generateload:
	@echo "📈 Generating traffic to demo apps..."
	@for i in {1..20}; do \
		curl -s http://localhost:8080 > /dev/null; \
		curl -s http://localhost:8081 > /dev/null; \
		echo -n "."; \
		sleep 0.2; \
	done
	@echo "\n✅ Load generation complete."

checkload:
	@./test-stack.sh

checkhealth:
	@echo "Checking status of pods in $(NAMESPACE) namespace:"
	kubectl get pods -n $(NAMESPACE)
	@echo "\nChecking status of services in $(NAMESPACE) namespace:"
	kubectl get svc -n $(NAMESPACE)

stop:
	kubectl delete -f $(MANIFESTS_DIR)/

clean:
	kubectl delete namespace $(NAMESPACE)
	@echo "Stopping any background port-forwarding..."
	-pkill -f "kubectl port-forward"
