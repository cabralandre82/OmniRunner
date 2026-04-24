---
id: L01-15
audit_ref: "1.15"
lens: 1
title: "JWT expiry window — Logout forçado"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "edge-function", "migration", "reliability"]
files:
  - docs/security/JWT_REVOCATION_POLICY.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: security+platform
runbook: docs/security/JWT_REVOCATION_POLICY.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Política ratificada em `docs/security/JWT_REVOCATION_POLICY.md`.
  Decisão: **2-layer revocation** (refresh-token kill via
  `auth.admin.signOut(uid, "global")` + L01-26 cache eviction)
  em vez de tabela `revoked_tokens`. Worst-case window cai para
  0 s em endpoints platform/group-scoped (cache invalidado →
  next request bate o DB e vê o rebaixamento de role) e fica
  limitado ao access-token TTL (≤ 5 min mobile / ≤ 60 min portal)
  em endpoints self-data. Edge Function `force-signout` é
  follow-up não-blocking; hooks de cache já estão em produção.
---
# [L01-15] JWT expiry window — Logout forçado
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** PORTAL + BACKEND
**Personas impactadas:** Atleta suspenso, Coach banido
## Achado
Supabase padrão: JWT expira em 3600s. Não vi configuração customizada. Um admin_master banido mantém acesso até expiração. **Não há tabela de `revoked_tokens`** (contrário ao projeto Clinipharma referência).
## Risco / Impacto

Janela de 1h de acesso livre após revogação de role/ban. Aceitável para a maioria dos casos, mas inaceitável para admin_master comprometido.

## Correção proposta

Adicionar tabela `revoked_sessions(jti_hash text primary key, revoked_at)` e checar no middleware antes do step 2. Alternativa mais simples: chamar `supabase.auth.admin.signOut(user_id)` via Edge Function quando role é removida, forçando refresh token inválido.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.15).