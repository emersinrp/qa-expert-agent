---
name: cypress
description: Use this skill for Cypress work — E2E and component tests, `cy.intercept` network stubbing, custom commands, `data-cy`/`data-testid` selector convention, Cypress Cloud parallel + retries, `cypress run` (headless CI) vs `cypress open` (interactive), plugins (before:spec, after:spec), `@axe-core/cypress` for a11y, `cypress-real-events` for native events. Trigger on "Cypress", "cy.intercept", "cy.get", "data-cy", "Cypress Cloud", "cypress.config.ts", "cypress run", "cypress open", "Cypress component testing". Use ONLY for Cypress; for Playwright use playwright skill.
---

# Cypress Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Already invested in Cypress; happy with its model | Need to test Safari/WebKit (Cypress is Chromium/Firefox/WebKit only via newer versions; historically Chromium) |
| Want an interactive `cypress open` dev loop for the QA team | Need cross-browser matrix on CI at the same run cost as Playwright |
| Component tests live next to E2E tests for the React/Angular/Vue app | Pure unit tests (use Vitest/Jest) |

## Core stack & versions

- **cypress** v13+ (14 stable; 15 around the corner). Pin per project.
- **cypress-real-events** for native events (focus/blur/hover) — needed for
  a11y assertions that depend on real focus.
- **@axe-core/cypress** — a11y command `cy.axe()` / `cy.checkA11y()`.
- **@testing-library/cypress** — semantic queries (`cy.findByRole`).
- **cypress-axe** (legacy name for @axe-core/cypress) — don't use the old.
- Browser scope: Cypress 13+ adds Firefox & WebKit support experimentally;
  Chrome/Edge historically first-class.
- Component testing in Cypress is GA in 13+ — works for React, Vue, Angular.

## Project structure (canonical)

```
project/
├── cypress.config.ts
├── package.json
├── cypress/
│   ├── e2e/
│   │   ├── login.cy.ts
│   │   └── dashboard.cy.ts
│   ├── component/                    # if using Cypress component tests
│   │   └── Button.cy.tsx
│   ├── support/
│   │   ├── e2e.ts                     # imports commands + index
│   │   ├── commands.ts                # custom commands (Cypress.Commands.add)
│   │   └── component.ts               # component mount setup
│   ├── fixtures/                      # JSON fixtures for cy.intercept
│   │   └── user.json
│   └── pages/                          # optional page-object modules
└── .github/workflows/cypress.yml
```

## Best practices checklist

1. ✅ `cypress.config.ts` is the source of truth: `baseUrl`, env vars,
   spec pattern, default timeout, retries (run vs open), screenshot/video.
2. ✅ **`data-cy` / `data-testid`** selector convention. Pick one and stick.
   Never select by fragile class or visible text alone.
3. ✅ **Custom commands** for high-frequency flows (`cy.loginByApi()`,
   `cy.findByDataId(...)`); live in `support/commands.ts`.
4. ✅ **`cy.intercept`** for mocking — returns spies, lets you assert the
   call. `cy.intercept('GET', '/api/me', { fixture: 'user.json' }).as('me')`
   then `cy.wait('@me')`.
5. ✅ Prefer **`cy.intercept` over `cy.server`/`route`** (deprecated).
6. ✅ **No `cy.wait(500)`** — flaky + slow. Use `cy.wait('@alias')` after
   `cy.intercept().as(...)`. Use timings via `cy.findBy...` (testing
   library) which auto-retries.
7. ✅ **Test isolation**: each test resets state — fresh visit, fresh API
   stubs, no shared `before` mutating app state.
8. ✅ **App actions / login shortcuts**: prefer API login (`cy.request({
   method: 'POST', url: '/api/login', body })`) + cookie reuse over UI
   logins for setup. UI login only when login itself is under test.
9. ✅ **Fixtures** for static payloads; use `cy.fixture('user.json')` to
   load.
10. ✅ **`data-testid`**, `aria-label`, `role` via `@testing-library/cypress`
    for resilient queries.
11. ✅ **Restore state afterEach**: clean cookies, localStorage, sessionStorage
    if you're not using full `cy.visit` reloads (which clear for you).
12. ✅ **Retries**: `retries: { runMode: 2, openMode: 0 }` — never in open
    mode (masks flakiness locally); standard 2 for CI.
15. ✅ **`task` plugins** for cross-test Node-side work; e.g., reading
    `fs.access`, generating UUIDs; declare in `cypress.config.ts`
    `setupNodeEvents`.
14. ✅ **`cy.session`** (Cypress 8+) for caching logins — stores + restores
    cookies + localStorage. Drastically faster E2E; read the docs and
    configure `cacheAcrossSpecs: true` when safe.
