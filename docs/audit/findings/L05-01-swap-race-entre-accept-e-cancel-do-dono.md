---
id: L05-01
audit_ref: "5.1"
lens: 5
title: "Swap: race entre accept e cancel do dono da oferta"
severity: critical
status: fixed
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "atomicity", "portal", "migration", "testing", "concurrency"]
files:
  - supabase/migrations/20260417180000_swap_cancel_race_hardening.sql
  - portal/src/lib/swap.ts
  - portal/src/lib/swap.test.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/app/api/swap/route.test.ts
  - tools/integration_tests.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/swap.test.ts
  - portal/src/app/api/swap/route.test.ts
  - tools/integration_tests.ts
linked_issues: []
linked_prs:
  - "commit:a32a462"
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Override manual Onda 1 → Onda 0: heurística de triage não capturou 'fundos transferidos em oferta cancelada' como perda financeira direta, mas trata-se de double-spend por race em operação financeira ativa. Ver TRIAGE.md seção 'Overrides manuais'."
---
# [L05-01] Swap: race entre accept e cancel do dono da oferta
> **Lente:** 5 — CPO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟢 fixed
**Camada:** DB + PORTAL
**Personas impactadas:** Assessoria (seller), Assessoria (buyer), Plataforma (CFO)

## Achado
`portal/src/app/api/swap/route.ts:117` chama `acceptSwapOffer` e `cancelSwapOffer` sem verificação cruzada. Se Grupo A cria oferta, Grupo B clica em "aceitar" e — no mesmo instante — o Grupo A clica em "cancelar", ambas chamadas tocam `UPDATE swap_orders SET status='…' WHERE id = x`. Quem chegar primeiro "vence", mas não há `FOR UPDATE` ou `status = 'open'` predicate na última vista da migration.

## Risco / Impacto

Oferta marcada "canceled" mas `execute_swap` já movimentou custódia → fundos transferidos numa oferta "cancelada". Mesmo quando a ordem SQL dos locks previne corrupção (execute_swap já usa `FOR UPDATE` + `WHERE status='open'` em pg lock re-check), o cliente não recebe sinal semântico distinguível entre "já cancelado", "já aceito", "não é seu" e "falha transitória" — logo, UX esconde estados ambíguos do admin_master e auditoria perde a causa raiz da falha.

## Correção implementada

### 1. Nova migration `20260417180000_swap_cancel_race_hardening.sql`

**RPC `cancel_swap_order(p_order_id, p_seller_group_id)`** — substitui o UPDATE direto do portal:

- `SECURITY DEFINER` + `SET search_path = public, pg_temp` (L18-03) + `SET lock_timeout = '2s'` (L19-05).
- `SELECT ... FOR UPDATE` atômico na linha. Se `execute_swap` está concorrente, uma das duas transações vence; a outra observa o estado commit-visível no re-check.
- Checks em ordem: `SWAP_NOT_FOUND` → `SWAP_NOT_OWNER` → `SWAP_NOT_OPEN`.
- **SQLSTATE distinguíveis**: P0002 (not_found), P0003 (not_owner), P0001 (not_open). O status atual vai no `HINT` da exceção P0001 (para o portal mostrar "oferta já está cancelled/settled").
- Retorna `(order_id, previous_status, new_status, cancelled_at)` — permite audit log mostrar transição real.
- `REVOKE EXECUTE ... FROM anon` (service_role + authenticated only).

**Refactor `execute_swap`** — mantém exatamente a lógica transacional anterior (FOR UPDATE em swap_orders, locks de custody_accounts em ordem UUID determinística para prevenir deadlocks, debit/credit/revenue/state transition), mas:

- Substitui `RAISE EXCEPTION 'Swap order not found or no longer open'` genérico por 4 SQLSTATE distinguíveis:
  - `P0001` SWAP_NOT_OPEN (status ≠ open; hint = status atual)
  - `P0002` SWAP_NOT_FOUND
  - `P0003` SWAP_SELF_BUY
  - `P0004` SWAP_INSUFFICIENT_BACKING
- Adiciona `SET search_path` (L18-03 compliant) e `SET lock_timeout = '2s'` (L19-05 — antes só aplicado via ALTER FUNCTION).
- `REVOKE EXECUTE FROM anon` (alinha com L01-17 postura de anon sem acesso a RPCs financeiras).

