# devops-skills

Three Claude Code skills that generate production-hardened Docker, Terraform, and Monitoring configurations.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## The Problem

Every DevOps engineer writes Docker, Terraform, and monitoring configs from scratch. Every time, something gets missed — a healthcheck, a security hardening flag, a recording rule, a lifecycle policy. Code reviews catch some of it. Production incidents catch the rest.

These skills encode the checklist that experience built into reusable prompt engineering. Run the command, get the config that passes review.

---

## What This Is

Three Claude Code skills that encode senior-level DevOps knowledge into reusable slash commands. They generate production-ready configs that pass a combined 43-item checklist across Docker (14 items), Terraform (15 items), and Monitoring (14 items).

You describe your stack. The skill produces every file — with inline comments explaining non-obvious decisions, not tutorials explaining what Docker is.

---

## Skills

| Skill | Slash Command | What It Generates |
|-------|--------------|-------------------|
| docker-generator | `/docker-generator` | Dockerfiles (multi-stage), Docker Compose (dev + prod), `.dockerignore`, `.env.example` |
| terraform-generator | `/terraform-generator` | Module structures, environment separation, state backends, IAM, networking, compute |
| monitoring-generator | `/monitoring-generator` | Prometheus alerting + recording rules, Grafana dashboards (JSON), AlertManager routing, ServiceMonitors |

---

## What "Production-Hardened" Means

Not a vague claim. These are the actual checklist items each skill enforces before delivery.

### Docker (14 items)

- Base images pinned to minor version — no `latest`
- Non-root user with fixed UID/GID (1001)
- Init process present (`dumb-init`/`tini` or `init: true`)
- Healthchecks on every service (functionality check, not process check)
- Memory and CPU limits on every container
- `read_only: true` filesystem with `tmpfs` for writable dirs
- `no-new-privileges:true` security option
- `cap_drop: ALL` — add back only what's needed
- Log rotation configured (`max-size`, `max-file`)
- `.dockerignore` uses deny-all pattern (`**` then allow-list)
- No secrets baked into images
- `depends_on` uses `condition: service_healthy`
- Layer order optimized for cache hits (least-changing layers first)
- `.env.example` generated alongside every compose file

### Terraform (15 items)

- Provider and Terraform versions pinned in `versions.tf`
- Remote backend with encryption and locking (S3+DynamoDB or GCS)
- All variables have `description` and explicit `type`
- Sensitive variables marked with `sensitive = true`
- `terraform.tfvars.example` provided — no real secrets committed
- Common tags in `locals.tf` applied to every tagged resource
- Consistent naming via `local.name_prefix`
- IAM follows least privilege — no `*` actions or resources
- Encryption enabled on all storage (S3, RDS, EBS, EFS)
- Security groups use separate rule resources (not inline)
- `prevent_destroy` on stateful resources
- `create_before_destroy` on resources where replacement causes downtime
- Data sources for existing resources — no hardcoded IDs
- `.gitignore` covers state files, tfvars, `.terraform/`, plan files
- Inline comments explain infrastructure design decisions

### Monitoring (14 items)

- Every alert has a `for` duration — no flapping on transient spikes
- Every alert has `severity`, `team`, `summary`, `description`, `runbook_url`
- Critical alerts pass the 3am test — worth waking someone up
- Warning alerts are actionable within business hours
- Recording rules pre-compute expensive dashboard/alert queries
- Recording rules follow `level:metric:operations` naming convention
- AlertManager routing separates critical (PagerDuty) from warning (Slack)
- Inhibition rules suppress warnings when critical fires for the same alert
- Grafana dashboards use template variables (`$service`, `$namespace`)
- Dashboards reference recording rules, not raw queries
- ServiceMonitors drop high-cardinality metrics at scrape time
- SLOs use multi-window burn rate approach
- Slack messages include runbook + dashboard links
- `send_resolved: true` on all receivers

---

## Quick Start

```bash
git clone https://github.com/your-org/devops-skills.git
cd devops-skills
./install.sh
```

Restart Claude Code. All three slash commands are active.

---

## Example Usage

### Docker

**Prompt:**
```
/docker-generator FastAPI app with Celery workers, PostgreSQL, Redis, and Nginx reverse proxy.
Production + dev environments.
```

**Output:** 6 files — `Dockerfile` (multi-stage Python build with virtualenv isolation), `docker-compose.yml` (base), `docker-compose.override.yml` (dev with bind mounts and debug ports), `docker-compose.prod.yml` (resource limits, restart policies, log rotation), `.dockerignore` (deny-all), `.env.example` (all required vars documented).

Every service has healthchecks, resource limits, and reads-only filesystem. Celery worker uses the same image as the API with a different `CMD`. Nginx has a `/healthz` location block. `depends_on` chains use `service_healthy` conditions throughout.

### Terraform

**Prompt:**
```
/terraform-generator AWS infrastructure: VPC, EKS cluster, RDS PostgreSQL, ElastiCache Redis, S3 bucket for uploads.
Three environments: dev, staging, prod.
```

