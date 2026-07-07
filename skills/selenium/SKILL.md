---
name: selenium
description: Use this skill for Selenium WebDriver (4.x) work — Java/JUnit, Python/pytest, .NET/NUnit, JS/Mocha, Selenium Grid (Hub+Node) for cross-browser and distributed runs, Selenium Manager auto-driver, Relative Locators (`above`/`below`/`near`), Page Object Model with PageFactory or composition, BrowserStack/LambdaTest cloud routing, migration to modern Selenium from legacy 3.x. Trigger on "Selenium", "WebDriver", "WebElement", "Selenium Grid", "RemoteWebDriver", "PageFactory", "relative locators", "BrowserStack", "LambdaTest". Use ONLY for Selenium; for Playwright/Cypress use those skills.
---

# Selenium (WebDriver 4.x) Best Practices

## When to use / When NOT to use

| Use when | Do NOT use when |
| --- | --- |
| Legacy / mature investment in Selenium ecosystem | New project — reach for Playwright/Cypress first |
| Cross-browser on legacy IE / old Safari pinning | Native app testing (use mobile-tests skill) |
| Heavy grid runs via Selenium Grid 4 | Component testing (use Vitest/Jest + Testing Library) |
| Cloud providers (BrowserStack / Sauce Labs / LambdaTest) support the protocol | Header-bidding / mobile-web emulation (Playwright mobile viewports are cheaper) |

## Core stack & versions

- **Selenium 4.x** as baseline. 3.x is EOL; do not start new project there.
- **Selenium Manager** (built-in since 4.6) auto-resolves drivers; no more
  manual `chromedriver` downloads.
- **Selenium Grid 4** with Hub + Node + Router / Distributor / Session Queue
  architecture. Docker compose official images or `selenium/hub` k8s helm.
- **WebDriver protocol** (W3C standard) — Selenium now speaks the same
  protocol newer drivers implement natively.
- Languages: Java/JUnit/AssertJ (most mainstream), Python/pytest,
  .NET/NUnit, JS/Mocha, Ruby/RSpec, Kotlin.
- Cloud: BrowserStack, Sauce Labs, LambdaTest use Selenium as the protocol;
  just change `RemoteWebDriver` URL and capabilities.
- Companion: `WebDriverManager` (still useful for advanced driver pinning
  where Selenium Manager leaves gaps).

## Project structure (canonical, Java/Maven example)

```
project/
├── pom.xml
├── src/test/java/com/myapi/e2e/
│   ├── BaseTest.java                  # driver setup/teardown
│   ├── pages/                          # page objects
│   │   ├── LoginPage.java
│   │   └── DashboardPage.java
│   ├── users/                          # feature folders
│   │   └── LoginIT.java
│   └── factories/                       # RemoteWebDriver factory
└── src/test/resources/
    ├── selenium-grid.yaml             # gitignored for prod
    ├── staging.properties
    └── logback-test.xml
```

## Best practices checklist

1. ✅ Upgrade Selenium to **4.x** — Selenium Manager removes driver hell.
2. ✅ Use **explicit waits** (`WebDriverWait` + `ExpectedConditions` /
   `until.elementToBeClickable(...)`) — never implicit (`manage().timeouts().implicitlyWait()`).
3. ✅ Disable implicit waits globally; implicit + explicit interaction is
   undefined behavior per W3C.
4. ✅ **Test isolation**: `@BeforeEach` new driver per test; `@AfterEach`
   quit. Sharing a session across tests leads to cascading failures.
5. ✅ **RemoteWebDriver** for CI vs `ChromeDriver`/`FirefoxDriver` for local
   dev — abstract via test setup.
6. ✅ **Capabilities object** via `Capabilities` / `MutableCapabilities` /
   `Options` (browser-specific) — not raw DesiredCapabilities (deprecated
   in 4.x).
7. ✅ **Browser options**: set headless chrome (`--headless=new` since Chrome
   109), disable GPU in CI, set window size; never `--user-data-dir` shared
   across tests.
8. ✅ **Page Object Model** with composition — prefer composition (`new
   LoginPage(driver).login(...)`) over PageFactory reflection (`@FindBy`)
   when possible; PageFactory is fine for legacy.
9. ✅ **Locators** priority: `id` (unique) > `name` > CSS > XPath text; never
   copy XPath from devtools that includes div[3]//div[2] indices.
10. ✅ **`By.id` / `By.cssSelector`** more stable than XPath in most cases.
11. ✅ **`By.role` (Selenium 4+)** supports `AccessibleBy` (under the hood
    Accessibility API). Use when available in your binding.
12. ✅ **Actions / keyboard + mouse**: use `Actions` builder rather than
    triggering synthetic JS events.
