---
id: L09-07
audit_ref: "9.7"
lens: 9
title: "Política de reembolso/chargeback sem prazo SLA"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["edge-function"]
files:
  - supabase/migrations/20260421430000_l09_07_refund_sla.sql
  - docs/compliance/REFUND_POLICY.md
  - tools/audit/check-refund-sla.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - local:9813af4
owner: platform-finance
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Extended `public.billing_refund_requests` with `sla_target_at`,
  `sla_breached_at`, `sla_breach_reason`. A BEFORE INSERT trigger
  `trg_billing_refund_requests_set_sla_target` sets the target to
  48 business hours (or 72h for weekend intake). Historical rows
  were backfilled. `public.v_billing_refund_requests_breached`
  (security_invoker) surfaces open-and-overdue requests; idempotent
  helper `fn_billing_refund_sla_mark_breached(uuid, text)` stamps
  the breach and logs to `public.audit_logs`. CDC Art. 49
  cooling-off commitment, 2026 holiday calendar, and decision log
  live in `docs/compliance/REFUND_POLICY.md`. 34 static invariants
  enforced via `npm run audit:refund-sla`.
---
# [L09-07] Política de reembolso/chargeback sem prazo SLA
> **Lente:** 9 — CRO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Vincula-se a [2.13]. Não há política documentada: "reembolso em até X dias". Código Defesa Consumidor Art. 49 exige 7 dias para arrependimento em vendas remotas.
## Correção proposta

— Implementar `process-refund` Edge Function (já existe em `supabase/functions/process-refund/`) para que deposite reverso + emitir NFS-e de estorno. Configurar SLA: estorno < 48 h úteis.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.7).