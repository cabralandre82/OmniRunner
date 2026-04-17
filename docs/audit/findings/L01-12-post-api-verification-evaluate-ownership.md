---
id: L01-12
audit_ref: "1.12"
lens: 1
title: "POST /api/verification/evaluate — Ownership"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["idempotency", "rate-limit", "mobile", "portal", "reliability"]
files:
  - portal/src/app/api/verification/evaluate/route.ts
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
# [L01-12] POST /api/verification/evaluate — Ownership
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** PORTAL
**Personas impactadas:** Atleta (verificação de autenticidade)
## Achado
`portal/src/app/api/verification/evaluate/route.ts:38-73` valida role (`admin_master | coach`) e verifica que o `user_id` pertence ao grupo como `athlete`. Idempotente (reexecuta regras). Rate limit aplicado. Bom padrão.
## Correção proposta

N/A. Esse é o padrão que deve ser replicado em `[1.11]`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.12).