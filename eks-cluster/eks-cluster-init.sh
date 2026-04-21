#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"

# Send stdout+stderr to screen and to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging to: $LOG_FILE"

export my_eks_cluster_name=my-eks-cluster
export my_aws_region_name=$(aws configure get region)
export eks_cluster_vpc_id=$(aws eks describe-cluster  --name "$my_eks_cluster_name"  --query "cluster.resourcesVpcConfig.vpcId"  --output text)


echo "====== Running refresh_eks_cluster_connection.sh ======"
./scripts/refresh_eks_cluster_connection.sh
echo "====== Running associate-iam-oidc-provider.sh ======"
./scripts/associate-iam-oidc-provider.sh
echo "====== Running create_iam_role_and_eks_serviceaccount.sh ======"
./scripts/create_iam_role_and_eks_serviceaccount.sh
echo "====== Running install_alb_controller.sh ======"
./scripts/install_alb_controller.sh
echo "====== Running install_ebs_csi_driver.sh ======"
./scripts/install_ebs_csi_driver.sh
echo "====== Running install_metrics_server.sh ======"
./scripts/install_metrics_server.sh
echo "====== Running install_traefik.sh ======"
./scripts/install_traefik.sh
echo "====== Running install_argocd.sh ======"
./scripts/install_argocd.sh
