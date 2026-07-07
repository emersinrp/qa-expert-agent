---
name: a11y-axe
description: Use this skill for accessibility testing with axe-core and WAI-ARIA semantics — axe-core (web), @axe-core/playwright, @axe-core/cypress, jest-axe, @axe-core/react (Storybook via axe), axe-android, @axe-core/puppeteer. Trigger on "axe-core", "WCAG", "accessibility", "jest-axe", "cypress-axe", "axe-playwright", "a11y", "ARIA", "screen reader", "Accessibility Insights", "VoiceOver tests". Use ONLY for accessibility testing; for general E2E use playwright/cypress skills.
---

# axe-core / Accessibility Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Automated / gated a11y in CI for web | Browser-only KB full coverage — axe covers only ~30-50% of WCAG; manual testing still required |
| Smoke-test a11y on every page in E2E suite | One-off audits (use Lighthouse / WAVE / AXE DevTools browser extension) |
| Storybook component testing via `@axe-core/react` | Native iOS / Android apps without WebView (use mobile-tests skill, iOS Audit / AccessibilityScanner) |

## Core stack & versions

- **axe-core** latest (4.x). Palettes per WCAG 2.1 / 2.2 levels A/AA/AAA.
- **Browser bindings**:
  - `@axe-core/playwright` — Playwright tests
  - `@axe-core/cypress` (formerly `cypress-axe`) — Cypress tests
  - `@axe-core/puppeteer` — Puppeteer scripts
  - `jest-axe` — Jest / Vitest unit tests
  - `@axe-core/react` — Storybook through `axeMode`
- CLI: `@axe-core/cli` for one-off URL audits, `axe --tags wcag2a,wcag2aa`.
- WCAG versions: WCAG 2.1 stable; WCAG 2.2 added "Focus Not Obscured",
  "Target Size (Minimum)", etc.

## Project structure (canonical)

```
project/
├── package.json
├── tests/
├── e2e/                              # Playwright/Cypress with axe checks
│   ├── home.a11y.spec.ts
│   ├── login.spec.ts
│   └── a11y-axe.test.ts           # reused helpers
├── src/
│   └── components/__tests__/         # jest-axe for component unit tests
└── .github/workflows/a11y.yml       # gate on critical violations
```

## Best practices checklist

1. ✅ Always test WCAG 2.1 AA as baseline CI target. WCAG 2.2 AA recommended
   for new projects.
2. ✅ Run axe inside one smoke E2E test (per page type), not every spec.
   Reduces total noise.
3. ✅ Scope axe runs to the rendered page via context selector
   (`AxeBuilder({ page }).include('#main-content').analyze()`).
4. ✅ Filter `violations` by `impact` — `critical`, `serious` should block,
   `moderate` rarely, `minor` rarely. Document the threshold.
5. ✅ Snapshot violations (count) in CI artifacts so you can trend week over
   week; raw violations pile up faster than reviewers can read them.
6. ✅ Use **custom rules** selection to disable rule violations that are
   impossible in your context (`color-contrast` when design tokens aren't
   final) — but document a tracking ticket.
7. ✅ Run `axe-core` in **Jest/Vitest** for unit-tested components too:
   `expect(await axe(container.getHTML())).toHaveNoViolations()`.
8. ✅ `axe-core` cannot always know the visible label is descriptive — pair
   with manual screen-reader checks (VoiceOver / NVDA) for an ARIA labelling
   audit at least once per release.
9. ✅ Pair axe with **Storybook + @axe-core/react** — covers individual
   components in isolation against the same tag set.
10. ✅ Test components in **multiple states** — including error, loading,
    disabled — axe on a single happy state misses rules like "Input without
    label" that appear only in error.
11. ✅ Never `expect(violations).toEqual([])` blindly — assert on filtered
    violations, so known false positives don't break the suite.
12. ✅ **Keyboard navigation** manual smoke + **tab order** assertions. Axe
    covers most, but the order of focus matters and slave tests.
13. ✅ DOM 4 + ARIA roles per WAI-ARIA 1.2; verify via axe + VoiceOver on iOS
    (audit) + NVDA on Windows.
14. ✅ **Color contrast** must satisfy 4.5:1 (AA) minimum for body, 3:1 for
    large text (≥18pt or 14pt bold). Use `axe-core color-contrast` rule.
15. ✅ **Tabular UI**: pure stale tables (without `<th scope="col">` headers)
    fail axe-* rules; expose designer tickets for legacy UI migrations.
16. ✅ **Forms**: every input has associated `<label for="...">`
    programmatically — `aria-labelledby` only when no `<label>` fits.
17. ✅ **Dynamic content**: `aria-live` for announcements without focusing;
    axe doesn't run checks at runtime after burden updates; unique smoke.
18. ✅ Use Accessibility Insights browser extension during dev for quick
    assessment (`Fastpass` shows automated issues + tab stops).
19. ✅ **Reduced motion**: respect `prefers-reduced-motion` CSS media query
    (axe detects most animations errors).
20. ✅ Audit page tree in tests that exercise theme switching — dark mode
    `color-contrast` differs and can silently break AA.
21. ✅ **Viewport** for each breakpoint — axe test lower-density layouts to
    ensure content doesn't overflow / stays operable at 320px width.
22. ✅ Mark known a11y violations with `data-axe-ignore="reason: ticket-N"`
    and a custom rule to skip; document the removal in the ticket.
23. ✅ Algorithmic audits only catch ~30-50% of WCAG violations — pair with
    manual tests using NVDA / VoiceOver at least once per release.
24. ✅ Adopt a "definition of done" that requires zero new `critical` /
    `serious` a11y violations for each PR.

## Canonical patterns

### Playwright + axe smoke

