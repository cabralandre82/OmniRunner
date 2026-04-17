---
id: L14-02
audit_ref: "14.2"
lens: 14
title: "Sem versionamento de path (/api/v1)"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "security-headers", "mobile", "migration", "reliability"]
files: []
correction_type: code
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L14-02] Sem versionamento de path (/api/v1)
> **Lente:** 14 — Contracts · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Rotas são `/api/custody`, `/api/swap`, `/api/distribute-coins`. Primeira mudança quebra:

- App mobile versão < atual em campo
- Integração de parceiro B2B
- Scripts internos de BI
## Correção proposta

— Migration gradual:

1. Mover endpoints financeiros críticos (`/api/custody`, `/api/swap`, `/api/distribute-coins`, `/api/clearing`, `/api/custody/withdraw`) para `/api/v1/...`.
2. Retornar header `Sunset: Wed, 01 Jan 2027 00:00:00 GMT` nas rotas sem versão.
3. Responses incluem `X-Api-Version: 1`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.2).