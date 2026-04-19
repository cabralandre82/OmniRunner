---
id: L18-08
audit_ref: "18.8"
lens: 18
title: "Edge Functions vs Route Handlers — responsabilidade duplicada"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "mobile", "portal", "edge-function"]
files:
  - portal/src/app/api/distribute-coins/route.ts
  - supabase/functions/_shared/wallet_credit.ts
  - supabase/functions/_shared/wallet_credit.test.ts
  - supabase/functions/challenge-withdraw/index.ts
  - supabase/functions/settle-challenge/index.ts
  - supabase/migrations/20260419140000_l18_canonical_wallet_credit.sql
correction_type: code
test_required: true
tests:
  - supabase/functions/_shared/wallet_credit.test.ts
linked_issues: []
linked_prs:
  - "commit:38f9c72"
owner: backend
runbook: docs/runbooks/WALLET_MUTATION_GUARD_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Solução em três camadas atacando o achado original ("dois caminhos
  que fazem coisas parecidas, mantidos separadamente") e desentupindo
  dois bugs latentes que estavam escondidos no caminho Edge.

  (1) **Migration `20260419140000_l18_canonical_wallet_credit.sql`** —
  re-cria `fn_increment_wallets_batch` corrigindo dois bugs introduzidos
  por L18-01 ao re-deployar o RPC sem alinhar com o schema de L19-01:

      • INSERT em `coin_ledger` escrevia apenas `created_at`
        (timestamptz, legado), mas L19-01 fez `created_at_ms` (bigint)
        `NOT NULL` sem default. Qualquer caller em schema fresh ou
        após restore de pg_dump teria falhado com `null value in column
        "created_at_ms"` na primeira liquidação de challenge — bug que
        nunca disparou em prod só porque migrations rodaram em ordem
        com dados pré-existentes.

      • `(v_entry->>'ref_id')::uuid` assumia a coluna uuid legada;
        L19-01 mudou para text. Cast funciona hoje (callers passam UUIDs
        de challenge.id) mas FAIL-CLOSED no momento que algum caller
        passa composite key `idem:user:nonce` (padrão L18-02). Removido.

  Nova RPC aceita ref_id como text, escreve `created_at_ms`, encaminha
  `issuer_group_id` opcional, valida user_id+delta upfront com
  `INVALID_USER_ID`/`INVALID_DELTA` (P0001), e mantém `set_config(
  'app.wallet_mutation_authorized', 'yes', true)` na entrada (L18-01
  guard preservado). Surface das callers existentes inalterada.

  (2) **`supabase/functions/_shared/wallet_credit.ts`** — entry point
  único `creditWallets(adminDb, entries, ctx)` para toda mutação de
  wallet em Edge Function:

      • Pré-flight valida shape (UUID v4 regex em user_id e
        issuer_group_id, delta inteiro non-zero, reason no allowlist
        que espelha `coin_ledger_reason_check`, ref_id text 1-200
        chars opcional) — falha-rápido SEM round-trip de rede,
        retornando discriminated-union `{ ok: true, processed }` |
        `{ ok: false, code, message, details }` com 8 códigos típados.

      • Loga linha estruturada JSON com `request_id`/`fn`/
        `entry_count`/`total_delta`/`outcome`+`pg_code` em falha —
        parseável pelo log-shipper existente, grep-by-request-id
        trivial em postmortem.

      • Transport-agnostic — caller mapeia `result.ok=false` para
        seu HTTP shape (REFUND_FAILED 500, etc).

  (3) **Migração de 3 call-sites**: `challenge-withdraw` (refund),
  `settle-challenge` (refund cooperativo no-runners + settlement
  competitivo) — substituem `.rpc("fn_increment_wallets_batch", ...)`
  raw por `creditWallets(adminDb, entries, ctx)`. Comportamento
  preservado.

  Cobertura: 29 Deno tests em `wallet_credit.test.ts` — toda branch
  de erro typed (8 INVALID_*), validation short-circuit (zero RPC
  call), RPC happy-path payload shape, RPC error path com pg_code
  propagation, log line structure, `ALLOWED_REASONS` parity. Todos
  passam com `deno test`. Suite portal **1085/0** sem regressão.

  O guard L18-01 continua sendo a fronteira de segurança no DB — toda
  tentativa de UPDATE direto a `wallets.balance_coins` é rejeitada
  com `WALLET_MUTATION_FORBIDDEN` (P0007). Esta camada apenas torna
  óbvio (e tipado) o caminho correto na borda Edge.
---
# [L18-08] Edge Functions vs Route Handlers — responsabilidade duplicada
> **Lente:** 18 — Principal Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `distribute-coins` tem versão em `portal/src/app/api/distribute-coins/route.ts` E existe função `fn_increment_wallets_batch` chamada por Edge Functions. Dois caminhos que fazem coisas parecidas, mantidos separadamente.
## Risco / Impacto

— Mudança de regra de negócio em um path esquece o outro. Divergência.

## Correção proposta

— **Canonical path**: tudo financeiro flui por RPC Postgres. Route Handler e Edge Function ambos apenas validam + chamam RPC. Business logic 100% no banco (SECURITY DEFINER funcs).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.8).