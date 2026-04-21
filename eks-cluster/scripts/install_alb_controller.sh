#!/usr/bin/env bash
set -euo pipefail

helm repo add eks https://aws.github.io/eks-charts

helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$my_eks_cluster_name \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$my_aws_region_name \
  --set vpcId=$eks_cluster_vpc_id

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
