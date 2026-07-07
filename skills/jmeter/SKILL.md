---
name: jmeter
description: Use this skill for Apache JMeter work — load/performance/stress tests authored via GUI (Thread Group → Sampler → Listener), Test Plan (.jmx), JSR223 with Groovy for dynamic data, properties (-J/-G), distributed testing (master + slaves), non-GUI mode (`-n -t plan.jmx -l out.jtl`), CI integration, plugins (Custom Thread Groups, Dummy Sampler, Throughput Shaping Timer), analysis with Grafana/dashboard. Trigger on "JMeter", ".jmx", "Thread Group", "JSR223", "Distributed JMeter", "Throughput Controller", "jmeter-maven-plugin". Use ONLY for JMeter; for k6 use tests-back-performance-k6 skill, for Locust use tests-back-performance-locust skill.
---

# Apache JMeter Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Team standardized on JMeter test plans (.jmx) | Modern k6/Locust is the team's chosen tool — use those skills |
| GUI scripting needed for QA teams less keen on code | Pure TS/JS workflow (k6 is faster to maintain) |
| Testing SOAP / JMS / legacy protocols (k6 gaps) | Load tests against a browser-like UI (use k6/browser or Playwright) |
| Reporting to stakeholders expecting JMeter HTML report | Need scheduled cron-style runs without infra |

## Core stack & versions

