---
id: L10-07
audit_ref: "10.7"
lens: 10
title: "Zero-trust entre microserviços — Edge Functions confiam no JWT sem validar audience"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal", "edge-function"]
files:
  - supabase/functions/_shared/auth.ts
correction_type: code
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
# [L10-07] Zero-trust entre microserviços — Edge Functions confiam no JWT sem validar audience
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/_shared/auth.ts` valida JWT mas não valida `aud` claim específica. Qualquer JWT válido do Supabase acessa qualquer função.
## Correção proposta

— JWT assinado com `aud=omni-runner-mobile` ou `aud=omni-runner-portal` + validação por-função de quem pode chamar o quê.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.7).