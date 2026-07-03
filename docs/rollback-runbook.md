# Rollback Runbook — Petclinic Platform

> **Scope:** This runbook covers rollback scenarios for the petclinic platform,
> covering both infrastructure (Terraform-managed) and application (K8s-managed)
> rollbacks.  It is the canonical reference when PETPLAT-54's trigger conditions are met.
>
> **Owner:** Platform Engineering
> **Severity:** P1 (production), P3 (dev)

---

## 1. Concepts

| Term | Definition |
|------|------------|
| **Rollback** | Reverting a change to the previous known-good state |
| **Reversion** | Applying a forward fix that cancels the bad change |
| **Restore** | Recovering state from a backup (S3, Secrets Manager, RDS) |

### Rollback Layers

| Layer | What | How |
|-------|------|-----|
| Git | Source-of-truth state (helm-values, k8s manifests, terraform) | `git revert` |
| Infrastructure (Terraform) | AWS resources (VPC, ECR, RDS, EKS) | `terraform plan -destroy`, `terraform apply` |
| Application (Helm/K8s) | Deployed microservices | `helm rollback`, `kubectl rollout undo` |
| Data (RDS) | MySQL database | `pg_dump` restore (pre-change snapshot) |
| OIDC/IAM | GitHub Actions IAM role | Detach policy, reassign role |

### Guardrails

| Guard | Applies When |
|-------|--------------|
| `terraform plan` required before `apply` | Infrastructure changes |
| `--dry-run=client` required before `kubectl apply` | K8s manifest changes |
| Manual approval gate in ArgoCD UI | Prod deployments |
| `helm rollback --wait --timeout 5m` | Application rollback |

---

## 2. When to Roll Back

