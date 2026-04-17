---
id: L03-01
audit_ref: "3.1"
lens: 3
title: "Divergência de fórmula de fee — TS vs SQL"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "mobile", "portal", "migration", "ux"]
files:
  - portal/src/lib/clearing.ts
  - portal/src/lib/money.ts
  - supabase/migrations/20260303100000_gateway_fee_backing_fix.sql
correction_type: migration
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
# [L03-01] Divergência de fórmula de fee — TS vs SQL
> **Lente:** 3 — CFO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** PORTAL + BACKEND
**Personas impactadas:** Plataforma (receita), Assessoria (pagamentos)
## Achado
`portal/src/lib/clearing.ts:115`: `const feeUsd = Math.round(grossUsd * feeRate) / 100;` ← fórmula **legada**.
  - `supabase/migrations/20260303100000_gateway_fee_backing_fix.sql:45-46` mudou `execute_burn_atomic` para `ROUND(v_gross * v_fee_rate / 100, 2)`.
  - `processBurnForClearing` (clearing.ts:57-173) **não é mais chamado** se o fluxo correto usa `executeBurnAtomic` (linha 186-202). Mas o código TS persiste no repo e pode ser chamado por legacy callers.
  - Para `grossUsd = 33.33, feeRate = 3.0`:
    - TS (`Math.round(33.33 * 3.0) / 100`) = `Math.round(99.99) / 100` = `100 / 100` = `1.00`
    - SQL novo (`ROUND(33.33 * 3.0 / 100, 2)`) = `ROUND(0.9999, 2)` = `1.00`
## Risco / Impacto

Divergência entre receita esperada (cálculo TS no portal/UI) e receita real (cálculo SQL durante burn). Centavos por burn × milhares de burns/mês = desvio significativo em relatórios. CFO reporta números diferentes do DB.

## Correção proposta

1. Remover `Math.round(x * y) / 100` e substituir por helper que replica a semântica de `numeric(14,2)`:
  ```typescript
  // portal/src/lib/money.ts
  export function roundCents(value: number): number {
    // Replica Postgres ROUND(value, 2) com banker's rounding
    const x = value * 100;
    const rounded = Math.abs(x % 1) === 0.5
      ? (Math.floor(x) % 2 === 0 ? Math.floor(x) : Math.ceil(x))
      : Math.round(x);
    return rounded / 100;
  }
  export function calcFee(gross: number, ratePct: number): number {
    return roundCents(gross * ratePct / 100);
  }
  ```
  2. Melhor: mover **todo** cálculo financeiro para SQL. TS só exibe valor já calculado.
  3. Adicionar teste property-based que compara cálculo TS vs SQL para 10k valores aleatórios.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.1).