---
id: L21-15
audit_ref: "21.15"
lens: 21
title: "Weather enrichment (sessão histórica)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["personas", "athlete-pro"]
files: []
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
# [L21-15] Weather enrichment (sessão histórica)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Pace no calor ≠ pace no frio; não há temperatura registrada por sessão.
## Correção proposta

— Pós-processamento via OpenWeather API; armazenar `sessions.weather jsonb`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.15).