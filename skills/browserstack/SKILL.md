---
name: browserstack
description: Use this skill for BrowserStack App Automate (mobile E2E on real devices) and App Live (manual/interactive mobile testing) — uploading apps, configuring capabilities (bstack:options), running XCUITest / Espresso / Detox / Appium suites on cloud, parallel sharding, local testing tunnel (Local/Gateway), CI integration, screenshots and video artifacts, observability dashboard. Trigger on "BrowserStack", "App Automate", "App Live", "bstack:options", "browserstack local", "browserstack appium", "browserstack xcuitest", "browserstack espresso", "browserstack detox", "BS_USER", "BS_ACCESS_KEY". Use ONLY for BrowserStack device-farm work; for local mobile E2E authoring use mobile-tests skill, for guidance picking a device farm use mobile-tests skill.
---

# BrowserStack Best Practices (App Automate + App Live)

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Run mobile E2E on real iOS / Android devices in CI | Local emulator/simulator dev loop (faster + free; use mobile-tests skill) |
| Verify parity across dozens of device/OS combos without buying hardware | Visual regression on web (use Percy / Chromatic — different products) |
| Manual QA needs interactive access to a real device they don't own | Need to test on a device with specific carrier / SIM not in BrowserStack catalog |
| Reproduce a bug reported on a specific device/OS combination | Need raw Instruments / Android profiler traces (not fully exposed in cloud) |

## Core stack & versions

- **BrowserStack App Automate**: cloud execution of `XCUITest` (iOS),
  `Espresso` / `UIAutomator2` (Android), `Detox` (RN), `Appium` (cross).
- **BrowserStack App Live**: interactive manual sessions on real devices
  (upload app + scroll/swipe via browser).
- **BrowserStack Local** (formerly `LocalClient`) and the newer
  **BrowserStack Gateway** — tunnels between cloud session and your
  private network when the app talks to internal/test APIs.
- REST API: `https://api-cloud.browserstack.com/` for app upload,
  build status, device list, builds/sessions retrieval. Auth = HTTP Basic
  `USERNAME:ACCESS_KEY`.
- CLI: `BrowserStackLocal` binary (replaced by Gateway for some flows).
- Capability namespace: `bstack:options` block inside `MutableCapabilities`
  (Selenium 4 / Appium-like). Carries credentials, project, session name,
  device list, etc.

## Project structure (canonical)

```
project/
├── browserstack/
│   ├── configs/
│   │   ├── xcuitest.json             # capabilities for XCUITest runs
│   │   ├── espresso.json             # capabilities for Android Espresso runs
│   │   ├── detox.json                # capabilities for RN Detox runs
│   │   └── appium.json                # capabilities for Appium (cross)
│   ├── upload_app.sh                  # curl to upload .ipa/.apk/.aab
│   └── README.md                      # how to run / rotate credentials
├── .github/workflows/mobile-e2e.yml   # CI that triggers BrowserStack runs
└── browserstack.env.example
```

Capabilities as JSON in `browserstack/configs/` so they are diff-friendly and
lang-agnostic. The CI job loads them and passes via `--config-file`
(equivalent varies per runner).

## Best practices checklist

1. ✅ **Credentials via env, never JSON files committed.** `BROWSERSTACK_USERNAME`
   + `BROWSERSTACK_ACCESS_KEY`; `bstack:options` reads them at runtime in CI.
2. ✅ Use **named `bstack:options`** sub-object in capabilities — sensible
   values like `projectName`, `buildName`, `sessionName` (incl. git SHA),
   `app`, `device`, `osVersion`, `realDevice: true`. rrename sessions by
   feature for the dashboard.
3. ✅ Always include the **git SHA** in `buildName`: `"orders-api #${GIT_SHA}"`
   → dashboard links build → CI run → commit.
4. ✅ Prefer **`realDevice: true`** — coverage parity with production; simulators/emulators
   miss carrier, sensor, and some GPU/rendering behaviors.
5. ✅ **Pin device + OS version** explicitly (`device: "iPhone 14", osVersion: "17"`)
   — `deviceName`'s `"*"` wildcard is convenient but produces flaky cross-run
   comparisons; pin the matrix for regression suites.
6. ✅ Run a **`matrix`** of devices via parallel capabilities files; the API
   accepts an array of capability objects to spawn parallel sessions.
