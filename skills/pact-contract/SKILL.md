---
name: pact-contract
description: Use this skill for Pact consumer-driven contract testing — Pact JS, Pact-JVM, pact-python, pact-go, Pact Rust, Pact Net, pact-broker / Pactflow. Trigger on "Pact", "consumer contract", "pact-broker", "can-i-deploy", "matchers", "provider verification", "Pact JS", "Pact JVM", "bi-directional contracts". Use ONLY for contract testing; for E2E use playwright/cypress skills.
---

# Pact Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Consumer-provider pairs where the consumer cares about a subset of the provider's API | Solo service with no external consumer — use unit/integration tests instead |
| Strangling / migrating from monolith → services, need to keep both shapeset | Public third-party API you cannot write pacts for (use OpenAPI schema validation) |
| Decoupled teams shipping independently | Few services with co-located teams — full E2E may be cheaper |

## Core stack & versions

- **Pact JS v11+** for Node/TS; modern Pact uses V3 spec by default.
- **Pact JVM** for JVM-side verifications.
- **pact-python**, **pact-go**, **pact-rust**, **Pact Net** for other stacks.
- **pact-broker** self-hosted Docker (`pactfoundation/pact-broker`) or **Pactflow**
  SaaS (commercial per-workspace tier).
- Pact spec V3 supports provider state `given` + generators + matching
  with sequence.

## Project structure (canonical, JS consumer)

```
consumer-service/
├── package.json
├── pact/
│   ├── pact.config.ts
│   └── tests/
│       └── usersApi.pact.test.ts
├── pact/pacts/                # generated JSON contracts (gitignored, only broker)
└── .github/workflows/pact.yml

provider-service/
└── src/test/java/com/myapi/pact/
    └── UsersApiPactVerificationTest.java
└── pact/pacts/                 # fetched from broker at verify time
```

Generated pacts pushed to the broker — never commit the JSON.

## Best practices checklist

1. ✅ The **consumer** side writes the test asserting what it expects; the
   test produces a contract JSON pushed to the broker.
2. ✅ The **provider** side verifies the broker's JSON against its actual
   implementation in CI every merge.
3. ✅ Use **matchers** (`like`, `eachLike`, `term`, `regex`, `datetime`)
   instead of hardcoding fixed values. Match types not content.
4. ✅ Use `like({...})` for shape and free primitive values; `eachLike(...)`
   for arrays; `term({ matcher: '...', generate: '...' })` for regex-bound
   values like UUIDs.
5. ✅ **Provider states** (`given`) parametrize the provider side. `given
   ("a user with id 1 exists")` maps to a fixture on the provider side.
6. ✅ Each provider state is set up and torn down per interaction via the
   state handler URL on the provider (or annotated method on JVM).
7. ✅ Run consumer `pact test` → **publish** to broker via contract
   identifier + branch / version (commit SHA + branch).
8. ✅ Run provider verification **after pulling latest contracts** from
   broker for the relevant branch; report results back to broker.
9. ✅ Use `can-i-deploy` lookup before deploy: returns nonzero exit when
   consumer and provider versions are not mutually compatible.
10. ✅ Always version both consumer and provider with git SHA + branch.
11. ✅ **Tag versions** with `--tag <env>` (e.g., `prod`, `main`) so
    can-i-deploy knows what's actually deployed in each env.
12. ✅ Don't publish a fresh pact if the consumer change has zero impact on
    the `requests` shape — but Pact's `rebar-code` will detect that.
13. ✅ For each consumer test, write one `interaction` per distinct request
    pair (status + headers + body). Multiple `expects` inside one
    interaction should issue multiple `axios` calls or multiple
    `addInteraction` mappings.
14. ✅ Use **message pacts** for async bus / event-driven systems where
    there's no HTTP request/response; consumer publishes expected message
    schema.
15. ✅ **Bi-directional contracts** (Pactflow feature): provider publishes
    its own OpenAPI spec; broker diffs it against consumer pact diff to
    decide compatibility. Skip provider verification step.
16. ✅ Never run the real provider against the real DB in consumer tests —
    consumer tests use a mock provider (Pact spins up a real HTTP server
    on a local port that replays the contract).
17. ✅ Provider verification should use a **test runner** that exercises the
    real endpoints but with provider-state fixtures (in-memory / test DB).
