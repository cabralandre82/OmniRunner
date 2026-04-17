---
id: L06-11
audit_ref: "6.11"
lens: 6
title: "Secret rotation sem playbook"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["webhook"]
files:
  - docs/SECRET_ROTATION_RUNBOOK.md
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
# [L06-11] Secret rotation sem playbook
> **Lente:** 6 — COO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_WEBHOOK_SECRET`, `MP_WEBHOOK_SECRET`, `ASAAS_API_KEY` são env vars. Não há runbook de rotação, intervalo recomendado, passos para rotação sem downtime.
## Correção proposta

— Runbook `docs/SECRET_ROTATION_RUNBOOK.md`. Todos rotacionados a cada 90 dias (180 para service_role se bloqueio dificultar).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.11).