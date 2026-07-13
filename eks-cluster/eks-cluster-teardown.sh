#!/usr/bin/env bash
set -euo pipefail

export my_eks_cluster_name="${my_eks_cluster_name:-my-eks-cluster}"
export my_aws_region_name="${my_aws_region_name:-$(aws configure get region)}"

cluster_exists() {
  local output
  local status

  set +e
  output="$(
    aws eks describe-cluster \
      --name "$my_eks_cluster_name" \
      --region "$my_aws_region_name" \
      2>&1
  )"
  status="$?"
  set -e

  if [[ "$status" -eq 0 ]]; then
    return 0
  fi

  if grep -q "ResourceNotFoundException" <<<"$output"; then
    return 1
  fi

  echo "$output" >&2
  return "$status"
}

helm_release_exists() {
  local release_name="$1"
  local namespace="$2"

  helm status "$release_name" -n "$namespace" >/dev/null 2>&1
}

uninstall_helm_release() {
  local release_name="$1"
  local namespace="$2"

  if helm_release_exists "$release_name" "$namespace"; then
    echo "Uninstalling Helm release ${namespace}/${release_name} ..."
    helm uninstall "$release_name" -n "$namespace"
  else
    echo "Helm release ${namespace}/${release_name} not found; skipping."
  fi
}

namespace_exists() {
  local namespace="$1"

  kubectl get namespace "$namespace" >/dev/null 2>&1
}

delete_iam_service_account_if_exists() {
  local namespace="$1"
  local service_account="$2"
  local output

  echo "Checking IAM service account ${namespace}/${service_account} ..."
  output="$(
    eksctl get iamserviceaccount \
      --cluster="$my_eks_cluster_name" \
      --namespace="$namespace" \
      --name="$service_account" \
      --output=json
  )"

  if ! jq -e 'type == "array"' <<<"$output" >/dev/null; then
    echo "Invalid IAM service account JSON output." >&2
    return 1
  fi

  if jq -e 'length > 0' <<<"$output" >/dev/null; then
    echo "Deleting IAM service account ${namespace}/${service_account} ..."
    eksctl delete iamserviceaccount \
      --cluster="$my_eks_cluster_name" \
      --namespace="$namespace" \
      --name="$service_account"
  else
    echo "IAM service account ${namespace}/${service_account} already absent; skipping."
  fi
}

delete_oidc_provider_if_exists() {
  local issuer
  local issuer_hostpath
  local account_id
  local oidc_arn

  issuer="$(
    aws eks describe-cluster \
      --name "$my_eks_cluster_name" \
      --region "$my_aws_region_name" \
      --query "cluster.identity.oidc.issuer" \
      --output text
  )"

  echo "$issuer"

  issuer_hostpath="${issuer#https://}"
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  oidc_arn="arn:aws:iam::${account_id}:oidc-provider/${issuer_hostpath}"

  echo "$oidc_arn"

  if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$oidc_arn" >/dev/null 2>&1; then
    aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$oidc_arn"
  else
    echo "OIDC provider already absent; continuing."
  fi
}

cluster_status=0
cluster_exists || cluster_status="$?"

if [[ "$cluster_status" -eq 1 ]]; then
  echo "EKS cluster '$my_eks_cluster_name' not found in '$my_aws_region_name'; nothing to tear down."
  exit 0
elif [[ "$cluster_status" -ne 0 ]]; then
  exit "$cluster_status"
fi

echo "====== Running refresh_eks_cluster_connection.sh ======"
./scripts/refresh_eks_cluster_connection.sh

echo "========== uninstall traefik  ========="
uninstall_helm_release traefik traefik
if namespace_exists traefik; then
  if kubectl -n traefik get pods --no-headers 2>/dev/null | grep -q .; then
    kubectl wait --for=delete pod --all -n traefik --timeout=90s || true
  else
    echo "No Traefik pods found; skipping pod deletion wait."
  fi
fi
kubectl delete namespace traefik --ignore-not-found=true

echo "========== uninstall aws-load-balancer-controller  ========="
uninstall_helm_release aws-load-balancer-controller kube-system

echo "========== uninstall aws-ebs-csi-driver  ========="
uninstall_helm_release aws-ebs-csi-driver kube-system

echo "========== Delete IAM Role on AWS ========="
delete_iam_service_account_if_exists kube-system aws-load-balancer-controller

echo "========== Delete ServiceAccount on EKS cluster ========="
delete_iam_service_account_if_exists kube-system ebs-csi-controller-sa

echo "========== Delete the IAM identity provider association  ========="
delete_oidc_provider_if_exists
