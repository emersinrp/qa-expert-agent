---
name: mobile-tests
description: Use this skill for mobile E2E testing across stacks — Flutter `integration_test`, iOS native `XCUITest`, React Native `Detox`, Maestro cross-platform flows. Trigger on "integration_test", "XCUITest", "Detox", "Maestro", "mobile E2E", "tap on element", "accessibility identifier", "UI test host". Use ONLY for mobile native / RN / Flutter tests; for web E2E use playwright / cypress skills.
---

# Mobile E2E Testing Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Mobile app E2E (Flutter, native iOS, React Native) | Pure widget unit tests (use Vitest / XCTest / flutter_test) |
| Cross-platform flows in Maestro when a thin layer is enough | Performance tests (use XCode Performance / flutter driving_test perf) |
| Setting screenshots & OTA release tests | Web-based mobile viewport tests (use Playwright mobile viewports) |

## Core stack & versions

- **Flutter `integration_test`** package: ships with Flutter SDK ≥ 3.0;
  replaces the older `flutter_driver` (do not use `flutter_driver`).
- **iOS `XCUITest`**: XCTest framework (XCTestCase subclasses with
  `@MainActor`-annotated).
- **React Native `Detox`** latest 20.x — uses WIX Mobile Native Driver; the
  binding integrates with Jest and TS.
- **Maestro** (`mobile.dev`teams) — YAML-driven cross-platform; great for
  one-page smoke flows; uses mobile-dev-provided Studio for authoring.
- **Android Espresso** (when also testing native Android Espresso) — pairs
  with `XCUITest` for iOS parallel.
- **Firebase Test Lab / AWS Device Farm** for real-device lab matrix.

## Project structure (canonical, Flutter example)

```
my_app/
├── integration_test/
│   ├── app_test.dart
│   ├── helpers/                    # shared test helpers
│   │   └── auth_helper.dart
│   ├── pages/
│   │   └── login_page.dart
│   └── smoke_test.dart
└── lib/
```

## Best practices checklist

### Flutter `integration_test`

1. ✅ Use the official `integration_test` package, not `flutter_driver`.
2. ✅ Initialize with `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`
   at top of the test file.
3. ✅ Use `tester.tap(find.byKey(Key('email')))` or `find.byType` /
   `find.byTooltip` — prefer **Key** + byValueKey for production code.
4. ✅ Use `find.bySemanticsLabel` when testing accessibility labels —
   verifies both test identity and a11y labelling in one go.
5. ✅ Pump-and-settle: `await tester.pumpAndSettle(Duration(seconds: 1));`
   after every non-trivial animation. Set the duration explicitly to bound
   waits.
6. ✅ For long-running async ops: `pump(Duration(seconds: 2))` instead of
   `pumpAndSettle` when network calls + spinners won't settle until you wait.
7. ✅ Press back via `await tester.pageBack();` — backs through Navigator
   stack safely.
8. ✅ Use `WidgetController` for native events where pump isn't enough.
9. ✅ Test golden images via `matchesGoldenFiles` (deprecated name) →
   `matchesReference` snapshot test.
10. ✅ Run device-specific suites: `flutter test integration_test/ -d
   iPhone 15` and `-d "Pixel 7"`.
11. ✅ Use `testWidgets('Title (a11y): action', ...)` — annotate title with
   `a11y:` prefix when the case is focused on a11y.

### iOS `XCUITest`

12. ✅ One `XCUITestCase` subclass per feature area, inheriting a base for
    setup/teardown.
13. ✅ Use `app.buttons["Sign In"]` (accessibility identifier) — set
    `accessibilityIdentifier` in production code on key elements.
14. ✅ Use `app.textFields["Email"]` with the **accessibility label**, not
    the placeholder text (`.placeholders` is fragile).
15. ✅ Wait for elements: `let button = app.buttons["Sign In"];
    expectation(for: NSPredicate(format: "exists == YES"), handler: nil)`
    or `.waitForExistence(timeout: 5)`..waitForExistence adds timeout bound.
