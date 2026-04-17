---
id: L15-05
audit_ref: "15.5"
lens: 15
title: "Sem landing pages SEO-otimizadas"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
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
# [L15-05] Sem landing pages SEO-otimizadas
> **Lente:** 15 — CMO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Portal é "logged app first"; não tem `/running-with-coaches`, `/marathon-training-plan`, etc. Tráfego orgânico search zero.
## Correção proposta

— `/app/(marketing)/[slug]/page.tsx` com MDX + schema.org SportsActivity + sitemap.xml.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.5).