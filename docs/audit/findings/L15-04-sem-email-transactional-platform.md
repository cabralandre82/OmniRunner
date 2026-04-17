---
id: L15-04
audit_ref: "15.4"
lens: 15
title: "Sem email transactional platform"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "edge-function", "reliability"]
files: []
correction_type: config
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
# [L15-04] Sem email transactional platform
> **Lente:** 15 — CMO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Grep `resend|postmark|sendgrid|mailgun` em `portal/src` e Edge Functions → zero provider integrado. Supabase Auth envia email de confirmação via SMTP padrão (quota limitada).
## Risco / Impacto

— Notificações importantes ("seu withdraw foi processado") não chegam ou caem em spam.

## Correção proposta

— Integrar Resend ou Postmark; templates versionados em `supabase/email-templates/`; log de entregas.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.4).