16. ✅ Use `app.swipeUp(velocity: .fast)` rather than fixed-offset swipes —
    resilient to dynamic type sizing.
17. ✅ Snapshots: use `snapshot("01_initial_state")` (XCTest Attachments)
    for visual diffs in CI reports.
18. ✅ Decay-tolerant selectors: `app.buttons.matching(.button,
    identifier: "...")` lets you pick ambiguous selectors with chaining.
18. ✅ Test on real-device UI tests in CI via `xcodebuild test \
    -destination 'platform=iOS,name=iPhone 15'`.
20. ✅ Clean derived data between runs — derived data persists between CI
    runs and causes flakiness if uncleaned.
21. ✅ Use **Launch Arguments / Launch Environment** to seed state:
    `app.launchArguments += ["-UITEST_SEED_USER", "alice"]; app.launchEnvironment["API_BASE_URL"]
    = "https://staging..."`.

### React Native `Detox`

22. ✅ Detox Startup config (`detox.config.js`) — `configurations` per env
    (ios.sim.debug / ios.sim.release / android.emu.release).
23. ✅ Use **`testID`** prop in RN components and `element.byId(testID)`
    in tests — same `data-testid` philosophy on web.
24. ✅ Match in components: `<TouchableOpacity testID="login.submit" />`
    and `await waitFor(element(by.id('login.submit')))
    .toBeVisible().withTimeout(5000)`.
25. ✅ Use `device.reloadReactNative()` between tests, NOT
    `device.launchApp({ newInstance: true })` unless demanded — far
    faster; the bridge stays warm.
26. ✅ Mock network via `detox.beforeEach(async () => { await networkMock.start(); })`
    with `nock`/`msw` for deterministic UI state.
27. ✅ Use `await device.setURLBlacklist(['.*'])` for telemetry / analytics
    calls.
28. ✅ Run on real iPhone via `--configuration ios.sim.release` for parity.

### Maestro cross-platform

29. ✅ Use Maestro Studio to record flows: `maestro studio` opens a
    window you click through; writes YAML line by line.
30. ✅ Keep flows small ("login", "checkout") not end-to-end end-to-end
    suites; chain through `runFlow` in main flows.

### Common / CI

31. ✅ Use **Firebase Test Lab** or **AWS Device Farm** for matrix device
    runs once a day; weekly releases are gates in nightly, not PR-blocking.
32. ✅ Parallelize via sharded suites with one device per shard.
33. ✅ No real backend — test against staging or `nock`-mocked RN.
34. ✅ For iOS, run tests on a real automation-enabled device; simulator
    flake is real.

## Canonical patterns

### Flutter integration_test (login flow)

```dart
// integration_test/login_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_app/main.dart' as app;
import 'package:my_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('User can log in', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.byKey(const Key('email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Welcome'), findsOneWidget);
  });
}
```

Run: `flutter test integration_test/login_test.dart -d "iPhone 15"`.

### iOS XCUITest (login)

```swift
// AppUITests/LoginUITests.swift
import XCTest
final class LoginUITests: XCTestCase {
  func testUserCanLogIn() throws {
    let app = XCUIApplication()
    app.launchEnvironment["API_BASE_URL"] = "https://staging.example.com"
    app.launchArguments += ["-UITEST_SEED_USER", "alice"]
    app.launch()

    let email = app.textFields["Email"]
    XCTAssertTrue(email.waitForExistence(timeout: 5))
    email.tap()
    email.typeText("a@b.com")

    let pwd = app.secureTextFields["Password"]
    pwd.tap()
    pwd.typeText("secret123")

    app.buttons["Sign In"].tap()

    XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
  }
}
```

Run: `xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'`.

### React Native Detox (login)

```ts
// e2e/login.e2e.ts
describe('Login', () => {
  beforeAll(async () => {
    await device.launchApp({ newInstance: true, permissions: { notifications: 'YES' } });
  });

  it('shows welcome after submit', async () => {
    await element(by.id('email')).tap();
    await element(by.id('email')).typeText('a@b.com');
    await element(by.id('password')).typeText('secret123\n');
    await element(by.id('submit')).tap();
    await expect(element(by.text('Welcome'))).toBeVisible();
  });
});
```