**Invariante final** na migration: falha se `cancel_swap_order` ou `execute_swap` acabar sem `search_path` ou `lock_timeout` configurados — regressão bloqueada no CI.

### 2. `portal/src/lib/swap.ts` — erros tipados

- Nova classe `SwapError` com `code: SwapErrorCode` (`not_found` | `not_open` | `not_owner` | `self_buy` | `insufficient_backing` | `lock_not_available` | `unknown`).
- Função `toSwapError()` converte erro Supabase/Postgres → `SwapError` com base em SQLSTATE + fallback regex de mensagem.
- `cancelSwapOffer` agora chama RPC `cancel_swap_order` e retorna `SwapCancelResult` com `previousStatus` + `newStatus` + `cancelledAt` (antes: `void`, silenciava falha).
- `acceptSwapOffer` propaga `SwapError` em vez de `Error` genérico — caller pode discriminar P0001 vs P0004 sem parsing.

### 3. `portal/src/app/api/swap/route.ts` — mapeamento HTTP

- Schemas `.strict()` em create/accept/cancel (defesa em profundidade contra campos extras).
- Novo helper `swapErrorToResponse()` mapeia `SwapErrorCode` → HTTP:
  - `not_found` → **404**
  - `not_open` → **409 Conflict** (com `detail.current_status` no body para UX)
  - `not_owner` → **403**
  - `self_buy` → **400**
  - `insufficient_backing` → **422**
  - `lock_not_available` → **503 + Retry-After: 2** (alinhado com L19-05)
- `auditLog` agora registra tanto `swap.offer.accepted` / `swap.offer.cancelled` (success) quanto `swap.offer.accept_failed` / `swap.offer.cancel_failed` (tentativas rejeitadas) com `code` + `sqlstate` no metadata para forense.
- Response de cancel inclui `previous_status` + `new_status` — observabilidade no front.

### 4. Testes de regressão

- **`portal/src/lib/swap.test.ts`** — expandido de 5 para 18 cases:
  - Mapeamento SQLSTATE → SwapErrorCode para cada um dos 6 códigos + `unknown` fallback.
  - `cancelSwapOffer` usa RPC (não mais UPDATE direto — `mockFrom` nunca é chamado).
  - `current_status` propagado no detail.
  - `P0003` em cancel → `not_owner`, em accept → `self_buy` (mesmo SQLSTATE, contexto discrimina).
  - Edge case: `data` null em cancel → erro "unknown" defensivo.

- **`portal/src/app/api/swap/route.test.ts`** — expandido de 11 para 21 cases:
  - Happy paths (accept, cancel, create) com audit log check.
  - Cada SQLSTATE mapeado para o HTTP correto (404/409/403/400/422/503).
  - `Retry-After: 2` header em 503.
  - `auditLog` NÃO emite sucesso em failure path, emite `*_failed` action.
  - Strict schema rejeita campos extras.
  - `detail.current_status` presente em 409 respose (UX).

- **`tools/integration_tests.ts`** — 4 novos casos:
  - Ambas funções têm `search_path` + `lock_timeout` configurados (regression-blocker).
  - `cancel_swap_order` raises P0002 para UUID inexistente.
  - `cancel_swap_order` raises P0003 quando caller não é seller.
  - Happy path retorna `previous_status='open'` + `new_status='cancelled'`, e 2ª chamada falha com P0001.

Total: **+22 testes** cobrindo todos os caminhos de erro + race semantics.

## Garantias finais

- **Atomicidade**: cancel e accept não podem ambos "ganhar" — `FOR UPDATE` serializa em Postgres.
- **Observabilidade**: toda tentativa (sucesso ou erro) emite audit log estruturado.
- **UX**: cliente recebe `code` + `current_status` e pode mostrar "Oferta já foi aceita" em vez de "Operação falhou".
- **Lock hygiene**: `lock_timeout=2s` evita pile-up sob contenção (L19-05 alignment).
- **Regressão-blocker**: migration falha se alguma função sair sem `search_path`/`lock_timeout`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.1]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.1).
- `2026-04-17` — Fix implementado: `cancel_swap_order` RPC race-safe + `execute_swap` com SQLSTATE distinguíveis + mapeamento HTTP semântico no portal.
- `2026-04-17` — E2E green (`tools/validate-migrations.sh --run-tests` 165/165 + 146/146; teste `cancel_swap_order has search_path and lock_timeout configured` corrigido). Promovido a `fixed` (commit `a32a462`).
