# Deployment Runbook — Spring Petclinic Microservices

> **Purpose:** Step-by-step guide for deploying all 8 microservices to the Kubernetes cluster. Covers initial deployment (via `kubectl apply` / `kustomize`), verification of each service, and ongoing operations.  
> **Audience:** Platform engineering team, student developers  
> **Prerequisites:** EKS cluster (`petclinic-dev` / `petclinic-prod`), ECR repos with images pushed, valid kubeconfig, `kubectl` and `helm` CLI tools installed

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Deployment Order (Startup Chain)](#2-deployment-order-startup-chain)
3. [Step 1 — Namespaces](#3-step-1--namespaces)
4. [Step 2 — External Secrets Operator (ESO)](#4-step-2--external-secrets-operator-eso)
5. [Step 3 — Config Server](#5-step-3--config-server)
6. [Step 4 — Discovery Server (Eureka)](#6-step-4--discovery-server-eureka)
7. [Step 5 — Domain Services (customers, visits, vets)](#7-step-5--domain-services-customers-visits-vets)
8. [Step 6 — API Gateway](#8-step-6--api-gateway)
9. [Step 7 — GenAI Service](#9-step-7--genai-service)
10. [Step 8 — Admin Server](#10-step-8--admin-server)
11. [Verification Checklist](#11-verification-checklist)
12. [Day-2 Operations](#12-day-2-operations)
13. [Placeholder replacement checklist](#13-placeholder-replacement-checklist)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

### 1.1 Cluster Access

```bash
# Verify cluster is reachable
kubectl cluster-info
# Expected output: Kubernetes control plane is running at https://{eks-endpoint}

# Verify nodes are Ready
kubectl get nodes
# Expected: 2 nodes, both STATUS=Ready

# Verify kubeconfig context
kubectl config current-context
# Expected: arn:aws:eks:us-east-1:{account}:cluster/petclinic-dev
```

### 1.2 Verify Images in ECR

```bash
# List images in each ECR repo (dev)
aws ecr describe-images --repository-name petclinic-dev/config-server --region us-east-1 --query 'imageDetails[].imageTags'
# Repeat for all 8 services

# Auth test
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {account}.dkr.ecr.us-east-1.amazonaws.com
```

### 1.3 Tools

```bash
# Verify required CLIs
kubectl version --client     # >= 1.28
helm version                 # >= 3.12
kustomize version            # built into kubectl
```

---

## 2. Deployment Order (Startup Chain)

Services **must** be deployed in this exact order due to the dependency chain:

```
1. Namespaces        (infrastructure — create before anything)
2. External Secrets  (must exist before services can read secrets)
3. Config Server      (all services depend on this for config)
4. Discovery Server   (all services depend on this for registration)
5. Domain Services (any order — init containers handle dependencies):
   ├── customers-service  (port 8081, MySQL)
   ├── visits-service      (port 8082, MySQL)
   └── vets-service        (port 8083, MySQL)
6. API Gateway        (port 8080 — public entry point)
7. GenAI Service      (port 8084 — optional dependency)
8. Admin Server       (port 9090 — monitoring, last to start)
```

**Why this order:** Each service has `initContainers` that block until Config Server and Discovery Server are healthy. If you deploy domain services before Config Server, their pods stay `Init:0/1` forever. If you deploy before Discovery Server, they register but never find peers.

---

## 3. Step 1 — Namespaces

### What to do

```bash
cd /home/ubuntu/spring-petclinic/petclinic-platform

# Apply namespaces directly
kubectl apply -f k8s/base/namespaces/namespaces.yaml
```

### What to verify

```bash
kubectl get ns petclinic-dev petclinic-prod
# Expected output:
# NAME              STATUS   AGE
# petclinic-dev     Active   1m
# petclinic-prod    Active   1m

kubectl get ns petclinic-dev -o jsonpath='{.metadata.labels}'
# Expected: {"app.kubernetes.io/part-of":"petclinic","app.kubernetes.io/managed-by":"Helm",...}
```

### Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `Error from server (AlreadyExists)` | Already created | `kubectl get ns` to confirm; this is safe |
| Namespace stuck `Terminating` | Resources still in it | `kubectl get all -n {ns}` to find orphans, delete them |

---

## 4. Step 2 — External Secrets Operator (ESO)

### What to do

```bash
# 1. Install ESO CRDs and controller (if not already in cluster)
kubectl apply -f https://github.com/external-secrets/external-secrets/releases/download/v0.9.13/external-secrets.yaml

# 2. Create ClusterSecretStore (AWS Secrets Manager provider)
kubectl apply -f k8s/base/external-secrets/

# 3. Verify the operator pod is running
kubectl get pods -n external-secrets
# Expected: external-secrets-xxx (1/1 Running)
```

### What to verify

```bash
kubectl get clustersecretstore -o wide
# Expected: aws-secrets-manager (VALID, age)

# Test secret resolution
kubectl get externalsecret -n petclinic-dev
# If rds-credentials shows status=Ready, ESO is working
```

### Prerequisites (before this step)

Before ESO can work, the following must exist:

| Dependency | Created by | Check |
|-----------|-----------|-------|
| AWS Secrets Manager secret `petclinic/{env}/rds-credentials` | Terraform (PETPLAT-23) | `aws secretsmanager list-secrets --region us-east-1` |
| IRSA role for ESO | Terraform (PETPLAT-35) | `kubectl get sa -n external-secrets` |

---

## 5. Step 3 — Config Server

### What to do

```bash
cd /home/ubuntu/spring-petclinic/petclinic-platform

# 1. Apply using Kustomize (dev overlay)
kubectl apply -k k8s/base/config-server/

# OR apply individual files
kubectl apply -f k8s/base/config-server/deployment.yaml \
             -f k8s/base/config-server/service.yaml \
             -f k8s/base/config-server/configmap.yaml \
             -f k8s/base/config-server/serviceaccount.yaml
```

### What to verify

```bash
# 1. Pod is running
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=config-server
# Expected: config-server-xxx (1/1 Running)

# 2. Health endpoint responds
kubectl port-forward pod/config-server-xxx 8888:8888 &
curl http://localhost:8888/actuator/health
# Expected: {"status":"UP"}

# 3. Config server serves config
curl http://localhost:8888/config-server/default/docker
# Expected: HTTP 200, JSON response with property sources
```

### Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| `CrashLoopBackOff` | `kubectl logs -n petclinic-dev deploy/config-server` | Check `SPRING_PROFILES_ACTIVE` is `docker` |
| `Init:0/1` | `kubectl describe pod -n petclinic-dev` | Config server has no init containers — this is normal |
| `Pending` / `Unschedulable` | `kubectl describe pod` | Nodes may not have enough resources; check `kubectl top nodes` |
| ImagePullErr (BackOff) | `kubectl describe pod` | ECR image tag doesn't exist; push image first |

### Verification commands (automated)

```bash
# Script to verify Config Server is healthy
POD=$(kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=config-server -o jsonpath='{.items[0].metadata.name}')
kubectl wait --for=condition=Ready pod/$POD -n petclinic-dev --timeout=120s
kubectl exec $POD -n petclinic-dev -- wget -qO- http://localhost:8888/actuator/health
```

---

## 6. Step 4 — Discovery Server (Eureka)

### What to do

```bash
cd /home/ubuntu/spring-petclinic/petclinic-platform

kubectl apply -k k8s/base/discovery-server/
# OR
kubectl apply -f k8s/base/discovery-server/deployment.yaml \
             -f k8s/base/discovery-server/service.yaml \
             -f k8s/base/discovery-server/configmap.yaml \
             -f k8s/base/discovery-server/serviceaccount.yaml
```

### What to verify

```bash
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=discovery-server
# Expected: 1/1 Running

# Port-forward and check Eureka dashboard
kubectl port-forward pod/discovery-server-xxx 8761:8761
curl http://localhost:8761/actuator/health
# Expected: {"status":"UP"}

# Eureka registered instances
curl http://localhost:8761/eureka/apps
# Expected: XML response with <applications><instances> — at minimum config-server should be registered
```

### Key detail

Discovery Server has an **init container** (`wait-for-config-server`) that blocks until `http://config-server:8888/actuator/health` returns UP. This means:

- Pod stays `Init:0/1` while Config Server is down
- Pod transitions to `Running` as soon as Config Server is healthy
- Total wait time: Config Server boot (~30s) + init check (~5s) = ~35s

### Verification commands

```bash
# Wait for init container to finish
kubectl wait --for=condition=Initialized pod -l app.kubernetes.io/name=discovery-server -n petclinic-dev --timeout=180s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=discovery-server -n petclinic-dev --timeout=120s

# Verify registration
kubectl exec deploy/discovery-server -n petclinic-dev -- wget -qO- http://localhost:8761/eureka/apps
# Expected: applications XML containing config-server as registered instance
```

---

## 7. Step 5 — Domain Services (customers, visits, vets)

### What to do

These three services require MySQL RDS. Deploy them in any order — their init containers handle the dependency chain.

```bash
cd /home/ubuntu/spring-petclinic/petclinic-platform

# Deploy all three
kubectl apply -k k8s/base/customers-service/
kubectl apply -k k8s/base/visits-service/
kubectl apply -k k8s/base/vets-service/
```

### What to verify

```bash
# All three pods
kubectl get pods -n petclinic-dev -l app.kubernetes.io/part-of=petclinic
# Expected: 3 pods, all 1/1 Running

# Per-service health
kubectl port-forward deploy/customers-service -n petclinic-dev 8081:8081 &
curl http://localhost:8081/actuator/health
# Expected: {"status":"UP"}

kubectl port-forward deploy/visits-service -n petclinic-dev 8082:8082 &
curl http://localhost:8082/actuator/health
# Expected: {"status":"UP"}

kubectl port-forward deploy/vets-service -n petclinic-dev 8083:8083 &
curl http://localhost:8083/actuator/health
# Expected: {"status":"UP"}
```

### Key differences from non-DB services

| Aspect | customers/visits/vets | config/discovery |
|-------|----------------------|-------------------|
| `SPRING_PROFILES_ACTIVE` | `docker,mysql` | `docker` |
| `SPRING_DATASOURCE_URL` | `jdbc:mysql://{rds-endpoint}:3306/petclinic` | Not set |
| RDS credentials | `envFrom: secretRef: rds-credentials` | No secret ref |
| Init containers | 2 (`wait-for-config-server` + `wait-for-discovery-server`) | 1 (config only) |

### RDS connection verification

```bash
# Port-forward and test DB connection
kubectl exec deploy/customers-service -n petclinic-dev -- \
  wget -qO- http://localhost:8081/actuator/health
# Look for: "db" : { "status" : "UP" } in the response

# Custom health endpoint includes DB check
kubectl exec deploy/customers-service -n petclinic-dev -- \
  curl -s http://localhost:8081/actuator/health | grep -q '"status":"UP"'
```

---

## 8. Step 6 — API Gateway

### What to do

```bash
cd /home/ubuntu/spring-petclinic/petclinic-platform

kubectl apply -k k8s/base/api-gateway/
# OR
kubectl apply -f k8s/base/api-gateway/deployment.yaml \
             -f k8s/base/api-gateway/service.yaml \
             -f k8s/base/api-gateway/configmap.yaml \
             -f k8s/base/api-gateway/serviceaccount.yaml
```

### What to verify

```bash
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=api-gateway
# Expected: 1/1 Running

kubectl port-forward deploy/api-gateway -n petclinic-dev 8080:8080 &
curl http://localhost:8080/actuator/health
# Expected: {"status":"UP"}

# Test routing to domain services via gateway
curl http://localhost:8080/api/customer/owners
# Expected: HTTP 200, JSON array of owners

curl http://localhost:8080/api/vet/vets
# Expected: HTTP 200, JSON array of vets

curl http://localhost:8080/api/visit/visits
# Expected: HTTP 200, JSON array of visits
```

### Resource note

API Gateway uses **higher CPU** than other services:

| Resource | api-gateway | Other services |
|---------|-------------|----------------|
| CPU request | 200m | 100m |
| CPU limit | 1000m | 500m |
| Memory limit | 512Mi | 512Mi |

This is because the gateway handles **all incoming traffic** and performs routing + circuit breaking.

---

## 9. Step 7 — GenAI Service

### What to do

```bash
cd /home/ubuntu/spring-petclinic/petclinic-platform

kubectl apply -k k8s/base/genai-service/
```

### What to verify

```bash
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=genai-service
# Expected: 1/1 Running

kubectl port-forward deploy/genai-service -n petclinic-dev 8084:8084 &
curl http://localhost:8084/actuator/health
# Expected: {"status":"UP"}
```

### Secret dependency

GenAI service requires `OPENAI_API_KEY` from a K8s secret. Before deploying:

```bash
# Verify the secret exists (created by ESO)
kubectl get secret openai-api-key -n petclinic-dev
# Expected: NAME=openai-api-key, TYPE=Opaque

# If not present, the service will start with
# OPENAI_API_KEY=default and log a warning
kubectl logs deploy/genai-service -n petclinic-dev | grep -i "openai"
# Expected: "OPENAI_API_KEY is 'default', using demo key"
```

---

## 10. Step 8 — Admin Server

### What to do

```bash
cd /home/ubuntu/spring-petclinic/petclinic-platform

kubectl apply -k k8s/base/admin-server/
```

### What to verify

```bash
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=admin-server
# Expected: 1/1 Running

kubectl port-forward deploy/admin-server -n petclinic-dev 9090:9090 &
curl http://localhost:9090/actuator/health
# Expected: {"status":"UP"}

# Admin Server dashboard shows all registered services
curl http://localhost:9090/applications
# Expected: JSON with all 7+ services listed
```

---

## 11. Verification Checklist

Run this after deploying all services:

```bash
# 1. All 8 deployments
kubectl get deployments -n petclinic-dev
# Expected: 8 deployments, all READY=1/1

# 2. All pods Running
kubectl get pods -n petclinic-dev --field-selector=status.phase=Running
# Expected: 8+ pods (some may have 2 containers)

# 3. All services have ClusterIP
kubectl get svc -n petclinic-dev
# Expected: 8 ClusterIP services

# 4. Eureka registry
kubectl port-forward deploy/discovery-server -n petclinic-dev 8761:8761 &
curl http://localhost:8761/eureka/apps | grep -c "<instance>"
# Expected: 6+ instances (all except Config Server and Discovery itself)

# 5. Config Server config served
kubectl port-forward deploy/config-server -n petclinic-dev 8888:8888 &
curl -s http://localhost:8888/config-server/default/docker | grep -c "propertySources"
# Expected: >= 1

# 6. API Gateway routes
kubectl port-forward deploy/api-gateway -n petclinic-dev 8080:8080 &
curl -s http://localhost:8080/api/customer/owners
curl -s http://localhost:8080/api/vet/vets
curl -s http://localhost:8080/api/visit/visits
# All expected: HTTP 200

# 7. Admin Server dashboard
kubectl port-forward deploy/admin-server -n petclinic-dev 9090:9090 &
curl -s http://localhost:9090/applications | python3 -m json.tool
# Expected: All 8 services listed
```

### Automated verification script

```bash
#!/bin/bash
# save as scripts/verify-deployment.sh

set -euo pipefail
NS=${1:-petclinic-dev}

echo "=== Verification: $NS ==="

echo "1. Pod status..."
kubectl get pods -n $NS

echo "2. Service health (port-forward in background)..."
for svc in config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server; do
  port=$(kubectl get svc -n $NS -l app.kubernetes.io/name=$svc -o jsonpath='{.items[0].spec.ports[0].port}')
  kubectl port-forward deploy/$svc -n $NS $port:$port &
  sleep 2
  if curl -sf http://localhost:$port/actuator/health > /dev/null 2>&1; then
    echo "  ✅ $svc ($port) — UP"
  else
    echo "  ❌ $svc ($port) — DOWN"
  fi
  kill %1 2>/dev/null || true
done

echo "3. Eureka registry..."
kubectl port-forward deploy/discovery-server -n $NS 8761:8761 &
sleep 2
curl -s http://localhost:8761/eureka/apps | grep -q "<application" && echo "  ✅ Services registered" || echo "  ❌ No registrations"
kill %1 2>/dev/null || true

echo "=== Done ==="
```

---

## 12. Day-2 Operations

### Update a single service

```bash
# 1. Edit the deployment (e.g., change image tag)
EDITOR=vim
$EDITOR k8s/base/customers-service/deployment.yaml

# 2. Reapply
kubectl apply -f k8s/base/customers-service/deployment.yaml

# 3. Watch rollout
kubectl rollout status deploy/customers-service -n petclinic-dev
```

### Scale a deployment

```bash
kubectl scale deploy/api-gateway -n petclinic-dev --replicas=2
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=api-gateway
```

### Rollback

```bash
kubectl rollout undo deploy/customers-service -n petclinic-dev
kubectl rollout status deploy/customers-service -n petclinic-dev
```

### Restart all services

```bash
kubectl rollout restart deploy -n petclinic-dev --all
```

### View logs

```bash
kubectl logs -f deploy/config-server -n petclinic-dev
kubectl logs -f deploy/customers-service -n petclinic-dev --tail=50

# Init container logs
kubectl logs deploy/config-server -n petclinic-dev -c wait-for-config-server
```

---

## 13. Placeholder replacement checklist

Before each service can run, its `deployment.yaml` contains a placeholder image and (for some services) a placeholder RDS endpoint. These must be replaced with real values.

### 13.1 Image tag placeholder

Every deployment has:

```yaml
image: REPLACE_ME
```

This must be replaced with the actual ECR image URL before applying:

```bash
# Format for all 8 services:
# {account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:{tag}
#
# Example for dev:
# 478468080326.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/config-server:a1b2c3d

# Quick reference:
# - Replace {account} with your AWS account ID
# - Replace {env} with dev or prod
# - Replace {tag} with the commit SHA from the build
```

### 13.2 Per-service image lines

| Service | Image line to modify | File |
|---------|---------------------|------|
| Config Server | `image: REPLACE_ME` | `k8s/base/config-server/deployment.yaml` |
| Discovery Server | `image: REPLACE_ME` | `k8s/base/discovery-server/deployment.yaml` |
| API Gateway | `image: REPLACE_ME` | `k8s/base/api-gateway/deployment.yaml` |
| Customers Service | `image: REPLACE_ME` | `k8s/base/customers-service/deployment.yaml` |
| Visits Service | `image: REPLACE_ME` | `k8s/base/visits-service/deployment.yaml` |
| Vets Service | `image: REPLACE_ME` | `k8s/base/vets-service/deployment.yaml` |
| GenAI Service | `image: REPLACE_ME` | `k8s/base/genai-service/deployment.yaml` |
| Admin Server | `image: REPLACE_ME` | `k8s/base/admin-server/deployment.yaml` |

### 13.3 RDS endpoint placeholder

The domain services' ConfigMaps contain a placeholder for the RDS endpoint:

```yaml
# Current (k8s/base/customers-service/configmap.yaml):
SPRING_DATASOURCE_URL: "jdbc:mysql://RDS_ENDPOINT_PLACEHOLDER:3306/petclinic"
```

Replace with the actual RDS endpoint before deploying:

```bash
# Get the real RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier petclinic-dev-mysql \
  --region us-east-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Update in all 3 ConfigMaps
for file in k8s/base/customers-service/configmap.yaml \
             k8s/base/visits-service/configmap.yaml \
             k8s/base/vets-service/configmap.yaml; do
  sed -i "s/RDS_ENDPOINT_PLACEHOLDER/$RDS_ENDPOINT/g" "$file"
done
```

### 13.5 Config map references (which ConfigMaps have placeholders)

| Service | ConfigMap file | Field that needs replacement |
|---------|---------------|-------------------------------|
| customers-service | k8s/base/customers-service/configmap.yaml | SPRING_DATASOURCE_URL: jdbc:mysql://RDS_ENDPOINT_PLACEHOLDER:3306/petclinic |
| visits-service | k8s/base/visits-service/configmap.yaml | SPRING_DATASOURCE_URL: jdbc:mysql://RDS_ENDPOINT_PLACEHOLDER:3306/petclinic |
| vets-service | k8s/base/vets-service/configmap.yaml | SPRING_DATASOURCE_URL: jdbc:mysql://RDS_ENDPOINT_PLACEHOLDER:3306/petclinic |

### 13.6 External Secret placeholders

The k8s/base/external-secrets/ directory has rds-credentials.yaml and openai-api-key.yaml that reference AWS Secrets Manager paths:

```yaml
# k8s/base/external-secrets/rds-credentials.yaml
remoteRef:
  key: petclinic/{env}/rds-credentials

# k8s/base/external-secrets/openai-api-key.yaml
remoteRef:
  key: petclinic/{env}/openai-api-key
```

The {env} placeholder must be replaced with dev or prod before applying.

### 13.7 How to apply after replacement

```bash
# After replacing all placeholders, apply with dry-run first
kubectl apply --dry-run=client -f k8s/base/config-server/deployment.yaml

# Then apply for real
kubectl apply -k k8s/base/
```

---

## 14. Troubleshooting

### Pod states

| State | Meaning | Action |
|-------|---------|-------|
| `Running` (1/1) | Healthy | None |
| `Running` (2/2) | Has sidecar (Envoy, etc.) | Check sidecar logs |
| `Pending` | Not scheduled | `kubectl describe pod` for events |
| `Init:0/1` | Waiting for Config Server | Check Config Server is `Running` |
| `Init:0/2` | Waiting for Config + Discovery | Check both are `Running` |
| `CrashLoopBackOff` | App starts, then dies | `kubectl logs --previous` |
| `ImagePullBackOff` | Image not found | Check ECR tag exists |
| `Error` | Init container failed | `kubectl logs -c wait-for-config-server` |

### Common failure patterns

#### Pattern 1: Init container never completes

```bash
# Check Config Server health
kubectl exec -n petclinic-dev deploy/config-server -- wget -qO- http://localhost:8888/actuator/health

# Check DNS resolution
kubectl exec -n petclinic-dev deploy/config-server -- nslookup config-server
# Expected: service IP

# If port-forward works but init curl doesn't
# The init container uses K8s DNS (service name), not localhost
```

#### Pattern 2: RDS connection refused

```bash
# Check RDS endpoint is reachable from inside cluster
kubectl run -it --rm test-pod -n petclinic-dev --image=busybox:1.36 -- sh
# Inside pod:
wget -qO- http://customers-service:8081/actuator/health | grep "db"

# If health endpoint shows "db" : {"status":"DOWN"}
# → Check secret exists:
kubectl get secret -n petclinic-dev rds-credentials
```

#### Pattern 3: DNS / service discovery

```bash
# K8s DNS check
kubectl run -it --rm dns-test -n petclinic-dev --image=busybox:1.36 -- nslookup config-server
# Expected: 10.100.x.x (ClusterIP)

# If `nslookup: can't resolve`, check coredns pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

#### Pattern 4: HPA not scaling

```bash
kubectl describe hpa -n petclinic-prod api-gateway
# Check: Metrics server is reachable?
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

---

## Appendix: Resource mapping

| Service | Port | Image (ECR) | ConfigMap | Secret | Profiles |
|---------|------|-------------|-----------|--------|----------|
| config-server | 8888 | `{env}/config-server` | `config-server-config` | None | `docker` |
| discovery-server | 8761 | `{env}/discovery-server` | `discovery-server-config` | None | `docker` |
| api-gateway | 8080 | `{env}/api-gateway` | `api-gateway-config` | None | `docker` |
| customers-service | 8081 | `{env}/customers-service` | `customers-service-config` | `rds-credentials` | `docker,mysql` |
| visits-service | 8082 | `{env}/visits-service` | `visits-service-config` | `rds-credentials` | `docker,mysql` |
| vets-service | 8083 | `{env}/vets-service` | `vets-service-config` | `rds-credentials` | `docker,mysql` |
| genai-service | 8084 | `{env}/genai-service` | `genai-service-config` | `openai-api-key` | `docker` |
| admin-server | 9090 | `{env}/admin-server` | `admin-server-config` | None | `docker` |