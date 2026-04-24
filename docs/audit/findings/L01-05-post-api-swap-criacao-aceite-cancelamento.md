---
id: L01-05
audit_ref: "1.5"
lens: 1
title: "POST /api/swap — Criação/aceite/cancelamento"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "rate-limit", "mobile", "portal", "observability"]
files:
  - portal/src/app/api/swap/route.ts
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 8046248
owner: platform+security
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Rate-limit por-ação em `portal/src/app/api/swap/route.ts`
  (commit 8046248, K7): action=accept ganha sub-bucket
  dedicado (3/min/group) em cima do POST-global (10/min)
  para impedir race-accept de ofertas recém-criadas. Bucket
  por `groupId` autenticado (IP é fallback apenas para
  requisições sem grupo, o que `requireAdminMaster()` já
  bloqueia upstream). `onMissingRedis: "fail_closed"` segue
  política L01-21/L02-15 (financeiro fecha quando Redis
  indisponível). Observabilidade (`logger.error` com
  `{action, groupId}`) já estava no caminho por L17-01
  (withErrorHandler universal). Book público é decisão
  de produto (L09 B2B marketplace) — não-bug, não-fix.
---
# [L01-05] POST /api/swap — Criação/aceite/cancelamento
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** PORTAL
**Personas impactadas:** Assessorias compradora e vendedora
## Achado
`portal/src/app/api/swap/route.ts:141-143` engole toda exceção em genérico "Operação falhou. Tente novamente." com `console.error` (não `logger.error`). Sentry não recebe o erro → observabilidade cega.
  - `getOpenSwapOffers(auth.groupId)` (linha 70) passa o `groupId` como `excludeGroupId`, mas **qualquer admin_master autenticado consegue ver TODAS as ofertas de todos os outros grupos** — isso é por design (marketplace B2B), porém expõe volumes e preços praticados por concorrentes. Verificar se é tratado pela `LENTE 9 — CRO`.
  - `amount_usd` validado `min(100) max(500_000)` — mas não há rate limit específico para `accept` (rate limit é global para POST, 10/min). Um agressor autenticado pode tentar race-accept de ofertas que ainda estão sendo precificadas.
## Risco / Impacto

Observabilidade comprometida em produção (erros financeiros invisíveis). Competidores enxergando book de ofertas pode ser leak de inteligência comercial.

## Correção proposta

Substituir `console.error` por `logger.error("swap operation failed", e, { action, groupId })`.
  - Adicionar rate limit separado para `action=accept`: 3/min/group.
  - Avaliar com produto se quer book público de ofertas ou matching privado (ver LENTE 9.1).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.5).