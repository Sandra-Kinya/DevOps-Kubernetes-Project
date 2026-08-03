I installed trivy.

Ran the following command to generate sbom file: 
trivy image --format cyclonedx -o reports/docker-sbom.json sandrakinya/demo-app:v.1.0