13. ✅ **Screenshot on failure**: `((TakesScreenshot)driver).getScreenshotAs(OutputType.BYTES)`
    attached to test report.
14. ✅ **`AScreenshot` + report integration**: attach base64 to Allure / Extent
    / ReportPortal.
15. ✅ **`JS executor`** for unavoidable cases (`scrollIntoView`), not as a
    general substitute for actions.
16. ✅ **Window/tab management**: `driver.switchTo().window(handle)` after
    opening new tabs; never assume handle order.
17. ✅ **Alerts / frames**: `switchTo().alert()`, `switchTo().frame(...)`,
    always remember `switchTo().defaultContent()` after.
18. ✅ **File downloads** in headless Chrome: set `download.default_directory`
    capability + watchdog on a temp dir per test.
19. ✅ **Grid 4 docker-compose** in CI: `selenium/standalone-chrome` docker
    image or distributed grid for sharded runs.
20. ✅ **Parallel via JUnit5 `@Execution(CONCURRENT)` + JUnit Platform** or
    TestNG `<suite parallel="methods">`; ensure no shared state.
21. ✅ **Network mocking**: Selenium does not have parity to `cy.intercept`
    / `page.route`. Use `BrowserMobProxy` (Java) or `mitmproxy` external
    sidecar if needed; consider whether the test really needs it.
22. ✅ **Headless vs headed**: `--headless=new` is the new headless mode
    since Chrome 109 — closer to real Chrome; older `--headless` defaulted
    to a separate renderer.
23. ✅ **Refresh-and-retry**: do explicit `wait.until(ExpectedConditions.visibilityOfElementLocated(...))`
    to avoid polls.
24. ✅ **BrowserStack / Sauce Labs / LambdaTest** all support capabilities
    `bstack:options` / `sauce:options` / `LT:Options`; pass via `Options`.
25. ✅ **Trace** via OpenTelemetry — Selenium 4 emits spans; merge with
    system traces when useful.

## Canonical patterns

### Base test (Java/JUnit5)

```java
public abstract class BaseTest {
    protected WebDriver driver;
    protected WebDriverWait wait;

    @BeforeEach
    void setUp() {
        ChromeOptions opts = new ChromeOptions();
        if (Boolean.parseBoolean(System.getProperty("headless", "true"))) {
            opts.addArguments("--headless=new", "--no-sandbox", "--disable-gpu");
            opts.addArguments("--window-size=1440,900");
        }
        driver = new ChromeDriver(opts);
        wait = new WebDriverWait(driver, Duration.ofSeconds(8));
        driver.manage().window().setSize(new Dimension(1440, 900));
    }

    @AfterEach
    void tearDown() {
        if (driver != null) driver.quit();
    }
}
```

### Page object (composition style)

```java
public class LoginPage {
    private final WebDriver driver;
    private final WebDriverWait wait;
    public LoginPage(WebDriver driver, WebDriverWait wait) {
        this.driver = driver; this.wait = wait;
    }

    public LoginPage open() { driver.get(System.getProperty("baseURL") + "/login"); return this; }
    public LoginPage setEmail(String v) {
        wait.until(ExpectedConditions.visibilityOfElementLocated(By.id("email"))).sendKeys(v);
        return this;
    }
    public LoginPage setPassword(String v) {
        driver.findElement(By.id("password")).sendKeys(v);
        return this;
    }
    public DashboardPage submit() {
        driver.findElement(By.cssSelector("button[type=submit]")).click();
        return new DashboardPage(driver, wait);
    }
}
```

### Explicit wait + expected conditions

```java
wait.until(ExpectedConditions.elementToBeClickable(By.id("submit"))).click();
wait.until(ExpectedConditions.urlMatches(".*/dashboard"));
WebElement title = wait.until(
    ExpectedConditions.visibilityOfElementLocated(By.tagName("h1"))
);
Assert.assertThat(title.getText(), equalTo("Welcome"));
```

### Relative locators

```java
WebElement submit = driver.findElement(
    RelativeLocator.with(By.tagName("button"))
        .below(By.id("password"))
        .near(By.id("remember-me"))
);
submit.click();
```

### RemoteWebDriver with capabilities (BrowserStack example)

```java
MutableCapabilities caps = new MutableCapabilities();
caps.setCapability("browserName", "chrome");
caps.setCapability("bstack:options", Map.of(
    "userName", System.getenv("BS_USER"),
    "accessKey", System.getenv("BS_KEY"),
    "browserVersion", "latest",
    "projectName", "myapi-e2e",
    "sessionName", "Login flow"
));

URL hub = new URL("https://hub-cloud.browserstack.com/wd/hub");
WebDriver driver = new RemoteWebDriver(hub, caps);
```

### Selenium Grid 4 (Docker compose)

