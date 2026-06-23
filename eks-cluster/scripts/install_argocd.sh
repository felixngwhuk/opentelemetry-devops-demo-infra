#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGO_CD_CHART_VERSION="9.7.0"

echo "Installing Argo CD ..."

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

echo "Validating Argo CD chart values against chart ${ARGO_CD_CHART_VERSION}..."
helm template argocd argo/argo-cd \
  --namespace argocd \
  --version "$ARGO_CD_CHART_VERSION" \
  -f "$SCRIPT_DIR/install_argocd_custom_values.yaml" \
  >/dev/null

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  --version "$ARGO_CD_CHART_VERSION" \
  -f "$SCRIPT_DIR/install_argocd_custom_values.yaml" \
  --wait \
  --timeout 10m \
  --cleanup-on-fail

echo "Waiting for Argo CD rollout ..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=10m

echo "Install bootstrap Argo CD root application ..."
kubectl apply -f "${my_argocd_bootstrap_repo_url%/}/refs/heads/main/bootstrap/root-application.yaml"
kubectl get application gitops-root-application -n argocd
