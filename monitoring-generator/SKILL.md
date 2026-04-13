---
name: monitoring-generator
description: >
  Generate production-grade monitoring configurations: Prometheus alerting/recording rules, Grafana
  dashboards as code (JSON), AlertManager routing, and scrape configurations. Use this skill whenever
  the user asks to create monitoring, alerting, dashboards, observability configs, SLOs, or PromQL
  queries. Also trigger when the user describes services they want to monitor (e.g., "I need alerts
  for my API and database"), mentions Prometheus, Grafana, AlertManager, ServiceMonitor, or asks for
  RED/USE method metrics, SLI/SLO definitions, or dashboard templates. Covers Prometheus rules,
  Grafana dashboard JSON, AlertManager routing trees, Kubernetes ServiceMonitor/PodMonitor CRDs,
  and Grafana provisioning files. Target audience is advanced DevOps engineers — skip basics,
  focus on PromQL patterns, alert design, dashboard structure, and operational signal quality.
---

# Monitoring Generator Skill

Generate production-grade monitoring configurations as code. The audience runs Prometheus + Grafana in production — they want well-designed alerts, dashboards, and recording rules, not tutorials on what a metric is.

## Reference Files

- `references/common-pitfalls.md` — Read when dealing with cardinality explosions, alert fatigue, histogram bucket design, or Grafana performance issues.

## Workflow

### Step 1: Identify the Stack

Extract from the user's request (infer where possible, ask only when genuinely ambiguous):

- **Services to monitor** — APIs, databases, queues, caches, Kubernetes components, custom apps
- **Metrics methodology** — RED (Rate, Errors, Duration) for services, USE (Utilization, Saturation, Errors) for infrastructure
- **Alert destinations** — Slack, PagerDuty, OpsGenie, email, webhook
- **Deployment method** — kube-prometheus-stack (Helm), standalone Prometheus, Grafana Cloud, Mimir

### Step 2: Generate Files

Depending on the request, generate one or more of:

1. **Prometheus alerting rules** — `PrometheusRule` CRDs or standalone `.rules.yml`
2. **Prometheus recording rules** — pre-computed expensive queries
3. **Grafana dashboards** — JSON files ready for provisioning or import
4. **AlertManager config** — routing tree, receivers, inhibition rules
5. **ServiceMonitor / PodMonitor** — Kubernetes scrape target CRDs
6. **Grafana provisioning** — datasource and dashboard provisioning YAML

### Step 3: Annotate Decisions

Add comments explaining: why specific thresholds, why certain aggregation windows, why a particular PromQL approach. Don't explain what PromQL is; explain *why this query catches the problem reliably*.

---

## Prometheus Alerting Rules

### Structure

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack    # Must match Prometheus selector
spec:
  groups:
    - name: api.rules
      rules:
        - alert: APIHighErrorRate
          expr: |
            (
              sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
              /
              sum(rate(http_requests_total[5m])) by (service)
            ) > 0.05
          for: 5m
          labels:
            severity: critical
            team: backend
          annotations:
            summary: "High 5xx rate on {{ $labels.service }}"
            description: "Error rate is {{ $value | humanizePercentage }} over the last 5 minutes."
            runbook_url: "https://runbooks.example.com/api-high-error-rate"
            dashboard_url: "https://grafana.example.com/d/api-overview"
```

### Alert Design Principles

**Every alert must have:**
- `for` duration — prevents flapping on transient spikes. Use 5m minimum for most alerts, 15m for capacity warnings
- `severity` label — `critical` (pages someone), `warning` (Slack notification), `info` (dashboard only)
- `team` label — routes to the right people
- `summary` + `description` annotations — human-readable, include `{{ $value }}`
- `runbook_url` — link to remediation steps
- `dashboard_url` — direct link to the relevant Grafana dashboard

**Alert severity guidelines:**

| Severity | Response Time | Channel | Use When |
|----------|--------------|---------|----------|
| critical | Immediate (page) | PagerDuty/OpsGenie | User-facing impact right now, data loss risk |
| warning | Next business day | Slack channel | Degradation trending, capacity approaching limits |
| info | No notification | Dashboard only | Informational, context for debugging |

**The on-call test:** Only create a `critical` alert if you'd want to be woken up at 3am for it. If the answer is no, it's a `warning`.

### RED Method Alerts (Services)

For every service, alert on Rate, Errors, Duration:

```yaml
# --- Rate: Traffic drop (possible upstream issue or outage) ---
- alert: APITrafficDrop
  expr: |
    sum(rate(http_requests_total[10m])) by (service)
    < (sum(rate(http_requests_total[10m] offset 1h)) by (service) * 0.5)
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Traffic on {{ $labels.service }} dropped >50% vs 1h ago"

# --- Errors: High error rate ---
- alert: APIHighErrorRate
  expr: |
    (
      sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
      /
      sum(rate(http_requests_total[5m])) by (service)
    ) > 0.05
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "5xx error rate >5% on {{ $labels.service }}"

# --- Duration: High latency (p99) ---
- alert: APIHighLatencyP99
  expr: |
    histogram_quantile(0.99,
      sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le)
    ) > 2
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "p99 latency >2s on {{ $labels.service }}"
```

### USE Method Alerts (Infrastructure)

For infrastructure components — CPU, memory, disk, network:

```yaml
# --- Utilization ---
- alert: HighCPUUtilization
  expr: |
    (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance))
    > 0.85
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "CPU >85% on {{ $labels.instance }} for 15m"

