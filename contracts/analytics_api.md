# Analytics API Contracts

> **Sprint:** 16.5.1
> **Status:** Ativo
> **Referencia:** DECISAO 010 (Supabase backend), ARCHITECTURE.md, sync_payload.md

---

## 1. Visao Geral

O modulo de coaching analytics expoe tres operacoes via Supabase (REST + Edge Functions):

| Operacao | Direcao | Ator | Destino |
|----------|---------|------|---------|
| `submitAnalyticsData` | Client → Backend | Atleta (pos-sessao) | Edge Function → tabelas analytics |
| `fetchGroupInsights` | Backend → Client | Coach | Postgres REST (`coach_insights`) |
| `fetchEvolutionMetrics` | Backend → Client | Coach / Atleta | Postgres REST (`athlete_trends` + `athlete_baselines`) |

Todas as operacoes exigem **Bearer token JWT** (Supabase Auth).
RLS garante que coaches so acessam dados de grupos que gerenciam e atletas so acessam seus proprios dados.

---

## 2. submitAnalyticsData

### Proposito

Apos uma sessao de corrida ser finalizada e sincronizada, o device do atleta envia um
resumo analitico que alimenta baselines, trends e insights do grupo de assessoria.

### Endpoint

```
POST  /functions/v1/submit-analytics

Content-Type: application/json
Authorization: Bearer <jwt>
```

### Request Body

```json
{
  "session_id": "uuid-da-sessao",
  "user_id": "uuid-do-atleta",
  "group_id": "uuid-do-grupo",
  "start_time_ms": 1707753600000,
  "end_time_ms": 1707755400000,
  "distance_m": 5230.5,
  "moving_ms": 1620000,
  "avg_pace_sec_per_km": 310.2,
  "avg_bpm": 152,
  "is_verified": true
}
```

### Request Schema

| Campo | Tipo | Obrigatorio | Unidade | Notas |
|-------|------|-------------|---------|-------|
| session_id | string (UUID) | SIM | — | Mesmo ID da sessao sincronizada |
| user_id | string (UUID) | SIM | — | `auth.uid()` do atleta |
| group_id | string (UUID) | SIM | — | Grupo de assessoria alvo |
| start_time_ms | integer | SIM | ms epoch UTC | Inicio da sessao |
| end_time_ms | integer | SIM | ms epoch UTC | Fim da sessao |
| distance_m | number | SIM | metros | Distancia verificada total |
| moving_ms | integer | SIM | milissegundos | Tempo em movimento |
| avg_pace_sec_per_km | number | NAO | sec/km | Null se distancia zero |
| avg_bpm | integer | NAO | BPM | Null se sem sensor HR |
| is_verified | boolean | SIM | — | Anti-cheat passed |

### Validacoes (Edge Function)

| # | Regra | HTTP | Erro |
|---|-------|------|------|
| V1 | `auth.uid() == user_id` | 403 | `forbidden` |
| V2 | Atleta e membro ativo do `group_id` | 403 | `not_group_member` |
| V3 | `is_verified == true` | 422 | `session_not_verified` |
| V4 | `session_id` nao duplicado na tabela `analytics_submissions` | 200 (idempotente) | — |
| V5 | `distance_m > 0` e `moving_ms > 0` | 422 | `invalid_session_data` |

### Processamento (Edge Function)

```
1. Inserir em `analytics_submissions` (idempotencia via session_id UNIQUE)
2. Recalcular baselines do atleta (ultimas 4 semanas)
3. Recalcular trends do atleta (ultimos 4 periodos)
4. Gerar insights automaticos para o coach (InsightGenerator)
5. Upsert resultados em `athlete_baselines`, `athlete_trends`, `coach_insights`
```

### Response

**Sucesso (200)**

```json
{
  "status": "ok",
  "baselines_updated": 6,
  "trends_updated": 6,
  "insights_generated": 2
}
```

**Duplicado (200 — idempotente)**

```json
{
  "status": "already_processed",
  "session_id": "uuid-da-sessao"
}
```

**Erro (4xx)**

