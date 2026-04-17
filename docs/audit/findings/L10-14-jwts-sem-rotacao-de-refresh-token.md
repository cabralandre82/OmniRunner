---
id: L10-14
audit_ref: "10.14"
lens: 10
title: "JWTs sem rotação de refresh_token"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
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
# [L10-14] JWTs sem rotação de refresh_token
> **Lente:** 10 — CSO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Supabase default: refresh_token "rotation" disponível via setting; não auditado se ativado.
## Correção proposta

— Confirmar em Supabase Dashboard: "Refresh Token Rotation" = `ON`, "Rotation Period" = 10s, "Reuse Interval" = 0.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.14).