---
id: L03-15
audit_ref: "3.15"
lens: 3
title: "Pedido eternamente pendente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "webhook", "cron"]
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
# [L03-15] Pedido eternamente pendente
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Atleta
## Achado
`custody_deposits.status='pending'` sem cron que expira. Em casos reais, Stripe pode enviar webhook muito depois, ou nunca.
## Correção proposta

Cron `expire-stale-deposits` que marca `status='expired'` após 48h sem confirmação. Separar de `refunded` (que exige ação explícita).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.15).