```json
{
  "status": "error",
  "code": "not_group_member",
  "message": "Atleta nao e membro ativo do grupo."
}
```

### Conversao Dart

```dart
/// Monta payload para submit analytics.
Map<String, Object?> analyticsPayload({
  required String sessionId,
  required String userId,
  required String groupId,
  required int startTimeMs,
  required int endTimeMs,
  required double distanceM,
  required int movingMs,
  double? avgPaceSecPerKm,
  int? avgBpm,
  required bool isVerified,
}) {
  return {
    'session_id': sessionId,
    'user_id': userId,
    'group_id': groupId,
    'start_time_ms': startTimeMs,
    'end_time_ms': endTimeMs,
    'distance_m': distanceM,
    'moving_ms': movingMs,
    if (avgPaceSecPerKm != null) 'avg_pace_sec_per_km': avgPaceSecPerKm,
    if (avgBpm != null) 'avg_bpm': avgBpm,
    'is_verified': isVerified,
  };
}
```

---

## 3. fetchGroupInsights

### Proposito

O coach consulta insights gerados automaticamente para o seu grupo de assessoria.
Suporta filtros por tipo, prioridade e status de leitura.

### Endpoint

```
GET  /rest/v1/coach_insights
     ?group_id=eq.<uuid>
     &order=created_at_ms.desc
     &limit=50

Authorization: Bearer <jwt>
```

### Query Parameters

| Parametro | Tipo | Obrigatorio | Notas |
|-----------|------|-------------|-------|
| group_id | `eq.<uuid>` | SIM | RLS valida que caller e coach/assistant do grupo |
| type | `eq.<string>` | NAO | Filtro por InsightType (snake_case) |
| priority | `eq.<string>` | NAO | Filtro por InsightPriority |
| read_at_ms | `is.null` | NAO | Filtrar apenas nao lidos |
| dismissed | `eq.false` | NAO | Excluir dispensados |
| order | string | NAO | Default: `created_at_ms.desc` |
| limit | integer | NAO | Default: 50, max: 200 |
| offset | integer | NAO | Paginacao |

### Tabela Postgres: `coach_insights`

```sql
CREATE TABLE public.coach_insights (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES coaching_groups(id),
  target_user_id  UUID,
  target_display_name TEXT,
  type            TEXT NOT NULL,
  priority        TEXT NOT NULL,
  title           TEXT NOT NULL,
  message         TEXT NOT NULL,
  metric          TEXT,
  reference_value DOUBLE PRECISION,
  change_percent  DOUBLE PRECISION,
  related_entity_id UUID,
  created_at_ms   BIGINT NOT NULL,
  read_at_ms      BIGINT,
  dismissed       BOOLEAN NOT NULL DEFAULT false
);

-- Indices
CREATE INDEX idx_insights_group ON coach_insights(group_id, created_at_ms DESC);
CREATE INDEX idx_insights_unread ON coach_insights(group_id) WHERE read_at_ms IS NULL AND dismissed = false;
CREATE INDEX idx_insights_type ON coach_insights(group_id, type);
```

### RLS Policy

```sql
-- Coach/assistant do grupo pode ler
CREATE POLICY "coach_reads_insights" ON coach_insights
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );

-- Coach/assistant pode atualizar (markRead, dismiss)
CREATE POLICY "coach_updates_insights" ON coach_insights
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );
```

### Response (200)

```json
[
  {
    "id": "uuid-insight-1",
    "group_id": "uuid-grupo",
    "target_user_id": "uuid-atleta",
    "target_display_name": "Ana Silva",
    "type": "performance_decline",
    "priority": "high",
    "title": "Ana Silva em queda em pace médio",
    "message": "Pace médio caiu 18.3% em relação ao baseline.",
    "metric": "avg_pace",
    "reference_value": 365.0,
    "change_percent": 18.3,
    "related_entity_id": null,
    "created_at_ms": 1707753600000,
    "read_at_ms": null,
    "dismissed": false
  }
]
```

### Enum Mapping (Postgres TEXT ↔ Dart enum)

**InsightType**

