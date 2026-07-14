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

## Estrutura do repo

```
qa-expert-agent/
├── qa-expert.md            # o agente (frontmatter + skill routing + processo + padrões)
├── skills/                 # as 10 skills que o agente despacha (bundle offline)
│   ├── playwright/SKILL.md
│   ├── cypress/SKILL.md
│   ├── selenium/SKILL.md
│   ├── tests-back-performance-k6/SKILL.md
│   ├── tests-back-performance-locust/SKILL.md
│   ├── jmeter/SKILL.md
│   ├── a11y-axe/SKILL.md
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

- [opencode](https://opencode.ai/go?ref=N7RAC3TFM1) instalado
- (Opcional, só pra executar os testes gerados) runtimes conforme a stack alvo: Node/k6/Python/JVM/Xcode/Flutter/Android SDK

### Instalação rápida (recomendado)

```bash
curl -fsSL https://raw.githubusercontent.com/emersinrp/qa-expert-agent/master/install.sh | bash
```

Instala o agente `qa-expert` e as 10 skills em `~/.config/opencode/` (com backup de qualquer versão anterior). Na próxima sessão do opencode, qualquer tarefa que envolva testes despacha o `qa-expert` automaticamente. Prefere revisar antes de rodar? [Leia o `install.sh`](./install.sh) — ele só baixa o repo e copia os arquivos.

### Passo a passo (manual)

1. Clone o repo:

   ```bash
   git clone https://github.com/emersinrp/qa-expert-agent.git
   cd qa-expert-agent
   ```

2. Copie o **agente** para a pasta de agentes do opencode:

   ```bash
   mkdir -p ~/.config/opencode/agents
   cp qa-expert.md ~/.config/opencode/agents/qa-expert.md
   ```

3. Copie as **skills** (as 10) para a pasta de skills do opencode:

   ```bash
   mkdir -p ~/.config/opencode/skills
   cp -r skills/* ~/.config/opencode/skills/
   ```

4. Pronto. Na próxima sessão do opencode, qualquer tarefa que envolva testes (Playwright, Cypress, k6, Pact, a11y, mobile E2E, BrowserStack, etc.) despacha o `qa-expert` automaticamente, e ele carrega a skill correspondente do bundle.

### Instalação rápida (one-liner, só agente)

Se você já tem as skills instaladas por outra via e quer só o agente:

```bash
mkdir -p ~/.config/opencode/agents && \
curl -fsSL https://raw.githubusercontent.com/emersinrp/qa-expert-agent/master/qa-expert.md \
  -o ~/.config/opencode/agents/qa-expert.md
```

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

## Estrutura do agente

`qa-expert.md` segue o formato de agente do opencode:

- **frontmatter** — descrição, exemplos de dispatch, `mode`, `model`, `color`, permissões
- **skill routing** — tabela verba→skill acionada antes de agir (10 skills no bundle)
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