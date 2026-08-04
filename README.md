# Local Kubernetes Cluster (k3s)

## Deploying an app to a local K3s cluster --> package with Helm --> use Prometheus and Grafana for monitoring.
This project demonstrates how to deploy a Flask application to a K3s cluster using Helm and implement monitoring.

## Table of Contents

- Project Overview
- Project architecture
- Installation
- Deployment
- Monitoring
- Optional tasks
- Tests
- Challenges

## Project overview
- Deploying a Flask application on K3s using Helm
- Using ConfigMaps for application configuration
- Exposing custom Prometheus metrics
- Monitoring the application with Prometheus and Grafana
- Setting up Prometheus alert rules
- Demonstrating Kubernetes self healing and scaling
- Pushing docker image to dockerhub

## Project architecture
https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Detailed_project_architecture.png

---

## 1. Installation 
**1a: INSTALL k3s**
```bash
curl -sfL https://get.k3s.io | sh -
```

VERIFY
```bash
sudo k3s kubectl get nodes
```

**1b: INSTALL HELM**
```bash
sudo snap install helm --classic
```
> Helm is not available in default ubuntu package repositories

**1c: Fix permission issue**
> To avoid using sudo everytime
```bash
mkdir ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### 2. CREATING A REPOSITORY 
The project files will be in this directory
Added .gitignore 
> To stop junk files and confidential files from getting commited

### 3. CREATING THE FILE STRUCTURE

https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/FileStructure.png

### 4: MODIFYING THE APP FILE
```python
from flask import Flask, Response
import os

app = Flask(__name__)
GREETING = os.environ.get("APP_GREETING", "Hello from Kubernetes + Helm!")
request_count = 0

@app.route('/')
def hello():
    global request_count
    request_count += 1
    return GREETING

@app.route('/metrics')
def metrics():
    return Response(f"demo_app_custom_metric {request_count}\n", mimetype="text/plain")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8085)
```
> I used port 8085

**/ route** — returns a greeting message. That message is read from an environment variable (APP_GREETING), with a hardcoded fallback if that variable isn't set — this is what the ConfigMap later feeds in*

**/metrics route** — exposes one custom metric in the exact text format Prometheus expects, with the correct Content-Type header (text/plain) — this was a fix for a scrape error in prometheus.*

**count requests** - makes the metric dynamic. Every hit to / increments the metricevery hit to / increments the metric.

### 5: DOCKERFILE
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY app/app.py .
RUN pip install flask
EXPOSE 8085
CMD ["python", "app.py"]
```

### 6: BUILDING DOCKER IMAGE
```bash
docker build -t demo-app:v.1.0 .
```

## Deployment

### 7: IMPORT IMAGE INTO k3s
```bash
docker save demo-app:v.1.0 | sudo k3s ctr images import -
```

### 8: CREATING HELM CHART FILES
```bash
cd /charts/demo-app
```

**8a) nano chart.yaml** 
*Declares helm's name, version, and a short description.*

```yaml
apiVersion: v2
name: demo-app
version: 0.1.0
description: A simple Flask app chart
```

**8b) nano values.yaml**
*Contains every configurable value templates use (image tag, replica count, port, greeting text, CPU/memory limits)*
```yaml
replicaCount: 1

image:
  repository: sandrakinya/demo-app
  tag: v.1.0
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8085

config:
  appGreeting: "Hello from Kubernetes + Helm!"

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```


### 9: CREATE TEMPLATE FILES
<details>
<summary> ## Template files</summary>

```bash
cd template
```

**9a) nano deployment.yaml**
*If no strategy is set, kubernetes uses rolling update by default*
*Tells Kubernetes to keep exactly 1 replicaCount copies of this Pod running, using this image, with these resource limits, loading this **ConfigMap** as environment variables.*
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "demo-app.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "demo-app.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "demo-app.name" . }}
    spec:
      containers:
      - name: demo-app
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 8085

        envFrom:
        - configMapRef:
            name: {{ include "demo-app.fullname" . }}-config

        resources:
          requests:
            cpu: {{ .Values.resources.requests.cpu }}
            memory: {{ .Values.resources.requests.memory }}
          limits:
            cpu: {{ .Values.resources.limits.cpu }}
            memory: {{ .Values.resources.limits.memory }}
