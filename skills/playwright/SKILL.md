---
name: playwright
description: Use this skill for Playwright Test Runner work (Node/TS/JS) — end-to-end web tests, cross-browser (chromium/firefox/webkit), fixtures, locators, auto-waiting, assertions (`expect(locator).toBeVisible()`), page-object model, `@axe-core/playwright` for a11y, trace viewer debugging, sharded CI runs, parallel workers, custom fixtures, `playwright.config.ts`. Trigger on "Playwright", "test runner", "page.goto", "expect(locator)", "playwright.config", "Trace Viewer", "@axe-core/playwright", `page.route`. Use ONLY for Playwright Test; for Cypress use cypress skill.
---

# Playwright Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Modern E2E on web (any framework) | Component unit tests — use Vitest/Jest with @testing-library |
| Cross-browser matrix (Chromium, Firefox, WebKit) in one run | Load testing — use k6/locust instead |
| Visual regression + a11y in one crawl | Mobile native app (use mobile-tests skill) |

## Core stack & versions

- **@playwright/test** latest stable (`^1.40+`). Pin per project.
- Node 18+ required; Node 20 LTS recommended.
- Browsers installed via `npx playwright install` (or pinned with
  `package.json` `--with-deps` for system libs in CI).
- Languages: TS (default) / JS / Python (`@playwright/test` Python port) /
  Java / .NET. The skill assumes the JS/TS flavor here; for Python etc. the
  idioms translate.
- Reports: built-in HTML / JSON / JUnit XML. Add `allure-playwright` if needed.
- Companion ecosystem: `@axe-core/playwright` (a11y), `playwright-visual-diff`/`@argos-ci/playwright` for visual diff; `@playwright/test-nightly` preview.

## Project structure (canonical)

```
project/
├── package.json
├── playwright.config.ts
├── tests/
│   └── e2e/
│       ├── fixtures.ts                # shared fixtures (user, auth state)
│       ├── pages/                     # page-object modules
│       │   ├── login.page.ts
│       │   └── dashboard.page.ts
│       ├── login.spec.ts
│       └── dashboard.spec.ts
├── tests-examples/                    # optional starter examples (scaffold from CLI)
└── .github/workflows/playwright.yml
```

`playwright.config.ts` defines projects (browsers × envs). Fixtures extend
`test` from `@playwright/test`.

## Best practices checklist

1. ✅ **`playwright.config.ts` is the source of truth**: browsers, baseURL,
   retries, workers, timeout, expect timeout, trace settings.
2. ✅ Use **baseURL** + relative paths in tests (`page.goto('/login')`), not
   full URLs. Switch env via config-level env vars.
3. ✅ Use **`expect(locator)`** web-first assertions over manual `await`s.
   `await expect(page.getByRole('heading')).toHaveText('Welcome')`.
4. ✅ Prefer **role-based locators**: `getByRole('button', { name: 'Sign in' })`,
   `getByLabel('Email')`, `getByText`, `getByPlaceholder`, `getByAltText`,
   `getByTitle`, `getByTestId`. Resilient to markup rewrites.
5. ✅ **Auto-wait**: every action on a Locator auto-retries until actionable.
   Do not add `page.waitForTimeout(500)`—it is the API];
   replace with	assertion.
6. ✅ **Locators are not elements**: `const btn = page.getByRole('button')`
   finds the element lazily; refetches per action. Don't `await locator` as
   an element handle (orphan handle are discouraged).
7. ✅ **Fixtures**: extend `test` for shared setup (auth state, user, page
   object). Never reuse one `page` across independent tests.
8. ✅ **Auth state reuse** via `storageState`: log in once in `globalSetup`,
   save to `storageState.json`, in `projects: [{ use: { storageState } }]`.
9. ✅ **Hooks** `test.beforeEach` for per-test resets; avoid `beforeAll` for
   mutating state. Nest fixtures instead of `beforeAll`.
10. ✅ **`page.route`** to mock/stub network responses with deterministic
    fixtures: `await page.route('**/api/*', (route) => route.fulfill({ json }))`.
11. ✅ **`page.routeFromHAR`** for record/replay-based mocks; great for
    reproducible dev-mode runs without a live backend.
