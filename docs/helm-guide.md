# Helm Guide — Petclinic Platform

> **Purpose:** How to use the shared Helm chart (`helm/petclinic-service/`), configure per-service and per-environment values, understand the values hierarchy, and know the startup order. Updated after the genai-service LLM config discussion (7/2/2026).

---

## Table of Contents

1. [Chart Overview](#chart-overview)
2. [Values Hierarchy](#values-hierarchy)
3. [Per-Service Configuration](#per-service-configuration)
4. [Per-Environment Overrides](#per-environment-overrides)
5. [Service Startup Order](#service-startup-order)
6. [Deploying a Service](#deploying-a-service)
7. [Deploying All Services](#deploying-all-services)
8. [LLM Config: genai-service](#llm-config-genai-service)
9. [Validation](#validation)
10. [Troubleshooting](#troubleshooting)

---

## Chart Overview

A **single generic Helm chart** (`helm/petclinic-service/`) is shared by all 8 microservices. Each service gets its own values file in `helm-values/` that sets port, image, probes, resources, env vars, and init containers. Environment-wide overrides (`dev.yaml`, `prod.yaml`) layer on top.

```
helm/
└── petclinic-service/
    ├── Chart.yaml               # apiVersion: v2, name: petclinic-service
    ├── values.yaml              # Defaults — 8 templates shared by all services
    └── templates/
        ├── _helpers.tpl         # Labels, names, selector helpers
        ├── deployment.yaml      # Main Deployment (Deployment, ServiceAccount, initContainers)
        ├── service.yaml         # ClusterIP Service
        ├── configmap.yaml       # Non-secret config (env vars → ConfigMap)
        ├── serviceaccount.yaml  # Conditional — only when .Values.serviceAccount.create
        ├── hpa.yaml             # Conditional — only when .Values.autoscaling.enabled
        └── pdb.yaml             # Conditional — only when .Values.podDisruptionBudget.enabled
```

---

## Values Hierarchy

Values merge in this order (last wins):

1. **`helm/petclinic-service/values.yaml`** — Chart defaults (replicaCount: 1, no HPA, no PDB, probes at /actuator/health)
2. **`helm-values/{service}.yaml`** — Per-service config (port, image, env, initContainers, resources, probes)
3. **`helm-values/{env}.yaml`** — Environment overrides (dev/prod: replicas, HPA, PDB, namespace)
4. **`--set`** — CLI overrides (used by CI/CD for image tags)

```bash
# Merge order (last wins):
helm template <release> helm/petclinic-service/ \
  -f helm-values/{service}.yaml \    # ← service-level (port, image, initContainers)
  -f helm-values/{env}.yaml \       # ← env-level (replicas, HPA, namespace)
  --set image.tag=<sha>              # ← CI/CD override (inline)
```

### What each layer sets

| Layer | Sets | Example |
|-------|------|---------|
| `values.yaml` (chart) | Defaults: resources, probes, securityContext | `service.port: 8080`, `replicaCount: 1` |
| `{service}.yaml` | Port, image, env, initContainers, serviceAccount | `config-server.yaml` → port 8888, no init |
| `{env}.yaml` | Namespace, replica count, HPA/PDB enabled | `dev.yaml` → no HPA; `prod.yaml` → HPA+PDB enabled |
| `--set` | CI-specific: image tag, overrides | `--set image.tag=85ed54d` |

---

## Per-Service Configuration

### Services and their key settings

| Service | Port | InitContainers | Env Vars | Notes |
|---------|------|---------------|----------|-------|
| **config-server** | 8888 | None | `SPRING_PROFILES_ACTIVE=docker` | No DB, starts first |
| **discovery-server** | 8761 | `wait-for-config-server` | `SPRING_PROFILES_ACTIVE=docker` | Eureka, starts second |
| **api-gateway** | 8080 | `wait-for-config-server` + `wait-for-discovery-server` | Higher CPU (200m/1000m) | Public-facing, frontend |
| **customers-service** | 8081 | `wait-for-config-server` + `wait-for-discovery-server` | `SPRING_DATASOURCE_URL`, `ENVFROM: rds-credentials` | MySQL-backed |
| **visits-service** | 8082 | Same as above | Same pattern | MySQL-backed |
| **vets-service** | 8083 | Same as above | Same pattern | MySQL-backed |
| **genai-service** | 8084 | Same as above | `OPENAI_API_KEY` from `secretKeyRef` | **No hardcoded LLM url/model** — see [LLM Config](#llm-config-genai-service) |
| **admin-server** | 9090 | Same as above | `CONFIG_SERVER_URL` | Spring Boot Admin |

### Per-service file location

```
helm-values/
├── config-server.yaml
├── discovery-server.yaml
├── api-gateway.yaml
├── customers-service.yaml
├── visits-service.yaml
├── vets-service.yaml
├── genai-service.yaml
├── admin-server.yaml
├── dev.yaml           # Dev environment overrides
└── prod.yaml          # Prod environment overrides
```

---

## Per-Environment Overrides

### `dev.yaml`

```yaml
namespace: petclinic-dev
replicaCount: 1
autoscaling:
  enabled: false
podDisruptionBudget:
  enabled: false
```

### `prod.yaml`

```yaml
namespace: petclinic-prod
replicaCount: 2
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 70
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

---

## Service Startup Order

Spring Petclinic has a **strict startup dependency**:
ESO - external secrets store first

```
config-server (1st) → discovery-server (2nd) → all others (3rd+)
```

This is enforced by **init containers** in each service's Deployment:

1. **`config-server`** — No init containers (starts first, no dependencies)
2. **`discovery-server`** — Init: `wait-for-config-server` (waits for config-server:8888/actuator/health)
3. **All other services** — Init: `wait-for-config-server` + `wait-for-discovery-server` (waits for both)

The init containers use `busybox:1.36` with `wget` to poll readiness endpoints. The `waitFor` field in each service's values determines which service to wait for.

---
## DRY RUN
helm template customers-service ./helm/petclinic-service -f helm-values/customers-service.yaml -f helm-values/prod.yaml

helm install --dry-run --debug my-release helm/petclinic-service/      -f helm-values/customers-service.yaml      -f helm-values/dev.yaml      -n petclinic-dev


## Deploying a Service

```bash
# Dev deployment
helm upgrade --install config-server helm/petclinic-service/ \
  -n petclinic-dev \
  -f helm-values/config-server.yaml \
  -f helm-values/dev.yaml \
  --set image.tag=85ed54d

# Prod deployment (same pattern, different env file)
helm upgrade --install customers-service helm/petclinic-service/ \
  -n petclinic-prod \
  -f helm-values/customers-service.yaml \
  -f helm-values/prod.yaml \
  --set image.tag=85ed54d
```

### Deploying all services (correct order)

```bash
# 1. Config Server (no dependencies)
helm upgrade --install config-server ...
# 2. Discovery Server (depends on config-server)
helm upgrade --install discovery-server ...
# 3. All other services (depends on both)
helm upgrade --install api-gateway ...
helm upgrade --install customers-service ...
helm upgrade --install visits-service ...
helm upgrade --install vets-service ...
helm upgrade --install genai-service ...
helm upgrade --install admin-server ...

helm upgrade --install config-server ./helm/petclinic-service/ \
  -f helm-values/config-server.yaml \
  -f helm-values/dev.yaml \
  -n petclinic-dev

helm upgrade --install discovery-server ./helm/petclinic-service/   -f helm-values/discovery-server.yaml   -f helm-values/dev.yaml   -n petclinic-dev

 helm upgrade --install api-gateway ./helm/petclinic-service/ \
     -f helm-values/api-gateway.yaml \
     -f helm-values/dev.yaml \
     -n petclinic-dev

   # Deploy Admin Server
   helm upgrade --install admin-server ./helm/petclinic-service/ \
     -f helm-values/admin-server.yaml \
     -f helm-values/dev.yaml \
     -n petclinic-dev

helm upgrade --install visits-service ./helm/petclinic-service/   -f helm-values/visits-service.yaml   -f helm-values/dev.yaml   -n petclinic-dev

helm upgrade --install vets-service ./helm/petclinic-service/   -f helm-values/vets-service.yaml   -f helm-values/dev.yaml   -n petclinic-dev
helm upgrade --install customers-service ./helm/petclinic-service/      -f helm-values/customers-service.yaml      -f helm-values/dev.yaml      -n petclinic-dev

helm upgrade --install genai-service ./helm/petclinic-service/ \
     -f helm-values/genai-service.yaml \
     -f helm-values/dev.yaml \
     -n petclinic-dev


 ```
```

---

## LLM Config: genai-service

The genai-service uses **Spring AI** with `spring.ai.openai.*` config keys. The LLM URL and model are **not** set via Helm environment variables — they are hardcoded in the service's `application.yml` (Java config) and baked into the Docker image.

**What this means:**

- `OPENAI_BASE_URL` and `OPENAI_MODEL` are **not** in the `helm-values/genai-service.yaml` `env` block
- They are **not** in `dev.yaml` or `prod.yaml`
- The values are set in `/home/ubuntu/spring-petclinic/spring-petclinic-microservices/spring-petclinic-genai-service/src/main/resources/application.yml`
- To change them: modify `application.yml` → rebuild Docker image → push to ECR → deploy

**If you want them configurable per-environment later:** Add `OPENAI_BASE_URL` and `OPENAI_MODEL` as `env` entries in `helm-values/genai-service.yaml`, and the app will pick them up via `@Value`/`SPRING_AI_OPENAI_BASE_URL`. But in the current state, they are **same for dev and prod** (handled by `application.yml`).

---

## Validation

Run the validation script:

```bash
bash scripts/validate-helm.sh
```

This runs for all 8 services × 2 environments:

1. **`helm lint`** — Checks chart structure
2. **`helm template`** — Renders YAML for each service + env
3. **`kubectl apply --dry-run=client`** — Validates against a real cluster

---

## VERIFY

ubuntu@ip-172-31-65-219:~/spring-petclinic/petclinic-platform$ helm list -n petclinic-dev
NAME             	NAMESPACE    	REVISION	UPDATED                                	STATUS  	CHART                  	APP VERSION
admin-server     	petclinic-dev	1       	2026-07-02 13:22:34.46833426 +0000 UTC 	deployed	petclinic-service-0.1.0	4.0.1
api-gateway      	petclinic-dev	1       	2026-07-02 13:22:21.513976519 +0000 UTC	deployed	petclinic-service-0.1.0	4.0.1
config-server    	petclinic-dev	2       	2026-07-02 13:01:50.55694652 +0000 UTC 	deployed	petclinic-service-0.1.0	4.0.1
customers-service	petclinic-dev	1       	2026-07-02 13:41:54.355538092 +0000 UTC	deployed	petclinic-service-0.1.0	4.0.1
discovery-server 	petclinic-dev	1       	2026-07-02 13:16:40.450325541 +0000 UTC	deployed	petclinic-service-0.1.0	4.0.1
genai-service    	petclinic-dev	1       	2026-07-02 13:57:06.96099547 +0000 UTC 	deployed	petclinic-service-0.1.0	4.0.1
my-release       	petclinic-dev	3       	2026-07-02 12:48:19.062411049 +0000 UTC	deployed	petclinic-service-0.1.0	4.0.1
vets-service     	petclinic-dev	1       	2026-07-02 13:18:32.64204616 +0000 UTC 	deployed	petclinic-service-0.1.0	4.0.1
visits-service   	petclinic-dev	1       	2026-07-02 13:18:31.592868382 +0000 UTC	deployed	petclinic-service-0.1.0	4.0.1
ubuntu@ip-172-31-65-219:~/spring-petclinic/petclinic-platform$ helm history config-server -n petclinic-dev
REVISION	UPDATED                 	STATUS    	CHART                  	APP VERSION	DESCRIPTION
1       	Thu Jul  2 12:56:18 2026	superseded	petclinic-service-0.1.0	4.0.1      	Install complete
2       	Thu Jul  2 13:01:50 2026	deployed  	petclinic-service-0.1.0	4.0.1      	Upgrade complete

   helm uninstall config-server -n petclinic-dev
   helm uninstall discovery-server -n petclinic-dev
   helm uninstall api-gateway -n petclinic-dev
   helm uninstall customers-service -n petclinic-dev
   helm uninstall visits-service -n petclinic-dev
   helm uninstall vets-service -n petclinic-dev
   helm uninstall admin-server -n petclinic-dev
   helm uninstall genai-service -n petclinic-dev

___

## Troubleshooting

### Common issues

| Error | Cause | Fix |
|-------|-------|-----|
| `YAML parse error on deployment.yaml: line 48` | `initContainers` `command` field is a YAML block scalar (`\|`) | Use `toYaml` on the whole `initContainers` block instead of `range` |
| `Could not find expected ':'` | `envFrom` block double-wraps YAML | Use `{{- toYaml .Values.envFrom \| nindent 10 }}` instead of `range` loop |
| `kubectl apply --dry-run: exit 191` | `csplit` can't split multi-resource YAML | Use `kubectl apply --dry-run=client -f` on the full manifest |
| No HPA/PDB in dev | `autoscaling.enabled: false` in `dev.yaml` | This is expected — dev has no HPA |
| HPA/PDB in prod | `autoscaling.enabled: true` in `prod.yaml` | Only services with `replicaCount > 1` get HPA |

### Checking rendered output

```bash
# Check a specific service's rendered YAML
helm template genai-service helm/petclinic-service/ \
  -f helm-values/genai-service.yaml \
  -f helm-values/dev.yaml

# Check only the Deployment (skip other resources)
helm template genai-service ... | kubectl apply --dry-run=client -f -
```

---

## Related

- `docs/technical-spec.md` — Full infrastructure spec (CIDRs, ports, versions)
- `docs/jira-backlog.md` — Jira story tracking
- `helm/petclinic-service/values.yaml` — Chart defaults
- `helm-values/` — All per-service and per-environment values
