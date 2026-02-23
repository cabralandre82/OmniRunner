# QA Phase 16 — Assessoria Mode (Coaching Intelligence Engine)

> **Data:** 2026-02-17
> **Auditor:** Claude (Automated QA)
> **Escopo:** Todos os artefatos criados nos sprints 16.0.1 – 16.4.6
> **Arquivos analisados:** 26 (domain entities, services, repos, Isar models, BLoCs, screens, Edge Function, SQL migration, contracts)
> **Status:** TODOS OS 12 ACHADOS CORRIGIDOS (sprint 16.9.0-fix)

---

## Resumo Executivo

| Severidade | Achados | Corrigidos |
|------------|---------|------------|
| CRITICAL (PRIV) | 1 | 1 |
| HIGH (FRAUD) | 4 | 4 |
| MEDIUM (INC) | 3 | 3 |
| LOW (PERF) | 4 | 4 |
| **Total** | **12** | **12** |
| PASS checks | 12 | — |

---

## CRITICAL — Privacidade

### PRIV-01: Políticas RLS "service_*" abrem tabelas para TODOS os usuários autenticados

**Arquivo:** `supabase/migrations/20260217_analytics_tables.sql`

Três políticas RLS destinadas ao service_role utilizam `USING (true)` / `WITH CHECK (true)` sem restringir ao papel `service_role`:

```sql
-- athlete_baselines
CREATE POLICY "service_upserts_baselines" ON public.athlete_baselines
  FOR ALL USING (true) WITH CHECK (true);

-- athlete_trends
CREATE POLICY "service_upserts_trends" ON public.athlete_trends
  FOR ALL USING (true) WITH CHECK (true);

-- coach_insights
CREATE POLICY "service_inserts_insights" ON public.coach_insights
  FOR INSERT WITH CHECK (true);
```

**Impacto:** Em Postgres RLS, se QUALQUER política para uma operação permitir acesso, a linha é acessível. Portanto:

- `service_upserts_baselines` com `FOR ALL USING (true)` permite que **qualquer usuário autenticado** faça SELECT, INSERT, UPDATE, DELETE em `athlete_baselines` — anulando completamente a política `baselines_read` (que restringe a coaches e ao próprio atleta).
- Mesmo problema em `athlete_trends` — anula `trends_read`.
- `service_inserts_insights` permite que **qualquer usuário** insira insights falsos em `coach_insights`.

**Causa raiz:** Em Supabase, o `service_role` key já ignora RLS automaticamente. Essas políticas são **desnecessárias** e **danosas**.

**Fix:** Remover as três políticas. O Edge Function (que usa `service_role` key) já bypassa RLS:

```sql
DROP POLICY IF EXISTS "service_upserts_baselines" ON public.athlete_baselines;
DROP POLICY IF EXISTS "service_upserts_trends" ON public.athlete_trends;
DROP POLICY IF EXISTS "service_inserts_insights" ON public.coach_insights;
```

---

## HIGH — Vetores de Fraude

### FRAUD-01: `is_verified` é enviado pelo cliente e trivialmente falsificável

**Arquivo:** `supabase/functions/submit-analytics/index.ts` (L131)

O Edge Function confia no booleano `is_verified` enviado pelo cliente. Um atacante pode submeter dados fabricados (ex: 100 km em 5 min) e definir `is_verified: true` para contornar qualquer validação client-side.

**Fix:** Remover o gate `is_verified` (falsa segurança) ou adicionar validação server-side (velocidade máxima, duração mínima, etc.).

### FRAUD-02: Sem validação de limites em métricas numéricas

**Arquivo:** `supabase/functions/submit-analytics/index.ts` (L135–137)

O Edge Function apenas verifica `distance_m > 0` e `moving_ms > 0`. Não há limites superiores. Um cliente malicioso pode enviar `distance_m: 1_000_000` (1000 km) para envenenar baselines e trends de todo o grupo.

**Fix:** Adicionar sanity checks server-side:

```typescript
if (body.distance_m > 200_000) return error("invalid_session_data", "distance_m > 200km");
if (body.moving_ms < 60_000)  return error("invalid_session_data", "moving_ms < 60s");
const paceMinKm = body.avg_pace_sec_per_km ? body.avg_pace_sec_per_km / 60 : null;
if (paceMinKm != null && (paceMinKm < 1.5 || paceMinKm > 30))
  return error("invalid_session_data", "pace fora do range 1:30–30:00/km");
```

### FRAUD-03: Sem rate limiting por usuário

**Arquivo:** `supabase/functions/submit-analytics/index.ts`

Um usuário malicioso pode enviar muitas sessões fabricadas em curto período para envenenar baselines e gerar insights excessivos para o grupo inteiro.

