---
name: terraform-generator
description: >
  Generate production-grade Terraform configurations and module structures from scratch.
  Use this skill whenever the user asks to create, generate, or write Terraform code, HCL files,
  infrastructure as code, or cloud resource definitions. Also trigger when the user describes
  infrastructure needs (e.g., "I need a VPC with EKS and RDS"), asks to set up cloud environments,
  mentions provisioning resources on AWS/GCP/Azure/any cloud, wants to modularize existing Terraform,
  or needs a remote backend / state management setup. Covers project structure, module design,
  provider configuration, state backends, resource patterns for compute/networking/databases/storage/IAM,
  environment separation, variable conventions, security hardening, and tagging strategies.
  Target audience is advanced DevOps engineers — skip HCL basics, focus on module design, state safety,
  least-privilege IAM, and production patterns.
---

# Terraform Generator Skill

Generate production-grade Terraform configurations. The audience knows Terraform well — they want well-structured, secure, DRY infrastructure code, not HCL tutorials.

## Reference Files

- `references/common-pitfalls.md` — Read when the setup involves state migration, multi-account patterns, provider version conflicts, or troubleshooting plan/apply issues.

## Workflow

### Step 1: Identify the Infrastructure

Extract from the user's request (infer where possible, ask only when genuinely ambiguous):

- **Cloud provider(s)** — AWS, GCP, Azure, or multi-cloud
- **Resources needed** — networking, compute, databases, storage, IAM, DNS, CDN, monitoring
- **Scale** — single environment, multi-env (dev/staging/prod), multi-account, multi-region
- **Constraints** — existing state to import, compliance requirements, specific Terraform version, OpenTofu preference

### Step 2: Generate Files

Produce all relevant files following the project structure standard below. Always include:
- `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` at minimum
- `backend.tf` for state configuration
- `terraform.tfvars.example` (never commit actual `.tfvars` with secrets)
- Modules under `modules/` when reusable components are needed

### Step 3: Annotate Decisions

Add inline comments for non-obvious choices — why a specific instance type, why a particular CIDR scheme, why a lifecycle rule. Keep comments terse and technical. Don't explain Terraform concepts; explain *your infrastructure design decisions*.

---

## Project Structure

### Single Project (Small-Medium)

```
project/
├── main.tf                 # Root module — resource composition
├── variables.tf            # Input variables with descriptions, types, validation
├── outputs.tf              # Outputs for downstream consumers
├── versions.tf             # Required providers + Terraform version constraint
├── backend.tf              # Remote state backend configuration
├── locals.tf               # Computed values, naming conventions, common tags
├── data.tf                 # Data sources (existing resources, AMIs, availability zones)
├── terraform.tfvars.example # Variable template — safe to commit
├── .terraform.lock.hcl     # Lock file — always commit this
└── modules/
    ├── networking/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── database/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Multi-Environment (Medium-Large)

```
infrastructure/
├── modules/                    # Shared reusable modules
│   ├── vpc/
│   ├── eks/
│   ├── rds/
│   └── ...
├── environments/
│   ├── dev/
│   │   ├── main.tf            # Calls modules with dev-specific values
│   │   ├── variables.tf
│   │   ├── backend.tf         # Points to dev state bucket
│   │   ├── terraform.tfvars
│   │   └── versions.tf
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
└── global/                     # Resources shared across environments
    ├── iam/
    ├── dns/
    └── state-backend/          # Bootstrap: S3 bucket + DynamoDB for state
```

Prefer directory-based environment separation over workspaces. Workspaces share the same backend config and make it too easy to accidentally apply prod changes. Directories give full isolation with separate state files.

---

## versions.tf

Always pin provider versions and Terraform version:

```hcl
terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}
```

Use `~>` (pessimistic constraint) for providers — allows patch updates but not major/minor breaking changes. Pin Terraform itself to a range that includes your team's minimum version.

---

## backend.tf

Always configure a remote backend. Never use local state for anything beyond personal experiments.

### AWS (S3 + DynamoDB)

```hcl
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"

    # Prevent accidental state operations
    # Use assume_role for cross-account state access
  }
}
```

### GCP (GCS)

```hcl
terraform {
  backend "gcs" {
    bucket = "company-terraform-state"
    prefix = "environments/dev"
  }
}
```

State bucket requirements:
- Versioning enabled (rollback on state corruption)
- Encryption at rest (SSE-S3/SSE-KMS or CMEK)
- Access logging enabled
- Public access blocked
- Locking mechanism (DynamoDB for AWS, built-in for GCS)

---

## locals.tf

Centralize naming conventions and common tags:

```hcl
locals {
  environment = var.environment
  project     = var.project_name
  region      = var.aws_region

  # Consistent naming: {project}-{environment}-{resource}
  name_prefix = "${local.project}-${local.environment}"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Repository  = var.repository_url
    Team        = var.team_name
  }
}
```

Apply `local.common_tags` to every resource that supports tags. Use `merge()` to add resource-specific tags:

```hcl
tags = merge(local.common_tags, {
  Name = "${local.name_prefix}-api"
  Role = "api-server"
})
```

---

## Variable Conventions

### variables.tf

Every variable must have a `description` and explicit `type`. Add `validation` blocks for values that have constraints:

```hcl
variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "instance_type" {
  description = "EC2 instance type for API servers"
  type        = string
  default     = "t3.medium"
}

variable "db_password" {
  description = "RDS master password — pass via TF_VAR_db_password or -var, never in tfvars"
  type        = string
  sensitive   = true
}
```

Rules:
- Never set `default` for sensitive variables — force explicit input
- Mark secrets with `sensitive = true`
- Use `object` types for complex config blocks to enforce structure
- Use `optional()` in object attributes where appropriate

### terraform.tfvars.example

Safe to commit — placeholder values only:

```hcl
# Copy to terraform.tfvars and fill in actual values
# NEVER commit terraform.tfvars — it's in .gitignore

