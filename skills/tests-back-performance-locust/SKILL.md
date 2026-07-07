---
name: tests-back-performance-locust
description: Use when creating, structuring, or improving backend API performance tests with Locust (Python) — load tests, stress tests, spike tests, smoke tests, soak tests. Trigger on requests for performance testing, load testing, stress testing, throughput validation, or when locustfiles need custom load shapes, task weighting, distributed testing, event hooks, or CI/CD integration with Python.
---

# Backend Performance Testing with Locust

## Overview

Locust é um framework Python open-source para testes de performance. Testes são escritos em Python puro, versionados junto ao código-fonte e executados localmente, em modo distribuído ou em pipelines CI/CD. Princípio central: **testes de performance são código** — seguem os mesmos padrões de qualidade do código de produção.

## Test Types & When to Use

| Tipo          | Usuários / Carga       | Duração      | Objetivo |
|---------------|------------------------|--------------|----------|
| **Smoke**     | 2–5 users              | 30–60s       | Valida o script, baseline mínimo |
| **Load**      | Pico esperado de users | 5–30 min     | Verifica sistema sob carga normal |
| **Stress**    | 2–3× pico              | 10–30 min    | Encontra ponto de ruptura |
| **Spike**     | Surge repentino        | Burst curto  | Testa recuperação após pico de tráfego |
| **Soak**      | Carga normal           | 1–24 h       | Detecta memory leaks, degradação progressiva |

## Project Structure

```
tests/performance/
  config/
    settings.py        # BASE_URL, thresholds, env vars
  data/
    users.csv          # Dados de teste parametrizados
    payloads.py        # Payloads reutilizáveis
  users/
    auth_user.py       # HttpUser com autenticação
    guest_user.py      # HttpUser sem autenticação
  tasks/
    product_tasks.py   # TaskSets por domínio
    checkout_tasks.py
  shapes/
    load_shape.py      # LoadTestShape customizados
  locustfile.py        # Entry point principal
  locustfile.smoke.py  # Entry point smoke test
  locust.conf          # Configuração headless/CI
```

## Core Locustfile Anatomy

```python
# locustfile.py
import os
from locust import HttpUser, task, between, events
from locust.runners import MasterRunner

# ── Configuração de ambiente ──────────────────────────────────────────
BASE_URL = os.getenv("BASE_URL", "http://localhost:8000")
FAILURE_RATE_THRESHOLD = float(os.getenv("FAILURE_RATE_THRESHOLD", "0.01"))

# ── User principal ────────────────────────────────────────────────────
class APIUser(HttpUser):
    host = BASE_URL
    wait_time = between(1, 3)  # think time realista entre tarefas

    def on_start(self):
        """Executado 1x por usuário ao iniciar — autenticação aqui."""
        resp = self.client.post(
            "/auth/login",
            json={"username": os.getenv("TEST_USER"), "password": os.getenv("TEST_PASS")},
            name="auth/login",  # SEMPRE nomeie requests para agrupamento
        )
        resp.raise_for_status()
        token = resp.json()["access_token"]
        self.client.headers.update({"Authorization": f"Bearer {token}"})

    @task(5)  # peso 5× maior que tarefas com @task(1)
    def list_products(self):
        self.client.get("/api/products", name="products/list")

    @task(2)
    def get_product(self):
        self.client.get("/api/products/42", name="products/detail")

    @task(1)
    def create_order(self):
        with self.client.post(
            "/api/orders",
            json={"product_id": 42, "qty": 1},
            name="orders/create",
            catch_response=True,  # permite validação manual do response
        ) as resp:
            if resp.status_code == 201:
                resp.success()
            else:
                resp.failure(f"Expected 201, got {resp.status_code}: {resp.text}")

# ── Event hooks ───────────────────────────────────────────────────────
@events.quitting.add_listener
def assert_thresholds(environment, **kwargs):
    """Falha o processo se taxa de erro exceder threshold (para CI/CD)."""
    stats = environment.runner.stats.total
    if stats.num_requests == 0:
        return
    failure_rate = stats.num_failures / stats.num_requests
    if failure_rate > FAILURE_RATE_THRESHOLD:
        environment.process_exit_code = 1
        print(f"FALHOU: failure rate {failure_rate:.2%} > {FAILURE_RATE_THRESHOLD:.2%}")
```