**Fix:** Adicionar rate limiting (ex: max 10 submissões por usuário por dia via contagem em `analytics_submissions`):

```typescript
const { count } = await adminDb
  .from("analytics_submissions")
  .select("*", { count: "exact", head: true })
  .eq("user_id", body.user_id)
  .gte("processed_at", new Date(Date.now() - MS_PER_DAY).toISOString());
if ((count ?? 0) >= 10) return error("rate_limited", "Max 10 submissions/day");
```

### FRAUD-04: Duplicação de insights a cada submissão

**Arquivo:** `supabase/functions/submit-analytics/index.ts` (L207–244)

Cada submissão de sessão dispara geração de insights para o grupo inteiro. Não há deduplicação — se um atleta permanece inativo, um novo `inactivity_warning` é criado a cada submissão de qualquer membro do grupo. Acúmulo pode poluir o dashboard do coach.

**Fix:** Adicionar verificação de insight existente antes de inserir:

```typescript
const { data: existing } = await adminDb
  .from("coach_insights")
  .select("id")
  .eq("group_id", groupId)
  .eq("target_user_id", userId)
  .eq("type", type)
  .eq("dismissed", false)
  .gte("created_at_ms", nowMs - 7 * MS_PER_DAY)
  .maybeSingle();
if (existing) continue; // skip duplicate
```

---

## MEDIUM — Inconsistências

### INC-01: Insights dispensados aparecem nas views padrão e filtradas por tipo

**Arquivo:** `omni_runner/lib/presentation/blocs/coach_insights/coach_insights_bloc.dart` (L90–119)

`ICoachInsightRepo.getByGroupId()` e `getByGroupAndType()` retornam insights dispensados. O filtro `isActionable` só é aplicado quando **ambos** `_typeFilter` e `_unreadOnly` estão ativos. Na lista padrão, insights dispensados continuam visíveis após o coach tocar "Dispensar".

**Matriz de comportamento atual:**

| typeFilter | unreadOnly | Dismissed visível? |
|------------|------------|-------------------|
| null | false | SIM (bug) |
| set | false | SIM (bug) |
| null | true | NÃO (correto) |
| set | true | NÃO (correto) |

**Fix:** Filtrar `dismissed == false` diretamente nas queries do repo, ou adicionar filtro no BLoC:

```dart
final filtered = all.where((i) => !i.dismissed).toList();
```

### INC-02: Registros DI para `IRaceEventRepo`, `IRaceParticipationRepo`, `IRaceResultRepo` ausentes

**Arquivo:** `omni_runner/lib/core/service_locator.dart` (L559–571)

`RaceEventsBloc` e `RaceEventDetailsBloc` são registrados como factories que referenciam `sl<IRaceEventRepo>()`, `sl<IRaceParticipationRepo>()` e `sl<IRaceResultRepo>()`. Porém, **nenhuma implementação concreta** desses repos foi registrada no service locator. Navegar para telas de eventos de corrida causará `StateError` em runtime.

**Contexto:** As interfaces foram criadas no sprint 16.3.4, mas os Isar implementations estão planejados para sprint futuro. As factories de BLoC foram registradas prematuramente.

**Fix (imediato):** Comentar ou remover os registros de `RaceEventsBloc` e `RaceEventDetailsBloc` até que os repos tenham implementação. Ou registrar stubs `UnimplementedError`-throwing.

### INC-03: Lógica de filtro inconsistente no CoachInsightsBloc

**Arquivo:** `omni_runner/lib/presentation/blocs/coach_insights/coach_insights_bloc.dart` (L90–99)

A lógica de `_fetch` escolhe queries diferentes conforme a combinação de filtros, resultando em comportamento inconsistente:

- `typeFilter != null` → `getByGroupAndType` (não filtra unread/dismissed)
- `typeFilter == null && unreadOnly` → `getUnreadByGroupId` (filtra corretamente)
- `typeFilter != null && unreadOnly` → `getByGroupAndType` + post-filter `isActionable`

A precedência de `_typeFilter` sobre `_unreadOnly` na escolha da query é confusa e causa inconsistência.

**Fix:** Refatorar para compor filtros de forma ortogonal (todos os filtros sempre aplicados).

---

## LOW — Performance

### PERF-01: N+1 queries no RaceEventsBloc

**Arquivo:** `omni_runner/lib/presentation/blocs/race_events/race_events_bloc.dart` (L49–51)

```dart
for (final e in events) {
  counts[e.id] = await _participationRepo.countByEventId(e.id);
}
```

Para N eventos, executa N+1 queries Isar. Aceitável para groups pequenos (Isar é local e rápido), mas escala mal para grupos com muitos eventos.

