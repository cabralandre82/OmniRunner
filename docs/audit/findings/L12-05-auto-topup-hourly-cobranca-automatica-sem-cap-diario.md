---
id: L12-05
audit_ref: "12.5"
lens: 12
title: "auto-topup-hourly — cobrança automática sem cap diário"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["edge-function", "migration", "antifraud", "billing", "cron"]
files:
  - "supabase/migrations/20260421200000_l12_05_auto_topup_daily_cap.sql"
  - "supabase/functions/auto-topup-check/index.ts"
  - "portal/src/app/api/auto-topup/route.ts"
  - "portal/src/app/(portal)/settings/auto-topup-form.tsx"
  - "portal/src/lib/schemas.ts"
correction_type: migration
test_required: true
tests:
  - "tools/test_l12_05_auto_topup_daily_cap.ts"
  - "portal/src/app/api/auto-topup/route.test.ts"
  - "portal/src/app/(portal)/settings/auto-topup-form.test.tsx"
  - "portal/src/lib/schemas.test.ts"
linked_issues: []
linked_prs:
  - "73d871f"  # fix(auto-topup): daily cap antifraud guardrail (L12-05)
owner: platform-billing
runbook: "docs/runbooks/AUTO_TOPUP_DAILY_CAP_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L12-05] auto-topup-hourly — cobrança automática sem cap diário
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** Edge Functions / Billing
**Personas impactadas:** atletas / clubes (vítimas da cobrança indevida); CFO (refund + reconciliação); suporte (atendimento ao cliente desconfiado).

## Achado original
"Roda de hora em hora. Se settings do atleta mal-configurado (bug ou ataque), pode cobrar 24×/dia."

### Por quê isso era exploitável
O `auto-topup-cron` chamava `auto-topup-check` para cada grupo `enabled=true`
de hora em hora. As salvaguardas pré-fix eram:

1. **Cooldown 24h** via `last_triggered_at` — porém **atualizado APÓS** o
   `stripe.paymentIntents.create` retornar. Isso abria uma janela de race
   de 5–30s (latência da Stripe) durante a qual N invocações concorrentes
   liam `last_triggered_at = NULL` e todas passavam o gate.
2. **Cap mensal** (`max_per_month`, default 3, máximo absoluto 10). Cobre
   o caso "X cobranças/mês" mas **não** o caso "Y cobranças em 1 dia".
3. **Sem cap diário em BRL absoluto** — um pacote default ~R$ 200 × 24
   cobranças/dia = **R$ 4.800/dia** indevidos no cartão do cliente.
   Refund manual via Stripe + suporte a um cliente desconfiado é caro
   (ticket P1) e desgasta a relação comercial.

O `auto-topup-check` também é invocado **inline** após cada token-debit
(ver header da fn). Burst de N debits em <1min → N invocações paralelas
→ todas passam cooldown via race.

## Fix entregue
**Defesa em profundidade — cap diário em **dois eixos** (BRL e contagem).**

### Migration (`supabase/migrations/20260421200000_l12_05_auto_topup_daily_cap.sql`)

- Adiciona 5 colunas em `billing_auto_topup_settings`:
  - `daily_charge_cap_brl numeric(10,2) NOT NULL DEFAULT 500.00`
  - `daily_max_charges integer NOT NULL DEFAULT 3` (CHECK 1..24 — cron é hourly)
  - `daily_limit_timezone text NOT NULL DEFAULT 'America/Sao_Paulo'`
  - `daily_limit_updated_at timestamptz`
  - `daily_limit_updated_by uuid → auth.users(id)`
- Cria `billing_auto_topup_cap_changes` (audit table) com FK +
  RLS (admin_master OR platform admin) + UNIQUE partial em
  `(group_id, idempotency_key)`.
- 3 RPCs novas (`SECURITY DEFINER`, `search_path = public, pg_temp`):
  - `fn_check_auto_topup_daily_window(group, charge_brl)` — preview
    read-only (count, total, available, would_exceed_count, would_exceed_total).
  - `fn_apply_auto_topup_daily_cap(group, charge_brl)` — guardrail
    `RAISE P0010` AUTO_TOPUP_DAILY_CAP_EXCEEDED se contagem **OR**
    total exceder cap. HINT estruturada com runbook reference.
  - `fn_set_auto_topup_daily_cap(group, cap_brl, max_charges, actor,
    reason, tz?, idempotency_key?)` — atomicamente atualiza settings
    + grava audit row. Reason >= 10 chars obrigatória, idempotente
    via UNIQUE partial.
- DO block self-test verifica schema + audit table + 3 funções
  registradas (falha o deploy se algo regredir).

### Edge Function (`supabase/functions/auto-topup-check/index.ts`)

`fn_apply_auto_topup_daily_cap` é invocada **antes** de
`stripe.paymentIntents.create`, **fechando a race condition**:

- P0010 → `{ triggered: false, reason: 'daily_cap_reached', detail: HINT }`
  + `product_event 'billing_auto_topup_blocked_daily_cap'` (CFO/painel).
- 42883 (function does not exist em deploy progressivo) → WARN +
  segue (fail-soft), evita derrubar o cron em janela de deploy.
- Outros erros propagam para o catch externo.

### Portal API (`portal/src/app/api/auto-topup/route.ts`)

- Zod `autoTopupSchema` ganha 4 campos opcionais
  (`daily_charge_cap_brl`, `daily_max_charges`, `daily_limit_timezone`,
  `daily_cap_change_reason`) com `superRefine` exigindo reason >= 10
  chars sempre que **qualquer** `daily_*` é tocado.
- Mudanças nos campos `daily_*` **não** vão pelo direct UPDATE; passam
  pelo RPC `fn_set_auto_topup_daily_cap` (audit-trailed). Suporta
  header `x-idempotency-key`.
- Erros traduzidos: P0001 → 400, P0002 → 404, default → 500.

### UI (`portal/src/app/(portal)/settings/auto-topup-form.tsx`)

- Seção "Limites diários de antifraude (avançado)" via `<details>`,
  visível apenas quando `hasStripePaymentMethod` (faz sentido apenas
  para grupos que **conseguem** ser cobrados).
- 3 inputs (cap BRL, max charges, TZ) + textarea de reason que aparece
  somente quando `dailyCapDirty`. Client-side gate antes do POST.

### Tests

| Arquivo | Cobertura |
| --- | --- |
| `tools/test_l12_05_auto_topup_daily_cap.ts` | 26 testes integração: schema, RPCs, guardrail (count + total), cross-group isolation, idempotência, audit trail, validação de inputs |
| `portal/src/app/api/auto-topup/route.test.ts` | +6 testes: rejeição sem reason, RPC invocation, idempotency-key forwarding, P0001/P0002 → HTTP, no-RPC quando nenhum daily_* enviado |
| `portal/src/lib/schemas.test.ts` | +9 testes Zod: bounds, superRefine, sanity ceilings |
| `portal/src/app/(portal)/settings/auto-topup-form.test.tsx` | +5 testes UI: visibilidade condicional, client-side gate, payload correto |

## Operação
Runbook: [`docs/runbooks/AUTO_TOPUP_DAILY_CAP_RUNBOOK.md`](../../runbooks/AUTO_TOPUP_DAILY_CAP_RUNBOOK.md).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.5]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.5).
- `2026-04-21` — **Fix entregue** em commit `73d871f`. Defesa em profundidade
  com cap dual (BRL + contagem), TZ-aware, RPC atomizada e audit trail.
