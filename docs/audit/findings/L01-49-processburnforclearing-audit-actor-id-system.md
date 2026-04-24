---
id: L01-49
audit_ref: "1.49"
lens: 1
title: "processBurnForClearing — Audit actor_id = \"system\""
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "portal", "audit", "fixed"]
files:
  - portal/src/lib/clearing.ts
  - portal/src/lib/audit.ts
  - supabase/migrations/20260421780000_l01_49_audit_log_actor_kind.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - supabase/migrations/20260421780000_l01_49_audit_log_actor_kind.sql
linked_issues: []
linked_prs:
  - ba3c71e
  - aa816fb
  - 8c62f60
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — audit_log schema change: portal_audit_log.actor_id was
  `UUID NOT NULL REFERENCES auth.users(id)`. auditLog({ actorId: "system" })
  was failing the cast and the row was lost (only logger.error). Fix:
    • new actor_kind text NOT NULL DEFAULT 'user'
    • actor_id is now NULLABLE
    • CHECK guarantees user⇒actor_id NOT NULL, system⇒actor_id NULL
  audit.ts now detects actorId === "system" and writes actor_id=NULL,
  actor_kind='system'. Existing rows backfilled to actor_kind='user'.
---
# [L01-49] processBurnForClearing — Audit actor_id = "system"
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Auditoria
## Achado
`portal/src/lib/clearing.ts:147, 161`: audit insere `actorId: "system"`. Isso é uma string não-UUID em `actor_id uuid` — **deve falhar** com cast error. Ou o schema de `portal_audit_log.actor_id` é `text`? Não verifiquei.
## Risco / Impacto

Audit log perdido (fail silent no `.catch` do `auditLog`).

## Correção proposta

Verificar schema de `portal_audit_log`. Se `actor_id` é UUID, usar `null` + novo campo `is_system_action bool`. Se é text, manter.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.49]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.49).