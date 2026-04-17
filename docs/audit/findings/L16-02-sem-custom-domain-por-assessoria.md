---
id: L16-02
audit_ref: "16.2"
lens: 16
title: "Sem custom domain por assessoria"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files: []
correction_type: process
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
# [L16-02] Sem custom domain por assessoria
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Todos acessam `portal.omnirunner.app`. Clube grande quer `portal.corredoresmorumbi.com.br`.
## Correção proposta

—

1. `coaching_groups.custom_domain text UNIQUE`.
2. Next.js middleware mapeia Host → group_id.
3. Vercel API: adicionar domain programaticamente via API `POST /v9/projects/.../domains`.
4. Auto-provisionar SSL (Let's Encrypt via Vercel).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.2).