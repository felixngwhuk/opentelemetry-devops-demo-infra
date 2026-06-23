#!/usr/bin/env bash
set -euo pipefail

issuer="$(
  aws eks describe-cluster \
    --name "$my_eks_cluster_name" \
    --query "cluster.identity.oidc.issuer" \
    --output text
)"
issuer_hostpath="${issuer#https://}"
aws_account_id="$(aws sts get-caller-identity --query Account --output text)"
oidc_arn="arn:aws:iam::${aws_account_id}:oidc-provider/${issuer_hostpath}"

if aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$oidc_arn" \
  >/dev/null 2>&1; then
  echo "IAM OIDC provider already exists: ${oidc_arn}"
else
  eksctl utils associate-iam-oidc-provider \
    --cluster "$my_eks_cluster_name" \
    --approve
fi

aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$oidc_arn" \
  >/dev/null
echo "Verified IAM OIDC provider: ${oidc_arn}"
