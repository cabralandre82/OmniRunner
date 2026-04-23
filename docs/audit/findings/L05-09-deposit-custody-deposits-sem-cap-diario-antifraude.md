---
id: L05-09
audit_ref: "5.9"
lens: 5
title: "Deposit custody_deposits — sem cap diário antifraude"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "migration", "antifraud", "aml", "custody"]
files:
  - supabase/migrations/20260421180000_l05_09_custody_daily_deposit_cap.sql
  - portal/src/app/api/custody/route.ts
  - portal/src/app/api/platform/custody/[groupId]/daily-cap/route.ts
correction_type: migration
test_required: true
tests:
  - tools/test_l05_09_custody_daily_cap.ts
  - portal/src/app/api/custody/route.test.ts
  - portal/src/app/api/platform/custody/[groupId]/daily-cap/route.test.ts
linked_issues: []
linked_prs:
  - d2cf37f14678c1c8e196e0957ab48d2c141a71ad
owner: cfo+ciso
runbook: docs/runbooks/CUSTODY_DAILY_CAP_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-09] Deposit custody_deposits — sem cap diário antifraude
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** custody · **Personas impactadas:** admin_master, platform_admin, CFO

## Achado original
Não havia limite por grupo/dia de depósitos em `custody_deposits`. Um
admin_master comprometido (ou a chave service_role vazada para um grupo
específico) podia depositar US$ 10M de uma vez, lavando dinheiro
através da plataforma — sem custo material para o atacante.

## Correção entregue (2026-04-21)

### Schema
- `custody_accounts.daily_deposit_limit_usd numeric(14,2) DEFAULT 50000.00`
  com `CHECK (>= 0)`.
- `custody_accounts.daily_limit_timezone text DEFAULT 'America/Sao_Paulo'`
  (per-account TZ — produto BR-first mas portátil para outros mercados).
- `custody_accounts.daily_limit_updated_at` + `daily_limit_updated_by`
  para forensics.
- `custody_daily_cap_changes` (audit table dedicada, indexada por
  `(group_id, changed_at DESC)` — query CFO mais barata que filtrar
  `portal_audit_log`).

### Funções RPC (SECURITY DEFINER, lock_timeout='2s')
- `fn_check_daily_deposit_window(group_id, amount_usd)` STABLE — preview
  read-only. Devolve `current_total / limit / available / would_exceed
  / window_start_utc / window_end_utc / timezone`. Útil para o frontend
  e debugging.
- `fn_apply_daily_deposit_cap(group_id, amount_usd)` — guardrail; RAISES
  `P0010 DAILY_DEPOSIT_CAP_EXCEEDED` se ultrapassaria o teto.
  `service_role` only.
- `fn_set_daily_deposit_cap(group_id, new_cap, actor, reason)` — atualiza
  cap + grava 1 row em `custody_daily_cap_changes`. `reason >= 10 chars`
  (postmortem obrigatório).

### Wiring
- `fn_create_custody_deposit_idempotent` chama `fn_apply_daily_deposit_cap`
  no **miss-path** APENAS. Replays idempotentes (`was_idempotent=true`)
  retornam o deposit existente sem re-cobrar (o budget já foi consumido
  na criação original).
- `POST /api/custody` mapeia `P0010` → HTTP 422
  `error.code = "DAILY_DEPOSIT_CAP_EXCEEDED"` com hint apontando para
  o runbook.
- `GET|PATCH /api/platform/custody/[groupId]/daily-cap` (novo endpoint
  platform-admin) — GET retorna account+window+history; PATCH atualiza
  cap via `fn_set_daily_deposit_cap` (idempotency required + audit log).

### Política contábil
- Janela conta `status IN ('pending', 'confirmed')`. `failed`/`refunded`
  NÃO contam. Reverter via `reverse_custody_deposit_atomic` (L03-13)
  libera budget no mesmo dia.
- Janela definida pelo TZ da conta. Default `America/Sao_Paulo` →
  `00:00 BRT = 03:00 UTC`. Endpoint expõe `window_start_utc` para o
  cliente referenciar.

## Cobertura de testes

**Sandbox PG (`tools/test_l05_09_custody_daily_cap.ts`)**: 19 testes
✅ — schema/RLS/grants, window arithmetic (pending/failed/refunded
counting), guardrail (cross-group isolation), idempotency interaction
(replay safe even if cap=0, cap raised mid-day), audit trail
(reason validation).

**Vitest unitário (`portal/.../route.test.ts`)**:
- `custody/route.test.ts` — 16 testes ✅ incluindo P0010 mapping para 422
  (com e sem error.code), pass-through de erros não-P0010 para
  `withErrorHandler` (500 INTERNAL_ERROR canônico).
- `platform/custody/[groupId]/daily-cap/route.test.ts` — 16 testes ✅
  cobrindo GET happy path, PATCH happy path com audit, validações
  (UUID inválido, reason curta, cap negativo, cap acima do ceiling 10M,
  campos extras strict), 401/403, error mapping P0001/P9999.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.9]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.9).
- `2026-04-21` — Fix entregue: migration + endpoint platform admin +
  runbook + 51 testes (19 PG sandbox + 32 Vitest).
