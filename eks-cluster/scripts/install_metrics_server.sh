#!/usr/bin/env bash
set -euo pipefail

echo "Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "Waiting for deployment to appear..."
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s || true

echo "Adding EKS-compatible args..."
kubectl -n kube-system patch deployment metrics-server \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP"}
  ]' || true

echo "Waiting for metrics-server rollout..."
kubectl -n kube-system rollout status deploy/metrics-server --timeout=300s

echo "Checking APIService..."
kubectl get apiservice | grep metrics
