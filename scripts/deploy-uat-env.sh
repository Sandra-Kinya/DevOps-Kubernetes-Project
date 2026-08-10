#!/bin/bash

set -e

CHART_PATH="./charts/demo-app"

usage() {
  echo "Usage:"
  echo "  $0 <id>              Deploy a test environment"
  echo "  $0 --cleanup <id>    Tear down a test environment"
  exit 1
}

# ---- Cleanup mode ----
if [ "$1" == "--cleanup" ]; then
  if [ -z "$2" ]; then
    echo "Error: missing <id> for cleanup."
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

  helm uninstall "${RELEASE}" -n "${NAMESPACE}" || echo "Release already removed."
  kubectl delete namespace "${NAMESPACE}"

  echo "Done. ${NAMESPACE} has been removed."
  exit 0
fi

# ---- Deploy mode ----
ID="${1:-$(date +%s)}"
NAMESPACE="test-${ID}"
RELEASE="demo-app-test-${ID}"

echo "Deploying test environment: ${NAMESPACE}"

kubectl create namespace "${NAMESPACE}"

helm install "${RELEASE}" "${CHART_PATH}" \
  -n "${NAMESPACE}" \
  --set replicaCount=1 \
  --set environment=test \
  --set service.type=NodePort

echo ""
echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=demo-app -n "${NAMESPACE}" --timeout=60s

echo ""
echo "Test environment is up."
kubectl get pods -n "${NAMESPACE}"
kubectl get svc -n "${NAMESPACE}"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc "${RELEASE}-demo-app" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo "Access the app at: http://${NODE_IP}:${NODE_PORT}/"
echo ""
echo "To tear down this environment, run:"
echo "  $0 --cleanup ${ID}"
