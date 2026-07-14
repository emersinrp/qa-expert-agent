# qa-expert-agent

Agente **`qa-expert`** de Quality Engineering — cobre estratégia de testes, E2E, contratos, mobile, acessibilidade, performance **e execução em device farms na nuvem**. Nasceu no [opencode](https://opencode.ai) e roda também em **Claude Code, Cursor, GitHub Copilot e Codex**: o corpo do agente e as 11 skills são portáveis — muda só o frontmatter e a pasta de instalação.

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
| API testing funcional (REST/GraphQL) | supertest, REST-assured, Karate, pytest, Postman | `api-testing` |
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

## Estrutura do repo

```
qa-expert-agent/
├── qa-expert.md            # o agente (frontmatter + skill routing + processo + padrões)
├── skills/                 # as 11 skills que o agente despacha (bundle offline)
│   ├── playwright/SKILL.md
│   ├── cypress/SKILL.md
│   ├── selenium/SKILL.md
│   ├── tests-back-performance-k6/SKILL.md
│   ├── tests-back-performance-locust/SKILL.md
│   ├── jmeter/SKILL.md
│   ├── a11y-axe/SKILL.md
│   ├── api-testing/SKILL.md
│   ├── pact-contract/SKILL.md
│   ├── mobile-tests/SKILL.md
│   └── browserstack/SKILL.md
├── install.sh              # instalador (one-liner)
├── README.md
└── _config.yml
```

> O bundle de skills torna o fork **autocontido**: clona, copia agente + skills, e o `qa-expert` já despacha sem depender de nada externo. Se você já tem alguma dessas skills instalada via opencode packages, pode omitir a correspondente — não vai conflitar.

## Como usar (instalação)

### Pré-requisitos

- Uma destas ferramentas: [opencode](https://opencode.ai/go?ref=N7RAC3TFM1), Claude Code, Cursor, GitHub Copilot ou Codex
- (Opcional, só pra executar os testes gerados) runtimes conforme a stack alvo: Node/k6/Python/JVM/Xcode/Flutter/Android SDK

O agente e as skills são **uma fonte só** pra qualquer ferramenta — muda só **onde** salvar o agente e **qual frontmatter** ele usa; o corpo (skill routing + processo + padrões) é idêntico. As skills (`skills/*/SKILL.md`) são portáveis: em **opencode** e **Claude Code** viram skills nativas; em **Cursor**, **Copilot** e **Codex** você mantém a pasta `skills/` no repo e o agente lê `skills/<nome>/SKILL.md` sob demanda.

> Nos snippets abaixo, **«corpo do agente»** = tudo em [`qa-expert.md`](./qa-expert.md) **abaixo** do frontmatter (da linha `You are the **qa-expert**...` até o fim). Só o cabeçalho YAML muda entre ferramentas.

### opencode (casa) — automático

```bash
curl -fsSL https://raw.githubusercontent.com/emersinrp/qa-expert-agent/master/install.sh | bash
```

Instala o agente `qa-expert` e as 11 skills em `~/.config/opencode/` (com backup de qualquer versão anterior). Na próxima sessão, qualquer tarefa de teste despacha o `qa-expert` automaticamente. Prefere revisar antes? [Leia o `install.sh`](./install.sh) — ele só baixa o repo e copia os arquivos.

Manual:

```bash
git clone https://github.com/emersinrp/qa-expert-agent.git && cd qa-expert-agent
mkdir -p ~/.config/opencode/agents ~/.config/opencode/skills
cp qa-expert.md ~/.config/opencode/agents/qa-expert.md
cp -r skills/* ~/.config/opencode/skills/
```

### Claude Code — automático

```bash
curl -fsSL https://raw.githubusercontent.com/emersinrp/qa-expert-agent/master/install.sh | bash -s -- claude
```

Instala em `~/.claude/` (agente + as mesmas 11 skills — o formato `SKILL.md` é idêntico). O instalador **gera o frontmatter do Claude** por cima do corpo canônico, porque o `mode`/`color`/`permission` do opencode não se aplicam aqui.

Manual — salve o agente em `~/.claude/agents/qa-expert.md` com este cabeçalho + o «corpo do agente», e copie as skills:

```markdown
---
name: qa-expert
description: >-
  Quality Engineering specialist — test strategy, E2E, contract, mobile,
  accessibility, and performance testing. Use for writing/maintaining tests,
  choosing a framework, debugging a flaky test, designing a test pyramid, or
  wiring tests into CI. Covers playwright, cypress, selenium, k6, locust,
  jmeter, axe-core, pact, mobile E2E (xcuitest/detox/flutter/maestro), and
  browserstack.
model: inherit
---

«corpo do agente»
```

```bash
mkdir -p ~/.claude/skills && cp -r skills/* ~/.claude/skills/
```

### Cursor

Cursor usa **rules** (`.cursor/rules/*.mdc`), não skills. Salve o «corpo do agente» como uma rule *Agent Requested* e mantenha a pasta `skills/` no repo — o agente lê `skills/<nome>/SKILL.md` quando a tarefa pede.

`.cursor/rules/qa-expert.mdc`:

```markdown
---
description: Quality Engineering — E2E, contract, mobile, a11y e performance. Escolhe framework, escreve/depura testes, integra no CI. Roteia para skills/<nome>/SKILL.md.
alwaysApply: false
---

«corpo do agente»
```

### GitHub Copilot

Salve o «corpo do agente» como arquivo de instruções e mantenha `skills/` no repo.

`.github/instructions/qa-expert.instructions.md`:

```markdown
---
applyTo: "**"
---

«corpo do agente»
```

Alternativa: cole o «corpo do agente» em `.github/copilot-instructions.md` (vale pro repo inteiro, sem frontmatter).

### Codex

Codex lê `AGENTS.md` — markdown puro, **sem frontmatter** — na raiz do projeto (ou `~/.codex/AGENTS.md` global). Cole o «corpo do agente» no `AGENTS.md` e mantenha `skills/` no repo.

### Resumo

| Ferramenta | Arquivo do agente | Frontmatter | Skills |
|---|---|---|---|
| **opencode** | `~/.config/opencode/agents/qa-expert.md` | `mode`/`model`/`color`/`permission` (como está) | `~/.config/opencode/skills/*` (nativas) |
| **Claude Code** | `~/.claude/agents/qa-expert.md` | `name` + `description` + `model` | `~/.claude/skills/*` (mesmo `SKILL.md`) |
| **Cursor** | `.cursor/rules/qa-expert.mdc` | `description` + `alwaysApply: false` | `skills/` no repo (sob demanda) |
| **Copilot** | `.github/instructions/qa-expert.instructions.md` | `applyTo: "**"` | `skills/` no repo (sob demanda) |
| **Codex** | `AGENTS.md` (raiz ou `~/.codex/`) | — (markdown puro) | `skills/` no repo (sob demanda) |

### Exemplos de dispatch

| Você diz... | Skill acionada |
|---|---|
| "Escreve um teste E2E de fluxo de login usando Playwright" | `playwright` |
| "Quero bloquear PRs que quebram WCAG 2.1 AA" | `a11y-axe` |
| "Como adiciono contract tests entre service-orders e service-payments?" | `pact-contract` |
| "Escreve testes de API do endpoint /orders — status, schema e casos de erro" | `api-testing` |
| "Preciso fazer load test da API. k6 ou Locust?" | `tests-back-performance-k6` / `locust` |
| "Como rodo meus testes XCUITest no BrowserStack em 10 iPhones reais via CI?" | `browserstack` |

## Stack do agente

- **Ferramentas:** opencode (casa), Claude Code, Cursor, GitHub Copilot, Codex
- **Formato canônico:** subagent do opencode (`mode: subagent`, `permission: edit/bash ask`, `color: #ef4444`) — adaptado por ferramenta na instalação
- **Modelo:** `model: inherit` — usa o modelo da sua sessão. Na parceria [opencode](https://opencode.ai/go?ref=N7RAC3TFM1) rodo com **GLM 5.2**.
- **Idioma das respostas:** PT-BR

## Estrutura do agente

`qa-expert.md` segue o formato de agente do opencode:

- **frontmatter** — descrição, exemplos de dispatch, `mode`, `model`, `color`, permissões
- **skill routing** — tabela verba→skill acionada antes de agir (11 skills no bundle)
- **processo** — inspect → apply skill → pirâmide → verify by running → flakiness hygiene → report
- **padrões de qualidade** — pirâmide, seletores, determinismo, CI gate, segurança, reporting
- **formato de output** — resumo + arquivos + verificação cru + próximos passos

Cada `skills/<name>/SKILL.md` é uma skill reutilizável no formato opencode — checklist específico da ferramenta, anti-patterns, comandos de verificação. Podem ser invocadas também diretamente por outros agentes, não só pelo `qa-expert`.

## Fork / contribuição

Fork à vontade. Sugestões de skills novas, ajustes de roteamento ou exemplos de dispatch extras → abre issue ou PR.

## Autor

**Emerson Rodrigues** — Arquiteto de Soluções e IA (GenAI, sistemas agênticos, Spec-Driven Development).
14+ anos em tecnologia, hoje na fronteira entre arquitetura de software e IA Generativa — conduz o *Spec Kit* na MBRF (framework SDD com 19 agentes de IA, 49 skills, integrações MCP com Figma, Azure DevOps, GitHub, Atlassian e Rovo). Trajetória de base em QA: Specialist QA Engineer e Senior QA Engineer em BRF/Wunderman/Luizalabs, instrutor de automação na QA Academy.

*Qualidade é a base. Arquitetura é o teto. IA é a alavanca entre as duas.*

---

Cadastre-se no opencode: <https://opencode.ai/go?ref=N7RAC3TFM1>