```

**9b) nano service.yaml**
*Creates a stable internal network address (demo-app-demo-app, port 8085) that routes traffic to the pod that is currently running*
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "demo-app.fullname" . }}
  labels:
    app: {{ include "demo-app.name" . }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ include "demo-app.name" . }}
  ports:
  - name: http
    port: {{ .Values.service.port }}
    targetPort: 8085
```

**9c) nano _helpers.tpl**
*I created helpers.tpl to store reusable template functions and naming rules - {{ include "demo-app.name" . }} are not built-in Helm functions they only work if a _helpers.tpl file defines them.*
*I changed the hardcoded service name for the fullname helper — this is necessary so the Ingress actually points at the Service I deployed*
```yaml
{{- define "demo-app.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "demo-app.fullname" -}}
{{- .Release.Name -}}-{{- .Chart.Name -}}
{{- end -}}
```


**9d) nano configmap.yaml** - stores the configurable greeting message (APP_GREETING) as a Kubernetes ConfigMap, which the Deployment loads into the container as an environment variable — *This will allow me to change the greeting without rebuilding the image.*
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo-app.fullname" . }}-config
data:
  APP_GREETING: {{ .Values.config.appGreeting | quote }}
```

**9e) nano ingress.yaml** - *I added the kubernetes.io/ingress.class: traefik annotation* 
This routes external requests arriving at demo.local to the demo-app-demo-app Service making the app reachable via a normal URL instead of only kubectl port-forward.
Added ip address to hosts to map to demo.local
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "demo-app.fullname" . }}
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: demo.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
envFrom:
        - configMapRef:
            name: {{ include "demo-app.fullname" . }}-config

        resources:
          requests:
            cpu: {{ .Values.resources.requests.cpu }}
            memory: {{ .Values.resources.requests.memory }}
          limits:
            cpu: {{ .Values.resources.limits.cpu }}
            memory: {{ .Values.resources.limits.memory }}
```

**9b) nano service.yaml**
*Creates a stable internal network address (demo-app-demo-app, port 8085) that routes tra>
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "demo-app.fullname" . }}
  labels:
    app: {{ include "demo-app.name" . }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ include "demo-app.name" . }}
  ports:
  - name: http
    port: {{ .Values.service.port }}
    targetPort: 8085
```

**9c) nano _helpers.tpl**
*I created helpers.tpl to store reusable template functions and naming rules - {{ include>
*I changed the hardcoded service name for the fullname helper — this is necessary so the >
```yaml
            name: {{ include "demo-app.fullname" . }}
            port:
              number: {{ .Values.service.port }}
```

**9f) nano monitor-values.yaml** - Helm values override - to the separate kube-prometheus-stack chart that enables persistent storage for Prometheus and Grafana so their data survives pod restarts.
```yaml
grafana:
  persistence:
    enabled: true
    size: 1Gi

prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
```

</details>


### 10: DEPLOY THE APP WITH HELM
```bash
cd ~/Sandra_tcs-devop-project-C
helm install demo-app ./charts/demo-app
```

### 11: VERIFY
```bash
kubectl get pods
kubectl get svc
```

### 12: Confirm the app responds via kubectl
```bash
kubectl port-forward svc/demo-app-demo-app 8085:8085