# --- Saturation: Memory pressure ---
- alert: HighMemoryUsage
  expr: |
    (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
    > 0.90
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "Memory >90% on {{ $labels.instance }}"

# --- Errors: Disk approaching full ---
- alert: DiskSpaceLow
  expr: |
    (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes)
    > 0.85
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Disk >85% full on {{ $labels.instance }}:{{ $labels.mountpoint }}"

# Predictive: disk will fill within 24h at current rate
- alert: DiskWillFillIn24h
  expr: |
    predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}[6h], 24*3600) < 0
  for: 30m
  labels:
    severity: warning
  annotations:
    summary: "Disk on {{ $labels.instance }}:{{ $labels.mountpoint }} will fill within 24h"
```

### Database Alerts

```yaml
# PostgreSQL
- alert: PostgreSQLHighConnections
  expr: |
    sum(pg_stat_activity_count) by (instance)
    /
    sum(pg_settings_max_connections) by (instance)
    > 0.80
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "PostgreSQL connections >80% of max on {{ $labels.instance }}"

- alert: PostgreSQLReplicationLag
  expr: pg_replication_lag > 30
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Replication lag >30s on {{ $labels.instance }}"

- alert: PostgreSQLDeadlocks
  expr: rate(pg_stat_database_deadlocks[5m]) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Deadlocks detected on {{ $labels.datname }}"

# Redis
- alert: RedisHighMemoryUsage
  expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.85
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Redis memory >85% of maxmemory on {{ $labels.instance }}"

- alert: RedisHighKeyEvictionRate
  expr: rate(redis_evicted_keys_total[5m]) > 100
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Redis evicting >100 keys/sec on {{ $labels.instance }}"
```

### Kubernetes Alerts

```yaml
# Pod restarts
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 3
  for: 15m
  labels:
    severity: critical
  annotations:
    summary: "{{ $labels.namespace }}/{{ $labels.pod }} restarted {{ $value | humanize }} times in 15m"

# Deployment stuck
- alert: DeploymentReplicasMismatch
  expr: |
    kube_deployment_spec_replicas != kube_deployment_status_ready_replicas
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "{{ $labels.namespace }}/{{ $labels.deployment }} has {{ $value }} unavailable replicas"

# Node not ready
- alert: NodeNotReady
  expr: kube_node_status_condition{condition="Ready",status="true"} == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Node {{ $labels.node }} is not ready"

# PVC almost full
- alert: PVCAlmostFull
  expr: |
    kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is >85% full"
