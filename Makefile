IMAGE_NAME := sandrakinya/demo-app
IMAGE_TAG  := v.1.0
CHART_PATH := ./charts/demo-app
NAMESPACE  := default
DASHBOARD_DIR := monitoring/dashboards
DASHBOARD_NAME := demo-app-overview

.PHONY: help nodes helm-check \
        build push deploy delete-pod \
        install upgrade uninstall reinstall \
        pods svc ingress port-forward-app curl-app \
        monitoring-namespace monitoring-install monitoring-uninstall \
        port-forward-prometheus port-forward-grafana \
        uat-namespace uat-install uat-uninstall \
        scan-image scan-config sbom \
        up down status clean
	dashboard-update

help:
	@echo "Available targets:"
	@echo "  make nodes                 - verify k3s cluster is up"
	@echo "  make build                 - docker build the app image"
	@echo "  make push                  - push image to Docker Hub"
	@echo "  make deploy                - build + push + delete pod (pick up new image)"
	@echo "  make install               - helm install demo-app"
	@echo "  make upgrade               - helm upgrade demo-app"
	@echo "  make uninstall             - helm uninstall demo-app"
	@echo "  make reinstall             - uninstall + install"
	@echo "  make pods                  - kubectl get pods"
	@echo "  make svc                   - kubectl get svc"
	@echo "  make ingress               - kubectl get ingress"
	@echo "  make port-forward-app      - port-forward the app to localhost:8085"
	@echo "  make curl-app              - curl the app's / and /metrics"
	@echo "  make monitoring-install    - install kube-prometheus-stack"
	@echo "  make port-forward-grafana  - port-forward Grafana to localhost:3001"
	@echo "  make port-forward-prometheus - port-forward Prometheus to localhost:9091"
	@echo "  make uat-install           - deploy the UAT release"
	@echo "  make scan-image            - trivy image scan (HIGH/CRITICAL)"
	@echo "  make sbom                  - generate SBOM via trivy"
	@echo "  make up                    - full stack: namespaces + monitoring + app"
	@echo "  make down                  - uninstall app + monitoring"
	@echo "  make status                - quick health snapshot of everything"
	@echo "  make dashboard-update      - regenerate + apply the dashboard ConfigMap after a UI edit"


# ---- Cluster check ----
nodes:
	sudo k3s kubectl get nodes

helm-check:
	helm list -A

# ---- Image build / push / deploy ----
build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

push: build
	docker push $(IMAGE_NAME):$(IMAGE_TAG)

delete-pod:
	kubectl delete pod -l app=demo-app -n $(NAMESPACE)

deploy: push delete-pod
	@echo "Deployed $(IMAGE_NAME):$(IMAGE_TAG) — waiting for rollout..."
	kubectl rollout status deployment/demo-app-demo-app -n $(NAMESPACE)

# ---- Helm lifecycle ----
install:
	helm install demo-app $(CHART_PATH)

upgrade:
	helm upgrade demo-app $(CHART_PATH)

uninstall:
	helm uninstall demo-app || true

reinstall: uninstall install

# ---- App inspection ----
pods:
	kubectl get pods -n $(NAMESPACE)

svc:
	kubectl get svc -n $(NAMESPACE)

ingress:
	kubectl get ingress -n $(NAMESPACE)

port-forward-app:
	kubectl port-forward svc/demo-app-demo-app 8085:8085 -n $(NAMESPACE)

curl-app:
	curl http://localhost:8085/
	@echo ""
	curl http://localhost:8085/metrics

# ---- Monitoring ----
monitoring-namespace:
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

monitoring-install: monitoring-namespace
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
	helm repo update
	helm install monitoring prometheus-community/kube-prometheus-stack \
	  -n monitoring -f monitoring/monitoring-values.yaml

monitoring-uninstall:
	helm uninstall monitoring -n monitoring || true

port-forward-prometheus:
	kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9091:9090

port-forward-grafana:
	kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80

dashboard-update:
	@echo "Regenerating ConfigMap from $(DASHBOARD_DIR)/$(DASHBOARD_NAME).json ..."
	kubectl create configmap $(DASHBOARD_NAME)-dashboard \
	  --from-file=$(DASHBOARD_DIR)/$(DASHBOARD_NAME).json \
	  -n monitoring --dry-run=client -o yaml | \
	kubectl label --local -f - grafana_dashboard="1" -o yaml \
	  > $(DASHBOARD_DIR)/$(DASHBOARD_NAME)-configmap.yaml
	kubectl apply -f $(DASHBOARD_DIR)/$(DASHBOARD_NAME)-configmap.yaml
	@echo "Done. Refresh Grafana in ~30-60s to see the update."


# ---- UAT environment ----
uat-namespace:
	kubectl create namespace uat --dry-run=client -o yaml | kubectl apply -f -

uat-install: uat-namespace
	helm install demo-app-uat $(CHART_PATH) -n uat -f $(CHART_PATH)/values-uat.yaml

uat-uninstall:
	helm uninstall demo-app-uat -n uat || true

# ---- Security scanning ----
scan-image:
	trivy image --severity HIGH,CRITICAL $(IMAGE_NAME):$(IMAGE_TAG)

scan-config:
	trivy config $(CHART_PATH)/templates

sbom:
	mkdir -p reports
	trivy image --format cyclonedx -o reports/docker-sbom.json $(IMAGE_NAME):$(IMAGE_TAG)

# ---- Full lifecycle shortcuts ----
up: nodes monitoring-install install
	@echo "Stack is up. Run 'make port-forward-app' or 'make port-forward-grafana' next."

down: uninstall monitoring-uninstall
	@echo "App and monitoring uninstalled."

status:
	@echo "--- Nodes ---"
	@sudo k3s kubectl get nodes
	@echo "--- Helm releases ---"
	@helm list -A
	@echo "--- App pods ---"
	@kubectl get pods -n $(NAMESPACE)
	@echo "--- Monitoring pods ---"
	@kubectl get pods -n monitoring

clean: down
	@echo "Cleaned up app and monitoring releases (namespaces left intact)."
