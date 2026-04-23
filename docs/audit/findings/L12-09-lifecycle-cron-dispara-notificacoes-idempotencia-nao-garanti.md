---
id: L12-09
audit_ref: "12.9"
lens: 12
title: "lifecycle-cron dispara notificações idempotência não garantida"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["migration", "cron", "notifications", "idempotency"]
files:
  - supabase/migrations/20260421240000_l12_09_notification_idempotency.sql
  - supabase/functions/notify-rules/index.ts
  - supabase/functions/onboarding-nudge/index.ts
  - tools/test_l12_09_notification_idempotency.ts
  - docs/runbooks/NOTIFICATION_IDEMPOTENCY_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l12_09_notification_idempotency.ts
linked_issues: []
linked_prs: ["48b2886"]
owner: coo
runbook: docs/runbooks/NOTIFICATION_IDEMPOTENCY_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L12-09] lifecycle-cron dispara notificações idempotência não garantida
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** Edge Function + migration
**Personas impactadas:** atleta (recebe push duplicado), operador (debug de "por que o mesmo push chegou 2×").

## Achado
`*/5 * * * *` sem tabela `sent_notifications` dedicada.

A infraestrutura pré-existente tinha `notification_log` (criada em
`20260221000003_notification_log.sql`) com PRIMARY KEY `id uuid` e índice
**não-unique** `idx_notification_log_dedup(user_id, rule, context_id, sent_at
DESC)`. O dedup era implementado por `wasRecentlyNotified()` em
`notify-rules/index.ts` e `onboarding-nudge/index.ts`:

```ts
// 1) SELECT lookback de 12h (SEM lock)
if (await wasRecentlyNotified(db, userId, "streak_at_risk", todayKey)) continue;
// 2) dispatchPush() — 5-30s de latência APNs/FCM
const ok = await dispatchPush(...);
// 3) só se ok, grava audit row — outros workers já passaram pelo SELECT
if (ok) await logNotification(db, userId, "streak_at_risk", todayKey);
```

Este é um TOCTOU clássico. Dois cron ticks overlapping (ou cron + operator
trigger manual via `POST /functions/v1/notify-rules`) podem ambos ler zero
rows no passo (1), ambos dispatchar no (2) e ambos gravar no (3) — o índice
não-unique aceita silenciosamente duas rows com mesmo `(user_id, rule,
context_id)`. O atleta recebe a mesma notificação duas vezes.

Além disso, alguns rules usavam `context_id` estático sem time bucket
(`low_credits_alert = 'low_credits:${groupId}'`), contando com a janela de
12h do `wasRecentlyNotified` para "re-firing" em dias subsequentes — o que
significa que **não podíamos** simplesmente adicionar UNIQUE sem também
ajustar as convenções de `context_id` para rules recorrentes.

## Correção aplicada

Fix em 5 camadas (`supabase/migrations/20260421240000_l12_09_notification_
idempotency.sql`, ~350 LOC + refactor de 2 Edge Functions + runbook):

### 1. `ROW_NUMBER()` cleanup histórico

A migration inicia removendo duplicatas pré-existentes antes de adicionar o
UNIQUE (caso contrário `ADD CONSTRAINT` falharia):

```sql
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id, rule, context_id
           ORDER BY sent_at ASC, id ASC
         ) AS rn
    FROM public.notification_log
),
deleted AS (
  DELETE FROM public.notification_log n
   USING ranked r
   WHERE n.id = r.id AND r.rn > 1
  RETURNING 1
)
SELECT COUNT(*) AS rows_deleted FROM deleted;
```

Tiebreak `sent_at ASC, id ASC` — `MIN(id)` não funciona porque id é UUID.

### 2. `UNIQUE (user_id, rule, context_id)`

```sql
ALTER TABLE public.notification_log
  ADD CONSTRAINT notification_log_dedup_unique
  UNIQUE (user_id, rule, context_id);
```

Idempotente via `pg_constraint` lookup (IF NOT EXISTS pattern). Qualquer INSERT
raw que duplicar agora recebe `23505 unique_violation`.

### 3. `fn_try_claim_notification` — race-safe claim primitive

```sql
CREATE OR REPLACE FUNCTION public.fn_try_claim_notification(
  p_user_id uuid, p_rule text, p_context_id text DEFAULT ''
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_inserted int;
BEGIN
  -- arg validation (22023 INVALID_USER_ID / INVALID_RULE)
  INSERT INTO public.notification_log (user_id, rule, context_id)
  VALUES (p_user_id, p_rule, COALESCE(p_context_id, ''))
  ON CONFLICT ON CONSTRAINT notification_log_dedup_unique DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted = 1;
END; $$;
```

