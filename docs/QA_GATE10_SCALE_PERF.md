# GATE 10 — Performance & Scale

**Data**: 2026-03-03  
**Revisor**: CTO / Lead QA  
**Método**: Auditoria de índices SQL, padrões de query, paginação, e ferramentas de benchmark

---

## 10.1 Index Audit

### Total de Índices
- **143+ indexes** across 43 migration files
- Todas as tabelas de coaching possuem índices compostos para as queries mais comuns

### Índices por Domínio

#### Core (full_schema — 23 indexes)
| Índice | Tabela | Colunas |
|--------|--------|---------|
| idx_profiles_display_name | profiles | display_name |
| idx_sessions_user | sessions | user_id, start_time_ms DESC |
| idx_sessions_status | sessions | user_id, status |
| idx_sessions_verified | sessions | user_id WHERE is_verified=true |
| idx_badge_awards_user | badge_awards | user_id, unlocked_at_ms DESC |
| idx_xp_tx_user | xp_transactions | user_id, created_at_ms DESC |
| idx_ledger_user | coin_ledger | user_id, created_at_ms DESC |
| idx_mission_progress_user | mission_progress | user_id, status |
| idx_friendships_a/b | friendships | user_id_a/b, status |
| idx_groups_privacy | groups | privacy WHERE privacy != 'secret' |
| idx_group_members_user/group | group_members | user_id/group_id, status |
| idx_group_goals | group_goals | group_id, status |
| idx_challenges_creator/status | challenges | creator_user_id/status |
| idx_challenge_parts_user | challenge_participants | user_id, status |
| idx_leaderboards_scope | leaderboards | scope, period, metric, period_key |
| idx_events_status | events | status, starts_at_ms |
| idx_coaching_members_user/group | coaching_members | user_id / group_id, role |
| idx_race_events_group | race_events | group_id, status |

#### Portal Performance (10 indexes dedicados)
| Índice | Tabela | Query Pattern |
|--------|--------|---------------|
| idx_sessions_user_start | sessions | Dashboard: sessions by user + time |
| idx_kpis_daily_group_day | coaching_kpis_daily | Dashboard: KPIs trend |
| idx_athlete_kpis_daily_group_day | coaching_athlete_kpis_daily | Engagement: athlete KPIs |
| idx_athlete_kpis_daily_group_user_day | coaching_athlete_kpis_daily | CRM: individual athlete KPI |
| idx_alerts_group_resolved | coaching_alerts | Risk: unresolved alerts |
| idx_alerts_group_user | coaching_alerts | Risk: alerts per athlete |
| idx_attendance_group_checked | coaching_training_attendance | Attendance: recent check-ins |
| idx_attendance_session_status | coaching_training_attendance | Attendance: by session |
| idx_announcement_reads_ann_user | coaching_announcement_reads | Announcements: read status |
| idx_member_status_group_status | coaching_member_status | CRM: status filter |

#### Training & Attendance (4 indexes)
| Índice | Query Pattern |
|--------|---------------|
| idx_training_sessions_group_starts | List sessions by date |
| idx_training_sessions_group_status_starts | Filter by status + date |
| idx_attendance_group_session | Attendance per session |
| idx_attendance_group_athlete_time | Attendance per athlete over time |

#### CRM (5 indexes)
| Índice | Query Pattern |
|--------|---------------|
| idx_tags_group | List tags for a group |
| idx_athlete_tags_group_athlete | Tags for specific athlete |
| idx_athlete_tags_tag | Athletes with a specific tag |
| idx_athlete_notes_group_athlete_time | Notes timeline |
| idx_member_status_group | Status overview |

#### Workout Builder (4 indexes)
| Índice | Query Pattern |
|--------|---------------|
| idx_workout_templates_group | Templates by group |
| idx_workout_blocks_template | Blocks by template |
| idx_workout_assignments_group_date | Assignments by date |
| idx_workout_assignments_athlete | Assignments for athlete |

#### Financial Engine (5 indexes)
| Índice | Query Pattern |
|--------|---------------|
| idx_plans_group | Plans by group |
| idx_subscriptions_group | Subscriptions by group |
| idx_subscriptions_athlete | Subscriptions by athlete |
| idx_ledger_group_date | Ledger by date (financial page) |
| idx_ledger_group_type | Ledger by type (revenue/expense) |

