---
id: L04-10
audit_ref: "4.10"
lens: 4
title: "Transferência internacional de dados (Supabase US, Sentry US) sem cláusulas"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "observability", "reliability"]
files:
  - docs/compliance/DATA_TRANSFER.md
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
# [L04-10] Transferência internacional de dados (Supabase US, Sentry US) sem cláusulas
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Supabase está hospedado em AWS US-East (padrão). Sentry DSN aponta `sentry.io` (EU/US). LGPD Art. 33 exige cláusulas-padrão ou decisão ANPD quando transferindo para país sem adequação.
## Risco / Impacto

— Processo administrativo ANPD. Não é bloqueio, mas é pendência contratual.

## Correção proposta

— Documento `docs/compliance/DATA_TRANSFER.md` com DPA Supabase + DPA Sentry + registro no ROPA (Registro de Operações). Considerar migrar Supabase para região sa-east-1.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.10).