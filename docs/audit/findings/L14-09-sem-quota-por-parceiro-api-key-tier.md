---
id: L14-09
audit_ref: "14.9"
lens: 14
title: "Sem quota por parceiro (API key tier)"
severity: medium
status: duplicate
wave: 2
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["partner-api", "rate-limit"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 8046248

owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: L16-03
deferred_to_wave: null
note: |
  Fechado como **duplicate de L16-03** ("sem API pública para
  parceiros B2B", critical em Onda 0). A demanda de quota por
  parceiro (API key tier free/pro/enterprise + scopes + quota
  diária) só faz sentido depois que L16-03 entregar o
  `api_keys` table + middleware de auth de parceiro. Quando
  esse trabalho começar, este finding será rastreado dentro da
  spec de L16-03 — duplicar aqui seria criar drift.
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