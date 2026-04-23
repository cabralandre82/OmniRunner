---
id: L04-10
audit_ref: "4.10"
lens: 4
title: "Transferência internacional de dados (Supabase US, Sentry US) sem cláusulas"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["lgpd", "observability", "reliability"]
files:
  - docs/compliance/DATA_TRANSFER.md
  - tools/audit/check-data-transfer.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-data-transfer.ts
linked_issues: []
linked_prs:
  - local:c8ac7f0
owner: platform
runbook: docs/compliance/DATA_TRANSFER.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Published docs/compliance/DATA_TRANSFER.md with per-processor rows
  (Supabase sa-east-1, Sentry US, Vercel edge, Resend/SendGrid US,
  Stripe US, Asaas BR, Strava US, GitHub US), each with DPA status,
  SCCs stance, data categories, retention, and LGPD Art. 33 legal
  basis. Records the 2026-03 Supabase migration to sa-east-1 that
  eliminated the largest single transfer volume; remaining US
  transfers (observability + payments + Strava) each documented
  individually. ANPD Resolução CD/ANPD nº 19/2024 SCCs incorporated
  by reference; fallback bases declared (consent for Strava,
  contract execution for Stripe). Change procedure requires DPO
  delegate approval + ROPA parity. CI guard audit:data-transfer
  (22 invariants) enforces processor list, regions, Sentry PII
  cross-link, LGPD/ANPD references, change procedure, and decision
  log. Follow-up L04-10-ropa-parity tracks ROPA delivery.
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