| Dart | Postgres |
|------|----------|
| `performanceDecline` | `performance_decline` |
| `performanceImprovement` | `performance_improvement` |
| `consistencyDrop` | `consistency_drop` |
| `inactivityWarning` | `inactivity_warning` |
| `personalRecord` | `personal_record` |
| `overtrainingRisk` | `overtraining_risk` |
| `raceReady` | `race_ready` |
| `groupTrendSummary` | `group_trend_summary` |
| `eventMilestone` | `event_milestone` |
| `rankingChange` | `ranking_change` |

**InsightPriority**

| Dart | Postgres |
|------|----------|
| `low` | `low` |
| `medium` | `medium` |
| `high` | `high` |
| `critical` | `critical` |

**EvolutionMetric**

| Dart | Postgres |
|------|----------|
| `avgPace` | `avg_pace` |
| `avgDistance` | `avg_distance` |
| `weeklyVolume` | `weekly_volume` |
| `weeklyFrequency` | `weekly_frequency` |
| `avgHeartRate` | `avg_heart_rate` |
| `avgMovingTime` | `avg_moving_time` |

### PATCH — Mark Read / Dismiss

```
PATCH  /rest/v1/coach_insights?id=eq.<uuid>

Authorization: Bearer <jwt>
Content-Type: application/json

{ "read_at_ms": 1707760000000 }
```

```
PATCH  /rest/v1/coach_insights?id=eq.<uuid>

{ "dismissed": true }
```

### Conversao Dart

```dart
/// Converte response JSON para CoachInsightEntity.
CoachInsightEntity insightFromJson(Map<String, dynamic> json) {
  return CoachInsightEntity(
    id: json['id'] as String,
    groupId: json['group_id'] as String,
    targetUserId: json['target_user_id'] as String?,
    targetDisplayName: json['target_display_name'] as String?,
    type: InsightType.values.byName(_snakeToCamel(json['type'] as String)),
    priority: InsightPriority.values.byName(json['priority'] as String),
    title: json['title'] as String,
    message: json['message'] as String,
    metric: json['metric'] != null
        ? EvolutionMetric.values.byName(_snakeToCamel(json['metric'] as String))
        : null,
    referenceValue: (json['reference_value'] as num?)?.toDouble(),
    changePercent: (json['change_percent'] as num?)?.toDouble(),
    relatedEntityId: json['related_entity_id'] as String?,
    createdAtMs: json['created_at_ms'] as int,
    readAtMs: json['read_at_ms'] as int?,
    dismissed: json['dismissed'] as bool? ?? false,
  );
}
```

---

## 4. fetchEvolutionMetrics

### Proposito

Coach ou atleta consulta trends e baselines de evolucao para um atleta dentro de um grupo.
Tambem permite consulta agregada de todos os atletas do grupo (visao coach).

### 4a. Athlete Trends

#### Endpoint

```
GET  /rest/v1/athlete_trends
     ?group_id=eq.<uuid>
     &order=analyzed_at_ms.desc

Authorization: Bearer <jwt>
```

#### Query Parameters

| Parametro | Tipo | Obrigatorio | Notas |
|-----------|------|-------------|-------|
| group_id | `eq.<uuid>` | SIM | RLS: coach/assistant ve todos; atleta ve apenas seus |
| user_id | `eq.<uuid>` | NAO | Filtrar por atleta especifico |
| metric | `eq.<string>` | NAO | Filtrar por EvolutionMetric (snake_case) |
| period | `eq.<string>` | NAO | `weekly` ou `monthly` |
| direction | `eq.<string>` | NAO | `improving`, `stable`, `declining`, `insufficient` |
| limit | integer | NAO | Default: 100 |

#### Tabela Postgres: `athlete_trends`