## SequentialTaskSet — Fluxo Ordenado de Usuário

```python
# tasks/checkout_tasks.py
from locust import SequentialTaskSet, task

class CheckoutFlow(SequentialTaskSet):
    """Fluxo completo: navegar → adicionar ao carrinho → comprar."""

    def on_start(self):
        self.product_id = None

    @task
    def browse_products(self):
        resp = self.client.get("/api/products", name="products/list")
        if resp.status_code == 200 and resp.json():
            self.product_id = resp.json()[0]["id"]

    @task
    def view_product(self):
        if self.product_id:
            self.client.get(f"/api/products/{self.product_id}", name="products/detail")

    @task
    def add_to_cart(self):
        if self.product_id:
            self.client.post("/api/cart", json={"product_id": self.product_id}, name="cart/add")

    @task
    def checkout(self):
        self.client.post("/api/checkout", json={"payment": "pix"}, name="checkout/submit")
        self.interrupt()  # OBRIGATÓRIO: volta ao User após sequência completa
```

## Custom LoadTestShape — Controle Total da Carga

```python
# shapes/load_shape.py
from locust import LoadTestShape

class StagesShape(LoadTestShape):
    """Ramp up → steady state → spike → ramp down."""

    stages = [
        {"duration": 60,  "users": 10,  "spawn_rate": 2},   # ramp up
        {"duration": 180, "users": 50,  "spawn_rate": 5},   # steady state
        {"duration": 240, "users": 200, "spawn_rate": 50},  # spike
        {"duration": 300, "users": 50,  "spawn_rate": 10},  # recover
        {"duration": 360, "users": 0,   "spawn_rate": 10},  # ramp down
    ]

    def tick(self):
        run_time = self.get_run_time()
        for stage in self.stages:
            if run_time < stage["duration"]:
                return stage["users"], stage["spawn_rate"]
        return None  # None encerra o teste
```

## Parametrização com Dados Externos

```python
# data/payloads.py
import csv
from locust import HttpUser, task, between

# Carrega CSV uma vez na memória — compartilhado entre todos os users
_users_data = []
with open("tests/performance/data/users.csv") as f:
    _users_data = list(csv.DictReader(f))

class ParametrizedUser(HttpUser):
    wait_time = between(1, 2)

    def on_start(self):
        # Distribui dados por user ID (evita colisão entre greenlets)
        user_data = _users_data[self.user_id % len(_users_data)]
        resp = self.client.post("/auth/login", json=user_data, name="auth/login")
        self.token = resp.json()["token"]
        self.client.headers["Authorization"] = f"Bearer {self.token}"
```

## Validação de Resposta com catch_response

```python
@task
def create_resource(self):
    with self.client.post(
        "/api/resources",
        json={"name": "test"},
        name="resources/create",
        catch_response=True,
    ) as resp:
        # Marcar sucesso/falha manualmente — permite lógica de negócio
        if resp.status_code != 201:
            resp.failure(f"Esperado 201, recebido {resp.status_code}")
        elif "id" not in resp.json():
            resp.failure("Response sem campo 'id'")
        else:
            resp.success()
```

## Configuração via locust.conf (CI/CD)

```ini
# locust.conf — carregado automaticamente pelo Locust
host = http://localhost:8000
headless = true
users = 50
spawn-rate = 5
run-time = 5m
html = reports/locust_report.html
csv = reports/locust
loglevel = INFO
```

## Distributed Testing com Docker Compose

```yaml
# docker-compose.perf.yml
version: "3"
services:
  master:
    image: locustio/locust
    ports: ["8089:8089"]
    volumes: ["./tests/performance:/mnt/locust"]
    command: >
      -f /mnt/locust/locustfile.py
      --master
      --expect-workers=4
      --headless -u 500 -r 20 --run-time 10m
      --html /mnt/locust/reports/report.html
    environment:
      - BASE_URL=${BASE_URL}
      - TEST_USER=${TEST_USER}
      - TEST_PASS=${TEST_PASS}

  worker:
    image: locustio/locust
    volumes: ["./tests/performance:/mnt/locust"]
    command: -f /mnt/locust/locustfile.py --worker --master-host=master
    deploy:
      replicas: 4
    environment:
      - BASE_URL=${BASE_URL}
```

