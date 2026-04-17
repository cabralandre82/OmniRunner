---
id: L22-05
audit_ref: "22.5"
lens: 22
title: "Grupos locais sem descoberta por proximidade"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "personas", "athlete-amateur"]
files: []
correction_type: code
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
# [L22-05] Grupos locais sem descoberta por proximidade
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Amador descobre clube via boca-a-boca. Sem `/groups/nearby` que mostra grupos < 5 km home.
## Correção proposta

— `coaching_groups.base_location geography(POINT)` + endpoint `GET /api/groups/nearby?lat=…&lng=…&radius_km=10`. Privacy: amador aprova compartilhamento de localização aproximada.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.5).