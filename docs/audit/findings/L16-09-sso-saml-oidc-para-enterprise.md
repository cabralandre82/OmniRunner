---
id: L16-09
audit_ref: "16.9"
lens: 16
title: "SSO SAML/OIDC para enterprise"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
files: []
correction_type: config
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
# [L16-09] SSO SAML/OIDC para enterprise
> **Lente:** 16 — CAO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Supabase Auth suporta SAML Enterprise plan. Não configurado. Assessorias grandes com AD corporativo forçadas a criar login individual.
## Correção proposta

— Em expansão enterprise: Supabase SSO + `identity_providers` table por group_id.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.9).