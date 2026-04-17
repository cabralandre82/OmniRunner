---
id: L01-14
audit_ref: "1.14"
lens: 1
title: "Sessão Supabase.auth.getSession() no middleware + auth.getUser() em updateSession"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "portal", "performance"]
files:
  - portal/src/lib/supabase/middleware.ts
  - portal/src/middleware.ts
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
# [L01-14] Sessão Supabase.auth.getSession() no middleware + auth.getUser() em updateSession
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Todos os usuários autenticados
## Achado
`portal/src/lib/supabase/middleware.ts:28-30` usa `supabase.auth.getUser()` — **bom**: consulta o servidor do Supabase a cada request, não confia apenas no JWT local. Latência extra (1 roundtrip Supabase).
  - O middleware chama `updateSession` **em toda rota não estática**, incluindo assets do matcher — mas o matcher exclui `_next/static`, `_next/image`, etc. OK.
  - `coaching_members` query (`portal/src/middleware.ts:82-88`) roda a cada request com cookie presente. Sem cache. Para um usuário staff com tráfego alto, isso adiciona 2 queries por request (getUser + coaching_members).
## Risco / Impacto

Performance em cold start. Não é um risco de segurança imediato.

## Correção proposta

Considerar cache curto em `@upstash/redis` de membership (60s) com invalidação em eventos de role change. Manter `getUser()` como está (crítico para logout remoto).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.14).