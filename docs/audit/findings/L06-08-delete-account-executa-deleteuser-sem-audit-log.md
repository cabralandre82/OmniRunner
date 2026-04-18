---
id: L06-08
audit_ref: "6.8"
lens: 6
title: "delete-account executa deleteUser sem audit_log"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["edge-function", "audit-trail", "lgpd"]
files:
  - supabase/functions/delete-account/index.ts
  - supabase/functions/_shared/account_deletion.ts
  - supabase/migrations/20260417300000_account_deletion_log.sql
  - tools/integration_tests.ts
  - docs/runbooks/ACCOUNT_DELETION_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - supabase/functions/_shared/account_deletion.test.ts
  - tools/integration_tests.ts
linked_issues: []
linked_prs:
  - "commit:5de4d0d"
owner: platform
runbook: docs/runbooks/ACCOUNT_DELETION_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido junto com L04-02. Nova tabela
  `public.account_deletion_log` recebe um INSERT logo após validação
  de admin_master e ANTES de qualquer mutação (cancel challenges /
  fn_delete_user_data / auth.admin.deleteUser), garantindo que toda
  tentativa de auto-exclusão deixa rastro mesmo em caso de crash.

  Para preservar a privacidade do email original (que será removido
  do `auth.users`), persistimos apenas seu `email_hash` (SHA-256
  hex de 64 chars, lowercase+trim) — o helper `hashEmail` em
  `supabase/functions/_shared/account_deletion.ts` é determinístico
  e tem cobertura por unit-tests com vetor SHA-256 NIST.

  Ao final, um UPDATE registra `outcome` (success / cleanup_failed /
  auth_delete_failed / internal_error / cancelled_by_validation),
  `failure_reason` (truncado, sem PII) e `cleanup_report`
  (jsonb retornado por `fn_delete_user_data`). Trigger
  `account_deletion_log_immutable` rejeita reescrita das colunas
  terminais. RLS limita SELECT a `platform_role='admin'`.

  O runbook `docs/runbooks/ACCOUNT_DELETION_RUNBOOK.md` documenta
  como responder a inquéritos ANPD ("apaguei essa conta?") usando o
  email_hash.
---
# [L06-08] delete-account executa deleteUser sem audit_log
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/delete-account/index.ts` nunca escreve em `audit_logs` antes nem depois. Após exclusão não há trilha de "fulano solicitou auto-exclusão em 2026-04-15".
## Risco / Impacto

— Investigação futura (fraude, dispute) sem trilha.

## Correção proposta

— `INSERT INTO audit_logs(action, actor_id, target_user_id, metadata, created_at) VALUES ('user.self_delete.initiated', uid, uid, jsonb_build_object('ip', ip, 'ua', ua), now())` antes e `'user.self_delete.completed'` depois. Como audit_log retém apenas `user_id` (anonimizado) pelo [4.7], manter `metadata->>'email_hash'` (SHA-256 do email original).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.8).