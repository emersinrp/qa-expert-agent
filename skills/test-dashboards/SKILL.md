---
name: test-dashboards
description: Use this skill to aggregate and visualize test RESULTS into dashboards/reports — a self-contained HTML dashboard from JUnit XML (embedded zero-dep Python generator), Allure (rich reports with history/trends), k6 → Grafana for performance, and CI-native summaries (GitHub Actions job summary, test-reporter actions, publish to Pages). Trigger on "test dashboard", "test report", "aggregate JUnit", "allure report", "pass-rate trend", "flaky trend", "publish test results", "GitHub Actions test summary". Use ONLY for reporting/visualizing results the runners already produce — it does NOT run tests (the domain skills do that — playwright/cypress/api-testing/k6/…); for live performance metrics see the k6 skill.
---

# Test Dashboards & Reporting Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Aggregating results from one or many runners into one view | Running the tests — that's the domain skill (playwright/api-testing/k6/…) |
| Tracking pass-rate / duration / flaky **trends** across runs | Live app performance monitoring / APM — use an observability stack |
| Publishing a portable report to CI artifacts / Pages / a PR | Gating the build — the **runner's** non-zero exit gates, not the report |
| Turning JUnit XML into a self-contained HTML dashboard | Rich per-step history & retries at scale — reach for Allure |

Reporting is downstream of execution: the runners emit **JUnit XML / Allure
results**, this skill turns those artifacts into something a human reads.

## Core approaches (route by need)

| Need | Approach |
| --- | --- |
| Zero-infra, works anywhere, one portable file | **JUnit XML → self-contained HTML** (embedded generator below) |
| Rich report: steps, attachments, retries, history, categories | **Allure** (`allure-*` adapters + `allure generate`) |
| Performance time-series (RPS, p95, VUs over time) | **k6 web dashboard** or **k6 → InfluxDB/Prometheus → Grafana** |
| Inline PR annotations + a job summary in CI | **GitHub Actions** summary + `dorny/test-reporter` |

Every runner in this bundle can emit **JUnit XML** (`--reporters junit`,
Surefire, `pytest --junitxml`, `k6 --out ...`, Newman `--reporters junit`), so
the universal path below works regardless of stack.

## Project structure (canonical)

```
repo/
├── tools/
│   └── junit_dashboard.py         # the embedded generator (committed once)
├── reports/                       # JUnit XML written by the runners (gitignored)
│   ├── unit.xml  api.xml  e2e.xml
├── .junit-history.json            # trend history, carried between CI runs
└── dashboard.html                 # generated artifact (gitignored / published)
```

## The embedded generator (JUnit XML → HTML, zero-dep)

Stdlib-only Python 3 — no `pip install`. Commit it once at `tools/junit_dashboard.py`:

```python
#!/usr/bin/env python3
"""Aggregate JUnit XML result files into a single self-contained HTML dashboard.

Stdlib only (no pip install). Works with any runner that emits JUnit XML:
Playwright, Cypress, pytest, Maven/Surefire, Karate, k6, Newman, etc.

    python3 junit_dashboard.py "results/**/*.xml" -o dashboard.html
    python3 junit_dashboard.py results/*.xml -o dashboard.html --history .junit-history.json

Security: JUnit XML never contains a DTD/entity declaration, so this refuses any
file carrying <!DOCTYPE / <!ENTITY (blocks billion-laughs & XXE at the source),
and transparently uses defusedxml when it happens to be installed.
"""
import argparse, glob, html, json, os, sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

try:  # belt-and-suspenders: use the hardened parser if it's available
    from defusedxml.ElementTree import fromstring as xml_fromstring
except ImportError:
    xml_fromstring = ET.fromstring


def collect(patterns):
    cases, files = [], []
    for pat in patterns:
        files.extend(glob.glob(pat, recursive=True))
    for path in sorted(set(files)):
        try:
            raw = open(path, "rb").read()
            if b"<!DOCTYPE" in raw or b"<!ENTITY" in raw:
                print(f"warn: skipping {path}: DTD/entity declarations are not allowed", file=sys.stderr)
                continue
            root = xml_fromstring(raw)
        except Exception as exc:  # unparseable / rejected — skip, don't crash the report
            print(f"warn: skipping {path}: {exc}", file=sys.stderr)
            continue
        for suite in root.iter("testsuite"):
            sname = suite.get("name") or os.path.basename(path)
            for tc in suite.findall("testcase"):
                fail = tc.find("failure")
                err = tc.find("error")
                node = fail if fail is not None else err
                skipped = tc.find("skipped") is not None
                status = "failed" if node is not None else "skipped" if skipped else "passed"
                msg = ""
                if node is not None:
                    msg = (node.get("message") or (node.text or "")).strip()
                cases.append({
                    "suite": sname,
                    "name": tc.get("name", "(unnamed)"),
                    "classname": tc.get("classname", ""),
                    "time": float(tc.get("time") or 0),
                    "status": status,
                    "message": msg,
                })
    return cases, sorted(set(files))


def summarize(cases):
    total = len(cases)
    passed = sum(c["status"] == "passed" for c in cases)
    failed = sum(c["status"] == "failed" for c in cases)
    skipped = sum(c["status"] == "skipped" for c in cases)
    duration = sum(c["time"] for c in cases)
    rate = (passed / total * 100) if total else 0.0
    return {"total": total, "passed": passed, "failed": failed,
            "skipped": skipped, "duration": round(duration, 3), "pass_rate": round(rate, 1)}


def sparkline(history):
    if len(history) < 2:
        return ""
    pts = [h["pass_rate"] for h in history][-30:]
    w, h = 260, 40
    step = w / (len(pts) - 1)
    coords = " ".join(f"{i*step:.1f},{h - (v/100*h):.1f}" for i, v in enumerate(pts))
    return (f'<svg class="spark" viewBox="0 0 {w} {h}" preserveAspectRatio="none" '
            f'width="{w}" height="{h}"><polyline points="{coords}" fill="none" '
            f'stroke="currentColor" stroke-width="2"/></svg>')


def render(summary, cases, files, history, top_n):
    slowest = sorted(cases, key=lambda c: c["time"], reverse=True)[:top_n]
    failures = [c for c in cases if c["status"] == "failed"]
    by_suite = {}
    for c in cases:
        s = by_suite.setdefault(c["suite"], {"tests": 0, "passed": 0, "failed": 0, "skipped": 0, "time": 0.0})
        s["tests"] += 1
        s[c["status"]] += 1
        s["time"] += c["time"]
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    e = html.escape

    rows_suite = "".join(
        f"<tr><td>{e(name)}</td><td>{d['tests']}</td><td class=ok>{d['passed']}</td>"
        f"<td class={'bad' if d['failed'] else 'muted'}>{d['failed']}</td>"
        f"<td class=muted>{d['skipped']}</td><td>{d['time']:.2f}s</td></tr>"
        for name, d in sorted(by_suite.items())
    )
    rows_slow = "".join(
        f"<tr><td>{e(c['name'])}</td><td class=muted>{e(c['suite'])}</td><td>{c['time']:.3f}s</td></tr>"
        for c in slowest
    )
    rows_fail = "".join(
        f"<tr><td>{e(c['name'])}</td><td class=muted>{e(c['classname'] or c['suite'])}</td>"
        f"<td><pre>{e(c['message'][:400])}</pre></td></tr>"
        for c in failures
    ) or "<tr><td colspan=3 class=ok>No failures 🎉</td></tr>"
    spark = sparkline(history)
    trend = f'<div class=card><div class=label>Pass-rate trend ({len(history)} runs)</div>{spark}</div>' if spark else ""

    return f"""<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Test dashboard — {summary['pass_rate']}% pass</title>
<style>
:root{{--bg:#fff;--fg:#1a1a1a;--mut:#6b7280;--line:#e5e7eb;--ok:#16a34a;--bad:#dc2626;--card:#f9fafb}}
@media(prefers-color-scheme:dark){{:root{{--bg:#0f1115;--fg:#e5e7eb;--mut:#9ca3af;--line:#272b33;--ok:#4ade80;--bad:#f87171;--card:#161a21}}}}
*{{box-sizing:border-box}}body{{margin:0;padding:24px;font:14px/1.5 system-ui,sans-serif;background:var(--bg);color:var(--fg)}}
h1{{font-size:20px;margin:0 0 4px}}.sub{{color:var(--mut);margin:0 0 20px}}
.cards{{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:24px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 18px;min-width:110px}}
.card .num{{font-size:26px;font-weight:700}}.label{{color:var(--mut);font-size:12px;text-transform:uppercase;letter-spacing:.04em}}
.ok{{color:var(--ok)}}.bad{{color:var(--bad)}}.muted{{color:var(--mut)}}
.bar{{height:10px;border-radius:5px;background:var(--bad);overflow:hidden;margin:6px 0 24px}}
.bar>i{{display:block;height:100%;width:{summary['pass_rate']}%;background:var(--ok)}}
table{{width:100%;border-collapse:collapse;margin:8px 0 28px}}
th,td{{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}}
th{{color:var(--mut);font-size:12px;text-transform:uppercase;letter-spacing:.04em}}
pre{{margin:0;white-space:pre-wrap;font:12px/1.4 ui-monospace,monospace;color:var(--bad)}}
.spark{{color:var(--ok);display:block;width:100%;max-width:260px}}h2{{font-size:15px;margin:24px 0 4px}}
</style></head><body>
<h1>Test dashboard <span class={'ok' if summary['failed']==0 else 'bad'}>{summary['pass_rate']}% pass</span></h1>
<p class=sub>{summary['total']} tests across {len(files)} report file(s) · generated {generated}</p>
<div class=bar><i></i></div>
<div class=cards>
<div class=card><div class=label>Total</div><div class=num>{summary['total']}</div></div>
<div class=card><div class=label>Passed</div><div class="num ok">{summary['passed']}</div></div>
<div class=card><div class=label>Failed</div><div class="num {'bad' if summary['failed'] else 'muted'}">{summary['failed']}</div></div>
<div class=card><div class=label>Skipped</div><div class="num muted">{summary['skipped']}</div></div>
<div class=card><div class=label>Duration</div><div class=num>{summary['duration']:.1f}s</div></div>
{trend}
</div>
<h2>By suite</h2>
<table><tr><th>Suite</th><th>Tests</th><th>Passed</th><th>Failed</th><th>Skipped</th><th>Time</th></tr>{rows_suite}</table>
<h2>Slowest {len(slowest)}</h2>
<table><tr><th>Test</th><th>Suite</th><th>Time</th></tr>{rows_slow}</table>
<h2>Failures ({summary['failed']})</h2>
<table><tr><th>Test</th><th>Class/suite</th><th>Message</th></tr>{rows_fail}</table>
</body></html>"""


def main():
    ap = argparse.ArgumentParser(description="JUnit XML -> self-contained HTML dashboard")
    ap.add_argument("patterns", nargs="+", help="JUnit XML file(s) or globs")
    ap.add_argument("-o", "--out", default="dashboard.html")
    ap.add_argument("--top", type=int, default=10, help="slowest N tests to list")
    ap.add_argument("--history", help="JSON file to append this run's summary to (enables trend)")
    ap.add_argument("--fail-under", type=float, default=None,
                    help="exit non-zero if pass-rate < this percent (CI gate)")
    args = ap.parse_args()

    cases, files = collect(args.patterns)
    if not files:
        print("error: no JUnit XML files matched", file=sys.stderr)
        return 2
    summary = summarize(cases)

    history = []
    if args.history:
        if os.path.exists(args.history):
            try:
                history = json.load(open(args.history))
            except (json.JSONDecodeError, OSError):
                history = []
        history.append({"ts": datetime.now(timezone.utc).isoformat(timespec="seconds"), **summary})
        json.dump(history, open(args.history, "w"), indent=2)

    open(args.out, "w").write(render(summary, cases, files, history, args.top))
    print(f"{args.out}: {summary['passed']}/{summary['total']} passed "
          f"({summary['pass_rate']}%), {summary['failed']} failed, {summary['skipped']} skipped")
    if args.fail_under is not None and summary["pass_rate"] < args.fail_under:
        print(f"pass-rate {summary['pass_rate']}% < --fail-under {args.fail_under}%", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Usage:

```bash
python3 tools/junit_dashboard.py "reports/**/*.xml" -o dashboard.html \
  --history .junit-history.json --top 10