| Trigger | Layer | Action | Priority |
|--------|-------|--------|----------|
| Image tag pointing to a bad build | Application (Helm values) | Revert or advance to known-good SHA | P1 |
| ECR IAM role configured incorrectly (no push) | IAM/OIDC | Update trust/role policy, re-apply terraform | P1 |
| OIDC provider broken (can't assume role) | OIDC/IAM | Re-create provider, verify thumbprint | P1 |
| Wrong `image.tag` committed to `helm-values/` | Git | `git revert HEAD` or `git push --force` with corrected tag | P3 |
| Terraform apply drifted (state mismatch) | Infrastructure | Identify drift, `terraform plan`, re-apply | P2 |
| EKS cluster misconfigured | EKS/IAM | Re-apply terraform module, verify nodes | P1 |
| RDS credentials rotated | Secrets Manager | Update ExternalSecret, wait for ESO sync | P2 |
| ArgoCD Application CRD misconfigured | ArgoCD | Edit Application CRD, re-sync | P3 |
| Prometheus alert rules stale | Observability | `kubectl apply -f k8s/prometheus-rules/` | P3 |

---

## 3. Rollback Procedures

### 3a. Application Rollback (image.tag)

**Scenario:** A bad image was pushed and the `repository_dispatch` workflow updated `helm-values/` with a bad SHA.  The bad image may be missing a layer, fail Trivy scan, or cause a container crash loop.

**Steps:**

1. **Identify the bad SHA:**
   ```bash
   # Check the most recent commit in helm-values/
   git log -1 --oneline helm-values/

   # Show diff that changed the tag
   git show --stat HEAD
   yq eval '.image.tag' helm-values/customers-service.yaml
   ```

2. **Option A — Advance to a known-good SHA:**
   Re-trigger the `repository_dispatch` from the app repo with the corrected SHA:
   ```bash
   curl -X POST \
     -H "Authorization: Bearer ${GH_TOKEN}" \
     -H "Accept: application/vnd.github.everest-preview+json" \
     "https://api.github.com/repos/amitmaurya001/eks-petclinic-platform/dispatches" \
     -d '{"event_type":"app-image-built","client_payload":{"sha":"a1b2c3d","services":"customers-service vets-service"}}'
   ```
   The workflow picks up the new SHA and updates `helm-values/` again.

3. **Option B — Roll back the commit:**
   ```bash
   git revert HEAD --no-edit
   git push origin main
   ```
   This restores the previous tag. ArgoCD detects the revert and auto-syncs.

4. **Verify:**
   ```bash
   # Check the running tags
   kubectl get deployment -n petclinic-dev \
     -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}' | \
     grep -v busybox | head -8
   ```

### 3b. Infrastructure Rollback (Terraform)

**Scenario:** A `terraform apply` in dev or prod created wrong resources (wrong VPC CIDR, bad RDS config, wrong ECR ownership).  The Terraform state file reflects the bad state.

**Steps:**

1. **Lock Terraform state:**
   ```bash
   aws dynamodb put-item \
     --table-name petclinic-terraform-locks \
     --item '{"LockID": {"S": "petclinc/$(env)/terraform.tfstate"}, "Info": {"S": "rollback-hold"}}'
   ```

2. **Retrieve the previous good state:**
   ```bash
   aws s3 cp s3://petclinic-terraform-state/terraform.tfstate \
     terraform/previous-good.tfstate
   ```

3. **Run `terraform plan` against previous state:**
   ```bash
   terraform plan -state=previous-good.tfstate -out=rollback.plan
   ```

4. **Review and apply:**
   ```bash
   terraform apply rollback.plan
   ```

5. **Push corrected state:**
   ```bash
   aws s3 cp terraform.tfstate s3://petclinic-terraform-state/petclinic/$(env)/
   ```

6. **Verify:**
   ```bash
   terraform state list | wc -l  # Should match pre-change count
   ```

### 3c. OIDC / IAM Rollback

**Scenario:** The OIDC provider was misconfigured or the IAM role's trust policy was too permissive (e.g. `*` instead of the repo-specific `sub`).  GitHub Actions struggles to connect.

**Steps:**

1. **Detach the over-permissive policy:**
   ```bash
   aws iam detach-role-policy \
     --role-name $ROLE \
     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   ```

2. **Re-attach the correct ECR-only policy:**
   ```bash
   terraform apply -target=module.github-oidc
   ```

3. **Verify trust policy:**
   ```bash
   aws iam get-role \
     --role-name petclinic-github-actions-build-role \
     --query 'AssumeRolePolicyDocument' --output json | \
     jq '.Statement[0].Condition.StringEquals."token.actions.githubusercontent.com:sub"'
   ```
   Should return `repo:amitmaurya001/eks-spring-petclinic:ref:refs/heads/main`.

4. **Test OIDC:**
   Trigger a test build in the app repo.  Check `ACTIONS_ID_TOKEN_REQUEST_TOKEN` in job logs.

### 3d. Git Rollback

**Scenario:** A `git push` to `helm-values/` committed wrong content, or the workflow failed mid-way (committed but didn't push).

**Steps:**

1. **`git log --oneline helm-values/`** — find the bad commit
2. **`git revert <bad-sha>`** — revert the commit
3. **`git push origin main`** — push the revert
4. **Verify:** `git log -1 helm-values/` shows the correct tag

**Important:** `git revert` is preferred over `git reset --hard` + `git push --force`.  Force push breaks ArgoCD's sync state and requires cluster re-sync.  Only force push when:

- The bad commit contains a secret
- The commit is on a branch that doesn't feed ArgoCD (feature branch)
- `git revert` is blocked by a merge conflict you can't resolve

---

## 4. Verification Checklist

After every rollback, run:

```bash
# 1. ECR — verify the correct image exists
aws ecr describe-images \
  --repository-name petclinic-dev/customers-service \
  --region us-east-1 | jq '.imageDetails[].imageTags'

# 2. EKS — verify pods are running
kubectl get pods -n petclinic-dev | grep -E "Running|Completed"

# 3. OIDC — verify trust policy
aws iam get-role \
  --role-name petclinic-github-actions-build-role \
  --query 'AssumeRolePolicyDocument'

# 4. Git — verify the reverted commit is visible
git log --oneline -3

# 5. ArgoCD — verify sync status
kubectl get applications -n argocd
```

---

## 5. Single-Command Rollback (Emergency)

For urgent production issues, a single `make rollback` target is provided:

```bash
# Revert the last git commit that touched helm-values/
make rollback
```

This runs:
```bash
#!/usr/bin/env bash
set -euo pipefail

SHA=$(git log -1 --format='%H' -- helm-values/)
git revert "${SHA}" --no-edit
git commit --amend -m "rollback: emergency revert to $(git log -1 --format='%h' ${SHA})"
git push origin main

echo "Rollback complete.  ArgoCD should detect the revert and sync."
```

---

## 6. Rollback Testing (DR)

| Frequency | Scope | Action |
|-----------|-------|--------|
| Weekly | Dev | `make rollback` on a dev image tag |
| Monthly | Prod | Simulate a bad commit, verify revert |
| Per release | All | Verify `helm rollback` works on all 8 services |

---

## 7. Appendices

### A. Expected Outputs

After a successful application rollback:

```
$ kubectl get pods -n petclinic-dev
NAME                              READY   STATUS    RESTARTS   AGE
customers-service-7f8b9c6d4-abc   1/1     Running   0          2m
vets-service-6d9c8b7e5-xyz       1/1     Running   0          2m
...
```

After a successful OIDC rollback:

```
$ aws iam get-role --role-name petclinic-github-actions-build-role
{
    "Role": {
        "RoleName": "petclinic-github-actions-build-role",
        "AssumeRolePolicyDocument": {
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Federated": "arn:aws:...:oidc-provider/token.actions.githubusercontent.com"},
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                    "StringEquals": {
                        "token.actions.githubusercontent.com:sub": "repo:amitmaurya001/eks-spring-petclinic:ref:refs/heads/main"
                    }
                }
            }]
        }
    }
}
```

After a successful git rollback:

```
$ git log --oneline -2
a1b2c3d ci: update image tags to 85ed54d (customers-service vets-service)
f6e5d4c ci: update image tags to a1b2c3d (customers-service vets-service)

$ yq eval '.image.tag' helm-values/customers-service.yaml
a1b2c3d
```

### B. Failed Rollback — Next Steps

| Symptom | Cause | Next Action |
|---------|-------|-------------|
| `helm rollback` fails | Release not found (deleted by auto-prune) | `helm install --atomic` with the previous tag |
| `git revert` has conflicts | Other commits since the bad one | `git rebase --onto <good-sha>~1 <bad-sha>` |
| `terraform apply rollback.plan` fails | State drift | `terraform plan -state=rollback.plan -target=module.$MODULE` |
| `make rollback` creates empty commit | No changes to helm-values | Fix manually — `git checkout HEAD~1 helm-values/` then `git commit` |
| ArgoCD doesn't detect the revert | Sync policy is manual (prod) | Click "Sync" in ArgoCD UI or `argocd app sync` from CLI |
| OIDC role not found | `terraform destroy` on the OIDC module | Run `terraform apply` on the OIDC module again with `-target=module.github-oidc` |