```sql
CREATE TABLE public.athlete_trends (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  group_id        UUID NOT NULL REFERENCES coaching_groups(id),
  metric          TEXT NOT NULL,
  period          TEXT NOT NULL,
  direction       TEXT NOT NULL,
  current_value   DOUBLE PRECISION NOT NULL,
  baseline_value  DOUBLE PRECISION NOT NULL,
  change_percent  DOUBLE PRECISION NOT NULL,
  data_points     INTEGER NOT NULL,
  latest_period_key TEXT NOT NULL,
  analyzed_at_ms  BIGINT NOT NULL,

  UNIQUE(user_id, group_id, metric, period)
);

CREATE INDEX idx_trends_group ON athlete_trends(group_id);
CREATE INDEX idx_trends_user_group ON athlete_trends(user_id, group_id);
CREATE INDEX idx_trends_direction ON athlete_trends(group_id, direction);
```

#### RLS Policy

```sql
-- Coach/assistant ve todos os trends do grupo; atleta ve apenas os seus
CREATE POLICY "trends_read" ON athlete_trends
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM coaching_members
      WHERE coaching_members.group_id = athlete_trends.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );
```

#### Response (200)

```json
[
  {
    "id": "uuid-trend-1",
    "user_id": "uuid-atleta",
    "group_id": "uuid-grupo",
    "metric": "avg_pace",
    "period": "weekly",
    "direction": "improving",
    "current_value": 310.5,
    "baseline_value": 340.2,
    "change_percent": -8.73,
    "data_points": 4,
    "latest_period_key": "2026-W07",
    "analyzed_at_ms": 1707753600000
  }
]
```

### 4b. Athlete Baselines

#### Endpoint

```
GET  /rest/v1/athlete_baselines
     ?group_id=eq.<uuid>

Authorization: Bearer <jwt>
```

#### Query Parameters

| Parametro | Tipo | Obrigatorio | Notas |
|-----------|------|-------------|-------|
| group_id | `eq.<uuid>` | SIM | Mesmo RLS que trends |
| user_id | `eq.<uuid>` | NAO | Filtrar por atleta |
| metric | `eq.<string>` | NAO | Filtrar por EvolutionMetric |

#### Tabela Postgres: `athlete_baselines`

```sql
CREATE TABLE public.athlete_baselines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  group_id        UUID NOT NULL REFERENCES coaching_groups(id),
  metric          TEXT NOT NULL,
  value           DOUBLE PRECISION NOT NULL,
  sample_size     INTEGER NOT NULL,
  window_start_ms BIGINT NOT NULL,
  window_end_ms   BIGINT NOT NULL,
  computed_at_ms  BIGINT NOT NULL,

  UNIQUE(user_id, group_id, metric)
);

CREATE INDEX idx_baselines_group ON athlete_baselines(group_id);
CREATE INDEX idx_baselines_user_group ON athlete_baselines(user_id, group_id);
```

#### RLS Policy

```sql
-- Mesma logica de trends
CREATE POLICY "baselines_read" ON athlete_baselines
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM coaching_members
      WHERE coaching_members.group_id = athlete_baselines.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );
```

#### Response (200)

```json
[
  {
    "id": "uuid-baseline-1",
    "user_id": "uuid-atleta",
    "group_id": "uuid-grupo",
    "metric": "avg_pace",
    "value": 340.2,
    "sample_size": 12,
    "window_start_ms": 1705161600000,
    "window_end_ms": 1707753600000,
    "computed_at_ms": 1707753600000
  }
]
```

### Conversao Dart

```dart
/// Converte response JSON para AthleteTrendEntity.
AthleteTrendEntity trendFromJson(Map<String, dynamic> json) {
  return AthleteTrendEntity(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    groupId: json['group_id'] as String,
    metric: EvolutionMetric.values.byName(_snakeToCamel(json['metric'] as String)),
    period: EvolutionPeriod.values.byName(json['period'] as String),
    direction: TrendDirection.values.byName(json['direction'] as String),
    currentValue: (json['current_value'] as num).toDouble(),
    baselineValue: (json['baseline_value'] as num).toDouble(),
    changePercent: (json['change_percent'] as num).toDouble(),
    dataPoints: json['data_points'] as int,
    latestPeriodKey: json['latest_period_key'] as String,
    analyzedAtMs: json['analyzed_at_ms'] as int,
  );
}

/// Converte response JSON para AthleteBaselineEntity.
AthleteBaselineEntity baselineFromJson(Map<String, dynamic> json) {
  return AthleteBaselineEntity(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    groupId: json['group_id'] as String,
    metric: EvolutionMetric.values.byName(_snakeToCamel(json['metric'] as String)),
    value: (json['value'] as num).toDouble(),
    sampleSize: json['sample_size'] as int,
    windowStartMs: json['window_start_ms'] as int,
    windowEndMs: json['window_end_ms'] as int,
    computedAtMs: json['computed_at_ms'] as int,
  );
}

/// Converte snake_case para camelCase (ex: "avg_pace" -> "avgPace").
String _snakeToCamel(String s) {
  final parts = s.split('_');
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}
```