Retorna TRUE iff esta chamada inseriu a row (caller dona do dispatch). Dez
workers chamando em paralelo → exatamente um recebe TRUE; nove recebem FALSE.

### 4. `fn_release_notification` — bounded rollback

```sql
CREATE OR REPLACE FUNCTION public.fn_release_notification(
  p_user_id uuid, p_rule text, p_context_id text DEFAULT '',
  p_max_age_seconds integer DEFAULT 60
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$ ... $$;
```

Se o dispatch falha (res.ok=false / timeout / etc.), o caller chama release
para permitir retry no próximo cron tick. **Row mais velha que 60s (bounded)
nunca é deletada** — protege notificações legítimas antigas contra clobber
acidental por caller bugado. `p_max_age_seconds` CHECK 1..300 (5 min hard
cap).

### 5. Refactor de `notify-rules` e `onboarding-nudge`

16 rules em `notify-rules/index.ts` passam do anti-pattern check-then-dispatch
para claim-first:

```ts
// ANTES
if (await wasRecentlyNotified(db, userId, rule, ctx)) continue;
const ok = await dispatchPush(...);
if (ok) await logNotification(db, userId, rule, ctx);

// DEPOIS
const claimed = await tryClaimNotification(db, userId, rule, ctx);
if (!claimed) continue;
const ok = await dispatchPush(...);
if (!ok) await releaseNotificationClaim(db, userId, rule, ctx);
```

**Context-id conventions atualizadas** para rules recorrentes que pré-fix
dependiam da janela de 12h:

| Rule | Pré-fix | Pós-fix | Dedup semântica |
| --- | --- | --- | --- |
| `low_credits_alert` | `low_credits:${groupId}` | `low_credits:${groupId}:${YYYY-MM-DD}` | 1/grupo/dia UTC |
| `challenge_expiring` | `${challengeId}` | `${challengeId}:${YYYY-MM-DD}` | 1/user/desafio/dia (permite re-fire se challenge for estendido) |
| `streak_at_risk`, `inactivity_nudge`, `onboarding_nudge` | já tinham date bucket | (sem mudança) | — |

**Fallback para RPC missing**: ambos `tryClaimNotification` e
`onboarding-nudge` têm try/catch que cai na pattern legacy (SELECT lookback
12h + INSERT com 23505 detection) quando a RPC ainda não está deployada
(graceful degradation em dev DB pré-migration).

### 6. Testes + self-test

**`tools/test_l12_09_notification_idempotency.ts`** — 12 cases via docker exec
psql (evita dependência `pg` no node_modules):

- Schema/DDL (1-4): constraint presente, 2 funções SECURITY DEFINER
  registradas, service_role EXECUTE.
- Argument validation (5-7): NULL user / empty rule / out-of-range max_age
  → 22023.
- Behaviour (8-12): first claim TRUE + insere, duplicate claim FALSE +
  não-insere, release ≤60s deleta, release ≥10min com bound 30s FALSE, raw
  duplicate INSERT → 23505.

12/12 verdes em ~3s. Self-test DO block na própria migration seeda
`auth.users` ephemeral + valida 7 invariantes + cleanup em EXCEPTION block.

### 7. Runbook canônico

**`docs/runbooks/NOTIFICATION_IDEMPOTENCY_RUNBOOK.md`** (~250 linhas, 7
seções):
- Summary + claim-first code pattern
- Operação normal (queries de health)
- 3 cenários operacionais: (A) user reporta push duplicado — triage, (B)
  push esperado não chegou — manual release, (C) cleanup histórico com
  ROW_NUMBER()
- Tabela completa de context-id conventions (17 rules)
- Guide "adicionando nova rule" (event-driven vs recurring)
- Rollback + observability signals
- Cross-refs L06-04/L06-05/L12-03/L15-04

## Validação

- `docker exec -i supabase_db psql < supabase/migrations/20260421240000_l12_09_notification_idempotency.sql`
  → `[L12-09.selftest] OK — all invariants pass`
- `npx tsx tools/test_l12_09_notification_idempotency.ts` → 12/12 passed
- `npx tsx tools/test_l06_05_edge_retry_wrapper.ts` → 18/18 passed (no
  regression)
- `npm run audit:verify` → 348/348

## Backwards compat

100% — migration é aditiva (1 constraint, 2 funções, 0 columns dropped);
Edge Function tem fallback para RPC missing; partial rollback seguro
(`DROP CONSTRAINT notification_log_dedup_unique` libera tudo e behaviour
regressa para pre-fix sem outras quebras).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/12-cron-scheduler.md`](../parts/) — anchor `[12.9]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.9).
- `2026-04-21` — Fix commit `48b2886` (migration 20260421240000 + refactor notify-rules/onboarding-nudge + 12 tests + runbook). Onda 1 → 84/179.