```ts
// e2e/a11y/home.a11y.spec.ts
import AxeBuilder from '@axe-core/playwright';
import { test, expect } from '@playwright/test';

test('Home page has no critical a11y violations', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa'])
    .analyze();

  const breaking = results.violations.filter(
    v => v.impact === 'critical' || v.impact === 'serious'
  );
  expect(breaking, JSON.stringify(breaking, null, 2)).toEqual([]);
});

test('Login form a11y', async ({ page }) => {
  await page.goto('/login');
  const results = await new AxeBuilder({ page })
    .include('form')           // scope
    .disableRules(['color-contrast'])   // skipping while design tokens re-theme
    .analyze();
  expect(results.violations).toEqual([]);
});
```

### Cypress + axe

```ts
// cypress/e2e/a11y.cy.ts
describe('Accessibility', () => {
  beforeEach(() => {
    cy.visit('/');
    cy.injectAxe();
  });
  it('Home passes WCAG AA', () => {
    cy.checkA11y(undefined, {
      runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa'] },
    }, (violations) => {
      // Custom reporter: log to console asserting violations
      cy.task('log', violations.map(v => v.id).join(','));
    });
  });
});
```

### Jest + jest-axe (component)

```ts
// src/components/Button/Button.test.tsx
import { render } from '@testing-library/react';
import { axe, toHaveNoViolations } from 'jest-axe';
expect.extend({ toHaveNoViolations });

it('Button has no a11y violations', async () => {
  const { container } = render(<button>Save</button>);
  const results = await axe(container);
  expect(results).toHaveNoViolations();
});
```

### CI gate (GitHub Actions)

```yaml
# .github/workflows/a11y.yml
jobs:
  a11y:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npx playwright test --project=chromium --grep "@a11y"
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: a11y-report, path: playwright-report/ }
```

### Exclude a rule with reason

```ts
const results = await new AxeBuilder({ page })
  .exclude('#legacy-banner')
  .disableRules(['region'])   // demoted because the page uses ARIA landmarks elsewhere
  .analyze();
```

## Common pitfalls / anti-patterns

- ❌ `expect(violations).toEqual([])` for the entire page — false positives
  from third-party widgets break the gate repeatedly.
- ❌ Scanning once per component of every storybook story — slow + noisy;
  prefer one combined Storybook a11y test job.
- ❌ Disabling rules globally with no comment / ticket — knowledge lost.
- ❌ Skipping `color-contrast` because "design is final" — contrast can be
  subjective but AA errors are objective.
- ❌ Using axe results as the END of accessibility testing — axe covers
  maybe half; pair with manual tests.
- ❌ Forgetting `aria-live` regions test — axe doesn't catch all of them at
  runtime; smoke manually.
- ❌ Marking tests as `// skip` because they are flaky on color-contrast with
  different fonts loaded async — wait for fonts via `await page.evaluate(() =>
  document.fonts.ready)`.
- ❌ Only testing desktop viewports — mobile breakpoints introduce a11y bugs
  (small touch targets, off-screen content).
- ❌ Not re-checking after `set autotest chorus visibleStylesChange` — axe
  requires the DOM be stable for assertions about visibleState.

## Testing & validation

- Add axe to Playwright/Cypress `*.a11y.spec.ts` with a single `@a11y` tag
  so CI can run them separately (`--grep "@a11y"`).
- Snapshot violations count in CI (`counts.json`) to trend.
- Manual pairing: run **NVDA / VoiceOver / TalkBack** for screen reader smoke
  across top user flows (login, checkout, dashboard).
- Use **Accessibility Insights Fastpass** browser extension for fast triage.
- **Storybook a11y**: install `@storybook/addon-a11y` and tick axe checks in
  each Story page during dev.

## Performance & tuning

- `axe-core` runs in ~50-200ms per page; smoke tests per page type, not per
  test, to keep E2E suite bounded.
- Use `.include(selector)` to scope to the relevant subtree; skipping
  header/footer doubles speed.
- Cache pre-evaluated axe rules per version when sharded — repeating across
  shards re-runs the same rules unnecessarily.
- Run as a **smoke test** in parallel with functional tests rather than
  gating every functional ESL test on it.

## Security (top 5)

1. axe itself doesn't expose anything sensitive; reports may leak DOM
   snippets — treat axe HTML reports as secrets-adjacent; do not publish
   internal UI screenshots/traces to public buckets.
2. While running axe against staging, use the same staging secrets policy as
   functional tests (no real PII).
3. axe JSON output may include user-generated content shown during testing;
   redact before persisting/training.
4. **For each change** running on production, ensure that DOM traces don't
   include session cookies in their HTML snapshots; use `include` carefully.
5. Browser-side axe doesn't transmit data anywhere; double-check no custom
   reporter posts results to a third party without approval.

## Official docs & references

- axe-core: https://github.com/dequelabs/axe-core
- axe-core rules: https://github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md
- @axe-core/playwright: https://github.com/dequelabs/axe-core-npm/tree/develop/packages/playwright
- @axe-core/cypress: https://github.com/dequelabs/axe-core-npm/tree/develop/packages/cypress
- jest-axe: https://github.com/storybookjs/jest-axe
- WCAG 2.1: https://www.w3.org/TR/WCAG21/
- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- WAI-ARIA 1.2: https://www.w3.org/TR/wai-aria-1.2/
- WAI tutorials: https://www.w3.org/WAI/
- Accessibility Insights: https://accessibilityinsights.io/
- WebAIM contrast checker: https://webaim.org/resources/contrastchecker/
- NVDA: https://www.nvaccess.org/
- VoiceOver (Apple): https://www.apple.com/accessibility/vision/
- axe CLI: https://github.com/dequelabs/axe-core-npm/tree/develop/packages/cli