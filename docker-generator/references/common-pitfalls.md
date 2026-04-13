# Common Docker Pitfalls — Reference

Read this file when troubleshooting or when the generated config involves edge cases listed below.

## Table of Contents
1. Alpine + glibc
2. DNS Resolution in Compose
3. Volume Permissions
4. Build Context Size
5. Signal Handling
6. Health Check Timing
7. Layer Cache Invalidation
8. Secrets Leaking into Layers
9. Timezone Issues
10. OOM Kills

---

## 1. Alpine + glibc

**Problem**: Alpine uses musl libc, not glibc. Applications compiled against glibc (most prebuilt binaries, Python packages with C extensions like numpy/pandas, Node native addons) may crash or segfault on Alpine.

**When it bites**: Python data science stacks, Node.js with native bindings (bcrypt, sharp), Java with JNI, any precompiled binary.

**Fix options**:
- Use `-slim` (Debian-based) instead of `-alpine` for the runtime image
- For Go: compile with `CGO_ENABLED=0` — fully static binary works on Alpine/scratch/distroless
- For Python: use `--only-binary=:all:` with pip to get manylinux wheels, or stick to slim
- For Node: rebuild native deps inside Alpine (`npm rebuild`) — but this adds build time

**Rule of thumb**: If the stack has native/compiled dependencies, default to `-slim-bookworm`. Use Alpine only for Go static binaries, Redis, Nginx, and other pure-C software that natively supports musl.

---

## 2. DNS Resolution in Compose

**Problem**: Container DNS resolves service names to IPs at startup. If a dependent service restarts and gets a new IP, the connection breaks.

**Common symptom**: "Connection refused" after a service restart, even though the service is healthy.

**Fix**:
- Use `depends_on` with `condition: service_healthy` — ensures services start in order
- Configure connection pools with retry logic in the application
- For Nginx upstream: use `resolver 127.0.0.11 valid=10s;` (Docker's embedded DNS) and set the upstream as a variable to force re-resolution:
  ```nginx
  resolver 127.0.0.11 valid=10s;
  set $upstream api:8000;
  proxy_pass http://$upstream;
  ```

---

## 3. Volume Permissions

**Problem**: Named volumes created by Docker are owned by root. If the container runs as non-root (UID 1001), the app can't write to the volume on first run.

**Common symptom**: "Permission denied" on first container start, works after manual `chown`.

**Fix options**:
- Use an init script or entrypoint wrapper that fixes permissions before dropping to the app user
- In the Dockerfile, create the mount target directory and chown it before the `VOLUME` instruction
- For PostgreSQL/MongoDB: their official images handle this internally — don't fight it
- For custom apps: `RUN mkdir -p /data && chown app:app /data` in the Dockerfile

---

## 4. Build Context Size

**Problem**: Docker sends the entire build context to the daemon before building. A missing or weak `.dockerignore` means sending `.git/`, `node_modules/`, build artifacts, and data files — potentially gigabytes.

**Symptom**: `docker build` takes forever before any layer runs; "Sending build context to Docker daemon  2.1GB".

**Fix**: Always use deny-all `.dockerignore` pattern (`**` then `!` allowlist). This eliminates the problem entirely.

---

## 5. Signal Handling

**Problem**: PID 1 in a container doesn't get default signal handlers from the kernel. Without an init process, SIGTERM is ignored and `docker stop` waits 10s then SIGKILL.

**Symptom**: Slow container shutdowns (always exactly 10 seconds), data corruption on ungraceful stops.

**Fix**: Always include an init process. In compose: `init: true`. In Dockerfile: `ENTRYPOINT ["dumb-init", "--"]` or `ENTRYPOINT ["tini", "--"]`.

---

## 6. Health Check Timing

**Problem**: `start_period` is often set too low. JVM apps, database migrations, and Next.js builds need significant startup time. If the health check fails during startup, the container is marked unhealthy and dependents won't start.

**Guidance**:
| Service Type | Recommended start_period |
|-------------|------------------------|
| Static binaries (Go, Rust) | 5-10s |
| Node.js / Python | 10-20s |
| JVM (Spring Boot) | 30-90s |
| Database with migrations | 30-60s |
| Elasticsearch | 60-120s |

Set `start_period` generously — it only affects initial startup, not ongoing checks.

---

## 7. Layer Cache Invalidation

**Problem**: Any change to a layer invalidates all subsequent layers. Copying `package.json` and application code in the same `COPY . .` means every code change re-runs `npm install`.

**Fix**: Always copy dependency manifests before application code:
```dockerfile
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
```

**Subtle trap**: `COPY . .` also copies files that change on every build (timestamps, .git). The deny-all `.dockerignore` pattern fixes this.

---

## 8. Secrets Leaking into Layers

**Problem**: Every `RUN`, `COPY`, and `ADD` creates a layer. Even if you delete a secret in a later layer, it's still accessible in the image history.

**Examples of leaks**:
- `COPY .env .` then `RUN rm .env` — still in layer history
- `RUN echo $SECRET > /tmp/auth && curl ... && rm /tmp/auth` — still in layer
- `ARG NPM_TOKEN` then `RUN echo "//registry.npmjs.org/:_authToken=$NPM_TOKEN" > .npmrc` — visible in `docker history`

**Fix**:
- Use BuildKit secret mounts: `RUN --mount=type=secret,id=npmrc,target=/app/.npmrc npm ci`
- Use multi-stage builds: secret used only in builder stage doesn't appear in runtime stage
- Never use `ENV` for secrets (persists in image metadata)

---

## 9. Timezone Issues

**Problem**: Official base images default to UTC. Applications that assume local timezone (logging, scheduled tasks) show wrong times.

**Fix**: Set `TZ` environment variable and install timezone data:
```dockerfile
ENV TZ=UTC
RUN apt-get update && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*
```

For Alpine: `RUN apk add --no-cache tzdata`

For distroless: timezone data is included, just set `TZ` env var.

---

## 10. OOM Kills

**Problem**: Container hits memory limit and gets killed. Common with JVM (which pre-allocates heap), Python data processing, and Node.js (V8 defaults to ~1.5GB heap).

**Symptoms**: Container exits with code 137, no error logs.

**Fix**:
- JVM: `-XX:MaxRAMPercentage=75.0` — uses 75% of container limit
- Node.js: `--max-old-space-size=384` — set explicitly below container limit
- Python: use streaming/chunked processing for large datasets
- Always set both `limits` and `reservations` in compose — limits prevent OOM, reservations ensure scheduling
