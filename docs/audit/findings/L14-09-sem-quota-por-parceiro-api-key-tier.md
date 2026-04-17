---
id: L14-09
audit_ref: "14.9"
lens: 14
title: "Sem quota por parceiro (API key tier)"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
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
# [L14-09] Sem quota por parceiro (API key tier)
> **Lente:** 14 — Contracts · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Mesmo se amanhã abrir API para parceiros, não há `api_keys` table com `tier` (free/pro/enterprise), quota diária, scopes.
## Correção proposta

— Já coberto em LENTE 16 ([16.3]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.9).