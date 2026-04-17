---
id: L02-10
audit_ref: "2.10"
lens: 2
title: "Cold start + timeout Vercel em operações longas"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "edge-function", "cron"]
files:
  - portal/src/lib/supabase/service.ts
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
# [L02-10] Cold start + timeout Vercel em operações longas
> **Lente:** 2 — CTO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Platform admin (relatórios/exports), Coach (batch)
## Achado
`createServiceClient` em `portal/src/lib/supabase/service.ts:7-9` tem timeout de 15s. Operações de batch (`settleWindowForDebtor` em `clearing.ts:296-329`) fazem loop síncrono de `settle_clearing` por settlement pending — para 500 settlements pendentes em uma janela, isso pode exceder 60s mesmo em Vercel Pro.
## Risco / Impacto

Deploys em Vercel Hobby (10s) vão falhar imediatamente em batch settlements. Em Pro (60s), acima de ~300 settlements/batch → função morta silenciosamente, settlements parciais, estado inconsistente.

## Correção proposta

1. Processar em chunks: `LIMIT 50` por invocação, continuação via cron `/api/cron/settle-clearing-batch` a cada minuto.
  2. Para exports: usar Supabase Edge Function (Deno, timeout 150s) em vez de Next.js API.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.10).