12. ✅ **Sharded parallel** in CI: `--shard=i/n` splits the suite; merge via
    `playwright merge-reports` after matrix completes.
13. ✅ **Retries**: `retries: 2` for CI; `0` for local (faster feedback).
14. ✅ **Trace on failure**: `trace: 'on-first-retry'` so failures always ship
    a trace zip; download trace from the HTML report.
15. ✅ **Screenshots & video on failure**: in `use:` block (`screenshot:
    'only-on-failure'`).
16. ✅ **Page-object model** for non-trivial flows; trivial pages can inline.
   POM files in `tests/e2e/pages/<name>.page.ts`.
17. ✅ **`test.step`** inside long tests to give readable trace + report steps.
18. ✅ **No secrets in code**: read `process.env.STAGING_USER` etc. CI
    injects via OIDC-stored secrets.
19. ✅ **Accessibility**: integrate `@axe-core/playwright` into a smoke test.
20. ✅ **Visual regression**: prefer `toHaveScreenshot()` built-in diffing;
    set `maxDiffPixelRatio: 0.01` to tolerate minor anti-alias drift.
21. ✅ **Multi-environment via projects** (`{ name: 'staging', use: { baseURL:
    STAGE } }`) so suites target multiple envs in one CI run.
22. ✅ **Browser install** via CI baked image OR cache `~/.cache/ms-playwright`.
23. ✅ **Tagged slows**: `test.skip(process.env.CI, 'flaky on CI')` or
    `test.fixme` to quarantine without removing the test.
24. ✅ **Docker image**: `mcr.microsoft.com/playwright:v1.xx-jammy` for CI;
    OR pre-bake system deps via `npx playwright install-deps`.

## Canonical patterns

### `playwright.config.ts`

```ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : '50%',
  reporter: process.env.CI
    ? [['github'], ['html'], ['junit', { outputFile: 'results.xml' }]]
    : 'list',
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox',  use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit',    use: { ...devices['Desktop Safari'] } },
    { name: 'Mobile Chrome', use: { ...devices['Pixel 7'] } },
  ],
});
```

### Locators + assertions

```ts
test('user can sign in', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('a@b.com');
  await page.getByLabel('Password').fill('secret123');
  await page.getByRole('button', { name: /sign in/i }).click();
  await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible();
  await expect(page).toHaveURL(/\/dashboard/);
});
```

### Auth state via fixtures

```ts
// tests/e2e/fixtures.ts
import { test as base, expect } from '@playwright/test';
import { LoginPage } from './pages/login.page';

type Fixtures = { authedPage: Page; loginPage: LoginPage };
export const test = base.extend<Fixtures>({
  loginPage: async ({ page }, use) => { await use(new LoginPage(page)); },
  authedPage: async ({ page }, use) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill(process.env.E2E_USER!);
    await page.getByLabel('Password').fill(process.env.E2E_PASS!);
    await page.getByRole('button', { name: /sign in/i }).click();
    await expect(page).toHaveURL(/\/dashboard/);
    await use(page);
  },
});
export { expect };
```

### Page object

```ts
// tests/e2e/pages/login.page.ts
import { Page, Locator, expect } from '@playwright/test';

export class LoginPage {
  readonly email: Locator;
  readonly password: Locator;
  readonly submit: Locator;
  constructor(readonly page: Page) {
    this.email = page.getByLabel('Email');
    this.password = page.getByLabel('Password');
    this.submit = page.getByRole('button', { name: /sign in/i });
  }
  async goto() { await this.page.goto('/login'); }
  async login(email: string, password: string) {
    await this.email.fill(email);
    await this.password.fill(password);
    await this.submit.click();
    await expect(this.page).toHaveURL(/\/dashboard/);
  }
}
```

### Mock responses

```ts
test('shows empty state', async ({ page }) => {
  await page.route('**/api/orders', (route) =>
    route.fulfill({ status: 200, json: { items: [] } })
  );
  await page.goto('/orders');
  await expect(page.getByText('No orders')).toBeVisible();
});
```

### Accessibility sweep

```ts
import AxeBuilder from '@axe-core/playwright';

test('home has no WCAG violations', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations.filter(v => v.impact === 'critical')).toEqual([]);
});
```

### CI GitHub Actions

