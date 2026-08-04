**Tool**: Trivy v0.71.2
**Scan type**: Container image (Docker image)
**Target scanned**: sandrakinya/demo-app:v.1.0
**SBOM format**: CycloneDX
**SBOM output**: reports/docker-sbom.json

---
**Deployment artifacts reviewed:**

Dockerfile
Helm chart (charts/demo-app)
Kubernetes manifests:
deployment.yaml
service.yaml
configmap.yaml
ingress.yaml
servicemonitor.yaml
monitoring-values.yaml
app/app.py

---
**Command used to generate the SBOM file**

trivy image --format cyclonedx -o reports/docker-sbom.json sandrakinya/demo-app:v.1.0
