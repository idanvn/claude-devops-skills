---
name: docker-generator
description: >
  Generate production-hardened Dockerfiles and Docker Compose configurations from scratch.
  Use this skill whenever the user asks to create, generate, or write a Dockerfile, docker-compose.yml,
  multi-container setup, or containerized application configuration. Also trigger when the user describes
  an application stack (e.g., "I need a Node app with Redis and Postgres") and wants it containerized,
  mentions Docker in the context of setting up a new project or migrating to containers, asks for a
  development or production environment with containers, or wants to containerize an existing application.
  Covers single-service Dockerfiles, multi-stage builds with layer optimization, Docker Compose with
  networking/volumes/healthchecks/resource limits, .dockerignore files, and init process handling.
  Target audience is advanced DevOps engineers — skip the basics, focus on optimized layers, security
  hardening, production patterns, and operational concerns.
---

# Docker Generator Skill

Generate production-hardened Docker configurations. The audience knows Docker well — they want optimized, secure, operationally sound configs, not tutorials.

## Reference Files

- `references/common-pitfalls.md` — Read when the stack involves edge cases (Alpine + native deps, JVM memory, MongoDB replica sets, Nginx DNS re-resolution). Also useful when the user reports issues with a generated config.

## Workflow

### Step 1: Identify the Stack

Extract from the user's request (infer where possible, ask only when genuinely ambiguous):

- **Language/runtime & version** — Node 20, Python 3.12, Go 1.22, Java 21, etc.
- **Services** — databases, caches, queues, proxies, monitoring
- **Target environment** — dev, staging, production, or multi-environment
- **Constraints** — private registries, air-gapped builds, specific base image policies, ARM/multi-arch

### Step 2: Generate Files

Produce all relevant files. Every Dockerfile gets a matching `.dockerignore`. Multi-service stacks get a `docker-compose.yml`. If the user needs both dev and prod, generate separate compose files with a shared base (`docker-compose.yml` + `docker-compose.override.yml` for dev, `docker-compose.prod.yml` for production).

Save all generated files to the output directory.

### Step 3: Annotate Decisions

Add inline comments for non-obvious choices — base image rationale, layer ordering tradeoffs, why a specific healthcheck interval. Keep comments terse and technical. Don't explain Docker concepts; explain *your architectural decisions*.

---

## Dockerfile Standards

### Base Image Selection

Always pin to a specific minor version. Never use `latest`.

| Stack | Build Stage | Production Runtime |
|-------|------------|-------------------|
| Node.js | `node:20.11-slim` | `gcr.io/distroless/nodejs20-debian12` or `node:20.11-alpine` |
| Python | `python:3.12-slim-bookworm` | Same slim image with virtualenv copied |
| Go | `golang:1.22-bookworm` | `gcr.io/distroless/static-debian12` or `scratch` |
| Java | `eclipse-temurin:21-jdk-jammy` | `eclipse-temurin:21-jre-alpine` or `gcr.io/distroless/java21-debian12` |
| Rust | `rust:1.77-slim-bookworm` | `gcr.io/distroless/cc-debian12` or `debian:bookworm-slim` |
| .NET | `mcr.microsoft.com/dotnet/sdk:8.0` | `mcr.microsoft.com/dotnet/aspnet:8.0-alpine` |

When the user's org has a base image policy or private registry, adapt accordingly.

### Layer Optimization

Layer order matters for cache efficiency. The principle: things that change least go first.

```dockerfile
FROM node:20.11-slim AS base

# System deps — almost never change
RUN apt-get update && apt-get install -y --no-install-recommends \
      dumb-init ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Non-root user with fixed UID/GID for consistency across environments
RUN groupadd -g 1001 app && useradd -u 1001 -g app -s /bin/false -d /app app

WORKDIR /app

# Dependency manifests first — change occasionally
COPY package.json package-lock.json ./

# Install cached unless manifests changed; clean cache in same layer
RUN npm ci --omit=dev && npm cache clean --force

# App code — changes every build
COPY --chown=app:app . .

USER app
EXPOSE 3000
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
```

Key points:
- Combine `apt-get update` + `install` + cache cleanup in one `RUN` to avoid stale cache layers
- Use `COPY --chown` to avoid extra `chown` layers
- `ENTRYPOINT` + `CMD` split allows overriding CMD in compose without losing init process

### Multi-Stage Builds

Always use multi-stage for compiled languages. For interpreted languages, use multi-stage when there are build-time-only dependencies (TypeScript compilation, asset bundling, native module builds).

Go example (produces a ~5MB static binary image):
```dockerfile
FROM golang:1.22-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -trimpath -o /bin/app ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /bin/app /app
EXPOSE 8080
ENTRYPOINT ["/app"]
```

Python with virtualenv isolation:
```dockerfile
FROM python:3.12-slim-bookworm AS builder
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim-bookworm AS runtime
RUN groupadd -g 1001 app && useradd -u 1001 -g app -s /bin/false -d /app app
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
WORKDIR /app
COPY --chown=app:app . .
USER app
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "app:create_app()"]
```

### Security Hardening

Apply all of these by default:

