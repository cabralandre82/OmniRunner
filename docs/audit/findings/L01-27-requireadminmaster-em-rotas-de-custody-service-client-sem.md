---
id: L01-27
audit_ref: "1.27"
lens: 1
title: "requireAdminMaster em rotas de custody — Service client sem RLS"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: ["finance", "rls", "mobile", "portal", "migration"]
files: []
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
# [L01-27] requireAdminMaster em rotas de custody — Service client sem RLS
> **Lente:** 1 — CISO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** PORTAL
**Personas impactadas:** Assessoria
## Achado
`requireAdminMaster` usa `createServiceClient()` (bypass RLS) para checar membership. A lógica em TS replica o que RLS faria. **Ressalva:** toda a segurança agora depende desse helper. Se alguém esquecer de chamar `requireAdminMaster` em um novo endpoint `/api/custody/xyz`, o endpoint fica totalmente aberto.
## Correção proposta

Criar middleware de rota tipo-seguro `withAdminMaster(handler)` wrapping, ou exportar um `createRouteHandler` que obriga o check.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.27]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.27).