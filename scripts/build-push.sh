#!/bin/bash

# Build and Push Docker Images to ECR
# Builds all 8 Petclinic microservices with Maven, then builds ARM64 Docker images and pushes to ECR
# Usage: ./build-push.sh [tag] [region]

# Variables
TAG="${1:-$(cd /home/ubuntu/spring-petclinic/spring-petclinic-microservices && git rev-parse --short HEAD)}"
REGION="${2:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

SERVICES=(
  "spring-petclinic-config-server:config-server:8888"
  "spring-petclinic-discovery-server:discovery-server:8761"
  "spring-petclinic-api-gateway:api-gateway:8080"
  "spring-petclinic-customers-service:customers-service:8081"
  "spring-petclinic-visits-service:visits-service:8082"
  "spring-petclinic-vets-service:vets-service:8083"
  "spring-petclinic-genai-service:genai-service:8084"
  "spring-petclinic-admin-server:admin-server:9090"
)

MICROSERVICES_DIR="/home/ubuntu/spring-petclinic/spring-petclinic-microservices"

# Function to build a service
build_service() {
  local service_name="$1"
  local service_port="$2"
  local ecr_service_name="$3"
  
  echo "============================="
  echo "Building: ${service_name}"
  echo "============================="
  
  # Build with Maven first (JAR creation)
  echo "Building JAR with Maven..."
  cd "${MICROSERVICES_DIR}/${service_name}" || {
    echo "Error: Could not find service directory: ${service_name}"
    return 1
  }
  
  mvn clean package -DskipTests || {
    echo "Error: Maven build failed for ${service_name}"
    return 1
  }
  
   # Copy JAR to docker directory for build context
   cp "${MICROSERVICES_DIR}/${service_name}/target/${service_name}-4.0.1.jar" "${MICROSERVICES_DIR}/docker/${service_name}-4.0.1.jar" || {
     echo "Error: Could not copy JAR file for ${service_name}"
     return 1
   }
   

   
   # Build Docker image (ARM64 platform via buildx directly pushing to ECR)
   echo "Building Docker image with buildx and pushing directly..."
   docker buildx build \
     --platform linux/arm64 \
     --push \
     --tag "${ECR_REGISTRY}/petclinic-dev/${ecr_service_name}:${TAG}" \
     --file "${MICROSERVICES_DIR}/docker/Dockerfile" \
     --build-arg ARTIFACT_NAME="${service_name}-4.0.1" \
     --build-arg EXPOSED_PORT="${service_port}" \
     --provenance=false \
     "${MICROSERVICES_DIR}/docker" || {
     echo "Error: Docker build and push failed for ${service_name}"
     return 1
   }
   
   # Clean up copied JAR
   rm -f "${MICROSERVICES_DIR}/docker/${service_name}-4.0.1.jar"
   
   echo "✅ Successfully built and pushed ${service_name}"
}

echo "Starting build-push process for Petclinic services"
echo "Tag: ${TAG}"
echo "Region: ${REGION}"
echo "ECR Registry: ${ECR_REGISTRY}"
echo ""

# Login to ECR first
ECR_LOGIN_SCRIPT="$(dirname "$0")/ecr-login.sh"
"${ECR_LOGIN_SCRIPT}" --region "${REGION}" || {
  echo "Error: ECR login failed"
  exit 1
}

# Build all services
for service in "${SERVICES[@]}"; do
  IFS=":" read -r service_name ecr_service_name service_port <<< "$service"
  build_service "$service_name" "$service_port" "$ecr_service_name" || exit 1
done

echo ""
echo "🎉 All services built and pushed successfully!"
echo "Images are tagged with: ${TAG}"
echo "Images are available at: ${ECR_REGISTRY}/petclinic-dev/*"

exit 0