#### Wearables (4 indexes)
| Índice | Query Pattern |
|--------|---------------|
| uq_execution_athlete_provider_activity | Dedup constraint |
| idx_device_links_athlete | Devices for athlete |
| idx_executions_group_athlete | Executions by group+athlete |
| idx_executions_assignment | Executions linked to workout |

#### TrainingPeaks (2 indexes)
| Índice | Query Pattern |
|--------|---------------|
| idx_tp_sync_group_status | Sync status overview |
| idx_tp_sync_athlete | Sync status per athlete |

### Hot Query Coverage

| Hot Query | Index Exists | Status |
|-----------|-------------|--------|
| Dashboard KPIs (group_id, day DESC) | ✅ idx_kpis_daily_group_day | ✅ |
| CRM members list (group_id, role) | ✅ idx_coaching_members_group | ✅ |
| CRM with status filter (group_id, status) | ✅ idx_member_status_group_status | ✅ |
| Attendance by session (session_id, status) | ✅ idx_attendance_session_status | ✅ |
| Alerts unresolved (group_id, resolved, day) | ✅ idx_alerts_group_resolved | ✅ |
| Workout assignments (group_id, date) | ✅ idx_workout_assignments_group_date | ✅ |
| Financial ledger (group_id, date) | ✅ idx_ledger_group_date | ✅ |
| Announcements (group_id, pinned, created_at) | ✅ idx_announcements_group_pinned | ✅ |
| Athlete KPIs trend (group_id, day) | ✅ idx_athlete_kpis_daily_group_day | ✅ |
| Subscriptions (group_id) | ✅ idx_subscriptions_group | ✅ |

**Resultado**: ✅ Todos os hot queries possuem índices dedicados.

---

## 10.2 Pagination Audit

### Portal Pages with Pagination

| Página | `.range()` / `.limit()` | Status |
|--------|------------------------|--------|
| /crm | ✅ | Paginated |
| /workouts | ✅ | Paginated |
| /announcements | ✅ | Paginated |
| /engagement | ✅ | Paginated |
| /risk | ✅ | Paginated |
| /executions | ✅ | Paginated |
| /communications | ✅ | Paginated |
| /clearing | ✅ | Paginated (3 queries) |
| /fx | ✅ | Paginated |
| /swap | ✅ | Paginated |
| /custody | ✅ | Paginated (4 queries) |
| /audit | ✅ | Paginated |
| /credits | ✅ | Paginated |
| /billing | ✅ | Paginated |
| /distributions | ✅ | Paginated |
| /workouts/assignments | ✅ | Paginated |

### Portal Pages WITHOUT Pagination

| Página | Justificativa | Risco |
|--------|---------------|-------|
| /dashboard | Aggregated KPIs, not a list | ✅ OK |
| /athletes | Loads all athletes in group | ⚠️ Medium |
| /financial | Aggregated KPIs + recent ledger | ⚠️ Low |
| /attendance | Filters by date range (30d default) | ✅ OK |
| /settings | Single group settings | ✅ OK |
| /verification | Single athlete status | ✅ OK |
| /attendance-analytics | Aggregated analytics | ✅ OK |
| /trainingpeaks | Sync status per athlete | ⚠️ Low |
| /exports | Download triggers | ✅ OK |
| /badges | Badge definitions | ✅ OK |

**Findings**:
- ⚠️ P2: `/athletes` carrega todos os atletas sem paginação. Para grupos com 500+ atletas pode ser lento. Mitigação: grupos típicos têm 20-50 atletas.
- ⚠️ P3: `/financial` sem limit na query de ledger — mitigação: filtra por mês corrente.

**Resultado**: ⚠️ PASS com notas — 16/25 páginas com paginação explícita. Páginas sem paginação são aggregações ou têm filtros de data que limitam volume.

---

## 10.3 Query Patterns (N+1 Audit)

