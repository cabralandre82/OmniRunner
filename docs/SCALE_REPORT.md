# SCALE REPORT — Teste de Escala a 10.000 Assessorias

**Data:** 2026-03-04  
**Autor:** Principal SRE — Scale Testing  
**Repositório:** `/home/usuario/project-running`  
**Escopo:** Monorepo completo (Flutter App + Next.js Portal + Supabase Backend)

---

## Resumo Executivo

Simulação de escala a **10.000 assessorias**, **800.000 atletas** e **30.000 staff** revelou que o sistema atual **quebra a partir de ~300 grupos** em pelo menos 5 pontos críticos, e atinge **degradação severa a ~2.000 grupos**.

| Métrica | Valor |
|---------|-------|
| **Limite real atual** | ~300–500 grupos (antes do primeiro timeout crítico) |
| **Limite com P0 fixes (indexes + cron rewrite)** | ~3.000–5.000 grupos |
| **Limite com P0+P1 (architecture changes)** | ~10.000 grupos |
| **Problemas encontrados** | **47** (12 CRITICAL, 18 HIGH, 12 MEDIUM, 5 LOW) |
| **Esforço total estimado** | ~120h de engenharia |

### Score por Camada

| Camada | Score (0-100) | Status |
|--------|---------------|--------|
| Banco de Dados | **35/100** | Indexes críticos ausentes, crons quebram, WAL excessivo |
| Edge Functions | **25/100** | 5 funções timeout < 5% da escala alvo |
| Frontend (Flutter) | **55/100** | Queries duplicadas, sem cache, listas unbounded |
| Frontend (Portal) | **40/100** | Full table scans, truncação silenciosa, 6 queries por navegação |

---

## Documentos Gerados

| Documento | Conteúdo |
|-----------|----------|
| `SCALE_DATABASE.md` | Schema, indexes, RLS, queries, WAL, particionamento, connection pool |
| `SCALE_EDGE.md` | 57 edge functions analisadas, timeouts, cold starts, cascading failures |
| `SCALE_FRONTEND.md` | 100 screens Flutter + 53 pages Portal, queries, memória, duplicatas |

---

## Modelo de Simulação

### Dataset

| Entidade | Quantidade |
|----------|-----------|
| Assessorias (coaching_groups) | 10.000 |
| Admin masters | 10.000 |
| Coaches | 20.000 |
| Assistentes | 30.000 |
| Atletas | 800.000 |
| **Total de usuários** | **860.000** |

### Volumes de Dados Estimados

| Tabela | Rows (10K groups) | Armazenamento |
|--------|-------------------|---------------|
| `coaching_athlete_kpis_daily` | **292M** | ~55 GB |
| `notification_log` | **160M** | ~18 GB |
| `coin_ledger` | **104M** | ~15 GB |
| `sessions` | **50M** | ~19 GB |
| `leaderboard_entries` | **50M** | ~9.5 GB |
| `coaching_workout_assignments` | **40M** | ~6 GB |
| `product_events` | **80M** | ~14 GB |
| **Total (c/ indexes)** | | **~200–250 GB** |

### Operações Diárias Estimadas

| Operação | Volume/dia | Tipo |
|----------|-----------|------|
| Strava webhooks | 200.000 | Event-driven |
| User API calls (app) | 10M | Leitura/Escrita |
| Staff portal loads | 150.000 | Leitura |
| Cron executions | ~300 | Background |
| Payment webhooks | ~700 | Event-driven |
| **WAL gerado/dia** | **~2.5–3.5 GB** | |

---

## Problemas Encontrados — CRITICAL (12)

### Banco de Dados (6 CRITICAL)

| # | Problema | Ponto de Quebra | Impacto |
|---|----------|-----------------|---------|
| DB-1 | **`coaching_members` sem index `(user_id, group_id)`** — TODA query RLS faz seq scan em 850K rows | Degradação a partir de 500 grupos | Toda operação autenticada fica 100x mais lenta |
| DB-2 | **`compute_coaching_kpis_daily` — single transaction em 50M rows** — cron daily roda 20-45min | Timeout a 2K grupos | KPIs param de ser calculados |
| DB-3 | **`inactivity_nudge` transfere 4M+ rows para Edge Function** | OOM a 50K users (6% da escala) | Edge function crasha, notificações perdidas |
| DB-4 | **Leaderboard DELETE+INSERT gera 650 MB WAL/semana** | Replication lag a 5K grupos | Read replicas atrasadas, checkpoints pesados |
| DB-5 | **`coin_ledger` sem index `(ref_id, reason)`** — settle-challenge faz seq scan em 104M rows | Timeout a 1K desafios acumulados | Desafios não são liquidados |
| DB-6 | **`notification_log` sem cleanup (160M rows unbounded)** | Degradação contínua | Disco cheio, queries cada vez mais lentas |