```

---

## Recording Rules

Pre-compute expensive queries used in dashboards and alerts. This reduces query load and ensures consistent calculations:

```yaml
groups:
  - name: api.recording_rules
    interval: 30s
    rules:
      # Error rate by service (used in dashboards + alerts)
      - record: service:http_error_rate:5m
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
          /
          sum(rate(http_requests_total[5m])) by (service)

      # Request rate by service
      - record: service:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (service)

      # p50/p95/p99 latency by service
      - record: service:http_duration:p50_5m
        expr: histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))

      - record: service:http_duration:p95_5m
        expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))

      - record: service:http_duration:p99_5m
        expr: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))
```

Naming convention: `level:metric:operations` — e.g., `service:http_error_rate:5m`.

---

## AlertManager Configuration

### Routing Tree

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: "${SLACK_WEBHOOK_URL}"

route:
  receiver: default-slack
  group_by: [alertname, service, namespace]
  group_wait: 30s         # Wait before first notification (batch related alerts)
  group_interval: 5m      # Wait before sending updates for same group
  repeat_interval: 4h     # Resend if alert still firing

  routes:
    # Critical → PagerDuty (pages on-call)
    - match:
        severity: critical
      receiver: pagerduty-critical
      continue: true       # Also send to Slack for visibility

    # Critical also goes to Slack
    - match:
        severity: critical
      receiver: slack-critical

    # Warning → team-specific Slack channels
    - match:
        severity: warning
        team: backend
      receiver: slack-backend

    - match:
        severity: warning
        team: infra
      receiver: slack-infra

    # Info → no notification (dashboard only)
    - match:
        severity: info
      receiver: "null"

receivers:
  - name: default-slack
    slack_configs:
      - channel: "#alerts-general"
        send_resolved: true
        title: '{{ if eq .Status "firing" }}:fire:{{ else }}:white_check_mark:{{ end }} [{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *{{ .Annotations.summary }}*
          {{ .Annotations.description }}
          {{ if .Annotations.runbook_url }}:book: <{{ .Annotations.runbook_url }}|Runbook>{{ end }}
          {{ if .Annotations.dashboard_url }}:chart_with_upwards_trend: <{{ .Annotations.dashboard_url }}|Dashboard>{{ end }}
          {{ end }}

  - name: pagerduty-critical
    pagerduty_configs:
      - service_key: "${PAGERDUTY_SERVICE_KEY}"
        severity: critical
        description: "{{ .CommonLabels.alertname }}: {{ .CommonAnnotations.summary }}"

  - name: slack-critical
    slack_configs:
      - channel: "#alerts-critical"
        send_resolved: true

  - name: slack-backend
    slack_configs:
      - channel: "#alerts-backend"
        send_resolved: true

  - name: slack-infra
    slack_configs:
      - channel: "#alerts-infra"
        send_resolved: true

  - name: "null"

# Inhibition: if critical is firing, suppress warnings for same service
inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: [alertname, service, namespace]
```

### Routing Design Principles

- **group_by** should include `alertname` + the most relevant label (service, namespace). Too broad = one huge notification. Too narrow = notification spam.
- **group_wait: 30s** — batches alerts that fire together (e.g., cascading failures)
- **inhibit_rules** — if the critical version of an alert fires, suppress the warning version. Prevents duplicate notifications.
- **continue: true** on critical routes — sends to PagerDuty AND Slack. On-call gets paged, team gets visibility.
- Every receiver should set `send_resolved: true` — people need to know when problems are fixed.

---

## Grafana Dashboards

### Dashboard Structure

Organize dashboards in a hierarchy:

```
dashboards/
├── overview/
│   └── service-overview.json       # RED metrics for all services — entry point
├── services/
│   ├── api.json                    # Deep dive: API latency, errors, throughput
│   ├── worker.json                 # Celery/queue worker metrics
│   └── gateway.json                # Ingress/gateway metrics
├── infrastructure/
│   ├── kubernetes.json             # Node/pod/deployment health
│   ├── nodes.json                  # USE method: CPU, memory, disk, network
│   └── networking.json             # Ingress traffic, DNS, connection pools
└── databases/
    ├── postgresql.json             # Connections, queries, replication, locks
    └── redis.json                  # Memory, keys, commands, evictions
```