**Output:** 44 files across 3 environments — shared modules for VPC, EKS, RDS, ElastiCache, and S3; environment directories each with `main.tf`, `variables.tf`, `backend.tf`, `versions.tf`, `terraform.tfvars.example`; `global/state-backend/` to bootstrap the S3+DynamoDB state infrastructure; `.gitignore`.

Single NAT gateway in dev/staging, multi-AZ in prod. `prevent_destroy = true` on RDS and S3. KMS encryption on all storage. VPC Flow Logs enabled. IAM roles scoped to specific S3 prefixes and EKS namespaces.

### Monitoring

**Prompt:**
```
/monitoring-generator Payment webhook service. Monitors HTTP endpoints, PostgreSQL, and Redis.
Alerts to PagerDuty (critical) and Slack (warnings). kube-prometheus-stack.
```

**Output:** Recording rules (p50/p95/p99 latency pre-computed, error rate pre-computed), 9 alerts (high error rate, high latency p99, traffic drop, PG connection saturation, PG replication lag, Redis memory, Redis eviction rate, pod crash-looping, PVC almost full), `ServiceMonitor` with cardinality reduction, AlertManager config with PagerDuty + two Slack channels + inhibition rules, Grafana dashboard JSON with RED metrics, DB panels, and deployment annotations.

---

## Combined Example

One session, one stack, all three skills:

```
/docker-generator Payment webhook service: Python FastAPI, Celery, PostgreSQL, Redis, Nginx.
Production + dev.

/terraform-generator AWS infrastructure for the payment service: EKS, RDS, ElastiCache, S3.
Staging and prod environments.

/monitoring-generator Monitoring for the payment webhook service. HTTP, Postgres, Redis, K8s pods.
PagerDuty for critical, Slack #payments-alerts for warnings.
```

End result: containerized application with production-hardened Dockerfiles, Terraform that provisions the full AWS stack from scratch, and a monitoring layer with alerts calibrated to payment service SLAs — recording rules, 9 alerts, `ServiceMonitor`, Grafana dashboard — all generated in one session.

---

## What's Inside Each Skill

### docker-generator

`SKILL.md` — 369 lines covering base image selection by runtime (Node, Python, Go, Java, Rust, .NET), multi-stage build patterns, layer optimization order, security hardening checklist, Docker Compose production template, healthcheck commands by service type, network segmentation, multi-environment compose layering, and the 14-item output checklist.

`references/common-pitfalls.md` — 162 lines documenting known failure modes: Alpine + native dependency issues, JVM memory in containers, MongoDB replica set initialization in compose, Nginx upstream DNS re-resolution, and more.

### terraform-generator

`SKILL.md` — 580 lines covering project structures for single and multi-environment setups, `versions.tf` pinning strategy, backend configuration (AWS S3+DynamoDB, GCP GCS), `locals.tf` naming conventions and tagging, variable conventions with `sensitive` and `validation`, module design principles, IAM least-privilege patterns, encryption configuration for S3/RDS/EBS, security group rules (separate resources, not inline), VPC with multi-AZ NAT, lifecycle rules, and the 15-item output checklist.

`references/common-pitfalls.md` — 252 lines covering state migration pitfalls, multi-account provider configuration, provider version conflicts, workspace vs directory tradeoffs, and common plan/apply failure patterns.

### monitoring-generator

`SKILL.md` — 602 lines covering Prometheus alerting rule structure, alert design principles (the 3am test, severity levels), RED method alerts for services, USE method alerts for infrastructure, database alerts (PostgreSQL, Redis), Kubernetes alerts (crash-loop, deployment mismatch, node not ready, PVC full), recording rule naming conventions, AlertManager routing tree design, Grafana dashboard structure and provisioning, `ServiceMonitor`/`PodMonitor` with metric relabeling, SLI/SLO definitions with multi-window burn rate, and the 14-item output checklist.

`references/common-pitfalls.md` — 212 lines covering cardinality explosion patterns, alert fatigue causes, histogram bucket design, high-cardinality label sources, and Grafana performance issues.

---

## Installation Options

### All skills (recommended)

```bash
./install.sh
```

Installs all three skills to `~/.claude/skills/`. Restart Claude Code.

### Single skill

```bash
SKILLS_DIR="${HOME}/.claude/skills"
mkdir -p "${SKILLS_DIR}/docker-generator/references"
cp -r docker-generator/* "${SKILLS_DIR}/docker-generator/"
```

### Per-project install

Copy a skill directory into `.claude/skills/` at the project root. Claude Code picks it up automatically for that project.

```
your-repo/
└── .claude/
    └── skills/
        └── docker-generator/
            ├── SKILL.md
            └── references/
                └── common-pitfalls.md
```

---

## Contributing

Bug reports, improved checklist items, and new reference pitfalls are welcome. Open an issue or pull request.

If you add a new skill, follow the same structure: `SKILL.md` with a frontmatter block, a workflow section, standards sections, and an output checklist. Add a `references/common-pitfalls.md` for failure modes that aren't obvious from the main skill.

---

## License

MIT. See [LICENSE](LICENSE).
