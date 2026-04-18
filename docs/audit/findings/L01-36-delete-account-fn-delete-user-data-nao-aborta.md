---
id: L01-36
audit_ref: "1.36"
lens: 1
title: "delete-account — fn_delete_user_data não-aborta no erro"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["lgpd", "finance", "edge-function", "audit-trail"]
files:
  - supabase/functions/delete-account/index.ts
  - supabase/functions/_shared/account_deletion.ts
  - supabase/migrations/20260417300000_account_deletion_log.sql
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
duplicate_of: L04-02
deferred_to_wave: null
note: |
  Mesmo root cause de **L04-02** (CLO lens). Resolvido conjuntamente:
  o pipeline de `delete-account` agora retorna 500 com `DATA_CLEANUP_FAILED`
  e **não** chama `auth.admin.deleteUser` quando `fn_delete_user_data`
  falha. O cancelamento de `challenge_participants` recebe o mesmo
  tratamento (falha → abort). O motivo do abort é gravado em
  `account_deletion_log.failure_reason` para investigação por SRE/DPO.
  Ver L04-02 para detalhes completos da fix.
---
# [L01-36] delete-account — fn_delete_user_data não-aborta no erro
> **Lente:** 1 — CISO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Usuário deletando conta (LGPD)
## Achado
`delete-account/index.ts:57-64`: se `fn_delete_user_data` falhar, só loga — **mas depois deleta o auth user (linha 70)**. Resultado: user existe em várias tabelas (sessions, coin_ledger, challenge_participants) mas auth record sumiu. Dados órfãos / LGPD comprometido.
## Risco / Impacto

Violação de LGPD "direito ao esquecimento". Também: orphan data acumula.

## Correção proposta

Abortar pipeline se `fn_delete_user_data` falhar:
  ```typescript
  if (cleanupErr) {
    return jsonErr(500, "DATA_CLEANUP_FAILED", "Cannot safely delete auth record", requestId);
  }
  ```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.36]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.36).