7. ✅ **App upload once per CI run** — upload `.ipa`/`.apk` once via the
   REST API, get back `bs://<app_id>`, then reference that URL across all
   parallel sessions. Re-uploading per session wastes minutes.
8. ✅ Use the **`Custom ID`** feature (`custom_id` in upload endpoint params)
   to give your app a stable URL across runs: `custom_id=myteam-ordersapp-staging`
   → subsequent uploads with the same custom_id re-point; CI fetches
   `bs://myteam-ordersapp-staging`.
9. ✅ The **Local / Gateway tunnel is opt-in per session**: set
   `localTesting: true` in `bstack:options`. Only enable when the build
   needs to hit internal env; otherwise skip — saves bandwidth and cold-start.
10. ✅ Start the **BrowserStackLocal binary before** the test run and
    **stop after** — plugin via CI teardown hook so both ends of the tunnel
    are torn down together.
11. ✅ With BrowserStack Gateway (newer), tunnel is one binary that auto-handles
    reconnection; prefer Gateway over the legacy Local binary when available.
12. ✅ **Network logs, device logs, screenshots, video** are captured
    automatically when `debug: true`, `networkLogs: true`,
    `deviceLogs: true` are set in `bstack:options`. Use sparingly in CI
    (space/bandwidth) — enable `debug` only for known-flaky sharded runs.
13. ✅ **Timeouts**: `idleTimeout` (max session idle) and `networkTimeout`
    have default caps — override only when your suite is reliably slower
    than default; never raise above 300s without a measured reason.
14. ✅ **Parallelism**: App Automate splits based on the array length of
    capabilities submitted at once. Target 10-50 parallel slots depending
    on your team plan; overcommit beyond plan limit → queueing → false
    test failures.
15. ✅ **Retries**: BrowserStack does NOT auto-retry failing sessions by
    default. Use `bstack:options.retries` (UIA-style) OR add a 1-retry
    wrapper in CI: `if !run; then run; fi`. Track flake count in the
    dashboard.
16. ✅ **Quarantine flaky tests** by gating specific specs behind a
    branch flag; combine with BrowserStack's flake tag in sessionName:
    `"login (flake=high)"`.
17. ✅ **App Live for manual triage**: when a CI run fails on a specific
    device/OS, link to an App Live session at the same combo from the pull
    request report so the reviewer can spin that exact device immediately.
18. ✅ **App Live session milestones**: use the `marker` button within the
    session to tag steps (`login → submit → success`) — appears in the
    session report and becomes the basis of an automated test script.
19. ✅ **Master device list** via REST: `GET
    https://api-cloud.browserstack.com/app-automate/devices.json` —
    cache the result weekly (devices change monthly). CI lints new devices
    into the matrix.
20. ✅ Tie **`sessionName` to a user-readable test identifier** (feature +
    device), e.g. `"Login flow — iPhone 14 iOS 17"`. Dashboard heavy-use
    and reviewers bless you later.
21. ✅ For Detox: build detector is `.test.apk`/`.app`; run Detox on
    BrowserStack via the `detox test --configuration browserstack.release`
    + custom ` detox.config.js` `launchArgs` exposing BS creds + ssh.
22. ✅ For XCUITest: run on BrowserStack via `xcuitest-runner` CLI or via
    the `xcodebuild test -scheme ... -destination platform=...` and specify
    `BROWSERSTACK_*` env, BS uploads tests **+** app together automatically
    when run via their CLI.
23. ✅ For Espresso **only upload the test apk and the app apk separately**
    via REST and reference both in capabilities (`app` + `testApp`).
24. ✅ **Session tagging REST endpoint** can update a session post-run:
    `PATCH /app-automate/sessions/:id.json` → set `status=failed/passed`
    for clean reporting.
25. ✅ For Latency-sensitive tests: pick a region closer to your backend
    (`bstack:options.region: "EU"` if backend EU).

## Canonical patterns

### Capabilities JSON (Appium, iOS, single session)

```json
{
  "platformName": "iOS",
  "automationName": "XCUITest",
  "app": "bs://myteam-ordersapp-staging",
  "deviceName": "iPhone 14",
  "platformVersion": "17",
  "realDevice": "true",
  "bstack:options": {
    "projectName": "orders-api",
    "buildName": "orders-api #${GIT_SHA}",
    "sessionName": "Login flow — iPhone 14 iOS 17",
    "userName": "${BROWSERSTACK_USERNAME}",
    "accessKey": "${BROWSERSTACK_ACCESS_KEY}",
    "localTesting": "true",
    "networkLogs": "true",
    "deviceLogs": "true",
    "debug": "false",
    "idleTimeout": "120",
    "region": "US"
  }
}
```

