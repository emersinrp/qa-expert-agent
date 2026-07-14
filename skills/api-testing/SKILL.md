---
name: api-testing
description: Use this skill for functional/behavioral API testing (REST & GraphQL) — status codes, response schema (OpenAPI / JSON Schema), headers, body assertions, auth flows, negative/error cases, idempotency, pagination, and test-data setup/cleanup. Multi-stack, routed by language — supertest & Playwright APIRequest (JS/TS), REST-assured & Karate (Java), pytest+httpx/requests & schemathesis (Python), Postman/Newman, Bruno, hurl. BDD-first (Given/When/Then; Karate/Cucumber/behave native where the stack fits). Trigger on "API test", "REST assured", "supertest", "Postman", "Newman", "Karate", "OpenAPI validation", "endpoint test", "status 200/4xx", "json schema". Use ONLY for functional API testing; for consumer-driven contracts use pact-contract; for load/perf use k6/locust; for E2E UI use playwright/cypress.
---

# API Testing Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Verifying an HTTP/GraphQL API's behavior directly (status, schema, body, headers, auth, errors) | Checking a consumer honors a provider's contract — use **pact-contract** |
| Testing backend logic without driving the UI | Load / stress / soak testing — use **k6** or **locust** |
| Validating responses against an OpenAPI / JSON Schema | Full user journey through the browser — use **playwright** / **cypress** |
| Regression on error paths, auth, pagination, idempotency | Unit-testing a pure function with no I/O — use the stack's unit runner |

API tests sit at the **integration** layer of the pyramid: cheaper than E2E,
richer than unit. Push an assertion here before reaching for a browser test.

## Core stack & versions (routed by language)

The agent picks the tool by **inspecting the project**, never by preference:

- **JS/TS** — `supertest` (^7) over an Express/Nest app instance, or
  Playwright's `APIRequestContext` (`request` fixture, `@playwright/test`
  ^1.40) for out-of-process APIs. Schema: `ajv` (^8) + `ajv-formats`.
- **Java** — `REST-assured` (^5) with JUnit 5 for imperative tests;
  `Karate` (^1.4) when you want Gherkin-native `.feature` API tests.
  Schema: `io.rest-assured:json-schema-validator`.
- **Python** — `pytest` + `httpx` (or `requests`); `jsonschema` for schema;
  `schemathesis` (^3) for property-based tests generated from OpenAPI;
  `behave` when the team wants native Gherkin.
- **Collection / language-agnostic** — Postman + **Newman** (CI runner),
  **Bruno** (`@usebruno/cli`, git-native collections), **hurl** (plain-text
  HTTP with inline asserts).
- **GraphQL** — POST `query`/`variables`; assert on `data` **and** `errors`;
  validate against the SDL/introspection schema.

Reports: JUnit XML everywhere (CI gate); Allure optional (`allure-*` adapters).

## Project structure (canonical, JS/TS)

```
service/
├── package.json
├── openapi.yaml                       # source of truth for schema asserts
├── test/
│   └── api/
│       ├── helpers/
│       │   ├── client.ts              # base URL, auth token, retries
│       │   └── schema.ts              # ajv compile + assert helper
│       ├── schemas/orders.schema.json # extracted from openapi.yaml
│       ├── orders.get.spec.ts         # one behavior area per file
│       └── orders.errors.spec.ts
└── .github/workflows/api-tests.yml
```

Java (Karate): `src/test/java/.../orders.feature` + `OrdersRunnerTest.java`.
Python: `tests/api/test_orders.py` + `tests/api/schemas/*.json` + `conftest.py`.

## BDD-first authoring (the #6 standard)