15. ✅ **Component tests** as a sibling of unit tests for UI libraries —
    live in `cypress/component/*.cy.tsx` with `cy.mount(<Component/>)`.
16. ✅ **Network error verification** assert `cy.contains('Network error')`
    after `forceNetworkError: true` on `cy.intercept`.
17. ✅ **`cypress run`** in CI; **`cypress open`** locally (interactive
    runner with time-travel). Do not run `cypress open` in CI.
18. ✅ Cypress Cloud for **dashboard + parallel**: `--record` posts run;
    parallelize via `--parallel` from multiple CI runners; or use a third-party
    reporter like `cypress-mochawesome-reporter` for self-hosted HTML.
19. ✅ **`--browser=chrome|firefox|edge|electron`** controls which browser to
    test; default electron is fine for green in CI.
20. ✅ **`cypress.config.ts > env` block** for environment vars surfaced
    into `Cypress.env('baseUrl')` — useful for env switching.
21. ✅ **`cy.then()` sparingly**: prefer `cy.` chain over manual `then` for
    queue kaleidoscope readability; callbacks are fine for `cy.then((x) => ...)`.
22. ✅ **`requestLink`**: never use `cy.visit` for untrusted URLs in tests
    of third-party sites; use `cy.request` to assert status only.
23. ✅ **Snapshot diffing** via `cypress-plugin-snapshots` or
    `@testing-library/cypress` `cy.matchImageSnapshot()` — treat baseline
    as committed artifact; require manual update on intentional change.
24. ✅ **`cypress-axe` / `@axe-core/cypress`** — invoke `cy.injectAxe()` once
    after `cy.visit`, then `cy.checkA11y()` per main view.

## Canonical patterns

### `cypress.config.ts`

```ts
import { defineConfig } from "cypress";
import * as dotenv from "dotenv";

export default defineConfig({
  e2e: {
    baseUrl: process.env.CYPRESS_BASE_URL ?? "http://localhost:5173",
    specPattern: "cypress/e2e/**/*.cy.{ts,tsx}",
    supportFile: "cypress/support/e2e.ts",
    viewportWidth: 1280, viewportHeight: 720,
    defaultCommandTimeout: 8000,
    retries: { runMode: 2, openMode: 0 },
    video: false,                        // CI: turn off to save space; turn on for flaky investigation
    screenshotOnRunFailure: true,
    setupNodeEvents(on, config) {
      on("task", {
        // task: { async readFile(p: string) { return await import("fs/promises").then(fs => fs.readFile(p, "utf8")); } }
      });
      return config;
    },
  },
  component: {
    devServer: { framework: "vite" },
    specPattern: "cypress/component/**/*.cy.{ts,tsx}",
    indexHtmlFile: "cypress/support/component-index.html",
  },
  env: {
    apiUrl: process.env.API_URL ?? "http://localhost:3000/api",
  },
});
```

### Test with `cy.intercept`

```ts
import cypress = require("cypress");
// cypress/e2e/orders.cy.ts

describe("Orders", () => {
  beforeEach(() => {
    cy.intercept("GET", "/api/orders", { fixture: "orders.json" }).as("orders");
    cy.login("a@b.com", "secret123");
    cy.visit("/orders");
    cy.wait("@orders");
  });

  it("lists orders from the fixture", () => {
    cy.findByRole("table").should("be.visible");
    cy.findByText("Order #10041").should("exist");
  });

  it("shows error on server error", () => {
    cy.intercept("GET", "/api/orders", { statusCode: 500, body: "boom" }).as("err");
    cy.visit("/orders");
    cy.findByText("Network error").should("be.visible");
  });
});
```

### Custom command for API login

```ts
// cypress/support/commands.ts
declare namespace Cypress {
  interface Chainable {
    login(email: string, password: string): Chainable<void>;
    findByDataId(id: string): Chainable<JQuery<HTMLElement>>;
  }
}

Cypress.Commands.add("login", (email, password) => {
  cy.request("POST", "/api/login", { email, password }).then((r) => {
    cy.setCookie("session", r.body.token);
  });
});

Cypress.Commands.add("findByDataId", (id) => {
  cy.get(`[data-testid="${id}"]`);
});
```

### Accessibility check

```ts
// cypress/e2e/a11y.cy.ts
describe("Accessibility", () => {
  beforeEach(() => {
    cy.visit("/");
    cy.injectAxe();
  });
  it("home has no critical violations", () => {
    cy.checkA11y(undefined, {
      runOnly: { type: "tag", values: ["wcag2a", "wcag2aa"] },
    });
  });
});
```

### Parallel CI with Cypress Cloud (recording)

