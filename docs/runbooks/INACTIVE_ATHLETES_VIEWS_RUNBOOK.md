## Inactive Athletes — Progression Views Runbook (L08-05)

**Status**: active · **Owner**: Data / Coaching · **Updated**: 2026-04-21

---

### 1. Problema

Rankings e baselines agregados em `v_user_progression` somavam atletas que
pararam de correr há meses/anos. Um atleta de `total_xp=5000 level=10` que
parou há 2 anos ainda aparecia no top da leaderboard, distorcendo:

- "Atleta mais evoluído" da assessoria.
- Baselines de `fn_generate_weekly_goal` (menos crítico — já janelado em 28 dias).
- Dashboards de staff agregando XP lifetime.

---

### 2. Solução

**Forward-compatible expansion** em vez de `WHERE` destrutivo:

1. `v_user_progression` ganha 2 colunas no final (sem mexer nas 16 originais):
   - `last_session_at timestamptz` — timestamp da última sessão verificada
     (`NULL` para atletas sem sessão).
   - `is_active_90d boolean` — `true` se há >= 1 sessão verificada nos
     últimos 90 dias.
2. `v_user_progression_active_90d` — novo view, filtrado por
   `is_active_90d = true`. **É a fonte canônica para rankings/baselines.**
3. `v_weekly_progress_active_90d` — mirror de `v_weekly_progress` com
   `start_time_ms >= now() - 90 days` embutido. Para analytics dashboards
   que agregam além do horizon semanal default.
4. `fn_is_athlete_active_90d(p_user_id uuid)` — helper STABLE SECURITY
   DEFINER para uso em filtros pontuais (RLS policies, check constraints).

**Nenhum código consumidor precisa mudar imediatamente** — os 3 sites atuais
(`notify-rules`, `streaks_leaderboard_screen`, `staff_weekly_report_screen`)
continuam legítimos ao buscar atletas com streak baixa ou leaderboard
interno. A migração de cada site para `_active_90d` é uma PR de UX separada,
com evaluação de intenção caso a caso.

---

### 3. Quando usar cada view

| View | Quando usar | Consumidor típico |
|---|---|---|
| `v_user_progression` | Preciso mostrar TODOS os atletas inclusive inativos / "cold start" | Staff report (mostra atleta que entrou hoje ainda sem corrida), motivation nudges para atletas inativos |
| `v_user_progression_active_90d` | Rankings, baselines, leaderboards públicos de "top runners" | "Top atleta do mês", badges de consistência, rankings de assessoria |
| `v_weekly_progress` | Goal baselines (28 days), relatório semanal do próprio atleta | `fn_generate_weekly_goal`, UI mobile do atleta |
| `v_weekly_progress_active_90d` | Analytics dashboard staff, agregações mensais/trimestrais | Staff dashboard "quantos km nossos atletas ativos rodaram este trimestre?" |

---

### 4. Migração de call sites (trabalho futuro)

Para cada consumidor de `v_user_progression`, classifique a intenção:

```bash
rg "from\(['\"]v_user_progression['\"]\)" -- omni_runner supabase
```

Classificação:
- **Leaderboard público / ranking "top atleta"** → migrar para `_active_90d`.
- **Staff report interno**, **nudge para atleta inativo** → manter
  `v_user_progression` (usa `is_active_90d` como flag para segmentar UI).

Exemplo de migração para `streaks_leaderboard_screen.dart`:

```dart
// Antes: incluía atletas com streak_current=0 que pararam há 1 ano
final progRes = await db
    .from('v_user_progression')
    .select('user_id, streak_current, streak_best, level, total_xp')
    .inFilter('user_id', athleteIds);

// Depois: só atletas ativos nos últimos 90 dias entram no ranking
final progRes = await db
    .from('v_user_progression_active_90d')
    .select('user_id, streak_current, streak_best, level, total_xp')
    .inFilter('user_id', athleteIds);
```

Se o site precisa diferenciar "atleta sem corridas" de "atleta inativo":

```dart
final progRes = await db
    .from('v_user_progression')
    .select('user_id, streak_current, level, is_active_90d, last_session_at')
    .inFilter('user_id', athleteIds);
// UI pode agora mostrar badge "Reativar!" para is_active_90d=false
// com last_session_at != null, ou "Nova atleta!" quando last_session_at=null.
```

---

### 5. Performance

Todas as views são `security_invoker = on` — RLS das tabelas subjacentes
(`profiles`, `profile_progress`, `sessions`) é aplicada per-query.

A projeção `last_session_at` usa subquery com `MAX(start_time_ms)` filtrado
por `is_verified = true`. O índice `idx_sessions_user(user_id,
start_time_ms DESC)` cobre esta query via index-only scan.

Custo observado (PG 16 no sandbox, 3 atletas): < 5 ms por row.
Para bases > 100k profiles, considere materializar `v_user_progression`
como `MATERIALIZED VIEW` com refresh diário via cron job.

---

### 6. Retrocompatibilidade

A coluna `last_session_at` é adicionada **no final** da lista, e
`is_active_90d` logo depois. Nenhuma coluna existente foi reordenada ou
removida. Consumidores que fazem `SELECT col1, col2 FROM v_user_progression`
continuam funcionando sem alteração.

Consumidores que fazem `SELECT * FROM v_user_progression` (discouraged)
verão 2 colunas extras — geralmente benigno.

---

### 7. Horizonte configurável (trabalho futuro)

90 dias é hardcoded. Se a assessoria precisar de horizonte configurável
(ex.: "ativos nos últimos 30 dias" para leaderboard mensal):

```sql
-- Variante parameterizada
CREATE OR REPLACE FUNCTION public.fn_is_athlete_active(
  p_user_id uuid, p_days integer DEFAULT 90
) RETURNS boolean ...;
```

---

### 8. Referências

- Finding: `docs/audit/findings/L08-05-views-de-progressao-sem-filtro-de-atletas-inativos.md`
- Migração: `supabase/migrations/20260421310000_l08_05_inactive_athletes_filter.sql`
- Testes: `tools/test_l08_05_inactive_athletes_filter.ts`
- Call sites:
  - `supabase/functions/notify-rules/index.ts` (streak at-risk nudges)
  - `omni_runner/lib/presentation/screens/streaks_leaderboard_screen.dart`
  - `omni_runner/lib/presentation/screens/staff_weekly_report_screen.dart`