environment    = "dev"
project_name   = "myapp"
aws_region     = "us-east-1"
instance_type  = "t3.medium"
# db_password  = "SET VIA TF_VAR_db_password"
```

---

## Module Design

### When to Create a Module

Create a module when:
- A group of resources is used in 2+ environments or projects
- A component has clear inputs/outputs and internal logic
- You want to enforce patterns (e.g., "every RDS instance must have encryption, backups, and monitoring")

Don't create a module for a single resource with no logic — that's just wrapping the provider for no benefit.

### Module Interface

```hcl
# modules/rds/variables.tf
variable "name" {
  description = "Database identifier"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.2"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20
}

variable "vpc_id" {
  description = "VPC where the database will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the DB subnet group"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect to the database"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

Module rules:
- Accept only what the module needs — don't pass the entire provider config
- Expose connection info via outputs (endpoint, port, security group ID)
- Never hardcode environment-specific values inside a module
- Set sensible defaults but allow overrides

### Module Outputs

```hcl
# modules/rds/outputs.tf
output "endpoint" {
  description = "Database connection endpoint"
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "Database port"
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "Security group ID attached to the database"
  value       = aws_security_group.db.id
}
```

---

## Security Patterns

### IAM — Least Privilege

```hcl
# Specific actions on specific resources — never use "*"
resource "aws_iam_policy" "app_s3_access" {
  name = "${local.name_prefix}-app-s3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.uploads.arn
      }
    ]
  })
}
```

IAM rules:
- Never use `Action: "*"` or `Resource: "*"` in production
- Use conditions to restrict by source IP, VPC, or tag where possible
- Prefer IAM roles over access keys for services
- Use `aws_iam_policy_document` data source for complex policies (composable, type-safe)

### Encryption

Enable encryption everywhere by default:

```hcl
# S3
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# RDS
resource "aws_db_instance" "this" {
  # ...
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn  # Use custom KMS key, not default
}

# EBS
resource "aws_ebs_default_encryption" "this" {
  enabled = true
}
```

### Security Groups

```hcl
# Start with deny-all, add specific rules
resource "aws_security_group" "api" {
  name_prefix = "${local.name_prefix}-api-"
  vpc_id      = var.vpc_id

  # No inline rules — use aws_vpc_security_group_ingress_rule / egress_rule
  # This prevents rule conflicts and makes changes cleaner

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-api" })
}

resource "aws_vpc_security_group_ingress_rule" "api_http" {
  security_group_id = aws_security_group.api.id
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  # Reference another SG — not a CIDR — for internal traffic
  referenced_security_group_id = aws_security_group.alb.id
}
```

---

## Networking Patterns

### VPC

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "${local.name_prefix}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"  # Save cost in non-prod
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # VPC Flow Logs for audit
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_iam_role             = true

  tags = local.common_tags
}
```

Networking rules:
- Always use 3 AZs in production for high availability
- Private subnets for compute/databases, public subnets only for load balancers and NAT gateways
- Use single NAT gateway in dev/staging to save cost, multi-AZ NAT in prod
- Enable VPC Flow Logs for audit trail

---

## Lifecycle Rules

```hcl
resource "aws_db_instance" "this" {
  # ...

  lifecycle {
    # Prevent accidental deletion of production databases
    prevent_destroy = true

    # Don't recreate if password changes externally
    ignore_changes = [password]
  }
}

resource "aws_security_group" "this" {
  name_prefix = "${local.name_prefix}-"

  lifecycle {
    # Create replacement before destroying old one — prevents downtime
    create_before_destroy = true
  }
}
```

Use `prevent_destroy` on stateful resources (databases, S3 buckets, EFS). Use `create_before_destroy` on resources where replacement causes downtime (security groups, launch templates).

---

## Data Sources

Use data sources to reference existing resources instead of hardcoding IDs:

```hcl
# Current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Existing resources
data "aws_vpc" "existing" {
  tags = { Name = "main-vpc" }
}
```

Never hardcode AMI IDs, account IDs, or resource ARNs — always use data sources.

---

## .gitignore

```
# Terraform state — never commit
*.tfstate
*.tfstate.*

# Variable files with secrets
*.tfvars
!terraform.tfvars.example

# Provider plugins — downloaded on init
.terraform/

# Crash logs
crash.log
crash.*.log

# Plan files — may contain secrets
*.tfplan

# Override files — local developer overrides
override.tf
override.tf.json
*_override.tf
*_override.tf.json
```

---

## Output Checklist

Before delivering, verify every item:

- [ ] Provider and Terraform versions pinned in `versions.tf`
- [ ] Remote backend configured with encryption and locking
- [ ] All variables have `description` and `type`
- [ ] Sensitive variables marked with `sensitive = true`
- [ ] `terraform.tfvars.example` provided (no real secrets)
- [ ] Common tags defined in `locals.tf` and applied everywhere
- [ ] Consistent naming convention using `local.name_prefix`
- [ ] IAM follows least privilege (no `*` actions or resources)
- [ ] Encryption enabled on all storage (S3, RDS, EBS, EFS)
- [ ] Security groups use separate rules (not inline)
- [ ] `prevent_destroy` on stateful resources
- [ ] `create_before_destroy` on resources where replacement causes downtime
- [ ] No hardcoded IDs — data sources used for existing resources
- [ ] `.gitignore` includes state files, tfvars, .terraform/, plan files
- [ ] Inline comments explain infrastructure design decisions
