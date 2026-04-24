---
id: L01-22
audit_ref: "1.22"
lens: 1
title: "GET /terms, GET /privacy, outras rotas públicas"
severity: na
status: not-reproducible
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["legal", "portal"]
files:
  - "portal/src/lib/route-policy.ts"
  - "portal/src/middleware.ts"
  - "docs/PRIVACY_POLICY_STUB.md"
  - "docs/TERMOS_OPERACIONAIS.md"
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: rotas /terms e /privacy não existem no portal. Conteúdo legal vive em docs/."
---
# [L01-22] GET /terms, GET /privacy, outras rotas públicas
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** 🔍 not-reproducible
**Camada:** PORTAL
**Personas impactadas:** Visitantes

## Achado original
Middleware não lista `/terms` nem `/privacy` em `PUBLIC_ROUTES`. Se existirem, bloqueia visitantes não autenticados. Verificar se existem.

## Re-auditoria 2026-04-24

### Busca por páginas
`Glob portal/src/app/**/{terms,privacy}/**/page.tsx` → **0 arquivos**. Também validado:

- `portal/src/app/terms/` → não existe
- `portal/src/app/privacy/` → não existe
- `portal/src/app/legal/` → não existe

### Conteúdo legal atual
Vive em `docs/` (não exposto via web):
- `docs/PRIVACY_POLICY_STUB.md`
- `docs/TERMOS_OPERACIONAIS.md`

APIs LGPD relacionadas (`/api/lgpd/*`) **não existem** no portal. O fluxo de exclusão de conta é via Edge Function `delete-account` invocada pelo app (ver `profile_data_service.dart:54-56`).

### Conclusão
**Rotas não existem, nada a corrigir no middleware.** Quando páginas públicas de termos/privacidade forem criadas (exigência para publicação nas stores e LGPD Art. 9), adicionar ao `PUBLIC_ROUTES` em `portal/src/lib/route-policy.ts`.

**Watchdog**: ao criar `/terms` ou `/privacy`, o CI deve falhar se não forem adicionadas a `PUBLIC_ROUTES` (rota autenticada quebra SEO de TOS). Considerar um teste `route-policy.test.ts` que enumera `portal/src/app` procurando páginas com palavras-chave `terms|privacy|legal|cookies` e exige que estejam em `PUBLIC_ROUTES`.

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.22]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.22).
- `2026-04-24` — Re-auditoria confirmou que as rotas não existem no codebase. Flipped para `not-reproducible` com watchdog documentado.
