---
name: tests-back-performance-k6
description: Use when creating, structuring, or improving backend API performance tests with k6 — load tests, stress tests, spike tests, smoke tests, soak tests. Trigger on requests for performance testing, load testing, SLO validation, throughput testing, or when k6 scripts need thresholds, scenarios, executors, custom metrics, or CI/CD integration.
---

# Backend Performance Testing with k6

## Overview

k6 is a developer-centric, open-source performance testing tool by Grafana Labs. Tests are written in JavaScript (ES6+), version-controlled alongside source code, and run locally or in CI/CD pipelines. Core principle: **performance tests are code** — they should follow the same quality standards as production code.

## Test Types & When to Use

| Test Type     | VUs / Load         | Duration   | Goal |
|---------------|--------------------|------------|------|
| **Smoke**     | 2–5 VUs            | 30–60s     | Validate script, baseline check |
| **Load**      | Expected peak VUs  | 5–30 min   | Verify system under normal load |
| **Stress**    | 2–3× peak VUs      | 10–30 min  | Find breaking point |
| **Spike**     | Sudden surge       | Short burst| Test recovery from traffic burst |
| **Soak**      | Normal load        | 1–24 h     | Detect memory leaks, degradation |

## Project Structure

```
tests/performance/
  config/
    thresholds.js     # Shared SLO thresholds
    scenarios.js      # Reusable scenario configs
  helpers/
    auth.js           # Auth flows (login, token)
    data.js           # Test data / SharedArray
    client.js         # HTTP client wrapper (optional)
  tests/
    smoke.test.js
    load.test.js
    stress.test.js
    soak.test.js
```

## Core Script Anatomy

```javascript
// 1. Init — runs once per VU (import, setup vars)
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const checkoutDuration = new Trend('checkout_duration');

// 2. Options — test configuration
export const options = {
  scenarios: {
    load: {
      executor: 'ramping-vus',
      stages: [
        { duration: '1m', target: 50 },   // ramp up
        { duration: '3m', target: 50 },   // steady state
        { duration: '1m', target: 0 },    // ramp down
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed:   ['rate<0.01'],   // <1% errors
    errors:            ['rate<0.05'],
    checks:            ['rate>0.95'],
  },
};

// 3. Setup — runs once before VUs start (optional)
export function setup() {
  const res = http.post(`${__ENV.BASE_URL}/auth/login`, JSON.stringify({
    username: __ENV.TEST_USER,
    password: __ENV.TEST_PASS,
  }), { headers: { 'Content-Type': 'application/json' } });
  return { token: res.json('access_token') };
}

// 4. Default — VU function, runs repeatedly
export default function (data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };

  const res = http.get(`${__ENV.BASE_URL}/api/products`, { headers, tags: { name: 'list_products' } });

  const ok = check(res, {
    'status 200':     (r) => r.status === 200,
    'has data':       (r) => r.json('data') !== undefined,
    'response < 500ms': (r) => r.timings.duration < 500,
  });

  errorRate.add(!ok);
  sleep(1);
}

// 5. Teardown — runs once after test (optional)
export function teardown(data) { /* cleanup */ }
```

## Executors Quick Reference

| Executor               | Use Case                              | Key Options |
|------------------------|---------------------------------------|-------------|
| `constant-vus`         | Simple fixed-load test                | `vus`, `duration` |
| `ramping-vus`          | Gradual ramp up/down (closed model)   | `stages` |
| `constant-arrival-rate`| Fixed RPS target (open model)         | `rate`, `timeUnit`, `duration`, `preAllocatedVUs` |
| `ramping-arrival-rate` | Variable RPS over time                | `startRate`, `stages`, `preAllocatedVUs`, `maxVUs` |
| `per-vu-iterations`    | Each VU runs N iterations             | `vus`, `iterations`, `maxDuration` |
| `shared-iterations`    | N total iterations split among VUs    | `vus`, `iterations` |
| `externally-controlled`| Real-time manual control via CLI/API  | `vus`, `maxVUs` |

> **Rule:** Use `constant-arrival-rate` / `ramping-arrival-rate` when validating RPS/throughput SLOs. Use `ramping-vus` for user-concurrency scenarios.

## Thresholds (SLO as Code)

```javascript
export const options = {
  thresholds: {
    // Global latency SLOs
    'http_req_duration':                    ['p(95)<500', 'p(99)<1000'],
    // Per-endpoint thresholds (via tags)
    'http_req_duration{name:checkout}':     ['p(95)<800'],
    'http_req_duration{name:search}':       ['p(95)<300'],
    // Availability
    'http_req_failed':                      ['rate<0.01'],
    // Custom metrics
    'errors':                               ['rate<0.05'],
    // Abort test if threshold breached early
    'http_req_duration': [{ threshold: 'p(99)<2000', abortOnFail: true }],
  },
};
```

> **Checks ≠ Thresholds.** Checks are informational assertions per request. Thresholds are pass/fail gates for the whole test. Both are needed.

## Custom Metrics

