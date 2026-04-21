#!/usr/bin/env bash
set -euo pipefail

aws_account_id=$(aws sts get-caller-identity --query Account --output text)

#eksctl create addon --name aws-ebs-csi-driver --cluster $my_eks_cluster_name --service-account-role-arn "arn:aws:iam::${aws_account_id}:role/AmazonEKS_EBS_CSI_DriverRole" --force

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update aws-ebs-csi-driver

helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  -n kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa

echo "waiting for aws-load-balancer deployment and pods ready ..."
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=300s
echo "aws-load-balancer deployment and pods ready"

echo "waiting for ebs-csi-controller deployment and pods ready ..."
kubectl -n kube-system rollout status deploy/ebs-csi-controller --timeout=10m
echo "ebs-csi-controller deployment and pods ready"

echo "waiting for ebs-csi-node daemonset ..."
kubectl -n kube-system rollout status ds/ebs-csi-node --timeout=10m
echo "ebs-csi-node daemonset ready"