# open dashboard.html — no server needed. --fail-under 95 turns it into a CI gate.
```

## Best practices checklist

1. ✅ Make every runner emit **JUnit XML** (the common denominator) — that is
   what the dashboard aggregates.
2. ✅ Aggregate **all suites of a run into one dashboard**, not one report per
   suite the reader has to stitch together.
3. ✅ Track the **trend** (pass-rate, duration) across runs via a small history
   artifact — a single green run hides a slow decay.
4. ✅ Surface the **slowest tests** — perf regressions hide in the long tail.
5. ✅ Show **failure messages inline** so triage doesn't require opening raw logs.
6. ✅ Emit a **self-contained** artifact (inline CSS/JS) that opens without a
   server — portable across CI, Slack, and reviewers' laptops.
7. ✅ Make it **theme-aware (light/dark)** and responsive — people open it on a
   phone from a Slack link.
8. ✅ **Escape** every test name/message rendered into HTML — test data can
   contain markup.
9. ✅ Put commit **SHA + branch + env + run URL** in the header for traceability.
10. ✅ The dashboard **reports; the runner gates.** A pretty report must never
    let a red build merge — keep the runner's non-zero exit.
11. ✅ Publish the dashboard as a **CI artifact** and/or to **Pages**, and link
    it from the PR.
12. ✅ For rich per-step history, retries, attachments and categories, use
    **Allure** (`allure-history` for trends).
13. ✅ For performance, use **k6's web dashboard** or **k6 → Grafana** time-series
    — a pass/fail view is the wrong shape for RPS/p95/VU curves.
14. ✅ Name suites and scenarios clearly (**Gherkin scenario names** per the
    BDD-first standard) so the dashboard reads as living documentation.
15. ✅ Carry **history between CI runs** via `actions/cache` or a dedicated
    results branch — history is worthless if it resets each build.
16. ✅ Add a **flaky/quarantine view** — mark tests that flip pass/fail across
    recent runs.
17. ✅ Generate the report **after** the run, from artifacts — never on the
    critical test path.
18. ✅ **Redact secrets/PII** from failure messages before publishing.
19. ✅ Prefer **standard formats** (JUnit XML, Allure results) over bespoke ones
    — everything interops with them.
20. ✅ Never parse **untrusted** XML with a naive parser — refuse `<!DOCTYPE`/
    `<!ENTITY>` (as the generator does) or use `defusedxml`.

## Canonical patterns

### Allure (rich report + history/trends)

```bash
# adapters emit allure-results/: allure-playwright, allure-pytest,
# allure-cypress, io.qameta.allure:allure-junit5 (Maven/Gradle)
cp -r allure-report/history allure-results/ 2>/dev/null || true   # carry trend
allure generate allure-results --clean -o allure-report
allure open allure-report            # local; or publish allure-report/ to Pages
```

### k6 → Grafana / built-in web dashboard

```bash
# built-in, self-contained HTML (k6 >= 0.49):
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=k6-report.html k6 run script.js
# time-series into Grafana (import dashboard 2587 for InfluxDB):
k6 run --out influxdb=http://localhost:8086/k6 script.js
# or Prometheus remote-write:
K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write k6 run -o experimental-prometheus-rw script.js
```

### GitHub Actions — job summary + published artifact

```yaml
- name: Build test dashboard
  if: always()                                  # run even when tests failed
  run: |
    python3 tools/junit_dashboard.py "reports/**/*.xml" -o dashboard.html \
      --history .junit-history.json | tee -a "$GITHUB_STEP_SUMMARY"