**Fix futuro:** Adicionar `countByEventIds(Set<String> ids)` batch query ao repo.

### PERF-02: Listas unbounded sem paginação (client-side)

**Arquivos:**
- `isar_coach_insight_repo.dart` → `getByGroupId()`, `getByGroupAndType()` retornam todos os registros
- `i_race_event_repo.dart` → `getByGroupId()` retorna todos os eventos

Nenhum parâmetro `limit`/`offset`. Para grupos muito ativos, pode carregar milhares de registros na memória.

**Nota:** `AnalyticsSyncService` (backend) corretamente implementa paginação (`_defaultLimit=50`, `_maxLimit=200`).

### PERF-03: N+1 writes no Edge Function

**Arquivo:** `supabase/functions/submit-analytics/index.ts` (L179–204, L241–244)

Baselines (6), trends (até 12), e insights são upseridos/inseridos um por vez em loops. Para um grupo com 20 membros, isso pode gerar 200+ roundtrips ao banco na mesma invocação.

**Fix:** Usar operações batch (ex: `adminDb.from("athlete_trends").upsert(allTrends, ...)`).

### PERF-04: Scan completo de dados do grupo a cada submissão

**Arquivo:** `supabase/functions/submit-analytics/index.ts` (L215–229)

Cada submissão carrega TODOS os trends, baselines e sessões recentes do grupo inteiro para gerar insights. À medida que o grupo cresce, o custo por submissão aumenta linearmente.

**Fix futuro:** Gerar insights apenas para o atleta que submeteu + resumo incremental.

---

## PASS — Verificações Aprovadas

| # | Check | Resultado |
|---|-------|-----------|
| 1 | Termos proibidos (gambling, pay-to-win, purchase, monetization) | PASS — todos os hits são falsos positivos ("between", "better", "compute") |
| 2 | Consistência ordinal enums (Isar ↔ declaração) | PASS — InsightType (10 valores), InsightPriority (4 valores), EvolutionMetric (6 valores) alinhados |
| 3 | Conversão JSON (snake_case ↔ camelCase) | PASS — `_snakeToCamel` / `_camelToSnake` verificados para todos os enums |
| 4 | Convenção de nomes DECISAO 019 | PASS — prefixos `coach_*`, `race_*`, `coaching_*` consistentes |
| 5 | Sentinel values Isar | PASS — `''`, `-1`, `double.nan` corretamente mapeados em ambas direções |
| 6 | Edge Function auth check | PASS — JWT validado, `user_id` comparado com `auth.uid()` |
| 7 | Edge Function idempotência | PASS — `analytics_submissions` com `UNIQUE(session_id)` |
| 8 | Equatable props completude | PASS — todos os campos de entities incluídos em `props` |
| 9 | Isar schema registration | PASS — `CoachInsightRecordSchema` registrado em `isar_database_provider.dart` |
| 10 | AnalyticsSyncService paginação | PASS — `_defaultLimit=50`, `_maxLimit=200`, clamped, `.range()` |
| 11 | Response não vaza PII | PASS — retorna apenas contadores (`baselines_updated`, etc.) |
| 12 | DECISAO 018 append-only enums | PASS — regra documentada e seguida em `InsightType`, `InsightPriority` |

---

## Arquivos Auditados

### Domain

| Arquivo | Sprints | Status |
|---------|---------|--------|
| `domain/entities/coach_insight_entity.dart` | 16.4.0 | OK |
| `domain/entities/insight_type_enum.dart` | 16.4.0 | OK |
| `domain/services/insight_generator.dart` | 16.4.1 | OK |
| `domain/repositories/i_coach_insight_repo.dart` | 16.4.2 | OK |
| `domain/repositories/i_race_event_repo.dart` | 16.3.4 | OK |
| `domain/repositories/i_race_participation_repo.dart` | 16.3.4 | OK |
| `domain/repositories/i_race_result_repo.dart` | 16.3.4 | OK |

### Data

| Arquivo | Sprints | Status |
|---------|---------|--------|
| `data/models/isar/coach_insight_model.dart` | 16.4.2 | OK |
| `data/repositories_impl/isar_coach_insight_repo.dart` | 16.4.2 | OK |
| `data/datasources/analytics_sync_service.dart` | 16.4.5 | OK |
| `data/datasources/isar_database_provider.dart` | 16.4.2 | OK |
| `core/service_locator.dart` | 16.3.4–16.4.5 | INC-02 |

### Presentation

