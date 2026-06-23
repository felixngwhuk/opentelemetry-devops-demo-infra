#!/usr/bin/env bash
set -euo pipefail

AWS_EBS_CSI_DRIVER_CHART_VERSION="2.62.0"

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver --force-update
helm repo update aws-ebs-csi-driver

echo "Validating AWS EBS CSI Driver chart values against chart ${AWS_EBS_CSI_DRIVER_CHART_VERSION}..."
helm template aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --version "$AWS_EBS_CSI_DRIVER_CHART_VERSION" \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa \
  >/dev/null

helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  -n kube-system \
  --version "$AWS_EBS_CSI_DRIVER_CHART_VERSION" \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa \
  --wait \
  --timeout 10m \
  --cleanup-on-fail

echo "waiting for ebs-csi-controller deployment and pods ready ..."
kubectl -n kube-system rollout status deploy/ebs-csi-controller --timeout=10m
echo "ebs-csi-controller deployment and pods ready"

echo "waiting for ebs-csi-node daemonset ..."
kubectl -n kube-system rollout status ds/ebs-csi-node --timeout=10m
echo "ebs-csi-node daemonset ready"
