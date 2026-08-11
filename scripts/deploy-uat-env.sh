#!/bin/bash

set -e

CHART_PATH="./charts/demo-app"

IMAGE_NAME="${IMAGE_NAME:-sandrakinya/demo-app}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"

usage() {
    echo "Usage:"
    echo "  $0 [ID]              Deploy a dynamic test environment"
    echo "  $0 --cleanup <ID>    Tear down a test environment"
    exit 1
}

# ---- Cleanup mode ----

if [ "$1" = "--cleanup" ]; then
    if [ -z "$2" ]; then
        echo "Error: missing environment ID for cleanup."
        usage
    fi

    ID="$2"
    NAMESPACE="test-${ID}"
    RELEASE="demo-app-test-${ID}"

    echo "Tearing down test environment: ${NAMESPACE}"

    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        echo "Namespace ${NAMESPACE} does not exist. Nothing to clean up."
        exit 0
    fi

    helm uninstall "${RELEASE}" -n "${NAMESPACE}" || \
        echo "Release ${RELEASE} is already removed."

    kubectl delete namespace "${NAMESPACE}"

    echo "Done. ${NAMESPACE} has been removed."
    exit 0
fi

# ---- Deploy mode ----

ID="${1:-$(date +%s)}"
NAMESPACE="test-${ID}"
RELEASE="demo-app-test-${ID}"

echo "Deploying dynamic test environment"
echo "Namespace: ${NAMESPACE}"
echo "Release:   ${RELEASE}"
echo "Image:     ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# ---- Create namespace ----

kubectl create namespace "${NAMESPACE}"

# ---- Deploy application ----

helm install "${RELEASE}" "${CHART_PATH}" \
    -n "${NAMESPACE}" \
    --set replicaCount=1 \
    --set environment=test \
    --set service.type=NodePort \
    --set image.repository="${IMAGE_NAME}" \
    --set image.tag="${IMAGE_TAG}"

echo ""
echo "Finding deployment..."

DEPLOYMENT_NAME=$(kubectl get deployment \
    -n "${NAMESPACE}" \
    -o jsonpath='{.items[0].metadata.name}')

echo "Deployment: ${DEPLOYMENT_NAME}"
echo ""
echo "Waiting for deployment to be ready..."

kubectl rollout status \
    deployment/"${DEPLOYMENT_NAME}" \
    -n "${NAMESPACE}" \
    --timeout=120s

echo ""
echo "Test environment is up."

kubectl get pods -n "${NAMESPACE}"
kubectl get svc -n "${NAMESPACE}"

# ---- Get access information ----

NODE_IP=$(kubectl get nodes \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

NODE_PORT=$(kubectl get svc "${RELEASE}-demo-app" \
    -n "${NAMESPACE}" \
    -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo "Application image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Access the app at: http://${NODE_IP}:${NODE_PORT}/"
echo ""
echo "To tear down this environment, run:"
echo "  $0 --cleanup ${ID}"
