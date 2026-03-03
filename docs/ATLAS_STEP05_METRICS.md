# ATLAS — STEP 05: Mapa de Métricas Existentes

> Gerado a partir de análise completa do repo (app Flutter + portal Next.js + Supabase).

---

## 1. Onde o app calcula KPIs hoje

### 1.1 `staff_retention_dashboard_screen.dart`

**Path:** `omni_runner/lib/presentation/screens/staff_retention_dashboard_screen.dart`

Calcula **DAU, WAU, retenção semanal (4 semanas)** ao vivo.

**Query 1 — busca atletas do grupo:**
```sql
-- Supabase PostgREST equivalent:
SELECT user_id, role FROM coaching_members
WHERE group_id = $groupId;
```
Linhas 57–61. Filtra `role == 'athlete'` no Dart (lado cliente).

**Query 2 — busca sessões dos últimos 28 dias:**
```sql
SELECT user_id, start_time_ms FROM sessions
WHERE user_id IN ($athleteIds)
  AND status = 3
  AND start_time_ms >= $fourWeeksAgoMs
  AND is_verified = true
  AND total_distance_m >= 1000;
```
Linhas 89–96. O `inFilter` gera um `IN(...)` com **todos os user_ids** — escala O(n) no tamanho da assessoria.

**Cálculo client-side (Dart):**
- DAU: `Set<String>` de user_ids com sessões `>= todayStartMs` (linha 108)
- WAU: `Set<String>` de user_ids com sessões `>= weekStartMs` (linha 109)
- Retenção: `_computeWeeklyRetention` — bucketiza por semana ISO, calcula interseção com semana anterior (linhas 130–178)

**Gargalo:** Para uma assessoria com 500 atletas, o `IN(...)` gera uma query com 500 UUIDs. Com milhares de assessorias abrindo ao mesmo tempo, esse padrão satura o Supabase.

---

### 1.2 `staff_dashboard_screen.dart`

**Path:** `omni_runner/lib/presentation/screens/staff_dashboard_screen.dart`

Dashboard principal do staff. **Não calcula KPIs de engajamento diretamente**, mas faz:

| Query | Tabela | Linhas | O que busca |
|---|---|---|---|
| Membros staff | `coaching_members` | 68–71 | Encontrar membership do staff logado |
| Grupo | `coaching_groups` | 85–88 | Dados do grupo (nome, logo, invite_code, approval_status) |
| Todos membros | `coaching_members` | 123–126 | Sync full para Isar local |
| Disputas abertas | `clearing_cases` | 150–154 | Count de casos com status OPEN/SENT_CONFIRMED/DISPUTED |
| Count membros | `coaching_members` | 161–163 | Total de membros (badge no card) |
| Join requests | `coaching_join_requests` | 170–173 | Pendentes para badge |

**Gargalo:** Sincroniza **todos os membros** do grupo para Isar local em toda abertura (linhas 123–139). Com 1000 atletas, são 1000 rows baixadas toda vez.

---

### 1.3 `staff_performance_screen.dart`

**Path:** `omni_runner/lib/presentation/screens/staff_performance_screen.dart`

KPIs de performance (corridas 7d, km 7d, atletas ativos, PR). Usa os mesmos padrões:
- Busca atletas via `coaching_members`
- Busca sessões via `sessions.inFilter('user_id', athleteIds)`
- Agrega tudo client-side

---

### 1.4 `staff_weekly_report_screen.dart`

**Path:** `omni_runner/lib/presentation/screens/staff_weekly_report_screen.dart`

Relatório semanal — mesma estrutura de queries live.

---

## 2. Onde o portal calcula KPIs hoje

### 2.1 Dashboard (`/dashboard`)

**Path:** `portal/src/app/(portal)/dashboard/page.tsx`

KPIs calculados server-side (Next.js SSR) com queries Supabase:

| KPI | Query | Tabela(s) | Linhas |
|---|---|---|---|
| Créditos disponíveis | `coaching_token_inventory.select('available_tokens')` | `coaching_token_inventory` | 32–34 |
| Count atletas | `coaching_members.select(count)` WHERE role=athlete | `coaching_members` | 36–39 |
| Compras (admin_master) | `billing_purchases.select('status, credits_amount')` | `billing_purchases` | 40–45 |
| All athlete IDs | `coaching_members.select('user_id')` WHERE role=athlete | `coaching_members` | 47–50 |
| Sessões 7d | `sessions.select(...)` WHERE user_id IN(...) AND start >= weekStart | `sessions` | 78–83 |
| Sessões prev 7d | `sessions.select(...)` WHERE start >= prevWeek AND < weekStart | `sessions` | 84–89 |
| Verificados | `athlete_verification.select(count)` WHERE VERIFIED | `athlete_verification` | 90–94 |
| Desafios 30d | `challenge_participants.select(count)` | `challenge_participants` | 95–101 |

