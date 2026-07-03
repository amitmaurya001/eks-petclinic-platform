#!/bin/bash
# validate-helm.sh — Automated Helm validation for all Petclinic services
# Runs: helm lint + helm template + kubectl apply --dry-run=client
# for each service with both dev and prod values

set -e

CHART_DIR="$(dirname "$0")/../helm/petclinic-service"
VALUES_DIR="$(dirname "$0")/../helm-values"

SERVICES=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)

ENVIRONMENTS=(dev prod)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

fail_count=0

echo "=========================================="
echo " Helm Validation — Petclinic Services"
echo "=========================================="
echo ""

# Step 1: Helm Lint
echo "--- Step 1: Helm Lint ---"
cd "$(dirname "$0")/../"
helm lint "$CHART_DIR" || {
  echo -e "${RED}Helm lint failed${NC}"
  exit 1
}

# Step 2: Helm Template for each service in each environment
echo ""
echo "--- Step 2: Helm Template (Rendered YAML) ---"

for service in "${SERVICES[@]}"; do
  for env in "${ENVIRONMENTS[@]}"; do
    echo ""
    echo "Rendering: $service / $env"

    output_dir="/tmp/helm-validate/${service}-${env}"
    mkdir -p "$output_dir"

    helm template "$service" "$CHART_DIR" \
      -f "$VALUES_DIR/${service}.yaml" \
      -f "$VALUES_DIR/${env}.yaml" \
      > "$output_dir/manifest.yaml" 2>&1 || {
      echo -e "${RED}  ✗ $service / $env: template failed${NC}"
      fail_count=$((fail_count + 1))
      continue
    }
    echo -e "${GREEN}  ✓ $service / $env: template succeeded${NC}"
  done
done

# Step 3: kubectl apply --dry-run=client
echo ""
echo "--- Step 3: kubectl apply --dry-run=client ---"

for service in "${SERVICES[@]}"; do
  for env in "${ENVIRONMENTS[@]}"; do
    output_dir="/tmp/helm-validate/${service}-${env}"
    manifest="$output_dir/manifest.yaml"

    if [[ -f "$manifest" ]]; then
      # Split multi-resource YAML into individual files
      csplit -z -f "$output_dir/resource-" "$manifest" '/^---$/' '{*}' 2>/dev/null || true

      # Remove empty chunks
      find "$output_dir" -name 'resource-*' -size 0 -delete 2>/dev/null || true

      for resource in "$output_dir"/resource-*; do
        echo "  Validating: $service / $env — $resource"
        kubectl apply --dry-run=client -f "$resource" 2>/dev/null || {
          echo -e "${RED}  ✗ $service / $env ($resource): validation failed${NC}"
          fail_count=$((fail_count + 1))
        }
      done
    fi
  done
done

# Summary
echo ""
echo "=========================================="
if [[ $fail_count -eq 0 ]]; then
  echo -e "${GREEN}All validations passed${NC}"
else
  echo -e "${RED}$fail_count failure(s) found${NC}"
fi
echo "=========================================="

# Cleanup
rm -rf /tmp/helm-validate

exit $fail_count