```yaml
# .github/workflows/playwright.yml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        shard: [1/4, 2/4, 3/4, 4/4]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npx playwright test --shard=${{ matrix.shard }}
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: html-report, path: playwright-report/ }
```

## Common pitfalls / anti-patterns

- ❌ `page.waitForTimeout(500)` — flaky and slow. Use web-first assertions.
- ❌ CSS / XPath selectors when a role + label works — fragile to markup
  changes.
- ❌ `await page.locator(...)` (returns Locator — not await of an element
  handle). Use `await page.locator(...).click()` (auto-wait handles it).
- ❌ Sharing `page` across tests—potentially slow and order-dependent tests.
- ❌ `beforeAll` mutating a shared DB — leaks state. Use per-test fixture.
- ❌ Forgetting `--with-deps` in CI dockerfile/installs — browsers fail to
  launch without system libs.
- ❌ Real network calls in CI tests — slow + flaky; mock or use a stable
  staging env with seeded data.
- ❌ Visual regression without retries + reviewer flow — generates 1000s of
  false positives on first image-render diffs.
- ❌ Storing `storageState.json` with real PII in the repo — it contains
  session tokens; never commit.
- ❌ Parallel DB writes colliding — use unique usernames per test via
  `Date.now()` or worker index in fixture.

## Testing & validation

- `npx playwright test` runs all configured projects sequentially in CI.
- `npx playwright test --grep "login"` filters by title.
- `npx playwright test --ui` opens the UI mode for local dev.
- `npx playwright show-report` opens HTML report; `show-trace trace.zip` for
  per-test trace inspection.
- `npx playwright codegen <url>` records a script while you click around —
  great drafting tool, but **sanitize** all generated selectors; do not ship
  as-is.
- `npx playwright test --update-snapshots` regenerates baseline screenshots;
  verify the diff in PR review carefully.

## Performance & tuning

- **Workers**: default `50%` of cores; full parallel may exhaust memory on a
  small machine. Set explicit `workers: 4` in CI for predictability.
- **Shards**: split suite into 4-8 shards (one matrix job each) to reduce wall
  time by Nx; merges via `npx playwright merge-reports --reporter html ./blob-report`.
- **projects** filter by folder or test annotation `@smoke` to run smoke in
  fast pipelines vs full in nightly.
- **Dependency install** in CI: prefer the Microsoft Docker image
  (`mcr.microsoft.com/playwright:v1.x-jammy`).
- **Browser install cache**: cache `~/.cache/ms-playwright` in CI to skip
  per-run downloads.
- **Storage state**: avoid repeated logins — once-run `globalSetup` saves
  the session.
- **`connectOptions` / CDP**: reuse existing browser in a remote grid for
  sharded cloud (e.g., BrowserStack).

## Security (top 5)

1. **No secret literals**; CI env vars only. `process.env.E2E_USER`,
   `process.env.E2E_PASS`.
2. **`storageState` tokens** — never commit; treat as credentials; rotate.
3. **Mock PII**: E2E fixtures using email/phone must use clearly fake data
   (`test+1@example.net`) so customer data never ends in screenshots/traces.
4. **CI isolation**: tests must use a dedicated env, never the live prod DB.
5. **Browser sandbox**: keep Chromium launched with `--no-sandbox` only
   inside the CI container; never on dev machines.

## Official docs & references

- Playwright docs: https://playwright.dev/docs/intro
- Test runner API: https://playwright.dev/docs/api/class-test
- Locators guide: https://playwright.dev/docs/locators
- Web-first assertions: https://playwright.dev/docs/test-assertions
- Fixtures & POM: https://playwright.dev/docs/test-fixtures
- Auth state: https://playwright.dev/docs/auth
- CI generators: https://playwright.dev/docs/ci
- Trace viewer: https://playwright.dev/docs/trace-viewer
- HTML reporter: https://playwright.dev/docs/test-reporters#html-reporter
- Sharding: https://playwright.dev/docs/test-advanced#sharded-tests
- @axe-core/playwright: https://github.com/dequelabs/axe-core-npm/tree/develop/packages/playwright
- Codegen: https://playwright.dev/docs/codegen
- VSCode extension: https://playwright.dev/docs/getting-started-vscode