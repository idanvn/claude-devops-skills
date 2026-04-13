<div align="center">

# claude-devops-skills

**Three Claude Code skills that generate production-hardened Docker, Terraform, and Monitoring configs.**

43-item combined checklist. Every config. Every time.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Skills-blueviolet)](https://docs.anthropic.com/en/docs/claude-code/overview)
[![Docker](https://img.shields.io/badge/Docker-Compose_%7C_Multi--stage-2496ED?logo=docker&logoColor=white)](#docker-generator)
[![Terraform](https://img.shields.io/badge/Terraform-AWS_%7C_GCP_%7C_Azure-844FBA?logo=terraform&logoColor=white)](#terraform-generator)
[![Prometheus](https://img.shields.io/badge/Monitoring-Prometheus_%7C_Grafana-E6522C?logo=prometheus&logoColor=white)](#monitoring-generator)

</div>

---

## The Problem

You write a Dockerfile. It works. It runs as root. No healthcheck. No init process. Layers in the wrong order. Secrets baked into the image.

You write Terraform. It applies. No state locking. No encryption. IAM policy has `"Action": "*"`. No `prevent_destroy` on the database.

You configure alerting. It fires. At 3am. For a deploy blip. Every time. Your team starts ignoring alerts.

These aren't beginner mistakes. They're the things senior engineers forget at 2pm on a Tuesday because they're juggling 14 other things.

---

## What This Is

Three Claude Code skills that encode senior-level DevOps knowledge into repeatable prompt engineering. Describe what you need in plain English — get production-ready configs that pass a **43-item combined checklist**.

```
You: "I need Docker for a FastAPI app with Celery, PostgreSQL, Redis, and Nginx. Production-ready."

Claude: generates 6 files — multi-stage Dockerfile, docker-compose with healthchecks,
        security hardening, network separation, resource limits, nginx.conf, .dockerignore,
        .env.example. Every file annotated with architectural decisions.
```

---

## Skills

| Skill | Command | Generates | Checklist |
|:------|:--------|:----------|:---------:|
| **Docker** | `/docker-generator` | Dockerfiles, Compose, .dockerignore, nginx configs | 14 items |
| **Terraform** | `/terraform-generator` | Modules, backends, IAM, networking, multi-env | 15 items |
| **Monitoring** | `/monitoring-generator` | Prometheus rules, Grafana dashboards, AlertManager | 14 items |

---

## Quick Start

```bash
git clone https://github.com/idanvn/claude-devops-skills.git
cd claude-devops-skills
./install.sh
```

Restart Claude Code. Done.

---

## What "Production-Hardened" Actually Means

Not a vague claim. Here's exactly what each skill enforces:

### Docker — 14 checks

```
 ✓ Base images pinned to minor version         ✓ No secrets baked into images
 ✓ Non-root user with fixed UID/GID            ✓ depends_on with service_healthy
 ✓ Init process (tini/dumb-init)               ✓ Inline comments on decisions
 ✓ Healthchecks for every service              ✓ Layer order optimized for cache
 ✓ Resource limits (memory + CPU)              ✓ .env.example alongside compose
 ✓ read_only, no-new-privileges, cap_drop ALL  ✓ Multi-arch when needed
 ✓ Log rotation configured                     ✓ .dockerignore deny-all pattern
```

### Terraform — 15 checks

```
 ✓ Provider + Terraform versions pinned        ✓ Encryption on all storage
 ✓ Remote backend with encryption + locking    ✓ Security groups — separate rules
 ✓ All variables: description + type           ✓ prevent_destroy on stateful resources
 ✓ Sensitive vars marked sensitive = true      ✓ create_before_destroy on replaceable
 ✓ terraform.tfvars.example provided           ✓ Data sources over hardcoded IDs
 ✓ Common tags via locals.tf                   ✓ .gitignore covers state + secrets
 ✓ Consistent naming (project-env-resource)    ✓ Inline comments on design decisions
 ✓ IAM least privilege (no * actions)
```

### Monitoring — 14 checks

```
 ✓ Every alert has for duration (no flapping)  ✓ Dashboards use template variables
 ✓ severity + team + summary + runbook_url     ✓ Dashboards reference recording rules
 ✓ Critical alerts pass the 3am test           ✓ ServiceMonitors drop unused metrics
 ✓ Warning alerts are actionable               ✓ SLOs use multi-window burn rate
 ✓ Recording rules pre-compute queries         ✓ Slack messages include runbook links
 ✓ Recording rules: level:metric:operations    ✓ send_resolved: true on all receivers
 ✓ AlertManager separates critical/warning     ✓ Inhibition suppresses duplicates
```

---

## Real Examples

### Docker

**Prompt:**
```
I need Docker for a FastAPI app with Celery workers, PostgreSQL 16,
Redis 7, and Nginx as reverse proxy. Production-ready. Python 3.12.
```

**Output: 6 files**

| File | What It Does |
|:-----|:-------------|
| `Dockerfile` | Multi-stage: python:3.12-slim builder → slim runtime, non-root, dumb-init |
| `docker-compose.yml` | 5 services, YAML anchors for security/logging, internal network |
| `docker-compose.override.yml` | Dev: hot-reload, debug ports, bind mounts |
| `docker-compose.prod.yml` | Hardened: read_only, cap_drop ALL, resource limits |
| `.dockerignore` | Deny-all allowlist |
| `.env.example` | Every required env var documented |

Redis configured with `--save "" --appendonly no` — it's a cache, not a store. The database unique constraint is the safety net. Persistence would be wasted I/O.

---

### Terraform

**Prompt:**
```
I need Terraform for a production AWS setup: VPC with 3 AZs, EKS cluster,
RDS PostgreSQL, ElastiCache Redis, S3 for uploads. Multi-environment.
```

**Output: 44 files across 3 environments**

```
infrastructure/
├── global/state-backend/     # Bootstrap: S3 + DynamoDB for state
├── modules/
│   ├── vpc/                  # 3-AZ, flow logs, EKS subnet tags
│   ├── eks/                  # 1.31, IRSA for EBS CSI + LB controller
│   ├── rds/                  # PostgreSQL 16, enhanced monitoring, Secrets Manager
│   ├── elasticache/          # Redis 7, auth token in Secrets Manager
│   └── s3/                   # KMS encryption, versioning, lifecycle, CORS
└── environments/
    ├── dev/                  # t3.micro, single NAT, public endpoint
    ├── staging/              # t3.small, 2-node Redis, PI enabled
    └── prod/                 # r6g Graviton2, Multi-AZ, 3-node Redis, private endpoint
```

Graviton2 in prod for RDS and ElastiCache — better price-to-memory ratio. Single NAT in dev saves ~$100/AZ/month.

---

### Monitoring

**Prompt:**
```
Full monitoring for a payment webhook service with PostgreSQL and Redis
on Kubernetes. Prometheus rules, Grafana dashboard, AlertManager routing.
```

**Output: 4 files, 9 alerts, 11-panel dashboard**

| File | Contents |
|:-----|:---------|
| `recording-rules.yaml` | Request rate, error rate, p50/p95/p99, cache hit rate, DB pool utilization |
| `alerting-rules.yaml` | 9 alerts: p99 latency, error rate, traffic drop, cache hit rate, DB pool, crash-loop, memory, replicas |
| `service-monitor.yaml` | 15s scrape, drops unused go_memstats_* and net_conntrack_* |
| `grafana/dashboard.json` | 11 panels: RED metrics, cache hit/miss, DB connections, pod resources |

High 4xx alert set as warning (not critical) — it signals HMAC misconfiguration, not an outage. Cache hit rate alert at 85% because below that, Redis isn't doing its job and the database absorbs unnecessary load.

---

### All Three Together

One prompt. Full stack.

**Prompt:**
```
I'm building a Go microservice that processes payment webhooks.
PostgreSQL for storage, Redis for idempotency cache. Runs on EKS.
Give me the full setup — Docker, Terraform, and monitoring.
```

The skills coordinated and made architectural decisions together:

| Decision | Reasoning |
|:---------|:----------|
| Redis: `--save "" --appendonly no` | Idempotency cache — DB unique constraint is the real safety net |
| IRSA scoped to `payments/payment-webhook` SA | No cluster-wide access leak |
| Egress locked to 5432, 6379, 443 only | Postgres, Redis, Secrets Manager + payment callbacks |
| `maxUnavailable: 0` in rolling update | Payment webhooks can't drop acknowledgments |
| Scale-up: +4 pods/30s | Payment provider timeouts are strict |
| Scale-down: 25%/min, 300s cooldown | Retries arrive in waves after spikes |

---

## What's Inside

<details>
<summary><b>docker-generator</b> — SKILL.md (~370 lines) + common-pitfalls.md (~160 lines)</summary>

**SKILL.md covers:** Base image selection table (6 stacks: Node, Python, Go, Java, Rust, .NET), layer optimization with full examples, multi-stage build patterns, security hardening (6 rules), init process handling, Compose production service template, healthcheck table (9 services), network separation, volumes, multi-environment compose layering, multi-arch builds with buildx, .env.example generation, deny-all .dockerignore, 14-item output checklist.

**common-pitfalls.md covers:** Alpine+glibc incompatibility, DNS resolution in Compose, volume permissions, build context size, signal handling, healthcheck timing by service type, layer cache invalidation, secrets leaking into layers, timezone issues, OOM kills with JVM/Node/Python fixes.
</details>

<details>
<summary><b>terraform-generator</b> — SKILL.md (~370 lines) + common-pitfalls.md (~250 lines)</summary>

**SKILL.md covers:** Project structure (single + multi-environment), versions.tf with pessimistic constraints, remote backends (S3+DynamoDB, GCS), locals.tf naming conventions and tagging strategy, variable conventions with validation blocks, module design patterns (when to create, interface rules, outputs), IAM least privilege, encryption everywhere, security groups with separate rules, VPC networking (3 AZs, public/private, NAT strategy), lifecycle rules, data sources, .gitignore, 15-item output checklist.

**common-pitfalls.md covers:** State lock stuck, provider version conflicts, dependency cycles, count vs for_each, sensitive output leaks, destroy-then-create downtime, state drift detection, module version pinning, importing existing resources, cross-account/cross-region patterns with provider aliases.
</details>

<details>
<summary><b>monitoring-generator</b> — SKILL.md (~420 lines) + common-pitfalls.md (~200 lines)</summary>

**SKILL.md covers:** RED method alerts (Rate, Errors, Duration), USE method alerts (Utilization, Saturation, Errors), database alerts (PostgreSQL connections/replication/deadlocks, Redis memory/evictions), Kubernetes alerts (CrashLoopBackOff, replica mismatch, node not ready, PVC), predictive alerts (disk fill in 24h), recording rules with naming convention, AlertManager routing tree with PagerDuty/Slack/inhibition, Grafana dashboard structure and JSON conventions, provisioning YAML, ServiceMonitor/PodMonitor CRDs with metric dropping, SLI/SLO with multi-window burn rate, 14-item output checklist.

**common-pitfalls.md covers:** Cardinality explosion, alert fatigue, histogram bucket design, rate() on counter resets, absent() for missing metrics, dashboard query performance, label conflicts on federation, recording rule staleness, Grafana variable load time, phantom alerts on deploy.
</details>

---

## Installation

### All skills (recommended)

```bash
git clone https://github.com/idanvn/claude-devops-skills.git
cd claude-devops-skills
./install.sh
# Restart Claude Code
```

### Single skill

```bash
mkdir -p ~/.claude/skills/docker-generator/references
cp -r docker-generator/* ~/.claude/skills/docker-generator/
# Restart Claude Code
```

### Per-project (team sharing)

```bash
# Copy into your repo — anyone who clones gets the skill
cp -r docker-generator .claude/skills/docker-generator
git add .claude/skills
git commit -m "Add Docker skill for Claude Code"
```

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) CLI
- Claude Pro, Max, or API access

---

## Contributing

PRs welcome. Follow the existing structure:

```
skill-name/
├── SKILL.md                    # Frontmatter + instructions
└── references/
    └── common-pitfalls.md      # Edge cases + fixes
```

Rules: every skill needs an output checklist. Every alert must pass the 3am test. No fluff in documentation.

---

## License

[MIT](LICENSE) — use it, fork it, share it.