```yaml
services:
  selenium-hub:
    image: selenium/hub:latest
    ports: ["4442:4442", "4443:4443", "4444:4444"]
  chrome:
    image: selenium/node-chrome:latest
    depends_on: [selenium-hub]
    environment:
      - SE_EVENT_BUS_HOST=selenium-hub
      - SE_EVENT_BUS_PUBLISH_PORT=4442
      - SE_EVENT_BUS_CONSUME_PORT=4443
    scale: 4
```

CI runs `RemoteWebDriver(new URL("http://localhost:4444/wd/hub"), opts)`.

## Common pitfalls / anti-patterns

- ❌ `driver.manage().timeouts().implicitlyWait(...)` mixed with explicit
  waits — undefined behavior, silent confusion.
- ❌ `Thread.sleep(500)` instead of `WebDriverWait.until(...)` — slows the
  suite + flaky when the next render takes 501ms.
- ❌ XPath with positional indices (`/div/div[3]/span`) — fragile.
- ❌ Sharing driver across tests — cascades failures when one test breaks
  navigation.
- ❌ Catching `Exception` to `// ignore` swallow — hides flakiness; never.
- ❌ Not quitting driver — orphan Chrome processes eat CI memory.
- ❌ Real prod DB / API in tests — slow + flaky; staging + seeded data.
- ❌ Hard-coded credentials in source — use system properties / env.
- ❌ Page object with mutable `driver.navigateTo(...)` mutating `BasePage`'s
  state across tests — keep immutable, return new page object per action.
- ❌ Forgetting `switchTo().defaultContent()` after frame interactions.
- ❌ Using `JS executor.click()` as a workaround for an unclickable element —
  investigate why; usually covered element, sweep ARIA / scrolling.
- ❌ Throws + try/catch wrapping all `findElement` (defensive) — use explicit
  `wait` instead; driver raises `NoSuchElementException` naturally.

## Testing & validation

- JUnit5 + Maven Surefire/Failsafe: `mvn -Dtest=*IT verify` (integration
  tests isolated).
- Allure report via `allure-maven` plugin for visual run output.
- Test result DSL via AssertJ: `assertThat(title).isEqualTo("Welcome")`.
- CI: sharded via Grid 4 distribute — `--width 4` fans to 4 chromium nodes.
- BrowserStack Local / Sauce Connect tunnel when crossing into internal
  env from cloud grid.
- Trace inspection: OpenTelemetry GraphQL spans rastered in Jaeger if
  needed.

## Performance & tuning

- **Headless=new** Chrome (since 109): closer to the headed browser,
  smaller CI footprint.
- **Grid 4 distribute**: distribute tests across grid nodes — 4 nodes can
  net 3-4x improvement for sharded suites with 1 suite per node.
- **Number of `findElement` calls**: cache `WebElement` references only
  within a single page interaction; do **not** save them across stages
  (DOM mutations make stale references).
- **Window/tab maximized only when needed**: `--window-size=1440,900`
  fixes flakiness vs `maximize()` which resizes asynchronously.
- Headed mode is sometimes needed when chromium cross-iframe behaviors
  disagree with headless — keep a `headedProfile` CI job for sanity.
- Use `RemoteWebDriver` with `Capabilities` minimizing extra calls.

## Security (top 5)

1. **No secrets in source** — env / system properties / CI secrets.
2. **Test environment isolation** — dedicated staging; never let E2E tests
   write into prod.
3. **Cloud credentials** (BrowserStack/Sauce) — store in CI secrets,
   never logged.
4. **Test users** must be fake — do not query real customer data via web
   UI even if read-only; leak path via screenshots/reports.
5. **Browser sandbox** flags (`--no-sandbox`, disable DevShm) only inside
   CI containers; never on developer's main machine.

## Official docs & references

- Selenium docs: https://www.selenium.dev/documentation/
- Selenium 4 upgrade guide: https://www.selenium.dev/documentation/overview/selenium_4/
- Selenium Manager: https://www.selenium.dev/documentation/selenium_manager/
- Grid 4: https://www.selenium.dev/documentation/grid/
- WebDriver protocol (W3C): https://w3c.github.io/webdriver/
- Relative locators: https://www.selenium.dev/documentation/webdriver/elements/locators/
- WebDriverWait: https://www.selenium.dev/documentation/webdriver/waits/
- Page Object Model: https://www.selenium.dev/documentation/test_practices/encouraged/page_object_models/
- Docker images (Selenium): https://github.com/SeleniumHQ/docker-selenium
- BrowserStack Automate: https://www.browserstack.com/docs/automate/selenium
- Sauce Labs: https://docs.saucelabs.com/
- LambdaTest: https://www.lambdatest.com/support/docs/selenium-documentation/
- Allure Report (Java): https://allurereport.org/docs/java/