## CI/CD — GitHub Actions

```yaml
# .github/workflows/performance.yml
name: Performance Tests
on:
  schedule:
    - cron: "0 2 * * *"  # nightly
  workflow_dispatch:

jobs:
  locust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install locust
      - name: Run Locust
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}
          TEST_USER: ${{ secrets.TEST_USER }}
          TEST_PASS: ${{ secrets.TEST_PASS }}
        run: |
          locust -f tests/performance/locustfile.py \
            --headless -u 50 -r 5 --run-time 5m \
            --html reports/report.html \
            --csv reports/locust
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: locust-reports
          path: reports/
```

## Métricas & Comandos

### Métricas Nativas Importantes

| Métrica          | O que mede |
|------------------|------------|
| `avg_response_time` | Tempo médio de resposta (ms) |
| `min_response_time` | Menor tempo de resposta |
| `max_response_time` | Maior tempo de resposta |
| `median_response_time` | Mediana (p50) |
| `response_times[95]` | Percentil 95 |
| `num_requests`   | Total de requisições |
| `num_failures`   | Total de falhas |
| `current_rps`    | Requisições por segundo atuais |
| `fail_ratio`     | Taxa de falha (0.0–1.0) |

### Comandos Essenciais

```bash
# Instalar
pip install locust

# Rodar com UI (padrão)
locust -f locustfile.py

# Headless (CI)
locust -f locustfile.py --headless -u 100 -r 10 --run-time 5m -H https://api.example.com

# Com arquivo de configuração
locust --config locust.conf

# Relatório HTML
locust -f locustfile.py --headless -u 50 -r 5 --run-time 3m --html report.html

# Distribuído local (4 workers)
locust -f locustfile.py --master &
locust -f locustfile.py --worker &
locust -f locustfile.py --worker &
locust -f locustfile.py --worker &
locust -f locustfile.py --worker

# Tags (executar subset de tasks)
locust -f locustfile.py --tags smoke
```

## wait_time Quick Reference

```python
from locust import between, constant, constant_pacing, constant_throughput

wait_time = between(1, 3)              # aleatório entre 1s e 3s (mais realista)
wait_time = constant(1)                # fixo em 1s
wait_time = constant_pacing(5)        # garante 1 task a cada 5s por user
wait_time = constant_throughput(0.1)  # mantém 0.1 task/s por user
```

## Common Mistakes

| Erro | Correção |
|------|----------|
| Não nomear requests | Sempre use `name=` em todo `client.get/post/...` |
| Usar `assert` em vez de `catch_response` | Use `with client.get(..., catch_response=True) as r:` |
| Esquecer `self.interrupt()` no SequentialTaskSet | OBRIGATÓRIO no final do fluxo ou o loop trava |
| Hardcode de URLs e credenciais | Use `os.getenv()` — nunca hardcode secrets |
| Sem think time (`wait_time`) | Adicione `between(1, 3)` para simular comportamento real |
| Single locustfile monolítico | Separe por tipo: smoke, load, stress, soak |
| Sem validação de response | Use `catch_response=True` e valide campos de negócio |
| Não setar exit code no CI | Use `@events.quitting` para setar `process_exit_code = 1` |
| Testar em produção | SEMPRE use staging ou ambiente dedicado de testes |
| Ignorar percentis altos (p95, p99) | Monitore p95 e p99 — avg esconde outliers críticos |

## Best Practices Checklist

- [ ] Locustfiles versionados junto ao código da aplicação
- [ ] `BASE_URL` e credenciais exclusivamente via variáveis de ambiente
- [ ] Arquivos separados por tipo de teste (smoke / load / stress / soak)
- [ ] `on_start()` faz autenticação; token injetado nos headers do client
- [ ] Toda request com `name=` para agrupamento correto de métricas
- [ ] `catch_response=True` para validação semântica de responses
- [ ] `wait_time = between(...)` simulando think time real
- [ ] `LoadTestShape` para cenários com ramp/spike programáticos
- [ ] `@events.quitting` setando `process_exit_code` para falha em CI
- [ ] Relatório HTML gerado (`--html`) e publicado como artefato de CI
- [ ] Testes de stress identificam ponto de saturação (response time explode)
- [ ] Docker Compose configurado para modo distribuído em testes de alta carga
