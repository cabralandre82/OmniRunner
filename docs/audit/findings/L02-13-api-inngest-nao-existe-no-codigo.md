---
id: L02-13
audit_ref: "2.13"
lens: 2
title: "/api/inngest — Não existe no código"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["mobile", "portal", "edge-function", "cron"]
files: []
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
# [L02-13] /api/inngest — Não existe no código
> **Lente:** 2 — CTO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** N/A
**Personas impactadas:** —
## Achado
O prompt original referenciava Inngest (Clinipharma). **Omni Runner usa `pg_cron` + Supabase Edge Functions**, não Inngest. Não há `/api/inngest` em `portal/src/app/api/`.
## Correção proposta

N/A (este item não se aplica ao projeto).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.13).