#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAEFIK_CHART_VERSION="41.0.0"

echo "Installing traefik ..."
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo update traefik

echo "Validating Traefik chart values against chart ${TRAEFIK_CHART_VERSION}..."
helm template traefik traefik/traefik \
  --namespace traefik \
  --version "$TRAEFIK_CHART_VERSION" \
  -f "$SCRIPT_DIR/install_traefik_custom_values.yaml" \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"="$my_aws_load_balancer_ssl_cert_arn" \
  >/dev/null

helm upgrade --install traefik traefik/traefik -n traefik \
  --create-namespace \
  --version "$TRAEFIK_CHART_VERSION" \
  -f "$SCRIPT_DIR/install_traefik_custom_values.yaml" \
  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"="$my_aws_load_balancer_ssl_cert_arn" \
  --wait \
  --timeout 10m \
  --cleanup-on-fail

echo "Waiting for traefik rollout..."
kubectl rollout status deployment/traefik -n traefik --timeout=10m

echo "Install PodDisruptionBudget for traefik..."
kubectl apply -f "$SCRIPT_DIR/traefik-pdb.yaml"

echo "Traefik service status:"
kubectl get service traefik -n traefik -o wide
