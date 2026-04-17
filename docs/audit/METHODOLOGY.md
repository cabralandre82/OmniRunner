# Metodologia — Auditoria 360° Omni Runner

> **Data:** 2026-04-17
> **Duração da execução:** ~1 sessão (exploração + análise em 8 partes)
> **Cobertura:** Portal Next.js (~180 rotas) + App Flutter (~458 arquivos Dart) + ~90 migrations SQL + ~40 Edge Functions + CI/CD + docs

---

## 1. As 23 Lentes

Cada lente representa a perspectiva de um C-level, especialista técnico ou usuário final. Cada achado é atribuído a **uma lente primária** (pode ter cross-refs em `tags`).

| # | Lente | Persona | Foco principal |
|---|---|---|---|
| 1 | **CISO** | Chief Information Security Officer | Superfície de ataque, autenticação, autorização, CSP, rate limiting, secrets |
| 2 | **CTO** | Chief Technology Officer | Arquitetura, escalabilidade, dívida técnica, escolhas de stack |
| 3 | **CFO** | Chief Financial Officer | Custódia, clearing, reconciliação, taxas, integridade financeira |
| 4 | **CLO** | Chief Legal Officer | LGPD, consentimento, retenção de dados, contratos, jurisdição |
| 5 | **CPO** | Chief Product Officer | Product-market fit, priorização, discovery, feature parity |
| 6 | **COO** | Chief Operating Officer | Runbooks, on-call, incident response, operações do dia-a-dia |
| 7 | **CXO** | Chief Experience Officer | UX, acessibilidade, copywriting, fluxos de erro, onboarding |
| 8 | **CDO** | Chief Data Officer | Data warehouse, analytics, event tracking, governança de dados |
| 9 | **CRO** | Chief Risk Officer | Fraude, anti-cheat, AML/KYC, risco operacional |
| 10 | **CSO** | Chief Security Officer (Supply Chain) | Dependências, SBOM, gitleaks, Dependabot |
| 11 | **Supply Chain** | — | Builds reprodutíveis, lockfiles, provenance |
| 12 | **Cron/Scheduler** | — | `pg_cron`, `pg_net`, jobs programados, idempotência |
| 13 | **Middleware** | — | Edge middleware Next.js, headers, rewrites, i18n |
| 14 | **Contracts** | — | Schemas públicos, API versioning, OpenAPI, backwards-compat |
| 15 | **CMO** | Chief Marketing Officer | SEO, Open Graph, deep links, growth loops |
| 16 | **CAO** | Chief Accessibility Officer | WCAG, leitores de tela, contraste, navegação por teclado |
| 17 | **VP Engineering** | — | Code review, quality gates, testes, CI/CD |
| 18 | **Principal Engineer** | — | Design patterns, primitives, idiomas internos |
| 19 | **DBA** | Database Administrator | Índices, query plans, bloat, migrations, RLS |
| 20 | **SRE** | Site Reliability Engineer | SLO, SLI, alertas, observabilidade, runbooks automáticos |
| 21 | **Atleta Profissional** | — | Precisão GPS, métricas avançadas (TSS/CTL/ATL), anti-cheat justo, zonas customizáveis |
| 22 | **Atleta Amador** | — | Onboarding, clareza de conceitos (OmniCoin), gamificação acessível |
| 23 | **Treinador** | — | Bulk assign, dashboards priorizados, comunicação inline, insights acionáveis |

---

## 2. Processo

1. **Exploração** — inventário de arquivos críticos (middleware, rotas de API, Edge Functions, migrations, libs financeiras, telas do app).
2. **Análise por lente** — cada lente produz 10–60 achados; para cada um:
   - Evidência (arquivo:linha ou migration:ID).
   - Impacto concreto (quem é afetado, como).
   - Severidade.
   - Correção proposta.
3. **Cross-checking** — achados duplicados entre lentes são consolidados e marcados com `tags` múltiplas.
4. **Priorização** — distribuição em 4 ondas (ver `ROADMAP.md`).

