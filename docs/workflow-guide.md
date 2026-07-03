# End-to-End Workflow — CI/CD Pipeline for Petclinic

> **Purpose:** This document explains how the two repos (app + platform) interact through
> GitHub Actions and ArgoCD to build, push, and deploy Docker images.
>
> **Audience:** Students setting up the CI/CD pipeline for the first time.

## Architecture Overview

```
App Repo (eks-spring-petclinic)          Platform Repo (eks-petclinic-platform)
   │                                          │
   │  push to main                            │
   │    ↓                                     │
   │  dorny/paths-filter                      │
   │  detects which services changed          │
   │    ↓                                     │
   │  Buildx + QEMU                           │
   │  → linux/arm64                          │
   │    ↓                                     │
   │  OIDC → aws-actions/configure-aws-creds  │
   │    ↓                                     │
   │  ECR login → build → tag                 │
   │  (github.sha[:7])                       │
   │    ↓                                     │
   │  Trivy scan (gate: CRITICAL)             │
   │    ↓                                     │
   │  Push to ECR                              │
   │    ↓                                     │
   │  repository_dispatch                      │
   │  ─────────────►  app-image-built        │
   │  {sha, services}                         │
   │                                          │
   │                               yq updates image.tag
   │                               in helm-values/*.yaml
   │                               git commit + push
   │                                    ↓
   │                               ArgoCD detects change
   │                               → deploys to EKS
```

## Two-Repo Setup

| Repo | URL | Location on disk | Contains |
|------|-----|----------------|---------|
| **App repo** | `https://github.com/amitmaurya001/eks-spring-petclinic` | `/home/ubuntu/spring-petclinic/spring-petclinic-microservices` | Java microservices, Dockerfiles, `build-push.yml` |
| **Platform repo** | `https://github.com/amitmaurya001/eks-petclinic-platform` | `/home/ubuntu/spring-petclinic/petclinic-platform` | Terraform, Helm values, `update-image-tags.yml`, docs |

## Secrets and Variables Required

Configure these in **both repos** → GitHub → Settings → Secrets and variables → Actions:

### App repo (`eks-spring-petclinic`) — **Secrets**