```yaml
# .github/workflows/cypress.yml
jobs:
  e2e:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        containers: [1, 2, 3, 4]
    steps:
      - uses: actions/checkout@v4
      - uses: cypress-io/github-action@v6
        with:
          start: npm run dev
          wait-on: "http://localhost:5173"
          record: true
          parallel: true
          browser: chrome
        env:
          CYPRESS_RECORD_KEY: ${{ secrets.CYPRESS_RECORD_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### `cy.session` for stable auth

```ts
beforeEach(() => {
  cy.session([Cypress.env("E2E_USER"), "session"], () => {
    cy.request("POST", "/api/login", {
      email: Cypress.env("E2E_USER"),
      password: Cypress.env("E2E_PASS"),
    }).then((r) => cy.setCookie("session", r.body.token));
  });
});
```

## Common pitfalls / anti-patterns

- ❌ `cy.wait(500)` instead of `cy.wait('@alias')` — flaky + slow.
- ❌ Sharing app state via `before` without `beforeEach` reset.
- ❌ Selecting by class `.submit-btn` — breaks on Tailwind refactor.
- ❌ Mixing assertions of async vs sync (`.should` is async-chain, `expect`
  is sync) — explicit `then` for sync.
- ❌ `cy.server`/`cy.route` (deprecated) — replace with `cy.intercept`.
- ❌ Putting real API tokens in `cypress.env.json` committed — use CI secrets.
- ❌ Component tests using global app setup — they should mount the component
  in isolation.
- ❌ Running `cypress open` in CI — it hangs; only `cypress run`.
- ❌ One giant `cypress/e2e/all.cy.ts` — splits limit parallelism & caching.
- ❌ Records `video: true` in CI for every spec on green builds — wasted
  storage; only turn on for known flaky tests.

## Testing & validation

- `npx cypress run` (headless) for CI; reports `passing`/`failing`.
- `npx cypress run --browser=firefox` to sanity cross-browser.
- `npx cypress run --spec "cypress/e2e/orders.cy.ts"` to scope.
- `npx cypress open` for local debugging — interactive runner with time
  travel and command log.
- Report generators: `cypress-mochawesome-reporter` (HTML + JSON) or Cypress
  Cloud dashboard for hosted reporting.
- Retry flaky runs via `retries: 2` but track every flaky test in your team's
  health dashboard; mark with flake flag + ticket to investigate.

## Performance & tuning

- **`cy.session`**: cache auth per spec — often halves run time.
- **`specPattern` sharding**: multiple specs split across CI runners via
  `--parallel` + Cypress Cloud, OR filesystem split (`cypress/e2e/{a,b,c}.cy.ts`)
  with matrix filtering.
- **Browser**: `--browser=electron` is fastest; but you lose some native
  features — choose chrome for prod fidelity.
- **`numTestsKeptInMemory`**: default is 50 — reduce on small CI runners
  to ~10 to lower RAM pressure.
- **`nodeVersion`**: Cypress 13+ uses Node 18; CI setup-node@v4 with cache.
- **Component tests** are much faster than E2E — move atomic assertions
  into component tests when possible.
- **`modifyObstructiveCode`**: default `false`; toggling `true` lets Cypress
  rewrite app code for stubbing — keep false in CI to avoid surprises.

## Security (top 5)

1. **No tokens in committed `cypress.json` / `cypress.config.ts`** — use CI
   secrets (`Cypress.env()` via `env:` in CI step).
2. **`cypress.env.json`** is per-developer, gitignored; never committed.
3. **Test-only endpoints**: prefer an API login route that bypasses MFA so
   E2E doesn't request real TOTP codes; isolate it from prod with feature
   flag.
4. **Sandboxing cookies / storage**: `cy.session` scopes per spec; do not
   share across specs unless intended.
5. **No prod traffic**: point tests at dedicated staging / ephemeral env;
   teardown test users.

## Official docs & references

- Cypress docs: https://docs.cypress.io/
- Configuration reference: https://docs.cypress.io/app/references/configuration
- Best practices: https://docs.cypress.io/app/references/best-practices
- `cy.intercept`: https://docs.cypress.io/api/commands/intercept
- Custom commands: https://docs.cypress.io/api/cypress-api/custom-commands
- `cy.session`: https://docs.cypress.io/api/commands/session
- Component testing: https://docs.cypress.io/app/get-started/component-testing
- Cypress Cloud: https://docs.cypress.io/cloud/dashboard
- @axe-core/cypress: https://github.com/dequelabs/axe-core-npm/tree/develop/packages/cypress
- @testing-library/cypress: https://testing-library.com/docs/cypress-testing-library/intro/
- cypress-real-events: https://github.com/dmtrKlvlk/cypress-real-events  
- GitHub Action: https://github.com/cypress-io/github-action