---

## 5. Tabela Auxiliar: `analytics_submissions`

Garante idempotencia do `submitAnalyticsData`.

```sql
CREATE TABLE public.analytics_submissions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID NOT NULL UNIQUE,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  group_id        UUID NOT NULL REFERENCES coaching_groups(id),
  distance_m      DOUBLE PRECISION NOT NULL,
  moving_ms       BIGINT NOT NULL,
  avg_pace_sec_per_km DOUBLE PRECISION,
  avg_bpm         INTEGER,
  start_time_ms   BIGINT NOT NULL,
  end_time_ms     BIGINT NOT NULL,
  processed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_submissions_user_group ON analytics_submissions(user_id, group_id);
CREATE INDEX idx_submissions_group_time ON analytics_submissions(group_id, start_time_ms DESC);
```

---

## 6. Seguranca

| Aspecto | Implementacao |
|---------|---------------|
| Autenticacao | Bearer token JWT (Supabase Auth) em todas as requests |
| RLS (insights) | Coach/assistant do grupo pode ler/atualizar |
| RLS (trends/baselines) | Coach/assistant ve todos; atleta ve apenas os seus |
| Edge Function auth | Valida `auth.uid() == user_id` no payload |
| Membership check | Valida que atleta e membro ativo do grupo |
| Idempotencia | `session_id UNIQUE` em `analytics_submissions` |
| Rate limit | Edge Function: 60 req/min por usuario (Supabase default) |

---

## 7. Fluxo Completo (Diagrama)

```
Atleta finaliza sessao
       │
       ▼
  sync_payload (sessao + pontos GPS)     ← Sprint 9.2
       │
       ▼
  submitAnalyticsData (Edge Function)    ← Este contrato
       │
       ├─► analytics_submissions (dedup)
       ├─► BaselineCalculator.computeAll()
       ├─► EvolutionAnalyzer.analyzeAll()
       ├─► InsightGenerator.generate()
       │
       ├─► UPSERT athlete_baselines
       ├─► UPSERT athlete_trends
       └─► INSERT coach_insights
              │
              ▼
  Coach abre dashboard
       │
       ├─► fetchGroupInsights   → coach_insights
       └─► fetchEvolutionMetrics → athlete_trends + athlete_baselines
```

---

## 8. Limites e Edge Cases

| Cenario | Tratamento |
|---------|------------|
| Sessao nao verificada | Rejeitada com 422 (`session_not_verified`) |
| Sessao duplicada | Retorna 200 idempotente (`already_processed`) |
| Atleta removido do grupo | Membership check falha (403) |
| Grupo com 0 sessoes | Trends/baselines retornam array vazio |
| Coach de multiplos grupos | Cada query e filtrada por `group_id` |
| Atleta em multiplos grupos | Baselines/trends separados por `group_id` |
| Mais de 200 insights | Paginacao via `limit` + `offset` |
| Baseline com `sample_size < 3` | Marcado como nao confiavel (`isReliable = false`) |

---

## 9. Versionamento

```
Versao atual: 1
Header de versao: NAO incluido no MVP

Estrategia futura:
  - submitAnalyticsData: campo "version" no body (default 1)
  - Postgres: migracao de colunas com defaults
  - Manter backward compatibility por 2 versoes
```

---

*Documento gerado na Sprint 16.5.1*