| Secret | Value | Where to get |
|--------|-------|-------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::{account}:role/petclinic-github-actions-build-role` | From the OIDC Terraform output (`terraform/modules/github-oidc/`) |
| `PLATFORM_REPO_TOKEN` | Fine-grained PAT with `contents:write` on `eks-petclinic-platform` | Created in GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens |

### App repo (`eks-spring-petclinic`) — **Variables**

| Variable | Value | Notes |
|----------|-------|-------|
| `AWS_REGION` | `us-east-1` | Default AWS region |
| `AWS_ACCOUNT_ID` | `478468080326` | 12-digit AWS account ID from `aws sts get-caller-identity --query Account` |
| `PLATFORM_REPO` | `amitmaurya001/eks-petclinic-platform` | The platform repo to send `repository_dispatch` to |

### Platform repo (`eks-petclinic-platform`) — **Secrets**

| Secret | Value | Notes |
|--------|-------|-------|
| `PLATFORM_REPO_TOKEN` | Same PAT as above | Used by `update-image-tags.yml` to check out the repo |
| `PLATFORM_REPO` (variable) | `amitmaurya001/eks-petclinic-platform` | Set as `vars` |

## Running the Pipeline

### Step 1: Set up OIDC

```bash
cd terraform/environments/dev
terraform init
terraform plan -out=oidc.plan -target=module.github-oidc
terraform apply oidc.plan
```

Output:
```
github_actions_build_role_arn = "arn:aws:iam::...:role/petclinic-github-actions-build-role"
github_actions_oidc_provider_arn = "arn:aws:iam::...:oidc-provider/token.actions.githubusercontent.com"
```

Three ARNs — what each one is

 ┌─────────────────────────────────┬─────────────────────────────────────────────────────────────┬────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────┐
 │ Output                          │ What it is                                                  │ Where it comes from                        │ Used by b                                                         │
 ├─────────────────────────────────┼─────────────────────────────────────────────────────────────┼────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
 │ eks_oidc_provider_arn           │ The EKS cluster's own OIDC provider (e.g.                   │ module.eks —                               │ Used for IRSA (IAM Roles for Service Accounts) — lets K8s pods  │
 │                                 │ arn:aws:iam::...:oidc-provider/oidc.eks.us-east-1.amazonaws │ aws_iam_openid_connect_provider.cluster_oi │ (e.g. EBS CSI, External Secrets) assume IAM roles via K8s       │
 │                                 │ .com/id/...)                                                │ dc                                         │ service accounts                                                │
 ├─────────────────────────────────┼─────────────────────────────────────────────────────────────┼────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
 │ github_actions_oidc_provider_ar │ The GitHub Actions OIDC provider                            │ module.github-oidc —                       │ Used as the trust anchor for GitHub Actions to assume the       │
 │ n                               │ (arn:aws:iam::...:oidc-provider/token.actions.githubusercon │ aws_iam_openid_connect_provider.github_act │ github_actions_build_role via OIDC federation                   │
 │                                 │ tent.com)                                                   │ ions                                       │                                                                 │
 ├─────────────────────────────────┼─────────────────────────────────────────────────────────────┼────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────┤
 │ github_actions_build_role_arn   │ The IAM role that GitHub Actions can assume                 │ module.github-oidc —                       │ The actual role GitHub Actions assumes to push images to ECR    │
 │                                 │ (arn:aws:iam::...:role/petclinic-github-actions-build-role) │ aws_iam_role.github_actions_build_role     │                                                                 │
 └─────────────────────────────────┴─────────────────────────────────────────────────────────────┴────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────┘

 Which one to use where

 In GitHub Actions CI/CD (as a secret / variable): you need only github_actions_build_role_arn.

 Here's why:

 - The OIDC provider (github_actions_oidc_provider_arn) is an AWS-side resource — GitHub doesn't need its ARN. GitHub's OIDC tokens are validated automatically by AWS when you use AssumeRoleWithWebIdentity.
   You don't store the provider ARN as a secret.
 - The eks_oidc_provider_arn is for Kubernetes IRSA (pods in the cluster assuming roles) — nothing to do with GitHub CI.

### Step 2: Set GitHub secrets

Copy the role ARN into `AWS_ROLE_ARN` secret in the app repo.

### Step 3: Push to the app repo

```bash
cd spring-petclinic-microservices
git add .
git commit -m "fix: update port mappings"
git push origin main
```

This triggers `build-push.yml`:

- **Expected:** Only the services whose `spring-petclinic-{service}/` directory changed get built
- **Expected:** Buildx + QEMU → `linux/arm64` → OIDC → ECR login → build → tag → Trivy → push → dispatch

### Step 4: Verify platform repo

```bash
cd ../petclinic-platform
git pull
git log -1 --oneline helm-values/
# Should show: "ci: update image tags to a1b2c3d (customers-service)"
```

### Step 5: ArgoCD syncs

ArgoCD detects the Git change in `helm-values/` and deploys the new image to EKS.

## Troubleshooting

| Symptom | Cause | Fix |
|----------|-------|-----|
| `repository_dispatch` fails with 403 | `PLATFORM_REPO_TOKEN` has wrong scope | Create a fresh PAT with `contents:write` |
| Trivy blocks push | CRITICAL vulnerability in base image | Update base image, rebuild |
| Workflow doesn't fire | `on: push: branches: [main]` — wrong branch | Push to `main`, not a feature branch |
| Matrix has empty entries | No service directory changed | Push only after modifying code |
| `yq` not found | Missing from runner | The workflow installs `yq` via `wget` |

## Files Created

| File | Location | Purpose |
|------|----------|---------|
| `build-push.yml` | `spring-petclinic-microservices/.github/workflows/` | CI build — detect, build, scan, push, dispatch |
| `update-image-tags.yml` | `petclinic-platform/.github/workflows/` | Receives dispatch, updates `image.tag` in `helm-values/`, commits |
| `ecr-login.yml` (reusable) | `spring-petclinic-microservices/.github/workflows/reusable/` | Encapsulates OIDC + ECR login |
| `rollback-runbook.md` | `petclinic-platform/docs/` | Rollback procedures for app, infra, OIDC, git |