### Maestro YAML

```yaml
# .maestro/login.yaml
appId: com.example.myapp
---
- launchApp:
    clearState: true
- tapOn:
    id: "email"
- inputText: "a@b.com"
- tapOn:
    id: "password"
- inputText: "secret123"
- tapOn:
    text: "Sign In"
- assertVisible:
    text: "Welcome"
```

## Common pitfalls / anti-patterns

- ❌ `flutter_driver` (legacy) — switch to `integration_test`.
- ❌ Wait without timeout in `XCUITest` `.waitForExistence()` — defaults to
  too short; explicitly pass `timeout:`.
- ❌ `app.buttons["Submit"]` (text) instead of accessibility identifier —
  fragile to localization; set `accessibilityIdentifier` on production
  code.
- ❌ Detox `device.launchApp({ newInstance: true })` on every test —
  devastation of speed; use `reloadReactNative()` where state reset is
  sufficient.
- ❌ Maestro flows longer than 30 steps — keeps refactor by extracting
  partial flows into separate `.yaml` files via `runFlow:`.
- ❌ Real prod credentials in CI launch environment.
- ❌ Tests against real network (slow; flaky) — mock or use staging.
- ❌ Simulators with derived data not cleared between CI runs.
- ❌ Detox tests without retry: CI endpoints vs Bash-detached commands
  cause occasional flake for cold network.

## Testing & validation

- Flutter: `flutter test integration_test/` runs all in host side; for
  device runs add `-d <device>`.
- iOS: `xcodebuild test -scheme MyApp -destination 'platform=iOS
  Simulator,name=iPhone 15'` runs all `XCUITest` cases in test plan.
- Detox: `detox test -c ios.sim.release` runs `e2e/*.e2e.ts` via Jest.
- Maestro: `maestro test .maestro/login.yaml` runs the flow once;
  supports `--format junit` for CI integration.
- Detox + Jest: snapshots via network mock + Jest's `toMatchSnapshot`.

## Performance & tuning

- iOS `XCUITest` on real device is faster than simulator for network and
  animations (simulator uses Mac CPU for round-trip networking).
- Detox WIX adaptive test id lookup is fast; avoid using
  `element(by.label('Sign'))` which searches across UITree.
- Flutter integration tests run flake-free in host mode (`flutter test
  integration_test`); for device fidelity run on a real device.
- Detox uses parallel workers: `"workers": 3` in detox.config; gate with
  `maxWorkers` based on CI CPU.
- Maestro Studio runs locally with a USB-connected device — author-time
  iterations are quick (~1s per step).

## Security (top 5)

1. **No real credentials** — use `launchEnvironment` / Dart env to seed
   test-only users without MFA, room for test-only fallback auth.
2. **TestID audit** — don't leak authentication UI flow with real names
   (alice@company.com); use `test.invalid` emails.
3. **Test snapshots** can contain rendered PII of test users — ephemeral
   only; never persist to long-term storage.
4. **Device Farm upload** of binaries to AWS / Firebase — scope IAM to
   your project; rotate access keys for upload.
5. **Maestro Cloud tokens** stored as CI secrets; never in `.maestro/`.

## Official docs & references

- Flutter integration_test: https://docs.flutter.dev/testing/integration-tests
- XCTest / XCUITest: https://developer.apple.com/documentation/xctest
- XCUITest tutorial: https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html
- Detox docs: https://wix.github.io/Detox/
- Detox config reference: https://wix.github.io/Detox/docs/introduction/project-setup
- Maestro docs: https://maestro.mobile.dev/
- Maestro Studio: https://maestro.mobile.dev/cli/maestro-studio
- Firebase Test Lab: https://firebase.google.com/docs/test-lab
- AWS Device Farm: https://aws.amazon.com/device-farm/
- Espresso (Android): https://developer.android.com/training/testing/espresso