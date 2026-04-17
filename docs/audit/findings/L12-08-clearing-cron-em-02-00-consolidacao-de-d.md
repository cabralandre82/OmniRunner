---
id: L12-08
audit_ref: "12.8"
lens: 12
title: "clearing-cron em 02:00 — consolidação de D-1 antes de fim do dia"
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
# [L12-08] clearing-cron em 02:00 — consolidação de D-1 antes de fim do dia
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Aggregator consolida ledger de "a semana". Usuário que queima moeda às 01:55 está na agregação; às 02:05 está fora. Jitter no horário do job pode cruzar a fronteira.
## Correção proposta

— Função agrega com `WHERE created_at < date_trunc('day', now())` (estritamente < início de hoje UTC). Documento "cutoff = 00:00 UTC" no runbook.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.8).