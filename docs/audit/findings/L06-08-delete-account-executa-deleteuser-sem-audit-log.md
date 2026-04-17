---
id: L06-08
audit_ref: "6.8"
lens: 6
title: "delete-account executa deleteUser sem audit_log"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["anti-cheat", "edge-function", "performance"]
files:
  - supabase/functions/delete-account/index.ts
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