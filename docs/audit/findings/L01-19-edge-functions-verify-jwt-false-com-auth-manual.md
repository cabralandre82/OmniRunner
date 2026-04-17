---
id: L01-19
audit_ref: "1.19"
lens: 1
title: "Edge Functions — verify_jwt = false com auth manual"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["rls", "security-headers", "edge-function", "migration"]
files:
  - supabase/functions/_shared/auth.ts
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
# [L01-19] Edge Functions — verify_jwt = false com auth manual
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Todos os chamadores de Edge Functions
## Achado
`supabase/functions/_shared/auth.ts:60-70` usa `createClient(url, serviceKey, { global: { headers: { Authorization: Bearer <userJwt> } } })` + `verifyClient.auth.getUser(jwt)` para validar manualmente.
## Risco / Impacto

Developers podem confiar no "user-scoped client" e deixar queries cross-tenant exploitáveis. É um tapete mental perigoso.

## Correção proposta

Renomear `db` para `adminDbScopedToUser` e documentar que RLS não se aplica. Alternativa: criar cliente separado só com JWT do usuário (sem service key) e migrar chamadas gradualmente, validando que queries ainda funcionam com RLS.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.19]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.19).