### Edge Functions (4 CRITICAL)

| # | Problema | Ponto de Quebra | Impacto |
|---|----------|-----------------|---------|
| EF-1 | **`auto-topup-cron` — loop serial com 200ms delay** | Timeout a **300 grupos** (3% da escala) | Assessorias sem auto-recarga; perda de receita |
| EF-2 | **`league-snapshot` — 4 queries × N grupos seriais** | Timeout a **50 grupos** (0.5%) | Ligas nunca atualizadas |
| EF-3 | **Strava API rate limit: 1.000 req/dia vs 400K necessários** | Limite atingido a **3% da escala** | 97% das atividades Strava perdidas permanentemente |
| EF-4 | **`lifecycle-cron` — fan-out serial para settle/snapshot/notify** | Timeout com **>4 desafios simultâneos** | Desafios e ligas acumulam backlog |

### Frontend (2 CRITICAL)

| # | Problema | Ponto de Quebra | Impacto |
|---|----------|-----------------|---------|
| FE-1 | **Portal Athletes page — ALL sessions sem limit nem filtro** | Timeout a 200+ atletas/grupo | Página não carrega |
| FE-2 | **Portal Engagement — `limit(1000)` trunca dados silenciosamente** | Dados errados a >33 atletas/grupo | Scores de engagement incorretos sem aviso |

---

## Problemas Encontrados — HIGH (18)

### Banco de Dados

| # | Problema | Fix |
|---|----------|-----|
| DB-7 | `sessions` sem partial index `(status, is_verified, start_time_ms)` para KPI cron | Index migration |
| DB-8 | `strava_connections` sem index `(strava_athlete_id)` — webhook lookup em seq scan | Index migration |
| DB-9 | `sessions` sem index `(strava_activity_id)` — dedup check em seq scan | Index migration |
| DB-10 | RLS policies encadeadas (`workout_blocks → templates → members`) atingem 20-50ms/row | Rewrite RLS com `auth.user_group_roles()` |
| DB-11 | `wallets` row — hot update contention em settlement bursts (500 UPDATEs simultâneos) | Batch RPC para wallet |
| DB-12 | Supabase Pro plan: 200 connections, necessário ~180 em pico | Upgrade para Team/Enterprise |

### Edge Functions

| # | Problema | Fix |
|---|----------|-----|
| EF-5 | `strava-webhook` — sem retry, atividades perdidas permanentemente | Queue + retry table |
| EF-6 | `send-push` — loop serial por token, timeout com 1000+ tokens | FCM batch API (500/request) |
| EF-7 | `settle-challenge` — N RPCs paralelos `increment_wallet_balance` | Batch RPC única |
| EF-8 | `clearing-cron` — queries unbounded em `coin_ledger` (104M rows) | Limit + cursor pagination |
| EF-9 | `compute-leaderboard` batch_assessoria — loop serial 10K grupos | Elapsed-time guard + cursor |
| EF-10 | `strava-webhook` carrega tabela `parks` inteira na memória | PostGIS spatial query |
| EF-11 | `notify-rules` — 1.229 linhas, monolito avaliando 15 regras serialmente | Split em funções individuais |

### Frontend

| # | Problema | Fix |
|---|----------|-----|
| FE-3 | `coin_ledger` limit(10000) no Portal para SUM client-side | RPC `SUM(delta_coins)` |
| FE-4 | Clearing/Swap/Audit carregam ALL 10K `coaching_groups` | Filter por IDs referenciados |
| FE-5 | Portal Layout: 6 queries em TODA navegação | Cache server-side 5min |
| FE-6 | StaffDashboard: 8 queries sequenciais + sync serial de membros | `Future.wait()` + batch Isar |
| FE-7 | TodayScreen: 7 queries re-executadas em cada tab switch | TTL guard de 60s |

---

## Problemas Encontrados — MEDIUM (12)

| # | Problema | Camada |
|---|----------|--------|
| M-1 | `coaching_athlete_kpis_daily` sem particionamento (292M rows) | DB |
| M-2 | `api_rate_limits` cleanup com DELETE em 100M rows (WAL churn) | DB |
| M-3 | `eval-verification-cron` — 100 RPCs seriais | EF |
| M-4 | `generate-wrapped` — carrega histórico completo de sessões | EF |
| M-5 | `requireUser()` cria 3 clientes Supabase por chamada | EF |
| M-6 | Isar: sessões incluem GPS route data (1000+ points/sessão) | App |
| M-7 | WalletBloc carrega ledger inteiro sem paginação | App |
| M-8 | CRM page limitada a 100 atletas sem indicação | Portal |
| M-9 | Dashboard sessions: todas colunas de todos atletas em 2 semanas | Portal |
| M-10 | Attendance page chama `getAttendanceData()` 2x | Portal |
| M-11 | Zero real-time subscriptions — tudo polling/refresh | App/Portal |
| M-12 | `select()` sem colunas em 7 screens Flutter | App |