curl http://localhost:8085/
curl http://localhost:8085/metrics
```

### 13: Confirm the app responds via ingress

a) Confirm ingress is running: kubectl get ingress

b) Make demo.local(added to the ingress.yaml) resolve to my machine: Added ip address to etc/hosts to map to demo.local

c) Test:
curl http://demo.local/
curl http://demo.local/metrics

https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Implementation_videos/demo.local.png

## Monitoring

### 14: Implementing monitoring
*I created a separate namespace for monitoring* - to enable isolation and avoid cluttering the defaults namespace where the app is.

**14a) Adding the helm repo:**
```bash
helm repo add prometheus-community https://prometheus-community.>
helm repo update
helm repo list
```

**14b) Creating new namespace:**
```bash
kubectl create namespace monitoring
kubectl get namespaces
```

**14c) Install prometheus into the namespace:**
```bash
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring
```

**14d) Verify several pods were created and running**
```bash
kubectl get pods -n monitoring
```

**14f) To access prometheus**
```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9091:9090
```
http://localhost:9091

**14g) To access Grafana**
```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80
```
http://localhost:3001:80

> This keeps running continuously in the background for the connection to stay alive.


### 15: Creating rule file for alerting

**15a)**
> This rule fires if Prometheus can't scrape the app for 1 minute straight.

```bash
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: {{ include "demo-app.fullname" . }}-rules
  labels:
    release: monitoring
spec:
  groups:
  - name: demo-app.rules
    rules:
    - alert: DemoAppPodDown
      expr: up{job="demo-app-demo-app"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Demo app pod is down"
        description: "The demo-app target has been unreachable for more than 1 minute."
```

**15b) Apply the change**

```bash
cd ~/Sandra_tcs-devop-project-C
helm upgrade demo-app ./charts/demo-app
```

**15c) Confirm Prometheus loaded the rule**
```bash
kubectl get prometheusrule -n default
```

**15d) Test**
Delete pod and check if the alert fires
```bash
kubectl delete pod -l app=demo-app -n default
```

### 16: Getting prometheus to scrap the application.

**16a) Check the label selector that prometheus expects:**
```bash
kubectl get prometheus -n monitoring -o yaml | grep -A10 serviceMonitorSelector
```

**16b) Create ServiceMonitor yaml**

> Tells the Prometheus Operator to find any Service labeled app: demo-app, and scrape its /metrics endpoint every 15 seconds.>

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "demo-app.fullname" . }}
  labels:
    release: monitoring
spec:
  selector:
    matchLabels:
      app: {{ include "demo-app.name" . }}
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
```


**16c) Added a name port in service.yaml**
***To expose multiple ports, every port has to have a unique name. These names are used to map he service ports.

**16d) Apply changes**
```bash
helm upgrade
```

**16e) Verify prometheus picked it up**
```bash
kubectl get servicemonitor -A
```

**16f) Get the service name**
```bash
kubectl get svc -n monitoring
```

**16g) Making the metric more dynamic**
> Add count request to app.py
**count requests** - makes the metric dynamic. Every hit to / increments the metric

**16h) Triggering the prometheus alert**
```bash
kubectl scale deployment demo-app-demo-app -n default --replicas=0
```

**Restore normal state**

```bash
kubectl scale deployment demo-app-demo-app -n default --replicas=1
```
### 17: BUILDING GRAFANA DASHBOARD**
**17a) Confirm prometheus has the metric on UI**
Query:
demo_app_custom_metric

**17b) Open Grafana on the browser**
localhost:3001

**17c) Create a new dashboard**
Dashboards > New > Add visualization

**17d) Grafana Dashboard Panels**

| Panel Title | PromQL Query |
|--------------|--------------|
| Demo App Custom Metric | `demo_app_custom_metric` |
| Request Rate (per second) | `rate(demo_app_custom_metric[1m])` |
| Pod CPU Usage | `sum(rate(container_cpu_usage_seconds_total{namespace="default"}[5m]))` |
| Pod Memory Usage | `sum(container_memory_working_set_bytes{namespace="default"})` |
| Pod Restarts | `kube_pod_container_status_restarts_total{namespace="default"}` |
| Running Pods | `count(kube_pod_status_phase{namespace="default", phase="Running"})` |

---

## Additional task
### PUSH IMAGE TO DOCKER HUB

** Build image --> Push to docker hub --> Pull into K3s**


The app image is pushed to Docker Hub instead of being
imported directly into k3s's local containerd store.

*CI/CD pattern: build → push to cloud registry → cluster pulls the image
over the network, rather than relying on local-only images.*

a)Login to docker hub via terminal
```bash
docker login
```

