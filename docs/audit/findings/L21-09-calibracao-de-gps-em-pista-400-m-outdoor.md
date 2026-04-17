---
id: L21-09
audit_ref: "21.9"
lens: 21
title: "Calibração de GPS em pista (400 m outdoor)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["gps", "personas", "athlete-pro"]
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
# [L21-09] Calibração de GPS em pista (400 m outdoor)
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Em pista de atletismo, GPS tem erro lateral 3-5 m → 200 m medidos viram 195 ou 212. Elite rodando 1500m em tartan quer distância exata.
## Correção proposta

— Modo "pista 400m" com auto-lap a cada volta por GPS fit + correção determinística (cada lap = 400 m). Ou BLE sensor de passos/cadência mais preciso que GPS em pista fechada.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.9).