### App upload via REST (shell)

```bash
#!/usr/bin/env bash
# browserstack/upload_app.sh
set -euo pipefail

APP_PATH="$1"
CUSTOM_ID="${2:-myteam-ordersapp-staging}"

curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/upload" \
  -F "file=@$APP_PATH" \
  -F "custom_id=$CUSTOM_ID"
# Response: { "app_url": "bs://abc...", "custom_id": "myteam-ordersapp-staging" }
# Stable id keeps returning that custom_id; CI uses `bs://myteam-ordersapp-staging`.
```

### BrowserStackLocal tunnel in CI (GitHub Actions)

```yaml
jobs:
  mobile-e2e:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - run: |
          # Install and start Local binary
          wget -qO BrowserStackLocal.zip \
            "https://www.browserstack.com/browserstack-local/BrowserStackLocal-darwin-x64.zip"
          unzip -q BrowserStackLocal.zip
          ./BrowserStackLocal --key $BROWSERSTACK_ACCESS_KEY \
            --local-identifier "orders-${{ github.sha }}" &
          echo $! > local.pid
      - run: ./browserstack/upload_app.sh app/build/outputs/apk/staging/app-staging.apk
      - run: mvn test -Dsuite=mobile -DBROWSERSTACK_LOCALID="orders-${{ github.sha }}"
      - if: always()
        run: kill $(cat local.pid)
```

### XCUITest runner (Swift)

```swift
// AppUITests/BrowserStackTests.swift
import XCTest

final class BrowserStackTests: XCTestCase {
  override class var runsForEachTargetUIState: Bool { false }

  func testLogin() {
    let app = XCUIApplication()
    app.launchEnvironment["API_BASE_URL"] = "https://staging.example.com"
    app.launch()

    app.textFields["Email"].tap()
    app.textFields["Email"].typeText("a@b.com\n")

    let pwd = app.secureTextFields["Password"]
    pwd.tap(); pwd.typeText("secret123\n")

    app.buttons["Sign In"].tap()
    XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 8))
  }
}
```

Run on BrowserStack:
```bash
BS_APP_URL=bs://myteam-ordersapp-staging
BS_TEST_PACKAGE=RunnerTests.zip   # ZIP with XCTest run plan
curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/xcuitest/test-suite" \
  -F "file=@$BS_TEST_PACKAGE"
```

### Detox config (RN)

```js
// detox.config.js
module.exports = {
  configurations: {
    "browserstack.android": {
      type: "android.android",
      binaryPath: "Android/app.apk",
      build: "...",
      artifactsLocation: "artifacts/",
      testBinaryPath: "Android/app_test.apk",
      device: {
        type: "android.browserstack",
        device: "Google Pixel 7",
        osVersion: "13",
        browserstackOptions: {
          userName: process.env.BROWSERSTACK_USERNAME,
          accessKey: process.env.BROWSERSTACK_ACCESS_KEY,
          app: "bs://myteam-ordersapp-staging",
          realDevice: true,
          localTesting: true,
        },
      },
    },
  },
};
```
Run: `detox test -c browserstack.android --workers 4`.

## Common pitfalls / anti-patterns

- ❌ Hard-coding `BROWSERSTACK_ACCESS_KEY` in committed JSON or env files —
  always CI secrets; rotate quarterly.
- ❌ Uploading the same `.ipa`/`.apk` per session instead of per CI run —
  adds minutes × slots; cache the `bs://` URL.
- ❌ `device: "*"` wildcard for regression suites — different device per run
  loses reproducibility; pin the matrix.
- ❌ Forgetting to **stop BrowserStackLocal** in CI teardown → orphan
  processes + tunnel stays open (billed/idle).
- ❌ Routing prod URLs in a tunnel back from a real device — exposes prod
  to device telemetry / cache poisoning. Use staging env.
- ❌ Skipping `bstack:options.buildName`/`sessionName` — dashboard becomes
  unsearchable over time; reviewers can't find the failing session.
- ❌ Treating App Live sessions as E2E — manual; no CI gate. Use them for
  triage, not as a regression layer.