| Arquivo | Sprints | Status |
|---------|---------|--------|
| `presentation/blocs/coach_insights/coach_insights_bloc.dart` | 16.4.3 | INC-01, INC-03 |
| `presentation/blocs/coach_insights/coach_insights_state.dart` | 16.4.3 | OK |
| `presentation/blocs/coach_insights/coach_insights_event.dart` | 16.4.3 | OK |
| `presentation/blocs/race_events/race_events_bloc.dart` | 16.3.4 | PERF-01 |
| `presentation/blocs/race_events/race_events_state.dart` | 16.3.4 | OK |
| `presentation/blocs/race_events/race_events_event.dart` | 16.3.4 | OK |
| `presentation/blocs/race_event_details/race_event_details_bloc.dart` | 16.3.4 | OK |
| `presentation/blocs/race_event_details/race_event_details_state.dart` | 16.3.4 | OK |
| `presentation/blocs/race_event_details/race_event_details_event.dart` | 16.3.4 | OK |
| `presentation/screens/coach_insights_screen.dart` | 16.4.3 | OK |
| `presentation/screens/group_events_screen.dart` | 16.3.4 | OK |
| `presentation/screens/race_event_details_screen.dart` | 16.3.4 | OK |

### Backend

| Arquivo | Sprints | Status |
|---------|---------|--------|
| `supabase/functions/submit-analytics/index.ts` | 16.4.6 | FRAUD-01–04, PERF-03–04 |
| `supabase/migrations/20260217_analytics_tables.sql` | 16.4.6 | PRIV-01 |

### Contracts

| Arquivo | Sprints | Status |
|---------|---------|--------|
| `contracts/analytics_api.md` | 16.4.4 | OK |

---

## Recomendação

1. **PRIV-01 deve ser corrigido imediatamente** — as políticas RLS atuais efetivamente desabilitam o controle de acesso nas tabelas `athlete_baselines`, `athlete_trends` e `coach_insights`.
2. **FRAUD-01 + FRAUD-02** devem ser corrigidos antes do deploy de produção — validação server-side de métricas é essencial.
3. **INC-02** (DI ausente) é esperado pelo planejamento, mas deve ser rastreado para não ser esquecido.
4. Os itens PERF são aceitáveis para MVP mas devem ser endereçados antes de escalar para grupos grandes (50+ atletas).

---

## Correções Aplicadas (sprint 16.9.0-fix)

| # | Issue | Fix | Arquivos |
|---|-------|-----|----------|
| 1 | PRIV-01 | Removidas 3 políticas RLS `service_*` (service_role já bypassa RLS) | `20260217_analytics_tables.sql` |
| 2 | FRAUD-01 | Removido gate `is_verified` do cliente; server marca internamente | `index.ts`, `analytics_sync_service.dart` |
| 3 | FRAUD-02 | Adicionadas 7 constantes de bounds + 5 validações server-side (distance, moving_ms, start<end, pace, bpm) | `index.ts` |
| 4 | FRAUD-03 | Rate limiting: max 10 submissões/dia/usuário via contagem em `analytics_submissions` (HTTP 429) | `index.ts` |
| 5 | FRAUD-04 | Deduplicação de insights: busca insights ativos dos últimos 7 dias e skip se (target_user_id, type) já existe | `index.ts` |
| 6 | INC-01 | Filtro `dismissed` aplicado sempre no BLoC (antes: só quando ambos filtros ativos) | `coach_insights_bloc.dart` |
| 7 | INC-02 | Registros DI de `RaceEventsBloc`/`RaceEventDetailsBloc` comentados até Isar impls existirem | `service_locator.dart` |
| 8 | INC-03 | Refatorada lógica de `_fetch`: filtros dismissed/unreadOnly agora ortogonais (corrigido junto com INC-01) | `coach_insights_bloc.dart` |
| 9 | PERF-01 | Adicionado `countByEventIds(Set<String>)` batch ao `IRaceParticipationRepo`; BLoC usa chamada única | `i_race_participation_repo.dart`, `race_events_bloc.dart` |
| 10 | PERF-02 | Adicionados `limit`/`offset` a `ICoachInsightRepo` (default 100) e `IRaceEventRepo` (default 50); Isar impl usa `.offset().limit()` | `i_coach_insight_repo.dart`, `isar_coach_insight_repo.dart`, `i_race_event_repo.dart` |
| 11 | PERF-03 | Substituídos loops de upsert/insert individuais por batch operations (1 chamada para baselines, 1 para trends, 1 para insights) | `index.ts` |
| 12 | PERF-04 | 5 fetches de dados do grupo agora executam em paralelo via `Promise.all` + limits explícitos por query | `index.ts` |

---

*Gerado automaticamente na sprint 16.9.0 — QA Phase 16*
*Correções aplicadas na sprint 16.9.0-fix*
