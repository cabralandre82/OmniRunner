---
id: L22-20
audit_ref: "22.20"
lens: 22
title: "Retenção D30/D90 — hooks específicos"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "cron", "personas", "athlete-amateur"]
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
# [L22-20] Retenção D30/D90 — hooks específicos
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Streak + badges cobrem D7. Falta motivador D30+: "aniversário de 1 mês no app", "sua evolução" comparativa.
## Correção proposta

— `lifecycle-cron` dispara notificação especial em D30/D90/D180/D365 com wrapped-lite.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.20]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.20).