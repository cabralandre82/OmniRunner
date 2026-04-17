---
id: L01-39
audit_ref: "1.39"
lens: 1
title: "CSP — style-src 'unsafe-inline'"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal"]
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
# [L01-39] CSP — style-src 'unsafe-inline'
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
Aceitável para shadcn/ui/Tailwind (compile-time styles). CSS injection tem superfície de risco muito menor que JS.
## Correção proposta

N/A imediata. Considerar migração para nonce em médio prazo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.39]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.39).