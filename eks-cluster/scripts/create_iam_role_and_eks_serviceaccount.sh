#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap_helpers.sh"

aws_account_id="$(aws sts get-caller-identity --query Account --output text)"
alb_controller_role_arn="arn:aws:iam::${aws_account_id}:role/AmazonEKSLoadBalancerControllerRole"
ebs_csi_role_arn="arn:aws:iam::${aws_account_id}:role/AmazonEKS_EBS_CSI_DriverRole"

eksctl create iamserviceaccount \
  --cluster="$my_eks_cluster_name" \
  --namespace="kube-system" \
  --name="aws-load-balancer-controller" \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn "arn:aws:iam::${aws_account_id}:policy/AWSLoadBalancerControllerIAMPolicy" \
  --override-existing-serviceaccounts \
  --approve

eksctl create iamserviceaccount \
  --cluster="$my_eks_cluster_name" \
  --namespace="kube-system" \
  --name="ebs-csi-controller-sa" \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --override-existing-serviceaccounts \
  --approve

verify_service_account_role \
  "kube-system" \
  "aws-load-balancer-controller" \
  "$alb_controller_role_arn"

verify_service_account_role \
  "kube-system" \
  "ebs-csi-controller-sa" \
  "$ebs_csi_role_arn"
