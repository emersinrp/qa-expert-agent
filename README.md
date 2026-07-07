# qa-expert-agent

Agente **`qa-expert`** para o [opencode](https://opencode.ai) — um especialista em Quality Engineering que cobre estratégia de testes, E2E, contratos, mobile, acessibilidade e performance.

> Arquitetura é o teto. Qualidade é a base. Sem base, o teto cai.

## O que ele faz

O `qa-expert` é um subagente do opencode acionado sempre que a demanda envolve testes. Em vez de improvisar, ele lê o contexto do projeto (`package.json`, `pubspec.yaml`, `pom.xml`, CI, folder de testes, padrão de seletores) e faz o **skill routing** — carrega automaticamente a skill certa para a ferramenta certa:

| Domínio | Skill carregada |
|---|---|
| E2E web com Playwright | `playwright` |
| E2E web + component com Cypress | `cypress` |
| Selenium / WebDriver (legado, grids) | `selenium` |
| Performance HTTP — stack JS/TS | `tests-back-performance-k6` |
| Performance HTTP — Python / distribuído | `tests-back-performance-locust` |
| Performance GUI — JMeter (legado Java) | `jmeter` |
| Acessibilidade / WCAG / axe-core | `a11y-axe` |
| Contract tests / consumer-driven / Pact | `pact-contract` |
| Mobile E2E — Flutter `integration_test`, iOS `XCUITest`, RN `Detox`, Maestro | `mobile-tests` |

## Princípios que ele segue

- **Pirâmide de testes como guia, não como lei** — usa o menor nível que prova o comportamento. Regressão no unitário custa ~10x menos que no E2E.
- **Seletores estáveis** — `role`/`label` primeiro, `data-testid` quando semântica não isola. Nunca CSS ou texto frágil.
- **Determinismo** — nada de `setTimeout`, wait implícito ou horário do dia. Teste flaky é corrigido ou isolado com ticket, nunca mascarado com `retries: 3`.
- **CI gate de verdade** — saída não-zero em falha. "a suite está maiormente verde" não é aceitável.
- **Segurança** — sem credenciais em fixtures, sem PII real, secrets via env de CI.
- **Verifica rodando** — ele **executa** os testes (`npx playwright test`, `k6 run`, `locust ...`, `mvn test`, `flutter test integration_test/`...) e cola o output cru. Nunca afirma "testes passaram" sem o runner.
- **Relatório estruturado** — JUnit XML/JSON/HTML quando possível.

## Como usar (instalação)

1. Tenha o [opencode](https://opencode.ai/go?ref=N7RAC3TFM1) instalado.
2. Copie o arquivo `qa-expert.md` para a pasta de agentes do opencode:

   ```bash
   mkdir -p ~/.config/opencode/agents
   curl -fsSL https://raw.githubusercontent.com/emersinrp/qa-expert-agent/main/qa-expert.md \
     -o ~/.config/opencode/agents/qa-expert.md
   ```

3. Pronto. Na próxima sessão do opencode, tarefas que envolvam testes (Playwright, Cypress, k6, Pact, a11y, mobile E2E, etc.) despacham o `qa-expert` automaticamente.

## Stack do agente

- **Modelo:** GLM 5.2 (`glm-5.2`)
- **Runner:** opencode (subagent com `mode: subagent`, `permission: edit/bash ask`)
- **Idioma das respostas:** PT-BR

## Fork / contribuição

Fork à vontade — sugestões de skills novas ou ajustes de roteamento, abre issue ou PR.

## Autor

**Emerson Rodrigues** — Tech Lead / Solutions Architect, Specialist QA Engineer.
*Qualidade é a base. Arquitetura é o teto.*

---

Cadastre-se no opencode: <https://opencode.ai/go?ref=N7RAC3TFM1>
