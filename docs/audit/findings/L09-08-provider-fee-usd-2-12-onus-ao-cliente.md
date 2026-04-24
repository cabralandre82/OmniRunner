---
id: L09-08
audit_ref: "9.8"
lens: 9
title: "provider_fee_usd ([2.12]) — ônus ao cliente ou à plataforma?"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "migration", "ux"]
files:
  - docs/adr/ADR-0001-provider-fee-ownership.md
  - docs/adr/README.md
  - docs/adr/TEMPLATE.md
  - supabase/migrations/20260421440000_l09_08_billing_fee_policy.sql
  - tools/audit/check-billing-fee-policy.ts
correction_type: config
test_required: false
tests: []
linked_issues: []
linked_prs:
  - local:1f42841
owner: platform-finance
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  ADR-0001 accepts "pass-through by default" for Stripe/Asaas
  gateway fees: CDC Art. 6 III requires clear disclosure and
  unit economics cannot absorb the fee at scale. Database
  support lives in singleton `public.billing_fee_policy`
  (PRIMARY KEY CHECK (id = 1)) with `gateway_passthrough` boolean,
  NOT NULL `disclosure_template` (pt-BR copy), pinned
  `adr_reference = 'ADR-0001'`. RLS forced; SELECT for
  authenticated, FOR ALL for service_role. STABLE SECURITY
  DEFINER `fn_billing_fee_policy()` exposes the row. This PR
  also seeds the `docs/adr/` directory (README + TEMPLATE) for
  future architectural decisions (L09-01, L09-05, L16-03, etc.).
  32 static invariants enforced via
  `npm run audit:billing-fee-policy`.
---
# [L09-08] provider_fee_usd ([2.12]) — ônus ao cliente ou à plataforma?
> **Lente:** 9 — CRO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Assessoria deposita US$ 1000, Stripe cobra US$ 38. Produto não deixa claro se assessoria credita 962 coins (absorve) ou 1000 (plataforma absorve). Contrato de adesão inexistente no repo.
## Risco / Impacto

— Reclamação/processo no PROCON por "cobrança não contratada" se cobrar do cliente sem aviso prévio claro.

## Correção proposta

— Política `platform_fee_config` linha `gateway_passthrough` boolean; UI mostra em tempo real no checkout "Taxa do gateway: US$ X (a seu cargo)". Contrato de adesão apresentado no onboarding com aceite ([4.3]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.8).