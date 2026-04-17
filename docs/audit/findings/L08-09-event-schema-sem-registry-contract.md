---
id: L08-09
audit_ref: "8.9"
lens: 8
title: "Event schema sem registry / contract"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/lib/analytics/events.ts
  - docs/analytics/EVENT_CATALOG.md
correction_type: docs
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
# [L08-09] Event schema sem registry / contract
> **Lente:** 8 — CDO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `ProductEvents` é uma classe com constantes. Novos events são criados ad-hoc; sem canonical list nem doc do payload esperado.
## Correção proposta

— `docs/analytics/EVENT_CATALOG.md` + Zod schemas em `portal/src/lib/analytics/events.ts` com tipagem compartilhada entre Flutter (code-gen) e portal.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.9).