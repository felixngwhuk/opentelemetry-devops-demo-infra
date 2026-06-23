#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/bootstrap_helpers.sh"

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"

# Send stdout+stderr to screen and to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging to: $LOG_FILE"

export my_eks_cluster_name="${my_eks_cluster_name:-my-eks-cluster}"
export my_aws_region_name="${my_aws_region_name:-$(aws configure get region)}"
export my_aws_load_balancer_ssl_cert_arn="${my_aws_load_balancer_ssl_cert_arn:-arn:aws:acm:eu-west-2:022029981383:certificate/c9403836-0ab0-4bb5-b504-6f91feabb6f9}"
export my_argocd_bootstrap_repo_url="${my_argocd_bootstrap_repo_url:-https://raw.githubusercontent.com/felixngwhuk/opentelemetry-devops-demo-gitops}"

CURRENT_BOOTSTRAP_STEP="initialization"
trap 'print_failure_diagnostics "$?" "$CURRENT_BOOTSTRAP_STEP"' ERR

run_bootstrap_step() {
  local step_name="$1"
  local script_path="$2"

  CURRENT_BOOTSTRAP_STEP="$step_name"
  echo "====== Running ${script_path##*/} ======"
  "$script_path"
  echo "====== Completed ${step_name} ======"
}

run_bootstrap_step "EKS connection refresh" "$SCRIPT_DIR/scripts/refresh_eks_cluster_connection.sh"

CURRENT_BOOTSTRAP_STEP="pre-installation diagnostics"
print_bootstrap_state

run_bootstrap_step "IAM OIDC provider" "$SCRIPT_DIR/scripts/associate-iam-oidc-provider.sh"
run_bootstrap_step "IAM service accounts" "$SCRIPT_DIR/scripts/create_iam_role_and_eks_serviceaccount.sh"
run_bootstrap_step "AWS Load Balancer Controller" "$SCRIPT_DIR/scripts/install_alb_controller.sh"
run_bootstrap_step "AWS EBS CSI Driver" "$SCRIPT_DIR/scripts/install_ebs_csi_driver.sh"
run_bootstrap_step "metrics-server" "$SCRIPT_DIR/scripts/install_metrics_server.sh"
run_bootstrap_step "Traefik" "$SCRIPT_DIR/scripts/install_traefik.sh"
run_bootstrap_step "Argo CD" "$SCRIPT_DIR/scripts/install_argocd.sh"

CURRENT_BOOTSTRAP_STEP="final verification"
print_bootstrap_state
echo "EKS cluster bootstrap completed successfully."