### Portal — Parallel Queries (Promise.all)
20 páginas usam `Promise.all` para queries paralelas:
- `/dashboard` — 3+ parallel queries ✅
- `/athletes` — parallel: members + verification + sessions ✅
- `/crm` — parallel: members + status + tags ✅
- `/financial` — parallel: ledger + subscriptions + prev month ✅
- `/engagement` — parallel: KPIs + athlete KPIs ✅
- `/risk` — parallel: alerts + athlete KPIs ✅
- `/clearing` — parallel: weeks + cases + items ✅

### Potential N+1 Patterns

| Página | Pattern | Status |
|--------|---------|--------|
| /athletes | Loads members, then maps verification + sessions | ⚠️ Sequential map, but uses batch queries per type |
| /crm/[userId] | Loads athlete profile, then parallel data | ✅ Promise.all for detail data |
| /attendance | Loads sessions, then attendance in batch | ✅ Uses `.in()` for batch |

**N+1 Analysis**: Nenhum N+1 clássico (query-per-row) encontrado. O pattern de `/athletes` faz batch queries por tipo de dado (não por atleta), o que é aceitável.

### Flutter — BLoC Pattern
- BLoCs fazem single repository calls que executam queries atômicas
- Sem N+1 patterns identificados nos repositories

**Resultado**: ✅ PASS — Nenhum N+1 pattern identificado.

---

## 10.4 Compute SLA

### compute_coaching_kpis_daily

**O que faz**:
1. Cria temp table com sessions de 30 dias (JOIN sessions × coaching_members)
2. Computa por grupo: total_members, DAU/WAU/MAU, sessions/distance, retention WoW, attendance rate
3. UPSERT em coaching_kpis_daily

**Complexidade**: O(groups × athletes) para a temp table, O(groups) para o INSERT

**Performance esperada**:
| Volume | Estimativa |
|--------|-----------|
| 10 groups × 20 athletes | < 100ms |
| 100 groups × 50 athletes | < 2s |
| 500 groups × 100 athletes | < 15s |
| 1000 groups × 200 athletes | < 60s |

**Otimizações aplicadas**:
- Temp table com index (group_id, start_time_ms) — evita re-scan
- LATERAL JOINs para aggregações por grupo
- ON CONFLICT DO UPDATE — idempotente
- SECURITY DEFINER + search_path hardened

### compute_coaching_alerts_daily

**O que faz**:
1. Gera alerts a partir de athlete KPIs (high risk, medium risk, inactive 7/14/30d)
2. Gera alerts de missed_trainings_14d
3. ON CONFLICT DO NOTHING — dedup

**Complexidade**: O(athletes) per alert type

**Performance esperada**:
| Volume | Estimativa |
|--------|-----------|
| 100 groups × 50 athletes | < 3s |
| 500 groups × 100 athletes | < 20s |

**SLA Target**: Ambas as funções devem completar em < 30s para 500 grupos em produção.

**Cron Schedule**: Executadas via `lifecycle-cron` edge function, tipicamente 1x/dia (madrugada).

---

## 10.5 Performance Tools

### tools/perf_seed.ts
- **Objetivo**: Seed do banco com volume realista
- **Volume**: 100 groups × 22 users = ~100k+ rows
- **Dados gerados**:
  - 100 groups com 20 athletes + 1 coach + 1 admin
  - 50 training sessions/group × 15 attendances avg
  - 30 dias de KPI snapshots/group
  - 3 workout templates × 5 blocks × 100 assignments/group
  - 10 announcements/group com 50% read rate
  - 5 tags/group com 3 tags/athlete
  - 1 plan × 20 subscriptions × 100 ledger entries/group
- **Cleanup**: `--cleanup` flag para remover seed data
- **Concurrency**: 40 auth users em paralelo, batch size 500

### tools/perf_benchmark.sql
- **12 benchmark queries** com `EXPLAIN ANALYZE`
- Queries cobertas:
  1. KPIs daily (single group, 30 days)
  2. Members with status (CRM)
  3. Sessions with attendance count (30 days)
  4. Unresolved alerts
  5. Workout assignments (30 days)
  6. Announcements with read status
  7. Financial ledger (30 days)
  8. Active athletes per group (cross-group)
  9. Subscriptions with plan info
  10. Full CRM with tags aggregation
  11. Athlete KPIs (engagement page)
  12. CRM attendance aggregation