---

## Problemas Encontrados — LOW (5)

| # | Problema | Camada |
|---|----------|--------|
| L-1 | CachedAvatar sem limite de cache size | App |
| L-2 | Strava connection status checado por 3 screens independentes | App |
| L-3 | Morning burst: 30K staff abrindo dashboards simultaneamente | App/Portal |
| L-4 | `trainingpeaks-sync/oauth` inicializam módulos no scope global | EF |
| L-5 | `park_activities` sem UNIQUE constraint para dedup | DB |

---

## Análise de Carga — Cenários

### Cenário 1: Pico de Uso (Domingo 8h — corrida popular)

```
Strava webhooks:     50+ RPS (burst)
Staff dashboards:    2.000 concurrent
Athlete app opens:   5.000 concurrent
Challenge polling:   ~67 queries/sec

Resultado:
├─ PostgREST pool: 150-250% utilização → requests enfileirados
├─ strava-webhook: Strava API rate-limited em 100 req/15min
├─ DB connections: ~180 concurrent (Pro limit: 200) → borderline
└─ Latência média: 500ms-2s (vs normal 50-200ms)
```

### Cenário 2: Uso Médio (Dia útil, 14h)

```
Strava webhooks:     ~2 RPS
Staff dashboards:    500 concurrent
Athlete app opens:   2.000 concurrent

Resultado:
├─ PostgREST pool: ~50% → OK
├─ DB connections: ~80 → OK
├─ Latência média: 100-300ms (aceitável sem index fixes)
└─ Bottleneck: RLS overhead em coaching_members (8ms/row)
```

### Cenário 3: Carga Contínua (Crons overlapping — diário 2h UTC)

```
compute_coaching_kpis_daily:    Running (20-45min)
clearing-cron:                  Running (30-60s)
eval-verification-cron:         Running (20-40s)
lifecycle-cron:                 Running (timeout <60s)
notify-rules (all rules):      Running (timeout 45-90s)

Resultado:
├─ KPI cron: single transaction locks temp tables por 20-45min
├─ lifecycle-cron: processa 3-4 desafios, timeout, 200+ não processados
├─ notify-rules: inactivity_nudge OOM a 50K users
├─ 5+ edge functions competem por connections simultaneamente
└─ WAL: 1.5-2 GB gerado em janela de 2h
```

---

## Matriz de Risco por Escala

```
Escala          300    1K     2K      5K      10K
                │      │      │       │       │
auto-topup      ██████ BREAKS
league-snapshot ███ BREAKS
strava-rate     ████████████ BREAKS
lifecycle-cron  ████████ BREAKS
notify-inactiv  ████████████████████ BREAKS
coaching_member ░░░░░░ ██████ DEGRADED  ████████████ UNUSABLE
KPI cron        ░░░░░░░░░░░░ ████████ TIMEOUT     ████████ BROKEN
leaderboard WAL ░░░░░░░░░░░░░░░░░░░░ ██████████ REPL LAG
portal athletes ░░░░░░░░░░░░░░░░ ██████████████ TIMEOUT
conn pool       ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ██████ EXHAUSTED

░ = OK    █ = Degraded    BREAKS/BROKEN = Failure
```

---

## Plano de Correção Recomendado

### Sprint 1 — Indexes Zero-Risk (2 dias, desbloqueiam 500→3K)

| # | Ação | Esforço | Impacto |
|---|------|---------|---------|
| 1 | `CREATE INDEX (user_id, group_id) INCLUDE (role)` em `coaching_members` | 1 migration | **10-100x melhoria em TODA query autenticada** |
| 2 | `CREATE INDEX (group_id, role)` em `coaching_members` | 1 migration | KPI cron 5x mais rápido |
| 3 | `CREATE INDEX (status, is_verified, start_time_ms)` partial em `sessions` | 1 migration | KPI temp table creation: 50M scan → range scan |
| 4 | `CREATE INDEX (ref_id, reason)` em `coin_ledger` | 1 migration | settle-challenge: 104M scan → index lookup |
| 5 | `CREATE INDEX (strava_athlete_id)` em `strava_connections` | 1 migration | Webhook lookup: O(N) → O(1) |
| 6 | `CREATE INDEX (strava_activity_id)` partial em `sessions` | 1 migration | Dedup check: O(N) → O(1) |