- uses: actions/upload-artifact@v4
  if: always()
  with: { name: test-dashboard, path: dashboard.html }
# inline PR annotations from the same JUnit XML:
- uses: dorny/test-reporter@v1
  if: always()
  with: { name: tests, path: 'reports/**/*.xml', reporter: java-junit }
```

## Common pitfalls / anti-patterns

- ❌ **Console-only output** — no artifact a reviewer can open after the run.
- ❌ **A pretty report that hides a red build** — the report is not the gate;
  keep the runner's non-zero exit.
- ❌ **Latest-run-only** — no trend, so slow decay and creeping flakiness go
  unseen.
- ❌ **History that resets every CI run** — not cached/persisted between builds.
- ❌ **Un-escaped test data** rendered into HTML (breaks layout, enables
  injection into the report).
- ❌ **Parsing untrusted XML naively** — XXE / billion-laughs; refuse DTDs or use
  `defusedxml`.
- ❌ **Publishing a report with secrets/PII** in failure messages or attachments.
- ❌ **One dashboard per suite** the reader must mentally merge — aggregate.
- ❌ Using a **pass/fail dashboard for performance** — perf needs time-series
  (Grafana / k6 dashboard), not a green bar.

## Testing & validation

- Generator self-check: `python3 tools/junit_dashboard.py "reports/*.xml" -o d.html`
  then open `d.html`; the printed line (`x/y passed (z%)`) must match the runners.
- Feed a **known** JUnit XML (n passed / m failed) and assert the totals render.
- Confirm a malformed or DTD-bearing file is **skipped with a warning**, not
  crashing or expanding.
- Allure: `allure generate --clean` exits zero and `index.html` opens.
- CI: the dashboard is attached as an artifact and the job summary shows the line.

## Performance & tuning

- Generation is cheap (XML parse + string build); keep it **off the critical
  path** — run after tests, from artifacts.
- For thousands of cases, the single-file HTML stays small (no per-test assets);
  Allure is heavier but gives history/attachments.
- Cache/restore `.junit-history.json` (or Allure `history/`) between runs so the
  trend survives without bloating the repo.

## Security (top 5)

1. **Untrusted XML** — stdlib parsers are vulnerable to XXE and billion-laughs;
   the generator refuses `<!DOCTYPE`/`<!ENTITY>` before parsing and prefers
   `defusedxml` when installed. Don't remove that guard.
2. **No secrets/PII in reports** — failure messages and attachments often leak
   tokens, emails, payloads; redact before publishing to Pages/artifacts.
3. **Access-control published dashboards** — a public Pages site exposes your
   test surface, endpoints, and data shapes; gate internal reports.
4. **Escape all rendered test data** — names/messages are attacker-influenced in
   some suites; always HTML-escape.
5. **Trust boundary on CI artifacts** — treat downloaded result XML from forks
   as untrusted input to the generator.

## Official docs & references

- JUnit XML schema (de-facto): https://github.com/testmoapp/junitxml
- Allure report: https://allurereport.org/docs/
- Allure history/trends: https://allurereport.org/docs/history-and-retries/
- k6 web dashboard: https://grafana.com/docs/k6/latest/results-output/web-dashboard/
- k6 outputs (InfluxDB/Prometheus): https://grafana.com/docs/k6/latest/results-output/
- GitHub Actions job summaries: https://docs.github.com/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary
- dorny/test-reporter: https://github.com/dorny/test-reporter
- mikepenz/action-junit-report: https://github.com/mikepenz/action-junit-report
- defusedxml (hardened XML): https://github.com/tiran/defusedxml
