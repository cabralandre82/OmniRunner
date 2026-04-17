---
id: L01-13
audit_ref: "1.13"
lens: 1
title: "POST /api/platform/fees — Alteração de taxas"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "rate-limit", "mobile", "portal", "migration", "reliability"]
files:
  - portal/src/app/api/platform/fees/route.ts
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
# [L01-13] POST /api/platform/fees — Alteração de taxas
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL + BACKEND
**Personas impactadas:** Plataforma (platform_admin)
## Achado
`portal/src/app/api/platform/fees/route.ts:9-14` aceita `fee_type` de `["clearing","swap","maintenance","billing_split"]` mas **não inclui `"fx_spread"`**, embora `getFxSpreadRate` em `custody.ts:198-208` consulte a linha `fee_type='fx_spread'`. Resultado: não há UI/endpoint para alterar fx_spread — admin precisa ir direto ao DB. Degradação silenciosa.
  - Rate limit 20/min/IP é ok para mudanças administrativas.
  - Auth via `platform_admins` table (linhas 16-32) é consistente com o modelo.
## Risco / Impacto

Operacional: impossibilidade de ajustar FX spread via UI em caso de crise cambial. Médio.

## Correção proposta

Estender `updateSchema` para `z.enum(["clearing","swap","maintenance","billing_split","fx_spread"])` e espelhar a UI em `portal/src/app/(platform)/platform/fees/page.tsx` (verificar se inclui fx_spread).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.13).