18. ✅ Always clean provider state between interactions; cross-state
    leakage silently breaks contract verification.
19. ✅ Treat pact failures as **hard blocks**: if the consumer expects a
    field the provider no longer emits, the consumer WILL break in prod;
    block the merge.
20. ✅ Use the **`pact-broker can-i-deploy`** output to gate deploys in CI.
21. ✅ Tag / branch metadata in publish step: `pact-broker publish
    --tag=$BRANCH --build-url=$CI_JOB_URL`.
22. ✅ Automate **Webhook** in broker: when a new pact is published for
    `<consumer>`, trigger the `<provider>` verification pipeline.
23. ✅ Tag the contract with env (e.g., `prod`) only after it has been
    verified as compatible in that env.
24. ✅ Use pact-broker **matrix** to inspect current compatibility state;
    embed monitoring badge in your service README.

## Canonical patterns

### Consumer test (Pact JS, V3)

```ts
// consumer/pact/tests/usersApi.pact.test.ts
import { Pact } from '@pact-foundation/pact';
import { like, eachLike, term } from '@pact-foundation/pact/src/dsl/matchers';
import path from 'path';
import axios from 'axios';

const provider = new Pact({
  consumer: 'orders-service',
  provider: 'users-api',
  log: path.resolve(__dirname, '../logs/pact.log'),
  dir: path.resolve(__dirname, '../pacts'),
  logLevel: 'info',
  spec: 3,
});

beforeAll(() => provider.setup());
afterAll(() => provider.finalize());
afterEach(() => provider.verify());

describe('User API consumer contract', () => {
  it('fetches a user by id', async () => {
    await provider.addInteraction({
      uponReceiving: 'a request for a user',
      withRequest: { method: 'GET', path: '/v1/users/abc', headers: { Accept: 'application/json' } },
      willRespondWith: {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
          id: term({ matcher: '^[a-f0-9-]+$', generate: 'abc-123' }),
          email: like('a@b.com'),
          roles: eachLike('admin'),
        },
      },
    });

    const user = await axios.get(`${provider.mockService.baseUrl}/v1/users/abc`, {
      headers: { Accept: 'application/json' },
    });
    expect(user.data.email).toBeTruthy();
  });
});
```

### Provider verification (Pact-JVM)

```java
// provider/src/test/java/com/myapi/pact/UsersApiPactVerificationTest.java
@Provider("users-api")
@PactFolder("pacts/consumer-pacts")        // or @PactBroker for PactBroker config
public class UsersApiPactVerificationTest {

  @TestTemplate
  @ExtendWith(PactVerification invocationProvider.class)
  void verifyPact(PactVerificationContext context) {
    context.verifyInteraction();
  }

  @BeforeAll
  static void start(PactVerificationContext context) {
    context.setTarget(HttpTestTarget.fromUrl(new URL("http://localhost:8080")));
  }

  @State("a request for a user")
  void aUserExists() {
    userRepo.seed(User.builder().id("abc-123").email("a@b.com").roles(List.of("admin")).build());
  }
}
```

### Pact Broker can-i-deploy (CI)

```bash
docker run --rm \
  -e PACT_BROKER_BASE_URL="$PACT_BROKER_URL" \
  -e PACT_BROKER_TOKEN="$PACT_BROKER_TOKEN" \
  pactfoundation/pact-cli:latest \
  broker can-i-deploy \
    --pacticipant orders-service \
    --version $GIT_SHA \
    --to-environment staging
```

### Consumer publish step

```bash
docker run --rm \
  -v $PWD/pact:/app/pact \
  -e PACT_BROKER_BASE_URL="$PACT_BROKER_URL" \
  -e PACT_BROKER_TOKEN="$PACT_BROKER_TOKEN" \
  pactfoundation/pact-cli:latest \
  publish /app/pact/pacts \
  --consumer-app-version $GIT_SHA \
  --tag $BRANCH \
  --branch $BRANCH
```

### CI consumer `pact.yml`