- **JMeter 5.6+** stable; requires Java 11 or 17.
- Docker images: `justb4/jmeter`, `vdbinhaerle/jmeter`.
- **Plugins Manager** (https://jmeter-plugins.org/) installed as jar in
  `lib/ext/`. Useful plugins: `Custom Thread Groups`, `Throughput Shaping
  Timer`, `Dummy Sampler`, `PerfMon` listener.
- **JSR223 + Groovy** is the recommended scripting engine. Beanshell is
  deprecated and slow. Use `cacheKey` to enable compilation caching.
- Backend listener → InfluxDB / Telegraf for live Grafana dashboards.

## Project structure (canonical)

```
perf/
├── plans/
│   ├── checkout_load.jmx
│   ├── checkout_stress.jmx
│   └── login_smoke.jmx
├── data/
│   └── users.csv                # CSV data set for parameterized users
├── properties/
│   ├── local.properties         # dev env values, gitignored secrets
│   ├── staging.properties
│   └── prod.properties
├── results/                     # .jtl outputs (gitignored)
├── reports/                     # HTML reports (gitignored)
├── Dockerfile
└── run.sh                       # wrapper for jmeter non-GUI
```

`.jmx` test plans committed; results and reports gitignored.

## Best practices checklist

1. ✅ **Non-GUI mode always in CI**: `jmeter -n -t plan.jmx -l out.jtl -e -o
   report/`. GUI mode is for authoring only.
2. ✅ `-e -o <dir>` generates the HTML dashboard after the run.
3. ✅ **Thread Group**: `Number of threads` = virtual users; `Ramp-up` =
   seconds to spread start; `Loop count` = `-1` with Scheduler Duration for
   bounded runs.
4. ✅ Prefer **Concurrency Thread Group** + **Throughput Shaping Timer**
   (plugins) for precise RPS scheduling over time.
5. ✅ **Stepping Thread Group** for staged stress tests (warm up in steps).
6. ✅ **CSV Data Set Config** for parameterized users/endpoints/payloads;
   one row per request; `Sharing mode = All threads` or `Current thread group`.
7. ✅ **JSR223 + Groovy** instead of Beanshell. Set `cacheKey` so the script
   compiles once and is reused across iterations.
8. ✅ Variables `${VarName}` are thread-scoped; properties `${__P(prop)}`
   read a JVM property; `-J` sets local prop, `-G` sets distributed prop.
9. ✅ **HTTP Request Defaults** sets common base URL + headers + credentials
   for all samplers; samplers set only path-specific things.
10. ✅ **HTTP Header Manager** for headers (auth tokens); **HTTP Cookie
    Manager** for sessions (`Clear cookies each iteration` typically on).
11. ✅ **Response assertions** per sampler (`Response Code = 200`, `contains
    "ok"`); not on whole test plan.
12. ✅ **JSON Extractor** parses and chains values (`${user.id}` → next
    sampler payload).
13. ✅ **Timers**: `Constant Timer` only for small realism; rely on
    scheduler. `Synchronizing Timer` for spike tests with a synchronized
    barrier.
14. ✅ **Listeners** kept only for authoring; non-GUI run uses `-l` JTL +
    `-e` dashboard. Listeners cost memory under load.
15. ✅ **Backend Listener** pushes live metrics to InfluxDB → Grafana;
    crucial for distributed tests to aggregate across slaves.
16. ✅ **Distributed testing**: master + slaves via `remote_hosts` in
    `jmeter.properties` (or `-R host1,host2`); master sends plan via RMI.
17. ✅ **Disable RMI SSL in controlled intranet**: set
    `server.rmi.ssl.disable=true`; JMeter 5.x defaults SSL on RMI, breaking
    many distributed setups.
18. ✅ **Heap size** raised: `-Xms2g -Xmx4g` for master collecting large
    results; slaves can run with smaller heap.
19. ✅ **CI integration**: `com.lazerycode.jmeter:jmeter-maven-plugin`
    runs plans in Maven `verify` phase; `jmeter-gradle-plugin` for Gradle.
20. ✅ **TearDown Thread Group** to clean up generated state (delete sessions
    via API); keeps env clean and tests repeatable.
21. ✅ **SetUp Thread Group** to seed data (auth tokens, test data) before
    the main group.
22. ✅ Use **Dummy Sampler** to stub third-party APIs when isolating the SUT.
23. ✅ **Properties files** per env (`-p staging.properties`); never bake
    secrets into `.jmx`.
24. ✅ **HTML report** ships a 15MB+ folder — use as CI artifact, do not commit.
25. ✅ **Source the docs** when in doubt: JMeter manual is dense but correct.

## Canonical patterns

### `run.sh` wrapper (non-GUI, Docker)

```bash
#!/usr/bin/env bash
set -euo pipefail

PLAN=${1:-plans/checkout_load.jmx}
ENV_NAME=${2:-staging}
TS=$(date +%Y%m%d_%H%M%S)
OUT="results/$(basename "${PLAN%.jmx}")_${TS}.jtl"
REP="reports/$(basename "${PLAN%.jmx}")_${TS}"

docker run --rm -i \
  -v "$PWD:/perf" -w /perf \
  -e JVM_ARGS="-Xms1g -Xmx3g" \
  justb4/jmeter:latest \
  -n -t "$PLAN" \
  -p "properties/${ENV_NAME}.properties" \
  -l "$OUT" \
  -e -o "$REP" \
  -Jthreads="${THREADS:-100}" \
  -Jrampup="${RAMP:-30}" \
  -Jduration="${DURATION:-300}"

echo "Report: $REP/index.html"
```

### Distributed test command

```bash
# On master node:
jmeter -n -t plans/checkout_load.jmx \
  -R slave1:1099,slave2:1099,slave3:1099 \
  -p properties/staging.properties \
  -l results/checkout_$(date +%s).jtl \
  -e -o reports/checkout_$(date +%s)
```

### JSR223 Sampler (Groovy) for dynamic payload

```groovy
// In JSR223 Sampler with groovy language, cacheKey = "loginGen"
import groovy.json.JsonOutput

def userIndex = vars.get("USER_INDEX").toInteger()
def email    = "perfUser_${userIndex}@test.invalid"
def password = "perf-pass-${userIndex}"

def payload = JsonOutput.toJson([
    email   : email,
    password: password
])

vars.put("REQ_BODY", payload)
SampleResult.setRequestData(payload)
return "Generated payload for ${email}"
```

### CSV Data Set → HTTP Request payload binding

```xml
<CSVDataSet>
  <stringProp name="filename">data/users.csv</stringProp>
  <stringProp name="delimiter">,</stringProp>
  <stringProp name="variableNames">EMAIL,password,_id</stringProp>
  <boolProp name="recycle">true</boolProp>
</CSVDataSet>

<HTTPSampler>
  <stringProp name="path">/api/login</stringProp>
  <stringProp name="method">POST</stringProp>
  <stringProp name="BODY">
    {"email":"${EMAIL}","password":"${password}"}
  </stringProp>
</HTTPSampler>
```

### HTML report → CI artifact (GitHub Actions)

```yaml
jobs:
  perf:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - run: ./run.sh plans/login_smoke.jmx staging
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: jmeter-report, path: reports/ }
      - run: |
          # Fail build if error rate > 1% or p95 > 1000ms
          STATS="results/login_smoke"
          docker run --rm -v "$PWD:/perf" -w /perf justb4/jmeter \
            -n -t plans/login_smoke.jmx -p properties/staging.properties -l results/checkout.jtl
          jq < reports/login_smoke/statistics.json
```

## Common pitfalls / anti-patterns

- ❌ Running tests in GUI mode for load — GUI adds listener overhead, hides
  throughput. CLI only.
- ❌ Many `View Results Tree` listeners enabled — eat memory, slow run.
- ❌ Hardcoded URLs in samplers — use `HTTP Request Defaults` + `${baseUrl}`
  variable soplannes.
- ❌ Mixing `${var}` (per thread) with `${__P(prop)}` (global) — easy to
  misread scalability; document usage.
- ❌ Default RMI SSL secure on, with no tunnen set up for distributed —
  the master-slave handshake aborts.
- ❌ Heap too small (1GB) for big test plans → OOM mid-run.
- ❌ Forgetting `-e -o` so no HTML report is generated — lose the dashboard
  for stakeholders.
- ❌ Putting secret tokens in `.jmx` — use properties files instead
  (`-p env.properties`).
- ❌ Tests against live prod DB by accident — verify env via `${baseUrl}`
  before ramping.
- ❌ Single slave handles more than ~500 threads (CPU bottleneck multiplies
  artificially) — shard horizontally.
- ❌ Using Beanshell `String`-concatenation instead of Groovy — 10-100x
  slower; use JSR223 + Groovy with `cacheKey` set.

## Testing & validation

- Smoke test every plan via `jmeter -n -t plan.jmx -Jthreads=1
  -Jduration=10s -l out.jtl` before ramping.
- Validate `out.jtl` has `success = true` forSampler (OK) or all expected
  failures for stress tests.
- Compare `statistics.json` (in the HTML report folder) against prior run
  as baseline trend.
- Grafana JMeter dashboard (Backend Listener) for live / historical.

## Performance & tuning

- Master heap 2-4GB; slaves 1GB; threads per slave 200–500 realistic.
- Use `jmeter-maven-plugin` `propertiesUser` to inject from CI env vars,
  avoids plaintext secrets.
- Throughput Shaping Timer for shaped ramp-up; replaces manual `ThreadGroup`
  ramp calculations.
- Disable RMI metrics overhead by setting `mode=Standard` (not StrippedSync)
  for distributed results when bandwidth not a concern.
- Use **Non-GUI Optimizations** openJVM: `-XX:+UseG1GC -XX:MaxGCPauseMillis=200`.
- Backend listener batch size defaults to 100; raise for noisy backpressure.

## Security (top 5)

1. **No secrets in `.jmx`** — properties files only, sourced via env vars in CI.
2. **`server.rmi.ssl.disable=true`** only inside an ACL-isolated network
   between master and slaves; default-SSL in 5.x is correct for untrusted nets.
3. **Test users** must be fake (`perfUser_x@test.invalid`) and isolated on a
   staging env; never enumerate real customers.
4. **RMI ports** (`1099`, `50000-51000`) gated by firewall rules; not exposed
   to the public internet.
5. **Result files** may contain echoed payloads ofAuthorization headers —
   treat them as sensitive; clean them out before sending around or storing
   long-term.

## Official docs & references

- JMeter user manual: https://jmeter.apache.org/usermanual/index.html
- Element reference: https://jmeter.apache.org/usermanual/component_reference.html
- Functions: https://jmeter.apache.org/usermanual/functions.html
- Best practices: https://jmeter.apache.org/usermanual/best-practices.html
- Distributed testing: https://jmeter.apache.org/usermanual/remote-test.html
- JSR223 + Groovy: https://jmeter.apache.org/usermanual/best-practices.html#best_practices_jsr223
- jmeter-maven-plugin: https://github.com/jmeter-maven-plugin/jmeter-maven-plugin
- jmeter-plugins: https://jmeter-plugins.org/
- jmeter-grafana-dashboard: https://github.com/data-gov-ua/jmeter-grafana
- Docker image (justb4): https://hub.docker.com/r/justb4/jmeter