### Sprint 2 — Cron Rewrites (3-4 dias, desbloqueiam 3K→5K)

| # | Ação | Esforço | Impacto |
|---|------|---------|---------|
| 7 | Rewrite `auto-topup-cron` → database-driven queue | Alto | 300 → 10K+ grupos |
| 8 | Rewrite `league-snapshot` → single SQL aggregation | Médio | 50 → 10K+ grupos |
| 9 | Rewrite `lifecycle-cron` → fan-out dispatcher + worker | Alto | 4 → 200+ desafios/tick |
| 10 | Rewrite `inactivity_nudge` → SQL set-difference | Médio | 50K → 800K users |
| 11 | Batch `compute_coaching_kpis_daily` por chunks de 100 grupos | Alto | 2K → 10K grupos |

### Sprint 3 — Frontend + Portal (3-4 dias)

| # | Ação | Esforço | Impacto |
|---|------|---------|---------|
| 12 | Portal Athletes page: aggregate RPC ao invés de ALL sessions | 2h | Página funcional a qualquer escala |
| 13 | Portal Engagement: remover limit(1000), usar aggregate | 3h | Dados corretos |
| 14 | Portal Layout: cache de 5min para metadata | 4h | 6 queries/navegação → 0 (cache hit) |
| 15 | Clearing/Swap/Audit: filter `coaching_groups` por IDs usados | 3h | 10K rows → ~50 rows |
| 16 | StaffDashboard: `Future.wait()` + batch Isar | 2h | 8 queries sequenciais → paralelas |
| 17 | TodayScreen: TTL guard de 60s | 30min | 7 queries/tab switch → 0 |

### Sprint 4 — Strava + Architecture (5-7 dias)

| # | Ação | Esforço | Impacto |
|---|------|---------|---------|
| 18 | Strava webhook queue + rate limiter | Alto | API rate limit respeitado |
| 19 | Strava failed events retry table | Médio | Zero atividades perdidas |
| 20 | RLS → `auth.user_group_roles()` materialized function | Alto | 10-100x em queries multi-row |
| 21 | Leaderboard: `INSERT ON CONFLICT DO UPDATE` | Médio | 650 MB WAL/semana → 10 MB |
| 22 | Particionamento: `coaching_athlete_kpis_daily` por mês | Alto | Writes em 800K rows vs 292M |

### Sprint 5 — Infrastructure (2-3 dias)

| # | Ação | Esforço | Impacto |
|---|------|---------|---------|
| 23 | Upgrade Supabase para Team/Enterprise (pool 400-800+) | Infra | Connection exhaustion prevenido |
| 24 | Add read replica para Portal analytics | Infra | Offload primary |
| 25 | `notification_log` particionamento + TTL drop | Médio | 160M → ~30M rows |
| 26 | `api_rate_limits` particionamento + DROP partition | Baixo | DELETE WAL → zero |
| 27 | `pg_stat_statements` monitoring + alertas | Baixo | Visibilidade de regressões |

---

## Resumo de Impacto

### Antes das Correções

| Escala | Status |
|--------|--------|
| 100 grupos | Funcional |
| 300 grupos | `auto-topup-cron` e `league-snapshot` quebram |
| 500 grupos | RLS overhead torna queries 10x mais lentas |
| 2K grupos | KPI cron timeout, Portal Athletes timeout |
| 5K grupos | Connection pool esgotado, WAL replication lag |
| 10K grupos | **Sistema inoperável** |

### Depois das Correções (Sprint 1-4)

| Escala | Status |
|--------|--------|
| 1K grupos | Fluido |
| 5K grupos | Funcional (Team plan) |
| 10K grupos | Funcional (Enterprise plan) |
| 50K grupos | Requer particionamento adicional + sharding |

---

## Conclusão

O sistema tem uma **base arquitetural sólida** (RLS consistente, feature flags, idempotência financeira), mas foi projetado para **~100-500 grupos**. Para atingir 10K:

1. **Semana 1**: 6 migrations de indexes (zero risco) removem o bottleneck #1
2. **Semana 2-3**: Rewrite de 5 crons serializa o salto de 300→5K
3. **Semana 3-4**: Frontend fixes e Strava queue habilitam 5K→10K
4. **Semana 5+**: Particionamento e infra para sustentabilidade a longo prazo

**Investimento total: ~120h de engenharia, distribuído em 5 sprints.**

O item de maior impacto/menor esforço é **R1** (um único `CREATE INDEX` em `coaching_members`) que melhora **toda operação autenticada** em 10-100x.

---

*Relatório gerado por Scale Testing simulation. Nenhum arquivo de código foi modificado.*
