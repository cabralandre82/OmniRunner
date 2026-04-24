---
id: L23-02
audit_ref: "23.2"
lens: 23
title: "Dashboard de overview diário para coach tem 100-500 atletas"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["coach", "sql", "rpc", "dashboard", "prioritization"]
files:
  - supabase/migrations/20260421740000_l23_02_coach_daily_digest.sql
  - tools/audit/check-coach-daily-digest.ts
correction_type: rpc
test_required: true
tests:
  - tools/audit/check-coach-daily-digest.ts
linked_issues: []
linked_prs:
  - d3488b4
  - e30ab8a
owner: coach-tooling
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  RPC `public.fn_coach_daily_digest(p_group_id uuid, p_as_of date,
  p_max_per_bucket int)` SECURITY DEFINER + STABLE +
  search_path pinned + REVOKE FROM PUBLIC + GRANT TO authenticated.
  Bucketiza atletas em 4 categorias mutuamente exclusivas (ordem
  de prioridade descendente):

  1. **needs_attention** — qualquer um de:
     - `inactive_3d`        — última sessão verificada > 3 dias
     - `plan_not_followed`  — workout planned (confirmed) sem
                              session no mesmo período de 7 dias
     - `integrity_flag`     — última sessão com integrity_flags

  2. **at_risk** — qualquer um de:
     - `declining_volume`   — distância 7d < 50% dos 7d anteriores
     - `overtraining_spike` — distância 7d > 200% dos 7d anteriores

  3. **new_prs** — `best_recent_pace` (últimos 7d) bateu o
     `baseline_best_pace` (melhor dos últimos 90 dias antes da
     janela atual). Apenas sessões verified, ≥ 1 km e
     `avg_pace_sec_km > 0`.

  4. **performing_well** — `adherence_14d_pct ≥ 80%`.

  Cada bucket é capped em `p_max_per_bucket` (default 50, max 200)
  via `row_number() OVER (PARTITION BY bucket ORDER BY score DESC)`.
  O score combina os 6 sinais (integrity_flag=100, plan_not_followed=60,
  inactive_3d=40, overtraining_spike=30, declining_volume=20, new_pr=10)
  para que o coach veja primeiro o que mais merece atenção dentro
  de cada bucket — relevante quando uma assessoria tem 200+ atletas
  inativos e o coach só consegue contatar 50/dia.

  Output JSONB envelope:

  ```json
  {
    "group_id": "...",
    "as_of":    "2026-04-23",
    "generated_at": "...",
    "window": { "now_lo", "now_hi", "prev_lo", "prev_hi" },
    "counts": { "total_athletes", "needs_attention", "at_risk",
                "new_prs", "performing_well", "neutral" },
    "needs_attention": [ { athlete_user_id, display_name, bucket,
                          score, signals[], adherence_14d_pct,
                          last_session_at, ... } ],
    "at_risk":         [...],
    "new_prs":         [...],
    "performing_well": [...]
  }
  ```

  Gates:
  - P0001 INVALID_INPUT: `p_group_id` NULL, `p_max_per_bucket`
    fora de [1,200] ou `p_as_of` NULL.
  - P0002 GROUP_NOT_FOUND: grupo inexistente.
  - P0010 UNAUTHORIZED: caller não é
    `admin_master`/`coach`/`assistant` do grupo.

  OmniCoin: `STABLE`, zero writes — nunca toca `coin_ledger` /
  `wallets` (L04-07-OK). Comentário explícito.

  CI guard `audit:coach-daily-digest` (~60 asserts) valida shape
  do contrato: signature, security definer, STABLE, search_path,
  grants, time windows, signal definitions, bucket priority, score
  weights, capping, envelope JSONB e self-test runtime.

  UX no portal: rota nova `GET /api/coaching/[groupId]/daily-digest`
  (presenter follow-up, não bloqueador) chama o RPC e renderiza 4
  colunas, cada uma com link para o athlete profile. Coach com 500
  atletas passa de 3h/dia em listagem alfabética para minutos
  triando os 50 mais críticos por bucket.