```javascript
import { Counter, Gauge, Rate, Trend } from 'k6/metrics';

const ordersCreated  = new Counter('orders_created');   // cumulative count
const activeUsers    = new Gauge('active_users');        // current value
const errorRate      = new Rate('error_rate');           // 0–1 proportion
const checkoutTime   = new Trend('checkout_time_ms');    // distribution

export default function() {
  const res = http.post('/api/orders', payload);
  ordersCreated.add(1);
  checkoutTime.add(res.timings.duration);
  errorRate.add(res.status >= 400);
}
```

## Parameterization with SharedArray

```javascript
import { SharedArray } from 'k6/data';
import papaparse from 'https://jslib.k6.io/papaparse/5.1.1/index.js';

// Loaded once, shared across all VUs (memory efficient)
const users = new SharedArray('users', function() {
  return papaparse.parse(open('./data/users.csv'), { header: true }).data;
});

export default function() {
  const user = users[__VU % users.length]; // deterministic per VU
  // use user.email, user.password...
}
```

## Multiple Scenarios

```javascript
export const options = {
  scenarios: {
    browse: {
      executor: 'constant-arrival-rate',
      rate: 100, timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 20,
      exec: 'browsing',
      tags: { flow: 'browse' },
    },
    checkout: {
      executor: 'constant-arrival-rate',
      rate: 10, timeUnit: '1s',
      duration: '5m',
      startTime: '30s',         // starts after browse warms up
      preAllocatedVUs: 5,
      exec: 'checkout',
      tags: { flow: 'checkout' },
    },
  },
  thresholds: {
    'http_req_duration{flow:browse}':   ['p(95)<300'],
    'http_req_duration{flow:checkout}': ['p(95)<800'],
  },
};

export function browsing() { /* ... */ }
export function checkout() { /* ... */ }
```

## Environment Variables & Config

```javascript
// Access via __ENV (never hardcode secrets)
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

// Run with: k6 run -e BASE_URL=https://staging.api.com test.js
// Or via .env + dotenv: k6 run --env-file .env test.js
```

## CI/CD Integration

```yaml
# GitHub Actions example
- name: Run k6 Performance Tests
  uses: grafana/k6-action@v0.3.1
  with:
    filename: tests/performance/load.test.js
    flags: --out json=results.json
  env:
    BASE_URL: ${{ secrets.STAGING_URL }}
    K6_VUS: 50

# k6 exits non-zero if any threshold fails → pipeline fails automatically
```

## Built-in Metrics Reference

| Metric                | Type   | Description |
|-----------------------|--------|-------------|
| `http_req_duration`   | Trend  | Total request time (send + wait + receive) |
| `http_req_failed`     | Rate   | Rate of failed requests (non-2xx/3xx) |
| `http_req_blocked`    | Trend  | Time waiting for TCP connection |
| `http_req_connecting` | Trend  | TCP handshake time |
| `http_req_tls_handshaking` | Trend | TLS handshake time |
| `http_req_waiting`    | Trend  | Time to first byte (TTFB) |
| `http_req_sending`    | Trend  | Request body send time |
| `http_req_receiving`  | Trend  | Response body receive time |
| `iterations`          | Counter| Total VU iterations completed |
| `vus`                 | Gauge  | Current active VUs |
| `checks`              | Rate   | Proportion of passing checks |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using only `vus` + `duration` for RPS goals | Use `constant-arrival-rate` with `rate` |
| Hardcoding `BASE_URL` | Use `__ENV.BASE_URL` with a fallback |
| Missing `sleep()` in user-flow tests | Add `sleep(1)` or randomized `sleep(Math.random() * 2 + 1)` |
| Checks without thresholds | Add `checks: ['rate>0.95']` threshold |
| Global state mutated by multiple VUs | Use `SharedArray` or VU-local variables |
| No tags on requests | Tag every request: `{ tags: { name: 'endpoint_name' } }` |
| Single monolithic test file | Split by test type (smoke/load/stress/soak) |
| Not using `setup()` for auth | Always authenticate in `setup()`, pass token to VUs |
| Forgetting `abortOnFail` on critical thresholds | Add `abortOnFail: true` for critical SLOs |

## Best Practices Checklist

- [ ] Scripts committed alongside application code (version-controlled)
- [ ] `BASE_URL` and secrets via `__ENV`, never hardcoded
- [ ] Separate files per test type (smoke, load, stress, soak)
- [ ] `setup()` handles auth; token passed to `default()`
- [ ] Every HTTP request tagged with `{ name: 'descriptive_name' }`
- [ ] Per-endpoint thresholds using tag filters
- [ ] `SharedArray` for large test data sets
- [ ] `sleep()` added to simulate think time
- [ ] Custom metrics for business-level KPIs
- [ ] `abortOnFail: true` on critical latency thresholds
- [ ] CI/CD pipeline uses non-zero exit code as gate
- [ ] Grafana / InfluxDB / Prometheus output for dashboards

## Running Tests

```bash
# Install
brew install k6              # macOS
choco install k6             # Windows
sudo apt-get install k6      # Linux (after adding repo)

# Run
k6 run test.js
k6 run -e BASE_URL=https://api.example.com --vus 50 --duration 60s test.js

# Output formats
k6 run --out json=results.json test.js
k6 run --out influxdb=http://localhost:8086/k6 test.js
k6 run --out csv=results.csv test.js

# Web dashboard (real-time)
K6_WEB_DASHBOARD=true k6 run test.js
```
