---
id: L20-07
audit_ref: "20.7"
lens: 20
title: "Backup testado — zero evidence"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "testing", "reliability"]
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
# [L20-07] Backup testado — zero evidence
> **Lente:** 20 — SRE · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Supabase PITR habilitado por default (verificar!), mas **processo de restore nunca testado** em game-day.
## Risco / Impacto

— "Temos backup" é crença não-validada até o dia do disaster.

## Correção proposta

— Quarterly restore drill:

1. Provisionar novo Supabase project (sandbox).
2. Restore PITR de T-24h.
3. Validar tabela-chave: `SELECT COUNT(*) FROM coin_ledger` == snapshot esperado.
4. Runbook `DR_PROCEDURE.md` atualizado após cada drill.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.7).