- ❌ Re-running a build via BrowserStack REST `POST /builds/:id/retry` and
  expecting stable coverage if device list drifted between runs — pin devices.
- ❌ For Espresso: not uploading `testApp` alongside `app` — runs fail with
  cryptic "no instrumentation found".
- ❌ Setting `networkLogs: true` globally — for high-volume sessions,
  dashboard storage / bandwidth budget grows fast; enable per flaky spec.
- ❌ Using `idleTimeout: 600` to mask slow tests — fix the slowness instead;
  BrowserStack counts session time against your plan.

## Testing & validation

- After upload, sanity-check the recent app URL:
  `GET https://api-cloud.browserstack.com/app-automate/recent_apps` —
  confirm the latest custom_id points at your current SHA build.
- **Smoke run before parallelization**: run the full suite on **one device**
  with the new app version + new tests; only expand to the matrix once
  green. The one-device smoke flags 80% of capability bugs.
- **Device parity check**: pair a rare device (iPhone 14 Pro with iOS 17 beta)
  with a mainstream one (iPhone 13 iOS 16) — catches regression introduced
  by new OS only after parallelism.
- **Tunnel health probe**: hit a localhost-only endpoint from inside the
  device via the app → if it loads, the local tunnel works. Add this as a
  `test local accessible` smoke spec.
- **Session tagging** post-run: `PATCH /sessions/:id.json { "status": "passed" }`
  keeps Batch dashboards accurate (CI may know pass/fail before the session
  completed).
- Weekly audit: list 5 highest-flake sessions; tag with `flake-review` and
  open tickets.

## Performance & tuning

- **Parallel slots**: align to your plan; overcommit = queue + flake. Use
  "Build Insights" panel to monitor real concurrency.
- **Run identification**: tag by feature or service, not by team alone —
  dashboard aggregations on feature enable faster triage.
- **App size**: minify the `.apk` (R8) and the `.ipa` (strip debug
  symbols) before upload; larger binaries → longer per-session bootstrap.
- **Idle elimination**: `idleTimeout: 120` (default ~300s is too lenient);
  stuck sessions wrongly count against plan.
- **Caching** the device list response weekly: `GET /app-automate/devices.json`
  static pinned file in CI; only refresh after release of new device.
- **Sharding for Espresso/XCUITest**: BrowserStack auto-subs the test list
  into slots; ensure tests are independent (no order dependence).
- **Network region**: pick `region: "EU"` / `"US"` whichever is closer to
  your backend; cuts device-to-backend RTT dramatically.

## Security (top 5)

1. **No app secrets in uploaded binaries** — strip API keys from debug builds;
   inject via launch env.
2. **Tunnel tokens / access keys** in CI secrets only; never logged.
3. **Local-testing identifier (`--local-identifier`)** per CI job (SHA) so
   tunnels don't cross-collide across builds.
4. **Permission scope**: BrowserStack user role for CI is "automation" only,
   not admin; auditor role can read dashboards without spin-up.
5. **App Live session sharing**: a session URL is unauthenticated-accessible
   if shared publicly — link with PR reviewers via direct message / private
   channels, not public issue trackers.

## Official docs & references

- BrowserStack docs (all products): https://www.browserstack.com/docs/
- App Automate home: https://www.browserstack.com/app-automate
- App Live home: https://www.browserstack.com/app-live
- XCUITest on App Automate: https://www.browserstack.com/docs/app-automate/xcuitest/getting-started
- Espresso on App Automate: https://www.browserstack.com/docs/app-automate/espresso/getting-started
- Detox on App Automate: https://www.browserstack.com/docs/app-automate/detox/getting-started
- Appium on App Automate: https://www.browserstack.com/docs/app-automate/appium/getting-started
- Capabilities reference: https://www.browserstack.com/docs/app-automate/appium/desired-capabilities
- REST API: https://www.browserstack.com/docs/app-automate/api-reference
- BrowserStack Local: https://www.browserstack.com/docs/app-automate/local-testing
- BrowserStack Gateway (local alternative): https://www.browserstack.com/docs/local-testing/gateway
- Device list endpoint: https://www.browserstack.com/docs/app-automate/api-reference/devices
- CI integrations: https://www.browserstack.com/docs/app-automate/integrations/ci
- Build insights / flakes: https://www.browserstack.com/docs/app-automate/build-insights