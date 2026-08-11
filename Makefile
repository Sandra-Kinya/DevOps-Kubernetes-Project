IMAGE_NAME := sandrakinya/demo-app
IMAGE_TAG ?= $(shell git rev-parse --short HEAD)

CHART_PATH := ./charts/demo-app
NAMESPACE := default

DASHBOARD_DIR := monitoring/dashboards
DASHBOARD_NAME := demo-app-overview


.PHONY: help nodes helm-check \
	build push deploy delete-pod \
	install upgrade uninstall reinstall \
	pods svc ingress port-forward-app curl-app \
	monitoring-namespace monitoring-install monitoring-uninstall \
	port-forward-prometheus port-forward-grafana \
	uat-install uat-clean \
	scan-image scan-config sbom \
	dashboard-update \
	up down status clean


# ---- Help ----

help:
	@echo "Available targets:"
	@echo "  make nodes                   - verify k3s cluster is up"
	@echo "  make build                   - build the app image"
	@echo "  make push                    - push image to Docker Hub"
	@echo "  make deploy                  - build, push and deploy the current Git SHA image"
	@echo "  make install                 - install demo-app with the current Git SHA image"
	@echo "  make upgrade                 - upgrade demo-app with the current Git SHA image"
	@echo "  make uninstall               - uninstall demo-app"
	@echo "  make reinstall               - uninstall and install demo-app"
	@echo "  make pods                    - get application pods"
	@echo "  make svc                     - get application Service"
	@echo "  make ingress                 - get application Ingress"
	@echo "  make port-forward-app        - port-forward the app to localhost:8085"
	@echo "  make curl-app                - test the app through the Ingress"
	@echo "  make monitoring-install      - install kube-prometheus-stack"
	@echo "  make monitoring-uninstall    - uninstall kube-prometheus-stack"
	@echo "  make port-forward-grafana    - port-forward Grafana to localhost:3001"
	@echo "  make port-forward-prometheus - port-forward Prometheus to localhost:9091"
	@echo "  make uat-install             - create a dynamic UAT environment"
	@echo "  make uat-clean ID=<id>       - remove a dynamic UAT environment"
	@echo "  make scan-image              - scan the image for HIGH and CRITICAL vulnerabilities"
	@echo "  make scan-config             - scan Helm configuration with Trivy"
	@echo "  make sbom                    - generate the image SBOM"
	@echo "  make dashboard-update        - regenerate and apply the Grafana dashboard ConfigMap"
	@echo "  make up                      - start monitoring and the application"
	@echo "  make down                    - uninstall application and monitoring"
	@echo "  make status                  - show cluster and application status"
	@echo "  make clean                   - clean application and monitoring releases"


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

deploy: push
	@echo "Deploying $(IMAGE_NAME):$(IMAGE_TAG)..."
	helm upgrade --install demo-app $(CHART_PATH) \
		--set image.repository=$(IMAGE_NAME) \
		--set image.tag=$(IMAGE_TAG) \
		-n $(NAMESPACE)
	@echo "Waiting for rollout..."
	kubectl rollout status deployment/demo-app-demo-app -n $(NAMESPACE)


# ---- Helm lifecycle ----

install:
	helm upgrade --install demo-app $(CHART_PATH) \
		--set image.repository=$(IMAGE_NAME) \
		--set image.tag=$(IMAGE_TAG) \
		-n $(NAMESPACE)

upgrade:
	helm upgrade demo-app $(CHART_PATH) \
		--set image.repository=$(IMAGE_NAME) \
		--set image.tag=$(IMAGE_TAG) \
		-n $(NAMESPACE)

uninstall:
	helm uninstall demo-app -n $(NAMESPACE) || true

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
	@echo "Testing application through Ingress..."
	curl http://demo.local/
	@echo ""
	@echo "Testing application metrics through Ingress..."
	curl http://demo.local/metrics


# ---- Monitoring ----

monitoring-namespace:
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

monitoring-install: monitoring-namespace
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
	helm repo update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		-n monitoring \
		-f monitoring/monitoring-values.yaml

monitoring-uninstall:
	helm uninstall monitoring -n monitoring || true

port-forward-prometheus:
	kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9091:9090

port-forward-grafana:
	kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80


# ---- Grafana dashboard ----

dashboard-update:
	@echo "Regenerating ConfigMap from $(DASHBOARD_DIR)/$(DASHBOARD_NAME).json ..."
	kubectl create configmap $(DASHBOARD_NAME)-dashboard \
		--from-file=$(DASHBOARD_DIR)/$(DASHBOARD_NAME).json \
		-n monitoring \
		--dry-run=client \
		-o yaml | \
	kubectl label --local -f - grafana_dashboard="1" -o yaml \
		> $(DASHBOARD_DIR)/$(DASHBOARD_NAME)-configmap.yaml
	kubectl apply -f $(DASHBOARD_DIR)/$(DASHBOARD_NAME)-configmap.yaml
	@echo "Done. Refresh Grafana in approximately 30 to 60 seconds."


# ---- Dynamic UAT environment ----

uat-install: push
	@IMAGE_NAME="$(IMAGE_NAME)" IMAGE_TAG="$(IMAGE_TAG)" ./scripts/deploy-uat-env.sh

uat-clean:
	@if [ -z "$(ID)" ]; then \
		echo "Usage: make uat-clean ID=<id>"; \
		exit 1; \
	fi
	@./scripts/deploy-uat-env.sh --cleanup $(ID)


# ---- Security scanning ----

scan-image:
	trivy image --severity HIGH,CRITICAL $(IMAGE_NAME):$(IMAGE_TAG)

scan-config:
	trivy config $(CHART_PATH)/templates

sbom:
	mkdir -p reports
	trivy image \
		--format cyclonedx \
		-o reports/docker-sbom.json \
		$(IMAGE_NAME):$(IMAGE_TAG)


# ---- Full lifecycle shortcuts ----

up: nodes monitoring-install install
	@echo "Stack is up. Run 'make ingress' or 'make curl-app' to test the application."

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
	@echo "Cleaned up app and monitoring releases. Namespaces remain intact."
