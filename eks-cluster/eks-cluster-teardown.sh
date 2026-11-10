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

delete_monitoring_storage() {
  local namespace=monitoring
  local prometheus=monitoring-kube-prometheus-prometheus
  local statefulset="prometheus-${prometheus}"
  local claim_template pvc pvc_json pv pod

  monitoring_volume_id=""
  claim_template="$(kubectl get statefulset "$statefulset" -n "$namespace" --ignore-not-found=true -o jsonpath='{.spec.volumeClaimTemplates[0].metadata.name}')"
  if [[ -z "$claim_template" ]]; then
    echo "Monitoring StatefulSet not found; skipping storage cleanup."
    return 0
  fi

  pvc="${claim_template}-${statefulset}-0"
  pvc_json="$(kubectl get pvc "$pvc" -n "$namespace" --ignore-not-found=true -o json)"
  pv="$(jq -r '.spec.volumeName // empty' <<<"$pvc_json")"
  if [[ -z "$pv" ]]; then
    # A previous attempt may have deleted the PVC while its PV is reclaiming.
    pv="$(kubectl get pv -o json | jq -r --arg pvc "$pvc" --arg ns "$namespace" '
      [.items[] | select(.spec.claimRef.name == $pvc and .spec.claimRef.namespace == $ns)]
      | if length > 1 then error("Multiple PVs reference the monitoring claim")
        else .[0].metadata.name // empty end')"
  fi
  if [[ -z "$pvc_json" && -z "$pv" ]]; then
    echo "Monitoring PVC/PV already absent; skipping storage cleanup."
    return 0
  fi
  if [[ -n "$pv" ]]; then
    monitoring_volume_id="$(kubectl get pv "$pv" -o jsonpath='{.spec.csi.volumeHandle}')"
  fi
  echo "Monitoring storage: PVC=$namespace/$pvc PV=$pv EBS=$monitoring_volume_id"

  kubectl patch prometheus "$prometheus" -n "$namespace" --type=merge -p '{"spec":{"replicas":0}}'
  pod="$(kubectl get pod "${statefulset}-0" -n "$namespace" --ignore-not-found=true -o name)"
  if [[ -n "$pod" ]]; then
    kubectl wait --for=delete "$pod" -n "$namespace" --timeout=10m
  fi
  kubectl delete pvc "$pvc" -n "$namespace" --ignore-not-found=true --wait=true --timeout=15m
  if [[ -n "$pv" ]]; then
    kubectl delete pv "$pv" --ignore-not-found=true --wait=true --timeout=15m
  fi
}

wait_monitoring_volume_deleted() {
  local attempt output

  if [[ -z "$monitoring_volume_id" ]]; then
    echo "No monitoring EBS volume ID captured; skipping AWS verification."
    return 0
  fi
  for ((attempt = 0; attempt < 18; attempt++)); do
    if output="$(aws ec2 describe-volumes --volume-ids "$monitoring_volume_id" --region "$my_aws_region_name" --output json 2>&1)"; then
      echo "EBS volume $monitoring_volume_id still exists; waiting for CSI reclamation."
    elif grep -Fq '(InvalidVolume.NotFound)' <<<"$output"; then
      echo "EBS volume $monitoring_volume_id is absent."
      return 0
    else
      echo "Could not verify EBS volume $monitoring_volume_id: $output" >&2
      return 1
    fi
    sleep 5
  done
  echo "Timed out after 90 seconds waiting for EBS volume $monitoring_volume_id; inspect CSI logs and volume attachments before retrying." >&2
  return 1
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

echo "========== Delete monitoring PVC/PV =========="
delete_monitoring_storage

echo "========== Wait for monitoring EBS volume deletion =========="
wait_monitoring_volume_deleted

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