### tools/perf_run.sh
- **Pipeline**: Seed → Benchmark → Cleanup prompt
- **Uso**: `bash tools/perf_run.sh`
- Requer `psql` e `tsx` instalados

### Como executar

```bash
# 1. Start local Supabase
supabase start

# 2. Run full performance suite
bash tools/perf_run.sh

# 3. Or run components individually
NODE_PATH=portal/node_modules npx tsx tools/perf_seed.ts
psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -f tools/perf_benchmark.sql
NODE_PATH=portal/node_modules npx tsx tools/perf_seed.ts --cleanup
```

### Acceptance Criteria
- Todas as 12 benchmark queries devem completar em < 100ms com 100 groups
- Index Scan (não Seq Scan) para todas as queries com filtro
- compute_coaching_kpis_daily deve completar em < 5s com seed data

---

### 10.6 Escala de Teste e Extrapolação

#### Seed disponível
O `tools/perf_seed.ts` gera:
| Recurso | Quantidade | Extrapolação 10k |
|---------|------------|------------------|
| Grupos | 100 | 10,000 |
| Membros | 2,200 | 220,000 |
| Sessions de treino | 5,000 | 500,000 |
| Attendance records | 75,000 | 7,500,000 |
| KPIs diários (grupo) | 3,000 | 300,000 |
| KPIs diários (atleta) | 60,000 | 6,000,000 |
| Alerts | 500 | 50,000 |
| Templates | 300 | 30,000 |
| Assignments | 10,000 | 1,000,000 |
| Announcements | 1,000 | 100,000 |
| Ledger entries | 10,000 | 1,000,000 |

#### Por que 100 grupos e não 10k?
- 100 grupos com 100k+ rows é suficiente para validar uso de índices via EXPLAIN ANALYZE
- Queries com índice B-tree escalam O(log n) — se funciona com 100k rows, funciona com 10M
- O SLA real depende do hardware de produção, não do volume do seed local
- **Recomendação**: Rodar `perf_seed.ts` com `NUM_GROUPS=1000` em staging antes do deploy

#### Benchmark esperado (baseado em índices)

| Query | Volume 100 grupos | Expectativa 10k | Índice |
|-------|-------------------|----------------|--------|
| KPIs dashboard (30d) | < 5ms (Index Scan) | < 10ms | idx_kpis_daily_group_day |
| CRM members | < 10ms (Index Scan) | < 20ms | uq_coaching_members_group_user |
| Attendance report | < 15ms (Index Scan + Join) | < 30ms | idx_attendance_group_session |
| Alerts unresolved | < 5ms (Index Scan) | < 10ms | idx_alerts_group_resolved |
| Workout assignments | < 10ms (Index Scan) | < 15ms | idx_workout_assignments_group_date |
| Financial ledger | < 5ms (Index Scan) | < 10ms | idx_ledger_group_date |
| Cross-group compute | < 500ms (Seq Scan expected) | < 5s | Batch-based |

**SLA definido**:
- Queries individuais (por grupo): < 50ms
- Compute batch (D-1, todos grupos): < 30s para 500 grupos, < 5min para 10k (linear scaling via set-based)
- Paginação: todas listas limitadas a 50-200 rows por request

#### Como rodar os benchmarks

```bash
# 1. Iniciar Supabase local
supabase start

# 2. Seed dados de teste
NODE_PATH=portal/node_modules npx tsx tools/perf_seed.ts

# 3. Rodar benchmarks SQL
psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -f tools/perf_benchmark.sql

# 4. Cleanup
NODE_PATH=portal/node_modules npx tsx tools/perf_seed.ts --cleanup
```

---

## Veredito GATE 10: ⚠️ CONDITIONAL PASS

**Findings**:
- P2: `/athletes` page sem paginação (risco em grupos muito grandes)
- P3: `/financial` ledger query sem limit explícito (mitigado por filtro mensal)
- ⚠️ Benchmark de performance precisa ser executado em ambiente similar a produção para validar SLAs

**Condição**: Executar `tools/perf_run.sh` em staging antes do deploy e confirmar que todas as queries usam Index Scan e completam < 100ms.

Nenhum finding P0 ou P1.
