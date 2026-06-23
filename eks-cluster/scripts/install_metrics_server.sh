#!/usr/bin/env bash
set -euo pipefail

METRICS_SERVER_MANIFEST_URL="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"

if kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
  echo "metrics-server deployment already exists; preserving the installed manifest version."
else
  echo "Installing metrics-server..."
  kubectl apply -f "$METRICS_SERVER_MANIFEST_URL"
fi

echo "Waiting for deployment to appear..."
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s

echo "Setting EKS-compatible metrics-server args..."
kubectl -n kube-system patch deployment metrics-server \
  --type='strategic' \
  -p='{
    "spec": {
      "template": {
        "spec": {
          "containers": [
            {
              "name": "metrics-server",
              "args": [
                "--cert-dir=/tmp",
                "--secure-port=10250",
                "--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP",
                "--kubelet-use-node-status-port",
                "--metric-resolution=15s",
                "--kubelet-insecure-tls"
              ]
            }
          ]
        }
      }
    }
  }'

echo "Waiting for metrics-server rollout..."
kubectl -n kube-system rollout status deploy/metrics-server --timeout=300s

echo "Checking APIService..."
kubectl wait \
  --for=condition=Available \
  apiservice/v1beta1.metrics.k8s.io \
  --timeout=180s
kubectl get apiservice v1beta1.metrics.k8s.io