```yaml
jobs:
  consumer-pact:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: npm }
      - run: npm ci
      - run: npm test -- pact             # generates pacts/*.json
      - run: |                            # publish to broker
          docker run --rm -v $PWD/pact:/app/pact \
            -e PACT_BROKER_BASE_URL=$PACT_BROKER_URL \
            -e PACT_BROKER_TOKEN=$PACT_BROKER_TOKEN \
            pactfoundation/pact-cli:latest publish /app/pact/pacts \
              --consumer-app-version ${{ github.sha }} \
              --tag ${{ github.ref_name }} \
              --branch ${{ github.ref_name }}
          # Webhook in broker will trigger provider-verifier CI in response.
```

## Common pitfalls / anti-patterns

- ❌ Hardcoding full string values in pact bodies — fails every time the
  fixture changes; use `like({...})` + `term` for regex-bound uniqueness.
- ❌ Provider state leakage — provider test step seeds "a user exists", then
  the next interaction receives the wrong user; clean between interactions.
- ❌ Generating JSON pacts committed to git — push to broker only; the
  broker is the source of truth.
- ❌ Forgetting `can-i-deploy` step — certs run if no checkout
- ❌ Tagging `prod` without verification — false confidence in production
   compatibility; only tag after verified result uploaded.
- ❌ Provider verification logging into staging DB — leaks test data and
   introduces cross-env variance; use ephemeral mailboxed DB
   (`DATABASE_URL=postgres://test:test@...`).
- ❌ Consumer tests doing too much in one interaction (multiple endpoints
   chained) — break into `addInteraction` calls per discrete request.
- ❌ Manual pact JSON hand-editing — tooling generates valid JSON; manual
   edits always drift.
- ❌ Skipping provider state handlers — `StateChange` URL on JVM or
   `stateHandlers` on V3 JSON setup; Pact invokes them between
   interactions; missing = silent skip with stale fixtures.
- ❌ Treating pacts as integration tests — Pact is *contract*; verify the
   exact bytes you expect, not "the full happy path".

## Testing & validation

- Consumer test suite filters run pact tests via `npm test -- pact`.
- Provider verifier: `mvn -Dtest='*PactVerificationTest' test` (or equivalent).
- `can-i-deploy` exit codes — nonzero = incompatible versions.
- Broker UI matrix view — quickly eyeball compatibility.
- Overall strategy: use matrix report at release time.

## Performance & tuning

- Pact consumer tests add ~100-300ms per interaction (local Mock Service
  port spin-up + tests); keep one broker publish per branch, not per commit.
- Provider verification with Pact-JVM spins up the JVM (~3-5s), then
  runs each interaction ~50-200ms. Parallelize via Pact-JVM `@EnabledForRoot`
  feature if many contracts.
- Use **bi-directional contracts** (Pactflow) when the provider already
  emits OpenAPI — skips provider verification step entirely, big win.
- Cache the pact-broker client library; clean cache jest enough to avoid
  persistent stale pacts if the broker is offline.

## Security (top 5)

1. **Broker tokens** should be rotation-capable per-workspace; never embed
   in client-side / browser-facing config.
2. **Provider state handler endpoints** should ONLY be reachable from tests
   (network ACL to CI pod subnet); exposing them allows bypassing auth in
   prod.
3. Pacts may include representative request/response bodies — never put real
   customer records; use `like({...})` to assert shape only.
4. CI Pact jobs interact with the broker; if the broker is self-hosted,
   add basic-auth + TLS at the reverse proxy.
5. Verification runs on provider CI must not run against prod — providers
   mistake in tests could delete real records; isolate DB.

## Official docs & references

- Pact docs: https://docs.pact.io/
- Pact JS: https://github.com/pact-foundation/pact-js
- Pact JVM: https://github.com/pact-foundation/pact-jvm
- pact-python: https://github.com/pact-foundation/pact-python
- pact-go: https://github.com/pact-foundation/pact-go
- pact-broker: https://github.com/pact-foundation/pact-broker
- Pactflow SaaS: https://pactflow.io/
- Pact spec V3: https://github.com/pact-foundation/pact-specification/tree/version-3
- Matchers reference: https://docs.pact.io/client-side/matching
- Provider states: https://docs.pact.io/provider/provider_states
- can-i-deploy: https://docs.pact.io/pact_broker/can_i_deploy
- Bi-directional contracts (Pactflow): https://docs.pactflow.io/docs/workshops/bi-directional-contracts/
- Pact CLI Docker image: https://github.com/pact-foundation/pact-ruby-standalone/releases