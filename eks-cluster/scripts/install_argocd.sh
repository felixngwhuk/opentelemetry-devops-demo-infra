#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Argo CD ..."

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f "$SCRIPT_DIR/install_argocd_custom_values.yaml"

echo "Waiting for Argo CD rollout ..."
kubectl rollout status deployment/argocd-server -n argocd

echo "Install bootstrap Argo CD root application ..."
kubectl apply -f https://raw.githubusercontent.com/felixngwhuk/opentelemetry-devops-demo-gitops/refs/heads/main/bootstrap/root-application.yaml
