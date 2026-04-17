---
id: L01-02
audit_ref: "1.2"
lens: 1
title: "POST /api/custody/withdraw — Criação e execução de saque em um único request"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "anti-cheat", "mobile", "portal", "testing", "reliability"]
files:
  - portal/src/app/api/custody/withdraw/route.ts
  - portal/src/lib/custody.ts
  - portal/src/lib/fx/quote.ts
  - portal/e2e/business-flow-financial.spec.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L01-02] POST /api/custody/withdraw — Criação e execução de saque em um único request
> **Lente:** 1 — CISO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Plataforma (CFO), Assessoria
## Achado
`portal/src/app/api/custody/withdraw/route.ts:19` aceita **`fx_rate` vindo do cliente** (`z.number().positive()`), sem validar contra nenhuma fonte autoritativa (BCB/ECB/Stripe FX quote).
  - Combinado com `portal/src/lib/custody.ts:231-243` (`convertFromUsdWithSpread` usa literalmente o rate do cliente), um admin_master malicioso pode sacar USD com `fx_rate = 10.0` (normal BRL≈5.5), recebendo 2× em BRL.
  - `executeWithdrawal` é chamado logo após `createWithdrawal` (linha 104) — saque é finalizado em um único request, sem passo de aprovação com validação externa do rate.
## Risco / Impacto

Fraude financeira direta por admin_master comprometido ou malicioso. Escala: até USD 1M por request (limite do schema), multiplicado pelo erro de rate. Quebra a invariante D_i = R_i + A_i quando o `total_deposited_usd -= amount_usd` usa USD nominal mas o payout local sai inflado.

## Correção proposta

1. Remover `fx_rate` do schema de entrada. Buscar rate em server-side de fonte autoritativa (`portal/src/lib/fx/quote.ts` — criar; consultar Stripe FX API ou BCB PTAX).
  2. Separar em duas etapas: `POST /api/custody/withdraw` cria pendente com rate congelado e `executeWithdrawal` exige aprovação por `PLATFORM_ADMIN` (não admin_master) em `/api/platform/custody/approve-withdraw`.
  3. Adicionar limite diário por grupo via `platform_fee_config` (`max_withdrawal_per_day_usd`).
  ```typescript
  const withdrawSchema = z.object({
    amount_usd: z.number().min(1).max(100_000),  // reduzir ceiling
    target_currency: z.enum(["BRL", "EUR", "GBP"]).default("BRL"),
    provider_fee_usd: z.number().min(0).max(100).optional(),
    // fx_rate removido
  });
  // ...
  const fxRate = await fetchAuthoritativeFxRate(parsed.data.target_currency);
  ```

## Teste de regressão

`portal/e2e/business-flow-financial.spec.ts` — tentar POST com `fx_rate` no body → 400 "Unknown field"; conferir que saque pendente exige 2ª aprovação.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.2).