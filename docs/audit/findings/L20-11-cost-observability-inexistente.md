---
id: L20-11
audit_ref: "20.11"
lens: 20
title: "Cost observability inexistente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["observability"]
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
# [L20-11] Cost observability inexistente
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Vercel + Supabase + Sentry + Upstash + Firebase + Resend/Postmark + outros — custos crescem invisível.
## Correção proposta

— Mensal: CSV de invoice via APIs; planilha com cost-per-user-active; alertar quando cost/MAU cresce > 20% MoM.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.11).