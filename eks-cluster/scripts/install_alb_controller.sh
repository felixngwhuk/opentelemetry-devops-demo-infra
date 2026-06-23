#!/usr/bin/env bash
set -euo pipefail

AWS_LOAD_BALANCER_CONTROLLER_CHART_VERSION="3.4.0"

eks_cluster_vpc_id="$(
  aws eks describe-cluster \
    --name "$my_eks_cluster_name" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text
)"

helm repo add eks https://aws.github.io/eks-charts --force-update
helm repo update eks

echo "Validating AWS Load Balancer Controller chart values against chart ${AWS_LOAD_BALANCER_CONTROLLER_CHART_VERSION}..."
helm template aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "$AWS_LOAD_BALANCER_CONTROLLER_CHART_VERSION" \
  --set "clusterName=$my_eks_cluster_name" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "region=$my_aws_region_name" \
  --set "vpcId=$eks_cluster_vpc_id" \
  >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --version "$AWS_LOAD_BALANCER_CONTROLLER_CHART_VERSION" \
  --set "clusterName=$my_eks_cluster_name" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "region=$my_aws_region_name" \
  --set "vpcId=$eks_cluster_vpc_id" \
  --wait \
  --timeout 10m \
  --cleanup-on-fail

echo "waiting for aws-load-balancer deployment and pods ready ..."
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=300s
echo "aws-load-balancer deployment and pods are ready"

endtime=$((SECONDS+300))
until kubectl -n kube-system get endpointslice \
  -l kubernetes.io/service-name=aws-load-balancer-webhook-service \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[*]}{"\n"}{end}' 2>/dev/null \
  | grep -qE '.'; do
  if (( SECONDS > endtime )); then
    echo "ERROR: webhook EndpointSlice still has no endpoints after 300s"
    kubectl -n kube-system get pods -o wide | grep -i load-balancer || true
    kubectl -n kube-system get endpointslice -l kubernetes.io/service-name=aws-load-balancer-webhook-service -o wide || true
    exit 1
  fi
  echo "waiting for aws-load-balancer-webhook-service EndpointSlice endpoints..."
  sleep 3
done

echo "webhook EndpointSlice endpoints ready"
