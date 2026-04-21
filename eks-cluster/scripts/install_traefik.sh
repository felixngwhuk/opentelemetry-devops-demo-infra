#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing traefik ..."
helm repo add traefik https://helm.traefik.io/traefik
helm repo update traefik

kubectl create namespace traefik
helm upgrade --install traefik traefik/traefik -n traefik \
  -f "$SCRIPT_DIR/install_traefik_custom_values.yaml"
#helm upgrade --install traefik traefik/traefik -n traefik \
#  --set ingressRoute.dashboard.enabled=true \
#  --set deployment.replicas=2 \
#  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
#  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=external \
#  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"=ip \
#  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-protocol"=http \
#  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-port"=traffic-port \
#  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-path"=/ping \
#  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-healthy-threshold"=3 \
#  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-unhealthy-threshold"=3 \
#  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-interval"=10 \
#  --set-string service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-attributes"=load_balancing.cross_zone.enabled=true

echo "Waiting for traefik rollout..."
kubectl rollout status deployment/traefik -n traefik

echo "Install PodDisruptionBudget for traefik..."
kubectl apply -f "$SCRIPT_DIR/traefik-pdb.yaml"