---
id: L01-15
audit_ref: "1.15"
lens: 1
title: "JWT expiry window — Logout forçado"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal", "edge-function", "migration", "reliability"]
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