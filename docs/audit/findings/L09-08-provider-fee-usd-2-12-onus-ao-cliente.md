---
id: L09-08
audit_ref: "9.8"
lens: 9
title: "provider_fee_usd ([2.12]) — ônus ao cliente ou à plataforma?"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "ux"]
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