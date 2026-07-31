I installed trivy.

Ran the following command to generate sbom file: 
trivy image --format cyclonedx -o reports/docker-sbom.json sandrakinya/demo-app:v.1.0

Ran the following command to generate vulnerability file: 
trivy image --format json -o reports/docker-vulnerability-report.json sandrakinya/demo-app:v.1.0

