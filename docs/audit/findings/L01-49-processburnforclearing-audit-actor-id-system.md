---
id: L01-49
audit_ref: "1.49"
lens: 1
title: "processBurnForClearing — Audit actor_id = \"system\""
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "portal"]
files:
  - portal/src/lib/clearing.ts
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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