**Gargalo:** O `IN(user_id, athleteIds)` para sessões é o mesmo padrão do app. O dashboard faz 6+ queries em paralelo a cada page load.

### 2.2 Engajamento (`/engagement`)

**Path:** `portal/src/app/(portal)/engagement/page.tsx`

| KPI | Cálculo | Linhas |
|---|---|---|
| DAU | `Set(sessions.filter(today).map(user_id)).size` | 62–67 |
| WAU | `Set(weekSessions.map(user_id)).size` | 70 |
| MAU | `Set(monthSessions.map(user_id)).size` | 73 |
| Retenção 30d | `round(MAU / totalAthletes * 100)` | 78–80 |
| Km 7d/30d | `sessions.reduce(sum distance)` | 82–83 |
| Desafios 30d | `challenge_participants count` | 58 |
| Daily breakdown | Loop 7 dias, filtra sessões por dia | 87–102 |

**Gargalo:** Mesma `IN(...)` com todos athlete IDs. Busca **todas as sessões de 30 dias** de **todos os atletas** para calcular MAU.

### 2.3 Atletas (`/athletes`)

**Path:** `portal/src/app/(portal)/athletes/page.tsx`

Lista atletas com dados de atividade. Para cada atleta, busca última sessão e count de sessões 7d.

### 2.4 Export (`/api/export/athletes`)

**Path:** `portal/src/app/api/export/athletes/route.ts`

Exporta CSV com dados de atletas. Mesmo padrão de queries.

### 2.5 `metrics.ts` (operacional, não business)

**Path:** `portal/src/lib/metrics.ts`

**NÃO é métricas de negócio.** É um collector de métricas operacionais (timing, error counts). Interface `MetricsCollector` com implementação `LogMetricsCollector`. Irrelevante para snapshots de KPIs.

---

## 3. Tabelas fonte de métricas

### 3.1 `sessions` — principal fonte de atividade

```sql
-- schema.sql linhas 892-909
CREATE TABLE public.sessions (
    id          uuid PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES auth.users(id),
    status      smallint DEFAULT 0 NOT NULL,      -- 3 = completed
    start_time_ms  bigint NOT NULL,
    end_time_ms    bigint,
    total_distance_m double precision DEFAULT 0,
    moving_ms   bigint DEFAULT 0,
    avg_pace_sec_km double precision,
    avg_bpm     integer,
    max_bpm     integer,
    is_verified boolean DEFAULT true,
    integrity_flags text[] DEFAULT '{}',
    ghost_session_id uuid,
    points_path text,
    is_synced   boolean DEFAULT true,
    created_at  timestamptz DEFAULT now()
);
```

**Índices existentes:**
```sql
idx_sessions_user     ON sessions(user_id, start_time_ms DESC)
idx_sessions_status   ON sessions(user_id, status)
idx_sessions_verified ON sessions(user_id) WHERE is_verified = true
```

**Observação:** Falta um índice composto `(user_id, start_time_ms, status, is_verified)` para a query de engagement que filtra por todos esses campos.

### 3.2 `coaching_members` — membros da assessoria

```sql
CREATE TABLE public.coaching_members (
    id          uuid PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES auth.users(id),
    group_id    uuid NOT NULL REFERENCES coaching_groups(id),
    display_name text NOT NULL,
    role        text DEFAULT 'athlete' CHECK (role IN ('admin_master','coach','assistant','athlete')),
    joined_at_ms bigint NOT NULL,
    UNIQUE(group_id, user_id)
);
```

**Índices:**
```sql
idx_coaching_members_group ON coaching_members(group_id, role)
idx_coaching_members_user  ON coaching_members(user_id)
```

### 3.3 `coaching_groups` — assessorias

```sql
CREATE TABLE public.coaching_groups (
    id            uuid PRIMARY KEY,
    name          text NOT NULL CHECK(length(name) >= 3 AND length(name) <= 80),
    logo_url      text,
    coach_user_id uuid NOT NULL REFERENCES auth.users(id),
    description   text DEFAULT '',
    city          text DEFAULT '',
    created_at_ms bigint NOT NULL,
    created_at    timestamptz DEFAULT now()
);
```

### 3.4 `profile_progress` — XP e streaks

