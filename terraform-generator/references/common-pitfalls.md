# Common Terraform Pitfalls — Reference

Read this file when troubleshooting or when the infrastructure involves edge cases listed below.

## Table of Contents
1. State Lock Stuck
2. Provider Version Conflicts
3. Dependency Cycles
4. Count vs for_each
5. Sensitive Output Leaks
6. Destroy-Then-Create Downtime
7. State Drift
8. Module Version Pinning
9. Import Existing Resources
10. Cross-Account / Cross-Region

---

## 1. State Lock Stuck

**Problem**: `terraform apply` fails with "Error acquiring the state lock". Happens when a previous run crashed or was killed mid-operation.

**Symptom**: Every plan/apply shows lock error with a Lock ID.

**Fix**:
```bash
# Verify no one else is running — check with your team first
terraform force-unlock <LOCK_ID>
```

**Prevention**:
- Use CI/CD pipelines for apply (not local machines)
- Set DynamoDB TTL or equivalent to auto-expire stale locks
- Never kill `terraform apply` mid-run — wait for it to finish or use `-target` for partial applies

---

## 2. Provider Version Conflicts

**Problem**: `terraform init` fails with version constraint conflicts, especially in projects with many modules that each pin different provider versions.

**Common symptom**: "Could not retrieve the list of available versions" or "no available version is compatible with all constraints".

**Fix**:
- Use `~>` (pessimistic) constraints — `~> 5.40` allows 5.40.x through 5.99.x but not 6.0
- Don't pin to exact versions unless you have a specific reason
- Run `terraform init -upgrade` when you need to update providers
- Always commit `.terraform.lock.hcl` — it captures exact resolved versions

**Prevention**: Pin providers only in the root module. Modules should use broad constraints (`>= 5.0`) and let the root module resolve the exact version.

---

## 3. Dependency Cycles

**Problem**: "Cycle" error in plan. Resource A depends on B which depends on A.

**Common case**: Security group A allows traffic from SG B, and SG B allows traffic from SG A.

**Fix**: Use separate `aws_vpc_security_group_ingress_rule` resources instead of inline `ingress` blocks:
```hcl
resource "aws_security_group" "a" { name_prefix = "a-" }
resource "aws_security_group" "b" { name_prefix = "b-" }

resource "aws_vpc_security_group_ingress_rule" "a_from_b" {
  security_group_id            = aws_security_group.a.id
  referenced_security_group_id = aws_security_group.b.id
  # ...
}

resource "aws_vpc_security_group_ingress_rule" "b_from_a" {
  security_group_id            = aws_security_group.b.id
  referenced_security_group_id = aws_security_group.a.id
  # ...
}
```

No cycle because the SG resources don't reference each other — only the rule resources do.

---

## 4. Count vs for_each

**Problem**: Using `count` with a list, then removing an item from the middle causes Terraform to destroy and recreate all subsequent items (because they're indexed by position).

**Example**: 3 subnets via `count`. Remove the second one. Terraform plans to destroy subnet[1] and subnet[2], then recreate subnet[2] as new subnet[1].

**Fix**: Always use `for_each` with a map or set. Resources are keyed by name, not position:
```hcl
variable "subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
}

resource "aws_subnet" "this" {
  for_each          = var.subnets
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  vpc_id            = var.vpc_id

  tags = { Name = "${local.name_prefix}-${each.key}" }
}
```

**Rule of thumb**: Use `count` only for conditional creation (`count = var.create_resource ? 1 : 0`). Use `for_each` for everything else.

---

## 5. Sensitive Output Leaks

**Problem**: Variables marked `sensitive = true` are hidden in CLI output, but they still appear in state files. Anyone with state access can read them.

**Symptom**: False sense of security — password is "hidden" in logs but readable in `terraform.tfstate`.

**Fix**:
- Encrypt state at rest (S3 SSE-KMS, GCS CMEK)
- Restrict state bucket access to CI/CD service accounts only
- Use external secret stores (AWS Secrets Manager, Vault) and reference via data sources instead of passing secrets through Terraform variables
- If you must pass secrets through Terraform, use `TF_VAR_` env vars — never commit them to files

---

## 6. Destroy-Then-Create Downtime

**Problem**: Terraform default replacement strategy is destroy-then-create. For resources with unique names (security groups, IAM roles), this causes downtime.

**Symptom**: Brief outage during apply when a resource is replaced.

**Fix**: Use `create_before_destroy` lifecycle and `name_prefix` instead of `name`:
```hcl
resource "aws_security_group" "api" {
  name_prefix = "${local.name_prefix}-api-"  # Not name = "..."

  lifecycle {
    create_before_destroy = true
  }
}
```

With `name_prefix`, Terraform generates a unique name, creates the new SG, migrates references, then destroys the old one — zero downtime.

---

## 7. State Drift

**Problem**: Someone makes a manual change in the console. Terraform doesn't know about it. Next apply reverts the manual change, or plan shows unexpected diffs.

**Symptom**: `terraform plan` shows changes you didn't make.

**Fix**:
- Run `terraform plan` regularly in CI (drift detection)
- Use `terraform refresh` or `terraform apply -refresh-only` to sync state
- For intentional manual changes, use `terraform import` to bring them under management
- Add `ignore_changes` for attributes managed outside Terraform (e.g., ASG desired_count managed by autoscaling)

**Prevention**: Enforce a "no console changes" policy. All changes go through Terraform PRs.

---

## 8. Module Version Pinning

**Problem**: Using `source = "terraform-aws-modules/vpc/aws"` without a version constraint. A module update breaks your infrastructure on next `terraform init -upgrade`.

**Fix**: Always pin module versions:
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"  # Allows 5.5.x - 5.99.x, blocks 6.0
}
```

For git-sourced modules, use `ref`:
```hcl
module "custom" {
  source = "git::https://github.com/org/module.git//modules/vpc?ref=v2.1.0"
}
```

**Rule**: Never use an unpinned module in production. A breaking change in a module you don't control can destroy resources.

---

## 9. Import Existing Resources

**Problem**: You need to bring manually-created infrastructure under Terraform management without destroying and recreating it.

**Approach**:

```hcl
# 1. Write the resource config first
resource "aws_s3_bucket" "existing" {
  bucket = "my-existing-bucket"
}

# 2. Import into state (Terraform 1.5+ supports import blocks)
import {
  to = aws_s3_bucket.existing
  id = "my-existing-bucket"
}

# 3. Run terraform plan — fix any diffs until plan shows "No changes"
# 4. Remove the import block after successful apply
```

For older Terraform versions:
```bash
terraform import aws_s3_bucket.existing my-existing-bucket
```

**Warning**: Import only adds to state — it doesn't generate config. You must write the `resource` block yourself and iterate until `plan` shows no changes.

---

## 10. Cross-Account / Cross-Region

**Problem**: Managing resources across multiple AWS accounts or regions. Common in production setups with separate accounts for dev/staging/prod.

**Pattern**: Use provider aliases:
```hcl
provider "aws" {
  region = "us-east-1"
  alias  = "us_east"
}

provider "aws" {
  region = "eu-west-1"
  alias  = "eu_west"
}

# Cross-account via assume_role
provider "aws" {
  alias  = "prod"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/TerraformRole"
  }
}

# Use in resources
resource "aws_s3_bucket" "eu_backup" {
  provider = aws.eu_west
  bucket   = "backup-eu"
}
```

**Key points**:
- The account running Terraform needs `sts:AssumeRole` permission on the target role
- Target role needs a trust policy allowing the source account
- Keep the blast radius small — one state file per account per environment
- Use separate AWS profiles or role chaining, never hardcode credentials