### Dashboard JSON Conventions

When generating dashboard JSON:

- **Use variables** for service, namespace, instance — always `$service`, `$namespace`, `$instance` as template variables at the top
- **Consistent time range** — default to last 6h with auto-refresh 30s
- **Row organization** — group panels into collapsible rows by concern (Overview, Latency, Errors, Saturation)
- **Panel sizing** — full-width for time series, half-width for stats/gauges, quarter-width for single values
- **Color coding** — green/yellow/red thresholds that match alert severities
- **Annotations** — add deployment annotations from your CI/CD system
- **Links** — cross-link dashboards (overview → detail), link to runbooks from alert panels

### Panel Patterns

**Golden Signals Overview Row:**
```json
{
  "title": "Request Rate",
  "type": "timeseries",
  "targets": [{
    "expr": "service:http_requests:rate5m{service=~\"$service\"}",
    "legendFormat": "{{ service }}"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "reqps"
    }
  }
}
```

**Use recording rules in dashboards** — reference `service:http_error_rate:5m` instead of repeating the raw query. This keeps dashboards fast and consistent with alert calculations.

**Latency heatmap** for request duration histograms — more informative than percentile lines for understanding distribution shape.

### Grafana Provisioning

```yaml
# grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: "15s"     # Match Prometheus scrape interval
      httpMethod: POST        # POST for large queries
```

```yaml
# grafana/provisioning/dashboards/dashboards.yaml
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true    # Creates folders matching directory structure
```

---

## ServiceMonitor / PodMonitor (Kubernetes)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames: [default, app]
  selector:
    matchLabels:
      app: api
  endpoints:
    - port: metrics              # Named port from Service
      interval: 15s
      path: /metrics
      scrapeTimeout: 10s
      metricRelabelings:
        # Drop high-cardinality metrics you don't need
        - sourceLabels: [__name__]
          regex: "go_.*"
          action: drop
```

Use `metricRelabelings` to drop unused metrics at scrape time — reduces storage cost and cardinality.

---

## SLI / SLO Definitions

When the user asks for SLOs, define them as recording rules + alerts:

```yaml
# Recording rule: availability SLI
- record: sli:api_availability:5m
  expr: |
    1 - (
      sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
      /
      sum(rate(http_requests_total[5m])) by (service)
    )

# Alert: error budget burn rate
# Uses multi-window approach: fast burn (last 1h) and slow burn (last 6h)
- alert: SLOErrorBudgetFastBurn
  expr: |
    (
      1 - sli:api_availability:5m > 14.4 * (1 - 0.999)
    )
    and
    (
      1 - sli:api_availability:5m > 14.4 * (1 - 0.999)
    )
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "SLO error budget burning fast on {{ $labels.service }} — 99.9% target at risk"
```

SLO target of 99.9% = error budget of 0.1%. Multi-window burn rate catches both sudden outages (fast burn) and slow degradation (slow burn).

---

## Output Checklist

Before delivering, verify every item:

- [ ] Every alert has `for` duration (no flapping)
- [ ] Every alert has `severity`, `team`, `summary`, `description`, `runbook_url`
- [ ] Critical alerts pass the "3am test" — worth waking someone
- [ ] Warning alerts are actionable within business hours
- [ ] Recording rules pre-compute expensive dashboard/alert queries
- [ ] Recording rules follow `level:metric:operations` naming
- [ ] AlertManager routing separates critical (page) from warning (Slack)
- [ ] Inhibition rules suppress warning when critical fires for same alert
- [ ] Grafana dashboards use template variables ($service, $namespace)
- [ ] Dashboards reference recording rules, not raw queries
- [ ] ServiceMonitors drop high-cardinality metrics not needed
- [ ] SLOs use multi-window burn rate approach
- [ ] Slack messages include runbook + dashboard links
- [ ] `send_resolved: true` on all receivers