Every test is authored from an **acceptance criterion → Gherkin scenario →
automated test**. Optionally phrase the criterion in **EARS** first
(e.g. *"When an unauthenticated request hits `/orders`, the API shall respond
401"*), then express it as a `Given/When/Then` scenario.

**Hybrid rule:**

- **Native `.feature`** where the stack supports it idiomatically — **Karate**
  (Java), **Cucumber**, **behave** (Python), **playwright-bdd** (JS). The
  `.feature` file *is* the living documentation and the executable test.
- **Structured G/W/T in code** everywhere else — a `describe`/`it` (or pytest
  function) whose body is commented/grouped as `// Given … // When … // Then`,
  derived from the scenario. Keep one behavior per scenario.

Both must map 1:1 to a criterion; a test with no stated scenario is incomplete.

## Best practices checklist

1. ✅ Assert **status + schema + key fields** — never full-body equality
   (brittle to additive changes). Match shape, pin only the fields the
   behavior is about.
2. ✅ Validate the response body against the **OpenAPI / JSON Schema**
   (ajv / json-schema-validator / jsonschema). A `200` with a malformed body
   is a failure.
3. ✅ Cover **negative paths**: 400 (validation), 401 (unauthenticated), 403
   (unauthorized), 404, 409 (conflict), 422, 5xx handling — not just the
   happy path.
4. ✅ Test **authZ, not just authN**: a valid token for user A must **not**
   read user B's resource (broken object-level auth / IDOR).
5. ✅ Assert the **method semantics**: GET/HEAD safe, PUT/DELETE idempotent,
   POST creates; verify `Location` on 201, `Allow` on 405.
6. ✅ Assert **headers & Content-Type**, not only the body (`application/json`,
   caching, correlation/trace id, rate-limit headers where contractual).
7. ✅ Obtain auth **via a setup step** (token endpoint / fixture); never
   hardcode tokens or credentials in the test body.
8. ✅ **Isolate test data**: create prerequisites via API/DB setup, tear down
   in teardown (or use a per-test transaction). Never depend on data that
   happens to exist.
9. ✅ **Determinism**: no `sleep()`. For async/eventual endpoints, **poll with
   a timeout** (bounded retries) until the condition holds.
10. ✅ Externalize **base URL and secrets** via env (`BASE_URL`, `API_TOKEN`);
    one config switch between local/staging/CI.
11. ✅ Parametrize variants with **table/data-driven** cases (scenario
    outlines), not copy-pasted tests.
12. ✅ Assert **pagination & filtering** contracts (page size, `next`
    cursor/link, total count, empty page).
13. ✅ For **GraphQL**, assert both `data` and the absence/shape of `errors`;
    a 200 with an `errors` array is a failure unless the scenario expects it.
14. ✅ Validate **error body shape** (RFC 7807 `application/problem+json` or the
    project's error contract), not just the status code.
15. ✅ Keep each spec **file scoped to one resource/behavior area**; one
    scenario asserts one behavior.
16. ✅ Reuse a **single configured HTTP client** (base URL, default headers,
    connection pool) via a helper/fixture.
17. ✅ Prefer **schema-driven fuzzing** (`schemathesis`) against the OpenAPI to
    catch unhandled inputs the hand-written cases miss.
18. ✅ Tag suites **`@smoke` vs `@full`**; smoke gates every PR, full runs
    nightly/pre-release.
19. ✅ Emit **JUnit XML** (and Allure if used); CI must exit **non-zero** on any
    assertion failure — a green-ish Newman run is not a pass.
20. ✅ Mask/omit **secrets and PII** in request/response logs and reports.
21. ✅ Don't re-verify a **contract** here — if the concern is "does the
    provider still honor what the consumer expects", that's **pact-contract**.
22. ✅ State every test as a **Gherkin scenario** (native `.feature` or
    structured G/W/T) per the BDD-first rule above.

## Canonical patterns

### JS/TS — supertest + ajv, structured Given/When/Then

```ts
// test/api/orders.errors.spec.ts
import request from 'supertest';
import { app } from '../../src/app';
import { assertSchema } from './helpers/schema';
import problemSchema from './schemas/problem.schema.json';

// Scenario: rejects an unauthenticated order lookup
describe('GET /orders/:id — auth', () => {
  it('returns 401 + problem body when no token is sent', async () => {
    // Given: no Authorization header
    // When: the client requests an order
    const res = await request(app).get('/orders/o-123');
    // Then: the API rejects it with a well-formed problem document
    expect(res.status).toBe(401);
    expect(res.headers['content-type']).toMatch(/application\/problem\+json/);
    assertSchema(problemSchema, res.body); // ajv compile+validate, throws on mismatch
  });
});
```

### Java — Karate (native Gherkin `.feature`)

```gherkin
# src/test/java/orders/orders.feature
Feature: Orders API

  Background:
    * url baseUrl
    * def token = call read('classpath:auth.js')

  Scenario: fetches an order by id for its owner
    Given path 'orders', 'o-123'
    And header Authorization = 'Bearer ' + token
    When method get
    Then status 200
    And match response == { id: 'o-123', total: '#number', status: '#string' }

  Scenario: forbids reading another user's order
    Given path 'orders', 'o-999'
    And header Authorization = 'Bearer ' + token
    When method get
    Then status 403
```

```java
// OrdersRunnerTest.java — JUnit 5 entry point
class OrdersRunnerTest {
  @Karate.Test
  Karate orders() { return Karate.run("orders").relativeTo(getClass()); }
}
```

### Python — pytest + httpx + jsonschema

```python
# tests/api/test_orders.py
import json, httpx, pytest
from jsonschema import validate

with open("tests/api/schemas/order.schema.json") as f:
    ORDER_SCHEMA = json.load(f)

def test_get_order_returns_valid_body(api_client: httpx.Client, auth_headers):
    # Given an existing order  # When the owner fetches it
    r = api_client.get("/orders/o-123", headers=auth_headers)
    # Then status is 200 and the body matches the schema
    assert r.status_code == 200
    validate(instance=r.json(), schema=ORDER_SCHEMA)
```

### Schema-driven fuzzing from OpenAPI (schemathesis)

```bash
schemathesis run http://localhost:8000/openapi.json \
  --checks all --hypothesis-max-examples 50 --junit-xml st-results.xml
```

### Collection run in CI (Newman)

```bash
newman run orders.postman_collection.json -e staging.postman_environment.json \
  --reporters cli,junit --reporter-junit-export newman-results.xml
# non-zero exit on any failed assertion → gates the pipeline
```

## Common pitfalls / anti-patterns

- ❌ **Full-body equality** (`toEqual(fixture)`) — breaks on every additive,
  non-breaking field. Assert schema + the fields under test.
- ❌ **Only the happy path** — no 4xx/5xx, no auth-failure, no boundary cases.
- ❌ **Trusting the status alone** — a `200` with `{}` or a wrong shape passes;
  always schema-validate.
- ❌ **Hardcoded tokens / URLs / PII** in tests or committed collections.
- ❌ **Order-dependent tests** sharing mutable server state with no cleanup —
  flaky the moment they run in parallel or a different order.
- ❌ **`sleep(2000)` for eventual consistency** — poll with a bounded timeout.
- ❌ **Re-implementing contract testing** here (asserting the exact bytes a
  specific consumer needs) — that's **pact-contract**.
- ❌ **Newman/hurl run whose failure doesn't fail CI** (missing `--reporters`
  wiring or swallowed exit code) — false green.
- ❌ **Asserting on volatile fields** (timestamps, generated ids) with fixed
  values instead of type/format matchers.
- ❌ **One giant scenario** chaining create→update→delete→list — split into
  discrete, independently-runnable scenarios.

## Testing & validation

Run and paste the raw output — never claim a pass without the runner:

- JS supertest: `npx jest test/api` or `npx vitest run test/api`
- Playwright API: `npx playwright test --project=api`
- REST-assured: `mvn -Dtest='*ApiTest' test`
- Karate: `mvn -Dtest=OrdersRunnerTest test` (HTML report under `target/karate-reports/`)
- Python: `pytest tests/api -v` · fuzzing: `schemathesis run <openapi-url> --checks all`
- Newman: `newman run <collection> -e <env> --reporters cli,junit`
- Bruno: `bru run --env staging` · hurl: `hurl --test tests/*.hurl`

CI gate: JUnit XML published + **non-zero exit on failure**.

## Performance & tuning

- API suites are cheap — keep them **fast and parallel**; reuse one HTTP
  client (connection pool / keep-alive) instead of a client per request.
- **Cache the auth token** across a suite (fetch once in setup), don't hit the
  token endpoint per test.
- Gate PRs with the `@smoke` subset (seconds); run the `@full` suite +
  `schemathesis` fuzzing nightly.
- For Karate/REST-assured, run features in parallel (Karate `Runner…parallel(n)`);
  for pytest use `pytest -n auto` (`pytest-xdist`).

## Security (top 5)

1. **Test authorization, not just authentication** — broken object-level auth
   (IDOR), missing role checks, and privilege escalation are the top API
   risks; assert user A cannot touch user B's data.
2. **No secrets in collections/fixtures** — tokens/keys via CI env only;
   scrub Postman/Bruno environments before committing.
3. **Never run destructive tests against shared/prod** — isolate an ephemeral
   env or DB; a `DELETE` test on prod deletes real records.
4. **Validate input handling** — oversized payloads, injection strings, wrong
   Content-Type should return 4xx, not 5xx or a leak; `schemathesis` surfaces
   many of these automatically.
5. **Mask sensitive response data** in logs/reports (PII, tokens); reports are
   often published as CI artifacts.

## Official docs & references

- supertest: https://github.com/ladjs/supertest
- Playwright API testing: https://playwright.dev/docs/api-testing
- ajv (JSON Schema): https://ajv.js.org/
- REST-assured: https://rest-assured.io/
- REST-assured JSON Schema validation: https://github.com/rest-assured/rest-assured/wiki/Usage#json-schema-validation
- Karate: https://github.com/karatelabs/karate
- pytest: https://docs.pytest.org/ · httpx: https://www.python-httpx.org/
- jsonschema (Python): https://python-jsonschema.readthedocs.io/
- schemathesis: https://schemathesis.readthedocs.io/
- Postman/Newman: https://github.com/postmanlabs/newman
- Bruno: https://docs.usebruno.com/ · hurl: https://hurl.dev/
- JSON Schema: https://json-schema.org/ · OpenAPI: https://spec.openapis.org/
- Problem Details (RFC 7807/9457): https://www.rfc-editor.org/rfc/rfc9457
