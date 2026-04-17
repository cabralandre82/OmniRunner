---
id: L11-09
audit_ref: "11.9"
lens: 11
title: "GitHub Actions sem OIDC para deploys"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal"]
files: []
correction_type: code
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
# [L11-09] GitHub Actions sem OIDC para deploys
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `SUPABASE_SERVICE_ROLE_KEY` usada em `portal.yml:117`. Mesmo para E2E, seria melhor ter um service-role de staging injetado via OIDC + curto-tempo.
## Correção proposta

— `permissions: id-token: write` + OIDC provider → Supabase Vault tem passo "emit short-lived token".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.9).