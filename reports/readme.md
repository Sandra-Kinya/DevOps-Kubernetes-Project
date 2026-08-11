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
**SBOM FILE**
**Command**
```bash
trivy image --format cyclonedx -o reports/docker-sbom.json sandrakinya/demo-app:v.1.0
```

---
**SECURITY**

**Image security**

```bash
trivy image --severity HIGH,CRITICAL --output reports/image-scan.txt sandrakinya/demo-app:v.1.0
```

**Scan Dockerfile for misconfigurations**

> Separate from package vulnerabilities — this checks the Dockerfile itself for bad practices (e.g., running as root, missing HEALTHCHECK).
```bash
trivy config --output reports/dockerfile-scan.txt Dockerfile
```

**Scan Helm chart / Kubernetes manifests**

> Checks helm configuration files for security misconfigurations - for missing resource limits, privileged containers, missing security contexts.

```bash
trivy config --output reports/helm-chart-scan.txt charts/demo-app/templates
```