---

## 3. Critérios de severidade (detalhado)

### 🔴 Critical
- Perda financeira direta potencial (ex: saldo negativo, double-spend).
- Exposição de PII sem controle de acesso (CPF, geolocalização histórica de atletas).
- Bypass de autenticação ou escalada de privilégios.
- Falha que bloqueia totalmente o produto em produção.
- Inconsistência de dados em tabelas financeiras (clearing, custody).
- Violação LGPD de alta gravidade (Art. 46, 48).

### 🟠 High
- UX degradado ao ponto de afetar retenção.
- Falha de anti-fraude que permite ganho injusto (ex: teletransporte não detectado).
- Ausência de idempotência em operações financeiras médias.
- Migrations frágeis que quebram em produção com certas combinações de dados.
- Observabilidade insuficiente para detectar incidentes em < 15min.

### 🟡 Medium
- Débito técnico sem impacto produtivo imediato.
- Documentação desatualizada.
- Testes de regressão ausentes para caminhos felizes secundários.
- Micro-otimizações de performance.
- Inconsistências de estilo/copy.

---

## 4. ID Scheme

Cada finding tem dois identificadores:

- **`audit_ref`**: formato `X.Y` onde `X` é o número da lente, `Y` é o sequencial — **usado nos relatórios originais** (`parts/`).
  - Exemplo: `2.1` = Lente 2 (CTO), item 1.
- **`id`**: formato `LXX-YY` (zero-padded), **usado no nome de arquivo e GitHub Issues**.
  - Exemplo: `L02-01` ↔ `audit_ref: "2.1"`.

O mapeamento é 1-a-1. Issues no GitHub usam label `audit:L02-01`.

---

## 5. Frontmatter YAML Schema

Veja `findings/_template.md` para o schema completo com comentários. Campos obrigatórios:

- `id` (string) — ex: `L02-01`
- `audit_ref` (string) — ex: `2.1`
- `lens` (integer 1-23)
- `title` (string)
- `severity` (`critical | high | medium | safe | na`)
- `status` (`fix-pending | in-progress | fixed | wont-fix | deferred | duplicate | not-reproducible`)
- `wave` (integer 0-3)
- `discovered_at` (ISO date)

Opcionais mas recomendados:

- `files[]` — paths afetados
- `tags[]` — cross-cutting concerns (ex: `lgpd`, `finance`, `anti-cheat`)
- `correction_type` (`code | config | migration | docs | process | test`)
- `test_required` (boolean)
- `linked_prs[]`, `linked_issues[]`
- `owner` (GitHub handle ou `unassigned`)
- `runbook` — path para runbook derivado

---

## 6. Rastreabilidade & CI

- **Single source of truth**: `findings/*.md`.
- **Gerados**: `registry.json`, `FINDINGS.md`, `SCORECARD.md` via `tools/audit/build-registry.ts`.
- **Validação CI**: `tools/audit/verify.ts`:
  - Todo finding com `status: fixed` exige ao menos um item em `linked_prs[]` **ou** `linked_issues[]`.
  - Todo finding com `test_required: true` e `status: fixed` exige caminho de teste em `tests[]`.
  - `id` único e coerente com nome do arquivo.
  - Frontmatter YAML válido.

---

## 7. Limitações desta auditoria

- **Sem acesso a dados de produção** — achados de performance são baseados em análise estática de queries + tamanho de tabela estimado.
- **Sem pentest ativo** — achados de CISO são "code review" + análise de superfície; não há PoCs executados.
- **Snapshot em tempo** — achados refletem o estado do repo em 2026-04-17. Migrations aplicadas após essa data podem invalidar achados; `verify.ts` detecta drift.
- **Personas sintéticas** — Lentes 21–23 baseadas em literatura de training science + análise do código; não houve entrevista com usuários reais nesta rodada.
