#!/usr/bin/env bash
# install-eso.sh
# Installs External Secrets Operator (ESO) on EKS using Helm.
#
# Usage:
#   export ESO_VERSION="2.7.0"
#   ./install-eso.sh <eso-irsa-role-arn>
#
# The IRSA role ARN is output by the dev environment Terraform root module:
#   terraform -chdir=terraform/environments/dev output -raw secrets_eso_role_arn

set -euo pipefail

ESO_VERSION="${ESO_VERSION:-2.7.0}"
NAMESPACE="external-secrets"
RELEASE_NAME="external-secrets"
SA_NAME="external-secrets-sa"

ROLE_ARN="${1:-}"

if [ -z "$ROLE_ARN" ]; then
  echo "Usage: $0 <eso-irsa-role-arn>"
  echo "Example: $0 arn:aws:iam::123456789012:role/petclinic-dev-eso-role"
  exit 1
fi

if ! command -v helm &>/dev/null; then
  echo "helm CLI not found. Install from https://helm.sh/docs/intro/install/"
  exit 1
fi

if ! command -v kubectl &>/dev/null; then
  echo "kubectl not found. Install from https://kubernetes.io/docs/tasks/tools/"
  exit 1
fi

# Ensure the target namespace exists.
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Add the External Secrets Operator Helm repository.
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

# Install/upgrade ESO with the IRSA-enabled service account.
helm upgrade --install "$RELEASE_NAME" external-secrets/external-secrets \
  --namespace "$NAMESPACE" \
  --version "$ESO_VERSION" \
  --set installCRDs=true \
  --set serviceAccount.name="$SA_NAME" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ROLE_ARN"

echo "External Secrets Operator ${ESO_VERSION} installed/updated in namespace ${NAMESPACE}"
echo "ServiceAccount: ${SA_NAME}"
echo "IRSA Role ARN:  ${ROLE_ARN}"