1. **Non-root execution** — dedicated user with fixed UID/GID (1001). For distroless use built-in `nonroot`.
2. **Read-only filesystem** — `read_only: true` in compose, `tmpfs` for writable dirs (`/tmp`, `/var/run`).
3. **No new privileges** — `security_opt: [no-new-privileges:true]` in compose.
4. **Drop capabilities** — `cap_drop: [ALL]`, then `cap_add` only what's needed.
5. **No secrets in image** — runtime env vars or Docker secrets. Never `COPY .env`.
6. **Minimal attack surface** — distroless or alpine for runtime when possible.

### Init Process

Containers need an init process for signal forwarding and zombie reaping. Without it, SIGTERM won't propagate and containers hang during shutdown. Options:

1. `init: true` in compose (uses `tini` via Docker, simplest)
2. `dumb-init` installed in image and used as ENTRYPOINT
3. `tini` installed directly

Always include one. Prefer `init: true` in compose unless the image will run outside compose (K8s, ECS) — then bake dumb-init/tini into the image.

---

## Docker Compose Standards

### Production Service Template

Every production service should include all of these operational concerns:

```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
      target: production
    image: registry.example.com/api:${TAG:-latest}
    init: true
    restart: unless-stopped
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp:size=64m
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 512m
          cpus: "1.0"
        reservations:
          memory: 256m
          cpus: "0.25"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    env_file:
      - .env
    depends_on:
      db:
        condition: service_healthy
```

### Healthchecks by Service Type

Choose checks that verify actual functionality, not just process liveness:

| Service | Healthcheck |
|---------|------------|
| HTTP API | `curl -f http://localhost:<port>/health` or `wget --spider -q` |
| PostgreSQL | `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB` |
| MySQL | `mysqladmin ping -h localhost -u root -p$MYSQL_ROOT_PASSWORD` |
| Redis | `redis-cli ping` |
| MongoDB | `mongosh --eval "db.adminCommand('ping')"` |
| RabbitMQ | `rabbitmq-diagnostics -q check_running` |
| Kafka | `kafka-broker-api-versions --bootstrap-server localhost:9092` |
| Elasticsearch | `curl -f http://localhost:9200/_cluster/health?wait_for_status=yellow` |
| Nginx | `curl -f http://localhost:80/healthz` (add healthz location block) |

For distroless images without curl: write a small healthcheck binary or use the app's own CLI.

### Networking

Separate frontend (exposed) and backend (internal) networks. Only attach services to networks they actually need:

```yaml
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true    # no external access

services:
  proxy:
    networks: [frontend, backend]
  api:
    networks: [backend]
  db:
    networks: [backend]
```

### Volumes

- Named volumes for databases and persistent state — never bind mounts in production
- For dev: bind mounts for hot-reload are fine
- Always set volume driver options appropriate for the environment

```yaml
volumes:
  pgdata:
    driver: local
  redis-data:
    driver: local
```

### Multi-Environment Compose Layering

Use compose file layering for environment separation:

- `docker-compose.yml` — base service definitions shared across environments
- `docker-compose.override.yml` — dev overrides (auto-loaded): bind mounts, debug ports, hot-reload
- `docker-compose.prod.yml` — production: resource limits, restart policies, logging, image tags

```bash
# Dev (auto-loads override)
docker compose up

# Production
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## Multi-Architecture Builds

When the user mentions ARM, multi-arch, or targets mixed infrastructure (e.g., AWS Graviton + x86), include a `docker-bake.hcl` or document the buildx workflow:

```bash
# Build and push multi-arch image
docker buildx create --name multiarch --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag registry.example.com/app:${TAG} \
  --push .
```

In the Dockerfile, avoid architecture-specific assumptions:
- Don't hardcode `GOARCH=amd64` — use `TARGETARCH` build arg (injected automatically by buildx)
- For Go: `RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build ...`
- For native deps: use `apt-get` over statically linked binaries that may be x86-only
- Test both architectures in CI before pushing multi-arch manifests

---

## .env.example

Always generate a `.env.example` alongside compose files. It documents every required environment variable with placeholder values and comments. The actual `.env` stays in `.gitignore`.

```bash
# --- Database ---
POSTGRES_USER=app
POSTGRES_PASSWORD=changeme_in_production
POSTGRES_DB=appdb

# --- Redis ---
REDIS_MAXMEMORY=256mb

# --- App ---
API_PORT=8000
NODE_ENV=production

# --- Registry (for prod deploys) ---
REGISTRY=registry.example.com
TAG=latest
```

---

## .dockerignore

Use a deny-all approach — safer than trying to enumerate exclusions:

```
# Deny everything
**

# Allow only what the build needs
!src/
!package.json
!package-lock.json
!tsconfig.json

# Adapt per language:
# !requirements.txt
# !go.mod
# !go.sum
# !Cargo.toml
# !Cargo.lock
```

---

## Output Checklist

Before delivering, verify every item:

- [ ] Base images pinned to minor version (no `latest`)
- [ ] Non-root user with fixed UID/GID
- [ ] Init process present (`init: true` or dumb-init/tini)
- [ ] Healthchecks for every service
- [ ] Resource limits set (memory + CPU)
- [ ] Security: read_only, no-new-privileges, cap_drop ALL
- [ ] Log rotation configured
- [ ] .dockerignore uses deny-all pattern
- [ ] No secrets baked into images
- [ ] `depends_on` uses `condition: service_healthy`
- [ ] Inline comments explain non-obvious decisions
- [ ] Layer order optimized for cache hits
- [ ] `.env.example` generated alongside compose files
- [ ] Multi-arch considered if user targets mixed infrastructure
