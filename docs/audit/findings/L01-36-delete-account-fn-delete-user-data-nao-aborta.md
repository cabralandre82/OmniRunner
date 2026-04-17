---
id: L01-36
audit_ref: "1.36"
lens: 1
title: "delete-account — fn_delete_user_data não-aborta no erro"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "finance", "performance"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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