b) Create a repository on Docker Hub
https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Screenshots/Docker_hub_repository.png

c) Tag existing image with docker hub username
```bash
docker tag demo-app:v.1.0 sandrakinya/demo-app:v.1.0
```

d) Push image to docker hub
```bash
docker push sandrakinya/demo-app:v.1.0
```

e) Update values.yaml to pull from docker hub instead of local import
image:
  repository: sandrakinya/demo-app
  tag: v.1.0
  pullPolicy: IfNotPresent
> IfNotPresent means pull from the registry (Docker Hub) if it's not already cached locally.

f) Apply change
```bash
helm upgrade demo-app ./charts/demo-app
```
g) Delete previous pod - to use a fresh pod which pulls from Docker Hub

h) Verify
```bash
kubectl get pods
kubectl describe pod
kubectl get svc -n default
```

> Any changes on app.py hence forth will require: docker build - docker push - kubectl delete pod.


---
## Optional tasks

### CREATING A CONFIG FILE

a) Edit app.py to read a configurable greeting message from an environment variable. The greeting message will be stored in the configMap.

b) Rebuild and reimport the image since app.py changed.
```bash
cd ~/Sandra_tcs-devop-project-C
docker build -t demo-app:v.1.0 .
docker save demo-app:v.1.0 -o demo-app.tar
sudo k3s ctr -n k8s.io images import demo-app.tar
```

c) Edit deployment.yaml - Add an envFrom block under the existing container spec.
```bash
envFrom:
        - configMapRef:
            name: {{ include "demo-app.fullname" . }}-config
```

d) Apply the changes
```bash
cd ~/Sandra_tcs-devop-project-C
helm upgrade demo-app ./charts/demo-app
```

### SBOM REPORT
a) Install trivy

b) To generate SBOM report:
```bash
trivy image --format cyclonedx -o reports/docker-sbom.json sandrakinya/demo-app:v.1.0
```

---

<details>
<summary> ## TESTS </summary>
## Tests
### 1. DEMONSTRATING SELF HEALING
Kubernetes checks if there is exactly one healthy running pod (replicas:2)

a) Confirm current health state: kubectl get pods

b) Kill pod: kubectl delete pod

c) Immediately check pod status again: kubectl get pods
A new pod appears automatically

https://github.com/user-attachments/assets/d47d7a5f-a634-4505-8b06-a4de5fdcdf74


### 2. PRACTICE THE FULL HELM LIFECYCLE
a) Current state:
```bash
helm list
kubectl get pods
```

b) Helm upgrade
```bash
helm updgrade demo-app
```

c) View revision history
```bash
helm history demo-app
```

d) Rollback
```bash
helm rollback demo-app 1
```

e) Roll forward to latest revision
```bash
helm upgrade demo-app
```

f) Uninstall
```bash
helm uninstall demo-app
kubectl get pods
kubectl get svc
```

g) Reinstall
```bash
helm install demo-app
kubectl get pods
```
https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Implementation_videos/Helm_LifeCycle.mp4


### 3. CHECKING RESOURCE UTILIZATION
I checked cluster and pod resource usage using the metrics-server bundled with k3s:

- **kubectl top node** — overall CPU/memory usage on the single-node cluster
- **kubectl top pods -A** — per-pod usage across all namespaces
- **kubectl top pod -n monitoring** — resource usage of the Prometheus/Grafana stack specifically

https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Implementation_videos/ResourceUtilization.mp4


**I added CPU and memory requests and limits in deployment.yaml**.These should be added to prevent one workload from starving others of resources.
Demo-app now has explicit CPU and memory requests and limits set in values.yaml and applied via deployment.yaml, preventing it from starving other workloads (that is the monitoring stack) of cluster resources.

> values.yaml
```bash
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```

> deployment.yaml
```bash
resources:
          requests:
            cpu: {{ .Values.resources.requests.cpu }}
            memory: {{ .Values.resources.requests.memory }}
          limits:
            cpu: {{ .Values.resources.limits.cpu }}
            memory: {{ .Values.resources.limits.memory }}
```

