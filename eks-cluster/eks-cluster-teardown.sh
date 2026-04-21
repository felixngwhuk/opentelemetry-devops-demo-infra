#!/usr/bin/env bash
set -euo pipefail

cluster_name="my-eks-cluster"

echo "========== uninstall traefik  ========="
helm uninstall traefik -n traefik
kubectl wait --for=delete pod --all -n traefik --timeout=90s
kubectl delete namespace traefik

echo "========== uninstall aws-load-balancer-controller  ========="
helm uninstall aws-load-balancer-controller -n kube-system

echo "========== uninstall aws-load-balancer-controller  ========="
helm uninstall aws-ebs-csi-driver -n kube-system

echo "========== Delete IAM Role on AWS ========="
eksctl delete iamserviceaccount \
  --cluster="$cluster_name" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller

echo "========== Delete ServiceAccount on EKS cluster ========="
eksctl delete iamserviceaccount \
  --cluster="$cluster_name" \
  --namespace=kube-system \
  --name=ebs-csi-controller-sa

echo "========== Delete the IAM identity provider association  ========="
issuer=$(aws eks describe-cluster --name "$cluster_name" --query "cluster.identity.oidc.issuer" --output text)
echo "$issuer"

issuer_hostpath="${issuer#https://}"   # strip https://
oidc_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/${issuer_hostpath}"
echo "$oidc_arn"

aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$oidc_arn"