```sql
CREATE TABLE public.profile_progress (
    user_id              uuid PRIMARY KEY REFERENCES auth.users(id),
    total_xp             integer DEFAULT 0,
    season_xp            integer DEFAULT 0,
    daily_streak_count   integer DEFAULT 0,
    last_streak_day_ms   bigint,
    weekly_session_count integer DEFAULT 0,
    monthly_session_count integer DEFAULT 0,
    lifetime_session_count integer DEFAULT 0,
    lifetime_distance_m  double precision DEFAULT 0,
    lifetime_moving_ms   bigint DEFAULT 0,
    updated_at           timestamptz DEFAULT now()
);
```

### 3.5 `analytics_submissions` — sessões processadas para analytics

```sql
CREATE TABLE public.analytics_submissions (
    id          uuid PRIMARY KEY,
    session_id  uuid NOT NULL UNIQUE,
    user_id     uuid NOT NULL REFERENCES auth.users(id),
    group_id    uuid NOT NULL,
    distance_m  double precision NOT NULL,
    moving_ms   bigint NOT NULL,
    avg_pace_sec_per_km double precision,
    avg_bpm     integer,
    start_time_ms bigint NOT NULL,
    end_time_ms   bigint NOT NULL,
    processed_at  timestamptz DEFAULT now()
);
```

**Índices:**
```sql
idx_submissions_group_time  ON analytics_submissions(group_id, start_time_ms DESC)
idx_submissions_user_group  ON analytics_submissions(user_id, group_id)
```

**Oportunidade:** Esta tabela já tem `group_id` — mais eficiente que `sessions` (que requer JOIN com `coaching_members`). Porém, pode não ter todas as sessões (depends on sync).

### 3.6 `challenge_participants` — participação em desafios

```sql
idx_challenge_parts_user ON challenge_participants(user_id, status)
```

---

## 4. Funções SQL existentes que agregam métricas

| Função | O que faz | Onde usada |
|---|---|---|
| `compute_leaderboard_global_weekly` | Rankeia por distância semanal | Cron/manual |
| `increment_profile_progress` | Incrementa XP/distância/sessões | Após sessão |
| `increment_wallet_balance` | Atualiza wallet | Após reward |

**Não existe nenhuma função de snapshot/pré-agregação de KPIs hoje.**

---

## 5. Gargalos identificados

| # | Gargalo | Impacto | Onde |
|---|---|---|---|
| G1 | `IN(user_id, ...)` com 100–1000 UUIDs | Query lenta, CPU alto no Postgres | App retention, portal dashboard/engagement |
| G2 | Full table scan em `sessions` (4 semanas) | Cresce linearmente com atividade | App retention, portal engagement |
| G3 | Sync de todos membros para Isar local | Transferência desnecessária | App staff_dashboard |
| G4 | Cálculo de DAU/WAU/MAU a cada page load | Redundância — mesmo resultado para todos os staffs do grupo | Portal dashboard/engagement |
| G5 | Sem cache/snapshot — sempre live | Não escala para >100 assessorias ativas | Todos |
| G6 | Falta índice composto para query de engagement | Index scan subótimo | `sessions` |

---

## 6. Telas que mostram métricas (mapa completo)

### App Flutter

| Tela | Path | Métricas mostradas |
|---|---|---|
| Staff Dashboard | `lib/presentation/screens/staff_dashboard_screen.dart` | Member count, disputes, join requests |
| Retenção | `lib/presentation/screens/staff_retention_dashboard_screen.dart` | DAU, WAU, retenção semanal 4w, insights |
| Performance | `lib/presentation/screens/staff_performance_screen.dart` | Corridas 7d, km 7d, atletas ativos, PRs |
| Relatório Semanal | `lib/presentation/screens/staff_weekly_report_screen.dart` | Resumo semanal por atleta |

### Portal Next.js

| Página | Path | Métricas mostradas |
|---|---|---|
| Dashboard | `portal/src/app/(portal)/dashboard/page.tsx` | Créditos, atletas, verificados, WAU, corridas 7d, km 7d, desafios 30d, daily chart |
| Engajamento | `portal/src/app/(portal)/engagement/page.tsx` | DAU, WAU, MAU, retenção 30d, corridas 7d/30d, km 7d/30d, daily breakdown, alerta inativos |
| Atletas | `portal/src/app/(portal)/athletes/page.tsx` | Lista com última sessão, corridas 7d |
| Export Atletas | `portal/src/app/api/export/athletes/route.ts` | CSV com dados de atividade |