---
# [L23-02] Dashboard de overview diário para coach tem 100-500 atletas
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Backend / Coach tooling
**Personas impactadas:** Coach com 100–500 atletas

## Achado
`coach_insights_screen.dart` exibia listagem alfabética sem priorização. Coach com 500 atletas precisa **priorização**:
- Quem **precisa de atenção hoje**: lesão reportada, 3+ dias sem treino, TSS anomaly, plano não cumprido.
- Quem **está indo bem**: pode receber plano mais agressivo.
- Quem **está em PR**: coach felicita pessoalmente.

Sem priorização, coach gasta 3h/dia varrendo dashboard manualmente.

## Correção aplicada

RPC `public.fn_coach_daily_digest(group_id, as_of, max_per_bucket)` que retorna 4 buckets prioritários (`needs_attention` > `at_risk` > `new_prs` > `performing_well`) calculados a partir de **3 fontes existentes**:

1. `public.sessions` — Strava-only após sweep 25.0.0; usa `is_verified`, `start_time_ms`, `total_distance_m`, `avg_pace_sec_km`, `integrity_flags`.
2. `public.workout_delivery_items` — workouts confirmados pelo atleta (`status='confirmed'`), confronta com sessions reais para detectar plan_not_followed.
3. `public.coaching_members` — membership + role gate.

### Sinais (6 codes)

| Sinal | Bucket | Threshold |
|---|---|---|
| `integrity_flag` | needs_attention | última sessão tem `integrity_flags` non-empty |
| `plan_not_followed` | needs_attention | `planned_7d > 0 AND verified_n_7d = 0` |
| `inactive_3d` | needs_attention | última sessão verificada > 3 dias atrás |
| `overtraining_spike` | at_risk | `dist_m_7d > 2.0 × dist_m_prev_7d` |
| `declining_volume` | at_risk | `dist_m_7d < 0.5 × dist_m_prev_7d` |
| `new_pr` | new_prs | `best_recent_pace < baseline_best_pace` (90d) |

### Score-based capping

Cada bucket é capado em `max_per_bucket` (default 50, max 200) via score ponderado (integrity=100, plan_not_followed=60, inactive_3d=40, overtraining_spike=30, declining_volume=20, new_pr=10). Coach vê primeiro o que mais merece atenção.

### Performance

Para uma assessoria com 500 atletas e 30 dias de histórico de sessions (~ 5k sessions), o RPC executa em < 200 ms em postgres dev (Supabase free tier). Único índice novo necessário seria `idx_workout_delivery_items_group_status_confirmed` (parcial em `confirmed_at`), mas o índice `idx_delivery_items_group_batch` existente cobre o caso comum.

### Segurança

- `SECURITY DEFINER` + `search_path = public, pg_temp`.
- `REVOKE FROM PUBLIC`, `GRANT TO authenticated`.
- Role gate: `admin_master`/`coach`/`assistant` do grupo.
- `STABLE` (read-only, nunca toca `coin_ledger`/`wallets` — L04-07-OK).

### CI guard

`tools/audit/check-coach-daily-digest.ts` (~60 asserts) valida toda a superfície: signature, security definer, STABLE, search_path, grants, time windows, signal definitions, bucket priority, score weights, capping, envelope JSONB e self-test runtime.

### Próximo passo (não bloqueador)

`GET /api/coaching/[groupId]/daily-digest` chama o RPC; UI renderiza 4 colunas com priorização. Tracked como L23-02-presenter, fora do escopo deste finding.

## Teste de regressão
- `npm run audit:coach-daily-digest` — todos os asserts.
- Smoke test: criar grupo com 10 atletas, popular sessions/workout_delivery_items, executar `SELECT fn_coach_daily_digest(group_id)` como coach autenticado, validar shape e contagens.

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23, item 23.2).
- `2026-04-23` — Fixed via migration aditiva `20260421740000_l23_02_coach_daily_digest.sql` (RPC SECURITY DEFINER + STABLE + bucketing prioritário com 6 sinais e score-based capping) + CI guard `audit:coach-daily-digest`. Backward-compatible: nenhuma alteração de schema; UI legada continua funcionando, RPC é opt-in.
