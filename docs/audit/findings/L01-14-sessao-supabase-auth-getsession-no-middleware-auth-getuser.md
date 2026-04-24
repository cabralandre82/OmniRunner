---
id: L01-14
audit_ref: "1.14"
lens: 1
title: "Sessão Supabase.auth.getSession() no middleware + auth.getUser() em updateSession"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "portal", "performance"]
files:
  - portal/src/lib/supabase/middleware.ts
  - portal/src/middleware.ts
  - portal/src/lib/auth/membership-cache.ts
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 8046248

owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: L01-26
deferred_to_wave: null
note: |
  Fechado como **duplicate de L01-26**. A causa-raiz que o finding
  apontava — "2 queries por request (getUser + coaching_members)" no
  middleware — foi neutralizada pelo trabalho de cache de
  `coaching_members` + `platform_role` introduzido em L01-26
  (`membership-cache.ts` + `platform-role-cache.ts`). Hoje:
  `getUser()` continua server-side (não dá para fazer cache disso —
  é o que garante logout remoto efetivo), mas `coaching_members` é
  servida de cache LRU process-local com TTL curto e invalidação
  ativa em eventos de role change. Em RSC com 15 sub-renders contra
  `/platform/*`, custo cai de 16 round-trips Postgres para 1 (cold)
  ou 0 (warm).
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