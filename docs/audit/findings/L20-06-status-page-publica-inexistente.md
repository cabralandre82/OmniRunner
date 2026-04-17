---
id: L20-06
audit_ref: "20.6"
lens: 20
title: "Status page pública inexistente"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: []
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
# [L20-06] Status page pública inexistente
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Usuário não tem onde ver "Omni Runner está operacional?". Em outage, support tickets inundam.
## Correção proposta

— `status.omnirunner.com` via Atlassian Statuspage, Better Stack, ou self-hosted Cachet. Feeds consumem Vercel + Supabase + Stripe status APIs + `/api/health`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.6).