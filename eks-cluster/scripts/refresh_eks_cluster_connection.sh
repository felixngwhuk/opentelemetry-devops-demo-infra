#!/usr/bin/env bash
set -euo pipefail

aws eks update-kubeconfig --region $my_aws_region_name --name $my_eks_cluster_name
kubectl config get-contexts
kubectl config current-context
kubectl cluster-info
