#!/usr/bin/env bash

print_bootstrap_state() {
  echo
  echo "========== EKS bootstrap state =========="

  echo "--- Kubernetes context ---"
  kubectl config current-context || true

  echo "--- Namespaces ---"
  kubectl get namespaces || true

  echo "--- Helm releases ---"
  helm list --all-namespaces || true

  echo "--- IAM service accounts ---"
  kubectl -n kube-system get serviceaccount \
    aws-load-balancer-controller \
    ebs-csi-controller-sa \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}{end}' \
    || true

  echo "--- Relevant deployments ---"
  kubectl get deployments --all-namespaces || true

  echo "--- EBS CSI node DaemonSet ---"
  kubectl -n kube-system get daemonset ebs-csi-node -o wide || true

  echo "--- Traefik resources ---"
  kubectl -n traefik get deployment,service,pods -o wide || true

  echo "--- Argo CD resources ---"
  kubectl -n argocd get deployment,pods -o wide || true
}

print_failure_diagnostics() {
  local exit_code="$1"
  local failed_step="$2"

  trap - ERR

  echo
  echo "::error title=EKS bootstrap failed::Step '${failed_step}' failed with exit code ${exit_code}."
  print_bootstrap_state

  echo "--- Recent cluster events ---"
  kubectl get events --all-namespaces --sort-by=.lastTimestamp | tail -n 100 || true

  exit "$exit_code"
}

verify_service_account_role() {
  local namespace="$1"
  local service_account="$2"
  local expected_role_arn="$3"
  local actual_role_arn

  actual_role_arn="$(
    kubectl -n "$namespace" get serviceaccount "$service_account" \
      -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
  )"

  if [[ "$actual_role_arn" != "$expected_role_arn" ]]; then
    echo "ERROR: ${namespace}/${service_account} is annotated with '${actual_role_arn}', expected '${expected_role_arn}'." >&2
    return 1
  fi

  echo "Verified ${namespace}/${service_account} uses ${expected_role_arn}."
}
