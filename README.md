# qa-expert-agent

Agente **`qa-expert`** para o [opencode](https://opencode.ai) — um especialista em Quality Engineering que cobre estratégia de testes, E2E, contratos, mobile, acessibilidade, performance **e execução em device farms na nuvem**.

> Arquitetura é o teto. Qualidade é a base. Sem base, o teto cai.

## Por que este agente existe

Subagentes genéricos tendem a "improvisar" quando a tarefa é teste: misturam Playwright em projeto Cypress, escrevem `setTimeout` em vez de auto-wait, mascaram flaky com `retries: 3`. O `qa-expert` foi desenhado contra isso: ele **inspecta antes de agir**, respeita a stack que já existe no projeto e segue skills com checklists reais (não vibes).

## O que ele cobre

O `qa-expert` faz o **skill routing** — lê o contexto (`package.json`, `pubspec.yaml`, `pom.xml`, CI, folder de testes, padrão de seletores) e carrega automaticamente a skill certa:

| Domínio | Ferramentas | Skill carregada |
|---|---|---|
| E2E web | Playwright | `playwright` |
| E2E web + component | Cypress | `cypress` |
| WebDriver / grids legados | Selenium | `selenium` |
| Performance HTTP (JS/TS) | k6 | `tests-back-performance-k6` |
| Performance HTTP (Python / distribuído) | Locust | `tests-back-performance-locust` |
| Performance GUI (legado Java) | JMeter | `jmeter` |
| Acessibilidade / WCAG 2.1 AA | axe-core | `a11y-axe` |
| Contract tests / consumer-driven | Pact | `pact-contract` |
| Mobile E2E | XCUITest (iOS), Detox (RN), `integration_test` (Flutter), Maestro | `mobile-tests` |
| **Device farm na nuvem** | **BrowserStack App Automate / App Live / Local tunnel** | **`browserstack`** |

## Princípios que ele segue

- **Pirâmide de testes como guia, não como lei** — usa o menor nível que prova o comportamento. Regressão no unitário custa ~10x menos que no E2E.
- **Seletores estáveis** — `role`/`label` primeiro, `data-testid` quando a semântica não isola. Nunca CSS frágil ou texto quebradiço.
- **Determinismo** — nada de `setTimeout`, wait implícito ou dependência de horário. Teste flaky é corrigido ou isolado com ticket, nunca mascarado com `retries: 3`.
- **CI gate de verdade** — saída não-zero em falha. "a suite está maiormente verde" não é aceitável.
- **Segurança** — sem credenciais em fixtures, sem PII real, secrets via env de CI.
- **Verifica rodando** — ele **executa** os testes e cola o output cru. Nunca afirma "testes passaram" sem o runner:
  - `npx playwright test` · `npx cypress run --spec` · `mvn test` / `pytest` / `dotnet test`
  - `k6 run` · `locust -f locustfile.py --headless ...` · `jmeter -n -t plan.jmx -l out.jtl`
  - `xcodebuild test -scheme <scheme>` · `flutter test integration_test/`
  - axe: parte da run E2E via `@axe-core/playwright` / `@axe-core/cypress`
  - Pact: `npm test` (consumer) · `npm run pact:verify` (provider)
- **Relatório estruturado** — JUnit XML/JSON/HTML quando possível, nunca só console.

## Como usar (instalação)

1. Tenha o [opencode](https://opencode.ai/go?ref=N7RAC3TFM1) instalado.
2. Copie o agente para a pasta de agentes do opencode:

   ```bash
   mkdir -p ~/.config/opencode/agents
   curl -fsSL https://raw.githubusercontent.com/emersinrp/qa-expert-agent/master/qa-expert.md \
     -o ~/.config/opencode/agents/qa-expert.md
   ```

3. Pronto. Na próxima sessão do opencode, qualquer tarefa que envolva testes (Playwright, Cypress, k6, Pact, a11y, mobile E2E, BrowserStack, etc.) despacha o `qa-expert` automaticamente.

### Exemplos de dispatch

| Você diz... | Skill acionada |
|---|---|
| "Escreve um teste E2E de fluxo de login usando Playwright" | `playwright` |
| "Quero bloquear PRs que quebram WCAG 2.1 AA" | `a11y-axe` |
| "Como adiciono contract tests entre service-orders e service-payments?" | `pact-contract` |
| "Preciso fazer load test da API. k6 ou Locust?" | `tests-back-performance-k6` / `locust` |
| "Como rodo meus testes XCUITest no BrowserStack em 10 iPhones reais via CI?" | `browserstack` |

## Stack do agente

- **Runner:** opencode (subagent `mode: subagent`, `permission: edit/bash ask`)
- **Modelo:** GLM 5.2 (`glm-5.2`)
- **Idioma das respostas:** PT-BR
- **Cor:** `#ef4444` (vermelho QA no opencode)

## Estrutura do arquivo

`qa-expert.md` segue o formato de agente do opencode:

- **frontmatter** — descrição, exemplos de dispatch, `mode`, `model`, `color`, permissões
- **skill routing** — tabela verba→skill acionada antes de agir
- **processo** — inspect → apply skill → pirâmide → verify by running → flakiness hygiene → report
- **padrões de qualidade** — pirâmide, seletores, determinismo, CI gate, segurança, reporting
- **formato de output** — resumo + arquivos + verificação cru + próximos passos

## Fork / contribuição

Fork à vontade. Sugestões de skills novas, ajustes de roteamento ou exemplos de dispatch extras → abre issue ou PR.

## Autor

**Emerson Rodrigues** — Specialist QA Engineer / Tech Lead.
*Qualidade é a base. Arquitetura é o teto.*

---

Cadastre-se no opencode: <https://opencode.ai/go?ref=N7RAC3TFM1>