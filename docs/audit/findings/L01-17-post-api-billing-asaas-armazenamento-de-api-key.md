---
id: L01-17
audit_ref: "1.17"
lens: 1
title: "POST /api/billing/asaas — Armazenamento de API Key"
severity: critical
status: fixed
wave: 0
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "backend", "security", "vault", "migration", "secrets"]
files:
  - portal/src/app/api/billing/asaas/route.ts
  - portal/src/app/(portal)/settings/payments/page.tsx
  - portal/src/app/(portal)/settings/payments/payments-client.tsx
  - portal/src/lib/billing/edge-cases.ts
  - supabase/functions/asaas-sync/index.ts
  - supabase/functions/asaas-batch/index.ts
  - supabase/functions/asaas-webhook/index.ts
  - supabase/functions/billing-reconcile/index.ts
  - supabase/migrations/20260417210000_asaas_vault_secrets.sql
  - tools/integration_tests.ts
correction_type: code
test_required: true
tests:
  - tools/integration_tests.ts
linked_issues: []
linked_prs:
  - "commit:35be23a"
owner: unassigned
runbook: docs/audit/runbooks/L01-17-asaas-vault-rotation.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L01-17] POST /api/billing/asaas — Armazenamento de API Key
> **Lente:** 1 — CISO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** 🟢 fixed
**Camada:** PORTAL + BACKEND
**Personas impactadas:** Assessoria (admin_master)
## Achado
`portal/src/app/api/billing/asaas/route.ts` (linhas 80-103) armazena `api_key` do Asaas em `payment_provider_config.api_key` **em texto puro**. A Asaas API Key permite emitir cobranças, consultar clientes e iniciar transferências.
  - Não há indicação de criptografia na inserção (`.upsert({ api_key: apiKey, ... })`). Nenhuma migration adiciona `api_key_encrypted`.
## Risco / Impacto

Se o banco vazar, TODAS as API Keys Asaas das assessorias vazam. Um atacante pode criar cobranças em nome da assessoria ou fazer sacar fundos da conta Asaas.

## Correção implementada

**Migration**: `supabase/migrations/20260417210000_asaas_vault_secrets.sql`

1. **Vault de segredos** (extensão `supabase_vault`, AEAD encryption via pgsodium).
   Colunas novas em `payment_provider_config`:
   - `api_key_secret_id uuid` → `vault.secrets.id`
   - `webhook_token_secret_id uuid` → `vault.secrets.id`
2. **Helpers (RPCs SECURITY DEFINER, search_path + lock_timeout hardened):**
   - `fn_ppc_save_api_key(group_id, api_key, environment, request_id)` — admin_master/coach ou service_role
   - `fn_ppc_get_api_key(group_id, request_id)` — service_role only
   - `fn_ppc_save_webhook_token(group_id, webhook_id, token, request_id)` — service_role only
   - `fn_ppc_get_webhook_token(group_id, request_id)` — service_role only
   - `fn_ppc_has_api_key(group_id)` — metadata sem expor secret (UI flag)
3. **Audit log** `public.payment_provider_secret_access_log(group_id, secret_kind, action, actor_user_id, actor_role, request_id, accessed_at)`. Cada create/rotate/read é registrado. RLS permite admin_master/coach ler apenas o próprio grupo.
4. **Backfill** idempotente: rows existentes com `api_key`/`webhook_token` texto-puro são transferidas para o vault antes do drop.
5. **Drop** das colunas plaintext — material secreto nunca mais aparece em dump/replica/logical backup a partir desta migration.
6. **Authz trivalent-safe**: `IF auth.uid() IS NULL OR v_caller_role NOT IN (...)` (não depende de `NULL NOT IN (...)` que retorna NULL, não TRUE).

**Callers refatorados** para usar as RPCs:
- `supabase/functions/asaas-sync/index.ts` — resolve api_key via `fn_ppc_get_api_key`; setup_webhook grava via `fn_ppc_save_webhook_token`.
- `supabase/functions/asaas-batch/index.ts` — api_key via RPC.
- `supabase/functions/asaas-webhook/index.ts` — valida incoming token contra `fn_ppc_get_webhook_token`.
- `supabase/functions/billing-reconcile/index.ts` — api_key via RPC em cada iteração.
- `portal/src/app/api/billing/asaas/route.ts` — `save_config` delega a `fn_ppc_save_api_key`.
- `portal/src/lib/billing/edge-cases.ts` — `canActivateBilling` checa `api_key_secret_id` em vez de `api_key`.

**Rotação**: re-chamar `fn_ppc_save_api_key` com o novo valor → `vault.update_secret()` preserva `secret_id` (zero impacto em FKs lógicas). Runbook em `docs/audit/runbooks/L01-17-asaas-vault-rotation.md`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.17).
- `2026-04-17` — Correção implementada (migration + refactor 4 Edge Functions + portal route + 9 integration tests + runbook).
- `2026-04-17` — E2E green (`tools/validate-migrations.sh --run-tests` 165/165 + 146/146; inclui os 9 testes L01-17). Promovido a `fixed` (commit `35be23a`).