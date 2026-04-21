#!/usr/bin/env bash
set -euo pipefail

oidc_id=$(aws eks describe-cluster --name $my_eks_cluster_name --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

eksctl utils associate-iam-oidc-provider --cluster $my_eks_cluster_name --approve
