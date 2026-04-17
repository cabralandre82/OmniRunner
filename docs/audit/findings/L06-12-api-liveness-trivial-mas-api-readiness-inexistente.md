---
id: L06-12
audit_ref: "6.12"
lens: 6
title: "/api/liveness trivial mas /api/readiness inexistente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal"]
files:
  - portal/src/app/api/liveness/route.ts
correction_type: code
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
# [L06-12] /api/liveness trivial mas /api/readiness inexistente
> **Lente:** 6 — COO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/liveness/route.ts` existe; não há `/api/readiness` (que verifica conectividade a DB + Redis + Stripe sem executar custody invariants).
## Correção proposta

— `readiness` checa `db.from("profiles").select("id").limit(1)` + `getRedis().ping()` + Stripe API heartbeat. Kubernetes/Vercel usa `liveness` (apenas servidor up) vs `readiness` (pode aceitar tráfego).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.12).