**Checking Dependencies**
- [x] k3s: v1.36.2+k3s1
- [x] Helm: v4.2.3
- [x] kubectl: v5.8.1
- [x] Docker: 29.6.1
- [x] Python: 3.12.13 (base image)
- [x] Flask: 3.1.3
- [x] Helm chart dependencies: none (standalone chart)
- [x] kube-prometheus-stack: installed via prometheus-community Helm repo

https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Implementation_videos/Versions.mp4

**Namespace overview**
I created a separate namespace for monitoring. *This is to provide isolation and clarity.*

https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Implementation_videos/Namespaces.mp4

**Persistent storage awareness**
kube-prometheus-stack did not create persistent volumes therefore I added persistent storage (PVCs) to Prometheus and Grafana via a Helm values override, so metrics history and dashboards survive pod restarts or rescheduling instead of being lost with the default ephemeral storage.

https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/blob/1574b7d575fda566c5813f61ba2887b3a334388d/Implementation_videos/PersistentStorage.mp4


### Test scaling
**a) Scale up manually**
```bash
kubectl scale deployment demo-app-demo-app -n default --replicas=3
kubectl get pods -n default
```

**b) Confirm the Service load-balances across all 3**
```bash
kubectl port-forward svc/demo-app-demo-app 8085:8085
```
curl http://localhost:8085/ calls — traffic is distributed across the 3 pods.

**c) Scale back down**
```bash
kubectl scale deployment demo-app-demo-app -n default --replicas=1
```

</details>


---

<details>
<summary> ## CHALLENGES ENCOUNTERED</summary>
### ISSUES

Port is already allocated
Solution: I used port 8085 since port 8080 is currently being used by Jenkins.

Error calling include
Solution: I created _helpers.tpl to store reusable template functions and naming rules.

Helm reported "Install complete" but no pods or services were created
Finding: The templates folder was misspelled "template" instead of "templates".
Solution: mv template templates, then re-ran helm upgrade.

ErrImageNeverPull - pod stuck, image not found
Finding: values.yaml requested image tag "latest", but only "v1.0" existed in
k3s's containerd store.
Solution: Updating values.yaml to reference the tag that actually existed.

Tag mismatch between Docker and containerd (v1.0 vs v.1.0)
Finding: Docker's local image store had the image tagged "v.1.0" (with a dot),
while containerd's k8s.io namespace had it imported as "v1.0" (no dot)
Solution: Standardized on "v.1.0" across values.yaml, the Docker build
command, and the containerd import command.

git push rejected - divergent branches
Finding: I edited the readme file using GUI, commited the changes and forgot to pull the repo when working on the project. Thus the remote repo had commits not present locally.
Solution:
  git config pull.rebase false
  git pull
  git push

Grafana - Unable to listen on port 3000: Listeners failed to create with the following errors: [unable to create listener: Error listen tcp4 127.0.0.1:3000: bind: address already in use unable to create listener: Error listen tcp6 [::1]:3000: bind: address already in use]
error: unable to listen on any of the requested ports: [{3000 3000}]
Finding: sudo ss -tulpn | grep 3000 : Docker is running on that port
Solution: kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80

Prometheus -
Unable to listen on port 9090: Listeners failed to create with the following errors: [unable to create listener: Error listen tcp4 127.0.0.1:9090: bind: address already in use unable to create listener: Error listen tcp6 [::1]:9090: bind: address already in use]
error: unable to listen on any of the requested ports: [{9090 9090}]
Solution: kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9091:9090

failed to resolve reference "SandraKinya/demo-app:v.1.0": failed to do request: 
Head https://SandraKinya/v2/demo-app/manifests/v.1.0": dial tcp: lookup SandraKinya
Finding: Docker image references must be entirely lowercase — capital letters aren't valid in image names/tags.
Solution: Re-tag and push image with lowercase name

ImagePullBackOff error - which was caused by capitalizing the image reference.
Solution:
Re-tagged and re-pushed the image using the correct lowercase Docker Hub username.
Applied the corrected values.yaml via helm upgrade.
</details>

**Author: Sandra Kinya Gikundi**
