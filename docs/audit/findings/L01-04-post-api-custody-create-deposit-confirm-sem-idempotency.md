---
id: L01-04
audit_ref: "1.4"
lens: 1
title: "POST /api/custody (create deposit / confirm) — Sem idempotency-key"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "idempotency", "webhook", "security-headers", "mobile", "portal"]
files:
  - supabase/migrations/20260417260000_custody_deposit_idempotency.sql
  - portal/src/lib/custody.ts
  - portal/src/lib/custody.test.ts
  - portal/src/app/api/custody/route.ts
  - portal/src/app/api/custody/route.test.ts
  - portal/src/lib/concurrency.test.ts
  - portal/src/lib/qa-e2e.test.ts
  - tools/integration_tests.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/custody.test.ts
  - portal/src/app/api/custody/route.test.ts
  - tools/integration_tests.ts
linked_issues: []
linked_prs: ["commit:b0dd775"]
owner: platform
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Implementação L01-04 (2026-04-17):

  1. **Schema** (`supabase/migrations/20260417260000_custody_deposit_idempotency.sql`):
     - `custody_deposits.idempotency_key text` (nullable p/ legacy).
     - UNIQUE parcial `(group_id, idempotency_key) WHERE idempotency_key IS NOT NULL` —
       protege durante TODA a janela do request, não só após gateway responder
       (corrige limitação da UNIQUE em `payment_reference WHERE NOT NULL`).

  2. **RPC `fn_create_custody_deposit_idempotent`**:
     - SECURITY DEFINER + search_path travado.
     - Hit barato via SELECT antes de INSERT.
     - Race entre 2 requests concorrentes resolvido via `EXCEPTION WHEN
       unique_violation` que re-SELECT a row vencedora.
     - Validações de entrada (key >= 8 chars, amount > 0, gateway whitelist).
     - Retorna `was_idempotent` para o caller distinguir criação vs replay.
     - `lock_timeout = 2s` (consistência L19-05).

  3. **RPC `confirm_custody_deposit(uuid, uuid)`** — DROP single-arg, CREATE
     dual-arg. Match `WHERE id = p_deposit_id AND group_id = p_group_id` no
     mesmo SELECT do FOR UPDATE. Mensagem de erro genérica
     ("Deposit not found, wrong group, or already processed") defende contra
     **enumeration de UUIDs cross-group** por admin malicioso. `lock_timeout = 2s`.

  4. **Portal** (`portal/src/lib/custody.ts`):
     - `createCustodyDeposit(group, amount, gateway, idempotencyKey)` — assinatura
       quebrante; agora chama RPC e retorna `{ deposit, wasIdempotent }`.
     - `confirmDeposit(depositId, groupId)` — exige `groupId`; propagado pelo
       caller (route handler usa `auth.groupId` do cookie).
     - `confirmDepositByReference` (webhook gateway) — agora também busca
       `group_id` na row e propaga para `confirmDeposit`.

  5. **Route** (`portal/src/app/api/custody/route.ts`):
     - **EXIGE** header `x-idempotency-key`. Rejeita 400 sem header
       (`code: IDEMPOTENCY_KEY_REQUIRED`) ou formato inválido
       (`IDEMPOTENCY_KEY_INVALID`).
     - Aceita UUID v4 ou opaque `[A-Za-z0-9_-]{16,128}` (ULID/nanoid).
     - Passa `auth.groupId` para `confirmDeposit` (cross-group block).
     - Retorna `{ deposit, idempotent: bool }` + header `Idempotent-Replayed: true`
       em replays (convenção alinhada com Stripe).
     - Audit log só registra criação real (replays não inflam o log).
     - `depositSchema`/`confirmSchema` agora `.strict()` — rejeita campos extras
       (defesa em profundidade contra body injection).

  6. **Invariants** (in-migration DO block):
     - 4a/4b: garante coluna + UNIQUE criados.
     - 4c: smoke test idempotency hit (2 chamadas com mesma chave → mesmo deposit).
     - 4d: smoke test confirm com group_id correto.
     - 4e: cleanup das rows de smoke (não polui prod).

  7. **Testes** (3 layers):
     - Unit (`portal/src/lib/custody.test.ts`): nova RPC mock, wasIdempotent=true/false,
       confirm com group_id (24 tests).
     - Route (`portal/src/app/api/custody/route.test.ts`): rejeita sem key, valida formato,
       Idempotent-Replayed header, cross-group propagation (13 tests).
     - Integration (`tools/integration_tests.ts`): 3 testes E2E com Postgres real
       — replay returns same id, cross-group blocked, non-existent generic error.

  Resultado: 149/149 integration, 792/792 unit, lint+tsc verdes.

  Defense-in-depth contra:
    a) Double-click no botão "Comprar" (UI quase sempre dispara 2 requests).
    b) Network retry após timeout (cliente não sabe se deu certo).
    c) Replay attack autenticado com body válido (idempotency key bloqueia).
    d) Admin malicioso de grupo A confirmando depósito do grupo B
       (RPC valida ownership; caller obriga via cookie).
    e) Enumeration de UUIDs por timing/error message.
---
# [L01-04] POST /api/custody (create deposit / confirm) — Sem idempotency-key
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** PORTAL
**Personas impactadas:** Assessoria (admin_master)
## Achado
`portal/src/app/api/custody/route.ts:60-146` cria depósito sem `idempotency-key` do cliente. Double-click cria dois registros `custody_deposits` PENDING.
  - A coluna `UNIQUE` em `payment_reference` (migration `20260228170000_custody_gaps.sql:33`) é **parcial `WHERE payment_reference IS NOT NULL`** — portanto não protege depósitos enquanto o reference é `NULL` (antes do gateway retornar).
  - `confirmDeposit(depositId)` chamado sem verificação de ownership (embora use `SECURITY DEFINER`, não recebe `group_id` do caller para cross-check).
## Risco / Impacto

Um admin_master pode, com conluio, chamar `confirm_custody_deposit` via RPC directa (se tiver acesso) e creditar sem pagar (verificar se a RPC confirma sem verificar gateway). Mais realista: duplicação cria UX ruim e possíveis dois checkouts pendentes abandonados.

## Correção proposta

Exigir header `x-idempotency-key` no POST de deposit; criar `deposit_idempotency` table ou reutilizar `custody_deposits.idempotency_key` com UNIQUE.
  - Em `confirmDeposit`, alterar signature para `confirmDeposit(depositId, groupId)` e validar em SQL: `WHERE id=p_deposit_id AND group_id=p_group_id`.

## Teste de regressão

`portal/src/app/api/custody/route.test.ts` — dois POSTs com mesmo idempotency-key devem retornar o mesmo deposit_id.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.4).
- `2026-04-17` — Resolvido: idempotency-key + cross-group enforcement via nova RPC + assinatura quebrante de `confirmDeposit`. Ver `note` para detalhes.