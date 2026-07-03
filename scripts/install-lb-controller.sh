#!/usr/bin/env bash
# install-lb-controller.sh
# Standalone script to install the AWS Load Balancer Controller into an EKS cluster.
# Required environment variables:
#   CLUSTER_NAME - name of the target EKS cluster
#   ROLE_ARN     - IRSA role ARN for the aws-load-balancer-controller service account

set -euo pipefail

APPLICATION_VERSION="${APPLICATION_VERSION:-v2.8.1}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
ROLE_ARN="${ROLE_ARN:-}"

if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "ERROR: CLUSTER_NAME environment variable is required" >&2
  exit 1
fi

if [[ -z "${ROLE_ARN}" ]]; then
  echo "ERROR: ROLE_ARN environment variable is required" >&2
  exit 1
fi

echo "Installing AWS Load Balancer Controller CRDs (application version ${APPLICATION_VERSION})..."
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=${APPLICATION_VERSION}"

echo "Adding EKS Helm repository..."
helm repo add eks https://aws.github.io/eks-charts || true

echo "Updating Helm repositories..."
helm repo update

echo "Installing AWS Load Balancer Controller Helm chart..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ROLE_ARN}"

echo "AWS Load Balancer Controller installation complete."
