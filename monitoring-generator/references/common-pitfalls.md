# Common Monitoring Pitfalls — Reference

Read this file when dealing with cardinality issues, alert fatigue, dashboard performance, or PromQL edge cases.

## Table of Contents
1. Cardinality Explosion
2. Alert Fatigue
3. Histogram Bucket Design
4. rate() on Resets
5. absent() for Missing Metrics
6. Dashboard Query Performance
7. Label Conflicts on Federation
8. Recording Rule Staleness
9. Grafana Variable Load Time
10. Phantom Alerts on Deploy

---

## 1. Cardinality Explosion

**Problem**: A label with unbounded values (user_id, request_id, URL path with IDs) creates millions of time series. Prometheus OOMs or becomes extremely slow.

**Symptom**: Prometheus memory usage spikes. `prometheus_tsdb_head_series` grows unbounded. Queries time out.

**How to detect**:
```promql
# Top 10 metrics by cardinality
topk(10, count by (__name__)({__name__=~".+"}))
```

**Fix**:
- Drop high-cardinality labels at scrape time via `metricRelabelings`
- In application code: never use unbounded values as label values
- Use histograms instead of per-ID metrics
- Aggregate in recording rules to reduce query-time cardinality

**Safe labels**: service, method, status_code, namespace, pod (bounded by cluster size).
**Dangerous labels**: user_id, trace_id, request_path (with dynamic segments), email, IP address.

---

## 2. Alert Fatigue

**Problem**: Too many alerts fire → team ignores them → real incidents get missed.

**Symptoms**: Slack channel has 100+ unread alerts. On-call acknowledges PagerDuty without investigating. "Oh, that alert always fires."

**Fix**:
- Apply the 3am test: critical alerts must be worth waking someone
- Every alert must be actionable — if there's nothing to do, it's not an alert
- Use `for` duration generously (5m minimum) to prevent flapping
- Use inhibition rules to suppress redundant alerts during incidents
- Regularly review and delete alerts nobody acts on
- Separate channels: `#alerts-critical` (pages), `#alerts-warning` (async), never mix them

**Rule of thumb**: If your team gets more than 5 critical pages per week, something is wrong with your alert definitions, not your infrastructure.

---

## 3. Histogram Bucket Design

**Problem**: Default histogram buckets (.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10) don't match the actual latency distribution of your service. p99 calculations become inaccurate.

**Symptom**: Dashboard shows p99 = 10s but actual p99 is somewhere between 5s and 10s. The histogram "snaps" to bucket boundaries.

**Fix**: Design buckets around your service's actual latency distribution:
```go
// API that typically responds in 10-500ms
prometheus.DefBuckets = []float64{
    0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0,
}

// Background job that takes 1-60s
prometheus.DefBuckets = []float64{
    0.5, 1, 2, 5, 10, 15, 30, 45, 60, 120,
}
```

**Rule of thumb**: Have at least 3-4 buckets in the range where most requests fall. The `+Inf` bucket is always added automatically.

More buckets = more accuracy but more cardinality. 10-15 buckets is usually the sweet spot.

---

## 4. rate() on Resets

**Problem**: `rate()` handles counter resets (pod restarts), but only if the range window is at least 4x the scrape interval. With a 15s scrape interval and `rate(...[1m])`, a reset at the wrong time can produce gaps or spikes.

**Symptom**: Spikes to absurd values after pod restarts. Gaps in rate graphs.

**Fix**: Use a range window of at least 4x scrape interval:
- Scrape interval 15s → minimum `rate(...[1m])`
- Scrape interval 30s → minimum `rate(...[2m])`
- For alerts, use 5m minimum: `rate(...[5m])`

Never use `rate()` with a window shorter than 2x scrape interval — it will produce no data points.

---

## 5. absent() for Missing Metrics

**Problem**: A service goes down. Its metrics disappear. Rate-based alerts return "no data" instead of firing — the alert doesn't trigger because there's nothing to evaluate.

**Symptom**: Service is completely down but no alerts fire. Error rate alert needs requests to exist to calculate a rate.

**Fix**: Use `absent()` for critical services:
```yaml
- alert: APIMetricsMissing
  expr: absent(up{job="api"} == 1)
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "No metrics from API service for 5 minutes — possible outage"
```

This fires when the metric doesn't exist at all, catching total outages that rate-based alerts miss.

---

## 6. Dashboard Query Performance

**Problem**: Grafana dashboard takes 30+ seconds to load. Users get timeout errors.

**Common causes**:
- Queries over long time ranges without recording rules
- `rate()` over 24h+ of raw histogram data
- Regex label matchers on high-cardinality labels
- Too many panels on one dashboard (50+)

**Fix**:
- Create recording rules for any query used in dashboards
- Use `$__rate_interval` in Grafana instead of hardcoded intervals
- Limit default time range to 6h, let users zoom out
- Split large dashboards into overview + detail views
- Use `max_source_resolution` in Grafana for Thanos/Mimir to avoid querying raw data for long ranges

---

## 7. Label Conflicts on Federation

**Problem**: Federating or aggregating metrics from multiple Prometheus instances. Labels like `instance` or `job` conflict or get overwritten.

**Symptom**: Metrics from different clusters merge incorrectly. `instance` labels clash.

**Fix**:
- Add an `external_labels` block in each Prometheus config with a unique `cluster` label
- Use `honor_labels: true` in federation scrape configs carefully — understand which labels you want to keep
- In Thanos/Mimir: rely on `external_labels` for deduplication

```yaml
# prometheus.yml
global:
  external_labels:
    cluster: "prod-us-east"
    environment: "prod"
```

---

## 8. Recording Rule Staleness

**Problem**: Recording rule uses a range vector (`[5m]`) but the rule evaluation interval is 1m. If the underlying metric disappears, the recording rule continues producing stale data for up to 5 minutes.

**Symptom**: Dashboard shows non-zero values for a service that's been down for a few minutes.

**Fix**:
- Set recording rule `interval` to match the range window: `interval: 5m` for `[5m]` queries
- Or accept the staleness as a feature — it provides some smoothing during restarts
- For critical accuracy: use shorter windows (`[1m]`) with shorter intervals

---

## 9. Grafana Variable Load Time

**Problem**: Template variables with `label_values()` queries take a long time to load when there are many unique values.

**Symptom**: Dashboard loads but dropdowns take 10+ seconds to populate.

**Fix**:
- Add a regex filter to variable queries: `label_values(up{namespace=~"prod.*"}, service)` instead of `label_values(up, service)`
- Use variable chaining: namespace variable filters the service variable query
- Enable variable caching in Grafana
- For static lists (environments, regions): use custom variables instead of query variables

---

## 10. Phantom Alerts on Deploy

**Problem**: Alerts fire briefly during rolling deployments. Old pods terminate (metrics disappear), new pods start (metrics not yet stable). Error rate spikes to 100% because there's one 5xx and zero total requests from the new pod.

**Symptom**: PagerDuty alert fires every deployment and auto-resolves 2 minutes later.

**Fix**:
- Use `for: 5m` on alerts — outlasts most rolling deployments
- Add deployment annotations in Grafana to correlate alert/deploy timing
- Use a minimum request threshold in error rate alerts:
  ```yaml
  # Only alert if there are enough requests to be meaningful
  - alert: APIHighErrorRate
    expr: |
      (
        sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
        /
        sum(rate(http_requests_total[5m])) by (service)
      ) > 0.05
      and
      sum(rate(http_requests_total[5m])) by (service) > 1
    for: 5m
  ```

The `and > 1` clause ensures there's meaningful traffic before alerting on error rate.
